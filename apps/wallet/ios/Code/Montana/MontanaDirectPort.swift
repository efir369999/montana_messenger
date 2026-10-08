import Foundation
import Network

// The node's direct-channel port — one constant, known to the app and to the tunnel extension alike
// ([I-10]/[C-1]). Two things depend on it being stable and shared:
//
//   • A published endpoint stays true across relaunches. With an ephemeral port every restart silently
//     invalidated every address peers held for this node, and they kept dialling a dead one.
//   • While the app is not running, the tunnel extension can stand on the same port and turn a peer's
//     knock into a notification — the sovereign first rung of the wake ladder (spec s.3 §8). The
//     extension holds no keys: it only notices the knock, the app fetches the message when opened.
//
// Handover needs no shared container and no entitlement: whoever holds the port answers a local
// connection carrying RELEASE by stepping aside.
enum MontanaDirectPort {
    static let value: UInt16 = 8447                 // Montana mesh direct channel
    static let releaseMagic = Data("MTRL".utf8)     // sent to 127.0.0.1:value — "step aside, the app is starting"

    // Ask whoever currently holds the port to let go (the app calls this before taking it back).
    static func requestRelease() {
        guard let port = NWEndpoint.Port(rawValue: value) else { return }
        let c = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
        c.start(queue: DispatchQueue.global(qos: .userInitiated))
        c.send(content: releaseMagic, completion: .contentProcessed { _ in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { c.cancel() }
        })
    }

}
