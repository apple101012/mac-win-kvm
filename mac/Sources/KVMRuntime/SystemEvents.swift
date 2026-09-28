import AppKit
import KVMCore
import Network

/// Feeds sleep, wake and network-change events into the driver.
@MainActor
public final class SystemEvents {
    private var observers: [NSObjectProtocol] = []
    private let monitor = NWPathMonitor()
    private var lastPath: String?
    private var debounce: Task<Void, Never>?

    public init(driver: ConnectionDriver) {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { driver.send(.sleep) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { driver.send(.wake) }
        })
        monitor.pathUpdateHandler = { [weak self] path in
            let key = "\(path.status) \(path.availableInterfaces.map(\.name).sorted())"
            Task { @MainActor in self?.pathChanged(key, driver: driver) }
        }
        monitor.start(queue: .main)
    }

    private func pathChanged(_ key: String, driver: ConnectionDriver) {
        defer { lastPath = key }
        guard let lastPath, lastPath != key else { return }   // ignore the initial report
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: .seconds(2))   // let DHCP / ZeroTier settle
            if !Task.isCancelled { driver.send(.networkChanged) }
        }
    }
}
