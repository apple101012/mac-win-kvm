import Foundation
import KVMCore
import KVMRuntime

// Headless: connect, print status changes, disconnect cleanly on Ctrl+C.
setvbuf(stdout, nil, _IOLBF, 0)

let endpoints: [Endpoint]
let port: UInt16
do { endpoints = try Paths.endpoints(); port = try Paths.port() } catch {
    print("error: \(error) (run mac/connect.sh or mac/install.sh first)")
    exit(1)
}

nonisolated(unsafe) var signalSources: [DispatchSourceSignal] = []

MainActor.assumeIsolated {
    let driver = ConnectionDriver(endpoints: endpoints, port: port)
    driver.onStatus = { status in
        let stamp = Date().formatted(date: .omitted, time: .standard)
        print("[\(stamp)] \(status)")
    }

    for sig in [SIGINT, SIGTERM] {
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        source.setEventHandler {
            driver.send(.quit)
            print("disconnected")
            exit(0)
        }
        source.resume()
        signalSources.append(source)
    }
    driver.send(.connect)
}
dispatchMain()
