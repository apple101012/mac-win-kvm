import Foundation
import Network

/// Is anything accepting TCP connections on host:port? Resolves within `timeout`.
public func probeTCP(host: String, port: UInt16, timeout: TimeInterval = 1.5) async -> Bool {
    await withCheckedContinuation { cont in
        let conn = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        let done = OnceFlag()
        let finish: @Sendable (Bool) -> Void = { ok in
            if done.set() { conn.cancel(); cont.resume(returning: ok) }
        }
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready: finish(true)
            case .failed, .waiting: finish(false)
            default: break
            }
        }
        conn.start(queue: .global())
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(false) }
    }
}

final class OnceFlag: @unchecked Sendable {
    private var fired = false
    private let lock = NSLock()
    /// true the first time only
    func set() -> Bool { lock.withLock { defer { fired = true }; return !fired } }
}
