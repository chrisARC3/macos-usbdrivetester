//
//  RunCoordinator.swift
//  Helper — everything between "a device is held" and "the pure cycle runs".
//
//  Step 8 (AI-6), BUILD-PLAN 8.7/8.9. This is the only place in the project where a write to a
//  real drive is initiated, and it is deliberately small: validate the request, allocate the
//  two buffers, seed FR-TEST-9's assessment from what the acquire established, run the pure
//  engine, log what happened. Every decision that could be made in `Core/` already was.
//
//  ## Why the logging lives here and not in the engine
//
//  BUILD-PLAN 8.7 requires `os_log` for the run start and for each failed block range
//  (NFR-OBS-1), and never the data itself (NFR-SEC-6). `Core/` is pure by rule — Foundation
//  only, no privilege, no `os_log` — so the engine emits events through `RunObserver` and this
//  file is the observer. That keeps the one file that must run identically against the
//  simulated device free of anything that cannot run there.
//
//  ## What is logged, and what is not
//
//  Block numbers and lengths: yes. They are addressing, they are what a user needs to act on,
//  and NFR-OBS-2 requires a failed run to be diagnosable after the fact. Device **contents**:
//  never, in any form, at any level (NFR-SEC-6).
//
//  Per-chunk progress is *not* logged. A 1 GiB run is 256 chunks and a whole-device run would
//  be a quarter of a million; logging each would be noise in the log and per-chunk overhead in
//  the cycle (NFR-PERF-3). Failures are logged individually up to
//  ``RunLogger/loggedFailureLimit``, after which the log says it has stopped listing them —
//  the same rule as `FailureLog`'s cap, for the same reason: a list that quietly stops growing
//  reads exactly like a complete one.
//

import Foundation
import os

private let ioLog = Logger(subsystem: HelperIdentity.loggingSubsystem, category: "io")

/// Step 9's category (NFR-OBS-1), the last of the six `HelperIdentity` names. One predicate
/// shows a run's measured figures without the I/O chatter:
/// `log show --predicate 'subsystem == "com.arc3solutions.USBDriveTester" and category == "metrics"'`.
private let metricsLog = Logger(subsystem: HelperIdentity.loggingSubsystem, category: "metrics")

// MARK: - Why a cycle was refused

/// Why the helper would not run the requested cycle.
///
/// Every one of these is decided **before** a single byte is read or written. `CustomStringConvertible`
/// because the strings cross the XPC boundary and are shown verbatim (NFR-USE-5).
enum RetentionCycleRefusal: Error, Equatable, CustomStringConvertible {

    /// No device is held. `acquireDevice` is what proves nothing is mounted and that
    /// exclusive access was taken; without it there is no permission to write anything
    /// (NFR-REL-3).
    case noDeviceHeld

    /// The device is already in use — a cycle, or a fingerprint. Refused rather than queued:
    /// the helper has one set of buffers, one descriptor, and no run-control state machine
    /// until Step 11.
    case deviceBusy(deviceName: String, operation: String)

    /// The I/O size is not one of FR-CTRL-8's.
    case ioSizeNotPermitted(ioSizeBytes: Int)

    /// The request covers more than ``TesterProtocol/maximumBytesPerCall``.
    case requestTooLarge(requestedBytes: UInt64, maximumBytes: UInt64)

    /// A zero-block request. Not an error the caller can act on, but not something to answer
    /// with a cheerful "completed" either.
    case emptyRequest

    /// The held device could not vend a block device — it was released between the check and
    /// the run.
    case deviceUnavailable(detail: String)

    /// The buffers could not be allocated.
    case buffersUnavailable(ChunkBufferError)

    /// The run would not begin on a 1 MiB boundary, or would cover a partial one without
    /// reaching the end of the device (FR-TEST-10).
    case placementRefused(RunPlacementRejection)

    /// The engine refused or stopped for a reason that is **this tool's** fault, not the
    /// drive's — see ``RunAbort``.
    case aborted(RunAbort)

    /// A fingerprint could not be taken.
    case digestFailed(detail: String)

    var description: String {
        switch self {
        case .noDeviceHeld:
            return "Cannot run: no device is held. Acquire the device first — that is what "
                 + "establishes that nothing is mounted and that exclusive access was taken."
        case .deviceBusy(let name, let operation):
            return "Cannot start: \(operation) is already in progress on \(name). Wait for it "
                 + "to finish."
        case .ioSizeNotPermitted(let size):
            let allowed = TesterProtocol.permittedIOSizes
                .map { "\($0 / (1 << 20)) MiB" }
                .joined(separator: ", ")
            return "Cannot run: \(size) bytes is not a permitted I/O size. Allowed: \(allowed)."
        case .requestTooLarge(let requested, let maximum):
            return "Cannot run: the request covers \(requested) bytes, more than the "
                 + "\(maximum)-byte maximum for one call. A run cannot be cancelled yet, so a "
                 + "single call is bounded to what the daemon can finish promptly."
        case .emptyRequest:
            return "Cannot run: the requested range covers no blocks."
        case .deviceUnavailable(let detail):
            return "Cannot run: the held device is no longer usable (\(detail))."
        case .buffersUnavailable(let error):
            return "Cannot run: \(error)"
        case .placementRefused(let rejection):
            return rejection.description
        case .aborted(let abort):
            return abort.description
        case .digestFailed(let detail):
            return "Cannot fingerprint the device: \(detail)"
        }
    }
}

// MARK: - Logging what a run did

/// The `RunObserver` the helper uses: it logs, and it never decides.
///
/// ## Where the mode is, and why it is not here (Step 10, 2026-08-06)
///
/// An earlier note on this class said it was "where the chosen mode will be wired in". It is
/// not. `Core/FailureModeObserver` obeys the mode and this class only **prints** it, for two
/// reasons recorded there: a decision that governs whether a run keeps writing to a failing
/// drive must live where a test can reach it — the test target compiles `Core/` and nothing else
/// from the helper — and it must not sit inside this method's counter-and-limit bookkeeping,
/// where a `return` on the wrong side of an `if` would answer "carry on" to a run that was asked
/// to stop.
///
/// So ``failureDetected(_:)`` below still returns ``FailureDisposition/continueRun`` — not as a
/// policy, but as the neutral answer of an observer that only watches. `ObserverFanOut`'s
/// stop-wins rule is what makes that safe.
///
/// The mode is held here **only** to name it in the run-start line (BUILD-PLAN 10.6,
/// NFR-OBS-1). Both this and the deciding observer are constructed from one value on one line in
/// ``RunCoordinator/runCycle(startBlock:blockCount:ioSizeBytes:failureMode:)``, so the mode that
/// is logged is the mode that ran.
final class RunLogger: RunObserver {

    /// How many individual failures get their own log line before the log says it has stopped
    /// listing them. A drive with a million bad blocks must not produce a million log lines.
    static let loggedFailureLimit = 64

    private let failureMode: FailureMode
    private var loggedFailures = 0
    private var announcedTruncation = false

    init(failureMode: FailureMode) {
        self.failureMode = failureMode
    }

    func runStarted(_ start: RunStart) {
        ioLog.notice("""
                     retention cycle START on \(start.deviceName, privacy: .public): \
                     blocks \(start.startBlock, privacy: .public)–\
                     \(start.startBlock + start.blockCount - 1, privacy: .public) \
                     (\(start.blockCount, privacy: .public) blocks, \
                     \(start.chunkCount, privacy: .public) chunks of \
                     \(start.ioSizeBytes, privacy: .public) bytes); \
                     failure mode: \(self.failureMode.reportName, privacy: .public); \
                     cache-bypass verdict at acquire: \(start.cacheBypass.description, privacy: .public)
                     """)
    }

    func failureDetected(_ failure: BlockRangeFailure) -> FailureDisposition {
        if loggedFailures < Self.loggedFailureLimit {
            loggedFailures += 1
            ioLog.error("""
                        retention cycle FAILURE: \(failure.description, privacy: .public)
                        """)
        } else if !announcedTruncation {
            announcedTruncation = true
            ioLog.error("""
                        retention cycle: more than \(Self.loggedFailureLimit, privacy: .public) \
                        failed ranges; individual ranges are no longer being logged. The run \
                        report carries the full list.
                        """)
        }
        // The neutral answer of an observer that only watches — **not** the log-and-continue
        // mode. `FailureModeObserver` decides; see this class's note. Under `ObserverFanOut`'s
        // stop-wins rule this can never override a decision to stop.
        return .continueRun
    }

    func runFinished(_ summary: RunSummary) {
        ioLog.notice("""
                     retention cycle END: \(summary.outcome.description, privacy: .public); \
                     \(summary.chunksProcessed, privacy: .public)/\
                     \(summary.chunksPlanned, privacy: .public) chunks; \
                     read \(summary.bytesRead, privacy: .public) B, \
                     wrote \(summary.bytesWritten, privacy: .public) B, \
                     verified \(summary.bytesVerified, privacy: .public) B; \
                     \(summary.failures.summaryLine, privacy: .public); \
                     cache bypass: \(summary.cacheBypass.state.description, privacy: .public); \
                     buffers held \(summary.bufferBytesHeld, privacy: .public) B
                     """)
    }
}

// MARK: - Running one

enum RunCoordinator {

    /// Run the cycle over `startBlock ..< startBlock + blockCount` of the held device.
    ///
    /// Validation happens in the order that refuses soonest and most specifically. Nothing is
    /// read or written until every check has passed — which matters more here than anywhere
    /// else in the project, because the next thing that happens is a write to somebody's
    /// drive.
    /// What a cycle produced, plus the two figures NFR-PERF-3 asks for.
    ///
    /// A separate type rather than more `RunSummary` fields: the summary is Core's, and CPU
    /// consumption is a fact about *this process* that a pure algorithm has no business knowing.
    struct CycleResult {
        let summary: RunSummary

        /// Host work as a fraction of device I/O time, measured inside the cycle's own loop.
        /// `nil` when no I/O was timed.
        let hostOverheadFraction: Double?

        /// The daemon's CPU over the run, as a fraction of one core (BUILD-PLAN 9.5a).
        /// `nil` when it could not be established — never `0`, which means something else.
        let helperCoreFraction: Double?

        /// **This run's** final figures (FR-RPT-2/3), read from the observer this call installed
        /// rather than from `MetricsChannel.shared` (Step 10, protocol v9).
        ///
        /// The distinction is the whole reason these travel in the cycle's reply. `begin()`
        /// replaces the shared slot when a run *starts*, which is after validation — so on a
        /// **refused** run the slot still holds the *previous* run's figures. A caller that
        /// polled `runProgress` once the reply arrived would get them, correctly formatted, and
        /// put them in a report that outlives the session. Reading the local observer means a
        /// refused run has no figures at all, which is the true answer.
        ///
        /// `nil` before the run's first event — a run refused before it started, or one that
        /// never measured a chunk.
        let metrics: MetricsSnapshot?

        /// The mode this run was actually performed in.
        ///
        /// Reported rather than assumed by the caller: `RunCoordinator` is not in the test
        /// target, so nothing in the unit suite can show that the deciding observer was
        /// installed, and a healthy drive produces no failure that would reveal its absence.
        let failureMode: FailureMode
    }

    /// - Parameter failureMode: FR-FAIL-1's mode, chosen before the run. It is **not** defaulted
    ///   here: the caller states it, and an unrecognised code arriving over XPC is refused at the
    ///   boundary rather than resolved to FR-FAIL-4's default (see `FailureModeCode`). A
    ///   parameter with a default value would make "nobody chose" and "somebody chose
    ///   log-and-continue" the same call.
    static func runCycle(startBlock: UInt64,
                         blockCount: UInt64,
                         ioSizeBytes: Int,
                         failureMode: FailureMode) -> Result<CycleResult, RetentionCycleRefusal> {

        // 1. The request itself, before anything is claimed or allocated (NFR-REL-7).
        guard blockCount > 0 else { return .failure(.emptyRequest) }

        guard TesterProtocol.permittedIOSizes.contains(ioSizeBytes) else {
            return .failure(.ioSizeNotPermitted(ioSizeBytes: ioSizeBytes))
        }

        // 2. Take the run slot. This is also what stops a second caller starting a concurrent
        //    cycle on the same descriptor, and what makes `prepareForShutdown` refuse while a
        //    run is in progress (NFR-INST-3, NFR-REL-5).
        let device: AcquiredDevice
        switch HelperActivity.shared.beginDeviceOperation("a retention cycle is writing") {
        case .started(let acquired):
            device = acquired
        case .refused(let refusal):
            return .failure(refusal)
        }
        defer { HelperActivity.shared.endDeviceOperation() }

        // 3. The size cap, which needs the device's block size to evaluate. Checked after the
        //    run slot only because the geometry lives on the held device.
        let geometry = device.deviceGeometry
        let requestedBytes = blockCount * UInt64(geometry.logicalBlockSize)
        guard requestedBytes <= TesterProtocol.maximumBytesPerCall else {
            return .failure(.requestTooLarge(requestedBytes: requestedBytes,
                                             maximumBytes: TesterProtocol.maximumBytesPerCall))
        }

        // 3a. FR-TEST-10, against the AUTHORITATIVE ioctl geometry rather than anything the
        //     caller asserted (NFR-REL-7). Making a misaligned start unexpressible in the GUI is
        //     right but not sufficient: the CLI gate clients are callers too, as is anything
        //     signed under the Team ID.
        //
        //     A misaligned start makes the device read-modify-write internally, which lowers
        //     measured throughput — and throughput here is a wear heuristic the user judges
        //     (decision 2026-08-04). Accepting one would manufacture the exact signal the
        //     measurement exists to detect.
        do {
            try RunPlacement.validate(startBlock: startBlock,
                                      blockCount: blockCount,
                                      geometry: geometry)
        } catch let rejection as RunPlacementRejection {
            return .failure(.placementRefused(rejection))
        } catch {
            return .failure(.placementRefused(
                .startNotOnBoundary(startBlock: startBlock,
                                    byteOffset: startBlock * UInt64(geometry.logicalBlockSize))))
        }

        // 4. The block device over the held descriptor, using the AUTHORITATIVE ioctl geometry
        //    (BUILD-PLAN 7.3) — never IOKit's, and never anything the caller supplied.
        let blockDevice: FileDescriptorBlockDevice
        do {
            guard let vended = try device.blockDevice() else {
                return .failure(.deviceUnavailable(detail: "the device has been released"))
            }
            blockDevice = vended
        } catch {
            return .failure(.deviceUnavailable(detail: "\(error)"))
        }

        // 5. The two buffers, allocated once for the whole run (NFR-PERF-1).
        let buffers: ChunkBuffers
        do {
            buffers = try ChunkBuffers(ioSizeBytes: ioSizeBytes)
        } catch let error as ChunkBufferError {
            return .failure(.buffersUnavailable(error))
        } catch {
            return .failure(.buffersUnavailable(.allocationFailed(bytesRequested: ioSizeBytes,
                                                                  errnoCode: 0)))
        }

        // 6. FR-TEST-9, seeded from what the acquire established — *not* re-checked here.
        //    The check is `fstat` plus the two `fcntl` results on the descriptor, taken when
        //    it was opened; re-opening the node to ask again is what makes DiskArbitration
        //    remount the volume ~4 ms later (measured 2026-08-01). The descriptor has been
        //    held continuously since, so the verdict still describes it.
        let assessment = CacheBypassAssessment(device.uncachedIO, linkSpeed: device.usbLinkSpeed)

        let engine = RetentionTestEngine(device: blockDevice, ioSizeBytes: ioSizeBytes)

        // 7. Three observers, fanned out: one logs (NFR-OBS-1), one obeys the failure mode
        //    (FR-FAIL-1/2/3), one accumulates metrics (FR-METR-*). Composed rather than chained,
        //    so none has to remember to forward events to the others — the same forget-a-method
        //    hazard that made Step 8's `chunkCompleted` skip every failing chunk.
        //
        //    **The composition is `RunObservers.forRun`, not an array literal here**, and that is
        //    deliberate: this file is not in the test target, and the two watchers below both
        //    answer a failure with the neutral `.continueRun`. An edit that dropped the deciding
        //    observer from a hand-written array would turn FR-FAIL-2 into FR-FAIL-3 on real
        //    hardware with no test failing anywhere. Core owns the assembly so the assembly is
        //    tested; what is left here is one call.
        //
        //    `RunLogger` takes the same `failureMode` value on the same line — one prints the
        //    mode, the other obeys it, so the mode in the log is necessarily the mode that ran.
        //
        //    Installing the metrics observer in `MetricsChannel` is what makes `runProgress`
        //    able to find it from a *different connection*, which it must: a second message on
        //    this connection will not be delivered until this call returns (measured
        //    2026-08-04, scripts/xpc-concurrency-check.sh).
        let metrics = MetricsChannel.shared.begin()
        let observer = RunObservers.forRun(mode: failureMode,
                                           watchedBy: [RunLogger(failureMode: failureMode),
                                                       metrics])

        // NFR-PERF-3's CPU figure brackets only the cycle. Reading `getrusage` costs one
        // syscall, twice per run — not per chunk.
        let cpuBefore = HelperCPUSample.processCPUSeconds()
        let wallBefore = RunClock.monotonicNanoseconds()

        func perfFigures(_ summary: RunSummary) -> (Double?, Double?) {
            let wallSeconds = Double(RunClock.monotonicNanoseconds() &- wallBefore) / 1_000_000_000
            let core = HelperCPUSample.coreFraction(from: cpuBefore,
                                                    to: HelperCPUSample.processCPUSeconds(),
                                                    wallSeconds: wallSeconds)
            return (metrics.snapshot?.hostOverheadFraction, core)
        }

        do {
            let summary = try engine.run(buffers: buffers,
                                         deviceName: device.device.rawValue,
                                         blockRange: startBlock ..< (startBlock + blockCount),
                                         cacheBypass: assessment,
                                         // Recomputed per chunk on purpose: a device released
                                         // mid-run must stop the very next write (NFR-REL-3).
                                         grant: { device.grant },
                                         // Read per chunk for the same reason, and from the
                                         // process-wide slot rather than a captured value: the
                                         // pause arrives on a *different connection* while this
                                         // call is blocking this one (measured 2026-08-04).
                                         control: { RunControlChannel.shared.current },
                                         observer: observer)
            logDeviceDiagnostics(blockDevice)

            let (overhead, core) = perfFigures(summary)
            logPerformance(summary, overheadFraction: overhead, coreFraction: core)
            return .success(CycleResult(summary: summary,
                                        hostOverheadFraction: overhead,
                                        helperCoreFraction: core,
                                        // The observer this call installed, not the shared slot.
                                        metrics: metrics.snapshot,
                                        failureMode: failureMode))
        } catch let abort as RunAbort {
            ioLog.error("""
                        retention cycle ABORTED on \(device.device.rawValue, privacy: .public): \
                        \(abort.description, privacy: .public)
                        """)
            logDeviceDiagnostics(blockDevice)
            return .failure(.aborted(abort))
        } catch {
            // `run` throws only `RunAbort`. Reported rather than trapped — a root daemon
            // holding a claim must not crash, or the disk stays claimed until launchd
            // restarts it.
            ioLog.error("""
                        retention cycle ABORTED on \(device.device.rawValue, privacy: .public) \
                        with an unexpected error: \(String(describing: error), privacy: .public)
                        """)
            return .failure(.aborted(.addressingFault(atByteOffset: 0, byteLength: 0,
                                                      detail: String(describing: error))))
        }
    }

    /// SHA-256 of a bounded range of the held device (Step 8, gate item 5).
    ///
    /// Read-only, and it takes the same device-operation slot a cycle does — one descriptor,
    /// used by one thing at a time. Fingerprinting a region while the cycle is writing it would
    /// produce a fingerprint of neither the before state nor the after one.
    ///
    /// The digest itself is `Core/DeviceDigest`, unit-tested against known SHA-256 vectors.
    /// That matters more here than it looks: the gate compares a fingerprint **this process**
    /// took before a cycle against one it took after, so a digest function that returned a
    /// constant would make the comparison pass unconditionally — a check that cannot fail.
    static func digestRange(startBlock: UInt64,
                            blockCount: UInt64) -> Result<(bytes: UInt64, hex: String),
                                                          RetentionCycleRefusal> {

        guard blockCount > 0 else { return .failure(.emptyRequest) }

        let device: AcquiredDevice
        switch HelperActivity.shared.beginDeviceOperation("a fingerprint is being taken") {
        case .started(let acquired):
            device = acquired
        case .refused(let refusal):
            return .failure(refusal)
        }
        defer { HelperActivity.shared.endDeviceOperation() }

        let geometry = device.deviceGeometry
        let requestedBytes = blockCount * UInt64(geometry.logicalBlockSize)
        guard requestedBytes <= TesterProtocol.maximumBytesPerCall else {
            return .failure(.requestTooLarge(requestedBytes: requestedBytes,
                                             maximumBytes: TesterProtocol.maximumBytesPerCall))
        }

        let blockDevice: FileDescriptorBlockDevice
        do {
            guard let vended = try device.blockDevice() else {
                return .failure(.deviceUnavailable(detail: "the device has been released"))
            }
            blockDevice = vended
        } catch {
            return .failure(.deviceUnavailable(detail: "\(error)"))
        }

        do {
            let hex = try DeviceDigest.sha256(of: blockDevice,
                                              startBlock: startBlock,
                                              blockCount: blockCount)
            return .success((bytes: requestedBytes, hex: hex))
        } catch let failure as DeviceDigest.Failure {
            ioLog.error("""
                        digest FAILED on \(device.device.rawValue, privacy: .public): \
                        \(failure.description, privacy: .public)
                        """)
            logDeviceDiagnostics(blockDevice)
            return .failure(.digestFailed(detail: failure.description))
        } catch {
            return .failure(.digestFailed(detail: String(describing: error)))
        }
    }

    /// Log the run's measured figures under the `metrics` category (NFR-OBS-1).
    ///
    /// Once per run, not per chunk. Addressing and timing only — never device contents
    /// (NFR-SEC-6) — and **no verdict**: throughput is reported for the user to judge against
    /// the manufacturer's advertised figure and the negotiated link speed, not graded by this
    /// tool (user decision 2026-08-04).
    private static func logPerformance(_ summary: RunSummary,
                                       overheadFraction: Double?,
                                       coreFraction: Double?) {
        guard let snapshot = MetricsChannel.shared.snapshot else { return }

        func rate(_ bytesPerSecond: Double?) -> String {
            guard let bytesPerSecond else { return "not measured" }
            return String(format: "%.1f MB/s", bytesPerSecond / 1_000_000)
        }
        func percent(_ fraction: Double?) -> String {
            guard let fraction else { return "not measured" }
            return String(format: "%.3f%%", fraction * 100)
        }
        func milliseconds(_ nanoseconds: UInt64?) -> String {
            guard let nanoseconds else { return "n/a" }
            return String(format: "%.3f ms", Double(nanoseconds) / 1_000_000)
        }

        metricsLog.notice("""
                          run metrics: read \(rate(snapshot.readBytesPerSecond), privacy: .public), \
                          write \(rate(snapshot.writeBytesPerSecond), privacy: .public), \
                          covering \(rate(snapshot.coverageBytesPerSecond), privacy: .public); \
                          read latency min \(milliseconds(snapshot.readLatency.minimumNanoseconds), privacy: .public) \
                          max \(milliseconds(snapshot.readLatency.maximumNanoseconds), privacy: .public) \
                          p99 <= \(milliseconds(snapshot.readLatency.p99?.upperBoundNanoseconds), privacy: .public) \
                          over \(snapshot.readLatency.count, privacy: .public) reads; \
                          host overhead \(percent(overheadFraction), privacy: .public) of device I/O time; \
                          daemon CPU \(percent(coreFraction), privacy: .public) of one core; \
                          unaccounted \(milliseconds(snapshot.unaccountedNanoseconds), privacy: .public); \
                          \(summary.chunksProcessed, privacy: .public) chunks
                          """)
    }

    /// The `errno`-level detail of the last I/O failure, which `DeviceIOError` deliberately
    /// does not carry.
    ///
    /// The engine has no use for an `errno` — it classifies a chunk as failed and moves on —
    /// but "the read failed" and nothing else is the kind of message that sent someone to
    /// check a cable when the answer was a checkbox (NFR-INST-4, NFR-USE-5). Addressing only,
    /// never contents.
    private static func logDeviceDiagnostics(_ device: FileDescriptorBlockDevice) {
        guard let failure = device.lastFailure else { return }
        ioLog.error("""
                    retention cycle, last device-level failure: \
                    \(failure.description, privacy: .public)
                    """)
    }
}
