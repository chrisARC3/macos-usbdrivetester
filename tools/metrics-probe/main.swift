//
//  main.swift
//  metrics-probe — drives a real run and polls its live metrics from a second connection, the
//  way the GUI does.
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
//    * connection A issues `runRetentionCycle` and blocks for the whole call;
//    * connection B polls `runProgress` twice a second and timestamps every reply.
//
//  Two connections is not a stylistic choice. Measured 2026-08-04
//  (`scripts/xpc-concurrency-check.sh`): a second message on a connection with a call in flight
//  is **not delivered until that call returns**, while a second connection is answered
//  concurrently in 0.2–0.3 ms.
//
//  ## PROTOCOL v11: FOUR CALLS ARE ONE RUN, AND THE FIGURES ARE CUMULATIVE
//
//  Rewritten in Step 11 increment 3. A run is now a sequence of bounded calls and the accumulators
//  live on the claim (CONSTRAINTS section 2), so this probe's four cycles — one per I/O size FR-CTRL-8
//  offers — are **one run of four calls** inside one `acquireDevice`, not four runs. Three things
//  follow, and each is a deliberate change to what the gate asserts:
//
//    * **Every figure but two is cumulative.** Chunk counts, latency samples, failure counts,
//      throughput and the two NFR-PERF-3 fractions describe the run so far, not the call that
//      returned them. The expectations below are running totals, computed here so a wrong one is a
//      failure rather than a number nobody checked. `bufferBytesHeld` and the outcome code stay
//      per-call.
//    * **Each size runs over its OWN gibibyte**, at `index × runBlocks`, rather than all four over
//      the first one. That keeps `currentBlock` and `fractionComplete` monotonic across the seam —
//      which is the property a real sequencer has, so the gate now rehearses the shape increment 4
//      will use instead of a shape nothing in the product produces.
//    * **Progress is against the WHOLE DEVICE.** Four gibibytes of a 1 TB drive is ~0.43%, not
//      100%. `EXPECTED_FRACTION` is computed here from the ioctl block count and the bytes actually
//      asked for, so a helper that used the *call's* range as its denominator — which is what the
//      code did before this increment — would report ~100% and be caught rather than believed.
//
//  ## ⚠️  THIS WRITES TO THE DRIVE
//
//  It runs the read → write-back → verify cycle over the **first 4 GiB** of the device, starting at
//  block 0 — which is where a real run begins (FR-TEST-4) and is 1 MiB-aligned by construction
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

               WRITES to the first 4 GiB of the named device.
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
    let coveringBytesPerSecond: Double
    /// `R-W-R-C speed` — v13 added it, v14 moved its denominator to successful phase time.
    let completedBytesPerSecond: Double
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

// THE SESSION OPENS HERE. Everything below is one run; `releaseAndExit` closes it.
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

// **Clear the run-control level before issuing anything.**
//
// `RunControlChannel` is a process-wide slot on the daemon that never clears itself. Its own header
// argues a stale value is harmless because *"the app owns the state and sets `proceed` before every
// run"*. That is true of the app. **It is not true of this probe, which is not the app** — and every
// gate script in this project is a client that is not the app.
//
// Measured 2026-08-23: the app set `stop` at 09:11:29 during a GUI session, nothing set it back, and
// this gate's four calls each returned `stoppedByUser` after 0.5 ms having processed zero chunks.
// Forty assertions failed off one stale value and not one of them named it. Whether this gate passes
// cannot depend on whether somebody pressed Stop in the GUI an hour earlier.
//
// Sent on the **progress** connection — the non-owning one, which is where the app sends it too, and
// the reason a level can be set at all while a call is in flight on the owning connection.
// `run-control-probe` has cleared the level since increment 2; this probe predates the channel and
// was never updated when it arrived.
var levelCleared = false
blockingCall("control", on: progressConnection) { tester, done in
    tester.setRunControl(code: RunControlCode.proceed.rawValue) { accepted, message in
        levelCleared = accepted
        print("[control] LEVEL_CLEARED=\(accepted ? 1 : 0)")
        print("[control] MESSAGE=\(message)")
        done()
    }
}

// Abandoned rather than attempted, exactly as `RunController.resume()` abandons: a run issued over
// an uncleared level measures nothing and then reports it as a run.
guard levelCleared else {
    print("[probe] ABORTED=the run-control level was not cleared")
    releaseAndExit(1)
}

var blockSize: UInt32 = 0
var deviceBlockCount: UInt64 = 0
var linkSpeedCode = -1
blockingCall("profile", on: runConnection) { tester, done in
    tester.deviceProfile { available, ioctlBlockSize, ioctlBlockCount, _, _, _, speedCode, _, message in
        if available {
            blockSize = ioctlBlockSize
            deviceBlockCount = ioctlBlockCount
            linkSpeedCode = speedCode
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

// One gibibyte per I/O size, each over its **own** region, advancing from block 0.
//
// Block 0 is where a real run begins (FR-TEST-4); each start is a whole multiple of the per-call
// cap and therefore 1 MiB-aligned (FR-TEST-10), and each length is the cap itself, a whole number
// of MiB. Advancing rather than repeating is what keeps `currentBlock` and `fractionComplete`
// monotonic across the four calls — the shape a real sequencer produces.
//
// ## Why every size, and not just the default
//
// Sweeping all four of FR-CTRL-8's sizes exercises the chunk plan at every size the UI can select,
// on real media, and at an 8× spread of chunk counts. It no longer doubles as the host-cost
// normalisation study: that question — does the cost follow bytes moved or chunk count? — was
// settled on 2026-08-05 and is recorded in CONSTRAINTS section 1 ("Host cost follows bytes moved,
// not chunk count"). Under a cumulative session the per-size figures are running totals and cannot
// be compared against one another anyway; NFR-PERF-3's own claim is asserted at the end, where the
// cumulative fraction is the run's.
let runBlocks = TesterProtocol.maximumBytesPerCall / UInt64(blockSize)
let sweepSizes = TesterProtocol.permittedIOSizes
let detailedSize = TesterProtocol.defaultIOSizeBytes
let deviceBytes = deviceBlockCount * UInt64(blockSize)

guard deviceBlockCount >= UInt64(sweepSizes.count) * runBlocks else {
    print("[probe] ABORTED=the device is smaller than the \(sweepSizes.count) GiB this sweep covers")
    releaseAndExit(1)
}

print("[probe] BLOCK_SIZE=\(blockSize)")
print("[probe] DEVICE_BLOCKS=\(deviceBlockCount)")
print("[probe] DEVICE_BYTES=\(deviceBytes)")
print("[probe] LINK_SPEED_CODE=\(linkSpeedCode)")
print("[probe] START_BLOCK=0")
print("[probe] RUN_BLOCKS=\(runBlocks)")
print("[probe] SWEEP_SIZES=\(sweepSizes.map(String.init).joined(separator: ","))")
print("[probe] DETAILED_SIZE=\(detailedSize)")

// MARK: - One call of the run, polled from the other connection

/// What one call produced. The figures marked cumulative describe the **run**, not this call.
struct CycleRun {
    let ioSizeBytes: Int
    let startBlock: UInt64

    /// Protocol v10: how **this call** ended. `1` is `RunOutcomeCode.completed`.
    let outcomeCode: Int
    let interruptedAtBlock: UInt64

    /// Cumulative — every chunk the run has attempted.
    let chunks: UInt64

    let failedRanges: Int                       // cumulative
    let failureSummary: String                  // cumulative
    let cacheBypass: Int                        // the run's verdict, only ever downgraded
    let bufferBytes: Int                        // per call: 2 x this call's I/O size
    let hostOverheadFraction: Double            // cumulative
    let helperCoreFraction: Double              // cumulative, bracketed from acquire
    let message: String
    let wallNanoseconds: UInt64                 // this call's own wall clock, measured here
    let samples: [Sample]
    let replyNanoseconds: UInt64
    let startNanoseconds: UInt64

    /// The run's figures, arriving in the reply rather than having to be polled for — which is
    /// what keeps protocol v9's property at run scope: a refused call returns none of them.
    let failureModeUsed: Int
    let failedBlockCount: UInt64
    let finalReadBytesPerSecond: Double
    let finalWriteBytesPerSecond: Double
    let finalCoveringBytesPerSecond: Double
    let finalCompletedBytesPerSecond: Double
    let finalLatencySamples: UInt64
    let finalLatencyMinimumNanoseconds: UInt64
    let finalLatencyMaximumNanoseconds: UInt64
    let finalLatencyP99UpperNanoseconds: UInt64
}

func runCycle(ioSizeBytes: Int, startBlock: UInt64) -> CycleRun {
    let log = SampleLog()
    let finished = Flag()
    let semaphore = DispatchSemaphore(value: 0)

    var outcomeCode = 0
    var interruptedAt: UInt64 = 0
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
    var finalCoveringRate = -1.0
    var finalCompletedRate = -1.0
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
        tester.runRetentionCycle(startBlock: startBlock,
                                 blockCount: runBlocks,
                                 ioSizeBytes: ioSizeBytes,
                                 failureModeCode: FailureModeCode.standard.rawValue) {
            outcome, resumeBlock, chunkCount, failed, summary, bypass, _, buffers, hostOverhead,
            coreFraction, modeUsed, _, failedBlocks, readRate, writeRate, coveringRate,
            completedRate, latencySampleCount, latencyMin, latencyMax, latencyP99, text, _ in

            replyNanoseconds = nowNanoseconds()
            outcomeCode = outcome
            interruptedAt = resumeBlock
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
            finalCoveringRate = coveringRate
            finalCompletedRate = completedRate
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
    // No settling delay any more, and its removal is the point. It existed because
    // `MetricsChannel.begin()` replaced the shared slot *after* validation, so the first poll of
    // each size saw the **previous** size's completed snapshot at 100% and the table then dropped
    // to 3% — progress apparently going backwards. Under a session there is no slot to replace and
    // no previous run to see: a poll during call 2 legitimately returns the run's state after
    // call 1, which is exactly what monotonic progress looks like.
    let pollInterval = Double(pollIntervalMilliseconds) / 1_000
    let deadline = startNanoseconds &+ 600 * 1_000_000_000

    while !finished.isRaised && nowNanoseconds() < deadline {
        if let tester = proxy(on: progressConnection, onError: { error in
            print("[progress] TRANSPORT_ERROR=\(error.localizedDescription)")
            transportFailed = true
        }) {
            tester.runProgress { available, fraction, currentBlock, readRate, writeRate,
                                 coveringRate, completedRate, remaining, latencySamples,
                                 latencyMin, latencyMax, latencyP99, chunksFailed in
                log.append(Sample(atNanoseconds: nowNanoseconds(),
                                  available: available,
                                  fractionComplete: fraction,
                                  currentBlock: currentBlock,
                                  readBytesPerSecond: readRate,
                                  writeBytesPerSecond: writeRate,
                                  coveringBytesPerSecond: coveringRate,
                                  completedBytesPerSecond: completedRate,
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

    // ONE MORE POLL, AFTER THE CALL HAS REPLIED.
    //
    // The loop above exits the instant the cycle replies, so its newest snapshot is whatever the
    // last poll caught — up to one poll interval *before* the end. On 2026-08-04 that made the
    // gate report "progress ended at 93.75%" and "240 latency samples for 256 chunks" at every
    // I/O size, and the arithmetic gave it away: every figure was exactly samples/chunks. The call
    // had completed; nobody had asked the helper what the completed state was.
    //
    // The session keeps accumulating for as long as the claim is held, so this final ask is what
    // the run actually stood at when this call ended.
    blockingCall("final-progress", on: progressConnection, timeout: 30) { tester, done in
        tester.runProgress { available, fraction, currentBlock, readRate, writeRate,
                             coveringRate, completedRate, remaining, latencySamples,
                             latencyMin, latencyMax, latencyP99, chunksFailed in
            log.append(Sample(atNanoseconds: nowNanoseconds(),
                              available: available,
                              fractionComplete: fraction,
                              currentBlock: currentBlock,
                              readBytesPerSecond: readRate,
                              writeBytesPerSecond: writeRate,
                              coveringBytesPerSecond: coveringRate,
                              completedBytesPerSecond: completedRate,
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
                    startBlock: startBlock,
                    outcomeCode: outcomeCode,
                    interruptedAtBlock: interruptedAt,
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
                    finalCoveringBytesPerSecond: finalCoveringRate,
                    finalCompletedBytesPerSecond: finalCompletedRate,
                    finalLatencySamples: finalLatencySamples,
                    finalLatencyMinimumNanoseconds: finalLatencyMinimum,
                    finalLatencyMaximumNanoseconds: finalLatencyMaximum,
                    finalLatencyP99UpperNanoseconds: finalLatencyP99Upper)
}

func column(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
}

// MARK: - The sweep: four calls, one run

var runs: [CycleRun] = []

/// The running totals the session should be reporting. Computed here rather than read back, so
/// "the helper agrees with itself" is not what is being checked.
var expectedChunks: UInt64 = 0
var expectedBlocksCovered: UInt64 = 0
var previousFraction = -1.0
var previousCurrentBlock: UInt64 = 0

for (index, size) in sweepSizes.enumerated() {
    let startBlock = UInt64(index) * runBlocks
    expectedChunks += TesterProtocol.maximumBytesPerCall / UInt64(size)
    expectedBlocksCovered += runBlocks

    print("")
    print("  ── \(size / (1 << 20)) MiB I/O ─────────────────────────────────────────────")
    print("  call \(index + 1) of \(sweepSizes.count): \(TesterParameters.gibibyteDescription) "
        + "from block \(startBlock), polling every \(pollIntervalMilliseconds) ms …")
    let run = runCycle(ioSizeBytes: size, startBlock: startBlock)
    runs.append(run)

    let expectedFraction = Double(expectedBlocksCovered) / Double(deviceBlockCount)

    print("[size:\(size)] START_BLOCK=\(startBlock)")
    print("[size:\(size)] OUTCOME_CODE=\(run.outcomeCode)")
    print("[size:\(size)] EXPECTED_OUTCOME_CODE=\(RunOutcomeCode.completed.rawValue)")
    print("[size:\(size)] INTERRUPTED_AT_BLOCK=\(run.interruptedAtBlock)")
    print("[size:\(size)] CHUNKS=\(run.chunks)")
    print("[size:\(size)] EXPECTED_CHUNKS=\(expectedChunks)")
    print("[size:\(size)] FAILED_RANGES=\(run.failedRanges)")
    print("[size:\(size)] FAILURE_SUMMARY=\(run.failureSummary)")
    print("[size:\(size)] CACHE_BYPASS=\(run.cacheBypass)")
    print("[size:\(size)] BUFFER_BYTES=\(run.bufferBytes)")
    print("[size:\(size)] EXPECTED_BUFFER_BYTES=\(size * 2)")
    print("[size:\(size)] WALL_MS=\(formatted(milliseconds(run.wallNanoseconds)))")
    print("[size:\(size)] HOST_OVERHEAD_FRACTION=\(run.hostOverheadFraction)")
    print("[size:\(size)] HELPER_CORE_FRACTION=\(run.helperCoreFraction)")

    // Cadence and progress, per call — NFR-PERF-5 is not a property of one I/O size.
    let inRun = run.samples.filter { $0.atNanoseconds <= run.replyNanoseconds }
    var widestGap = 0.0
    for sampleIndex in 1 ..< Swift.max(inRun.count, 1) {
        let gap = milliseconds(inRun[sampleIndex].atNanoseconds
                                &- inRun[sampleIndex - 1].atNanoseconds)
        if gap > widestGap { widestGap = gap }
    }
    // Mid-run means: available, arrived before the reply, and reporting real coverage. The old
    // `fractionComplete < 1` clause is gone — against the whole device the fraction never
    // approaches 1 on a drive this size, so it excluded nothing and would have been a filter
    // nobody could see failing.
    let midRun = run.samples.filter {
        $0.available && $0.atNanoseconds < run.replyNanoseconds && $0.fractionComplete > 0
    }
    let final = run.samples.last

    // Monotonic **across the whole run**, not within one call: the session accumulates, so a
    // fraction that fell at a call boundary would mean the accumulator had been reset — which is
    // precisely the defect this increment removed.
    var monotonic = true
    for sample in run.samples where sample.available && sample.fractionComplete > 0 {
        if sample.fractionComplete < previousFraction { monotonic = false }
        previousFraction = Swift.max(previousFraction, sample.fractionComplete)
        if sample.currentBlock < previousCurrentBlock { monotonic = false }
        previousCurrentBlock = Swift.max(previousCurrentBlock, sample.currentBlock)
    }

    print("[size:\(size)] SAMPLES_TOTAL=\(run.samples.count)")
    print("[size:\(size)] SAMPLES_MID_RUN=\(midRun.count)")
    print("[size:\(size)] WIDEST_GAP_MS=\(formatted(widestGap))")
    print("[size:\(size)] MONOTONIC=\(monotonic ? 1 : 0)")
    print("[size:\(size)] FINAL_FRACTION=\(formatted((final?.fractionComplete ?? 0) * 100, 6))")
    print("[size:\(size)] EXPECTED_FRACTION=\(formatted(expectedFraction * 100, 6))")
    print("[size:\(size)] FINAL_CURRENT_BLOCK=\(final?.currentBlock ?? 0)")
    print("[size:\(size)] EXPECTED_CURRENT_BLOCK=\(startBlock + runBlocks)")
    print("[size:\(size)] FINAL_LATENCY_SAMPLES=\(final?.latencySamples ?? 0)")
    print("[size:\(size)] FINAL_LATENCY_MIN_NS=\(final?.latencyMinimum ?? 0)")
    print("[size:\(size)] FINAL_LATENCY_MAX_NS=\(final?.latencyMaximum ?? 0)")
    print("[size:\(size)] FINAL_LATENCY_P99_NS=\(final?.latencyP99Upper ?? 0)")
    print("[size:\(size)] FINAL_READ_BYTES_PER_SECOND=\(final?.readBytesPerSecond ?? -1)")
    print("[size:\(size)] FINAL_WRITE_BYTES_PER_SECOND=\(final?.writeBytesPerSecond ?? -1)")
    print("[size:\(size)] FINAL_COVERING_BYTES_PER_SECOND=\(final?.coveringBytesPerSecond ?? -1)")
    print("[size:\(size)] FINAL_RWRC_BYTES_PER_SECOND=\(final?.completedBytesPerSecond ?? -1)")
    print("[size:\(size)] FINAL_CHUNKS_FAILED=\(final?.chunksFailed ?? 0)")

    // The same figures, by a completely different route: these came back in the cycle's reply,
    // the `FINAL_*` ones above from a `runProgress` poll issued after it. **They must agree.**
    //
    // That agreement is the only check available on the part of the reply no unit test can reach.
    // The reply is twenty positional values assembled in the helper's `main.swift`, six of them
    // adjacent same-typed numbers — two `Double` rates and four `UInt64` latency figures — and a
    // transposition there would compile, run, and put read throughput under "write" in an exported
    // report. Two independent paths to the same numbers is what makes it visible.
    print("[size:\(size)] REPLY_FAILURE_MODE_USED=\(run.failureModeUsed)")
    print("[size:\(size)] REPLY_FAILED_BLOCKS=\(run.failedBlockCount)")
    print("[size:\(size)] REPLY_READ_BYTES_PER_SECOND=\(run.finalReadBytesPerSecond)")
    print("[size:\(size)] REPLY_WRITE_BYTES_PER_SECOND=\(run.finalWriteBytesPerSecond)")
    print("[size:\(size)] REPLY_COVERING_BYTES_PER_SECOND=\(run.finalCoveringBytesPerSecond)")
    print("[size:\(size)] REPLY_RWRC_BYTES_PER_SECOND=\(run.finalCompletedBytesPerSecond)")
    print("[size:\(size)] REPLY_LATENCY_SAMPLES=\(run.finalLatencySamples)")
    print("[size:\(size)] REPLY_LATENCY_MIN_NS=\(run.finalLatencyMinimumNanoseconds)")
    print("[size:\(size)] REPLY_LATENCY_MAX_NS=\(run.finalLatencyMaximumNanoseconds)")
    print("[size:\(size)] REPLY_LATENCY_P99_NS=\(run.finalLatencyP99UpperNanoseconds)")

    // The full snapshot table only for the default size, or the output becomes unreadable.
    guard size == detailedSize else { continue }
    print("")
    print("  live snapshots at the default I/O size, relative to this call starting")
    print("    " + column("at ms", 10) + column("% device", 11) + column("read MB/s", 12)
        + column("write MB/s", 12) + column("ETA s", 11) + column("reads", 9) + "p99 ms")
    for sample in run.samples where sample.available {
        let at = milliseconds(sample.atNanoseconds &- run.startNanoseconds)
        print("    " + column(formatted(at, 0), 10)
            + column(formatted(sample.fractionComplete * 100, 4), 11)
            + column(sample.readBytesPerSecond >= 0
                     ? formatted(sample.readBytesPerSecond / 1_000_000, 0) : "—", 12)
            + column(sample.writeBytesPerSecond >= 0
                     ? formatted(sample.writeBytesPerSecond / 1_000_000, 0) : "—", 12)
            + column(sample.estimatedRemainingSeconds >= 0
                     ? formatted(sample.estimatedRemainingSeconds, 0) : "—", 11)
            + column("\(sample.latencySamples)", 9)
            + (sample.latencySamples > 0
               ? formatted(Double(sample.latencyP99Upper) / 1_000_000, 3) : "—"))
    }
}

// MARK: - What the run came to

print("")
print("  ── the run, cumulative ─────────────────────────────────────────────────────────")
if let last = runs.last {
    let coveredGiB = Double(expectedBlocksCovered * UInt64(blockSize)) / Double(1 << 30)
    let deviceGiB = Double(deviceBytes) / Double(1 << 30)
    print("    chunks               \(last.chunks)")
    print("    read-latency samples \(last.finalLatencySamples)")
    print("    covered              \(formatted(coveredGiB, 2)) GiB of \(formatted(deviceGiB, 2)) GiB")
    print("    host overhead        \(formatted(last.hostOverheadFraction * 100, 3))% of device I/O time")
    print("    daemon CPU           \(formatted(last.helperCoreFraction * 100, 3))% of one core")
    print("[run] CUMULATIVE_CHUNKS=\(last.chunks)")
    print("[run] CUMULATIVE_EXPECTED_CHUNKS=\(expectedChunks)")
    print("[run] CUMULATIVE_LATENCY_SAMPLES=\(last.finalLatencySamples)")
    print("[run] CUMULATIVE_HOST_OVERHEAD_FRACTION=\(last.hostOverheadFraction)")
    print("[run] CUMULATIVE_HELPER_CORE_FRACTION=\(last.helperCoreFraction)")
}
print("")
print("  Host cost follows BYTES MOVED, not chunk count — measured 2026-08-05 and recorded in")
print("  CONSTRAINTS section 1. This sweep no longer re-derives it: under a cumulative session the")
print("  per-size figures are running totals and cannot be compared with one another.")

print("[probe] TRANSPORT_FAILED=\(transportFailed ? 1 : 0)")

// MARK: - FR-TEST-10 shown refusing, and a refused call carrying no figures

// A run that satisfies the placement rule proves the rule did not get in the way. It says
// nothing about whether the rule is *enforced* — and an unenforced guard is indistinguishable
// from an enforced one until the day something misaligned arrives. So both halves are asked for
// explicitly and both must be refused.
//
// Neither of these performs any I/O: `RunCoordinator.runCycle` validates placement before it
// vends a block device, so a refusal costs nothing and touches nothing.
//
// ## AND THIS IS NOW THE SHARPER HALF OF THE GATE
//
// These refusals arrive **inside the session the four calls above filled**, so the figures a
// refusal could wrongly report are no longer some previous run's — they are *this* run's, sitting
// on the claim, four gibibytes of entirely plausible measurements. Under protocol v9 the guard was
// structural: the observer a call read its figures from did not exist until that call passed
// validation. Under a session the accumulators predate the call, and what keeps the property is
// that `RunCoordinator` returns a `CycleResult` only on success, so `main.swift`'s refusal path has
// nothing to read from.
//
// That is a weaker guard, and `main.swift` is not in the test target. **These four lines are the
// only check anywhere that reaches that reply assembly.**

func expectRefusal(_ label: String,
                   startBlock: UInt64,
                   blockCount: UInt64,
                   failureModeCode: Int = FailureModeCode.standard.rawValue) {
    blockingCall(label, on: runConnection, timeout: 60) { tester, done in
        tester.runRetentionCycle(startBlock: startBlock,
                                 blockCount: blockCount,
                                 ioSizeBytes: detailedSize,
                                 failureModeCode: failureModeCode) {
            outcome, _, chunks, _, _, _, _, _, _, _, modeUsed, ranges, failedBlocks,
            readRate, writeRate, coveringRate, completedRate, latencySamples, _, _, _, message,
            // v15's device-loss phase. Not this gate's subject — it measures a healthy drive,
            // where the field is always `unrecognised` — and asserting `0` here would be a test
            // that agrees with any change.
            _ in

            // WAS THE CALL REFUSED — and nothing else. The outcome code alone answers it.
            //
            // This used to be `outcome == unrecognised && chunks == 0`, one flag stating two
            // facts, and mutation H1 on 2026-08-12 showed why that is wrong. H1 leaked the
            // session's figures into the refusal reply; the helper had refused correctly — outcome
            // 0, and the message was the right FR-TEST-10 text — but the leaked chunk count
            // flipped this flag and the gate reported "the alignment guard is not enforced",
            // sending the reader to `RunPlacement`, which was innocent.
            //
            // Under v11 the conflation is not merely unhelpful, it is measuring the wrong thing:
            // `chunks` in the reply is the RUN's cumulative total, so it is non-zero for reasons
            // that have nothing to do with whether this call did any work. "Did it report
            // anything it should not have" is a separate fact and has its own line below.
            print("[\(label)] REFUSED=\(outcome == RunOutcomeCode.unrecognised.rawValue ? 1 : 0)")
            print("[\(label)] OUTCOME_CODE=\(outcome)")
            print("[\(label)] CHUNKS=\(chunks)")
            print("[\(label)] MODE_USED=\(modeUsed)")
            print("[\(label)] RANGES_ENCODED=\(ranges)")
            print("[\(label)] FAILED_BLOCKS=\(failedBlocks)")
            print("[\(label)] READ_BYTES_PER_SECOND=\(readRate)")
            print("[\(label)] WRITE_BYTES_PER_SECOND=\(writeRate)")
            print("[\(label)] COVERING_BYTES_PER_SECOND=\(coveringRate)")
            // v13's fourth rate, on the refusal path too. `metrics-check.sh` asserts all four are
            // -1 here: a refused call must report NO figures, and a rate that came back 0 would
            // read as "stalled" rather than "never measured".
            print("[\(label)] RWRC_BYTES_PER_SECOND=\(completedRate)")
            print("[\(label)] LATENCY_SAMPLES=\(latencySamples)")
            print("[\(label)] MESSAGE=\(message)")
            done()
        }
    }
}

print("")
print("  asking for three runs the helper must refuse …")
print("")

// Half one: a start one block past a boundary — 512 bytes in, not a 1 MiB boundary (FR-TEST-10).
expectRefusal("misaligned", startBlock: 1, blockCount: runBlocks)

// Half two: a length one block short of a whole number of MiB, in the middle of the device so
// the final-range exemption cannot apply (FR-TEST-10).
expectRefusal("partial", startBlock: 0, blockCount: runBlocks - 1)

// And FR-FAIL-1's mode, which protocol v9 made a required parameter. An unrecognised code is
// REFUSED, never defaulted: resolving it to FR-FAIL-4's default would answer a caller asking to
// stop on the first error with a run that writes to the whole drive. The placement is valid here,
// so the refusal can only be the mode.
expectRefusal("badmode", startBlock: 0, blockCount: runBlocks, failureModeCode: 99)

// MARK: - And the session dies with the claim

// One poll after the release. Under protocol v9 this returned the finished run's figures for as
// long as the daemon lived, because the slot was never cleared. The session is a property of the
// claim, so releasing it destroyed the accumulators and there is nothing left to report — which is
// what makes "a poll cannot return a previous run's numbers" a fact about the object graph rather
// than about anybody remembering to clear something.

blockingCall("release", on: runConnection) { tester, done in
    tester.releaseDevice { released, message in
        print("[release] RELEASED=\(released ? 1 : 0)")
        print("[release] MESSAGE=\(message)")
        done()
    }
}

blockingCall("after-release", on: progressConnection, timeout: 30) { tester, done in
    tester.runProgress { available, fraction, currentBlock, readRate, _, _, _, _,
                         latencySamples, _, _, _, _ in
        print("[after-release] AVAILABLE=\(available ? 1 : 0)")
        print("[after-release] FRACTION=\(fraction)")
        print("[after-release] CURRENT_BLOCK=\(currentBlock)")
        print("[after-release] READ_BYTES_PER_SECOND=\(readRate)")
        print("[after-release] LATENCY_SAMPLES=\(latencySamples)")
        done()
    }
}

let allCompleted = !runs.isEmpty
    && runs.allSatisfy { $0.outcomeCode == RunOutcomeCode.completed.rawValue }
runConnection.invalidate()
progressConnection.invalidate()
exit(transportFailed || !allCompleted ? 1 : 0)

// MARK: -

/// Small helpers kept out of the flow above.
enum TesterParameters {
    static var gibibyteDescription: String {
        "\(TesterProtocol.maximumBytesPerCall / (1 << 20)) MiB"
    }
}
