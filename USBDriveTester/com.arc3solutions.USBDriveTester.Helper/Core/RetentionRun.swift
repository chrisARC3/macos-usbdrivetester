//
//  RetentionRun.swift
//  Core — the vocabulary of a run: what failed, what happened, and who is told about it.
//
//  Step 8 (AI-6), BUILD-PLAN 8.3/8.6/8.7/8.10/8.11. Satisfies the classification half of
//  FR-FAIL-6, the bounded-accumulation half of NFR-PERF-2, and gives NFR-REL-5 something to
//  terminate cleanly *into*. The cycle itself lives in `RetentionTestEngine`; this file is
//  everything the cycle reports with, kept separate so a safety-relevant vocabulary is not
//  buried inside a loop.
//
//  Pure Foundation, no privilege, no `os_log` — see "Why Core does not log" below.
//
//  ## Three things that fail, and only two of them are the drive's fault
//
//  | What happened | Reported as | Whose fault |
//  |---|---|---|
//  | `pread` refused, or came back short | ``BlockFailureKind/readError`` | the device |
//  | `pwrite` refused, or came back short | ``BlockFailureKind/writeError`` | the device |
//  | The re-read differs from what was written | ``BlockFailureKind/verifyMismatch`` | the device |
//  | The engine addressed a place that is not on the device | ``RunAbort`` — **not** a block failure | **us** |
//
//  That last row is the one worth being deliberate about. A `misaligned` or `outOfRange` error
//  coming back from the device layer means *this code* computed an address the device does not
//  have — the plan is wrong, or the range was never validated. Recording that as a bad block
//  would tell a user their drive is failing when the defect is ours, on a tool whose entire
//  output is a judgement about their hardware. So it aborts the run instead, loudly, and never
//  reaches the bad-block list.
//
//  ## Why Core does not log
//
//  BUILD-PLAN 8.7 requires `os_log` for run start and for each failed range (NFR-OBS-1), and
//  never the data itself (NFR-SEC-6). Core is pure by rule — Foundation only, no privilege,
//  fully testable with no hardware — so it *emits events* through ``RunObserver`` and the
//  helper's `RunCoordinator` does the logging. The alternative, an `os_log` call in the middle
//  of the cycle, would put an unloggable dependency into the one file that has to run
//  identically against the simulated device.
//
//  ## Why the failure list is bounded (NFR-PERF-2)
//
//  A plain `[BlockRangeFailure]` grows with the number of failures, which on a genuinely
//  failing multi-terabyte drive is unbounded — the same capacity-scaling growth Step 7 removed
//  from the chunk plan, arriving by a different door. ``FailureLog`` coalesces contiguous
//  same-kind ranges as they arrive and caps what it retains, carrying the dropped count
//  separately so a truncated list **says** it was truncated. A list that quietly stops growing
//  reads exactly like a complete one.
//

import Foundation

// MARK: - What kind of failure

/// The three ways a block range can fail (FR-FAIL-6).
///
/// Deliberately three cases and not a `Bool`-plus-detail: FR-FAIL-6 requires hard I/O failures
/// and verify mismatches to be *classified*, not merely counted, and Step 10's report presents
/// them differently — a read error means the drive could not produce the data at all, while a
/// verify mismatch means it accepted a write and gave back something else.
public enum BlockFailureKind: Equatable, CustomStringConvertible {

    /// The original read failed, so the chunk was never written. The device's data at this
    /// range is untouched — see ``LoadedChunk``.
    case readError

    /// The write-back failed. Nothing was verified, because verifying after a failed write
    /// compares against the *old* data and reports a mismatch that did not happen.
    case writeError

    /// The write reported success and the re-read differs from what was written
    /// (NFR-REL-8, FR-TEST-8). Any single-bit difference counts.
    case verifyMismatch

    public var description: String {
        switch self {
        case .readError:      return "read error"
        case .writeError:     return "write error"
        case .verifyMismatch: return "verify mismatch"
        }
    }
}

/// A contiguous range of blocks that failed, and how.
///
/// Block units rather than bytes because that is what a user can act on and what Step 10's
/// report tabulates — a byte offset into a 1 TB device is not a thing anyone can look up.
public struct BlockRangeFailure: Equatable, CustomStringConvertible {

    /// First failing block.
    public let startBlock: UInt64

    /// How many blocks failed. Always >= 1.
    public let blockCount: UInt64

    /// What went wrong.
    public let kind: BlockFailureKind

    public init(startBlock: UInt64, blockCount: UInt64, kind: BlockFailureKind) {
        self.startBlock = startBlock
        self.blockCount = blockCount
        self.kind = kind
    }

    /// One past the last failing block.
    public var endBlock: UInt64 { startBlock + blockCount }

    /// Can `other` be merged onto the end of this range?
    ///
    /// Same kind and immediately adjacent. Different kinds are never merged even when
    /// adjacent: "blocks 100–199 failed" is useless if half of them could not be read and the
    /// other half read back wrong.
    public func adjoins(_ other: BlockRangeFailure) -> Bool {
        kind == other.kind && endBlock == other.startBlock
    }

    public var description: String {
        blockCount == 1
            ? "block \(startBlock): \(kind)"
            : "blocks \(startBlock)–\(endBlock - 1) (\(blockCount)): \(kind)"
    }
}

// MARK: - The bounded failure list

/// Every failed range a run produced — coalesced, capped, and honest about the cap.
///
/// ## How the bound is kept without losing the coalescing
///
/// One range is held **pending** at all times: the most recent one, whether or not it was
/// retained. A new failure that adjoins the pending range extends it in place and costs
/// nothing. A new failure that does not adjoin it closes the pending range off — appending it
/// if there is room, counting it as dropped if there is not — and becomes the new pending
/// range. So the structure holds at most `retentionLimit + 1` ranges no matter how many
/// failures arrive, and a long contiguous run of bad blocks still collapses to one entry even
/// when it arrives after the cap was reached.
///
/// ``finish()`` closes the last pending range and must be called before the log is read.
public struct FailureLog: Equatable {

    /// How many coalesced ranges are retained in full.
    ///
    /// 1,024 is chosen to be far past useful: a report listing more than a thousand distinct,
    /// non-contiguous bad ranges has already told the reader everything they need. The number
    /// exists to bound memory, not to curate.
    public static let defaultRetentionLimit = 1_024

    /// The retained, coalesced ranges, in ascending block order.
    public private(set) var ranges: [BlockRangeFailure] = []

    /// Ranges that were coalesced away or dropped past the cap.
    public private(set) var droppedRangeCount = 0

    /// Total failing blocks seen, including any the cap dropped. Never approximate.
    public private(set) var failedBlockCount: UInt64 = 0

    /// The cap in force.
    public let retentionLimit: Int

    /// The most recent range, still open for coalescing. `nil` before the first failure and
    /// after ``finish()``.
    private var pending: BlockRangeFailure?

    public init(retentionLimit: Int = FailureLog.defaultRetentionLimit) {
        self.retentionLimit = max(1, retentionLimit)
    }

    /// Whether anything failed at all.
    public var isEmpty: Bool { failedBlockCount == 0 }

    /// Total coalesced ranges, retained plus dropped.
    public var totalRangeCount: Int { ranges.count + droppedRangeCount }

    /// Did the cap drop anything? **Must be surfaced wherever ``ranges`` is** — a truncated
    /// list that does not say so is indistinguishable from a complete one.
    public var isTruncated: Bool { droppedRangeCount > 0 }

    /// Record one failure.
    public mutating func record(_ failure: BlockRangeFailure) {
        failedBlockCount += failure.blockCount

        if let open = pending, open.adjoins(failure) {
            pending = BlockRangeFailure(startBlock: open.startBlock,
                                        blockCount: open.blockCount + failure.blockCount,
                                        kind: open.kind)
            return
        }

        close()
        pending = failure
    }

    /// Close the last pending range. Idempotent; call once the run is over.
    public mutating func finish() { close() }

    private mutating func close() {
        guard let open = pending else { return }
        if ranges.count < retentionLimit {
            ranges.append(open)
        } else {
            droppedRangeCount += 1
        }
        pending = nil
    }

    /// A one-line summary for a log line or an XPC reply, safe to show when nothing failed.
    ///
    /// Contains addressing only, never device contents (NFR-SEC-6).
    public var summaryLine: String {
        guard !isEmpty else { return "no failed block ranges" }
        let head = ranges.first.map(\.description) ?? "none retained"
        let counted = "\(failedBlockCount) block(s) in \(totalRangeCount) range(s)"
        return isTruncated
            ? "\(counted); first \(head); list truncated to \(ranges.count) retained range(s)"
            : "\(counted); first \(head)"
    }
}

// MARK: - The proof that a read succeeded

/// Bytes that were **actually read from the device**, and the only thing the write-back
/// accepts.
///
/// ## The hazard this type exists to make unrepresentable
///
/// The run owns two buffers and reuses them for every chunk (NFR-PERF-1). So if chunk *n*'s
/// original read fails and control falls through to the write, `ChunkBuffers.original` still
/// holds **chunk *n−1*'s data** — and the engine writes the previous chunk's bytes to this
/// chunk's offset. That is silent, permanent corruption of a region the tool was asked to
/// preserve, on a drive whose every other block verifies clean, and it is one missing
/// `continue` away.
///
/// A `LoadedChunk` is produced *only* by a successful read — the read either throws or returns
/// one — and the write step takes one as a parameter. There is therefore no expressible path
/// from a failed read to a write, in the same way `AcquiredDevice` makes "write with no access
/// held" unexpressible (NFR-REL-3).
///
/// - Important: never construct one to stand in for a read that did not happen.
public struct LoadedChunk: Equatable {

    /// The chunk whose original data is in buffer A.
    public let chunk: Chunk

    /// How many bytes were read — `chunk.byteLength`, and shorter than the I/O size on the
    /// final chunk of a plan (FR-TEST-5).
    public let byteCount: Int

    /// Created by the read step only.
    init(chunk: Chunk, byteCount: Int) {
        self.chunk = chunk
        self.byteCount = byteCount
    }
}

// MARK: - How the run ended

/// Why a run stopped.
///
/// Two cases now. Step 10 adds the user-selected failure modes, Step 11 adds stop-by-user, and
/// Step 12 adds device loss — each of which is a *new* way to end, not a re-reading of these.
public enum RunOutcome: Equatable, CustomStringConvertible {

    /// Every chunk in the plan was processed. Says nothing about whether they all passed —
    /// a run that found bad blocks and kept going still completes (FR-FAIL-3).
    case completed

    /// The observer answered ``FailureDisposition/stopRun`` to this failure, and no further
    /// I/O was issued (NFR-REL-5).
    case stoppedOnFailure(BlockRangeFailure)

    public var description: String {
        switch self {
        case .completed:
            return "completed"
        case .stoppedOnFailure(let failure):
            return "stopped on failure at \(failure)"
        }
    }
}

/// What the run did.
public struct RunSummary: Equatable {

    /// How it ended.
    public let outcome: RunOutcome

    /// Chunks the run attempted — including any that failed, and including the chunk a stop
    /// happened on. Equal to ``chunksPlanned`` exactly when the run reached the end.
    public let chunksProcessed: UInt64

    /// Chunks the plan contained.
    public let chunksPlanned: UInt64

    /// Bytes moved by the original reads, the write-backs, and the verify reads. Three
    /// counters rather than one, because a run that read everything and wrote nothing is a
    /// specific, diagnosable failure and a single total would hide it.
    public let bytesRead: UInt64
    public let bytesWritten: UInt64
    public let bytesVerified: UInt64

    /// Every failed range (FR-RPT-1), coalesced and bounded.
    public let failures: FailureLog

    /// The FR-TEST-9 verdict as it stood at the end — seeded at acquire, then only ever
    /// downgraded by what the run's own throughput revealed. Step 10 carries this into the
    /// exported report, where it is **mandatory** rather than conditional.
    public let cacheBypass: CacheBypassAssessment

    /// Bytes of buffer this run held — `2 x` the I/O size (NFR-PERF-1).
    ///
    /// Reported rather than inferred, because it crosses the XPC boundary and a gate should be
    /// able to assert it against a live daemon rather than trusting the source. It is exact
    /// and uncontaminated: it is what *this* run holds, not a process-global figure. An
    /// earlier draft reported `ChunkBuffers.peakAllocatedBytes` and had the engine reset it,
    /// which clobbered a concurrently-running test suite's baseline — production code must not
    /// mutate shared instrumentation.
    ///
    /// It cannot vary with device capacity, because capacity is not one of `ChunkBuffers`'
    /// inputs. The stronger claims live where they can actually fail: that a run does not
    /// *accumulate* buffers is `ChunkBuffersInstrumentationTests`, and that it holds one
    /// chunk at a time is the ordering audit.
    public let bufferBytesHeld: Int

    public init(outcome: RunOutcome,
                chunksProcessed: UInt64,
                chunksPlanned: UInt64,
                bytesRead: UInt64,
                bytesWritten: UInt64,
                bytesVerified: UInt64,
                failures: FailureLog,
                cacheBypass: CacheBypassAssessment,
                bufferBytesHeld: Int) {
        self.outcome = outcome
        self.chunksProcessed = chunksProcessed
        self.chunksPlanned = chunksPlanned
        self.bytesRead = bytesRead
        self.bytesWritten = bytesWritten
        self.bytesVerified = bytesVerified
        self.failures = failures
        self.cacheBypass = cacheBypass
        self.bufferBytesHeld = bufferBytesHeld
    }

    /// Did every planned chunk get processed?
    public var isComplete: Bool { outcome == .completed }
}

// MARK: - Aborts: our fault, not the drive's

/// A run could not proceed for a reason that is **not** a device failure.
///
/// Kept entirely separate from ``BlockRangeFailure`` because the two say opposite things to a
/// user. A block-range failure says "your drive has a problem here". A `RunAbort` says "this
/// tool asked for something impossible and stopped rather than guess". Folding the second into
/// the first would have this tool report bad blocks on a healthy drive because of a bug in its
/// own arithmetic — the worst available way to be wrong, for a tool whose whole output is a
/// judgement about somebody's hardware.
public enum RunAbort: Error, Equatable, CustomStringConvertible {

    /// The requested block range is not entirely on the device.
    case rangeNotWithinDevice(startBlock: UInt64, blockCount: UInt64, deviceBlockCount: UInt64)

    /// The I/O size is not a positive multiple of the logical block size.
    case planRejected(ChunkPlanError)

    /// The buffers are smaller than the I/O size the plan is tiled with. A chunk would not
    /// fit in the buffer it must be read into.
    case buffersTooSmall(ioSizeBytes: Int, bufferCapacityBytes: Int)

    /// The NFR-REL-3 write guard refused. This is the runtime half of "never write without
    /// exclusive access held", and it is re-checked **per chunk** — a device released
    /// mid-run must stop the very next write, not be discovered at the end.
    case writeRefused(WritePreconditionViolation)

    /// The device rejected an address the engine generated: misaligned, or past the end.
    /// The plan is wrong, or a range reached the engine unvalidated.
    case addressingFault(atByteOffset: UInt64, byteLength: Int, detail: String)

    public var description: String {
        switch self {
        case .rangeNotWithinDevice(let start, let count, let deviceBlocks):
            return "Refusing to run: blocks \(start)–\(start &+ count &- 1) are not entirely "
                 + "within this device, which has \(deviceBlocks) blocks."
        case .planRejected(let error):
            return "Refusing to run: the chunk plan was rejected (\(error))."
        case .buffersTooSmall(let ioSize, let capacity):
            return "Refusing to run: the run's buffers hold \(capacity) bytes, which is less "
                 + "than the \(ioSize)-byte I/O size the plan uses."
        case .writeRefused(let violation):
            return "Run stopped before writing: \(violation)"
        case .addressingFault(let offset, let length, let detail):
            return "Run stopped: the engine addressed \(length) bytes at offset \(offset), "
                 + "which this device refused (\(detail)). This is a fault in the test "
                 + "tool's addressing, not a fault in the drive."
        }
    }
}

// MARK: - Watching a run

/// What the engine should do after a failure.
///
/// Step 8 ships one caller, which always continues — FR-FAIL-4's default. The **modes**
/// themselves (FR-FAIL-1/2/3) are Step 10's. This exists now because without a stop path,
/// BUILD-PLAN 8.6 / NFR-REL-5 — "on stop, issue no further writes" — has nothing to test.
public enum FailureDisposition: Equatable {

    /// Record it and carry on with the next chunk (FR-FAIL-3).
    case continueRun

    /// Stop now. The engine issues no further I/O of any kind and returns a summary whose
    /// outcome names this failure (NFR-REL-5).
    case stopRun
}

/// How long each phase of one chunk's cycle took.
///
/// Measured because FR-TEST-9's falsifier needs it (see ``CacheBypassAssessment/observe(bytes:nanoseconds:)``),
/// and passed on because Step 9 builds throughput and read-latency statistics from exactly
/// these numbers. Step 8 computes **no** statistics from them: no averages, no min/max, no p99.
public struct ChunkTiming: Equatable {
    public let readNanoseconds: UInt64
    public let writeNanoseconds: UInt64
    public let verifyNanoseconds: UInt64

    public init(readNanoseconds: UInt64, writeNanoseconds: UInt64, verifyNanoseconds: UInt64) {
        self.readNanoseconds = readNanoseconds
        self.writeNanoseconds = writeNanoseconds
        self.verifyNanoseconds = verifyNanoseconds
    }
}

/// What the run is about to do, handed to the observer once, before the first chunk.
///
/// Carries addressing and configuration only — never device contents (NFR-SEC-6).
public struct RunStart: Equatable {

    /// Canonical BSD name of the device, e.g. `disk4`.
    public let deviceName: String

    /// First block of the run.
    public let startBlock: UInt64

    /// Blocks the run covers.
    public let blockCount: UInt64

    /// Fixed I/O size (FR-CTRL-8).
    public let ioSizeBytes: Int

    /// Chunks the plan contains.
    public let chunkCount: UInt64

    /// The FR-TEST-9 verdict the run starts from.
    public let cacheBypass: CacheBypassState

    public init(deviceName: String,
                startBlock: UInt64,
                blockCount: UInt64,
                ioSizeBytes: Int,
                chunkCount: UInt64,
                cacheBypass: CacheBypassState) {
        self.deviceName = deviceName
        self.startBlock = startBlock
        self.blockCount = blockCount
        self.ioSizeBytes = ioSizeBytes
        self.chunkCount = chunkCount
        self.cacheBypass = cacheBypass
    }
}

/// Receives what a run does, as it happens.
///
/// `AnyObject`-bound because both real implementations are reference types — the helper's
/// coordinator, which logs, and the tests' recorder, which asserts. Every method has a default
/// implementation so an observer states only what it cares about.
///
/// Not `Sendable`, and deliberately: a run drives one device from one task, the same contract
/// `ChunkBuffers` and `InMemoryBlockDevice` document. An observer shared across tasks would be
/// a correctness bug well before it was a data race.
public protocol RunObserver: AnyObject {

    /// Once, before the first chunk. The helper logs the run start here (BUILD-PLAN 8.7).
    func runStarted(_ start: RunStart)

    /// After each chunk's read → write → verify completes without failing.
    func chunkCompleted(_ chunk: Chunk, timing: ChunkTiming)

    /// A block range failed. The helper logs it here (BUILD-PLAN 8.7, NFR-OBS-1).
    ///
    /// - Returns: whether to keep going. Defaults to ``FailureDisposition/continueRun``, which
    ///   is FR-FAIL-4's default mode.
    func failureDetected(_ failure: BlockRangeFailure) -> FailureDisposition

    /// Once, after the last chunk or after a stop.
    func runFinished(_ summary: RunSummary)
}

public extension RunObserver {
    func runStarted(_ start: RunStart) {}
    func chunkCompleted(_ chunk: Chunk, timing: ChunkTiming) {}
    func failureDetected(_ failure: BlockRangeFailure) -> FailureDisposition { .continueRun }
    func runFinished(_ summary: RunSummary) {}
}

// MARK: - The clock

/// A source of monotonic nanoseconds. Injected so the falsifier can be tested.
public typealias MonotonicClock = () -> UInt64

/// The run's default clock.
public enum RunClock {

    /// Monotonic nanoseconds since boot.
    ///
    /// ## Why `CLOCK_MONOTONIC_RAW` and not `CLOCK_UPTIME_RAW`
    ///
    /// They differ only in whether they advance while the system is asleep — `MONOTONIC_RAW`
    /// does, `UPTIME_RAW` does not — and that difference decides which way this check is wrong
    /// when it is wrong. These durations feed FR-TEST-9's falsifier, which flags a read as
    /// host-served when it completes *faster* than the transport allows. Excluding sleep would
    /// make a read that spanned a sleep look shorter, therefore faster, therefore more likely
    /// to be flagged — a false accusation that the verify cannot be trusted. Including sleep
    /// makes such a read look slower, which the falsifier simply ignores.
    ///
    /// So the safe direction is to include it. Sleep is prevented during a run anyway
    /// (NFR-REL-9), which is precisely why the choice must not rest on that holding.
    public static func monotonicNanoseconds() -> UInt64 {
        clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
    }
}
