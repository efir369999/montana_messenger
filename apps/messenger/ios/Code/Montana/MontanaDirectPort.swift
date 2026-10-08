import Foundation

// The node's direct-channel port — one constant ([I-10]/[C-1]). A published endpoint stays true across relaunches: with an
// ephemeral port every restart silently invalidated every address peers held for this node, and they kept dialling a dead one.
enum MontanaDirectPort {
    static let value: UInt16 = 8447
}
