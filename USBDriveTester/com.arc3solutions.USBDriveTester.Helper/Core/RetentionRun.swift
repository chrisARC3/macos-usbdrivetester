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

    /// - Important: duplicated by `FailedBlockRangeKind` in `Shared/TesterControl.swift`, the
    ///   same arrangement as ``CacheBypassState/wireCode`` and `DeviceAccessRefusal.causeCode`:
    ///   Core compiles into the helper and the test target but deliberately **not** into the app
    ///   module, so the wire needs its own mirror.
    ///
    ///   This exists rather than a `switch` at the helper's reply site because a mapping written
    ///   there would be **untestable** — `main.swift` is not in the test target — and a
    ///   transposition (a read error travelling as a write error) would compile, run, and put a
    ///   wrong classification in a report somebody may act on by discarding a drive.
    ///   `FailedRangeCodingTests.kindCodesMatchCoresClassification` is the only place both types
    ///   are visible at once, and it pins the codes and the names together.
    public var wireCode: Int {
        switch self {
        case .readError:      return 1
        case .writeError:     return 2
        case .verifyMismatch: return 3
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
/// Four cases. Step 11 added the two interruptions; Step 12 adds device loss — which is a *new*
/// way to end, not a re-reading of these.
///
/// The two interruptions carry the block the run was **about to process**, not the last one it
/// finished. That is the block a resume starts from, and stating it as the resume point rather
/// than as "where we got to" removes an off-by-one from the one arithmetic that must not have one.
public enum RunOutcome: Equatable, CustomStringConvertible {

    /// Every chunk in the plan was processed. Says nothing about whether they all passed —
    /// a run that found bad blocks and kept going still completes (FR-FAIL-3).
    case completed

    /// The observer answered ``FailureDisposition/stopRun`` to this failure, and no further
    /// I/O was issued (NFR-REL-5).
    case stoppedOnFailure(BlockRangeFailure)

    /// **FR-CTRL-2, NFR-REL-10.** The user paused, and the run settled at a chunk boundary with
    /// no write in flight. The previous chunk's full read → write-back → verify is complete;
    /// `atBlock` has not been touched.
    ///
    /// This is the only outcome a run may be **resumed** from (FR-CTRL-3), and the resume is
    /// in-session — not FR-FAIL-7's prohibited cross-interruption resume.
    case pausedByUser(atBlock: UInt64)

    /// **FR-CTRL-4.** The user stopped the run. Same settling guarantee as ``pausedByUser``, and
    /// the same block, but the run is over: a stopped run cannot be continued, and testing the
    /// drive would have to start again from the beginning.
    case stoppedByUser(atBlock: UInt64)

    public var description: String {
        switch self {
        case .completed:
            return "completed"
        case .stoppedOnFailure(let failure):
            return "stopped on failure at \(failure)"
        case .pausedByUser(let block):
            return "paused by the user at block \(block)"
        case .stoppedByUser(let block):
            return "stopped by the user at block \(block)"
        }
    }

    /// The block a resume would start from, or `nil` for an outcome that cannot be resumed.
    ///
    /// `nil` for ``stoppedByUser`` as well as for the two natural endings, and that is the point:
    /// FR-FAIL-7 forbids resuming a run that was stopped, so the value that would let somebody do
    /// it does not exist rather than existing and being ignored.
    public var resumeBlock: UInt64? {
        if case .pausedByUser(let block) = self { return block }
        return nil
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
/// Step 8 shipped one caller, which always continued — FR-FAIL-4's default. Step 10 adds the
/// **modes** (FR-FAIL-1/2/3) that decide this; see ``FailureMode``. This existed before them
/// because without a stop path, BUILD-PLAN 8.6 / NFR-REL-5 — "on stop, issue no further
/// writes" — had nothing to test.
public enum FailureDisposition: Equatable {

    /// Record it and carry on with the next chunk (FR-FAIL-3).
    case continueRun

    /// Stop now. The engine issues no further I/O of any kind and returns a summary whose
    /// outcome names this failure (NFR-REL-5).
    case stopRun
}

// MARK: - Run control (FR-CTRL-2/3/4, NFR-REL-10)

/// What the app currently wants the run in flight to do.
///
/// ## Why the engine asks rather than being told
///
/// Measured 2026-08-04: while the helper is inside a blocking privileged call, **a second message
/// on that same connection is not delivered until the call returns.** So a pause cannot arrive as
/// a message to the code that is running — it has to be *left somewhere the run will look*. The
/// app sets it over a second connection; the engine reads it at each chunk boundary.
///
/// Expressed as a closure the engine calls, not a value it is given, for exactly the reason
/// `grant` is: a value captured once would be the answer as it stood when the run started, and the
/// whole point is that it changes underneath a call that is already in flight.
///
/// ## Two cases and no third
///
/// There is deliberately no `resume` and no `unrecognised`.
///
/// **No `resume`,** because this is a *level*, not an edge: it says what the app wants now. Resume
/// is the app setting ``proceed`` again. An edge-triggered control would have to be delivered while
/// the run was looking, and the whole reason this type exists is that messages cannot be delivered
/// to a blocked connection.
///
/// **No `unrecognised`,** for the same reason ``FailureMode`` has none: this side of the boundary
/// is inside the helper, where a signal that cannot be read is not a state a run can be in. An
/// unrecognised code arriving over XPC is *refused* at the boundary, which is where the case for it
/// lives.
///
/// ## The safe direction, stated because it is what makes a stale value harmless
///
/// The helper never clears this by itself — the app owns the state (BUILD-PLAN Step 11: *"state
/// owned GUI-side"*) and sets ``proceed`` before every run and on every resume. A stale ``pause``
/// or ``stop`` can therefore only make a run do **less** than asked, never more, and the run it
/// would shorten has not started. That asymmetry is what makes an app-owned level safe here where
/// an app-owned *permission* would not be.
public enum RunControlSignal: Equatable {

    /// Carry on. The ordinary value, and what a run with no control surface always reads.
    case proceed

    /// **FR-CTRL-2.** Settle at the next chunk boundary and return, saying where to resume.
    case pause

    /// **FR-CTRL-4.** Settle at the next chunk boundary and end the run.
    case stop
}

/// Ready-made control closures.
public enum RunControl {

    /// A run nothing can interrupt.
    ///
    /// Named rather than written as `{ .proceed }` at each call site so that "this run has no
    /// control surface" is a **statement** in the source rather than a literal that reads like
    /// boilerplate. Every test that does not exercise pause says so in one word, and a reader can
    /// grep for the ones that do.
    public static let uninterrupted: () -> RunControlSignal = { .proceed }
}

// MARK: - The two modes (FR-FAIL-1)

/// How a run reacts to a failed block range — chosen **before** the run starts (FR-FAIL-1).
///
/// Two cases and no third. There is deliberately no "unknown" or "unset" member: a run that
/// does not know its mode must not start, and the place that refuses is the trust boundary,
/// where an unrecognised wire code is rejected the same way an unpermitted I/O size is
/// (NFR-REL-7). Giving this type an unrecognised case would let one travel inward and be
/// resolved by a `default:` somewhere — silently, into whichever mode the author of that
/// `switch` happened to write first.
///
/// ## Why the disposition takes the failure's kind
///
/// FR-FAIL-2 says stop on "any I/O failure", and FR-TEST-8 plus FR-FAIL-6 make a verify
/// mismatch a block-range failure too. **All three kinds therefore stop**, and taking the kind
/// here is what lets a test assert that per kind rather than leaving the conjunction of two
/// requirements implicit in a constant. The parameter is not a hint that the kinds differ
/// today — they do not — it is the place a difference would have to be written down, and the
/// place a test can prove there isn't one.
public enum FailureMode: Equatable, CaseIterable, CustomStringConvertible {

    /// **Stop on first error** (FR-FAIL-2): halt immediately on the first failed range. The
    /// engine issues no further I/O, and the run's outcome names the offending range.
    ///
    /// There is no resume (FR-FAIL-7) — a run halted this way is restarted from the beginning.
    case stopOnFirstError

    /// **Log and continue** (FR-FAIL-3): record the range and keep refreshing the rest of the
    /// device. The default (FR-FAIL-4).
    case logAndContinue

    /// FR-FAIL-4's default, stated once so nothing has to remember which it is.
    public static let standard = FailureMode.logAndContinue

    /// What the engine should do about `kind` in this mode.
    public func disposition(for kind: BlockFailureKind) -> FailureDisposition {
        switch self {
        case .logAndContinue:
            return .continueRun
        case .stopOnFirstError:
            // Every kind, including `verifyMismatch`: FR-FAIL-2's "any I/O failure" read
            // together with FR-TEST-8, which makes a mismatched chunk a failed range. A drive
            // that accepts a write and hands back something else has failed at the one thing
            // this tool is checking.
            switch kind {
            case .readError, .writeError, .verifyMismatch:
                return .stopRun
            }
        }
    }

    /// How the mode is named in the exported report and in the log (FR-RPT, NFR-OBS-1).
    ///
    /// Wording matched to FR-FAIL-1's own, because the report is read by someone who may go
    /// looking for the control that produced it.
    public var reportName: String {
        switch self {
        case .stopOnFirstError: return "Stop on first error"
        case .logAndContinue:   return "Log and continue"
        }
    }

    /// - Important: duplicated by `FailureModeCode` in `Shared/TesterControl.swift`, for the
    ///   same reason `DeviceAccessRefusal.causeCode` is: Core compiles into the helper and the
    ///   test target but deliberately **not** into the app module. `FailureModeTests` is the
    ///   only place both are visible at once, and it pins them together.
    public var wireCode: Int {
        switch self {
        case .stopOnFirstError: return 1
        case .logAndContinue:   return 2
        }
    }

    public var description: String { reportName }
}

// MARK: - What one chunk's cycle cost

/// Which phase a chunk reached, and how it ended.
///
/// Five cases rather than a `Bool`, because each implies a different set of numbers being
/// meaningful. A chunk that failed its write has a valid read latency and no write throughput;
/// a chunk that failed its read has neither. Collapsing them would make a consumer guess.
public enum ChunkOutcome: Equatable, Sendable, CustomStringConvertible {

    /// Read, write and verify all completed, and the comparison matched.
    case completed

    /// All three phases completed; the verify read differed from what was written.
    ///
    /// **Timing-wise this is a complete chunk** — every byte moved — so it contributes to every
    /// rate and to both latency distributions. It is a *data* failure, not an I/O one, and
    /// counting it as a phase failure would depress the throughput of a drive that is reading
    /// and writing perfectly well.
    case verifyMismatch

    /// The original read failed. Nothing was written, nothing verified.
    case failedReading

    /// The write failed. The read had succeeded; nothing was verified (rule 3 of the cycle).
    case failedWriting

    /// The verify read failed. The read and the write had both succeeded.
    case failedVerifying

    /// Did every phase move its bytes?
    public var didCompleteAllPhases: Bool {
        self == .completed || self == .verifyMismatch
    }

    /// Did this chunk fail in a way that stopped I/O partway through?
    public var isPhaseFailure: Bool {
        switch self {
        case .failedReading, .failedWriting, .failedVerifying: return true
        case .completed, .verifyMismatch:                      return false
        }
    }

    public var description: String {
        switch self {
        case .completed:       return "completed"
        case .verifyMismatch:  return "verify mismatch"
        case .failedReading:   return "failed reading"
        case .failedWriting:   return "failed writing"
        case .failedVerifying: return "failed verifying"
        }
    }
}

/// Everything measurable about one chunk's trip through the cycle.
///
/// ## This replaced Step 8's `ChunkTiming` (Step 9, 2026-08-04)
///
/// `ChunkTiming` carried three durations and was emitted **only for chunks that completed every
/// phase** — all three `catch` blocks in the cycle `continue` past the emission. That was
/// harmless while nothing computed statistics from it, and became a defect the moment something
/// did: an accumulator fed only completed chunks stalls its progress counter while the engine
/// walks on, so percent-complete freezes and the ETA runs away **on exactly the failing drive
/// this tool exists to find**, at the moment somebody is watching hardest.
///
/// So this is emitted **once per chunk, whatever happened**, and says which phase was reached.
/// It is a strict superset of what `ChunkTiming` carried, which is why that type is gone rather
/// than kept alongside: two representations of one fact are two things that can drift.
///
/// A duration is `nil` when that phase was never attempted, and non-`nil` when it was — whether
/// or not it succeeded. Which of those applies is decided by ``outcome``, never by inspecting
/// the durations, so a phase that failed in an unmeasurably short time cannot be mistaken for a
/// phase that never ran.
public struct ChunkMeasurement: Equatable, Sendable {

    /// Bytes this chunk covers. Shorter than the I/O size on a plan's final chunk (FR-TEST-5).
    public let byteLength: Int

    /// One past the last block this chunk covers — the run's position after it (FR-METR-6).
    public let endBlock: UInt64

    /// How the chunk ended.
    public let outcome: ChunkOutcome

    /// Time in the original read, successful or not. `nil` only if no read was attempted.
    ///
    /// Also what FR-TEST-9's falsifier consumes
    /// (see ``CacheBypassAssessment/observe(bytes:nanoseconds:)``).
    public let readNanoseconds: UInt64?

    /// Time in the write-back. `nil` when the read failed, so no write was attempted.
    public let writeNanoseconds: UInt64?

    /// Time in the verify read. `nil` when the read or the write failed.
    public let verifyNanoseconds: UInt64?

    /// Time this chunk spent in **host** work rather than waiting on the device — the compare,
    /// the write-guard re-check, the loop's own bookkeeping. NFR-PERF-3's numerator.
    ///
    /// Computed as the chunk's whole span minus the three device phases, so it captures
    /// everything in the loop that is not a device call rather than only the parts somebody
    /// remembered to time.
    ///
    /// - Note: it stops just before the observer is called, so it excludes whatever the
    ///   *observer* costs. That is deliberate: this is a figure about the cycle, and including
    ///   the observer would make it depend on who is watching. Nothing is hidden by the choice —
    ///   `MetricsSnapshot.unaccountedNanoseconds` measures the wall clock independently and
    ///   would show an expensive observer as unaccounted time.
    public let hostOverheadNanoseconds: UInt64

    public init(byteLength: Int,
                endBlock: UInt64,
                outcome: ChunkOutcome,
                readNanoseconds: UInt64?,
                writeNanoseconds: UInt64?,
                verifyNanoseconds: UInt64?,
                hostOverheadNanoseconds: UInt64) {
        self.byteLength = byteLength
        self.endBlock = endBlock
        self.outcome = outcome
        self.readNanoseconds = readNanoseconds
        self.writeNanoseconds = writeNanoseconds
        self.verifyNanoseconds = verifyNanoseconds
        self.hostOverheadNanoseconds = hostOverheadNanoseconds
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

    /// The device's logical block size (512 or 4096, NFR-COMPAT-5).
    ///
    /// Added in Step 9. Without it an observer cannot turn ``blockCount`` into bytes, and every
    /// metric in FR-METR is denominated in bytes — so a run's total size was not derivable from
    /// what Step 8 handed over.
    public let logicalBlockSize: Int

    /// Chunks the plan contains.
    public let chunkCount: UInt64

    /// The FR-TEST-9 verdict the run starts from.
    public let cacheBypass: CacheBypassState

    /// Bytes the run's range covers, counted **once** — not the 3× the cycle actually moves.
    public var rangeByteCount: UInt64 { blockCount * UInt64(logicalBlockSize) }

    public init(deviceName: String,
                startBlock: UInt64,
                blockCount: UInt64,
                ioSizeBytes: Int,
                logicalBlockSize: Int,
                chunkCount: UInt64,
                cacheBypass: CacheBypassState) {
        self.deviceName = deviceName
        self.startBlock = startBlock
        self.blockCount = blockCount
        self.ioSizeBytes = ioSizeBytes
        self.logicalBlockSize = logicalBlockSize
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

    /// **Once per chunk, whatever happened to it** — completed, mismatched, or failed at any
    /// phase. This is the event a metrics accumulator counts progress from, which is why it
    /// fires on the failure paths too (see ``ChunkMeasurement``).
    func chunkMeasured(_ chunk: Chunk, measurement: ChunkMeasurement)

    /// A block range failed. The helper logs it here (BUILD-PLAN 8.7, NFR-OBS-1).
    ///
    /// Distinct from a failing ``chunkMeasured(_:measurement:)``, and not a replacement for it:
    /// this can fire **many times for one chunk** — once per contiguous run of mismatched
    /// blocks — and carries no timing, so it cannot drive progress or throughput.
    ///
    /// - Returns: whether to keep going. Defaults to ``FailureDisposition/continueRun``, which
    ///   is FR-FAIL-4's default mode.
    func failureDetected(_ failure: BlockRangeFailure) -> FailureDisposition

    /// Once, after the last chunk or after a stop.
    func runFinished(_ summary: RunSummary)
}

public extension RunObserver {
    func runStarted(_ start: RunStart) {}
    func chunkMeasured(_ chunk: Chunk, measurement: ChunkMeasurement) {}
    func failureDetected(_ failure: BlockRangeFailure) -> FailureDisposition { .continueRun }
    func runFinished(_ summary: RunSummary) {}
}

// MARK: - Watching a run from more than one place

/// Delivers every event to several observers.
///
/// The engine takes one observer, and from Step 9 the helper needs two: the one that logs
/// (NFR-OBS-1) and the one that accumulates metrics (FR-METR-*). Composing them here rather
/// than having the logger forward to the accumulator keeps each observer a single thing, and
/// makes "did every event reach both?" a property a test can assert.
///
/// - Important: **every** observer is called, with no short-circuiting, including on
///   ``failureDetected(_:)``. An observer that only watches must never be able to change what
///   the run does by being asked first.
public final class ObserverFanOut: RunObserver {

    private let observers: [RunObserver]

    public init(_ observers: [RunObserver]) {
        self.observers = observers
    }

    public func runStarted(_ start: RunStart) {
        for observer in observers { observer.runStarted(start) }
    }

    public func chunkMeasured(_ chunk: Chunk, measurement: ChunkMeasurement) {
        for observer in observers { observer.chunkMeasured(chunk, measurement: measurement) }
    }

    /// Stop wins.
    ///
    /// Every observer is asked — none is skipped once an answer is known — and the run stops if
    /// **any** of them says to. That is the conservative direction and it is the one that makes
    /// composition safe: adding a passive observer, which answers with the default
    /// ``FailureDisposition/continueRun``, can never override a decision to stop.
    public func failureDetected(_ failure: BlockRangeFailure) -> FailureDisposition {
        var disposition = FailureDisposition.continueRun
        for observer in observers where observer.failureDetected(failure) == .stopRun {
            disposition = .stopRun
        }
        return disposition
    }

    public func runFinished(_ summary: RunSummary) {
        for observer in observers { observer.runFinished(summary) }
    }
}

// MARK: - The observer that obeys the mode

/// Answers every failure according to the run's chosen mode (FR-FAIL-1/2/3), **and does nothing
/// else.**
///
/// ## Why this is not folded into the helper's `RunLogger`
///
/// `RunLogger` was written expecting to be where the mode wired in, and it is the obvious home:
/// it is already the observer that sees every failure. Two reasons it is not.
///
/// First, **it would not be testable.** The test target compiles the fourteen `Core/` files and
/// nothing else from the helper, by explicit membership. A decision that governs whether a run
/// keeps writing to a failing drive must not live in a file no test can reach.
///
/// Second, `RunLogger.failureDetected` has real bookkeeping in it — a counter, a limit, and a
/// once-only truncation notice — and a `return` on the wrong side of that `if` would silently
/// answer "carry on" to a run that was asked to stop. Mixing a safety decision into a branch
/// about how many log lines have been emitted is how one gets lost. This class has one method,
/// one expression, and nothing to get lost behind.
///
/// It composes with the logger through ``ObserverFanOut``, whose stop-wins rule is what makes
/// that safe: a passive observer answering the default ``FailureDisposition/continueRun`` can
/// never override this one.
public final class FailureModeObserver: RunObserver {

    /// The mode this run was started in.
    public let mode: FailureMode

    public init(mode: FailureMode) {
        self.mode = mode
    }

    public func failureDetected(_ failure: BlockRangeFailure) -> FailureDisposition {
        mode.disposition(for: failure.kind)
    }
}

/// Assembles the observer set a run is watched by, with the deciding observer always in it.
///
/// ## Why this is a function and not an array literal at the call site
///
/// The helper's `RunCoordinator` composes three observers: one that logs, this one that obeys the
/// mode, and one that accumulates metrics. Two of the three answer a failure with the neutral
/// ``FailureDisposition/continueRun`` because they only watch, so **the entire behaviour of
/// stop-on-first-error rests on the deciding observer being in that list.**
///
/// And `RunCoordinator` is not in the test target — it compiles the fourteen `Core/` files and
/// nothing else from the helper. So an edit that dropped one element from a hand-written array
/// would turn FR-FAIL-2 into FR-FAIL-3 **on real hardware, silently**: no test would fail, the
/// run would complete, and the report would be honest about a run that had ignored the mode it
/// was given. On a healthy drive it would never even be noticeable, because there is no failure
/// to not-stop on.
///
/// Making the composition one call moves it inside the tested boundary. What is left outside is
/// a single call site rather than an assembly, and increment 3 adds a second, independent check:
/// the cycle's reply names the mode the run actually used, so hardware can confirm the mode
/// reached the run path even on a drive with nothing wrong with it.
public enum RunObservers {

    /// - Parameters:
    ///   - mode: FR-FAIL-1's mode. Its observer is placed **first**, though position does not
    ///     matter — `ObserverFanOut` asks every observer and stop wins. `RunObserverCompositionTests`
    ///     pins that in both orders, so this is legibility rather than load-bearing ordering.
    ///   - watchers: observers that only watch — the logger, the metrics accumulator, a test's
    ///     recorder. None of them may change what the run does.
    public static func forRun(mode: FailureMode,
                              watchedBy watchers: [RunObserver]) -> ObserverFanOut {
        var observers: [RunObserver] = [FailureModeObserver(mode: mode)]
        observers.append(contentsOf: watchers)
        return ObserverFanOut(observers)
    }
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
