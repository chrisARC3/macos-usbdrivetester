//
//  main.swift
//  negative-client — a deliberately FOREIGN XPC client.
//
//  Step 3's security gate (FR-ARCH-5, NFR-SEC-2) requires demonstrating that the
//  privileged helper refuses a caller not signed under our Team ID. This is that
//  caller.
//
//  Why it is not an Xcode target
//  -----------------------------
//  An Xcode target under `CODE_SIGN_STYLE = Automatic` would be signed with team
//  5JC55GTLZA — it would SATISFY the helper's requirement and prove nothing, and a
//  single mis-set signing flag would silently turn the security gate into a no-op.
//  Building it with swiftc and force-adhoc-signing it (see scripts/negative-test.sh)
//  makes "this binary is not ours" explicit and verifiable with `codesign -dvvv`.
//
//  It is compiled together with the app's Shared/TesterControl.swift, so the XPC
//  interface it uses is byte-for-byte the real contract, not a lookalike. A rejection
//  therefore cannot be blamed on a mismatched interface.
//
//  Exit status is the assertion:
//      0  = the helper did NOT serve us  -> security gate PASSED
//      1  = the helper answered us       -> security gate FAILED
//      2  = could not run the test at all (helper not installed, etc.)
//

import Foundation

/// How long to wait for the helper to either answer or tear us down.
private let timeout: TimeInterval = 10

/// Collects the outcome from whichever XPC callback fires first.
private final class Outcome: @unchecked Sendable {
    private let lock = NSLock()
    private var settled = false

    private(set) var served = false
    private(set) var detail = "no response"

    let semaphore = DispatchSemaphore(value: 0)

    func settle(served: Bool, detail: String) {
        lock.lock()
        defer { lock.unlock() }
        guard !settled else { return }
        settled = true
        self.served = served
        self.detail = detail
        semaphore.signal()
    }
}

private let outcome = Outcome()

print("negative-client: pid \(ProcessInfo.processInfo.processIdentifier)")
print("negative-client: connecting to Mach service \(HelperIdentity.machServiceName)")
print("negative-client: the helper requires [\(HelperIdentity.codeSigningRequirement)]")
print("")

let connection = NSXPCConnection(machServiceName: HelperIdentity.machServiceName,
                                 options: .privileged)
connection.remoteObjectInterface = NSXPCInterface(with: TesterControl.self)

// The expected rejection path. Per the NSXPCConnection SDK documentation the helper's
// code-signing requirement is enforced lazily: a non-conforming peer is admitted and
// then invalidated when it sends a message. So this handler — not an error at connect
// time — is what firing looks like when the gate works.
connection.invalidationHandler = {
    outcome.settle(served: false, detail: "connection invalidated by the helper")
}
connection.interruptionHandler = {
    outcome.settle(served: false, detail: "connection interrupted")
}
connection.resume()

let proxy = connection.remoteObjectProxyWithErrorHandler { error in
    outcome.settle(served: false, detail: "transport error: \(error.localizedDescription)")
}

guard let tester = proxy as? TesterControl else {
    print("negative-client: could not obtain a TesterControl proxy — cannot run the test.")
    exit(2)
}

tester.ping { reply in
    // Reaching here means the helper executed a method on our behalf.
    outcome.settle(served: true, detail: "helper replied \"\(reply)\"")
}

if outcome.semaphore.wait(timeout: .now() + timeout) == .timedOut {
    outcome.settle(served: false, detail: "no response within \(Int(timeout))s")
}

connection.invalidate()

print("negative-client: outcome — \(outcome.detail)")
print("")

if outcome.served {
    print("RESULT: SECURITY GATE FAILED")
    print("  The helper served a request from an adhoc-signed client.")
    print("  Check that ListenerDelegate calls setCodeSigningRequirement(_:) before resume(),")
    print("  and that this binary really is adhoc — `codesign -dvvv` must show")
    print("  'TeamIdentifier=not set'. A client signed with team 5JC55GTLZA is SUPPOSED to pass.")
    exit(1)
}

print("RESULT: NOT SERVED (expected)")
print("  The helper did not answer an adhoc-signed client.")
print("")
print("  NOTE: 'not served' on its own is weak evidence — a helper that is not installed")
print("  at all looks identical from here. scripts/negative-test.sh is the authoritative")
print("  harness: it confirms the daemon is loaded BEFORE running this, and afterwards")
print("  checks the helper's own log for this client's pid, so a rejection can be told")
print("  apart from an absence.")
exit(0)
