import Foundation
import CoreBluetooth
import CryptoKit
import MontanaBindings
import UIKit

// Montana Bluetooth LE mesh (CoreBluetooth): every phone is central and peripheral at once,
// packets relay hop to hop under a TTL, repeats are dropped, long packets are fragmented — and
// the crypto is MONTANA's post-quantum crypto ONLY:
//  • a per-DEVICE ML-KEM-768 identity, drawn at random and kept locally: a key derived from
//    the seed would be one key for every device of one person, forever, and would join all of
//    their appearances by itself ([I-17].2)
//  • messages are ML-KEM sealed-box to the recipient (encaps -> ct + ChaCha20-Poly1305) — relays
//    carry OPAQUE ciphertext, only the recipient decapsulates. No classical Noise/Ed25519.
// Works with NO internet and NO third party; each phone is a self-sufficient node here too.
final class MontanaBLEMesh: NSObject {
    static let shared = MontanaBLEMesh()

    // Our own service/characteristic UUIDs — Montana talks only to Montana.
    private let serviceUUID = CBUUID(string: "4D4F4E54-414E-4100-4245-6C654D657368")   // "MONTANA..BleMesh"
    private let charUUID    = CBUUID(string: "4D4F4E54-414E-4101-4D65-737361676573")   // "MONTANA..Messages"

    private var central: CBCentralManager?
    private var peripheral: CBPeripheralManager?
    private var myChar: CBMutableCharacteristic?
    private var started = false

    // Mesh identity (post-quantum)
    private var kemPk = [UInt8](repeating: 0, count: 1184)   // MT_MLKEM_PUBKEY_SIZE
    private var kemSk = [UInt8](repeating: 0, count: 2400)   // MT_MLKEM_SECKEY_SIZE
    private var myOverlay = Data(count: 32)
    // AIR-CHECKED: the account key signs a letter INSIDE the sealed blob and is read only by its
    // recipient — a postman carries opaque bytes. It is never part of a beacon or a knock.
    private var signPk = [UInt8](repeating: 0, count: 1952)
    private var signSk = [UInt8](repeating: 0, count: 4032)   // AIR-CHECKED: signs inside the seal

    // Links
    private var connectedPeripherals: [CBPeripheral: CBCharacteristic] = [:]   // central role: write targets
    private var subscribedCentrals: [CBCentral] = []                            // peripheral role: notify targets
    private var pendingConnect: Set<CBPeripheral> = []

    // Peer table learned from announces: overlay -> (kem pubkey, montana addr)
    private struct PeerInfo { let kem: Data; let ref: String }
    private var peers: [Data: PeerInfo] = [:]
    /// What a neighbouring NODE offered in its beacon: a sealing key and, when it has one, an
    /// address to dial. Keyed by the node, and holding nothing about a person — the correspondence
    /// a node answers for is learned from a knock, if it ever knocks.
    private var nodeKem: [Data: Data] = [:]
    private var nodeEndpoint: [Data: (String, UInt16)] = [:]
    /// When a position was last heard. A position lives one window, so its record does too:
    /// without this the neighbour map would grow by a new value every minute and never shrink.
    private var nodeSeenAt: [Data: Date] = [:]
    private static let nodeTTL: TimeInterval = 3 * 60   // three windows -- the same tolerance the labels have
    private func pruneNodes() {
        let cut = Date().addingTimeInterval(-Self.nodeTTL)
        for (k, at) in nodeSeenAt where at < cut {
            nodeSeenAt[k] = nil; nodeKem[k] = nil; nodeEndpoint[k] = nil; peers[k] = nil
        }
    }

    // Dedup (sliding set of recently seen msg_ids)
    private var seen: [Data] = []
    private var seenSet: Set<Data> = []

    // Fragment reassembly: fragId -> (total, [index: chunk])
    private var assembly: [String: (Int, [Int: Data])] = [:]
    // Per-link inbound accumulators keyed by link id (a fragment always fits one write, so we frame per packet)

    private let bleQueue = DispatchQueue(label: "montana.ble.mesh")

    func start() {
        guard !started else { return }
        // The KEM key of this NODE. Drawn for the device, not derived from the seed: a key derived
        // from the seed is the same key on every device of one person and never changes, so it
        // joins all of their appearances by itself — which is what [I-17].2 forbids. What it must
        // do is let a neighbour seal a letter to this machine, and a device-local key does that.
        guard let kem = MontanaNodeKem.device() else { MontanaLog.event("BLE mesh keygen FAIL"); return }
        kemPk = kem.pk; kemSk = kem.sk
        // §3.3 overlay identity — ONE place computes it, and it is not this one.
        guard let ident = MontanaOverlayKey.device() else {
            MontanaLog.event("BLE mesh overlay identity FAIL"); return
        }
        myOverlay = ident.tag
        // The account key signs a letter INSIDE the sealed blob, where only its recipient reads it.
        // It never travels on the air: an announce carrying it hands every listener the one value
        // that names a person for good.
        //
        // Taken from the one node that holds them rather than derived here from the phrase: that
        // call ran the stretch of the phrase a second time, inside the core where no cache of this
        // side could reach it, and the radio started seconds late because of it.
        // AIR-CHECKED: sender authenticity inside the sealed envelope; nothing of this goes on the air.
        guard let k = MontanaSeed.keys() else { MontanaLog.event("BLE mesh identity keys FAIL"); return }
        signPk = [UInt8](k.pub); signSk = [UInt8](k.sk)
        started = true
        central = CBCentralManager(delegate: self, queue: bleQueue,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "montana.ble.central"])
        peripheral = CBPeripheralManager(delegate: self, queue: bleQueue,
            options: [CBPeripheralManagerOptionRestoreIdentifierKey: "montana.ble.peripheral"])
        MontanaLog.event("BLE mesh starting node=\(myOverlay.prefix(4).map { String(format: "%02x", $0) }.joined())")
    }

    /// Links the radio actually holds right now: peripherals we write to plus centrals subscribed to
    /// us. Shown in diagnostics, because "Bluetooth is on" and "a neighbour is connected" are different
    /// facts and only the second one carries a message.
    // MAIN-SAFE-SYNC: counters read only from the five-second beat and the diary line, both on a
    // utility queue; the radio queue holds no I/O of its own — CoreBluetooth calls are async.
    var linkCount: Int { bleQueue.sync { connectedPeripherals.count + subscribedCentrals.count } }
    // MAIN-SAFE-SYNC: as above.
    var knownPeerCount: Int { bleQueue.sync { peers.count } }
    // MAIN-SAFE-SYNC: as above.
    var queuedFragments: Int { bleQueue.sync { writeQueue.values.reduce(0) { $0 + $1.count } + notifyQueue.count } }

    // MARK: send a letter — addressed by the TAG of its pipe, sealed to the node that holds it
    @discardableResult
    func send(to conv: String, envelope: Data) -> Bool {
        guard let tag = MTPipeBook.outgoingTag(for: conv) else { return false }
        var target: (node: Data, kem: Data)?
        bleQueue.sync {   // MAIN-SAFE-SYNC: a short read of radio bookkeeping, called off the main thread
            if let e = peers.first(where: { $0.value.ref == conv }) { target = (e.key, e.value.kem) }
        }
        // Nobody within reach holds this pipe, so the letter waits where Network says it waits: in
        // the sender's queue, until a path assembles. It is never sent to whoever happens to be near.
        guard let t = target, t.kem.count == 1184 else { return false }
        // AIR-CHECKED: signed inside the seal, read only by the recipient.
        var sig = [UInt8](repeating: 0, count: 3309)
        let sr = signSk.withUnsafeBufferPointer { sk in [UInt8](envelope).withUnsafeBufferPointer { m in
            mt_sign(sk.baseAddress, m.baseAddress, envelope.count, &sig) } }
        guard sr == 0 else { return false }
        var inner = Data(signPk); inner.append(Data(sig)); inner.append(envelope)   // 1952 | 3309 | envelope
        guard let sealed = MontanaBLEMesh.seal(to: t.kem, inner) else { return false }
        var msgId = Data(count: 16); _ = msgId.withUnsafeMutableBytes { p in p.bindMemory(to: UInt8.self).baseAddress.map { mt_random_fast($0, 16) } }
        let pkt = packet(type: 2, msgId: msgId, dst: tag, payload: sealed)
        bleQueue.async { self.markSeen(msgId); self.broadcast(pkt, exceptLink: nil) }
        MontanaP2PTrace.mark("ble_tx", "bytes=\(sealed.count)")
        return true
    }

    /// A WORD OF THE MESH WALL (MTMeshRoom, 29.09): addressed to nobody -- the zero slot every beacon wears -- heard by every
    /// neighbour and passed on once by each while it is fresh. Only while this device offers itself to the mesh.
    func sayInRoom(_ payload: Data, type: UInt8 = 7) {
        var msgId = Data(count: 16); _ = msgId.withUnsafeMutableBytes { p in p.bindMemory(to: UInt8.self).baseAddress.map { mt_random_fast($0, 16) } }
        let pkt = packet(type: type, msgId: msgId, dst: Self.broadcastDst, payload: payload)
        bleQueue.async {
            guard self.discoverable else { return }
            self.markSeen(msgId); self.broadcast(pkt, exceptLink: nil)
        }
        if type == 7 { MontanaP2PTrace.mark("mesh_room", "tx bytes=\(payload.count)") }
        else { MontanaP2PTrace.markFolded("mesh_room", "tx type=\(type)", window: 10) }   // an item's pieces and asks, folded
    }

    // Blob chunk (type 4): content-addressed, so no signature — the recipient verifies by hashing.
    // Addressed by the tag of the pipe exactly as a letter is.
    func sendBlob(to conv: String, blobId: String, sealed: Data) -> Bool {
        guard let tag = MTPipeBook.outgoingTag(for: conv) else { return false }
        var target: (node: Data, kem: Data)?
        bleQueue.sync {   // MAIN-SAFE-SYNC: a short read of radio bookkeeping, called off the main thread
            if let e = peers.first(where: { $0.value.ref == conv }) { target = (e.key, e.value.kem) }
        }
        guard let t = target, t.kem.count == 1184 else { return false }
        var inner = Data(blobId.utf8); inner.append(0); inner.append(sealed)
        guard let box = MontanaBLEMesh.seal(to: t.kem, inner) else { return false }
        var msgId = Data(count: 16); _ = msgId.withUnsafeMutableBytes { p in p.bindMemory(to: UInt8.self).baseAddress.map { mt_random_fast($0, 16) } }
        let pkt = packet(type: 4, msgId: msgId, dst: tag, payload: box)
        bleQueue.async { self.markSeen(msgId); self.broadcast(pkt, exceptLink: nil) }
        MontanaP2PTrace.mark("ble_blob_tx", "bytes=\(sealed.count)")
        return true
    }

    // MARK: the cell  [ver1 | type1 | msgId16 | dst16 | payload]
    //
    // Network states it plainly: «there is no field of address, no counter of hops, no marker of
    // position». What used to stand here had all three — the recipient's permanent node address, the
    // sender's permanent node address, and a hop counter. The sender's address was the worst of
    // them: [I-16] requires that an observer cannot tell whether a machine is the origin of a cell
    // or merely passing it on, and a field naming the origin answers that question outright.
    //
    // Now a letter is addressed the way the set addresses one: by the TAG of its pipe in this
    // window. It names nobody, it points at whoever holds the secret behind it, and a minute later
    // it is meaningless. Nothing says where the cell came from.
    //
    // The hop counter is gone with it — dedup already bounds a flood, since a node passes any one
    // cell on exactly once, and a counter only published how far a cell had travelled.
    static let frameVersion: UInt8 = 3
    static let headerSize = 34
    /// The address slot of a cell that is not addressed to a pipe: a beacon, a knock. Zero, and the
    /// same zero for everyone, so the slot itself distinguishes nothing.
    static let broadcastDst = Data(count: 16)

    private func packet(type: UInt8, msgId: Data, dst: Data, payload: Data) -> Data {
        var d = Data([Self.frameVersion, type]); d.append(msgId); d.append(dst.prefix(16)); d.append(payload); return d
    }
    private func parse(_ d: Data) -> (type: UInt8, msgId: Data, dst: Data, payload: Data)? {
        guard d.count >= Self.headerSize, d[d.startIndex] == Self.frameVersion else { return nil }
        let b = d.startIndex
        let type = d[b+1]
        let msgId = d.subdata(in: b+2..<b+18)
        let dst = d.subdata(in: b+18..<b+34)
        let payload = d.subdata(in: b+34..<d.endIndex)
        return (type, msgId, dst, payload)
    }

    // Verify the message sender: ML-DSA signature over the envelope under `pubkey`, and `from` derives
    // from that pubkey. Post-quantum sender authenticity at the mesh layer.
    /// A letter over the radio is accepted when its signature holds AND the key that signed it is
    /// the key this correspondence already answers under.
    ///
    /// It used to be checked against an address: the identifier was derived from the key and
    /// compared to the string the letter travelled under. There is no such string any more, and the
    /// stronger question is the one asked here — not «does this key hash to the name on the
    /// envelope», but «is this the key of the person I have been talking to». A correspondence whose
    /// key is not known yet accepts nothing: keys are learned at acquaintance, never from a letter
    /// that introduces itself.
    private func verifySender(env: Data, pubkey: Data, sig: Data, ref: String) -> Bool {
        guard pubkey.count == 1952, sig.count == 3309, !ref.isEmpty else { return false }
        let ok = [UInt8](pubkey).withUnsafeBufferPointer { pk in [UInt8](env).withUnsafeBufferPointer { m in
            [UInt8](sig).withUnsafeBufferPointer { sg in mt_verify(pk.baseAddress, m.baseAddress, env.count, sg.baseAddress) } } }
        guard ok == 0 else { return false }
        guard let known = MontanaOverlayBook.shared.authPub(forRef: ref) else {
            MontanaLog.event("BLE ✗ letter from a correspondence whose key is not known — refused")
            return false
        }
        return known == pubkey
    }

    // MARK: post-quantum sealed-box (ML-KEM encaps + ChaCha20-Poly1305)  ct(1088) || nonce/tag+ct via seal_blob
    static func seal(to kemPk: Data, _ msg: Data) -> Data? {
        var ct = [UInt8](repeating: 0, count: 1088), ss = [UInt8](repeating: 0, count: 32)
        let rc = [UInt8](kemPk).withUnsafeBufferPointer { mt_mlkem_encaps($0.baseAddress, &ct, &ss) }
        guard rc == 0 else { return nil }
        var nonce = [UInt8](repeating: 0, count: 12)
        guard mt_random_fast(&nonce, 12) == 0 else { return nil }
        var outPtr: UnsafeMutablePointer<UInt8>? = nil; var outLen = 0
        let r2 = ss.withUnsafeBufferPointer { k in nonce.withUnsafeBufferPointer { n in msg.withUnsafeBytes { pp in
            mt_e2e_seal_blob(k.baseAddress, n.baseAddress, pp.bindMemory(to: UInt8.self).baseAddress, msg.count, &outPtr, &outLen) }}}
        guard r2 == 0, let p = outPtr else { return nil }
        let sealed = Data(bytes: p, count: outLen); mt_e2e_free(p, outLen)
        return Data(ct) + sealed
    }
    private func open(_ blob: Data) -> Data? {
        guard blob.count > 1088 else { return nil }
        let ct = [UInt8](blob.prefix(1088)); let sealed = blob.suffix(from: blob.startIndex + 1088)
        var ss = [UInt8](repeating: 0, count: 32)
        let rc = kemSk.withUnsafeBufferPointer { sk in ct.withUnsafeBufferPointer { c in
            mt_mlkem_decaps(sk.baseAddress, c.baseAddress, &ss) } }
        guard rc == 0 else { return nil }
        var outPtr: UnsafeMutablePointer<UInt8>? = nil; var outLen = 0
        let r2 = ss.withUnsafeBufferPointer { k in sealed.withUnsafeBytes { s in
            mt_e2e_open_blob(k.baseAddress, s.bindMemory(to: UInt8.self).baseAddress, sealed.count, &outPtr, &outLen) }}
        guard r2 == 0, let p = outPtr else { return nil }
        let msg = Data(bytes: p, count: outLen); mt_e2e_free(p, outLen)
        return msg
    }

    // MARK: dedup
    private func markSeen(_ id: Data) {
        if seenSet.contains(id) { return }
        seenSet.insert(id); seen.append(id)
        if seen.count > 512 { let old = seen.removeFirst(); seenSet.remove(old) }
    }

    // MARK: fragmentation  [ver1|type3|fragId8|index u16 BE|total u16 BE|chunk]
    private func fragments(_ packet: Data, mtu: Int) -> [Data] {
        let chunkSize = max(64, mtu - 13)
        var fragId = Data(count: 8); _ = fragId.withUnsafeMutableBytes { p in p.bindMemory(to: UInt8.self).baseAddress.map { mt_random_fast($0, 8) } }
        var out: [Data] = []; var idx = 0
        let total = (packet.count + chunkSize - 1) / chunkSize
        var off = packet.startIndex
        while off < packet.endIndex {
            let end = min(off + chunkSize, packet.endIndex)
            var f = Data([1, 3]); f.append(fragId)
            f.append(UInt8(idx >> 8)); f.append(UInt8(idx & 0xff))
            f.append(UInt8(total >> 8)); f.append(UInt8(total & 0xff))
            f.append(packet.subdata(in: off..<end))
            out.append(f); idx += 1; off = end
        }
        return out
    }
    // Half-assembled packets expire. A single lost fragment used to leave its entry in place forever —
    // every announce carries a fresh fragment id, so the table only grew, and a partial packet was
    // indistinguishable from one still arriving.
    private var assemblyAt: [String: Double] = [:]
    private let assemblyTTL: Double = 20
    private func purgeAssembly() {
        let now = Date().timeIntervalSince1970
        for (k, t) in assemblyAt where now - t > assemblyTTL { assembly[k] = nil; assemblyAt[k] = nil }
        if assembly.count > 64, let oldest = assemblyAt.min(by: { $0.value < $1.value })?.key {
            assembly[oldest] = nil; assemblyAt[oldest] = nil
        }
    }

    private func reassemble(_ frag: Data, link: AnyObject) -> Data? {
        guard frag.count >= 14, frag[frag.startIndex] == 1, frag[frag.startIndex+1] == 3 else { return nil }
        let b = frag.startIndex
        let fragId = frag.subdata(in: b+2..<b+10)
        let idx = (Int(frag[b+10]) << 8) | Int(frag[b+11])
        let total = (Int(frag[b+12]) << 8) | Int(frag[b+13])
        let chunk = frag.subdata(in: b+14..<frag.endIndex)
        let key = "\(UInt(bitPattern: ObjectIdentifier(link).hashValue))-" + fragId.map { String(format: "%02x", $0) }.joined()
        purgeAssembly()
        var entry = assembly[key] ?? (total, [:])
        entry.1[idx] = chunk; assembly[key] = entry
        assemblyAt[key] = Date().timeIntervalSince1970
        guard entry.1.count == total else { return nil }
        var full = Data(); for i in 0..<total { guard let c = entry.1[i] else { return nil }; full.append(c) }
        assembly.removeValue(forKey: key); assemblyAt.removeValue(forKey: key)
        return full
    }

    // Fragments waiting for the link to accept them, per peripheral. A write without response is
    // DISCARDED, silently, when CoreBluetooth's buffer is full — and an announce is eight kilobytes,
    // some forty fragments at a typical MTU, so writing them in a tight loop loses most of them and the
    // far side never reassembles a single announce. That is precisely what "the phones do not see each
    // other" looks like from the outside: the radio is fine, the packet never completes.
    private var writeQueue: [ObjectIdentifier: [Data]] = [:]

    private func drainWrites(_ per: CBPeripheral) {
        guard let ch = connectedPeripherals[per] else { writeQueue[ObjectIdentifier(per)] = nil; return }
        let key = ObjectIdentifier(per)
        while var q = writeQueue[key], !q.isEmpty {
            guard per.canSendWriteWithoutResponse else { return }
            let f = q.removeFirst()
            writeQueue[key] = q
            per.writeValue(f, for: ch, type: .withoutResponse)
        }
        if writeQueue[key]?.isEmpty ?? false { writeQueue[key] = nil }
    }

    /// Send to ONE link — the one a cell arrived on, and nobody else.
    ///
    /// This is what lets an answer to a knock exist at all. A knock is a broadcast: it must be,
    /// because the one who should hear it is not known yet. An ANSWER must not be, because the same
    /// tag coming from two points in one window is precisely the edge a tag exists to avoid. Sent
    /// back down the arriving link, the answer is heard by the one machine that already heard the
    /// knock, and by nothing else in range.
    private func sendOnLink(_ packet: Data, link: AnyObject?) {
        guard let link else { broadcast(packet, exceptLink: nil); return }
        if let per = link as? CBPeripheral, connectedPeripherals[per] != nil {
            let mtu = per.maximumWriteValueLength(for: .withoutResponse)
            let key = ObjectIdentifier(per)
            var q = writeQueue[key] ?? []
            q.append(contentsOf: fragments(packet, mtu: max(64, mtu)))
            if q.count > 512 { q.removeFirst(q.count - 512) }
            writeQueue[key] = q
            drainWrites(per)
            return
        }
        // The link is a subscribed central: a notification reaches exactly the subscribers, and the
        // one that knocked is among them.
        if let ch = myChar, !subscribedCentrals.isEmpty {
            let mtu = subscribedCentrals.map { $0.maximumUpdateValueLength }.min() ?? 180
            for f in fragments(packet, mtu: max(64, mtu)) {
                if peripheral?.updateValue(f, for: ch, onSubscribedCentrals: nil) != true { notifyQueue.append(f) }
            }
        }
    }

    // MARK: broadcast a full mesh packet over all links (fragmented per link MTU)
    private func broadcast(_ packet: Data, exceptLink: AnyObject?) {
        // central role: write to each connected peripheral
        for (per, _) in connectedPeripherals where (per as AnyObject) !== (exceptLink as AnyObject?) {
            let mtu = per.maximumWriteValueLength(for: .withoutResponse)
            let key = ObjectIdentifier(per)
            var q = writeQueue[key] ?? []
            q.append(contentsOf: fragments(packet, mtu: max(64, mtu)))
            // A link that has fallen behind by more than a few announces is not going to catch up;
            // dropping the oldest keeps the newest state moving instead of replaying a stale queue.
            if q.count > 512 { q.removeFirst(q.count - 512) }
            writeQueue[key] = q
            drainWrites(per)
        }
        // peripheral role: notify subscribed centrals
        if let ch = myChar, !subscribedCentrals.isEmpty {
            let mtu = subscribedCentrals.map { $0.maximumUpdateValueLength }.min() ?? 180
            for f in fragments(packet, mtu: max(64, mtu)) {
                if peripheral?.updateValue(f, for: ch, onSubscribedCentrals: nil) != true { notifyQueue.append(f) }
            }
        }
    }

    private func handleFullPacket(_ data: Data, fromLink link: AnyObject?) {
        guard let p = parse(data) else { return }
        if seenSet.contains(p.msgId) { return }   // dedup — and it is what bounds the flood
        markSeen(p.msgId)
        switch p.type {
        case 1:   // beacon: kem(1184) | overlayAuth(1952) | sig(3309) | ipLen(1) | ip | port(2)
            let b = p.payload.startIndex
            guard p.payload.count >= 32 + 1184 + 3 else { return }
            var o = b
            let node = p.payload.subdata(in: o..<o+32); o += 32     // this window's position
            let kem = p.payload.subdata(in: o..<o+1184); o += 1184
            let il = Int(p.payload[o]); o += 1
            guard p.payload.count >= (o - b) + il + 2 else { return }
            let hintIP = String(data: p.payload.subdata(in: o..<o+il), encoding: .utf8) ?? ""; o += il
            let hintPort = (UInt16(p.payload[o]) << 8) | UInt16(p.payload[o+1]); o += 2
            // Who spoke is not checked here and cannot be: a beacon asserts nothing about a machine's
            // identity. It says "a Montana node is here, seal to this, call to that", and all of it is
            // proven by the channel. Our own position is learned from the three accepted windows.
            if !MontanaWindowPos.mine(myOverlay).contains(node) {
                nodeSeenAt[node] = Date()
                nodeKem[node] = kem
                // A knock may have arrived before the beacon that carries the sealing key. Complete
                // the entry now, or a letter to a neighbour who is plainly here would be refused for
                // want of a key we are holding.
                if let known = peers[node], known.kem.count != 1184 {
                    peers[node] = PeerInfo(kem: kem, ref: known.ref)
                    publishPeers()
                }
                if !hintIP.isEmpty, hintPort > 0, MontanaTransport.isGlobalIP(hintIP) {
                    nodeEndpoint[node] = (hintIP, hintPort)
                }
                relay(p, fromLink: link)   // a beacon travels the mesh so sealing keys are known beyond one hop
            }
        case 5:   // knock: node(32) | count(1) | tag(16) × count — a tag of THIS window, or noise
            let b = p.payload.startIndex
            guard p.payload.count >= 33 else { return }
            let node = p.payload.subdata(in: b..<b+32)
            let n = Int(p.payload[b+32])
            guard n > 0, p.payload.count >= 33 + n * 16,
                  !MontanaWindowPos.mine(myOverlay).contains(node) else { return }
            for k in 0..<n {
                let o = b + 33 + k * 16
                let tag = p.payload.subdata(in: o..<o+16)
                // Mine, or noise. One lookup in the index of this window.
                // Either a pipe this device holds, or a node it listens at for a first letter.
                // Both deserve the same answer: «I am here, seal to this».
                guard let conv = MTPipeBook.match(tag) ?? (MTPipeBook.isFirstContactTag(tag) ? "" : nil) else { continue }
                guard !conv.isEmpty else {
                    var reply = MontanaWindowPos.of(myOverlay, MTPipe.window()); reply.append(Data(kemPk))
                    var rid = Data(count: 16); _ = rid.withUnsafeMutableBytes { q in q.bindMemory(to: UInt8.self).baseAddress.map { mt_random_fast($0, 16) } }
                    sendOnLink(packet(type: 6, msgId: rid, dst: tag, payload: reply), link: link)
                    markSeen(rid)
                    continue
                }
                peers[node] = PeerInfo(kem: nodeKem[node] ?? Data(), ref: conv)
                publishPeers()
                if let ep = nodeEndpoint[node] {
                    MontanaP2PNode.shared.learnEndpoint(ref: conv, ip: ep.0, port: ep.1)
                }
                MontanaOverlayBook.shared.bind(ref: conv, overlay: node)
                let w = MTPipe.window()
                if w != heardWindow { heardWindow = w; heardSet = [] }
                heardSet.insert(conv)
                flushCarry(for: conv)
                MontanaP2PTrace.mark("ble_knock_rx", "conv=\(String(conv.prefix(10)))")
                // Answer, or the two never meet. Whoever knocked learned nothing by knocking: it
                // still does not know this machine is here, and its letter would sit in its queue
                // for good. The answer goes back down the arriving link alone, so the tag it
                // carries is heard by the machine that already heard it and by nobody else.
                var reply = MontanaWindowPos.of(myOverlay, MTPipe.window()); reply.append(Data(kemPk))
                var rid = Data(count: 16); _ = rid.withUnsafeMutableBytes { q in q.bindMemory(to: UInt8.self).baseAddress.map { mt_random_fast($0, 16) } }
                sendOnLink(packet(type: 6, msgId: rid, dst: tag, payload: reply), link: link)
                markSeen(rid)
            }
            // A knock is for the neighbours who can hear it, and is not passed on: it says «I am
            // here and I have something for you», which is true of one hop and of nowhere else.
        case 6:   // answer to a knock: node(32) | kem(1184), addressed by the tag it answers
            guard p.payload.count >= 32 + 1184 else { return }
            let convOrDoor = MTPipeBook.match(p.dst)
            guard let conv = convOrDoor ?? MTPipeBook.convAwaiting(firstContactTag: p.dst) else { return }
            let b = p.payload.startIndex
            let node = p.payload.subdata(in: b..<b+32)
            let kem = p.payload.subdata(in: b+32..<b+32+1184)
            guard !MontanaWindowPos.mine(myOverlay).contains(node) else { return }
            nodeKem[node] = kem
            peers[node] = PeerInfo(kem: kem, ref: conv)
            publishPeers()
            MontanaOverlayBook.shared.bind(ref: conv, overlay: node)
            flushCarry(for: conv)
            MontanaP2PTrace.mark("ble_knock_answer_rx", "conv=\(String(conv.prefix(10)))")
            // Not passed on: it belongs to the link it came in on.
        case 2:   // letter
            // For me exactly when the tag of the cell is a tag of one of MY pipes. Nothing else in
            // the cell is consulted, and nothing else could be: it names neither end.
            if let conv = MTPipeBook.match(p.dst) {
                let owners = Self.distinctOwners(in: p.payload)
                guard let inner = open(Self.body(of: p.payload)), inner.count > 1952 + 3309 else { return }
                let ib = inner.startIndex
                let pubkey = inner.subdata(in: ib..<ib+1952)
                let sig = inner.subdata(in: ib+1952..<ib+1952+3309)
                let env = inner.subdata(in: ib+1952+3309..<inner.endIndex)
                guard let (_, sealed) = MontanaP2PNode.parseEnvelope(env),
                      let (mid, text, snm, sgl, qt, qm, _) = MontanaP2PNode.openBody(sealed, conv: conv),
                      verifySender(env: env, pubkey: pubkey, sig: sig, ref: conv) else { return }
                MontanaP2PTrace.mark("ble_rx", mid: mid, "dir=in via=bluetooth owners=\(owners)")
                DispatchQueue.main.async {
                    var ui: [String: Any] = ["from": conv, "mid": mid, "text": text, "transport": MontanaTransport.bluetooth.rawValue]
                    if let n = snm { ui["senderName"] = n }
                    if let g = sgl { ui["senderGlyph"] = g }
                    if let q = qt, !q.isEmpty { ui["quoteText"] = q }
                    if let m = qm, !m.isEmpty { ui["quoteMid"] = m }
                    NotificationCenter.default.post(name: .montanaP2PIncoming, object: nil, userInfo: ui)
                }
            } else if MTPipeBook.isFirstContactTag(p.dst) {
                // Somebody wrote first, at a node this device listens at: a card it handed out, or
                // the name it holds. The correspondence is not stated anywhere in the cell — it
                // FOLLOWS from the ciphertext inside, which only the holder of that root can open.
                guard let inner = open(Self.body(of: p.payload)), inner.count > 1952 + 3309 else { return }
                let ib = inner.startIndex
                let env = inner.subdata(in: ib+1952+3309..<inner.endIndex)
                guard let (ct, sealed) = MontanaP2PNode.parseFirstEnvelope(env),
                      let conv = MontanaP2PNode.openFirst(ct, sealed: sealed),
                      let (mid, text, snm, sgl, qt, qm, _) = MontanaP2PNode.openBody(sealed, conv: conv) else { return }
                MTPipeBook.dropFirstIndex()
                MontanaP2PTrace.mark("ble_first_rx", mid: mid, "conv=\(String(conv.prefix(10)))")
                DispatchQueue.main.async {
                    var ui: [String: Any] = ["from": conv, "mid": mid, "text": text, "transport": MontanaTransport.bluetooth.rawValue]
                    if let n = snm { ui["senderName"] = n }
                    if let g = sgl { ui["senderGlyph"] = g }
                    if let q = qt, !q.isEmpty { ui["quoteText"] = q }
                    if let m = qm, !m.isEmpty { ui["quoteMid"] = m }
                    NotificationCenter.default.post(name: .montanaP2PIncoming, object: nil, userInfo: ui)
                }
            } else {
                relay(p, fromLink: link)   // forward opaque — we cannot read it and do not know whose it is
                carry(p)                   // DTN: hold it for a recipient that is not here yet
            }
        case 7:   // a word of the mesh wall: addressed to nobody, laid here and passed on once while it is fresh (29.09)
            guard discoverable else { return }
            if MTMeshRoom.heard(Self.body(of: p.payload), id: p.msgId) { relay(p, fromLink: link) }
        case 8:   // a piece of a picture, voice, file or sticker of the mesh wall: gathered, passed on within the phone's measure
            guard discoverable else { return }
            if MTMeshRoom.heardPiece(Self.body(of: p.payload)) { relay(p, fromLink: link) }
        case 9:   // an ask for the pieces a neighbour missed: answered by whoever holds the item whole, never passed on
            guard discoverable else { return }
            MTMeshRoom.heardAsk(Self.body(of: p.payload))
        case 4:   // blob chunk
            if MTPipeBook.match(p.dst) != nil {
                guard let inner = open(Self.body(of: p.payload)), let sep = inner.firstIndex(of: 0) else { return }
                let bid = String(data: inner[inner.startIndex..<sep], encoding: .utf8) ?? ""
                let sealed = Data(inner[inner.index(after: sep)...])
                guard !bid.isEmpty, !sealed.isEmpty else { return }
                MontanaBlobStore.put(bid, sealed)
                MontanaP2PTrace.mark("ble_blob_rx", "id=\(String(bid.prefix(8))) bytes=\(sealed.count)")
            } else {
                relay(p, fromLink: link)
                carry(p)
            }
        default: break
        }
    }
    // Stage 8 — DTN store-carry-forward (spec s.3 §10). A node carries an OPAQUE packet whose dst is
    // not itself and not in the live mesh, then flushes it when that recipient appears (a verified
    // announce). The courier never reads the payload (ML-KEM sealed to the recipient). In-memory this
    // session; the receiver dedups by msgId so redundant carried copies are harmless.
    private struct Carried { let type: UInt8; let dst: Data; let payload: Data; let expiry: Double }
    private var carryStore: [Data: Carried] = [:]     // msgId -> carried (bleQueue)
    /// A carried cell lives no longer than the tag it is addressed by. Network is explicit: a deposit
    /// under a tag of a past window is refused in silence — so a cell held past its window is not a
    /// letter waiting to arrive, it is bytes nobody will ever accept. The sender's queue is what
    /// redelivers, under the tag of the window the delivery actually happens in.
    private var carryTTL: Double { Double(MTPipe.windowSeconds) * 2 }
    private let carryCap = 256

    private func carry(_ p: (type: UInt8, msgId: Data, dst: Data, payload: Data)) {
        guard p.dst != Self.broadcastDst, carryStore[p.msgId] == nil else { return }
        let now = Date().timeIntervalSince1970
        carryStore = carryStore.filter { $0.value.expiry > now }
        if carryStore.count >= carryCap, let oldest = carryStore.min(by: { $0.value.expiry < $1.value.expiry })?.key { carryStore[oldest] = nil }
        carryStore[p.msgId] = Carried(type: p.type, dst: p.dst, payload: p.payload, expiry: now + carryTTL)
        MontanaP2PTrace.mark("ble_carry", "held=\(carryStore.count)")
    }

    /// A pipe just announced itself within reach: hand over whatever is being carried for it. Which
    /// cells those are is answered by the tags of that pipe in the windows still accepted — the same
    /// question the recipient itself would ask.
    private func flushCarry(for conv: String) {
        let now = Date().timeIntervalSince1970
        carryStore = carryStore.filter { $0.value.expiry > now }
        var tags = Set<Data>()
        for w in MTPipe.windows() {
            if let t = MTPipeBook.tag(for: conv, window: w) { tags.insert(t) }   // the wallet's door, as every frame of this app
        }
        for (mid, c) in carryStore where tags.contains(c.dst) {
            broadcast(packet(type: c.type, msgId: mid, dst: c.dst, payload: c.payload), exceptLink: nil)
            carryStore[mid] = nil
            MontanaP2PTrace.mark("ble_carry_flush", "delivered")
        }
    }

    /// Passing a cell on. The hop attaches the SEAL of its owner to the step it rewrites: two
    /// machines of one owner produce the same seal and collapse into one step's worth of
    /// distinctness, so a path that only looks diverse cannot pretend to be.
    ///
    /// There is no hop counter to decrement. A flood is bounded by dedup — a node passes any one
    /// cell on exactly once — and a counter published how far a cell had already travelled, which is
    /// the marker of position Network forbids.
    private func relay(_ p: (type: UInt8, msgId: Data, dst: Data, payload: Data), fromLink link: AnyObject?) {
        let sealed = Self.withSeal(p.payload, step: p.msgId)
        broadcast(packet(type: p.type, msgId: p.msgId, dst: p.dst, payload: sealed), exceptLink: link)
    }

    /// The seals a frame carries, in the order the hops attached them. Sixteen bytes each, appended
    /// after a one-byte count; a frame nobody relayed carries a count of zero.
    static func seals(in payload: Data) -> [Data] {
        guard let n = payload.last.map(Int.init), n > 0 else { return [] }
        let need = 1 + n * 16
        guard payload.count > need else { return [] }
        let start = payload.count - need
        return (0..<n).map { i in
            let o = payload.startIndex + start + i * 16
            return payload.subdata(in: o..<(o + 16))
        }
    }

    /// The body of a frame without the seals of its path.
    static func body(of payload: Data) -> Data {
        guard let n = payload.last.map(Int.init), n > 0 else { return payload }
        let need = 1 + n * 16
        guard payload.count > need else { return payload }
        return payload.prefix(payload.count - need)
    }

    /// How many DISTINCT owners a frame crossed. One owner running three machines counts once.
    static func distinctOwners(in payload: Data) -> Int { Set(seals(in: payload)).count }

    private static func withSeal(_ payload: Data, step: Data) -> Data {
        guard let mn = MontanaSeed.mnemonic,
              let master = MontanaQueueKeys.masterSeed(mn),
              let owner = MTPipe.ownerSecret(masterSeed: master) else { return payload }
        let seal = MTPipe.relaySeal(ownerSecret: owner, label: step)
        var out = body(of: payload)
        var list = seals(in: payload)
        guard !list.contains(seal), list.count < 32 else { return payload }   // own seal once; bounded
        list.append(seal)
        for s in list { out.append(s) }
        out.append(UInt8(list.count))
        return out
    }

    private func publishPeers() {
        let refs = Array(Set(peers.values.map { $0.ref }))
        MontanaP2PNode.shared.setBTPeers(refs)
    }

    // MARK: periodic announce (so peers learn our kem for sealing) — fragmented, TTL multi-hop
    private var announceTimer: DispatchSourceTimer?
    private func startAnnounce() {
        announceTimer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: bleQueue)
        t.schedule(deadline: .now() + 2, repeating: 30)   // periodic; immediate announce fires on each new link
        t.setEventHandler { [weak self] in self?.pruneNodes(); self?.announce() }
        t.resume(); announceTimer = t
    }
    /// The same one switch as the local network ([I-10]): off means this device sends no announce and
    /// advertises no service, so nobody discovers it over the radio.
    private var discoverable = MontanaP2PNode.meshDiscoverable
    /// The radio, off at the root: managers torn down, links dropped, lists emptied. `start` brings it
    /// back when the switch turns on.
    func powerDown() {
        bleQueue.async {
            self.central?.stopScan(); self.peripheral?.stopAdvertising()
            self.dutyTimer?.cancel(); self.dutyTimer = nil
            self.announceTimer?.cancel(); self.announceTimer = nil
            for (per, _) in self.connectedPeripherals { self.central?.cancelPeripheralConnection(per) }
            self.connectedPeripherals.removeAll(); self.subscribedCentrals.removeAll()
            self.pendingConnect.removeAll(); self.writeQueue.removeAll(); self.notifyQueue.removeAll()
            self.peers.removeAll(); self.publishPeers()
            self.central = nil; self.peripheral = nil; self.myChar = nil
            self.started = false
            MontanaP2PTrace.mark("ble_power_down")
        }
    }

    func setDiscoverable(_ on: Bool) {
        bleQueue.async {
            self.discoverable = on
            if on {
                self.peripheral?.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [self.serviceUUID]])
                self.startDutyScan(); self.announce()
            } else {
                self.peripheral?.stopAdvertising()
                self.dutyTimer?.cancel(); self.dutyTimer = nil
                self.central?.stopScan()
                self.peers.removeAll(); self.publishPeers()
            }
        }
    }

    /// The beacon: «a Montana node is here, seal to this key, dial this address». It names NOBODY.
    ///
    /// What it used to carry is why this is written out: the reference of a correspondence derived
    /// from the seed, the account public key, a signature binding the two, and the person's chosen
    /// name — all in the clear, every thirty seconds, relayed onward by every neighbour. Any
    /// listener with a phone held a permanent, provable name for whoever walked past, and held it
    /// for good. [I-17].2 forbids a quantity that names a person and survives two of their actions;
    /// that beacon survived all of them.
    ///
    /// So the beacon says only what a machine must say to be useful as a postman, and the question
    /// «is that you» is answered elsewhere — by a tag of a window, which is the set's own answer.
    private func announce() {
        guard discoverable else { return }
        let hintIP = MontanaP2PNode.reachableEndpoint() ?? ""
        let hintPort = MontanaP2PDirect.shared.port
        let ipBytes = Array(hintIP.utf8)
        let portBE = Data([UInt8(hintPort >> 8), UInt8(hintPort & 0xff)])
        // A beacon names a machine by the POSITION of this window, not by its permanent claim.
        //
        // Here lay the node public key -- one thousand nine hundred and fifty-two bytes, unchanged for
        // the whole life of the device -- and a signature over it. Anyone within reception range read
        // one and the same value and could follow one machine through places and times without breaking
        // anything. The signature proved that the sealing key and the address belong to each other; that
        // is proven anew by the CHANNEL that follows the dial, and the envelope inside the seal carries
        // its own signature. A forged beacon costs one refused handshake -- the same answer already
        // given to the local network announcement, and here it also shortens the frame fivefold.
        var payload = MontanaWindowPos.of(myOverlay, MTPipe.window())   // 32
        payload.append(Data(kemPk))            // 1184
        payload.append(UInt8(min(ipBytes.count, 255)))
        payload.append(contentsOf: ipBytes.prefix(255))
        payload.append(portBE)
        var msgId = Data(count: 16); _ = msgId.withUnsafeMutableBytes { p in p.bindMemory(to: UInt8.self).baseAddress.map { mt_random_fast($0, 16) } }
        let pkt = packet(type: 1, msgId: msgId, dst: Self.broadcastDst, payload: payload)
        markSeen(msgId); broadcast(pkt, exceptLink: nil)
    }

    /// The knock: «whoever holds the secret behind this tag, I have something for you».
    ///
    /// A tag stands on a secret two correspondents share and lives for ONE window, so to anybody
    /// else it is sixteen bytes of noise that mean nothing and join to nothing a minute later. It is
    /// put on the air ONLY when this device actually has something to hand over — a knock with
    /// nothing behind it would be an inventory of who this person talks to, broadcast for free.
    ///
    /// The count of tags in a knock is FIXED, and short of that the frame is filled with noise the
    /// core draws: a knock carrying three tags one minute and eleven the next would publish how many
    /// correspondents a person has, which the beacon above went to some trouble not to say.
    static let knockTags = 4
    /// A knock is worth sending once per window: the tags inside it do not change until the window
    /// turns, so a second identical knock in the same minute costs a broadcast and tells nobody
    /// anything new. This is also what keeps a busy queue from turning the radio into a beacon.
    private var knockedWindow: UInt64 = 0
    private var knockedSet: Set<String> = []
    /// Correspondences already HEARD in this window: the other side knocked first, so this device
    /// knows where it is and has no reason to answer with the same bytes.
    ///
    /// This is what keeps a tag from becoming an edge. Two sides of one conversation compute the
    /// SAME tag for a window — that is what makes it work — so if both put it on the air at once, a
    /// listener sees one value coming from two places and has learned that those two talk, without
    /// anybody publishing anything. Whoever hears first falls silent for that window, and the value
    /// stays where it belongs: coming from one point, meaning nothing to anyone else.
    private var heardWindow: UInt64 = 0
    private var heardSet: Set<String> = []

    private func knock(for convs: [String]) {
        guard discoverable, !convs.isEmpty else { return }
        let w = MTPipe.window()
        if w != knockedWindow { knockedWindow = w; knockedSet = [] }
        if w != heardWindow { heardWindow = w; heardSet = [] }
        let want = Set(convs.prefix(Self.knockTags)).subtracting(heardSet)
        guard !want.isEmpty, !want.isSubset(of: knockedSet) else { return }
        knockedSet.formUnion(want)
        var body = Data()
        var n = 0
        for c in want {
            guard let t = MTPipeBook.outgoingTag(for: c) else { continue }
            body.append(t); n += 1
        }
        guard n > 0 else { return }
        while n < Self.knockTags {   // noise to a fixed size: the count of tags says nothing
            var pad = [UInt8](repeating: 0, count: 16)
            guard mt_random_fast(&pad, 16) == 0 else { break }
            body.append(contentsOf: pad); n += 1
        }
        // The knock says which machine is knocking, because a neighbour must know what to seal to.
        // It is not passed on, so nothing of it crosses a path.
        var payload = MontanaWindowPos.of(myOverlay, w); payload.append(UInt8(n)); payload.append(body)
        var msgId = Data(count: 16); _ = msgId.withUnsafeMutableBytes { p in p.bindMemory(to: UInt8.self).baseAddress.map { mt_random_fast($0, 16) } }
        let pkt = packet(type: 5, msgId: msgId, dst: Self.broadcastDst, payload: payload)
        markSeen(msgId); broadcast(pkt, exceptLink: nil)
        MontanaP2PTrace.mark("ble_knock", "tags=\(n)")
    }

    /// Ask the radio to look for these correspondences. Called by the delivery engine when it has
    /// something queued — never on a timer of its own.
    func seek(_ convs: [String]) { bleQueue.async { self.knock(for: convs) } }

    /// The beacon check is no longer here, and that is not an omission.
    ///
    /// It rested on the permanent node public key, which the beacon carried for it -- that is, the check
    /// itself was the reason for a constant on the air. The beacon now asserts nothing: it says "a node
    /// is here, seal to this, call to that". Who is there is proven by the CHANNEL that follows the
    /// dial, while the envelope inside the seal carries its own signature and is read only by the recipient.
    /// A forged beacon costs one refused handshake.

    // per-link inbound frame accumulators keyed by an object id
    private var linkBuf: [ObjectIdentifier: Data] = [:]
    private var notifyQueue: [Data] = []
    private var dutyTimer: DispatchSourceTimer?
    private var dutyOn = false
    // Duty-cycled discovery scan (battery): ~8s on / 4s off. Established links persist across the off phase.
    private func startDutyScan() {
        dutyTimer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: bleQueue)
        t.schedule(deadline: .now(), repeating: 4)
        t.setEventHandler { [weak self] in
            guard let self, let c = self.central, c.state == .poweredOn else { return }
            self.dutyOn.toggle()
            if self.dutyOn { c.scanForPeripherals(withServices: [self.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]) }
            else { c.stopScan() }
        }
        t.resume(); dutyTimer = t
    }

    private func onFragment(_ frag: Data, fromLink link: AnyObject) {
        if let full = reassemble(frag, link: link) { handleFullPacket(full, fromLink: link) }
    }
}

// MARK: Central role — scan, connect, subscribe, write
extension MontanaBLEMesh: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        MontanaP2PNode.shared.setBTOn(c.state == .poweredOn)
        if c.state == .poweredOn { startDutyScan() }
    }
    func centralManager(_ c: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let ps = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for p in ps { p.delegate = self
                if p.state == .connected { p.discoverServices([serviceUUID]) } else { c.connect(p, options: nil) } }
        }
    }
    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        guard !pendingConnect.contains(p), connectedPeripherals[p] == nil else { return }
        pendingConnect.insert(p); p.delegate = self
        c.connect(p, options: [CBConnectPeripheralOptionNotifyOnConnectionKey: true,
                               CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
                               CBConnectPeripheralOptionNotifyOnNotificationKey: true])
    }
    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) { p.discoverServices([serviceUUID]) }
    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) { pendingConnect.remove(p) }
    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        pendingConnect.remove(p); connectedPeripherals.removeValue(forKey: p)
        linkBuf.removeValue(forKey: ObjectIdentifier(p)); writeQueue.removeValue(forKey: ObjectIdentifier(p))
        c.connect(p, options: nil)   // reconnect
    }
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] where s.uuid == serviceUUID { p.discoverCharacteristics([charUUID], for: s) }
    }
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] where ch.uuid == charUUID {
            connectedPeripherals[p] = ch; pendingConnect.remove(p)
            p.setNotifyValue(true, for: ch)
            bleQueue.async { self.startAnnounce(); self.announce() }
        }
    }
    func peripheralIsReady(toSendWriteWithoutResponse p: CBPeripheral) {
        bleQueue.async { self.drainWrites(p) }
    }
    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let v = ch.value else { return }
        bleQueue.async { self.onFragment(v, fromLink: p) }
    }
}

// MARK: Peripheral role — advertise, receive writes, notify
extension MontanaBLEMesh: CBPeripheralManagerDelegate {
    func peripheralManager(_ pm: CBPeripheralManager, willRestoreState dict: [String: Any]) {
        if let svcs = dict[CBPeripheralManagerRestoredStateServicesKey] as? [CBMutableService],
           let ch = svcs.first(where: { $0.uuid == serviceUUID })?.characteristics?.first as? CBMutableCharacteristic { myChar = ch }
    }
    func peripheralManagerDidUpdateState(_ pm: CBPeripheralManager) {
        guard pm.state == .poweredOn else { return }
        if myChar == nil {   // fresh start; on background restoration the service is already restored (willRestoreState)
            let ch = CBMutableCharacteristic(type: charUUID, properties: [.write, .writeWithoutResponse, .notify],
                                             value: nil, permissions: [.writeable])
            let svc = CBMutableService(type: serviceUUID, primary: true); svc.characteristics = [ch]
            pm.add(svc); myChar = ch
        }
        if discoverable { pm.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [serviceUUID]]) }
        bleQueue.async { self.startAnnounce() }
    }
    func peripheralManager(_ pm: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for r in requests { if let v = r.value { bleQueue.async { self.onFragment(v, fromLink: r.central) } } }
        pm.respond(to: requests[0], withResult: .success)
    }
    func peripheralManager(_ pm: CBPeripheralManager, central: CBCentral, didSubscribeTo ch: CBCharacteristic) {
        if !subscribedCentrals.contains(central) { subscribedCentrals.append(central) }
        bleQueue.async { self.announce() }
    }
    func peripheralManager(_ pm: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom ch: CBCharacteristic) {
        subscribedCentrals.removeAll { $0 === central }
    }
    func peripheralManagerIsReady(toUpdateSubscribers pm: CBPeripheralManager) {
        guard let ch = myChar else { return }
        while let f = notifyQueue.first {
            if pm.updateValue(f, for: ch, onSubscribedCentrals: nil) { notifyQueue.removeFirst() } else { break }
        }
    }
}

/// THE MESH WALL, THE ROOM OF EVERYONE ON THE MESH (the author's word 29.09: «the common mesh chat is pinned at the very top of
/// the chats, and everyone on the mesh gets into it at once; it is called the Mesh wall and appears the moment the switch of
/// visibility on the mesh is on»). A word of the room is a cell of type 7 addressed to nobody; every Montana phone on the mesh
/// with its switch on lays it in its own room and passes it on once. What the cell carries is what a public room needs and
/// nothing more: the name the person chose to speak under, a mark of this run of the app (eight random bytes born with the
/// process, so two runs of one person are not joined by the cell), the moment and the words. No address, no permanent key, no
/// tag of a pipe, no field of origin ([I-17].2 for everything but the name the person gives the room). The room is public by
/// the author's word: whoever is on the mesh reads it, as whoever is in a room hears it.
///   [ver 1 : run 8 : at 4 (seconds, big-endian) : name length 1 : name : words]
enum MTMeshRoom {
    static let version: UInt8 = 1
    static let nameBytes = 96           // the name as the room shows it: sixty-four letters of most scripts
    static let wordBytes = 1024         // the words of one cell: a long letter is several words, as the chat breaks it
    static let freshFor: Double = 600   // a word older than ten minutes is neither laid nor passed on (I-15: scarcity by time)
    static let passPerMinute = 30       // the words of one run passed on per minute (a run that shouts is not carried further)
    static let passAllPerMinute = 120   // the words of the room this phone passes on per minute, whatever marks they wear: a
                                        // mark is eight bytes the speaker draws, so a flood under new marks meets this bound
    /// This run's mark: eight random bytes, born with the process and gone with it.
    static let run: Data = {
        var d = Data(count: 8)
        _ = d.withUnsafeMutableBytes { p in p.bindMemory(to: UInt8.self).baseAddress.map { mt_random_fast($0, 8) } }
        return d
    }()
    private static let lock = NSLock()
    private static var passed: [Data: [Double]] = [:]   // run: the moments its words were passed on in the last minute
    private static var passedAll: [Double] = []          // the moments any word was passed on in the last minute

    struct Word: Equatable { let run: Data; let at: UInt32; let name: String; let text: String }

    /// Pure: the cell's body from its parts, the name and the words cut at a letter's edge within their bounds.
    static func encode(_ w: Word) -> Data {
        let name = Data(cut(w.name, nameBytes).utf8), text = Data(cut(w.text, wordBytes).utf8)
        var d = Data([version]); d.append(w.run.prefix(8))
        d.append(contentsOf: [UInt8((w.at >> 24) & 0xff), UInt8((w.at >> 16) & 0xff), UInt8((w.at >> 8) & 0xff), UInt8(w.at & 0xff)])
        d.append(UInt8(name.count)); d.append(name); d.append(text)
        return d
    }
    /// Pure: the parts of a cell's body, or nil for a body of another shape or of empty words.
    static func decode(_ d: Data) -> Word? {
        let b = d.startIndex
        guard 14 <= d.count, d[b] == version else { return nil }
        let run = d.subdata(in: b + 1 ..< b + 9)
        let at = (UInt32(d[b + 9]) << 24) | (UInt32(d[b + 10]) << 16) | (UInt32(d[b + 11]) << 8) | UInt32(d[b + 12])
        let n = Int(d[b + 13])
        guard 14 + n < d.count, n <= nameBytes, d.count - 14 - n <= wordBytes,
              let name = String(data: d.subdata(in: b + 14 ..< b + 14 + n), encoding: .utf8),
              let text = String(data: d.subdata(in: b + 14 + n ..< d.endIndex), encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Word(run: run, at: at, name: name, text: text)
    }
    /// THE CELL ENDS WITH A SEAL COUNT OF ZERO (the mesh's own rule, MontanaBLEMesh.seals: «a frame nobody relayed carries a
    /// count of zero»). A hop appends its seal and the count after the body, and a reader takes the last byte for that count:
    /// without the zero, the last byte of the words was read as a count and a long word ending in a full stop or a digit lost
    /// its tail (found by the critic's pass, 29.09, before the first build of the room).
    static func cell(_ w: Word) -> Data { var d = encode(w); d.append(0); return d }
    /// Pure: the word of a cell's body as the mesh hands it (the seals of its path taken off), or nil.
    static func word(ofBody body: Data) -> Word? {
        guard body.last == 0 else { return nil }
        return decode(body.dropLast())
    }
    /// Pure: the word's own name in the room -- its run, its moment and its words -- so the same word passed on under a new
    /// cell id (a replay) lays nothing twice. The first sixteen bytes of their SHA-256.
    static func mid(of w: Word) -> String {
        var d = w.run
        d.append(contentsOf: [UInt8((w.at >> 24) & 0xff), UInt8((w.at >> 16) & 0xff), UInt8((w.at >> 8) & 0xff), UInt8(w.at & 0xff)])
        d.append(Data(w.name.utf8)); d.append(0); d.append(Data(w.text.utf8))
        return "mid:mesh-" + hex(Data(SHA256.hash(data: d)).prefix(16))
    }
    /// A string cut at a letter's edge to at most `bytes` bytes of UTF-8.
    static func cut(_ s: String, _ bytes: Int) -> String {
        var out = ""
        for ch in s {
            if bytes < out.utf8.count + String(ch).utf8.count { break }
            out.append(ch)
        }
        return out
    }
    /// The word's measure: a run passes on at most thirty words a minute, the phone at most 120, whatever marks they wear.
    static func mayPassWord(_ r: Data, _ now: Double) -> Bool {
        lock.lock(); defer { lock.unlock() }
        var seen = (passed[r] ?? []).filter { now - $0 < 60 }
        passedAll = passedAll.filter { now - $0 < 60 }
        let may = seen.count < passPerMinute && passedAll.count < passAllPerMinute
        if may { seen.append(now); passedAll.append(now) }
        passed[r] = seen
        if 256 < passed.count { passed = passed.filter { !($0.value.filter { now - $0 < 60 }.isEmpty) } }
        return may
    }
    /// The ref a word's row carries in this phone's room: the run and the name, so the room names its writer from the row
    /// itself. COMPAT-LOCAL: a row's own field, never a word on the wire.
    static func ref(of w: Word) -> String { "mesh:" + hex(w.run) + ":" + w.name }
    static func name(of ref: String?) -> String? {
        guard let r = ref, r.hasPrefix("mesh:") else { return nil }
        let parts = r.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let n = String(parts[2]).trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? String(localized: "Someone", bundle: MTLanguage.bundle) : n
    }
    static func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }

    /// The person's words on the mesh wall: on the air at once, to everyone on the mesh. Only the words a person wrote -- a
    /// service word of the app never leaves by the room.
    static func say(_ text: String) {
        guard MontanaP2PNode.meshDiscoverable, !text.hasPrefix("\u{200B}"), !isControlMarker(text) else { return }
        let w = Word(run: run, at: UInt32(max(0, Date().timeIntervalSince1970)), name: E2E.myDisplayName(), text: text)
        MontanaBLEMesh.shared.sayInRoom(cell(w))
    }
    /// A cell of the room came by the radio (on the radio's queue): the word is laid in the room, and the answer says whether
    /// it may be passed on -- fresh, not this run's own, its run not over its minute's measure.
    static func heard(_ body: Data, id: Data) -> Bool {
        if body.first == mediaVersion { return heardMedia(body) }   // the word of a picture, voice, file or sticker
        guard let w = word(ofBody: body), w.run != run else { return false }
        let now = Date().timeIntervalSince1970
        guard abs(now - Double(w.at)) < freshFor else { return false }
        guard mayPassWord(w.run, now) else { MontanaP2PTrace.markFolded("mesh_room", "held -- a run over its minute's measure", window: 60); return false }
        let mid = mid(of: w)
        DispatchQueue.main.async { ChatStore.live?.appendMeshRoom(mid: mid, from: ref(of: w), text: w.text, at: Double(w.at)) }
        return true
    }
}

/// THE MESH WALL'S PICTURES, VOICES, FILES AND STICKERS (the author's word 29.09: «everything goes into the common mesh room as
/// in any chat»). An item rides as its word (type 7, version 2: the word's own parts and the item's kind, size, pieces and
/// SHA-256) and its pieces (type 8), each passed on once by every neighbour; a neighbour that missed pieces asks for them
/// (type 9) and whoever holds the item whole answers. The radio carries kilobytes a second, so an item is at most 256 KB: a
/// picture is made that small, a voice of about a minute, a file and a sticker fit, and a video longer than a moment does not
/// -- its row says it was not sent. Nothing of it names a person beyond the word's own name.
///   word:  [ver 2 : run 8 : at 4 : name length 1 : name : kind 1 : item 16 : size 4 : pieces 2 : sha 32 : ext length 1 : ext :
///           file name length 1 : file name : duration ms 4 : caption]
///   piece: [ver 1 : item 16 : index 2 : count 2 : bytes]        ask: [ver 1 : item 16 : n 1 : index 2 × n]
/// Every cell ends with the mesh's seal count of zero (MTMeshRoom.cell).
extension MTMeshRoom {
    static let mediaVersion: UInt8 = 2
    static let pieceBytes = 960
    static let itemMax = 256 * 1024
    static let piecesMax = (itemMax + pieceBytes - 1) / pieceBytes

    struct Media: Equatable {
        let kind: String        // img, vid, aud, doc -- the chat's own words for a row's file
        let item: Data          // sixteen random bytes: the item's name on the air
        let size: Int
        let pieces: Int
        let sha: Data
        let ext: String
        let fileName: String    // a file's own name, or the sticker's mark; empty for a picture or a voice
        let durMs: UInt32
    }
    /// A bounded reader of a cell's body: every read says whether its bytes are there.
    struct Reader {
        let d: Data
        var at: Int
        init(_ d: Data) { self.d = d; at = d.startIndex }
        mutating func bytes(_ n: Int) -> Data? {
            guard 0 <= n, at + n <= d.endIndex else { return nil }
            defer { at += n }
            return d.subdata(in: at ..< at + n)
        }
        mutating func u8() -> UInt8? { bytes(1).map { $0[$0.startIndex] } }
        mutating func u16() -> Int? { bytes(2).map { (Int($0[$0.startIndex]) << 8) | Int($0[$0.startIndex + 1]) } }
        mutating func u32() -> UInt32? { bytes(4).map { b in b.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } } }
        func rest() -> Data { d.subdata(in: at ..< d.endIndex) }
    }
    static func be16(_ v: Int) -> Data { Data([UInt8((v >> 8) & 0xff), UInt8(v & 0xff)]) }
    static func be32(_ v: UInt32) -> Data { Data([UInt8((v >> 24) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff)]) }
    static func kindByte(_ k: String) -> UInt8 { k == "img" ? 0x69 : (k == "vid" ? 0x76 : (k == "aud" ? 0x61 : 0x64)) }
    static func kind(of b: UInt8) -> String { b == 0x69 ? "img" : (b == 0x76 ? "vid" : (b == 0x61 ? "aud" : "doc")) }
    static func pieceCount(_ size: Int) -> Int { (size + pieceBytes - 1) / pieceBytes }

    /// Pure: the item's word, ending with the seal count of zero.
    static func mediaCell(_ w: Word, _ m: Media) -> Data {
        let name = Data(cut(w.name, nameBytes).utf8), cap = Data(cut(w.text, wordBytes).utf8)
        let ext = Data(cut(m.ext, 8).utf8), file = Data(cut(m.fileName, 120).utf8)
        var d = Data([mediaVersion]); d.append(w.run.prefix(8)); d.append(be32(w.at))
        d.append(UInt8(name.count)); d.append(name)
        d.append(kindByte(m.kind)); d.append(m.item.prefix(16)); d.append(be32(UInt32(m.size))); d.append(be16(m.pieces)); d.append(m.sha.prefix(32))
        d.append(UInt8(ext.count)); d.append(ext); d.append(UInt8(file.count)); d.append(file); d.append(be32(m.durMs)); d.append(cap)
        d.append(0)
        return d
    }
    /// Pure: the item's word from a cell's body, or nil for another shape, a size past the measure, or pieces that do not
    /// match the size.
    static func media(ofBody body: Data) -> (Word, Media)? {
        guard body.last == 0 else { return nil }
        var r = Reader(body.dropLast())
        guard r.u8() == mediaVersion, let run = r.bytes(8), let at = r.u32(), let nl = r.u8(), let nd = r.bytes(Int(nl)),
              let k = r.u8(), let item = r.bytes(16), let size = r.u32(), let pieces = r.u16(), let sha = r.bytes(32),
              let el = r.u8(), let ed = r.bytes(Int(el)), let fl = r.u8(), let fd = r.bytes(Int(fl)), let dur = r.u32(),
              let name = String(data: nd, encoding: .utf8), let ext = String(data: ed, encoding: .utf8),
              let file = String(data: fd, encoding: .utf8), let cap = String(data: r.rest(), encoding: .utf8) else { return nil }
        let n = Int(size)
        guard 0 < n, n <= itemMax, pieces == pieceCount(n), Int(nl) <= nameBytes, r.rest().count <= wordBytes else { return nil }
        return (Word(run: run, at: at, name: name, text: cap),
                Media(kind: kind(of: k), item: item, size: n, pieces: pieces, sha: sha, ext: ext, fileName: file, durMs: dur))
    }
    /// Pure: one piece of an item, ending with the seal count of zero.
    static func pieceCell(item: Data, index: Int, count: Int, bytes: Data) -> Data {
        var d = Data([1]); d.append(item.prefix(16)); d.append(be16(index)); d.append(be16(count)); d.append(bytes); d.append(0)
        return d
    }
    static func piece(ofBody body: Data) -> (item: Data, index: Int, count: Int, bytes: Data)? {
        guard body.last == 0 else { return nil }
        var r = Reader(body.dropLast())
        guard r.u8() == 1, let item = r.bytes(16), let i = r.u16(), let n = r.u16() else { return nil }
        let bytes = r.rest()
        guard 0 < n, n <= piecesMax, i < n, !bytes.isEmpty, bytes.count <= pieceBytes else { return nil }
        return (item, i, n, bytes)
    }
    /// Pure: an ask for the pieces of an item a neighbour missed (forty at most), ending with the seal count of zero.
    static func askCell(item: Data, missing: [Int]) -> Data {
        let list = Array(missing.prefix(40))
        var d = Data([1]); d.append(item.prefix(16)); d.append(UInt8(list.count))
        for i in list { d.append(be16(i)) }
        d.append(0)
        return d
    }
    static func ask(ofBody body: Data) -> (item: Data, missing: [Int])? {
        guard body.last == 0 else { return nil }
        var r = Reader(body.dropLast())
        guard r.u8() == 1, let item = r.bytes(16), let n = r.u8(), 0 < n, n <= 40 else { return nil }
        var out: [Int] = []
        for _ in 0 ..< Int(n) {
            guard let i = r.u16() else { return nil }
            out.append(i)
        }
        return (item, out)
    }
    /// Pure: the bytes of piece `i` of an item's whole bytes.
    static func bytesOfPiece(_ data: Data, _ i: Int) -> Data {
        let from = data.startIndex + i * pieceBytes
        return data.subdata(in: from ..< min(data.endIndex, from + pieceBytes))
    }
}

/// The room's items on this phone: gathered from the air, held whole to answer asks, sent from one's own rows.
extension MTMeshRoom {
    static let pieceGap = 0.15                   // seconds between two pieces of one's own item: about six kilobytes a second
    static let passBytesPerMinute = 384 * 1024   // the pieces this phone passes on per minute, whatever items they belong to
    static let heldFor: Double = 600             // an item whole answers asks for ten minutes
    static let heldBytes = 4 * 1024 * 1024       // the bytes of items kept whole to answer asks
    static let gatherFor: Double = 180           // an item not whole in three minutes is let go
    static let gatherMax = 8                     // items gathered at once
    static let askEvery: Double = 5              // a quiet item asks for its missing pieces after this long
    static let asksMax = 6                       // asks per item

    private struct Gathering { var word: Word?; var media: Media?; var got: [Int: Data]; let first: Double; var last: Double; var asks: Int }
    private struct Held { let word: Word; let media: Media; let data: Data; let at: Double }
    private static var gathering: [Data: Gathering] = [:]
    private static var held: [Data: Held] = [:]
    private static var passedBytes: [(at: Double, n: Int)] = []
    private static var answeredAt: [Data: Double] = [:]
    private static var repair: DispatchSourceTimer?
    private static let itemQueue = DispatchQueue(label: "montana.mesh.room.items", qos: .utility)

    /// ONE'S OWN PICTURE, VOICE, FILE OR STICKER IN THE MESH WALL: handed here by the room's one settle (ChatStore.setMediaStatus).
    /// The answer says whether it leaves: a file past the radio's measure does not, and its row stands «not sent». A picture is
    /// made small enough first; the rest leaves as it is.
    @MainActor static func share(_ row: Message) -> Bool {
        guard MontanaP2PNode.meshDiscoverable else { return false }
        let pair: (String, String)? = row.imageFile.map { ($0, "img") } ?? row.videoFile.map { ($0, "vid") }
            ?? row.audioFile.map { ($0, "aud") } ?? row.docFile.map { ($0, "doc") }
        guard let (file, kind) = pair else { return false }
        let url = attachmentURL(file)
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard 0 < size else { return false }
        if kind != "img", itemMax < size {
            MontanaP2PTrace.mark("mesh_room", "not sent -- kind=\(kind) bytes=\(size) past the radio's measure")
            return false
        }
        let w = Word(run: run, at: UInt32(max(0, Date().timeIntervalSince1970)), name: E2E.myDisplayName(), text: row.text)
        let fileName = row.docName ?? ""
        let durMs = UInt32(max(0, min(3_600_000, row.audioDuration * 1000)))
        let ownExt = (file as NSString).pathExtension
        itemQueue.async {
            let made: (Data, String)? = kind == "img" ? small(url) : (try? Data(contentsOf: url)).map { ($0, ownExt) }
            guard let (data, ext) = made, !data.isEmpty, data.count <= itemMax else {
                MontanaP2PTrace.mark("mesh_room", "not sent -- kind=\(kind) did not read small enough")
                return
            }
            send(w, kind: kind, ext: ext, fileName: fileName, durMs: durMs, data: data)
        }
        return true
    }
    /// A picture small enough for the radio: as it is when it already fits (a sticker keeps its own shape and transparency),
    /// else a JPEG at a shrinking side and quality until it does.
    static func small(_ url: URL) -> (Data, String)? {
        guard let orig = try? Data(contentsOf: url) else { return nil }
        if orig.count <= itemMax { return (orig, url.pathExtension.isEmpty ? "jpg" : url.pathExtension) }
        guard let img = UIImage(data: orig) else { return nil }
        let steps: [(CGFloat, CGFloat)] = [(1280, 0.6), (1024, 0.55), (800, 0.5), (640, 0.45), (480, 0.4)]
        for (side, q) in steps {
            let scale = min(1, side / max(img.size.width, img.size.height, 1))
            let target = CGSize(width: max(1, (img.size.width * scale).rounded()), height: max(1, (img.size.height * scale).rounded()))
            let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = true
            let jpeg = UIGraphicsImageRenderer(size: target, format: fmt).jpegData(withCompressionQuality: q) { _ in
                img.draw(in: CGRect(origin: .zero, size: target))
            }
            if jpeg.count <= itemMax { return (jpeg, "jpg") }
        }
        return nil
    }
    private static func send(_ w: Word, kind: String, ext: String, fileName: String, durMs: UInt32, data: Data) {
        var item = Data(count: 16)
        _ = item.withUnsafeMutableBytes { p in p.bindMemory(to: UInt8.self).baseAddress.map { mt_random_fast($0, 16) } }
        let m = Media(kind: kind, item: item, size: data.count, pieces: pieceCount(data.count), sha: Data(SHA256.hash(data: data)),
                      ext: ext, fileName: fileName, durMs: durMs)
        let h = Held(word: w, media: m, data: data, at: Date().timeIntervalSince1970)
        lock.lock(); keep(h); lock.unlock()
        let word = mediaCell(w, m)
        MontanaBLEMesh.shared.sayInRoom(word, type: 7)
        for i in 0 ..< m.pieces {
            itemQueue.asyncAfter(deadline: .now() + pieceGap * Double(i + 1)) {
                MontanaBLEMesh.shared.sayInRoom(pieceCell(item: m.item, index: i, count: m.pieces, bytes: bytesOfPiece(data, i)), type: 8)
            }
        }
        // The word again after the last piece: a neighbour that came in range midway learns what the pieces are.
        itemQueue.asyncAfter(deadline: .now() + pieceGap * Double(m.pieces + 2)) { MontanaBLEMesh.shared.sayInRoom(word, type: 7) }
        MontanaP2PTrace.mark("mesh_room", "item out kind=\(kind) bytes=\(data.count) pieces=\(m.pieces)")
    }
    /// Under the lock: an item whole is kept to answer asks, within its time and the bytes' measure.
    private static func keep(_ h: Held) {
        let now = Date().timeIntervalSince1970
        held = held.filter { now - $0.value.at < heldFor }
        held[h.media.item] = h
        var total = held.values.reduce(0) { $0 + $1.data.count }
        while heldBytes < total, let oldest = held.min(by: { $0.value.at < $1.value.at }) {
            held[oldest.key] = nil
            total -= oldest.value.data.count
        }
    }
    /// Under the lock: the item gathered whole moves to the held once its bytes are the ones its word names; nil while a
    /// piece is missing, and nil -- the item let go -- when the bytes are not those.
    private static func takeWhole(_ item: Data) -> (held: Held?, refused: Bool) {
        guard let g = gathering[item], let m = g.media, let w = g.word, g.got.count == m.pieces else { return (nil, false) }
        var data = Data(capacity: m.size)
        for i in 0 ..< m.pieces {
            guard let p = g.got[i] else { return (nil, false) }
            data.append(p)
        }
        gathering[item] = nil
        guard data.count == m.size, Data(SHA256.hash(data: data)) == m.sha else { return (nil, true) }
        let h = Held(word: w, media: m, data: data, at: Date().timeIntervalSince1970)
        keep(h)
        return (h, false)
    }
    /// The word of an item came (on the radio's queue): the item is gathered from here on; the word keeps the word's measure.
    static func heardMedia(_ body: Data) -> Bool {
        guard let (w, m) = media(ofBody: body), w.run != run else { return false }
        let now = Date().timeIntervalSince1970
        guard abs(now - Double(w.at)) < freshFor, mayPassWord(w.run, now) else { return false }
        lock.lock()
        if held[m.item] == nil, gathering[m.item] != nil || gathering.count < gatherMax {
            var g = gathering[m.item] ?? Gathering(word: nil, media: nil, got: [:], first: now, last: now, asks: 0)
            g.word = w; g.media = m; g.last = now
            if g.got.keys.contains(where: { m.pieces <= $0 }) { g.got = [:] }   // pieces of another shape than the word says
            gathering[m.item] = g
        }
        let taken = takeWhole(m.item)
        lock.unlock()
        land(taken)
        armRepair()
        return true
    }
    /// A piece came (on the radio's queue): kept for its item, and passed on while the phone's minute allows.
    static func heardPiece(_ body: Data) -> Bool {
        guard let p = piece(ofBody: body) else { return false }
        let now = Date().timeIntervalSince1970
        lock.lock()
        passedBytes = passedBytes.filter { now - $0.at < 60 }
        let may = passedBytes.reduce(0) { $0 + $1.n } + p.bytes.count <= passBytesPerMinute
        if may { passedBytes.append((now, p.bytes.count)) }
        var taken: (held: Held?, refused: Bool) = (nil, false)
        if held[p.item] == nil {
            if var g = gathering[p.item] {
                if g.media.map({ $0.pieces == p.count }) ?? true, g.got[p.index] == nil { g.got[p.index] = p.bytes }
                g.last = now
                gathering[p.item] = g
                taken = takeWhole(p.item)
            } else if gathering.count < gatherMax {
                gathering[p.item] = Gathering(word: nil, media: nil, got: [p.index: p.bytes], first: now, last: now, asks: 0)
            }
        }
        lock.unlock()
        land(taken)
        armRepair()
        return may
    }
    /// An ask came: whoever holds the item whole answers with the pieces asked, once in three seconds per item.
    static func heardAsk(_ body: Data) {
        guard let a = ask(ofBody: body) else { return }
        let now = Date().timeIntervalSince1970
        lock.lock()
        let h = held[a.item]
        let may = h != nil && 3 <= now - (answeredAt[a.item] ?? 0)
        if may { answeredAt[a.item] = now }
        lock.unlock()
        guard may, let h else { return }
        let want = a.missing.filter { $0 < h.media.pieces }
        for (n, i) in want.enumerated() {
            itemQueue.asyncAfter(deadline: .now() + pieceGap * Double(n)) {
                MontanaBLEMesh.shared.sayInRoom(pieceCell(item: h.media.item, index: i, count: h.media.pieces, bytes: bytesOfPiece(h.data, i)), type: 8)
            }
        }
        MontanaP2PTrace.markFolded("mesh_room", "ask answered pieces=\(want.count)", window: 10)
    }
    /// The item whole lands in the room on the main thread; a refused one is said in the diary.
    private static func land(_ taken: (held: Held?, refused: Bool)) {
        if taken.refused { MontanaP2PTrace.mark("mesh_room", "item refused -- its bytes are not the ones its word names") }
        guard let h = taken.held else { return }
        let ref = ref(of: h.word)
        Task { @MainActor in lay(h.word, h.media, h.data, ref: ref) }
    }
    @MainActor private static func lay(_ w: Word, _ m: Media, _ data: Data, ref: String) {
        guard let store = ChatStore.live, MontanaP2PNode.meshDiscoverable else { return }
        let mid = "mid:mesh-" + hex(m.item)
        guard store.messages[meshRoomKey]?.contains(where: { $0.msgId == mid }) != true else { return }
        let name = store.mediaFileName(kind: m.kind, ext: m.ext, seed: mid)
        guard MontanaMediaStore.put(name, data: data) else {
            MontanaP2PTrace.mark("mesh_room", "item refused by the disk kind=\(m.kind)")
            return
        }
        store.appendMediaPlaceholder(meshRoomKey, kind: m.kind, name: name, docName: m.fileName.isEmpty ? nil : m.fileName,
                                     caption: w.text, isFromMe: false, time: "", msgId: mid, senderRef: ref,
                                     audioDuration: Double(m.durMs) / 1000)
        store.fillMedia(meshRoomKey, name: name)
        MontanaP2PTrace.mark("mesh_room", "laid item kind=\(m.kind) bytes=\(data.count)")
    }
    /// The quiet items ask for their missing pieces every five seconds, six times at most; an item not whole in three minutes
    /// is let go. The beat stands only while something is being gathered.
    private static func armRepair() {
        lock.lock()
        var born: DispatchSourceTimer?
        if !gathering.isEmpty, repair == nil {
            let t = DispatchSource.makeTimerSource(queue: itemQueue)
            t.schedule(deadline: .now() + askEvery, repeating: askEvery)
            t.setEventHandler { repairBeat() }
            repair = t
            born = t
        }
        lock.unlock()
        born?.resume()
    }
    private static func repairBeat() {
        let now = Date().timeIntervalSince1970
        var asks: [(Data, [Int])] = []
        var stopped: DispatchSourceTimer?
        lock.lock()
        for (item, g) in gathering {
            if gatherFor < now - g.first { gathering[item] = nil; continue }
            guard let m = g.media, askEvery <= now - g.last, g.asks < asksMax else { continue }
            let missing = (0 ..< m.pieces).filter { g.got[$0] == nil }
            guard !missing.isEmpty else { continue }
            var next = g; next.asks += 1; next.last = now
            gathering[item] = next
            asks.append((item, Array(missing.prefix(40))))
        }
        if gathering.isEmpty { stopped = repair; repair = nil }
        lock.unlock()
        stopped?.cancel()
        for (item, missing) in asks { MontanaBLEMesh.shared.sayInRoom(askCell(item: item, missing: missing), type: 9) }
        if !asks.isEmpty { MontanaP2PTrace.markFolded("mesh_room", "asked items=\(asks.count)", window: 10) }
    }
}
