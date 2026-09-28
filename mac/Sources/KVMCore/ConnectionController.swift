public enum Route: String, Equatable, Sendable { case lan, zerotier }

public struct Endpoint: Equatable, Sendable {
    public let route: Route
    public let host: String
    public init(route: Route, host: String) { self.route = route; self.host = host }
}

public enum ConnectionStatus: Equatable, Sendable {
    case disconnected
    case connecting
    case connected(Route)
    case unreachable
    case failed(Failure)
}

public enum ConnectionEvent: Equatable, Sendable {
    case connect
    case disconnect
    case quit
    case setAutoConnect(Bool)
    case sleep
    case wake
    case networkChanged
    case probeResult(Endpoint, reachable: Bool)
    case client(ClientEvent)
    case clientExited
    case retryTimerFired
}

public enum ConnectionEffect: Equatable, Sendable {
    case probe(Endpoint)
    case startClient(Endpoint)
    case stopClient
    case scheduleRetry(seconds: Int)
    case cancelRetry
    case publish(ConnectionStatus)
}

/// All Mac-side connection decisions: events in, effects out. No I/O.
///
/// - Tries endpoints in order (LAN, then ZeroTier), backing off while none is reachable.
/// - A connection the user asked for ("wanted") retries loudly and survives sleep.
/// - With auto-connect on, the desktop is checked quietly in the background and joined when reachable;
///   a manual Disconnect pauses that until the next wake or network change.
public final class ConnectionController {
    public private(set) var status: ConnectionStatus = .disconnected

    private let endpoints: [Endpoint]
    private enum Phase: Equatable {
        case idle
        case probing(index: Int, background: Bool)
        case running(index: Int, failures: Int, checkingPreferred: Bool = false)
        case waitingToRetry(background: Bool)
    }
    private var phase: Phase = .idle
    private var wanted = false
    private var autoConnect = false
    private var autoPaused = false
    private var retryDelay = 2

    static let failuresBeforeNextRoute = 3
    static let maxRetryDelay = 30
    static let backgroundCheckInterval = 30

    public init(endpoints: [Endpoint]) {
        precondition(!endpoints.isEmpty)
        self.endpoints = endpoints
    }

    public func handle(_ event: ConnectionEvent) -> [ConnectionEffect] {
        switch (event, phase) {
        case (.connect, .running):
            return []
        case (.connect, _):
            wanted = true
            return restart()

        case (.disconnect, let p):
            let wasActive = wanted || p != .idle
            wanted = false
            autoPaused = true
            phase = .idle
            guard wasActive else { return [] }
            return stopIfRunning(p) + [.cancelRetry] + publish(.disconnected)

        case (.quit, let p):
            phase = .idle
            return stopIfRunning(p) + [.cancelRetry]

        case (.setAutoConnect(let on), let p):
            autoConnect = on
            if on {
                return p == .idle && !wanted && !autoPaused ? startBackgroundCheck() : []
            }
            if isBackground(p) {
                phase = .idle
                return [.cancelRetry]
            }
            return []

        case (.sleep, let p):
            phase = .idle
            guard p != .idle else { return [] }
            return stopIfRunning(p) + [.cancelRetry] + publish(.disconnected)

        case (.wake, _):
            autoPaused = false
            if wanted { return restart() }
            return autoConnect ? startBackgroundCheck() : []

        case (.networkChanged, .running(let i, let failures, _)) where i > 0:
            phase = .running(index: i, failures: failures, checkingPreferred: true)
            return [.probe(endpoints[0])]
        case (.probeResult(let e, let reachable), .running(let i, let failures, true)) where e == endpoints[0]:
            guard reachable else {
                phase = .running(index: i, failures: failures)
                return []
            }
            phase = .running(index: 0, failures: 0)
            return [.stopClient] + publish(.connecting) + [.startClient(e)]

        case (.networkChanged, .waitingToRetry(let background)):
            phase = .probing(index: 0, background: background)
            return [.cancelRetry, .probe(endpoints[0])]
        case (.networkChanged, .idle) where autoConnect && !wanted:
            autoPaused = false
            return [.cancelRetry] + startBackgroundCheck()

        case (.probeResult(let e, let reachable), .probing(let i, let background)) where e == endpoints[i]:
            if reachable {
                phase = .running(index: i, failures: 0)
                return (background ? publish(.connecting) : []) + [.startClient(e)]
            }
            return next(after: i, background: background)

        case (.client(.connected), .running(let i, _, _)):
            phase = .running(index: i, failures: 0)
            retryDelay = 2
            return publish(.connected(endpoints[i].route))

        case (.client(.connectFailed), .running(let i, let failures, _)):
            if failures + 1 < Self.failuresBeforeNextRoute {
                phase = .running(index: i, failures: failures + 1)
                return []
            }
            return [.stopClient] + next(after: i, background: !wanted)

        case (.client(.disconnected), .running):
            return [.stopClient] + restart()

        case (.client(.fatal(let failure)), .running):
            phase = .idle
            wanted = false
            autoPaused = true   // don't re-fail every 30 s; the next wake/network change or Connect tries again
            return [.stopClient] + publish(.failed(failure))

        case (.clientExited, .running):
            return restart()

        case (.retryTimerFired, .waitingToRetry(let background)):
            phase = .probing(index: 0, background: background)
            return [.probe(endpoints[0])]

        default:
            return []
        }
    }

    /// Start over from the first endpoint, loudly if the user wants a connection, else quietly if auto-connecting.
    private func restart() -> [ConnectionEffect] {
        if wanted {
            phase = .probing(index: 0, background: false)
            return publish(.connecting) + [.probe(endpoints[0])]
        }
        if autoConnect {
            return publish(.disconnected) + startBackgroundCheck()
        }
        phase = .idle
        return publish(.disconnected)
    }

    private func startBackgroundCheck() -> [ConnectionEffect] {
        phase = .probing(index: 0, background: true)
        return [.probe(endpoints[0])]
    }

    private func next(after i: Int, background: Bool) -> [ConnectionEffect] {
        if i + 1 < endpoints.count {
            phase = .probing(index: i + 1, background: background)
            return [.probe(endpoints[i + 1])]
        }
        phase = .waitingToRetry(background: background)
        if background {
            return publish(.disconnected) + [.scheduleRetry(seconds: Self.backgroundCheckInterval)]
        }
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, Self.maxRetryDelay)
        return publish(.unreachable) + [.scheduleRetry(seconds: delay)]
    }

    private func isBackground(_ p: Phase) -> Bool {
        switch p {
        case .probing(_, let b), .waitingToRetry(let b): b
        default: false
        }
    }

    private func stopIfRunning(_ p: Phase) -> [ConnectionEffect] {
        if case .running = p { return [.stopClient] }
        return []
    }

    /// Publishes only actual status changes.
    private func publish(_ s: ConnectionStatus) -> [ConnectionEffect] {
        guard s != status else { return [] }
        status = s
        return [.publish(s)]
    }
}

extension ConnectionStatus: CustomStringConvertible {
    public var description: String {
        switch self {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting…"
        case .connected(.lan): "Connected via LAN"
        case .connected(.zerotier): "Connected via fallback (ZeroTier/Tailscale)"
        case .unreachable: "Desktop unreachable — retrying"
        case .failed(.serverNotTrusted): "Desktop certificate not trusted — copy trust/server.sha256 from the desktop, re-run mac/install.sh"
        case .failed(.missingClientCertificate): "Mac certificate missing — run mac/install.sh"
        case .failed(.refusedByServer): "Desktop refused this Mac — check names in settings.json"
        }
    }
}
