import Foundation
import KVMCore

/// Runs a ConnectionController against the real world: probes, the Deskflow client process, retry timers.
/// Everything happens on the main actor; events from stale client processes are dropped.
@MainActor
public final class ConnectionDriver {
    public var onStatus: ((ConnectionStatus) -> Void)?
    public var status: ConnectionStatus { controller.status }
    public let port: UInt16

    private let controller: ConnectionController
    private var client: ClientProcess?
    private var generation = 0
    private var retryTask: Task<Void, Never>?

    public init(endpoints: [Endpoint], port: UInt16) {
        controller = ConnectionController(endpoints: endpoints)
        self.port = port
    }

    public func send(_ event: ConnectionEvent) {
        for effect in controller.handle(event) { perform(effect) }
    }

    private func perform(_ effect: ConnectionEffect) {
        switch effect {
        case .publish(let s):
            onStatus?(s)
        case .probe(let e):
            let port = self.port
            Task { [weak self] in
                let ok = await probeTCP(host: e.host, port: port)
                self?.send(.probeResult(e, reachable: ok))
            }
        case .startClient(let e):
            generation += 1
            let gen = generation
            let p = ClientProcess(
                settings: Paths.settingsFile(for: e.route),
                onEvent: { ev in Task { @MainActor [weak self] in self?.fromClient(gen, .client(ev)) } },
                onExit: { Task { @MainActor [weak self] in self?.fromClient(gen, .clientExited) } })
            client = p
            do { try p.start() } catch { fromClient(gen, .clientExited) }
        case .stopClient:
            generation += 1
            client?.stop()
            client = nil
        case .scheduleRetry(let seconds):
            retryTask?.cancel()
            retryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                if !Task.isCancelled { self?.send(.retryTimerFired) }
            }
        case .cancelRetry:
            retryTask?.cancel()
            retryTask = nil
        }
    }

    private func fromClient(_ gen: Int, _ event: ConnectionEvent) {
        guard gen == generation else { return }
        send(event)
    }
}
