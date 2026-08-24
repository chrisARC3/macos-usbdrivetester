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
//  Usage: run-control-probe <bsdName> [preRunPauseSeconds]
//
//  Emits `KEY=VALUE` lines for `scripts/run-control-check.sh` to assert on, and a human table.
//

import Foundation

// MARK: - Arguments

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: run-control-probe <bsdName> [waitSeconds]\n".utf8))
    exit(2)
}
let bsdName = arguments[1]
let preRunWaitSeconds = arguments.count >= 3 ? (Double(arguments[2]) ?? 2.0) : 2.0

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
        _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, message in
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

// MARK: - The control run: how long IS a bounded call?

// Without this, a drive fast enough to finish a call inside the pre-pause wait would make every
// case below report `completed`, and "the pause did nothing" and "the pause was too late" would be
// indistinguishable. Measuring the uninterrupted call first tells them apart.
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
// **Every per-call figure below is therefore a DIFFERENCE.** The control run is the first
// contribution to the total, so the baseline starts at its count rather than at zero.
var chunksBefore = control.report.chunksProcessed

for ioSizeBytes in TesterProtocol.permittedIOSizes {
    let result = performRun(ioSizeBytes: ioSizeBytes, pauseAfter: preRunWaitSeconds)
    let report = result.report

    // Differenced **before any `continue`**, so a case that bails out cannot corrupt the next
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

    let prefix = "CASE_\(mib)MIB"
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
        inconclusive += 1
        continue
    }
    // This check had become **untriggerable**: against a cumulative counter it could only read
    // zero if the control run had also done nothing, and that is already guarded above. On the
    // difference it can fail again, which is the whole point of it.
    if chunksThisCall == 0 {
        emit("\(prefix)_VERDICT=INCONCLUSIVE_PAUSE_BEFORE_FIRST_CHUNK")
        inconclusive += 1
        continue
    }
    guard report.outcomeCode == RunOutcomeCode.pausedByUser.rawValue else {
        emit("\(prefix)_VERDICT=WRONG_OUTCOME")
        continue
    }

    // **The arithmetic that proves the resume point is where the run actually stopped**, rather
    // than merely a plausible-looking block number. Every chunk before the settle was a full
    // `ioSizeBytes`, so the resume point must be exactly that many bytes past this call's start.
    //
    // `chunksThisCall`, never `report.chunksProcessed` — see the note above the loop.
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
        settled += 1
    } else {
        emit("\(prefix)_VERDICT=RESUME_POINT_WRONG")
    }
}

emit("")
emit("SETTLED_CASES=\(settled)")
emit("INCONCLUSIVE_CASES=\(inconclusive)")
emit("TOTAL_CASES=\(TesterProtocol.permittedIOSizes.count)")

// Leave the daemon as it was found. A stale `pause` could only make a later run do less, but
// leaving one behind would be leaving an instrument's residue in the product's state.
setControl(.proceed)

emit("PROBE_RESULT=\(settled == TesterProtocol.permittedIOSizes.count ? "OK" : "INCOMPLETE")")
releaseAndExit(settled == TesterProtocol.permittedIOSizes.count ? 0 : 1)
