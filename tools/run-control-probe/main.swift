//
//  main.swift
//  run-control-probe — does a pause reach a running helper, and where does it settle?
//
//  Step 11, increment 2's pre-flight. The whole design of this step rests on one property that
//  has never been measured: that `setRunControl` sent on a **second connection** reaches a helper
//  inside a blocking `runRetentionCycle`, and that the run then settles at a chunk boundary within
//  roughly one chunk's worth of I/O.
//
//  ## Why this is measured before increments 3–7 are built, rather than at the step's gate
//
//  *A pre-flight before a design is committed to is almost free, and has killed two designs before
//  they were built.* Step 8's "fingerprint from a separate process" was sound right up until
//  `O_EXLOCK` was measured against a plain `O_RDONLY` and returned `EBUSY`; that measurement was
//  made before the gate design was committed to, which is the only reason it cost nothing. This is
//  the same move. A wrong number found in increment 7 is six increments built on top of it.
//
//  ## What the transport measurement already establishes, and what it does not
//
//  `scripts/xpc-concurrency-check.sh` measured (2026-08-04) that a second *connection* is answered
//  in 0.2–0.3 ms while a privileged call blocks the first. That is the transport half, and it is
//  settled. What it says nothing about is whether the **engine** acts on what arrives: the control
//  is read at a chunk boundary inside a loop no test outside this project's unit suite can reach,
//  and `RunCoordinator` — which wires the channel to that loop — is not in the test target at all.
//  A mutation swapping the helper's outward outcome mapping is likewise uncatchable by the suite
//  (see `RunControlWireTests`'s header). This probe is the cover for both.
//
//  ## THIS PROBE WRITES TO THE DEVICE
//
//  Unlike `xpc-concurrency-probe`, which deliberately used the read-only `digestRange`, this one
//  must use `runRetentionCycle`: the question is about the *run* loop's chunk boundary, and only a
//  run has one. The writes are the ordinary non-destructive cycle — every byte written is a byte
//  just read from that same offset (FR-TEST-7, NFR-REL-1) — but they are writes, and the wrapper
//  script treats them as such.
//
//  ## What is measured, and what would make the answer meaningless
//
//  For each of FR-CTRL-8's four I/O sizes: issue a bounded run, wait until it is demonstrably
//  mid-flight, send a pause on the second connection, and record three instants — pause sent,
//  pause acknowledged by the daemon, run reply arrived. **The settle latency is the third minus
//  the first**, and the second is reported separately because the two are different facts: the
//  daemon accepting a request is not the run having acted on it, which is the whole distinction
//  NFR-REL-10's handshake exists to preserve.
//
//  Three ways this could pass vacuously, all of which it refuses to call a result:
//
//    1. **The run finished before the pause was sent.** Then `outcome` is `completed` and nothing
//       was interrupted. Reported as INCONCLUSIVE, never as a settle.
//    2. **The run had not started.** If `chunksProcessed` is 0 the pause may have been seen before
//       the first chunk, which is a real state but not evidence that a *running* engine can be
//       interrupted. Reported as INCONCLUSIVE.
//    3. **The device is fast enough that a bounded call is shorter than the pre-pause wait.** The
//       control run at the top exists to measure that directly rather than assume it: it runs the
//       same range with no pause and reports how long a whole call takes. If that is not
//       comfortably longer than the wait, every subsequent case is inconclusive by construction
//       and the wrapper says so.
//
//  The raw instants are printed, not just the verdict, because a verdict is a conclusion and the
//  timestamps are the evidence.
//
//  Usage: run-control-probe <bsdName> [preRunPauseSeconds] [--repeat-1mib N]
//
//  Emits `KEY=VALUE` lines for `scripts/run-control-check.sh` to assert on, and a human table.
//
//  `--repeat-1mib N` appends N extra 1 MiB cases *after* the four-size table, under
//  `CASE_1MIB_R<n>_*` keys the gate's own parsing does not read. It answers a question the table
//  cannot — whether the settle has a fixed floor — and is documented at its own site below.
//  **The four gate cases run first, in order, and their keys are unchanged**, so a run with this
//  flag re-validates the gate and takes the samples in one pass.
//

import Foundation

// MARK: - Arguments

let arguments = CommandLine.arguments

/// How many extra 1 MiB samples to take after the four-size table, for the fixed-cost question
/// (see "The repeat samples" below). `0` — the default — leaves this probe's behaviour and its
/// emitted keys **exactly** as they were before 2026-09-05, which is what keeps the four gate
/// cases a re-run of the same instrument rather than a new one.
var repeatOneMiBSamples = 0
var positional: [String] = []

do {
    var index = 1
    while index < arguments.count {
        let argument = arguments[index]
        if argument == "--repeat-1mib" {
            guard index + 1 < arguments.count, let count = Int(arguments[index + 1]), count >= 0 else {
                FileHandle.standardError.write(Data("--repeat-1mib needs a non-negative count\n".utf8))
                exit(2)
            }
            repeatOneMiBSamples = count
            index += 2
            continue
        }
        positional.append(argument)
        index += 1
    }
}

guard let bsdName = positional.first else {
    FileHandle.standardError.write(
        Data("usage: run-control-probe <bsdName> [waitSeconds] [--repeat-1mib N]\n".utf8))
    exit(2)
}
let preRunWaitSeconds = positional.count >= 2 ? (Double(positional[1]) ?? 2.0) : 2.0

/// How much of the device one bounded call covers. The per-call cap, so the call is as long as a
/// call can legally be — which is what gives the pause the widest window to land inside.
let bytesPerCall = TesterProtocol.maximumBytesPerCall

/// A fixed, 1 MiB-aligned offset well inside the drive (FR-TEST-10).
///
/// Deliberately **not** random, unlike the retention gate's placement. That gate draws randomly
/// because it is proving something about the *medium* and must not always test the same cells;
/// this one is proving something about *control flow*, where a reproducible offset is worth more
/// than coverage — a latency that differs between runs should be the drive varying, not the
/// placement.
let startBlockBytes: UInt64 = 64 << 30      // 64 GiB in

// MARK: - Clock

func nowNanoseconds() -> UInt64 { clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) }

func millisecondsBetween(_ start: UInt64, _ end: UInt64) -> Double {
    end >= start ? Double(end - start) / 1_000_000 : -1
}

// MARK: - Connections

/// Two connections, and the second is not a convenience.
///
/// Measured 2026-08-04: a second message on a connection with a blocking call in flight is not
/// delivered until that call returns. So a pause sent on the run's own connection would arrive
/// *after* the run it was meant to interrupt had already ended, and this probe would report a
/// settle latency equal to the remaining run time — a plausible-looking number meaning nothing.
func makeConnection(_ label: String) -> NSXPCConnection {
    let connection = NSXPCConnection(machServiceName: HelperIdentity.machServiceName,
                                     options: .privileged)
    connection.remoteObjectInterface = NSXPCInterface(with: TesterControl.self)
    connection.invalidationHandler = {
        FileHandle.standardError.write(Data("\(label) connection invalidated\n".utf8))
    }
    connection.interruptionHandler = {
        FileHandle.standardError.write(Data("\(label) connection interrupted\n".utf8))
    }
    connection.resume()
    return connection
}

let runConnection = makeConnection("run")
let controlConnection = makeConnection("control")

func proxy(on connection: NSXPCConnection, _ label: String) -> TesterControl {
    let remote = connection.remoteObjectProxyWithErrorHandler { error in
        FileHandle.standardError.write(
            Data("\(label) transport error: \(error.localizedDescription)\n".utf8))
    }
    guard let tester = remote as? TesterControl else {
        FileHandle.standardError.write(Data("\(label): could not obtain a proxy\n".utf8))
        exit(3)
    }
    return tester
}

func emit(_ line: String) {
    print(line)
    fflush(stdout)
}

// MARK: - Handshake

var helperVersion = -1
let versionDone = DispatchSemaphore(value: 0)
proxy(on: runConnection, "run").protocolVersion { version in
    helperVersion = version
    versionDone.signal()
}
guard versionDone.wait(timeout: .now() + 10) == .success else {
    emit("PROBE_RESULT=NO_HELPER")
    exit(4)
}
emit("PROTOCOL=\(helperVersion)")
emit("EXPECTED=\(TesterProtocol.version)")
guard helperVersion == TesterProtocol.version else {
    emit("PROBE_RESULT=PROTOCOL_MISMATCH")
    exit(5)
}

// MARK: - Acquire

var acquired = false
var acquireMessage = ""
let acquireDone = DispatchSemaphore(value: 0)
proxy(on: runConnection, "run").acquireDevice(bsdName: bsdName) { ok, causeCode, message in
    acquired = ok
    acquireMessage = "cause=\(causeCode) \(message)"
    acquireDone.signal()
}
guard acquireDone.wait(timeout: .now() + 30) == .success else {
    emit("PROBE_RESULT=ACQUIRE_TIMEOUT")
    exit(6)
}
guard acquired else {
    emit("ACQUIRE_FAILED=\(acquireMessage)")
    emit("PROBE_RESULT=ACQUIRE_REFUSED")
    exit(7)
}
emit("ACQUIRED=\(bsdName)")

/// Release on every exit path from here on. The helper also releases when this connection dies,
/// but an acknowledged release is observable and an inferred one is not.
func releaseAndExit(_ code: Int32) -> Never {
    let releaseDone = DispatchSemaphore(value: 0)
    proxy(on: runConnection, "run").releaseDevice { _, message in
        emit("RELEASED=\(message.replacingOccurrences(of: "\n", with: " "))")
        releaseDone.signal()
    }
    _ = releaseDone.wait(timeout: .now() + 15)
    exit(code)
}

// MARK: - Geometry

var blockSize: UInt32 = 0
var deviceBlocks: UInt64 = 0
let profileDone = DispatchSemaphore(value: 0)
proxy(on: runConnection, "run").deviceProfile { available, ioctlSize, ioctlCount, _, _,
                                                _, _, _, message in
    if available { blockSize = ioctlSize; deviceBlocks = ioctlCount }
    else { emit("PROFILE_UNAVAILABLE=\(message)") }
    profileDone.signal()
}
_ = profileDone.wait(timeout: .now() + 15)
guard blockSize > 0, deviceBlocks > 0 else {
    emit("PROBE_RESULT=NO_GEOMETRY")
    releaseAndExit(8)
}
emit("BLOCK_SIZE=\(blockSize)")
emit("DEVICE_BLOCKS=\(deviceBlocks)")

let startBlock = startBlockBytes / UInt64(blockSize)

// The second run's placement, for the device-operation slot check below.
//
// **Disjoint from the region every other case uses, and only 1 MiB long.** The slot is device-wide
// — `beginDeviceOperation` refuses on "something else holds it", never on a range — so a disjoint
// range exercises it exactly as well as an overlapping one while touching the least possible media.
// That matters because the *failure* mode of this check is a run that escapes the guard, and the
// helper has one descriptor and one set of buffers to share between it and the run already in
// flight. 2 GiB past the start, which is 1 MiB-aligned wherever `startBlockBytes` is.
let secondRunStartBlock = startBlock + (UInt64(2) << 30) / UInt64(blockSize)
let secondRunBlocks = UInt64(1 << 20) / UInt64(blockSize)
let blockCount = bytesPerCall / UInt64(blockSize)
guard startBlock + blockCount <= deviceBlocks else {
    emit("PROBE_RESULT=RANGE_OFF_DEVICE")
    releaseAndExit(9)
}
emit("START_BLOCK=\(startBlock)")
emit("BLOCK_COUNT=\(blockCount)")

// MARK: - One run, optionally interrupted

struct RunOutcomeReport {
    var outcomeCode = -1
    var interruptedAtBlock: UInt64 = 0
    var chunksProcessed: UInt64 = 0
    var message = ""
    var repliedAt: UInt64 = 0
}

/// Set the control level and wait for the daemon to say it recorded it.
///
/// **The reply is not the acknowledgement of a settle** — it says only that the daemon has the
/// request. The settle is the run's own reply, later, carrying `pausedByUser`. Conflating the two
/// is precisely what BUILD-PLAN's risks note forbids, so they are timed separately here.
@discardableResult
func setControl(_ code: RunControlCode) -> (accepted: Bool, at: UInt64) {
    var accepted = false
    var at: UInt64 = 0
    let done = DispatchSemaphore(value: 0)
    proxy(on: controlConnection, "control").setRunControl(code: code.rawValue) { ok, _ in
        accepted = ok
        at = nowNanoseconds()
        done.signal()
    }
    _ = done.wait(timeout: .now() + 15)
    return (accepted, at)
}

/// Issue one bounded run. If `pauseAfter` is non-nil, send a pause that many seconds in.
func performRun(ioSizeBytes: Int, pauseAfter: Double?) -> (report: RunOutcomeReport,
                                                           issuedAt: UInt64,
                                                           pauseSentAt: UInt64,
                                                           pauseAckedAt: UInt64) {
    // Clean slate. The helper never clears the level by itself — the app owns it — so a previous
    // case's pause would otherwise stop this run at its first chunk.
    setControl(.proceed)

    var report = RunOutcomeReport()
    let runDone = DispatchSemaphore(value: 0)
    let issuedAt = nowNanoseconds()

    proxy(on: runConnection, "run").runRetentionCycle(
        startBlock: startBlock,
        blockCount: blockCount,
        ioSizeBytes: ioSizeBytes,
        failureModeCode: FailureModeCode.logAndContinue.rawValue
    ) { runOutcomeCode, interruptedAtBlock, chunksProcessed, _, _,
        _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, message in
        report.repliedAt = nowNanoseconds()
        report.outcomeCode = runOutcomeCode
        report.interruptedAtBlock = interruptedAtBlock
        report.chunksProcessed = chunksProcessed
        report.message = message.replacingOccurrences(of: "\n", with: " ")
        runDone.signal()
    }

    var pauseSentAt: UInt64 = 0
    var pauseAckedAt: UInt64 = 0
    if let pauseAfter {
        Thread.sleep(forTimeInterval: pauseAfter)
        pauseSentAt = nowNanoseconds()
        let (accepted, at) = setControl(.pause)
        pauseAckedAt = at
        if !accepted { emit("CONTROL_REFUSED=1") }
    }

    // Generous: a 1 GiB call is ~7 s at the scratch drive's measured rate, and a pause should cut
    // it far shorter. A timeout here is itself the finding.
    if runDone.wait(timeout: .now() + 180) != .success {
        emit("RUN_TIMEOUT=1")
    }
    return (report, issuedAt, pauseSentAt, pauseAckedAt)
}

// MARK: - The device-operation slot

/// Issue one bounded 1 MiB run on the **control** connection — deliberately not the connection that
/// acquired the device.
///
/// The claim is process-wide (`HelperActivity.shared`), not per-connection, so this reaches the
/// device-operation slot rather than being turned away for not owning the claim. That the idle call
/// below is *accepted* is what proves it: if ownership gated this call, both attempts would be
/// refused and the busy one would prove nothing.
func attemptSecondRun(_ label: String) -> RunOutcomeReport {
    var report = RunOutcomeReport()
    let done = DispatchSemaphore(value: 0)
    proxy(on: controlConnection, "control").runRetentionCycle(
        startBlock: secondRunStartBlock,
        blockCount: secondRunBlocks,
        ioSizeBytes: 1 << 20,
        failureModeCode: FailureModeCode.logAndContinue.rawValue
    ) { runOutcomeCode, _, chunksProcessed, _, _,
        _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, message in
        report.repliedAt = nowNanoseconds()
        report.outcomeCode = runOutcomeCode
        report.chunksProcessed = chunksProcessed
        report.message = message.replacingOccurrences(of: "\n", with: " ")
        done.signal()
    }
    if done.wait(timeout: .now() + 180) != .success {
        emit("\(label)_TIMEOUT=1")
    }
    return report
}

// MARK: - The control run: how long IS a bounded call?

// Without this, a drive fast enough to finish a call inside the pre-pause wait would make every
// case below report `completed`, and "the pause did nothing" and "the pause was too late" would be
// indistinguishable. Measuring the uninterrupted call first tells them apart.
// **Fired 1 s into the control run**, which lasts ~7 s at this drive's measured rate. Scheduled
// before the run is issued because `performRun` blocks until its reply arrives.
var busyAttempt = RunOutcomeReport()
let busyAttemptDone = DispatchSemaphore(value: 0)
DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
    busyAttempt = attemptSecondRun("SLOT_BUSY")
    busyAttemptDone.signal()
}

let control = performRun(ioSizeBytes: TesterProtocol.defaultIOSizeBytes, pauseAfter: nil)
let controlMilliseconds = millisecondsBetween(control.issuedAt, control.report.repliedAt)
emit("CONTROL_RUN_MS=\(String(format: "%.1f", controlMilliseconds))")
emit("CONTROL_RUN_OUTCOME=\(control.report.outcomeCode)")
emit("CONTROL_RUN_CHUNKS=\(control.report.chunksProcessed)")
emit("PRE_PAUSE_WAIT_MS=\(String(format: "%.1f", preRunWaitSeconds * 1000))")

guard control.report.outcomeCode == RunOutcomeCode.completed.rawValue else {
    emit("PROBE_RESULT=CONTROL_RUN_DID_NOT_COMPLETE")
    releaseAndExit(10)
}

// The busy attempt was issued while the call above was in flight. Its reply is collected here,
// after that call has completed, so the two cannot be confused.
_ = busyAttemptDone.wait(timeout: .now() + 240)
emit("SLOT_BUSY_OUTCOME=\(busyAttempt.outcomeCode)")
emit("SLOT_BUSY_CHUNKS=\(busyAttempt.chunksProcessed)")
emit("SLOT_BUSY_MESSAGE=\(busyAttempt.message)")

// **The same call again, with nothing in flight.** This is the half that makes the one above mean
// something: same request, same connection, and the only variable is whether the slot was taken.
// Without it a refusal proves only that *something* refused — connection ownership, the request
// itself, a typo in the block arithmetic — and a check that cannot be seen answering both ways is
// not a check. No mutation is needed for that evidence because the product supplies it.
let idleBefore = control.report.chunksProcessed
let idleAttempt = attemptSecondRun("SLOT_IDLE")
emit("SLOT_IDLE_OUTCOME=\(idleAttempt.outcomeCode)")
emit("SLOT_IDLE_CHUNKS_CUMULATIVE=\(idleAttempt.chunksProcessed)")
emit("SLOT_IDLE_CHUNKS=\(idleAttempt.chunksProcessed >= idleBefore ? idleAttempt.chunksProcessed - idleBefore : 0)")
emit("SLOT_IDLE_MESSAGE=\(idleAttempt.message)")

// The control run must still have finished cleanly. Without this, "refused cleanly" and "the
// second call broke the first one too" look identical from the assertions above.
emit("SLOT_CONTROL_SURVIVED=\(control.report.outcomeCode == RunOutcomeCode.completed.rawValue ? 1 : 0)")

// MARK: - The measurement, at each of FR-CTRL-8's I/O sizes

emit("")
emit("ioSize     outcome  chunks  resumeBlock    ackMs   settleMs")

var inconclusive = 0
var settled = 0

// **Chunk counts on the reply are CUMULATIVE across the session, not per call** — Step 11
// increment 3 moved the accumulators onto the claim. This probe was written at protocol v10, when
// they were per-call, and was **not** updated when that changed; `metrics-probe` was, and says so
// at length in its own header.
//
// Re-running this gate on 2026-08-24 — twelve days after it last ran — is what found it. The
// arithmetic below multiplied a running total by the *current* call's chunk size, so its prediction
// inflated with every case: it reported RESUME_POINT_WRONG four times over while the product was
// settling correctly at chunk-aligned boundaries every time. The reported totals reconciled exactly
// as differences (555, +150, +74, +37 — each ~300 MiB of covering work in the 2 s window), which is
// what proved the counter cumulative rather than the resume points wrong.
//
// **Every per-call figure below is therefore a DIFFERENCE.** The baseline is the cumulative total
// after *everything* that has already run, which is the idle slot attempt — not the control run.
//
// It read `control.report.chunksProcessed` for about ten minutes on 2026-08-24 and was wrong by
// exactly one chunk: the idle attempt runs 1 MiB of real work *after* the control run and before
// this loop, so the first case differenced against a baseline that predated it and reported a
// resume point 2048 blocks too far. **Anything added between the control run and this loop that
// touches the device must move this baseline forward**, which is why it reads from the last thing
// to run rather than naming a particular call.
var chunksBefore = idleAttempt.chunksProcessed

/// What one case concluded. Returned rather than counted inside, so the repeat loop below can
/// tally its own samples without touching the four the gate asserts on.
enum CaseVerdict { case settled, inconclusive, wrong }

/// Run one bounded, paused case and emit its keys under `prefix`.
///
/// **Extracted 2026-09-05 so the repeat loop cannot drift from the gate loop.** The two differ
/// only in which sizes they walk and what they name their keys; every figure — the chunk
/// difference, the resume arithmetic, the alignment — is computed here, once. Duplicating it for
/// the repeats is how `metrics-probe` and this probe came to disagree about what `chunksProcessed`
/// meant, which cost twelve days and four false RESUME_POINT_WRONG reports.
///
/// - Parameter prefix: the `KEY=` namespace, e.g. `CASE_1MIB` or `CASE_1MIB_R3`.
func measureCase(ioSizeBytes: Int, prefix: String) -> CaseVerdict {
    let result = performRun(ioSizeBytes: ioSizeBytes, pauseAfter: preRunWaitSeconds)
    let report = result.report

    // Differenced **before any early return**, so a case that bails out cannot corrupt the next
    // one's baseline. The `>=` guard means a counter that went backwards reads as zero work rather
    // than as a vast negative underflowing into a plausible block number.
    let chunksThisCall = report.chunksProcessed >= chunksBefore
        ? report.chunksProcessed - chunksBefore
        : 0
    chunksBefore = report.chunksProcessed

    let ackMilliseconds = millisecondsBetween(result.pauseSentAt, result.pauseAckedAt)
    let settleMilliseconds = millisecondsBetween(result.pauseSentAt, report.repliedAt)
    let mib = ioSizeBytes / (1 << 20)

    emit(String(format: "%-10s %7d  %6llu  %11llu  %7.2f  %9.2f",
                ("\(mib) MiB" as NSString).utf8String!,
                report.outcomeCode,
                chunksThisCall,
                report.interruptedAtBlock,
                ackMilliseconds,
                settleMilliseconds))

    emit("\(prefix)_OUTCOME=\(report.outcomeCode)")
    // `_CHUNKS` is this call's work, which is what every assertion downstream means by it.
    // The running total is emitted beside it so the two are never confused again.
    emit("\(prefix)_CHUNKS=\(chunksThisCall)")
    emit("\(prefix)_CHUNKS_CUMULATIVE=\(report.chunksProcessed)")
    emit("\(prefix)_RESUME_BLOCK=\(report.interruptedAtBlock)")
    emit("\(prefix)_ACK_MS=\(String(format: "%.3f", ackMilliseconds))")
    emit("\(prefix)_SETTLE_MS=\(String(format: "%.3f", settleMilliseconds))")

    // The two vacuous passes, refused rather than counted.
    if report.outcomeCode == RunOutcomeCode.completed.rawValue {
        emit("\(prefix)_VERDICT=INCONCLUSIVE_RUN_FINISHED_FIRST")
        return .inconclusive
    }
    // This check had become **untriggerable**: against a cumulative counter it could only read
    // zero if the control run had also done nothing, and that is already guarded above. On the
    // difference it can fail again, which is the whole point of it.
    if chunksThisCall == 0 {
        emit("\(prefix)_VERDICT=INCONCLUSIVE_PAUSE_BEFORE_FIRST_CHUNK")
        return .inconclusive
    }
    guard report.outcomeCode == RunOutcomeCode.pausedByUser.rawValue else {
        emit("\(prefix)_VERDICT=WRONG_OUTCOME")
        return .wrong
    }

    // **The arithmetic that proves the resume point is where the run actually stopped**, rather
    // than merely a plausible-looking block number. Every chunk before the settle was a full
    // `ioSizeBytes`, so the resume point must be exactly that many bytes past this call's start.
    //
    // `chunksThisCall`, never `report.chunksProcessed` — see the note above.
    let blocksPerChunk = UInt64(ioSizeBytes) / UInt64(blockSize)
    let expectedResume = startBlock + chunksThisCall * blocksPerChunk
    emit("\(prefix)_EXPECTED_RESUME_BLOCK=\(expectedResume)")
    let arithmeticHolds = report.interruptedAtBlock == expectedResume

    // FR-TEST-10: the resumed call must start on a 1 MiB boundary or the helper will refuse it.
    let blocksPerMebibyte = UInt64(1 << 20) / UInt64(blockSize)
    let aligned = report.interruptedAtBlock % blocksPerMebibyte == 0
    emit("\(prefix)_RESUME_ALIGNED=\(aligned ? 1 : 0)")

    if arithmeticHolds && aligned {
        emit("\(prefix)_VERDICT=SETTLED")
        return .settled
    }
    emit("\(prefix)_VERDICT=RESUME_POINT_WRONG")
    return .wrong
}

for ioSizeBytes in TesterProtocol.permittedIOSizes {
    switch measureCase(ioSizeBytes: ioSizeBytes, prefix: "CASE_\(ioSizeBytes / (1 << 20))MIB") {
    case .settled:      settled += 1
    case .inconclusive: inconclusive += 1
    case .wrong:        break
    }
}

emit("")
emit("SETTLED_CASES=\(settled)")
emit("INCONCLUSIVE_CASES=\(inconclusive)")
emit("TOTAL_CASES=\(TesterProtocol.permittedIOSizes.count)")

// MARK: - The repeat samples (2026-09-05)
//
// **This walks ONE size many times, which is a different question from the loop above.**
//
// The four-size table reports one sample per size, and CONSTRAINTS §1's model says a settle is
// "the remainder of the current chunk", so a sample scatters uniformly across one chunk's worth of
// time. Twelve samples across three runs fit that — except the 1 MiB column, which rode high in
// every run (0.87 -> 0.96 -> 1.43) and on 2026-09-05 came back at 9.33 ms against a bound of
// ~6.5 ms. A fraction above 1.0 is not an unlucky draw, it is out of range, so the model is what
// is wrong.
//
// The competing hypothesis is `settle = remainder of the current chunk + a fixed cost` — a few ms
// of reply plumbing, invisible against 8 MiB's ~53 ms bound and dominant against 1 MiB's ~6.5 ms.
// **A fixed cost has a floor; a uniform draw does not**, so the discriminating experiment is to
// repeat the smallest size alone and look at the bottom of the distribution, not the top. Three
// samples per column cannot separate them; a dozen at one size can.
//
// **ANSWERED 2026-09-05, first time this ran: it is a floor, and the fixed cost is ~3.5 ms.**
// Eight samples, minimum 0.65 of its own bound, three of the eight above 1.0. Under a uniform draw
// the minimum is a one-in-4,400 event and the three above 1.0 are impossible. The flag is kept
// because the figure is a property of this machine and this drive, not a constant — re-run it when
// either changes, or when the reply's payload does. Full account in CONSTRAINTS section 1.
//
// Each sample carries its own calibration — the chunk count in its own 2 s pre-pause window — so
// the repeats need neither the control run nor the other three sizes to be comparable with the
// table. They run last so the four gate cases are untouched, in order, exactly as before.
if repeatOneMiBSamples > 0 {
    emit("")
    emit("-- repeat samples at 1 MiB --")
    emit("ioSize     outcome  chunks  resumeBlock    ackMs   settleMs")

    var repeatSettled = 0
    for sample in 1...repeatOneMiBSamples {
        if measureCase(ioSizeBytes: 1 << 20, prefix: "CASE_1MIB_R\(sample)") == .settled {
            repeatSettled += 1
        }
    }
    emit("")
    emit("REPEAT_1MIB_SAMPLES=\(repeatOneMiBSamples)")
    emit("REPEAT_1MIB_SETTLED=\(repeatSettled)")
}

// Leave the daemon as it was found. A stale `pause` could only make a later run do less, but
// leaving one behind would be leaving an instrument's residue in the product's state.
setControl(.proceed)

emit("PROBE_RESULT=\(settled == TesterProtocol.permittedIOSizes.count ? "OK" : "INCOMPLETE")")
releaseAndExit(settled == TesterProtocol.permittedIOSizes.count ? 0 : 1)
