import Testing
@testable import KVMCore

let lan = Endpoint(route: .lan, host: "192.168.1.10")
let zerotier = Endpoint(route: .zerotier, host: "100.64.0.10")

func makeController() -> ConnectionController { ConnectionController(endpoints: [lan, zerotier]) }

/// Drives the controller like the app would and returns the effects of the last event.
@discardableResult
func send(_ c: ConnectionController, _ events: ConnectionEvent...) -> [ConnectionEffect] {
    var last: [ConnectionEffect] = []
    for e in events { last = c.handle(e) }
    return last
}

@Suite struct ConnectionControllerTests {
    @Test func startsDisconnected() {
        #expect(makeController().status == .disconnected)
    }

    @Test func connectProbesLanFirst() {
        let c = makeController()
        #expect(send(c, .connect) == [.publish(.connecting), .probe(lan)])
    }

    @Test func reachableLanStartsTheClientOnLan() {
        let c = makeController()
        #expect(send(c, .connect, .probeResult(lan, reachable: true)) == [.startClient(lan)])
        #expect(c.status == .connecting)
    }

    @Test func clientConnectedPublishesTheRoute() {
        let c = makeController()
        let effects = send(c, .connect, .probeResult(lan, reachable: true), .client(.connected))
        #expect(effects == [.publish(.connected(.lan))])
        #expect(c.status == .connected(.lan))
    }

    @Test func unreachableLanFallsBackToZeroTier() {
        let c = makeController()
        #expect(send(c, .connect, .probeResult(lan, reachable: false)) == [.probe(zerotier)])
        #expect(send(c, .probeResult(zerotier, reachable: true)) == [.startClient(zerotier)])
        #expect(send(c, .client(.connected)) == [.publish(.connected(.zerotier))])
    }

    @Test func bothUnreachableRetriesWithBackoff() {
        let c = makeController()
        send(c, .connect, .probeResult(lan, reachable: false))
        #expect(send(c, .probeResult(zerotier, reachable: false)) == [.publish(.unreachable), .scheduleRetry(seconds: 2)])
        #expect(send(c, .retryTimerFired) == [.probe(lan)])
        send(c, .probeResult(lan, reachable: false))
        #expect(send(c, .probeResult(zerotier, reachable: false)) == [.scheduleRetry(seconds: 4)])
    }

    @Test func backoffIsCappedAt30Seconds() {
        let c = makeController()
        send(c, .connect)
        var delays: [Int] = []
        for _ in 0..<8 {
            send(c, .probeResult(lan, reachable: false))
            for case let .scheduleRetry(s) in send(c, .probeResult(zerotier, reachable: false)) { delays.append(s) }
            send(c, .retryTimerFired)
        }
        #expect(delays == [2, 4, 8, 16, 30, 30, 30, 30])
    }

    @Test func successResetsTheBackoff() {
        let c = makeController()
        send(c, .connect, .probeResult(lan, reachable: false), .probeResult(zerotier, reachable: false), .retryTimerFired)
        send(c, .probeResult(lan, reachable: true), .client(.connected), .client(.disconnected))
        send(c, .probeResult(lan, reachable: false))
        #expect(send(c, .probeResult(zerotier, reachable: false)) == [.publish(.unreachable), .scheduleRetry(seconds: 2)])
    }

    @Test func droppedConnectionStopsTheClientAndStartsOverFromLan() {
        let c = makeController()
        send(c, .connect, .probeResult(lan, reachable: true), .client(.connected))
        #expect(send(c, .client(.disconnected)) == [.stopClient, .publish(.connecting), .probe(lan)])
    }

    @Test func repeatedConnectFailuresFallBackToTheNextRoute() {
        // e.g. LAN port is open but the client never gets through (VPN, firewall)
        let c = makeController()
        send(c, .connect, .probeResult(lan, reachable: true))
        #expect(send(c, .client(.connectFailed)) == [])
        #expect(send(c, .client(.connectFailed)) == [])
        #expect(send(c, .client(.connectFailed)) == [.stopClient, .probe(zerotier)])
    }

    @Test func unexpectedClientExitRetries() {
        let c = makeController()
        send(c, .connect, .probeResult(lan, reachable: true), .client(.connected))
        #expect(send(c, .clientExited) == [.publish(.connecting), .probe(lan)])
    }

    @Test func certificateFailureStopsWithoutRetrying() {
        let c = makeController()
        send(c, .connect, .probeResult(lan, reachable: true))
        #expect(send(c, .client(.fatal(.serverNotTrusted))) == [.stopClient, .publish(.failed(.serverNotTrusted))])
        #expect(send(c, .clientExited) == [])
        #expect(send(c, .retryTimerFired) == [])
    }

    @Test func disconnectStopsEverything() {
        let c = makeController()
        send(c, .connect, .probeResult(lan, reachable: true), .client(.connected))
        #expect(send(c, .disconnect) == [.stopClient, .cancelRetry, .publish(.disconnected)])
        #expect(send(c, .clientExited) == [])
        #expect(send(c, .retryTimerFired) == [])
        #expect(send(c, .probeResult(lan, reachable: true)) == [])
    }

    @Test func disconnectWhileDisconnectedDoesNothing() {
        #expect(send(makeController(), .disconnect) == [])
    }

    @Test func connectWhileConnectedDoesNothing() {
        let c = makeController()
        send(c, .connect, .probeResult(lan, reachable: true), .client(.connected))
        #expect(send(c, .connect) == [])
    }

    @Test func connectAfterFailureTriesAgain() {
        let c = makeController()
        send(c, .connect, .probeResult(lan, reachable: true), .client(.fatal(.serverNotTrusted)))
        #expect(send(c, .connect) == [.publish(.connecting), .probe(lan)])
    }

    @Test func staleProbeResultsAreIgnored() {
        let c = makeController()
        send(c, .connect, .probeResult(lan, reachable: true))
        #expect(send(c, .probeResult(zerotier, reachable: true)) == [])
    }

    @Test func quitStopsTheClient() {
        let c = makeController()
        send(c, .connect, .probeResult(lan, reachable: true), .client(.connected))
        #expect(send(c, .quit) == [.stopClient, .cancelRetry])
    }
}

@Suite struct AutoConnectAndSleepTests {
    @Test func sleepWhileConnectedStopsAndWakeReconnects() {
        let c = makeController()
        send(c, .connect, .probeResult(lan, reachable: true), .client(.connected))
        #expect(send(c, .sleep) == [.stopClient, .cancelRetry, .publish(.disconnected)])
        #expect(send(c, .wake) == [.publish(.connecting), .probe(lan)])
    }

    @Test func wakeAfterDisconnectedSleepStaysDisconnected() {
        let c = makeController()
        #expect(send(c, .sleep) == [])
        #expect(send(c, .wake) == [])
        #expect(c.status == .disconnected)
    }

    @Test func manualDisconnectBeforeSleepIsRespectedOnWake() {
        let c = makeController()
        send(c, .connect, .probeResult(lan, reachable: true), .client(.connected), .disconnect)
        send(c, .sleep)
        #expect(send(c, .wake) == [])
    }

    @Test func sleepWhileRetryingReconnectsOnWake() {
        let c = makeController()
        send(c, .connect, .probeResult(lan, reachable: false), .probeResult(zerotier, reachable: false))
        send(c, .sleep)
        #expect(send(c, .wake) == [.publish(.connecting), .probe(lan)])
    }

    @Test func autoConnectOnProbesQuietlyWhileDisconnected() {
        let c = makeController()
        #expect(send(c, .setAutoConnect(true)) == [.probe(lan)])
        #expect(c.status == .disconnected)
    }

    @Test func autoConnectConnectsWhenTheDesktopIsReachable() {
        let c = makeController()
        send(c, .setAutoConnect(true))
        #expect(send(c, .probeResult(lan, reachable: true)) == [.publish(.connecting), .startClient(lan)])
    }

    @Test func autoConnectStaysQuietWhenUnreachable() {
        // e.g. at work: no "unreachable" status, no nagging, just a slow background check
        let c = makeController()
        send(c, .setAutoConnect(true))
        #expect(send(c, .probeResult(lan, reachable: false)) == [.probe(zerotier)])
        #expect(send(c, .probeResult(zerotier, reachable: false)) == [.scheduleRetry(seconds: 30)])
        #expect(c.status == .disconnected)
        #expect(send(c, .retryTimerFired) == [.probe(lan)])
    }

    @Test func autoConnectOffCancelsTheBackgroundCheck() {
        let c = makeController()
        send(c, .setAutoConnect(true), .probeResult(lan, reachable: false), .probeResult(zerotier, reachable: false))
        #expect(send(c, .setAutoConnect(false)) == [.cancelRetry])
        #expect(send(c, .retryTimerFired) == [])
    }

    @Test func autoConnectOffDoesNotDisconnectAnActiveConnection() {
        let c = makeController()
        send(c, .setAutoConnect(true), .probeResult(lan, reachable: true), .client(.connected))
        #expect(send(c, .setAutoConnect(false)) == [])
        #expect(c.status == .connected(.lan))
    }

    @Test func networkChangeTriggersAnImmediateCheckWhenAutoConnecting() {
        let c = makeController()
        send(c, .setAutoConnect(true), .probeResult(lan, reachable: false), .probeResult(zerotier, reachable: false))
        #expect(send(c, .networkChanged) == [.cancelRetry, .probe(lan)])
    }

    @Test func networkChangeWhileUnreachableRetriesNow() {
        let c = makeController()
        send(c, .connect, .probeResult(lan, reachable: false), .probeResult(zerotier, reachable: false))
        #expect(send(c, .networkChanged) == [.cancelRetry, .probe(lan)])
    }

    @Test func networkChangeWhileDisconnectedWithoutAutoConnectDoesNothing() {
        #expect(send(makeController(), .networkChanged) == [])
    }

    @Test func manualDisconnectWithAutoConnectOnStaysDisconnectedUntilWakeOrNetworkChange() {
        // otherwise Disconnect would be undone seconds later by the background check
        let c = makeController()
        send(c, .setAutoConnect(true), .probeResult(lan, reachable: true), .client(.connected))
        #expect(send(c, .disconnect) == [.stopClient, .cancelRetry, .publish(.disconnected)])
        #expect(send(c, .retryTimerFired) == [])
        #expect(send(c, .networkChanged) == [.cancelRetry, .probe(lan)])
    }

    @Test func autoConnectResumesAfterWake() {
        let c = makeController()
        send(c, .setAutoConnect(true), .probeResult(lan, reachable: false), .probeResult(zerotier, reachable: false))
        send(c, .sleep)
        #expect(send(c, .wake) == [.probe(lan)])
    }
}

@Suite struct PreferLanTests {
    func onZeroTier() -> ConnectionController {
        let c = makeController()
        send(c, .connect, .probeResult(lan, reachable: false), .probeResult(zerotier, reachable: true), .client(.connected))
        return c
    }

    @Test func networkChangeOnZeroTierChecksLan() {
        #expect(send(onZeroTier(), .networkChanged) == [.probe(lan)])
    }

    @Test func movesBackToLanWhenItBecomesReachable() {
        let c = onZeroTier()
        send(c, .networkChanged)
        #expect(send(c, .probeResult(lan, reachable: true)) == [.stopClient, .publish(.connecting), .startClient(lan)])
        #expect(send(c, .client(.connected)) == [.publish(.connected(.lan))])
    }

    @Test func staysOnZeroTierWhenLanIsStillUnreachable() {
        let c = onZeroTier()
        send(c, .networkChanged)
        #expect(send(c, .probeResult(lan, reachable: false)) == [])
        #expect(c.status == .connected(.zerotier))
    }

    @Test func networkChangeOnLanDoesNothing() {
        let c = makeController()
        send(c, .connect, .probeResult(lan, reachable: true), .client(.connected))
        #expect(send(c, .networkChanged) == [])
    }

    @Test func statusDescriptions() {
        #expect(ConnectionStatus.connected(.zerotier).description == "Connected via fallback (ZeroTier/Tailscale)")
        #expect(ConnectionStatus.unreachable.description == "Desktop unreachable — retrying")
    }
}
