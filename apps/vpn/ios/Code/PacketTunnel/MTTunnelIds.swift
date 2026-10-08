import Foundation

/// One source of the tunnel identifier: the extension reads it from its own bundle,
/// the app derives it from its own. Nothing is spelled out twice.
enum MTTunnelIds {
    static let extensionBundleId = Bundle.main.bundleIdentifier ?? "p2p.montana.app.PacketTunnel"
}
