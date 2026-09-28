import Testing
@testable import KVMCore

@Suite struct ClientLogParserTests {
    @Test func connected() {
        #expect(ClientLogParser.event(from: "[2026-09-27T21:42:04.520] IPC: connected to server") == .connected)
    }

    @Test func disconnected() {
        #expect(ClientLogParser.event(from: "[2026-09-27T21:50:00.000] IPC: disconnected from server") == .disconnected)
    }

    @Test func connectAttemptFailedIsTransient() {
        #expect(ClientLogParser.event(from: "[2026-09-27T21:32:50.565] WARNING: failed to connect to server: Timed out") == .connectFailed)
        #expect(ClientLogParser.event(from: "[x] ERROR: server already has a connected client with name \"MacBook\"") == .connectFailed)
    }

    @Test func certificateProblemsAreFatal() {
        #expect(ClientLogParser.event(from: "[x] ERROR: failed to verify server certificate fingerprint") == .fatal(.serverNotTrusted))
        #expect(ClientLogParser.event(from: "[x] ERROR: secure socket error: tls certificate doesn't exist: /a/tls/deskflow.pem") == .fatal(.missingClientCertificate))
        #expect(ClientLogParser.event(from: "[x] ERROR: server refused client with name \"MacBook\"") == .fatal(.refusedByServer))
    }

    @Test func noiseIsIgnored() {
        #expect(ClientLogParser.event(from: "[x] DEBUG: opening new socket: FCD09930") == nil)
        #expect(ClientLogParser.event(from: "[x] IPC: connecting to '192.168.1.10': 192.168.1.10:24800") == nil)
        #expect(ClientLogParser.event(from: "") == nil)
    }
}
