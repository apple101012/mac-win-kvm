import Foundation
import KVMCore

/// Files written by mac/install.sh (or mac/connect.sh). One Deskflow settings file per route;
/// they share tls/ because Deskflow looks for it next to the settings file.
public enum Paths {
    public static let deskflowCore = "/Applications/Deskflow.app/Contents/MacOS/deskflow-core"
    public static let stateDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/macwinkvm")
    public static let clientLog = stateDir.appendingPathComponent("client.log")

    public static func settingsFile(for route: Route) -> URL {
        stateDir.appendingPathComponent("Deskflow-\(route.rawValue).conf")
    }

    /// LAN first, then the optional fallback (ZeroTier / Tailscale); host read from each settings file's client/remoteHost.
    public static func endpoints() throws -> [Endpoint] {
        let lan = Endpoint(route: .lan, host: try value("remoteHost", in: settingsFile(for: .lan)))
        // the fallback (ZeroTier / Tailscale) is optional
        let fallback = try? Endpoint(route: .zerotier, host: value("remoteHost", in: settingsFile(for: .zerotier)))
        return [lan] + (fallback.map { [$0] } ?? [])
    }

    /// core/port from the generated settings (same for both routes).
    public static func port() throws -> UInt16 {
        let text = try value("port", in: settingsFile(for: .lan))
        guard let port = UInt16(text) else { throw RuntimeError("bad port \(text)") }
        return port
    }

    private static func value(_ key: String, in file: URL) throws -> String {
        let text = try String(contentsOf: file, encoding: .utf8)
        guard let line = text.split(separator: "\n").first(where: { $0.hasPrefix(key + "=") }) else {
            throw RuntimeError("no \(key) in \(file.path)")
        }
        return String(line.dropFirst(key.count + 1))
    }
}

public struct RuntimeError: Error, CustomStringConvertible {
    public let description: String
    public init(_ d: String) { description = d }
}
