import AppKit
import KVMCore
import KVMRuntime
import ServiceManagement
import SwiftUI

@main
struct MacWinKVMApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuContent(model: delegate.model)
        } label: {
            Image(systemName: delegate.model.iconName)
        }
    }
}

/// No Dock icon (LSUIElement). Opening the app from Finder/Spotlight/Launchpad shows the window;
/// the login agent starts it with --background so it stays out of sight.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var window: NSWindow?
    static let showWindowNotification = Notification.Name("io.github.macwinkvm.show")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // a second copy (e.g. opened while the login-agent copy runs): hand over to the first and quit
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0 != .current }
        if !others.isEmpty {
            DistributedNotificationCenter.default().postNotificationName(Self.showWindowNotification, object: nil,
                                                                         deliverImmediately: true)
            exit(0)
        }
        DistributedNotificationCenter.default().addObserver(forName: Self.showWindowNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.showWindow() }
        }
        model.migrateLoginItem()
        if !CommandLine.arguments.contains("--background") { showWindow() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func showWindow() {
        if window == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "MacWinKVM"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: MainWindow(model: model))
            w.setContentSize(w.contentView!.fittingSize)
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct MainWindow: View {
    @Bindable var model: AppModel
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: model.iconName).font(.system(size: 28)).foregroundStyle(model.isConnected ? .green : .secondary)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.statusText).font(.headline)
                    Text("Desktop: \(model.desktopDescription)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.isActive {
                    Button("Disconnect") { model.disconnect() }.controlSize(.large)
                } else {
                    Button("Connect") { model.connect() }.controlSize(.large).buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Auto-connect when the desktop is reachable", isOn: $model.autoConnect)
                Toggle("Launch at login (hidden)", isOn: $model.launchAtLogin)
                Toggle("Show icon in the menu bar", isOn: $showMenuBarIcon)
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow { Text("Switch machine").foregroundStyle(.secondary); Text("screen edge  ·  Win+Esc") }
                GridRow { Text("Lock to current").foregroundStyle(.secondary); Text("Scroll Lock") }
                GridRow { Text("On the Mac").foregroundStyle(.secondary); Text("Alt = ⌘   Win = ⌥   Ctrl = ⌃") }
                GridRow { Text("Keyboard lighting").foregroundStyle(.secondary); Text("white Windows · blue Mac · red/purple locked") }
            }
            .font(.callout)

            HStack {
                Button("View Logs") { model.openLogs() }
                Spacer()
                Button("Quit macwinkvm") { model.quit() }
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

struct MenuContent: View {
    @Bindable var model: AppModel

    var body: some View {
        Text(model.statusText)
        Divider()
        if model.isActive {
            Button("Disconnect") { model.disconnect() }.keyboardShortcut("d")
        } else {
            Button("Connect") { model.connect() }.keyboardShortcut("c")
        }
        Divider()
        Toggle("Auto-connect at Home", isOn: $model.autoConnect)
        Toggle("Launch at Login", isOn: $model.launchAtLogin)
        Button("View Logs") { model.openLogs() }
        Divider()
        Button("Quit macwinkvm") { model.quit() }.keyboardShortcut("q")
    }
}

@MainActor @Observable
final class AppModel {
    private(set) var status: ConnectionStatus = .disconnected
    private(set) var setupError: String?
    private var driver: ConnectionDriver?
    private var systemEvents: SystemEvents?
    private let clipboardFixer = ClipboardImageFixer()

    var autoConnect: Bool = UserDefaults.standard.bool(forKey: "autoConnect") {
        didSet {
            UserDefaults.standard.set(autoConnect, forKey: "autoConnect")
            driver?.send(.setAutoConnect(autoConnect))
        }
    }

    init() {
        do {
            let d = ConnectionDriver(endpoints: try Paths.endpoints(), port: try Paths.port())
            d.onStatus = { [weak self] s in
                self?.status = s
                if case .connected = s { self?.clipboardFixer.enabled = true } else { self?.clipboardFixer.enabled = false }
            }
            driver = d
            systemEvents = SystemEvents(driver: d)
            if autoConnect { d.send(.setAutoConnect(true)) }
        } catch {
            setupError = "Not set up — run mac/install.sh"
        }
    }

    var isActive: Bool {
        switch status {
        case .connecting, .connected, .unreachable: true
        case .disconnected, .failed: false
        }
    }

    var statusText: String { setupError ?? status.description }

    var isConnected: Bool {
        if case .connected = status { return true }
        return false
    }

    var desktopDescription: String {
        guard let e = try? Paths.endpoints() else { return "not set up" }
        return e.map { "\($0.host) (\($0.route == .lan ? "LAN" : "fallback"))" }.joined(separator: " · ")
    }

    var iconName: String {
        switch status {
        case .connected: "keyboard.fill"
        case .connecting, .unreachable: "keyboard.badge.ellipsis"
        case .failed: "keyboard.badge.exclamationmark"
        case .disconnected: "keyboard"
        }
    }

    func connect() { driver?.send(.connect) }
    func disconnect() { driver?.send(.disconnect) }

    func quit() {
        driver?.send(.quit)
        NSApp.terminate(nil)
    }

    func openLogs() {
        NSWorkspace.shared.open(Paths.clientLog)
    }

    /// Login agent that starts the app with --background (Contents/Library/LaunchAgents).
    private let loginAgent = SMAppService.agent(plistName: "io.github.macwinkvm.agent.plist")

    var launchAtLogin: Bool {
        get { loginChanges >= 0 && loginAgent.status == .enabled }
        set {
            do {
                if newValue { try loginAgent.register() } else { try loginAgent.unregister() }
            } catch {
                NSLog("launch at login: \(error)")
            }
            loginChanges += 1
        }
    }
    private var loginChanges = 0   // lets SwiftUI observe the change

    /// Earlier versions registered the app itself as the login item, which opened the window at login.
    func migrateLoginItem() {
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
            launchAtLogin = true
        }
    }
}
