import Foundation
import CryptoKit
import NIOCore
import NIOPosix
import NIOSSH

// A NODE PUT UP FROM THE PHONE, BY ADDRESS, LOGIN AND PASSWORD (the author's word 28.09: «a way into your own node by
// the root login, the password and the IP address»). A machine the person rents stands bare; the phone reaches it the
// one way a bare machine can be reached -- its SSH door -- puts the door of Montana on it (the same source this app
// carries for the shelf), makes it a certificate of its own, and keeps that certificate's digest: from then on the
// phone speaks TLS to the address straight and trusts that digest alone, no name and no authority between them.
//
// SSH here is the admission ticket of an external standard ([I-16]): the machine's own door speaks it and nothing else
// before Montana stands on it. Apple's NIOSSH (swift-nio-ssh) carries it; the password rides once and is kept nowhere;
// the first meeting takes the machine's host key as it is -- the person named the machine by address and password, and
// the door of Montana is what the meeting leaves behind, exactly as the first `ssh` of every operator does.
enum MTSSHError: Error { case noPassword, channel, closed, timeout, refused(Int, String) }

final class MTSSHRun {
    struct Outcome { let status: Int; let out: String; let err: String }
    private final class Auth: NIOSSHClientUserAuthenticationDelegate {
        private let user: String
        private let pass: String
        private var offered = false
        init(_ u: String, _ p: String) { user = u; pass = p }
        func nextAuthenticationType(availableMethods: NIOSSHAvailableUserAuthenticationMethods,
                                    nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>) {
            // One password, offered once: a second ask means the first was refused, and the answer is no more methods.
            guard availableMethods.contains(.password), !offered else { return nextChallengePromise.succeed(nil) }
            offered = true
            nextChallengePromise.succeed(NIOSSHUserAuthenticationOffer(username: user, serviceName: "", offer: .password(.init(password: pass))))
        }
    }
    private final class FirstMeeting: NIOSSHClientServerAuthenticationDelegate {
        func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) { validationCompletePromise.succeed(()) }
    }
    private final class Collector: ChannelInboundHandler {
        typealias InboundIn = SSHChannelData
        var out = [UInt8]()
        var err = [UInt8]()
        private let exit: EventLoopPromise<Int>
        private var settled = false
        init(_ exit: EventLoopPromise<Int>) { self.exit = exit }
        private func settle(_ r: Result<Int, Error>) {
            guard !settled else { return }
            settled = true
            switch r {
            case .success(let s): exit.succeed(s)
            case .failure(let e): exit.fail(e)
            }
        }
        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            let d = unwrapInboundIn(data)
            guard case .byteBuffer(var b) = d.data else { return }
            let bytes = b.readBytes(length: b.readableBytes) ?? []
            if d.type == .channel { out += bytes } else { err += bytes }
        }
        func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
            if let e = event as? SSHChannelRequestEvent.ExitStatus { settle(.success(e.exitStatus)) } else { context.fireUserInboundEventTriggered(event) }
        }
        func errorCaught(context: ChannelHandlerContext, error: Error) { settle(.failure(error)); context.close(promise: nil) }
        func handlerRemoved(context: ChannelHandlerContext) { settle(.failure(MTSSHError.closed)) }
    }

    /// One command on the machine, its standard input handed whole, its output and exit status brought back.
    static func run(host: String, user: String, password: String, command: String, stdin: Data, seconds: TimeInterval) async throws -> Outcome {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { group.shutdownGracefully { _ in } }
        let auth = Auth(user, password)
        let bootstrap = ClientBootstrap(group: group)
            .connectTimeout(.seconds(20))
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    let ssh = NIOSSHHandler(role: .client(.init(userAuthDelegate: auth, serverAuthDelegate: FirstMeeting())),
                                            allocator: channel.allocator, inboundChildChannelInitializer: nil)
                    try channel.pipeline.syncOperations.addHandler(ssh)
                }
            }
        return try await within(seconds) {
            let channel = try await bootstrap.connect(host: host, port: 22).get()
            let ssh = try await channel.pipeline.handler(type: NIOSSHHandler.self).get()
            let exit = channel.eventLoop.makePromise(of: Int.self)
            let collector = Collector(exit)
            let born = channel.eventLoop.makePromise(of: Channel.self)
            ssh.createChannel(born) { child, type in
                guard type == .session else { return child.eventLoop.makeFailedFuture(MTSSHError.channel) }
                return child.eventLoop.makeCompletedFuture { try child.pipeline.syncOperations.addHandler(collector) }
            }
            let child = try await born.futureResult.get()
            try await child.setOption(ChannelOptions.allowRemoteHalfClosure, value: true).get()
            try await child.triggerUserOutboundEvent(SSHChannelRequestEvent.ExecRequest(command: command, wantReply: true)).get()
            if !stdin.isEmpty {
                var buf = child.allocator.buffer(capacity: stdin.count)
                buf.writeBytes(stdin)
                try await child.writeAndFlush(SSHChannelData(type: .channel, data: .byteBuffer(buf))).get()
            }
            try await child.close(mode: .output).get()
            let status = try await exit.futureResult.get()
            try? await child.closeFuture.get()
            try? await channel.close().get()
            return Outcome(status: status, out: String(decoding: collector.out, as: UTF8.self), err: String(decoding: collector.err, as: UTF8.self))
        }
    }
    private static func within<T>(_ s: TimeInterval, _ op: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { g in
            g.addTask { try await op() }
            g.addTask { try await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)); throw MTSSHError.timeout }
            guard let first = try await g.next() else { throw MTSSHError.timeout }
            g.cancelAll()
            return first
        }
    }
}

/// THE SET-UP OF ONE'S OWN NODE: the door's source, the certificate, the unit -- and the digest the phone keeps.
enum MontanaNodeSetup {
    static let tlsPort = 8463   // NOT-UI: the door's own TLS port, beside the plain one a front proxies to
    /// The door this app carries, byte for byte the one deployed (Audit/Internal, lauterbourg-node-store.py).
    static func door() -> Data? {
        Bundle.main.url(forResource: "lauterbourg-node-store", withExtension: "py").flatMap { try? Data(contentsOf: $0) }
    }
    /// What the machine does to itself, as root: the store's own user and folders, the unit, a certificate of its own made
    /// by that user under a closed umask, the port -- and it answers with the certificate's digest. A unit already there
    /// keeps every word it had and gains the shelf.
    static let script = """
set -e
IP="$1"
id montana 2>/dev/null || useradd -r -m -d /var/lib/montana-node-wake -s /usr/sbin/nologin montana
runuser -u montana -- mkdir -p /var/lib/montana-node-wake/blobs /var/lib/montana-node-wake/vault /var/lib/montana-node-wake/tls
python3 - <<'PYEOF'
import os
u = '/etc/systemd/system/montana-node-store.service'
want = {'VAULT_DIR': '/var/lib/montana-node-wake/vault', 'VAULT_TLS_CERT': '/var/lib/montana-node-wake/tls/cert.pem',
        'VAULT_TLS_KEY': '/var/lib/montana-node-wake/tls/key.pem', 'STORE_TLS_PORT': '8463',
        'STORE_DB': '/var/lib/montana-node-wake/tokens.db', 'WAKE_BLOBS': '/var/lib/montana-node-wake/blobs'}
if os.path.exists(u):
    rows = open(u).read().split(chr(10))
    env = {}
    for r in rows:
        if r.startswith('Environment='):
            k, _, v = r[12:].partition('=')
            env[k] = v
    caps = [c for c in env.get('MONTANA_CAPS', '').split(',') if c]
    if 'vault' not in caps: caps.append('vault')
    env['MONTANA_CAPS'] = ','.join(caps)
    for k, v in want.items():
        if k not in env: env[k] = v
    out = []
    for r in rows:
        if r.startswith('Environment='): continue
        out.append(r)
        if r.strip() == '[Service]':
            for k, v in env.items(): out.append('Environment=' + k + '=' + v)
    open(u, 'w').write(chr(10).join(out))
else:
    env = {'MONTANA_CAPS': 'vault'}
    env.update(want)
    text = ['[Unit]', 'Description=Montana node store (the shelf of the whole phone)', 'After=network.target', '', '[Service]']
    text += ['Environment=' + k + '=' + v for k, v in env.items()]
    text += ['User=montana', 'ExecStart=/usr/bin/python3 /opt/montana-node-store/montana-node-store.py', 'Restart=always',
             'RestartSec=2', 'LimitNOFILE=65536', '', '[Install]', 'WantedBy=multi-user.target', '']
    open(u, 'w').write(chr(10).join(text))
PYEOF
if [ ! -f /var/lib/montana-node-wake/tls/key.pem ]; then
  case "$IP" in *[a-zA-Z]*) SAN="DNS:$IP";; *) SAN="IP:$IP";; esac
  runuser -u montana -- sh -c "umask 077; openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 3650 -keyout /var/lib/montana-node-wake/tls/key.pem -out /var/lib/montana-node-wake/tls/cert.pem -subj /CN=montana-node -addext subjectAltName=$SAN" 2>/dev/null
fi
command -v ufw >/dev/null 2>&1 && ufw allow 8463/tcp >/dev/null 2>&1 || true
systemctl daemon-reload
systemctl enable montana-node-store >/dev/null 2>&1 || true
systemctl restart montana-node-store
sleep 1
systemctl is-active montana-node-store
openssl x509 -in /var/lib/montana-node-wake/tls/cert.pem -noout -fingerprint -sha256
"""   // NOT-UI: the machine's own commands

    /// Puts the door up on the machine and brings back the digest of its certificate, 64 hex.
    static func run(host: String, user: String, password: String) async throws -> String {
        guard let d = door() else { throw MTSSHError.channel }
        let put = try await MTSSHRun.run(host: host, user: user, password: password,
                                         command: "mkdir -p /opt/montana-node-store && cat > /opt/montana-node-store/montana-node-store.py",   // NOT-UI
                                         stdin: d, seconds: 120)
        guard put.status == 0 else { throw MTSSHError.refused(put.status, put.err) }
        let ran = try await MTSSHRun.run(host: host, user: user, password: password, command: "bash -s -- " + host,   // NOT-UI
                                         stdin: Data(script.utf8), seconds: 300)
        guard ran.status == 0 else { throw MTSSHError.refused(ran.status, ran.err.isEmpty ? ran.out : ran.err) }
        MontanaP2PTrace.mark("home_node", "set up: active=" + (ran.out.contains("active") ? "1" : "0"))
        guard let line = ran.out.split(separator: "\n").last(where: { $0.contains("Fingerprint=") }),   // NOT-UI: openssl's own word
              let eq = line.firstIndex(of: "=") else { throw MTSSHError.refused(0, "no fingerprint") }   // NOT-UI
        let fp = line[line.index(after: eq)...].replacingOccurrences(of: ":", with: "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard fp.count == 64 else { throw MTSSHError.refused(0, "bad fingerprint") }   // NOT-UI
        return fp
    }
}

/// THE NODE'S CERTIFICATE, TRUSTED BY ITS DIGEST ALONE (28.09): a node put up by address has no name and no authority; the
/// digest the set-up brought back is the whole trust. Without a pin the platform's own judgement stands -- a named node
/// behind a certificate authority.
class MTNodeTrust: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let pin = MontanaHomeNode.pin
        guard !pin.isEmpty, challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else { return (.performDefaultHandling, nil) }
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else { return (.cancelAuthenticationChallenge, nil) }
        let digest = MontanaHomeNode.hex(Data(SHA256.hash(data: SecCertificateCopyData(leaf) as Data)))
        return digest == pin ? (.useCredential, URLCredential(trust: trust)) : (.cancelAuthenticationChallenge, nil)
    }
}
