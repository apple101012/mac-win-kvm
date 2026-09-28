import Darwin
import Foundation
import KVMCore

/// Runs `deskflow-core client` and reports its output as ClientEvents.
/// - deskflow-core ignores SIGTERM/SIGINT on macOS (docs/adr/0001), so stop() uses SIGKILL.
/// - It is spawned "responsibility-disclaimed", so macOS asks for Accessibility for Deskflow itself
///   rather than for this (ad-hoc signed, frequently rebuilt) app.
final class ClientProcess: @unchecked Sendable {
    private let settings: URL
    private let onEvent: @Sendable (ClientEvent) -> Void
    private let onExit: @Sendable () -> Void
    private(set) var pid: pid_t = 0
    private var readSource: DispatchSourceRead?
    private var exitSource: DispatchSourceProcess?
    private var buffer = Data()
    private let queue = DispatchQueue(label: "macwinkvm.client")

    init(settings: URL, onEvent: @escaping @Sendable (ClientEvent) -> Void, onExit: @escaping @Sendable () -> Void) {
        self.settings = settings
        self.onEvent = onEvent
        self.onExit = onExit
    }

    func start() throws {
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { throw RuntimeError("pipe failed") }
        let (readFD, writeFD) = (fds[0], fds[1])

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, writeFD, 1)
        posix_spawn_file_actions_adddup2(&actions, writeFD, 2)
        posix_spawn_file_actions_addclose(&actions, readFD)

        var attrs: posix_spawnattr_t?
        posix_spawnattr_init(&attrs)
        defer { posix_spawnattr_destroy(&attrs) }
        disclaimResponsibility(&attrs)

        let args = [Paths.deskflowCore, "client", "--new-instance", "-s", settings.path]
        let argv: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }

        let rc = posix_spawn(&pid, Paths.deskflowCore, &actions, &attrs, argv, environ)
        close(writeFD)
        guard rc == 0 else { close(readFD); throw RuntimeError("could not start deskflow-core (\(rc))") }

        let read = DispatchSource.makeReadSource(fileDescriptor: readFD, queue: queue)
        read.setEventHandler { [weak self] in
            var chunk = [UInt8](repeating: 0, count: 4096)
            let n = Darwin.read(readFD, &chunk, chunk.count)
            if n <= 0 { read.cancel(); return }
            self?.consume(chunk[0..<n])
        }
        read.setCancelHandler { close(readFD) }
        read.resume()
        readSource = read

        let exit = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
        exit.setEventHandler { [weak self] in
            guard let self else { return }
            var status: Int32 = 0
            waitpid(self.pid, &status, 0)
            exit.cancel()
            self.onExit()
        }
        exit.resume()
        exitSource = exit
    }

    func stop() {
        if pid > 0 { kill(pid, SIGKILL) }
    }

    private func consume(_ bytes: ArraySlice<UInt8>) {
        buffer.append(contentsOf: bytes)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: buffer[..<nl], as: UTF8.self)
            buffer.removeSubrange(...nl)
            if let e = ClientLogParser.event(from: line) { onEvent(e) }
        }
    }
}

/// Private but long-stable libSystem call (used by Terminal, iTerm, VS Code). No-op if missing.
private func disclaimResponsibility(_ attrs: inout posix_spawnattr_t?) {
    typealias Fn = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32
    guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_spawnattrs_setdisclaim") else { return }
    _ = unsafeBitCast(sym, to: Fn.self)(&attrs, 1)
}
