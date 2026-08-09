//
//  main.swift
//  metrics-probe — drives a real bounded cycle and polls its live metrics from a second
//  connection, the way the GUI does.
//
//  ## What this is evidence for
//
//  Step 9's gate asks that live metrics refresh **at least once per second during a run**
//  (NFR-PERF-5) and that the run be **device-bound, not host-bound** (NFR-PERF-3). Neither can be
//  established in simulation: the first is a property of the XPC transport under a real blocking
//  privileged call, and the second is meaningless against an in-memory device that runs at
//  ~71 GB/s, where the host genuinely *is* the limit.
//
//  So this does what the app does, from the CLI where it can be asserted mechanically:
//
//    * connection A issues `runRetentionCycle` and blocks for the whole run;
//    * connection B polls `runProgress` twice a second and timestamps every reply.
//
//  Two connections is not a stylistic choice. Measured 2026-08-04
//  (`scripts/xpc-concurrency-check.sh`): a second message on a connection with a call in flight
//  is **not delivered until that call returns**, while a second connection is answered
//  concurrently in 0.2–0.3 ms.
//
//  ## ⚠️  THIS WRITES TO THE DRIVE
//
//  It runs the read → write-back → verify cycle over the **first 1 GiB** of the device, starting
//  at block 0 — which is what a real run does (FR-TEST-4) and is 1 MiB-aligned by construction
//  (FR-TEST-10). The cycle writes back exactly the bytes it read; that is proven in simulation and
//  was verified byte-for-byte on the scratch device in Step 8. This probe does **not** re-prove it —
//  `scripts/retention-cycle-check.sh` is what fingerprints the device either side of a run.
//
//  Output is `KEY=value` on stdout, one fact per line — meant for grep.
//
//  Usage:
//      metrics-probe <bsdName> [pollIntervalMs]
//

import Foundation

// MARK: - Arguments

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("""
        usage: metrics-probe <bsdName> [pollIntervalMs]

               WRITES to the first 1 GiB of the named device.
               pollIntervalMs defaults to 500 — twice NFR-PERF-5's required cadence, so a
               missed refresh is visible rather than marginal.

        """.utf8))
    exit(2)
}

let bsdName = arguments[1]
let pollIntervalMilliseconds = arguments.count >= 3 ? (Int(arguments[2]) ?? 500) : 500

setvbuf(stdout, nil, _IONBF, 0)

func nowNanoseconds() -> UInt64 { clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) }
func milliseconds(_ nanoseconds: UInt64) -> Double { Double(nanoseconds) / 1_000_000 }
func formatted(_ value: Double, _ places: Int = 1) -> String {
    String(format: "%.\(places)f", value)
}

// MARK: - Shared state, written from XPC reply queues

final class Flag {
    private let lock = NSLock()
    private var raised = false
    func raise() { lock.withLock { raised = true } }
    var isRaised: Bool { lock.withLock { raised } }
}

/// One `runProgress` reply, with when it arrived.
struct Sample {
    let atNanoseconds: UInt64
    let available: Bool
    let fractionComplete: Double
    let currentBlock: UInt64
    let readBytesPerSecond: Double
    let writeBytesPerSecond: Double
    let estimatedRemainingSeconds: Double
    let latencySamples: UInt64
    let latencyMinimum: UInt64
    let latencyMaximum: UInt64
    let latencyP99Upper: UInt64
    let chunksFailed: UInt64
}

final class SampleLog {
    private let lock = NSLock()
    private var items: [Sample] = []
    func append(_ sample: Sample) { lock.withLock { items.append(sample) } }
    var all: [Sample] { lock.withLock { items } }
}

var transportFailed = false

// MARK: - Connections

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

func proxy(on connection: NSXPCConnection,
           onError: @escaping (Error) -> Void) -> TesterControl? {
    connection.remoteObjectProxyWithErrorHandler { onError($0) } as? TesterControl
}

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

print("metrics-probe: pid \(getpid()) on \(bsdName)")
print("[probe] POLL_INTERVAL_MS=\(pollIntervalMilliseconds)")

let runConnection = makeConnection("run")
let progressConnection = makeConnection("progress")

// MARK: - Setup

var helperProtocolVersion = -1
blockingCall("version", on: runConnection) { tester, done in
    tester.protocolVersion { version in helperProtocolVersion = version; done() }
}
print("[version] PROTOCOL=\(helperProtocolVersion)")
print("[version] EXPECTED=\(TesterProtocol.version)")

var acquired = false
blockingCall("acquire", on: runConnection) { tester, done in
    tester.acquireDevice(bsdName: bsdName) { ok, causeCode, message in
        acquired = ok
        print("[acquire] ACQUIRED=\(ok ? 1 : 0)")
        print("[acquire] CAUSE=\(causeCode)")
        print("[acquire] MESSAGE=\(message)")
        done()
    }
}

guard acquired else {
    print("[probe] ABORTED=the device was not acquired")
    runConnection.invalidate()
    progressConnection.invalidate()
    exit(1)
}

func releaseAndExit(_ status: Int32) -> Never {
    blockingCall("release", on: runConnection) { tester, done in
        tester.releaseDevice { released, message in
            print("[release] RELEASED=\(released ? 1 : 0)")
            print("[release] MESSAGE=\(message)")
            done()
        }
    }
    runConnection.invalidate()
    progressConnection.invalidate()
    exit(status)
}

var blockSize: UInt32 = 0
var linkSpeedCode = -1
blockingCall("profile", on: runConnection) { tester, done in
    tester.deviceProfile { available, ioctlBlockSize, _, _, _, _, speedCode, _, message in
        if available { blockSize = ioctlBlockSize; linkSpeedCode = speedCode }
        else { print("[profile] UNAVAILABLE=\(message)") }
        done()
    }
}

guard blockSize > 0 else {
    print("[probe] ABORTED=no geometry from the held device")
    releaseAndExit(1)
}

// 1 GiB from block 0, once per permitted I/O size. Block 0 is where a real run begins
// (FR-TEST-4) and is 1 MiB-aligned by construction (FR-TEST-10); the length is the per-call cap,
// itself a whole number of MiB.
//
// ## Why every size, and not just the default
//
// NFR-PERF-3's host-overhead figure was measured at 4 MiB only (2026-08-04), and that leaves an
// open question the Step 16 release note cannot answer: does the host cost scale with **bytes
// moved** or with **chunk count**? The two imply opposite advice about I/O size, so guessing is
// worse than not saying. Sweeping all four of FR-CTRL-8's sizes over the same gibibyte gives an
// 8x lever on chunk count at constant bytes, which settles it — and incidentally exercises the
// chunk plan at every size the UI can select, on real media.
let runBlocks = TesterProtocol.maximumBytesPerCall / UInt64(blockSize)
let sweepSizes = TesterProtocol.permittedIOSizes
let detailedSize = TesterProtocol.defaultIOSizeBytes

print("[probe] BLOCK_SIZE=\(blockSize)")
print("[probe] LINK_SPEED_CODE=\(linkSpeedCode)")
print("[probe] START_BLOCK=0")
print("[probe] RUN_BLOCKS=\(runBlocks)")
print("[probe] SWEEP_SIZES=\(sweepSizes.map(String.init).joined(separator: ","))")
print("[probe] DETAILED_SIZE=\(detailedSize)")

// MARK: - One cycle, polled from the other connection

/// What one size's run produced.
struct CycleRun {
    let ioSizeBytes: Int
    let completed: Bool
    let chunks: UInt64
    let failedRanges: Int
    let failureSummary: String
    let cacheBypass: Int
    let bufferBytes: Int
    let hostOverheadFraction: Double
    let helperCoreFraction: Double
    let message: String
    let wallNanoseconds: UInt64
    let samples: [Sample]
    let replyNanoseconds: UInt64
    let startNanoseconds: UInt64

    // Protocol v9 (Step 10). The final figures now arrive in the cycle's own reply rather than
    // having to be polled for afterwards — which is the whole point: `MetricsChannel`'s slot is
    // replaced when a run *starts*, so a refused run leaves the previous run's numbers behind,
    // and this probe's Step 9 predecessor read exactly that kind of stale value once already.
    let failureModeUsed: Int
    let failedBlockCount: UInt64
    let finalReadBytesPerSecond: Double
    let finalWriteBytesPerSecond: Double
    let finalLatencySamples: UInt64
    let finalLatencyMinimumNanoseconds: UInt64
    let finalLatencyMaximumNanoseconds: UInt64
    let finalLatencyP99UpperNanoseconds: UInt64
}

func runCycle(ioSizeBytes: Int) -> CycleRun {
    let log = SampleLog()
    let finished = Flag()
    let semaphore = DispatchSemaphore(value: 0)

    var completed = false
    var chunks: UInt64 = 0
    var failedRanges = 0
    var failureSummary = ""
    var cacheBypass = 0
    var bufferBytes = 0
    var overhead = -1.0
    var core = -1.0
    var message = ""
    var replyNanoseconds: UInt64 = 0
    var failureModeUsed = FailureModeCode.unrecognised.rawValue
    var failedBlockCount: UInt64 = 0
    var finalReadRate = -1.0
    var finalWriteRate = -1.0
    var finalLatencySamples: UInt64 = 0
    var finalLatencyMinimum: UInt64 = 0
    var finalLatencyMaximum: UInt64 = 0
    var finalLatencyP99Upper: UInt64 = 0

    let startNanoseconds = nowNanoseconds()

    if let tester = proxy(on: runConnection, onError: { error in
        print("[cycle] TRANSPORT_ERROR=\(error.localizedDescription)")
        transportFailed = true
        replyNanoseconds = nowNanoseconds()
        finished.raise()
        semaphore.signal()
    }) {
        // FR-FAIL-4's default (protocol v9). This probe measures a *healthy* device, so the
        // mode never acts on anything — but the reply says which mode ran, and that is
        // asserted, because it is the only evidence available that the mode reached the run
        // path when there is no failure for it to stop on.
        tester.runRetentionCycle(startBlock: 0,
                                 blockCount: runBlocks,
                                 ioSizeBytes: ioSizeBytes,
                                 failureModeCode: FailureModeCode.standard.rawValue) {
            done, chunkCount, failed, summary, bypass, _, buffers, hostOverhead,
            coreFraction, modeUsed, _, failedBlocks, readRate, writeRate,
            latencySampleCount, latencyMin, latencyMax, latencyP99, text in

            replyNanoseconds = nowNanoseconds()
            completed = done
            chunks = chunkCount
            failedRanges = failed
            failureSummary = summary
            cacheBypass = bypass
            bufferBytes = buffers
            overhead = hostOverhead
            core = coreFraction
            failureModeUsed = modeUsed
            failedBlockCount = failedBlocks
            finalReadRate = readRate
            finalWriteRate = writeRate
            finalLatencySamples = latencySampleCount
            finalLatencyMinimum = latencyMin
            finalLatencyMaximum = latencyMax
            finalLatencyP99Upper = latencyP99
            message = text
            finished.raise()
            semaphore.signal()
        }
    } else {
        print("[cycle] TRANSPORT_ERROR=proxy did not conform to TesterControl")
        transportFailed = true
        finished.raise()
        semaphore.signal()
    }

    // Poll on the OTHER connection while the run blocks this one's.
    //
    // Settle first, for the same reason the D1 pre-flight did: `MetricsChannel.begin()` runs
    // inside `runCycle` *after* validation — correctly, so a refused run does not wipe the
    // previous run's figures — which leaves a few milliseconds where a poll still sees the
    // **previous** size's completed snapshot. Without this, every table's first row read 100%
    // and then dropped to 3%, which looks like progress going backwards and is really just a
    // question asked before there was anything new to answer it.
    Thread.sleep(forTimeInterval: 0.25)

    let pollInterval = Double(pollIntervalMilliseconds) / 1_000
    let deadline = startNanoseconds &+ 600 * 1_000_000_000

    while !finished.isRaised && nowNanoseconds() < deadline {
        if let tester = proxy(on: progressConnection, onError: { error in
            print("[progress] TRANSPORT_ERROR=\(error.localizedDescription)")
            transportFailed = true
        }) {
            tester.runProgress { available, fraction, currentBlock, readRate, writeRate,
                                 remaining, latencySamples, latencyMin, latencyMax,
                                 latencyP99, chunksFailed in
                log.append(Sample(atNanoseconds: nowNanoseconds(),
                                  available: available,
                                  fractionComplete: fraction,
                                  currentBlock: currentBlock,
                                  readBytesPerSecond: readRate,
                                  writeBytesPerSecond: writeRate,
                                  estimatedRemainingSeconds: remaining,
                                  latencySamples: latencySamples,
                                  latencyMinimum: latencyMin,
                                  latencyMaximum: latencyMax,
                                  latencyP99Upper: latencyP99,
                                  chunksFailed: chunksFailed))
            }
        }
        Thread.sleep(forTimeInterval: pollInterval)
    }

    if semaphore.wait(timeout: .now() + 600) != .success {
        print("[cycle] TRANSPORT_ERROR=the cycle never replied")
        transportFailed = true
        replyNanoseconds = nowNanoseconds()
    }

    Thread.sleep(forTimeInterval: 1)          // let a straggler reply land

    // ONE MORE POLL, AFTER THE RUN HAS REPLIED.
    //
    // The loop above exits the instant the cycle replies, so its newest snapshot is whatever the
    // last poll caught — up to one poll interval *before* the end. On 2026-08-04 that made the
    // gate report "progress ended at 93.75%" and "240 latency samples for 256 chunks" at every
    // I/O size, and the arithmetic gave it away: every figure was exactly samples/chunks. The run
    // had completed; nobody had asked the helper what the completed state was.
    //
    // `MetricsChannel` keeps the finished run's accumulator until the next run replaces it, so
    // this final ask is what the run actually ended at.
    blockingCall("final-progress", on: progressConnection, timeout: 30) { tester, done in
        tester.runProgress { available, fraction, currentBlock, readRate, writeRate,
                             remaining, latencySamples, latencyMin, latencyMax,
                             latencyP99, chunksFailed in
            log.append(Sample(atNanoseconds: nowNanoseconds(),
                              available: available,
                              fractionComplete: fraction,
                              currentBlock: currentBlock,
                              readBytesPerSecond: readRate,
                              writeBytesPerSecond: writeRate,
                              estimatedRemainingSeconds: remaining,
                              latencySamples: latencySamples,
                              latencyMinimum: latencyMin,
                              latencyMaximum: latencyMax,
                              latencyP99Upper: latencyP99,
                              chunksFailed: chunksFailed))
            done()
        }
    }

    return CycleRun(ioSizeBytes: ioSizeBytes,
                    completed: completed,
                    chunks: chunks,
                    failedRanges: failedRanges,
                    failureSummary: failureSummary,
                    cacheBypass: cacheBypass,
                    bufferBytes: bufferBytes,
                    hostOverheadFraction: overhead,
                    helperCoreFraction: core,
                    message: message,
                    wallNanoseconds: replyNanoseconds > startNanoseconds
                        ? replyNanoseconds - startNanoseconds : 0,
                    samples: log.all,
                    replyNanoseconds: replyNanoseconds,
                    startNanoseconds: startNanoseconds,
                    failureModeUsed: failureModeUsed,
                    failedBlockCount: failedBlockCount,
                    finalReadBytesPerSecond: finalReadRate,
                    finalWriteBytesPerSecond: finalWriteRate,
                    finalLatencySamples: finalLatencySamples,
                    finalLatencyMinimumNanoseconds: finalLatencyMinimum,
                    finalLatencyMaximumNanoseconds: finalLatencyMaximum,
                    finalLatencyP99UpperNanoseconds: finalLatencyP99Upper)
}

func column(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
}

// MARK: - The sweep

var runs: [CycleRun] = []

for size in sweepSizes {
    print("")
    print("  ── \(size / (1 << 20)) MiB I/O ─────────────────────────────────────────────")
    print("  running \(TesterParameters.gibibyteDescription) from block 0, polling every "
        + "\(pollIntervalMilliseconds) ms …")
    let run = runCycle(ioSizeBytes: size)
    runs.append(run)

    print("[size:\(size)] COMPLETED=\(run.completed ? 1 : 0)")
    print("[size:\(size)] CHUNKS=\(run.chunks)")
    print("[size:\(size)] EXPECTED_CHUNKS=\(TesterProtocol.maximumBytesPerCall / UInt64(size))")
    print("[size:\(size)] FAILED_RANGES=\(run.failedRanges)")
    print("[size:\(size)] FAILURE_SUMMARY=\(run.failureSummary)")
    print("[size:\(size)] CACHE_BYPASS=\(run.cacheBypass)")
    print("[size:\(size)] BUFFER_BYTES=\(run.bufferBytes)")
    print("[size:\(size)] WALL_MS=\(formatted(milliseconds(run.wallNanoseconds)))")
    print("[size:\(size)] HOST_OVERHEAD_FRACTION=\(run.hostOverheadFraction)")
    print("[size:\(size)] HELPER_CORE_FRACTION=\(run.helperCoreFraction)")

    // Cadence and progress, per size — NFR-PERF-5 is not a property of one I/O size.
    let inRun = run.samples.filter { $0.atNanoseconds <= run.replyNanoseconds }
    var widestGap = 0.0
    for index in 1 ..< Swift.max(inRun.count, 1) {
        let gap = milliseconds(inRun[index].atNanoseconds &- inRun[index - 1].atNanoseconds)
        if gap > widestGap { widestGap = gap }
    }
    let midRun = run.samples.filter {
        $0.available && $0.atNanoseconds < run.replyNanoseconds
            && $0.fractionComplete > 0 && $0.fractionComplete < 1
    }
    let fractions = midRun.map(\.fractionComplete)
    let monotonic = zip(fractions, fractions.dropFirst()).allSatisfy { $0 <= $1 }
    let final = run.samples.last

    print("[size:\(size)] SAMPLES_TOTAL=\(run.samples.count)")
    print("[size:\(size)] SAMPLES_MID_RUN=\(midRun.count)")
    print("[size:\(size)] WIDEST_GAP_MS=\(formatted(widestGap))")
    print("[size:\(size)] MONOTONIC=\(monotonic ? 1 : 0)")
    print("[size:\(size)] FINAL_FRACTION=\(formatted((final?.fractionComplete ?? 0) * 100, 2))")
    print("[size:\(size)] FINAL_CURRENT_BLOCK=\(final?.currentBlock ?? 0)")
    print("[size:\(size)] FINAL_LATENCY_SAMPLES=\(final?.latencySamples ?? 0)")
    print("[size:\(size)] FINAL_LATENCY_MIN_NS=\(final?.latencyMinimum ?? 0)")
    print("[size:\(size)] FINAL_LATENCY_MAX_NS=\(final?.latencyMaximum ?? 0)")
    print("[size:\(size)] FINAL_LATENCY_P99_NS=\(final?.latencyP99Upper ?? 0)")
    print("[size:\(size)] FINAL_READ_BYTES_PER_SECOND=\(final?.readBytesPerSecond ?? -1)")
    print("[size:\(size)] FINAL_WRITE_BYTES_PER_SECOND=\(final?.writeBytesPerSecond ?? -1)")
    print("[size:\(size)] FINAL_CHUNKS_FAILED=\(final?.chunksFailed ?? 0)")

    // Protocol v9 (Step 10). The same six figures, by a completely different route: these came
    // back in `runRetentionCycle`'s reply, the `FINAL_*` ones above from a `runProgress` poll
    // issued after it. **They must agree.**
    //
    // That agreement is the only check available on the part of the v9 reply no unit test can
    // reach. The reply is nineteen positional values assembled in the helper's `main.swift`, six
    // of them adjacent same-typed numbers — two `Double` rates and four `UInt64` latency figures
    // — and a transposition there would compile, run, and put read throughput under "write" in
    // an exported report. Two independent paths to the same numbers is what makes it visible.
    print("[size:\(size)] REPLY_FAILURE_MODE_USED=\(run.failureModeUsed)")
    print("[size:\(size)] REPLY_FAILED_BLOCKS=\(run.failedBlockCount)")
    print("[size:\(size)] REPLY_READ_BYTES_PER_SECOND=\(run.finalReadBytesPerSecond)")
    print("[size:\(size)] REPLY_WRITE_BYTES_PER_SECOND=\(run.finalWriteBytesPerSecond)")
    print("[size:\(size)] REPLY_LATENCY_SAMPLES=\(run.finalLatencySamples)")
    print("[size:\(size)] REPLY_LATENCY_MIN_NS=\(run.finalLatencyMinimumNanoseconds)")
    print("[size:\(size)] REPLY_LATENCY_MAX_NS=\(run.finalLatencyMaximumNanoseconds)")
    print("[size:\(size)] REPLY_LATENCY_P99_NS=\(run.finalLatencyP99UpperNanoseconds)")

    // The full snapshot table only for the default size, or the output becomes unreadable.
    guard size == detailedSize else { continue }
    print("")
    print("  live snapshots at the default I/O size, relative to the run starting")
    print("    " + column("at ms", 10) + column("%", 8) + column("read MB/s", 12)
        + column("write MB/s", 12) + column("ETA s", 9) + column("reads", 9) + "p99 ms")
    for sample in run.samples where sample.available {
        let at = milliseconds(sample.atNanoseconds &- run.startNanoseconds)
        print("    " + column(formatted(at, 0), 10)
            + column(formatted(sample.fractionComplete * 100, 1), 8)
            + column(sample.readBytesPerSecond >= 0
                     ? formatted(sample.readBytesPerSecond / 1_000_000, 0) : "—", 12)
            + column(sample.writeBytesPerSecond >= 0
                     ? formatted(sample.writeBytesPerSecond / 1_000_000, 0) : "—", 12)
            + column(sample.estimatedRemainingSeconds >= 0
                     ? formatted(sample.estimatedRemainingSeconds, 1) : "—", 9)
            + column("\(sample.latencySamples)", 9)
            + (sample.latencySamples > 0
               ? formatted(Double(sample.latencyP99Upper) / 1_000_000, 3) : "—"))
    }
}

// MARK: - Does host cost follow bytes, or chunks?

print("")
print("  ── host cost vs I/O size ───────────────────────────────────────────────────────")
print("    " + column("I/O size", 11) + column("chunks", 9) + column("overhead %", 13)
    + column("us/chunk", 12) + column("us/MiB", 10) + "read MB/s")

for run in runs where run.hostOverheadFraction >= 0 && run.chunks > 0 {
    let deviceNanoseconds = Double(run.wallNanoseconds)          // dominated by device I/O
    let hostNanoseconds = deviceNanoseconds * run.hostOverheadFraction
        / (1 + run.hostOverheadFraction)
    let perChunk = hostNanoseconds / Double(run.chunks) / 1_000
    let mibMoved = Double(TesterProtocol.maximumBytesPerCall) / Double(1 << 20)
    let perMib = hostNanoseconds / mibMoved / 1_000
    let readRate = run.samples.last?.readBytesPerSecond ?? -1

    print("    " + column("\(run.ioSizeBytes / (1 << 20)) MiB", 11)
        + column("\(run.chunks)", 9)
        + column(formatted(run.hostOverheadFraction * 100, 3), 13)
        + column(formatted(perChunk, 1), 12)
        + column(formatted(perMib, 1), 10)
        + (readRate >= 0 ? formatted(readRate / 1e6, 0) : "—"))

    print("[scaling:\(run.ioSizeBytes)] US_PER_CHUNK=\(formatted(perChunk, 3))")
    print("[scaling:\(run.ioSizeBytes)] US_PER_MIB=\(formatted(perMib, 3))")
}

print("")
print("  If us/MiB is roughly constant while us/chunk tracks the I/O size, host cost follows")
print("  BYTES MOVED and a larger I/O size will not reduce it. If us/chunk is roughly constant")
print("  instead, it follows CHUNK COUNT and a larger size reduces it proportionally.")

print("[probe] TRANSPORT_FAILED=\(transportFailed ? 1 : 0)")

// MARK: - FR-TEST-10, shown refusing

// A run that satisfies the placement rule proves the rule did not get in the way. It says
// nothing about whether the rule is *enforced* — and an unenforced guard is indistinguishable
// from an enforced one until the day something misaligned arrives. So both halves are asked for
// explicitly and both must be refused.
//
// Neither of these performs any I/O: `RunCoordinator.runCycle` validates placement before it
// vends a block device, so a refusal costs nothing and touches nothing.

func expectRefusal(_ label: String,
                   startBlock: UInt64,
                   blockCount: UInt64,
                   failureModeCode: Int = FailureModeCode.standard.rawValue) {
    blockingCall(label, on: runConnection, timeout: 60) { tester, done in
        tester.runRetentionCycle(startBlock: startBlock,
                                 blockCount: blockCount,
                                 ioSizeBytes: detailedSize,
                                 failureModeCode: failureModeCode) {
            completed, chunks, _, _, _, _, _, _, _, modeUsed, ranges, failedBlocks,
            readRate, writeRate, latencySamples, _, _, _, message in

            // `completed == false` and no chunks processed is what a refusal looks like; a
            // refusal that had already written something would show up as chunks > 0.
            print("[\(label)] REFUSED=\(completed || chunks > 0 ? 0 : 1)")
            print("[\(label)] CHUNKS=\(chunks)")

            // Protocol v9 (Step 10). **A refused run must carry no figures at all**, and this is
            // the hardware evidence for why the figures travel in this reply rather than being
            // polled from `runProgress` afterwards: at this moment the helper's `MetricsChannel`
            // slot still holds the *previous* run's numbers, because `begin()` runs after
            // validation. A caller that went looking would find them, correctly formatted, and
            // put another run's measurements into an exported report.
            print("[\(label)] MODE_USED=\(modeUsed)")
            print("[\(label)] RANGES_ENCODED=\(ranges)")
            print("[\(label)] FAILED_BLOCKS=\(failedBlocks)")
            print("[\(label)] READ_BYTES_PER_SECOND=\(readRate)")
            print("[\(label)] WRITE_BYTES_PER_SECOND=\(writeRate)")
            print("[\(label)] LATENCY_SAMPLES=\(latencySamples)")
            print("[\(label)] MESSAGE=\(message)")
            done()
        }
    }
}

print("")
print("  asking for three runs the helper must refuse …")
print("")

// Half one: a start one block past zero — 512 bytes in, not a 1 MiB boundary (FR-TEST-10).
expectRefusal("misaligned", startBlock: 1, blockCount: runBlocks)

// Half two: a length one block short of a whole number of MiB, in the middle of the device so
// the final-range exemption cannot apply (FR-TEST-10).
expectRefusal("partial", startBlock: 0, blockCount: runBlocks - 1)

// And FR-FAIL-1's mode, which protocol v9 made a required parameter. An unrecognised code is
// REFUSED, never defaulted: resolving it to FR-FAIL-4's default would answer a caller asking to
// stop on the first error with a run that writes to the whole drive. The placement is valid here,
// so the refusal can only be the mode.
expectRefusal("badmode", startBlock: 0, blockCount: runBlocks, failureModeCode: 99)

let allCompleted = !runs.isEmpty && runs.allSatisfy { $0.completed }
releaseAndExit(transportFailed || !allCompleted ? 1 : 0)

// MARK: -

/// Small helpers kept out of the flow above.
enum TesterParameters {
    static var gibibyteDescription: String {
        "\(TesterProtocol.maximumBytesPerCall / (1 << 20)) MiB"
    }
}
