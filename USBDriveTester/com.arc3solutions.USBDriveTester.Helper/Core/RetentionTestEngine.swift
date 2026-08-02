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
public struct ChunkPlan: Sequence {

    /// Logical block size in bytes.
    public let logicalBlockSize: Int

    /// Total addressable blocks (64-bit, NFR-COMPAT-6).
    public let blockCount: UInt64

    /// Fixed I/O size for the run, in bytes (FR-CTRL-8).
    public let ioSizeBytes: Int

    /// Whole blocks in a full chunk. Always >= 1, guaranteed by the initialiser.
    public let blocksPerChunk: UInt64

    /// Build a plan.
    ///
    /// - Throws: ``ChunkPlanError`` if `ioSizeBytes` is not a positive multiple of
    ///   `logicalBlockSize`.
    public init(logicalBlockSize: Int, blockCount: UInt64, ioSizeBytes: Int) throws {
        guard ioSizeBytes > 0 else {
            throw ChunkPlanError.ioSizeNotPositive(ioSizeBytes: ioSizeBytes)
        }
        guard logicalBlockSize > 0, ioSizeBytes % logicalBlockSize == 0 else {
            throw ChunkPlanError.ioSizeNotBlockAligned(ioSizeBytes: ioSizeBytes,
                                                        logicalBlockSize: logicalBlockSize)
        }
        self.logicalBlockSize = logicalBlockSize
        self.blockCount = blockCount
        self.ioSizeBytes = ioSizeBytes
        self.blocksPerChunk = UInt64(ioSizeBytes / logicalBlockSize)
    }

    /// Build a plan from device geometry — in production, the ioctl-derived values.
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
    /// Useful where iterating to reach a chunk would be absurd: `disk8`'s final chunk is
    /// number 5,245,439.
    public func chunk(at index: UInt64) -> Chunk? {
        guard index < chunkCount else { return nil }
        let startBlock = index * blocksPerChunk
        let remaining = blockCount - startBlock
        let blocks = Swift.min(blocksPerChunk, remaining)     // final chunk = exact remainder
        return Chunk(index: Int(index),
                     byteOffset: startBlock * UInt64(logicalBlockSize),
                     byteLength: Int(blocks) * logicalBlockSize,
                     startBlock: startBlock,
                     blockCount: blocks)
    }

    /// The last chunk, or `nil` on an empty device. This is the FR-TEST-5 case.
    public var finalChunk: Chunk? {
        chunkCount == 0 ? nil : chunk(at: chunkCount - 1)
    }

    public func makeIterator() -> Iterator {
        Iterator(logicalBlockSize: logicalBlockSize,
                 blockCount: blockCount,
                 blocksPerChunk: blocksPerChunk)
    }

    /// Walks the device from block 0 to the last block, producing each chunk as it is asked
    /// for and holding nothing but its own position.
    public struct Iterator: IteratorProtocol {

        private let logicalBlockSize: Int
        private let blockCount: UInt64
        private let blocksPerChunk: UInt64
        private var offsetBlocks: UInt64 = 0
        private var index = 0

        init(logicalBlockSize: Int, blockCount: UInt64, blocksPerChunk: UInt64) {
            self.logicalBlockSize = logicalBlockSize
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

            let chunk = Chunk(index: index,
                              byteOffset: offsetBlocks * UInt64(logicalBlockSize),
                              byteLength: Int(blocks) * logicalBlockSize,
                              startBlock: offsetBlocks,
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
