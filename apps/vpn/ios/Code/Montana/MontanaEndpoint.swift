import Foundation

/// The address at which a machine can be reached, and its kind.
///
/// This is all that is left of the layer that kept a MAP of the network. The map is deleted whole --
/// not as a debt, but because the set forbids it to exist: "No global list of devices exists and none can be
/// assembled», «an address is never relayed beyond one step», «There is nothing to collect, so no
/// list forms". Here stood a node table, signed records "this machine lives here" with a two-hour term
/// and an exchange of "and whom else do you know" -- that is, exactly the assembly of a device list and
/// the passing of endpoints further than one hop.
///
/// An address by itself belongs "to the world, not to the set": an implementation carries what an
/// introduction gave it. So the type stays and the directory does not.
struct MontanaEndpoint: Equatable {
    enum Kind: UInt8 { case relay = 0x01, directV6 = 0x02, directV4 = 0x03 }
    let kind: Kind
    let endpoint: String        // "ip:port" or the identifier of a carrying chain

    func encode() -> Data {
        var d = Data([kind.rawValue])
        let a = Data(endpoint.utf8)
        d.append(UInt8(min(a.count, 255)))
        d.append(a.prefix(255))
        return d
    }
    static func decode(_ d: Data, _ o: inout Int) -> MontanaEndpoint? {
        guard o + 2 <= d.count, let k = Kind(rawValue: d[d.startIndex + o]) else { return nil }
        let al = Int(d[d.startIndex + o + 1]); o += 2
        guard o + al <= d.count else { return nil }
        let a = String(data: d.subdata(in: (d.startIndex + o)..<(d.startIndex + o + al)), encoding: .utf8) ?? ""
        o += al
        return MontanaEndpoint(kind: k, endpoint: a)
    }
}
