/// The extension from a manifest is data, never a path. Preserve normal existing names byte-for-byte.
enum MTMediaFileSuffix {
    static func of(_ value: String, kind: String) -> String {
        let bytes = value.utf8
        if !bytes.isEmpty, bytes.count <= 32,
           bytes.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }) {
            return value
        }
        switch kind {
        case "img": return "jpg"
        case "vid": return "mov"
        case "aud": return "m4a"
        default: return "dat"
        }
    }
}
