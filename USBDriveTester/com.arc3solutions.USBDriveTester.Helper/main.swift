//
//  main.swift
//  com.arc3solutions.USBDriveTester.Helper
//
//  The privileged LaunchDaemon. In the finished product this process is the ONLY
//  place raw, uncached, block-level I/O happens (FR-ARCH-6, NFR-SEC-1). For Step 1
//  it does nothing privileged: it just stands up an NSXPCListener on the helper's
//  Mach service and answers `ping` with `pong`, proving the trust-boundary plumbing.
//
//  Step 3 will add, in `shouldAcceptNewConnection`, the Team-ID code-signature
//  requirement that rejects any caller not signed by us (FR-ARCH-5, NFR-SEC-2).
//

import Foundation
import os

private let log = Logger(subsystem: "com.arc3solutions.USBDriveTester", category: "helper")

/// Concrete implementation of the XPC interface.
final class TesterControlImpl: NSObject, TesterControl {
    func ping(reply: @escaping (String) -> Void) {
        log.info("ping received; replying pong")
        reply("pong")
    }
}

/// Accepts incoming XPC connections and wires each one to a fresh exported object.
final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // STEP 3 TODO: before accepting, require the peer's code signature to match
        // our Team ID via newConnection.setCodeSigningRequirement(...). Until then
        // we accept all callers — acceptable only because nothing privileged is
        // exposed yet.
        newConnection.exportedInterface = NSXPCInterface(with: TesterControl.self)
        newConnection.exportedObject = TesterControlImpl()
        newConnection.resume()
        log.info("accepted new XPC connection")
        return true
    }
}

// Stand up the listener on the Mach service that launchd advertises for us.
let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: HelperIdentity.machServiceName)
listener.delegate = delegate
listener.resume()
log.info("helper listener resumed on \(HelperIdentity.machServiceName, privacy: .public)")

// Keep the daemon alive to service connections.
dispatchMain()
