//
//  RetentionTestEngine.swift
//  Core — the chunk plan, and the engine that will host the read -> write-back -> verify cycle.
//
//  Step 2 created this as a stub computing only the chunk plan. Step 7 makes that plan
//  **lazy** (see `ChunkPlan` below and the note on NFR-PERF-2). The per-chunk cycle, metrics
//  and failure classification arrive in Steps 8-10 against this same type.
//
//  Pure Foundation; no privilege. Drives any `RawBlockDevice` — simulated or real.
//

import Foundation

/// One block-aligned unit of work in a run.
public struct Chunk: Equatable {
    /// Zero-based position of this chunk in the plan.
    public let index: Int
    /// Byte offset of the chunk from the start of the device (block-aligned).
    public let byteOffset: UInt64
    /// Length of the chunk in bytes (a whole multiple of the logical block size; the
    /// final chunk may be shorter than the I/O size).
    public let byteLength: Int
    /// First logical block covered by this chunk.
    public let startBlock: UInt64
    /// Number of logical blocks covered by this chunk.
    public let blockCount: UInt64

    public init(index: Int, byteOffset: UInt64, byteLength: Int, startBlock: UInt64, blockCount: UInt64) {
        self.index = index
        self.byteOffset = byteOffset
        self.byteLength = byteLength
        self.startBlock = startBlock
        self.blockCount = blockCount
    }
}

/// Errors from computing a chunk plan (configuration problems, not device I/O).
public enum ChunkPlanError: Error, Equatable {
    /// The requested I/O size was zero or negative.
    case ioSizeNotPositive(ioSizeBytes: Int)
    /// The requested I/O size was not a whole multiple of the logical block size.
    case ioSizeNotBlockAligned(ioSizeBytes: Int, logicalBlockSize: Int)
}

// MARK: - The plan

/// The sequential, block-aligned tiling of a whole device, **computed on demand**.
///
/// ## Why this is a `Sequence` and not an array (NFR-PERF-2)
///
/// Step 2 returned `[Chunk]`, and Step 7's scoping measured what that costs. `Chunk` has a
/// 40-byte stride, so a materialised plan is:
///
/// | Device | blocks (512 B) | chunks @ 4 MiB | materialised plan |
/// |---|---|---|---|
/// | `disk4` — 1.0 TB | 1,953,525,168 | 238,468 | **9.1 MiB** |
/// | `disk8` — 22 TB | 42,970,644,479 | 5,245,440 | **200.1 MiB** |
///
/// That is memory scaling linearly with capacity, which is exactly what NFR-PERF-2 forbids —
/// *"a bounded-memory stream of chunks so that arbitrarily large (multi-terabyte) devices can
/// be tested without proportional memory growth"*. It survived Step 2 because the gate item
/// says "peak **buffer** memory", and the buffers genuinely were bounded. Bounded buffers
/// beside an unbounded plan satisfied the wording and missed the point.
///
/// A `ChunkPlan` stores four integers. Its size does not depend on the device, so the whole
/// question disappears rather than being managed — the same reasoning as `ChunkBuffers`, which
/// cannot scale with capacity because capacity is not one of its inputs.
///
/// ## The plan is a function of geometry, not of a device
///
/// Only `logicalBlockSize` and `blockCount` are needed, which is why this can be built
/// straight from a `DeviceGeometry`. That matters for testing: `InMemoryBlockDevice` allocates
/// its entire backing store, so it cannot represent `disk8` — but a `ChunkPlan` over `disk8`'s
/// real geometry costs nothing, and the awkward 8,191-block final chunk can be checked against
/// the actual hardware numbers rather than invented ones.
///
/// ## Covering part of a device (added Step 8)
///
/// A plan starts at ``startBlock`` and covers ``blockCount`` blocks from there. A whole-device
/// plan — what a run uses, and what FR-TEST-1/4 requires — is the default: block 0 to the last
/// block.
///
/// The partial form exists because Step 8's hardware gate writes a bounded region of `disk4`
/// rather than all 1 TB of it, and because there is no way to cancel a run until Step 11. It is
/// expressed as **the plan the engine is given**, not as an early stop, which is what lets the
/// engine keep its single behaviour — *complete the plan you were given* — and lets a bounded
/// run finish as a genuinely completed run rather than as a special case.
///
/// It could not be expressed as a range of chunk *indices*: a plan needs to start wherever it
/// is told to, and only a `startBlock` can say that. The gate happens to draw a start that is
/// chunk-aligned — deliberately, so it writes where a real whole-device run would — but the
/// type must not depend on that.
public struct ChunkPlan: Sequence {

    /// Logical block size in bytes.
    public let logicalBlockSize: Int

    /// First block this plan covers. `0` for a whole-device plan.
    public let startBlock: UInt64

    /// Blocks this plan covers, counting from ``startBlock`` (64-bit, NFR-COMPAT-6). For a
    /// whole-device plan this is the device's total block count.
    ///
    /// - Note: the plan does **not** know how large the device is, so it cannot tell whether
    ///   it runs past the end. `RetentionTestEngine.run` validates the range against the
    ///   device before building one, and every transfer is validated again at the device
    ///   boundary.
    public let blockCount: UInt64

    /// Fixed I/O size for the run, in bytes (FR-CTRL-8).
    public let ioSizeBytes: Int

    /// Whole blocks in a full chunk. Always >= 1, guaranteed by the initialiser.
    public let blocksPerChunk: UInt64

    /// Build a plan.
    ///
    /// - Throws: ``ChunkPlanError`` if `ioSizeBytes` is not a positive multiple of
    ///   `logicalBlockSize`.
    public init(logicalBlockSize: Int,
                startBlock: UInt64 = 0,
                blockCount: UInt64,
                ioSizeBytes: Int) throws {
        guard ioSizeBytes > 0 else {
            throw ChunkPlanError.ioSizeNotPositive(ioSizeBytes: ioSizeBytes)
        }
        guard logicalBlockSize > 0, ioSizeBytes % logicalBlockSize == 0 else {
            throw ChunkPlanError.ioSizeNotBlockAligned(ioSizeBytes: ioSizeBytes,
                                                        logicalBlockSize: logicalBlockSize)
        }
        self.logicalBlockSize = logicalBlockSize
        self.startBlock = startBlock
        self.blockCount = blockCount
        self.ioSizeBytes = ioSizeBytes
        self.blocksPerChunk = UInt64(ioSizeBytes / logicalBlockSize)
    }

    /// Build a whole-device plan from device geometry — in production, the ioctl-derived
    /// values.
    public init(geometry: DeviceGeometry, ioSizeBytes: Int) throws {
        try self.init(logicalBlockSize: Int(geometry.logicalBlockSize),
                      blockCount: geometry.blockCount,
                      ioSizeBytes: ioSizeBytes)
    }

    /// How many chunks the plan contains, computed arithmetically rather than by counting.
    ///
    /// `UInt64` rather than `Int`, and the division is written to avoid the overflow that
    /// `(blockCount + blocksPerChunk - 1)` would hit near `UInt64.max`.
    public var chunkCount: UInt64 {
        let full = blockCount / blocksPerChunk
        return blockCount % blocksPerChunk == 0 ? full : full + 1
    }

    /// Total bytes the plan covers — the whole device.
    public var totalByteCount: UInt64 { blockCount * UInt64(logicalBlockSize) }

    /// The chunk at `index`, in constant time, or `nil` if past the end.
    ///
    /// `index` is the position **within this plan**, not a device-wide chunk number: a plan
    /// starting at block 1,000,000 still numbers its first chunk 0.
    ///
    /// Useful where iterating to reach a chunk would be absurd: `disk8`'s final chunk is
    /// number 5,245,439.
    public func chunk(at index: UInt64) -> Chunk? {
        guard index < chunkCount else { return nil }
        let offsetBlocks = index * blocksPerChunk
        let remaining = blockCount - offsetBlocks
        let blocks = Swift.min(blocksPerChunk, remaining)     // final chunk = exact remainder
        let firstBlock = startBlock + offsetBlocks
        return Chunk(index: Int(index),
                     byteOffset: firstBlock * UInt64(logicalBlockSize),
                     byteLength: Int(blocks) * logicalBlockSize,
                     startBlock: firstBlock,
                     blockCount: blocks)
    }

    /// The last chunk, or `nil` on an empty device. This is the FR-TEST-5 case.
    public var finalChunk: Chunk? {
        chunkCount == 0 ? nil : chunk(at: chunkCount - 1)
    }

    public func makeIterator() -> Iterator {
        Iterator(logicalBlockSize: logicalBlockSize,
                 startBlock: startBlock,
                 blockCount: blockCount,
                 blocksPerChunk: blocksPerChunk)
    }

    /// Walks the plan from its first block to its last, producing each chunk as it is asked
    /// for and holding nothing but its own position.
    public struct Iterator: IteratorProtocol {

        private let logicalBlockSize: Int
        private let startBlock: UInt64
        private let blockCount: UInt64
        private let blocksPerChunk: UInt64
        private var offsetBlocks: UInt64 = 0
        private var index = 0

        init(logicalBlockSize: Int, startBlock: UInt64, blockCount: UInt64, blocksPerChunk: UInt64) {
            self.logicalBlockSize = logicalBlockSize
            self.startBlock = startBlock
            self.blockCount = blockCount
            self.blocksPerChunk = blocksPerChunk
        }

        public mutating func next() -> Chunk? {
            guard offsetBlocks < blockCount else { return nil }

            let remaining = blockCount - offsetBlocks
            // The final chunk is sized to the *exact* remaining blocks, never rounded to an
            // arbitrary byte remainder (FR-TEST-5). Because a device is an integer number of
            // logical blocks, every chunk including the last is a whole number of blocks.
            let blocks = Swift.min(blocksPerChunk, remaining)

            let firstBlock = startBlock + offsetBlocks
            let chunk = Chunk(index: index,
                              byteOffset: firstBlock * UInt64(logicalBlockSize),
                              byteLength: Int(blocks) * logicalBlockSize,
                              startBlock: firstBlock,
                              blockCount: blocks)
            offsetBlocks += blocks
            index += 1
            return chunk
        }
    }
}

// MARK: - The engine

public struct RetentionTestEngine {

    /// The device under test (simulated in Step 2; real `/dev/rdiskN` from Step 7).
    public let device: RawBlockDevice

    /// Fixed I/O size for the run, in bytes. In production this is one of {1, 2, 4, 8} MiB
    /// (FR-CTRL-8, default 4), but the engine only requires that it be a positive multiple of
    /// the device's logical block size — so tests can use deliberately awkward sizes to
    /// exercise the final chunk. The {1,2,4,8} MiB dropdown that maps onto this arrives in
    /// Step 11.
    public let ioSizeBytes: Int

    public init(device: RawBlockDevice, ioSizeBytes: Int) {
        self.device = device
        self.ioSizeBytes = ioSizeBytes
    }

    /// The plan, lazily. **This is what a run iterates** (NFR-PERF-2).
    ///
    /// - Throws: ``ChunkPlanError`` if `ioSizeBytes` is not a positive multiple of the
    ///   device's `logicalBlockSize`.
    public func chunks() throws -> ChunkPlan {
        try ChunkPlan(logicalBlockSize: device.logicalBlockSize,
                      blockCount: device.blockCount,
                      ioSizeBytes: ioSizeBytes)
    }

    /// The whole plan, materialised into an array.
    ///
    /// - Important: **for tests and diagnostics only — not for the run path.** This allocates
    ///   40 bytes per chunk, which is 9.1 MiB for `disk4` and 200.1 MiB for `disk8`, and is
    ///   precisely the growth NFR-PERF-2 forbids. It survives because the Step 2 tests are
    ///   written against it and it remains the clearest way to assert a small plan's exact
    ///   shape. A run uses ``chunks()``.
    ///
    /// The final chunk is sized to the *exact* remaining blocks (FR-TEST-5).
    public func chunkPlan() throws -> [Chunk] {
        Array(try chunks())
    }
}

// MARK: - The cycle (Step 8, AI-6)

//  read original -> write the SAME bytes back -> read again -> compare.
//
//  Satisfies FR-TEST-1/3/4/7/8, FR-FAIL-6/7, NFR-REL-1/2/4/8, and is FR-TEST-9's caller.
//  Runs identically against `InMemoryBlockDevice` and `FileDescriptorBlockDevice` — which is
//  the entire reason `RawBlockDevice` exists, and what lets the non-destructiveness proof be
//  made in simulation *before* the first byte reaches real media (NFR-REL-1).
//
//  ## Four rules the shape of this code enforces, rather than remembers
//
//  1. **The bytes written are the bytes read (FR-TEST-7).** `write` is handed
//     `buffers.original`, untouched, and there is no other buffer it could be handed.
//  2. **A failed read can never lead to a write.** The read returns a ``LoadedChunk`` or
//     throws; the write takes one. The buffers are reused, so falling through a failed read
//     into a write would put the *previous* chunk's data at this chunk's offset — see
//     ``LoadedChunk``.
//  3. **A failed write ends the chunk.** Verifying after a failed write compares buffer A
//     against the data that was already there and reports a mismatch that did not happen.
//  4. **Nothing accumulates per chunk (NFR-REL-4, NFR-PERF-2).** The loop holds counters, one
//     `LoadedChunk` (two integers and a `Chunk`), and a bounded ``FailureLog``. The plan is
//     iterated lazily and the buffers are the two allocated before it started.

public extension RetentionTestEngine {

    /// Run the read → write-back → read-verify cycle.
    ///
    /// - Parameters:
    ///   - buffers: the run's two buffers, allocated once and reused (NFR-PERF-1). Must be at
    ///     least ``ioSizeBytes`` each.
    ///   - deviceName: canonical BSD name, e.g. `disk4`. Checked against what the grant says
    ///     is held, before every write.
    ///   - blockRange: the blocks to cover, or `nil` for the **whole device** — which is what
    ///     FR-TEST-1/4 requires and what a real run uses. A bounded range is expressed as the
    ///     plan, so a bounded run *completes* rather than stopping early.
    ///   - cacheBypass: the FR-TEST-9 assessment seeded from `AcquiredDevice.cacheBypass` and
    ///     the link speed. Every read's throughput is fed in, which can only downgrade it.
    ///   - grant: what the helper currently holds. Called **before every write**, not once —
    ///     a device released mid-run must stop the very next write (NFR-REL-3, NFR-REL-5),
    ///     and `AcquiredDevice.grant` recomputes rather than caching precisely so this works.
    ///   - control: what the app currently wants this run to do (FR-CTRL-2/3/4). Called **at each
    ///     chunk boundary**, for the same reason `grant` is called before each write: the answer
    ///     changes underneath a call that is already in flight, so a value captured once would be
    ///     the answer as it stood when the run started.
    ///
    ///     **Required, with no default**, unlike `observer`. A run that silently could not be
    ///     interrupted would fail exactly the way `RunObservers.forRun` was built to prevent — no
    ///     test failing anywhere, and nothing visible until somebody pressed Pause on real
    ///     hardware and watched it do nothing. `grant`, the other safety-critical closure in this
    ///     signature, is required for the same reason. Pass ``RunControl/uninterrupted`` to say so
    ///     deliberately.
    ///   - observer: receives run start, each completed chunk, each failure, and the summary.
    ///     Its answer to a failure decides whether the run continues.
    ///   - clock: monotonic nanoseconds. Injected so FR-TEST-9's falsifier can be driven from
    ///     a test with no device fast enough to trigger it.
    ///
    /// - Returns: what the run did, including the final cache-bypass verdict.
    /// - Throws: ``RunAbort`` — and only ``RunAbort``. A *device* failure is never thrown; it
    ///   is classified, recorded and reported to the observer. Anything thrown from here is
    ///   this tool's fault, not the drive's.
    func run(buffers: ChunkBuffers,
             deviceName: String,
             blockRange: Range<UInt64>? = nil,
             cacheBypass: CacheBypassAssessment,
             grant: () -> DeviceAccessGrant?,
             control: () -> RunControlSignal,
             observer: RunObserver? = nil,
             clock: MonotonicClock = RunClock.monotonicNanoseconds) throws -> RunSummary {

        let range = blockRange ?? 0 ..< device.blockCount
        let rangeBlockCount = range.upperBound - range.lowerBound

        guard range.upperBound <= device.blockCount else {
            throw RunAbort.rangeNotWithinDevice(startBlock: range.lowerBound,
                                                blockCount: rangeBlockCount,
                                                deviceBlockCount: device.blockCount)
        }
        guard buffers.capacityBytes >= ioSizeBytes else {
            throw RunAbort.buffersTooSmall(ioSizeBytes: ioSizeBytes,
                                           bufferCapacityBytes: buffers.capacityBytes)
        }

        let plan: ChunkPlan
        do {
            plan = try ChunkPlan(logicalBlockSize: device.logicalBlockSize,
                                 startBlock: range.lowerBound,
                                 blockCount: rangeBlockCount,
                                 ioSizeBytes: ioSizeBytes)
        } catch let error as ChunkPlanError {
            throw RunAbort.planRejected(error)
        }

        // NFR-REL-3, before anything is touched. Re-checked before every write below; this
        // one exists so a run with no access held fails before it reads a single byte.
        try Self.requireWriteAccess(grant(), deviceName: deviceName)

        // NOTE (2026-08-02): an earlier draft called `ChunkBuffers.resetPeakAllocatedBytes()`
        // here, to report a per-run high-water mark. That was wrong, and the test suite caught
        // it: `ChunkBuffers`' accounting is **process-global**, so a run resetting it silently
        // clobbered `ChunkBuffersInstrumentationTests`' baseline in a concurrently-running
        // suite. Production code has no business mutating shared instrumentation — and the
        // figure it bought was the weaker half of NFR-PERF-1 anyway. What the summary reports
        // instead is what this run actually holds, which cannot depend on the device because
        // capacity is not one of `ChunkBuffers`' inputs. The property that the run does not
        // *accumulate* buffers is Step 7's `reusingOnePairAcrossManyChunksDoesNotAccumulate`,
        // and the property that it holds one chunk at a time is the ordering audit.

        var assessment = cacheBypass
        var failures = FailureLog()
        var chunksProcessed: UInt64 = 0
        var bytesRead: UInt64 = 0
        var bytesWritten: UInt64 = 0
        var bytesVerified: UInt64 = 0
        var outcome = RunOutcome.completed

        let blockSize = device.logicalBlockSize

        observer?.runStarted(RunStart(deviceName: deviceName,
                                      startBlock: plan.startBlock,
                                      blockCount: plan.blockCount,
                                      ioSizeBytes: ioSizeBytes,
                                      logicalBlockSize: blockSize,
                                      chunkCount: plan.chunkCount,
                                      cacheBypass: assessment.state))

        for chunk in plan {
            // **NFR-REL-10, and the only place a run is interrupted.**
            //
            // Consulted here — before this chunk's read, and therefore *after* the previous
            // chunk's full read → write-back → verify — so a pause settles with the device at a
            // chunk boundary and no write in flight **by construction rather than by care**. There
            // is no other point in this loop where that is true without qualification.
            //
            // It is also before `chunksProcessed += 1`, which is what makes `chunk.startBlock` the
            // correct resume point: this chunk has not been touched, so a resume must redo it, not
            // skip it. The alternative — record the last completed chunk and add one — is the same
            // fact with an increment in front of it, and the increment is where the off-by-one
            // would live.
            if let interruption = Self.interruption(control(), atBlock: chunk.startBlock) {
                outcome = interruption
                break
            }

            chunksProcessed += 1

            // The chunk's span starts here, so host overhead below captures *everything* in this
            // iteration that is not a device call — the write-guard re-check, the compare, the
            // loop's own bookkeeping — rather than only the parts somebody remembered to time.
            let chunkStart = clock()
            var sawMismatch = false

            /// Record a failure and ask the observer whether to carry on.
            /// - Returns: `true` to keep running.
            func record(_ kind: BlockFailureKind, from startBlock: UInt64, blocks: UInt64) -> Bool {
                let failure = BlockRangeFailure(startBlock: startBlock,
                                                blockCount: blocks,
                                                kind: kind)
                failures.record(failure)
                if kind == .verifyMismatch { sawMismatch = true }
                guard observer?.failureDetected(failure) == FailureDisposition.stopRun else {
                    return true
                }
                outcome = .stoppedOnFailure(failure)
                return false
            }

            /// Emit this chunk's measurement. **Called exactly once per chunk, on every path** —
            /// completed, mismatched, or failed at any phase. That is what keeps a metrics
            /// consumer's progress moving on a failing drive; see ``ChunkMeasurement``.
            ///
            /// `spanEnd` is passed in rather than read here so it can be captured *before* the
            /// observer is involved: host overhead is a figure about the cycle, and it must not
            /// vary with what the observer costs.
            ///
            /// `RunMetricsObserverTests` asserts the once-per-chunk property against runs with
            /// every mix of outcomes, because "every path remembered to call this" is exactly
            /// the kind of thing that is true until somebody adds a path.
            func measure(_ chunkOutcome: ChunkOutcome,
                         endedAt spanEnd: UInt64,
                         read: UInt64?, write: UInt64?, verify: UInt64?) {
                let span = spanEnd > chunkStart ? spanEnd - chunkStart : 0
                let deviceTime = (read ?? 0) &+ (write ?? 0) &+ (verify ?? 0)
                observer?.chunkMeasured(chunk, measurement: ChunkMeasurement(
                    byteLength: chunk.byteLength,
                    endBlock: chunk.startBlock &+ chunk.blockCount,
                    outcome: chunkOutcome,
                    readNanoseconds: read,
                    writeNanoseconds: write,
                    verifyNanoseconds: verify,
                    hostOverheadNanoseconds: span > deviceTime ? span - deviceTime : 0))
            }

            // 1. Read the original into buffer A (FR-TEST-3).
            let readStart = clock()
            let loaded: LoadedChunk
            do {
                try device.read(into: buffers.original(byteCount: chunk.byteLength),
                                atByteOffset: chunk.byteOffset)
                loaded = LoadedChunk(chunk: chunk, byteCount: chunk.byteLength)
            } catch let error as DeviceIOError {
                // Timed even though it failed. Step 8 did not time this path at all, because
                // nothing consumed it; a metrics consumer needs it, and a drive that takes
                // thirty seconds to fail a read has spent thirty seconds of the run.
                let failedAt = clock()
                // Before `measure`: if this is an addressing fault it is *our* bug, the run
                // aborts, and it is not a measurement of the device.
                let classification = try Self.classify(error, operation: .readError)
                measure(.failedReading, endedAt: failedAt,
                        read: failedAt &- readStart, write: nil, verify: nil)
                switch classification {
                case .blockFailure(let kind):
                    if record(kind, from: chunk.startBlock, blocks: chunk.blockCount) { continue }
                case .deviceLost:
                    // Not recorded: an absent device has not failed a block. Nothing had been
                    // written this chunk, so the drive is exactly as the run found it.
                    outcome = .deviceLost(atBlock: chunk.startBlock, phase: .reading)
                }
                break
            }
            let readNanoseconds = clock() &- readStart
            bytesRead += UInt64(loaded.byteCount)
            assessment.observe(bytes: loaded.byteCount, nanoseconds: readNanoseconds)

            // 2. Write buffer A back, unchanged, to the same place (FR-TEST-7, NFR-REL-2).
            //    The guard is re-checked here, per chunk, not once at the top.
            //
            //    A refusal throws `RunAbort` and no measurement is emitted for this chunk —
            //    correct, because the run ends and the chunk never happened.
            try Self.requireWriteAccess(grant(), deviceName: deviceName)

            let writeStart = clock()
            do {
                try device.write(UnsafeRawBufferPointer(buffers.original(byteCount: loaded.byteCount)),
                                 atByteOffset: loaded.chunk.byteOffset)
            } catch let error as DeviceIOError {
                let failedAt = clock()
                let classification = try Self.classify(error, operation: .writeError)
                measure(.failedWriting, endedAt: failedAt,
                        read: readNanoseconds, write: failedAt &- writeStart, verify: nil)
                switch classification {
                case .blockFailure(let kind):
                    // Rule 3: no verify after a failed write.
                    if record(kind, from: chunk.startBlock, blocks: chunk.blockCount) { continue }
                case .deviceLost:
                    // The one phase where the device left while this run held the chunk's only
                    // copy of the original and had not finished putting it back.
                    outcome = .deviceLost(atBlock: chunk.startBlock, phase: .writingBack)
                }
                break
            }
            let writeNanoseconds = clock() &- writeStart
            bytesWritten += UInt64(loaded.byteCount)

            // 3. Read what was just written into buffer B.
            let verifyStart = clock()
            do {
                try device.read(into: buffers.verify(byteCount: loaded.byteCount),
                                atByteOffset: loaded.chunk.byteOffset)
            } catch let error as DeviceIOError {
                let failedAt = clock()
                let classification = try Self.classify(error, operation: .readError)
                measure(.failedVerifying, endedAt: failedAt,
                        read: readNanoseconds, write: writeNanoseconds,
                        verify: failedAt &- verifyStart)
                switch classification {
                case .blockFailure(let kind):
                    if record(kind, from: chunk.startBlock, blocks: chunk.blockCount) { continue }
                case .deviceLost:
                    // The write-back had already reported success, so this chunk was whole
                    // before the device left. Unverified is not the same as bad.
                    outcome = .deviceLost(atBlock: chunk.startBlock, phase: .verifying)
                }
                break
            }
            let verifyNanoseconds = clock() &- verifyStart
            bytesVerified += UInt64(loaded.byteCount)

            // The verify read is the one a host cache would answer, so it is the observation
            // FR-TEST-9's falsifier most needs (D6, 2026-08-02).
            assessment.observe(bytes: loaded.byteCount, nanoseconds: verifyNanoseconds)

            // 4. Compare A with B (NFR-REL-8, FR-TEST-8), narrowing to the blocks that differ.
            let finishedScan = Self.scanMismatchedBlocks(
                original: UnsafeRawBufferPointer(buffers.original(byteCount: loaded.byteCount)),
                verify: UnsafeRawBufferPointer(buffers.verify(byteCount: loaded.byteCount)),
                chunk: loaded.chunk,
                logicalBlockSize: blockSize,
                emit: { start, blocks in record(.verifyMismatch, from: start, blocks: blocks) })

            // Captured after the scan, which on a *mismatching* chunk has already called the
            // observer once per differing range — so for those chunks the overhead figure does
            // include the observer's failure handling. On a healthy drive the scan is a single
            // `memcmp` that calls nobody, which is the case NFR-PERF-3 is about.
            let comparedAt = clock()

            // Emitted before the stop check, so the chunk a stop happened on is still measured.
            measure(sawMismatch ? .verifyMismatch : .completed,
                    endedAt: comparedAt,
                    read: readNanoseconds, write: writeNanoseconds, verify: verifyNanoseconds)

            if !finishedScan { break }
        }

        failures.finish()

        let summary = RunSummary(outcome: outcome,
                                 chunksProcessed: chunksProcessed,
                                 chunksPlanned: plan.chunkCount,
                                 bytesRead: bytesRead,
                                 bytesWritten: bytesWritten,
                                 bytesVerified: bytesVerified,
                                 failures: failures,
                                 cacheBypass: assessment,
                                 bufferBytesHeld: buffers.totalAllocatedBytes)

        observer?.runFinished(summary)
        return summary
    }

    // MARK: Internals

    /// Translate the app's current wish into the outcome it ends this run with, or `nil` to carry
    /// on (FR-CTRL-2/4).
    ///
    /// A function rather than a `switch` in the loop so that "which signals end a run, and as
    /// what" is one expression a test can reach — the same reason `FailureModeObserver` is its own
    /// type rather than a branch inside `RunLogger`'s counter bookkeeping.
    private static func interruption(_ signal: RunControlSignal,
                                     atBlock block: UInt64) -> RunOutcome? {
        switch signal {
        case .proceed: return nil
        case .pause:   return .pausedByUser(atBlock: block)
        case .stop:    return .stoppedByUser(atBlock: block)
        }
    }

    /// The NFR-REL-3 guard, in the vocabulary a run aborts with.
    private static func requireWriteAccess(_ grant: DeviceAccessGrant?,
                                           deviceName: String) throws {
        do {
            try WritePrecondition.check(grant, writingTo: deviceName)
        } catch let violation as WritePreconditionViolation {
            throw RunAbort.writeRefused(violation)
        }
    }

    /// What a device error means for the run.
    ///
    /// Three answers, and the third is Step 12's. `deviceLost` is **returned rather than
    /// thrown**, unlike an addressing fault, and that is the load-bearing part: a thrown
    /// `RunAbort` leaves `run()` with no `RunSummary` at all, discarding every failure the run
    /// had legitimately found before the device went away. Those failures were real readings of
    /// a real drive and the run must still report them.
    private enum ChunkFailureClassification: Equatable {

        /// The drive's failure, at the range being addressed. Recorded, and the observer decides
        /// whether to carry on (FR-FAIL-3).
        case blockFailure(BlockFailureKind)

        /// The device is not there. **Nothing is recorded against the drive** and the run ends.
        case deviceLost
    }

    /// Decide whether a device error is the **drive's** failure, the **device's absence**, or
    /// **ours**.
    ///
    /// A short transfer is the device's: the transfer was legal and it did not complete.
    /// A misaligned or out-of-range request is this engine addressing a place the device does
    /// not have, which means the plan is wrong — recording that as a bad block would report a
    /// fault in somebody's hardware that is actually a fault in this code.
    /// A lost device is none of those: it is the absence of the thing being judged, and it is
    /// the one case where the honest number of bad blocks found is zero.
    ///
    /// - Parameter operation: `.readError` when the failing call was a read, `.writeError`
    ///   when it was a write. Used for `shortTransfer`, which is neutral about direction.
    ///
    /// - Note: `shortTransfer` stays a **block failure**, deliberately. The *decision* is pinned
    ///   by `ShortTransferIsNotDeviceLossTests`; the *physics* behind it is still one hardware
    ///   gate short, and the two should not be confused.
    ///
    ///   Until Step 12's mutation round, neither was pinned. Moving this case into `.deviceLost`
    ///   passed all 1,288 tests, because `InMemoryBlockDevice` — the only device the engine tests
    ///   run against — had no hook that could produce a short transfer, so nothing could reach
    ///   this line with one. `FileDescriptorBlockDeviceTests` pins what *produces* a short
    ///   transfer and never what is *done* with one. The fake now has `injectShortRead` and
    ///   `injectShortWrite`, and the gap is closed on the decision.
    ///
    ///   What remains open: a device that vanishes mid-transfer could plausibly produce a short
    ///   read with no `errno` before it produces `ENXIO`, in which case the first chunk of a loss
    ///   is recorded as one bad range and the next call ends the run. That sequence is now a
    ///   test — `aShortReadFollowedByTheDeviceLeavingCostsOneRangeAndStillEndsTheRun` — so its
    ///   cost is known and bounded: a single spurious range rather than two million, which is not
    ///   the defect Step 12 exists to fix. Whether a real drive does it is what the hardware gate
    ///   can answer, and only it.
    private static func classify(_ error: DeviceIOError,
                                 operation: BlockFailureKind) throws -> ChunkFailureClassification {
        switch error {
        case .readError, .writeError, .shortTransfer:
            return .blockFailure(operation)

        case .deviceLost:
            return .deviceLost

        case .misaligned(let offset, let length, let logicalBlockSize):
            throw RunAbort.addressingFault(
                atByteOffset: offset, byteLength: length,
                detail: "not a whole multiple of the \(logicalBlockSize)-byte logical block size")

        case .outOfRange(let offset, let length, let deviceByteCount):
            throw RunAbort.addressingFault(
                atByteOffset: offset, byteLength: length,
                detail: "past the end of a \(deviceByteCount)-byte device")
        }
    }

    /// Report each contiguous run of blocks where the verify read differs from what was
    /// written (D4, 2026-08-02).
    ///
    /// One `memcmp` covers the whole chunk first, so the per-block walk is paid **only** when
    /// something actually differs — which on a healthy drive is never. Narrowing matters
    /// because a chunk is 8,192 blocks at 4 MiB / 512 B geometry, and reporting all 8,192 for
    /// a four-block fault is not the range that failed.
    ///
    /// - Parameter emit: called with (first block, block count) of each differing run;
    ///   returns `false` to stop.
    /// - Returns: `false` if `emit` asked to stop, `true` otherwise.
    private static func scanMismatchedBlocks(original: UnsafeRawBufferPointer,
                                             verify: UnsafeRawBufferPointer,
                                             chunk: Chunk,
                                             logicalBlockSize: Int,
                                             emit: (UInt64, UInt64) -> Bool) -> Bool {
        guard let left = original.baseAddress,
              let right = verify.baseAddress,
              original.count > 0,
              memcmp(left, right, original.count) != 0 else { return true }

        var runStart: UInt64?
        var runLength: UInt64 = 0
        var block: UInt64 = 0

        while block < chunk.blockCount {
            let offset = Int(block) * logicalBlockSize
            if memcmp(left + offset, right + offset, logicalBlockSize) != 0 {
                if runStart == nil { runStart = chunk.startBlock + block }
                runLength += 1
            } else if let start = runStart {
                if !emit(start, runLength) { return false }
                runStart = nil
                runLength = 0
            }
            block += 1
        }

        if let start = runStart, !emit(start, runLength) { return false }
        return true
    }
}
