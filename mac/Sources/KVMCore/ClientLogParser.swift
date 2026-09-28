/// What a line of `deskflow-core client` output means for the connection.
public enum ClientEvent: Equatable, Sendable {
    case connected
    case disconnected
    /// One connection attempt failed; Deskflow retries by itself.
    case connectFailed
    /// Retrying won't help until something is fixed.
    case fatal(Failure)
}

public enum Failure: Equatable, Sendable {
    case serverNotTrusted
    case missingClientCertificate
    case refusedByServer
}

/// Deskflow 1.26 client log lines, see docs/adr/0001.
public enum ClientLogParser {
    public static func event(from line: String) -> ClientEvent? {
        if line.hasSuffix("IPC: connected to server") { return .connected }
        if line.hasSuffix("IPC: disconnected from server") { return .disconnected }
        if line.contains("failed to verify server certificate fingerprint") { return .fatal(.serverNotTrusted) }
        if line.contains("tls certificate doesn't exist") { return .fatal(.missingClientCertificate) }
        if line.contains("server refused client with name") { return .fatal(.refusedByServer) }
        if line.contains("failed to connect to server") || line.contains("server already has a connected client") {
            return .connectFailed
        }
        return nil
    }
}
