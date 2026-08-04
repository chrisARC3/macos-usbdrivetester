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
        case .aborted(let abort):
            return abort.description
        case .digestFailed(let detail):
            return "Cannot fingerprint the device: \(detail)"
        }
    }
}

// MARK: - Logging what a run did

/// The `RunObserver` the helper uses: it logs, and it always continues.
///
/// Continuing is FR-FAIL-4's default. The user-selectable modes — stop on first error versus
/// log and continue — are Step 10's, and this class is where the chosen mode will be wired in.
final class RunLogger: RunObserver {

    /// How many individual failures get their own log line before the log says it has stopped
    /// listing them. A drive with a million bad blocks must not produce a million log lines.
    static let loggedFailureLimit = 64

    private var loggedFailures = 0
    private var announcedTruncation = false

    func runStarted(_ start: RunStart) {
        ioLog.notice("""
                     retention cycle START on \(start.deviceName, privacy: .public): \
                     blocks \(start.startBlock, privacy: .public)–\
                     \(start.startBlock + start.blockCount - 1, privacy: .public) \
                     (\(start.blockCount, privacy: .public) blocks, \
                     \(start.chunkCount, privacy: .public) chunks of \
                     \(start.ioSizeBytes, privacy: .public) bytes); \
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
    static func runCycle(startBlock: UInt64,
                         blockCount: UInt64,
                         ioSizeBytes: Int) -> Result<RunSummary, RetentionCycleRefusal> {

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
        let observer = RunLogger()

        do {
            let summary = try engine.run(buffers: buffers,
                                         deviceName: device.device.rawValue,
                                         blockRange: startBlock ..< (startBlock + blockCount),
                                         cacheBypass: assessment,
                                         // Recomputed per chunk on purpose: a device released
                                         // mid-run must stop the very next write (NFR-REL-3).
                                         grant: { device.grant },
                                         observer: observer)
            logDeviceDiagnostics(blockDevice)
            return .success(summary)
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
