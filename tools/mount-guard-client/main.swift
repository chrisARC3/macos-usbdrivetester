//
//  main.swift
//  mount-guard-client — drives the helper's Step 6 device methods from the CLI.
//
//  ## Why this exists
//
//  Step 6's gate has to show that the helper distinguishes FR-SAFE-4's two causes, and
//  cause (b) — "unmounted, but another process holds the node" — cannot be produced from
//  the GUI: something else has to be holding the disk at the moment the acquire happens.
//  `scripts/claim-contention-test.sh` arranges that with `exclusivity-probe --hold` and
//  uses this client to ask the helper what it sees.
//
//  It also moves the *classification* half of gate items 1 and 2 off "needs a person".
//  A human reading two prose messages can confirm they differ; this asserts the cause
//  code, which is the thing the app actually branches on.
//
//  ## Signed with the real Team ID, unlike tools/negative-client
//
//  `negative-client` is adhoc-signed on purpose, to prove the helper refuses foreign
//  callers. This one must be signed as Apple Development under team 5JC55GTLZA or the
//  helper will invalidate it on its first message and every result would read as a
//  transport failure. The script signs it and then asserts the Team ID is present —
//  the inverse of the check negative-test.sh makes.
//
//  ## One process, one connection — deliberately
//
//  The helper releases a device when the connection that acquired it goes away
//  (NFR-REL-5): a GUI that crashes mid-run must not leave a claim behind. That means
//  `acquire` in one invocation and `release` in another would not work — the claim would
//  be gone before the second process started. So commands are given as a list and run in
//  sequence on a single connection.
//
//  That behaviour is itself testable here: run `acquire` alone, let the process exit, and
//  a following `check` should report the device no longer held.
//
//  Usage:
//      mount-guard-client <bsdName> <command> [<command> ...]
//
//  Commands: check | acquire | release | hold:<seconds>
//
//  Output is `KEY=value` on stdout, one fact per line, prefixed with the command — meant
//  for grep, not for reading aloud.
//

import Foundation

// MARK: - Arguments

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("""
        usage: mount-guard-client <bsdName> <command> [<command> ...]
               commands: check | acquire | release | hold:<seconds>

        """.utf8))
    exit(2)
}

let bsdName = arguments[1]
let commands = Array(arguments.dropFirst(2))

setvbuf(stdout, nil, _IOLBF, 0)
print("mount-guard-client: pid \(getpid()) on \(bsdName)")

// MARK: - Connection

let connection = NSXPCConnection(machServiceName: HelperIdentity.machServiceName,
                                 options: .privileged)
connection.remoteObjectInterface = NSXPCInterface(with: TesterControl.self)
connection.invalidationHandler = {
    FileHandle.standardError.write(Data("connection invalidated\n".utf8))
}
connection.resume()

/// Tracks whether anything failed, so the exit status is usable in a script.
var transportFailed = false

/// Run one call, blocking until it replies or the connection errors.
///
/// Blocking the main thread is safe: XPC delivers reply blocks on its own queue, not on
/// this one.
func call(_ label: String, _ body: (TesterControl, @escaping () -> Void) -> Void) {
    let semaphore = DispatchSemaphore(value: 0)
    var settled = false

    let proxy = connection.remoteObjectProxyWithErrorHandler { error in
        // A helper too old to implement these methods lands here, as does an unreachable
        // one. Both mean "access was not granted" — there is no permissive reading.
        print("[\(label)] TRANSPORT_ERROR=\(error.localizedDescription)")
        transportFailed = true
        if !settled { settled = true; semaphore.signal() }
    }

    guard let tester = proxy as? TesterControl else {
        print("[\(label)] TRANSPORT_ERROR=proxy did not conform to TesterControl")
        transportFailed = true
        return
    }

    body(tester) {
        if !settled { settled = true; semaphore.signal() }
    }

    if semaphore.wait(timeout: .now() + 30) != .success {
        print("[\(label)] TRANSPORT_ERROR=no reply within 30s")
        transportFailed = true
    }
}

// MARK: - Commands

for command in commands {
    switch command {
    case "check":
        call("check") { tester, done in
            tester.checkDeviceReadiness(bsdName: bsdName) { ready, count, summary, held, cause, message in
                print("[check] READY=\(ready ? 1 : 0)")
                print("[check] MOUNTED_COUNT=\(count)")
                print("[check] MOUNTED=\(summary)")
                print("[check] HELD=\(held ? 1 : 0)")
                print("[check] BLOCKING_CAUSE=\(cause)")
                print("[check] MESSAGE=\(message)")
                done()
            }
        }

    case "acquire":
        call("acquire") { tester, done in
            tester.acquireDevice(bsdName: bsdName) { acquired, causeCode, message in
                print("[acquire] ACQUIRED=\(acquired ? 1 : 0)")
                print("[acquire] CAUSE=\(causeCode)")
                print("[acquire] MESSAGE=\(message)")
                done()
            }
        }

    case "release":
        call("release") { tester, done in
            tester.releaseDevice { released, message in
                print("[release] RELEASED=\(released ? 1 : 0)")
                print("[release] MESSAGE=\(message)")
                done()
            }
        }

    case let held where held.hasPrefix("hold:"):
        let seconds = Double(held.dropFirst("hold:".count)) ?? 5
        print("[hold] HOLDING_FOR=\(Int(seconds))")
        Thread.sleep(forTimeInterval: seconds)
        print("[hold] DONE=1")

    default:
        FileHandle.standardError.write(Data("unknown command '\(command)'\n".utf8))
        exit(2)
    }
}

// Deliberately NOT invalidated before exit in the plain case: letting the process die
// with the connection still open is what exercises the helper's release-on-connection-loss
// path (NFR-REL-5).
exit(transportFailed ? 1 : 0)
