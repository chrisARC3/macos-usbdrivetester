//
//  main.swift
//  xpc-concurrency-probe — can the helper answer a second XPC message while a long
//  privileged call is in flight?
//
//  ## The question, and why it has to be measured before Step 9 is designed
//
//  Step 9 must show live metrics in the GUI, refreshing at least once per second
//  (FR-METR-2/4/5, NFR-PERF-5). There are two ways to move a snapshot across the trust
//  boundary:
//
//    * **poll** — the GUI calls a cheap query method on a 1 Hz timer while a run is in
//      flight. One additive method, no reverse interface, no new inbound surface on the
//      app, and the cadence is owned by the GUI's own timer so it cannot be
//      back-pressured by the daemon.
//    * **push** — a reverse `@objc` protocol, an exported object on the *app* side, the
//      helper retaining the connection and calling back into a client.
//
//  Poll is by far the smaller change. But it only works if the daemon will actually
//  *service* that second message while it is inside `runRetentionCycle`, which blocks for
//  the whole call. **Nothing in this project has ever established that.** The only
//  statement about concurrent delivery is a comment in the helper's `HelperActivity`,
//  and it is about two *connections* — not two messages on one.
//
//  BUILD-PLAN 9.4 assumes the push ("the helper sends a metrics snapshot to the GUI over
//  the XPC progress callback"). Committing to either mechanism on an assumption is how
//  Step 8 nearly lost forty minutes of hardware time: the "fingerprint from a separate
//  process" design was sound right up until `O_EXLOCK` was measured against a plain
//  `O_RDONLY` and returned `EBUSY`. That measurement was made *before* the gate design was
//  committed to, which is the only reason it cost nothing. This probe is the same move.
//
//  ## READ-ONLY. This probe writes nothing to the device.
//
//  The long call it uses is `digestRange` — SHA-256 over a bounded range, one read pass,
//  no writes — deliberately, and not `runRetentionCycle`. The XPC delivery question is
//  identical for both (a blocking privileged call holding the device-operation slot), and
//  answering it does not require putting a byte on anybody's drive. A 1 GiB digest is
//  about 2.2 s at the scratch device's measured rate, which is a wide enough window to fire twenty
//  pings into.
//
//  It DOES require the device unmounted and acquired, because `digestRange` requires a
//  held device. `scripts/xpc-concurrency-check.sh` unmounts, runs this, and restores the
//  mount state on every exit path.
//
//  ## What is measured, and what would make the answer meaningless
//
//  Every ping is timestamped twice — when it was **sent** and when its reply **arrived** —
//  both relative to the moment the digest was issued. That pair is the whole discriminator:
//
//    * sent at +0.5 s, replied at +0.52 s, digest replied at +2.2 s  → **concurrent**
//    * sent at +0.5 s, replied at +2.21 s, digest replied at +2.20 s → **serialized**
//
//  The raw table is printed, not just the verdict, because a verdict is a conclusion and
//  the timestamps are the evidence.
//
//  Two ways this probe could pass vacuously, both of which it refuses to call a result:
//
//    1. **The digest returned too fast.** If the window is under a second there was never
//       a meaningful in-flight period, and "no ping was delayed" says nothing. Reported
//       as `inconclusive`, never as `concurrent`.
//    2. **No ping was actually issued inside the window.** Same reasoning.
//
//  The first ping is deliberately held back by a settle delay, so that a ping cannot be
//  answered during a period when the digest message itself might still be in transit.
//
//  Usage:
//      xpc-concurrency-probe <bsdName> [digestBytes] [pingIntervalMs] [settleMs]
//
//  Output is `KEY=value` on stdout, one fact per line — meant for grep.
//

import Foundation

// MARK: - Arguments

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("""
        usage: xpc-concurrency-probe <bsdName> [digestBytes] [pingIntervalMs] [settleMs]

               digestBytes     length of the read-only call to run underneath the pings.
                               Defaults to TesterProtocol.maximumBytesPerCall (1 GiB), which
                               is also the most the helper will accept in one call.
               pingIntervalMs  how often to ping (default 100).
               settleMs        how long to wait after issuing the digest before the first
                               ping, so the digest is definitely in flight (default 250).

        """.utf8))
    exit(2)
}

let bsdName = arguments[1]
let digestBytes = arguments.count >= 3
    ? Swift.min(UInt64(arguments[2]) ?? TesterProtocol.maximumBytesPerCall,
                TesterProtocol.maximumBytesPerCall)
    : TesterProtocol.maximumBytesPerCall
let pingIntervalMilliseconds = arguments.count >= 4 ? (Int(arguments[3]) ?? 100) : 100
let settleMilliseconds = arguments.count >= 5 ? (Int(arguments[4]) ?? 250) : 250

/// Below this, the in-flight window was never wide enough for the answer to mean anything.
let minimumMeaningfulWindowMilliseconds: Double = 1_000

/// How many pings must be answered *inside* the window before "concurrent" is claimed. More
/// than one, so a single lucky reply landing on the boundary cannot carry the verdict.
let minimumConcurrentReplies = 3

// Unbuffered for the same reason mount-guard-client is: this is piped through `tee` by the
// gate script, and a pipe's 4 KB buffer swallowed an hour of progress lines in Step 8.
setvbuf(stdout, nil, _IONBF, 0)

/// The same clock the run itself uses — `CLOCK_MONOTONIC_RAW`, see `Core/RunClock`.
func nowNanoseconds() -> UInt64 { clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) }

func milliseconds(_ nanoseconds: UInt64) -> Double { Double(nanoseconds) / 1_000_000 }

func formatted(_ value: Double) -> String { String(format: "%.1f", value) }

// MARK: - Shared state, written from XPC reply queues

/// XPC delivers reply blocks on its own queue, not this thread — which is the entire point of
/// this probe — so every piece of state a reply block touches is behind a lock.
final class Flag {
    private let lock = NSLock()
    private var raised = false
    func raise() { lock.withLock { raised = true } }
    var isRaised: Bool { lock.withLock { raised } }
}

struct PingRecord {
    let index: Int
    let sentNanoseconds: UInt64
    var repliedNanoseconds: UInt64?
    var transportError: String?
}

/// One connection's ping timeline.
final class PingLog {

    let label: String
    private let lock = NSLock()
    private var records: [PingRecord] = []

    init(label: String) { self.label = label }

    func send(_ index: Int, at nanoseconds: UInt64) {
        lock.withLock {
            records.append(PingRecord(index: index, sentNanoseconds: nanoseconds))
        }
    }

    func reply(_ index: Int, at nanoseconds: UInt64) {
        lock.withLock {
            guard let position = records.firstIndex(where: { $0.index == index }) else { return }
            // First answer wins. A reply block should not fire twice, but recording the
            // earliest is the honest reading if one ever did.
            if records[position].repliedNanoseconds == nil {
                records[position].repliedNanoseconds = nanoseconds
            }
        }
    }

    func fail(_ index: Int, _ message: String) {
        lock.withLock {
            guard let position = records.firstIndex(where: { $0.index == index }) else { return }
            if records[position].transportError == nil {
                records[position].transportError = message
            }
        }
    }

    var snapshot: [PingRecord] { lock.withLock { records } }
}

// MARK: - Connections

var transportFailed = false

func makeConnection(_ label: String) -> NSXPCConnection {
    let connection = NSXPCConnection(machServiceName: HelperIdentity.machServiceName,
                                     options: .privileged)
    connection.remoteObjectInterface = NSXPCInterface(with: TesterControl.self)
    connection.invalidationHandler = {
        FileHandle.standardError.write(Data("connection \(label) invalidated\n".utf8))
    }
    connection.resume()
    return connection
}

/// A proxy for one message, with its own error handler.
///
/// A fresh proxy per message rather than one reused: it costs nothing and it means a failure
/// can be attributed to the exact ping that failed, instead of to "something on connection A".
func proxy(on connection: NSXPCConnection,
           onError: @escaping (Error) -> Void) -> TesterControl? {
    let remote = connection.remoteObjectProxyWithErrorHandler { error in onError(error) }
    return remote as? TesterControl
}

/// Issue one call and block this thread until it replies. Used only for the sequential
/// setup and teardown steps, never for the measurement itself.
func blockingCall(_ label: String,
                  on connection: NSXPCConnection,
                  timeout: TimeInterval = 30,
                  _ body: (TesterControl, @escaping () -> Void) -> Void) {
    let semaphore = DispatchSemaphore(value: 0)
    let settled = Flag()

    let signal: () -> Void = {
        guard !settled.isRaised else { return }
        settled.raise()
        semaphore.signal()
    }

    guard let tester = proxy(on: connection, onError: { error in
        print("[\(label)] TRANSPORT_ERROR=\(error.localizedDescription)")
        transportFailed = true
        signal()
    }) else {
        print("[\(label)] TRANSPORT_ERROR=proxy did not conform to TesterControl")
        transportFailed = true
        return
    }

    body(tester) { signal() }

    if semaphore.wait(timeout: .now() + timeout) != .success {
        print("[\(label)] TRANSPORT_ERROR=no reply within \(Int(timeout))s")
        transportFailed = true
    }
}

print("xpc-concurrency-probe: pid \(getpid()) on \(bsdName)")
print("[probe] DIGEST_BYTES_REQUESTED=\(digestBytes)")
print("[probe] PING_INTERVAL_MS=\(pingIntervalMilliseconds)")
print("[probe] SETTLE_MS=\(settleMilliseconds)")

let connectionA = makeConnection("A")
let connectionB = makeConnection("B")

// MARK: - Setup: version, acquire, geometry

var helperProtocolVersion = -1
blockingCall("version", on: connectionA) { tester, done in
    tester.protocolVersion { version in
        helperProtocolVersion = version
        done()
    }
}
print("[version] PROTOCOL=\(helperProtocolVersion)")
print("[version] EXPECTED=\(TesterProtocol.version)")

var acquired = false
blockingCall("acquire", on: connectionA) { tester, done in
    tester.acquireDevice(bsdName: bsdName) { ok, causeCode, message in
        acquired = ok
        print("[acquire] ACQUIRED=\(ok ? 1 : 0)")
        print("[acquire] CAUSE=\(causeCode)")
        print("[acquire] MESSAGE=\(message)")
        done()
    }
}

guard acquired else {
    print("[probe] ABORTED=the device was not acquired, so there is no long call to run")
    connectionA.invalidate()
    connectionB.invalidate()
    exit(1)
}

/// Everything below must release the device, including on an early exit — otherwise the
/// disk stays claimed and macOS will not remount it (NFR-REL-5).
func releaseAndExit(_ status: Int32) -> Never {
    blockingCall("release", on: connectionA) { tester, done in
        tester.releaseDevice { released, message in
            print("[release] RELEASED=\(released ? 1 : 0)")
            print("[release] MESSAGE=\(message)")
            done()
        }
    }
    connectionA.invalidate()
    connectionB.invalidate()
    exit(status)
}

var blockSize: UInt32 = 0
var deviceBlockCount: UInt64 = 0
blockingCall("profile", on: connectionA) { tester, done in
    tester.deviceProfile { available, ioctlBlockSize, ioctlBlockCount, _, _, _, _, _, message in
        if available {
            blockSize = ioctlBlockSize
            deviceBlockCount = ioctlBlockCount
        } else {
            print("[profile] UNAVAILABLE=\(message)")
        }
        done()
    }
}

guard blockSize > 0, deviceBlockCount > 0 else {
    print("[probe] ABORTED=no geometry from the held device")
    releaseAndExit(1)
}

// Geometry from the helper's own ioctls (BUILD-PLAN 7.3) — never from diskutil, and never
// from anything this probe assumed.
let digestBlocks = Swift.min(digestBytes / UInt64(blockSize), deviceBlockCount)
guard digestBlocks > 0 else {
    print("[probe] ABORTED=the requested digest covers no blocks")
    releaseAndExit(1)
}
print("[probe] BLOCK_SIZE=\(blockSize)")
print("[probe] DIGEST_BLOCKS=\(digestBlocks)")
print("[probe] DIGEST_BYTES=\(digestBlocks * UInt64(blockSize))")

// MARK: - The measurement

let logA = PingLog(label: "A")
let logB = PingLog(label: "B")
let digestFinished = Flag()
let digestSemaphore = DispatchSemaphore(value: 0)

var digestOK = false
var digestReportedBytes: UInt64 = 0
var digestHex = ""
var digestMessage = ""
var digestReplyNanoseconds: UInt64 = 0

print("")
print("  issuing a \(digestBlocks * UInt64(blockSize))-byte read-only digest, then pinging "
    + "underneath it …")
print("")

let startNanoseconds = nowNanoseconds()

if let tester = proxy(on: connectionA, onError: { error in
    print("[digest] TRANSPORT_ERROR=\(error.localizedDescription)")
    transportFailed = true
    digestReplyNanoseconds = nowNanoseconds()
    digestFinished.raise()
    digestSemaphore.signal()
}) {
    tester.digestRange(startBlock: 0, blockCount: digestBlocks) { ok, bytes, hex, message in
        digestReplyNanoseconds = nowNanoseconds()
        digestOK = ok
        digestReportedBytes = bytes
        digestHex = hex
        digestMessage = message
        digestFinished.raise()
        digestSemaphore.signal()
    }
} else {
    print("[digest] TRANSPORT_ERROR=proxy did not conform to TesterControl")
    releaseAndExit(1)
}

// Hold the first ping back, so no ping can be answered during a period when the digest
// message itself might still be in transit.
Thread.sleep(forTimeInterval: Double(settleMilliseconds) / 1_000)

let halfInterval = Double(pingIntervalMilliseconds) / 2_000
/// Ten minutes. Far past a 1 GiB digest (~2.2 s measured), and only reached if the daemon
/// has stopped answering entirely — which is itself the finding.
let deadlineNanoseconds = startNanoseconds &+ 600 * 1_000_000_000

var pingIndex = 0
while !digestFinished.isRaised && nowNanoseconds() < deadlineNanoseconds {

    let indexA = pingIndex
    logA.send(indexA, at: nowNanoseconds())
    if let tester = proxy(on: connectionA, onError: { error in
        logA.fail(indexA, error.localizedDescription)
    }) {
        tester.ping { _ in logA.reply(indexA, at: nowNanoseconds()) }
    } else {
        logA.fail(indexA, "proxy did not conform to TesterControl")
    }

    Thread.sleep(forTimeInterval: halfInterval)
    if digestFinished.isRaised { break }

    // Offset by half an interval so the two connections' pings are never in flight at the
    // same instant — otherwise a delay on one could be read as evidence about the other.
    let indexB = pingIndex
    logB.send(indexB, at: nowNanoseconds())
    if let tester = proxy(on: connectionB, onError: { error in
        logB.fail(indexB, error.localizedDescription)
    }) {
        tester.ping { _ in logB.reply(indexB, at: nowNanoseconds()) }
    } else {
        logB.fail(indexB, "proxy did not conform to TesterControl")
    }

    Thread.sleep(forTimeInterval: halfInterval)
    pingIndex += 1
}

if digestSemaphore.wait(timeout: .now() + 600) != .success {
    print("[digest] TRANSPORT_ERROR=the digest never replied")
    transportFailed = true
    digestReplyNanoseconds = nowNanoseconds()
}

// Give stragglers a chance to land. In the serialized case every ping issued during the
// window replies immediately *after* the digest does, and those replies are the evidence —
// dropping them would turn the clearest possible result into "no reply".
Thread.sleep(forTimeInterval: 2)

// MARK: - What the timestamps show

let windowNanoseconds = digestReplyNanoseconds > startNanoseconds
    ? digestReplyNanoseconds - startNanoseconds
    : 0
let windowMilliseconds = milliseconds(windowNanoseconds)

print("[digest] OK=\(digestOK ? 1 : 0)")
print("[digest] BYTES=\(digestReportedBytes)")
print("[digest] SHA256=\(digestHex)")
print("[digest] MESSAGE=\(digestMessage)")
print("[digest] WINDOW_MS=\(formatted(windowMilliseconds))")

/// One connection's answer, and the evidence for it.
struct Analysis {
    let label: String
    let sent: Int
    let answeredDuringWindow: Int
    let answeredAfterWindow: Int
    let unanswered: Int
    let failed: Int
    let maximumLatencyDuringWindowMilliseconds: Double
    let verdict: String
}

func analyse(_ log: PingLog) -> Analysis {
    let records = log.snapshot
    var duringWindow = 0
    var afterWindow = 0
    var unanswered = 0
    var failed = 0
    var maximumLatency: Double = 0

    /// Left-pad to a fixed width so the columns line up and a delayed reply is visible as a
    /// step in the numbers rather than something to be read carefully.
    func column(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }

    print("")
    print("  connection \(log.label) — every ping, relative to the digest being issued")
    print("    " + column("ping", 7) + column("sent", 11) + column("replied", 11)
        + column("latency", 11) + "when")

    for record in records {
        let sent = milliseconds(record.sentNanoseconds &- startNanoseconds)
        let prefix = "    " + column("\(record.index)", 7) + column(formatted(sent), 11)

        if let error = record.transportError {
            failed += 1
            print(prefix + "TRANSPORT_ERROR \(error)")
            continue
        }

        guard let repliedNanoseconds = record.repliedNanoseconds else {
            unanswered += 1
            print(prefix + "no reply")
            continue
        }

        let replied = milliseconds(repliedNanoseconds &- startNanoseconds)
        let latency = replied - sent
        let inWindow = repliedNanoseconds < digestReplyNanoseconds

        if inWindow {
            duringWindow += 1
            if latency > maximumLatency { maximumLatency = latency }
        } else {
            afterWindow += 1
        }

        print(prefix + column(formatted(replied), 11) + column(formatted(latency) + " ms", 11)
            + (inWindow ? "[during]" : "[after]"))
    }

    // The verdict refuses to be positive on evidence that could not have been negative.
    let verdict: String
    if windowMilliseconds < minimumMeaningfulWindowMilliseconds {
        verdict = "inconclusive"          // the call was never in flight long enough
    } else if records.isEmpty {
        verdict = "inconclusive"          // nothing was asked during the window
    } else if duringWindow >= minimumConcurrentReplies {
        verdict = "concurrent"
    } else if duringWindow == 0 && afterWindow > 0 {
        verdict = "serialized"
    } else {
        verdict = "inconclusive"
    }

    return Analysis(label: log.label,
                    sent: records.count,
                    answeredDuringWindow: duringWindow,
                    answeredAfterWindow: afterWindow,
                    unanswered: unanswered,
                    failed: failed,
                    maximumLatencyDuringWindowMilliseconds: maximumLatency,
                    verdict: verdict)
}

let analysisA = analyse(logA)
let analysisB = analyse(logB)

for analysis in [analysisA, analysisB] {
    let key = analysis.label == "A" ? "SAME_CONNECTION" : "SECOND_CONNECTION"
    print("")
    print("[\(key)] PINGS_SENT=\(analysis.sent)")
    print("[\(key)] ANSWERED_DURING=\(analysis.answeredDuringWindow)")
    print("[\(key)] ANSWERED_AFTER=\(analysis.answeredAfterWindow)")
    print("[\(key)] UNANSWERED=\(analysis.unanswered)")
    print("[\(key)] FAILED=\(analysis.failed)")
    print("[\(key)] MAX_LATENCY_DURING_MS="
        + formatted(analysis.maximumLatencyDuringWindowMilliseconds))
    print("[\(key)] VERDICT=\(analysis.verdict)")
}

print("")
if windowMilliseconds < minimumMeaningfulWindowMilliseconds {
    print("[probe] MEANINGFUL_WINDOW=0")
    print("[probe] NOTE=the digest replied in \(formatted(windowMilliseconds)) ms, under the "
        + "\(Int(minimumMeaningfulWindowMilliseconds)) ms this probe requires. There was no "
        + "in-flight period to test, so neither verdict is a result. Re-run with a larger "
        + "digestBytes.")
} else {
    print("[probe] MEANINGFUL_WINDOW=1")
}

let definite = ["concurrent", "serialized"]
let bothDefinite = definite.contains(analysisA.verdict) && definite.contains(analysisB.verdict)

print("[probe] DIGEST_OK=\(digestOK ? 1 : 0)")
print("[probe] TRANSPORT_FAILED=\(transportFailed ? 1 : 0)")

// Exit status says whether the probe *produced a result*, not which result. "Serialized" is a
// perfectly good finding — it just means Step 9 builds the push instead of the poll.
releaseAndExit(bothDefinite && digestOK && !transportFailed ? 0 : 1)
