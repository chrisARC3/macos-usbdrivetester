//
//  RetentionTestEngine.swift
//  Core — the engine that will host the read -> write-back -> read-verify algorithm.
//
//  For Step 2 this is a stub: it computes only the *chunk plan* for a device at a
//  given I/O size, so the plan (especially the block-size-rounded final chunk,
//  FR-TEST-5) can be unit-tested immediately. The per-chunk cycle, metrics, and
//  failure classification are added test-first in Steps 7-10 against this same type.
//
//  Pure Foundation; no privilege. Drives any RawBlockDevice — simulated or real.
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

public struct RetentionTestEngine {

    /// The device under test (simulated in Step 2; real `/dev/rdiskN` from Step 7).
    public let device: RawBlockDevice

    /// Fixed I/O size for the run, in bytes. In production this is one of
    /// {1, 2, 4, 8} MiB (FR-CTRL-8, default 4), but the engine only requires that it
    /// be a positive multiple of the device's logical block size — so tests can use
    /// deliberately awkward sizes to exercise the final chunk. The {1,2,4,8} MiB
    /// dropdown that maps onto this arrives in Steps 7/11.
    public let ioSizeBytes: Int

    public init(device: RawBlockDevice, ioSizeBytes: Int) {
        self.device = device
        self.ioSizeBytes = ioSizeBytes
    }

    /// Compute the sequential, block-aligned chunk plan covering the whole device
    /// from block 0 to the last block.
    ///
    /// The final chunk is sized to the *exact* remaining blocks — never rounded to an
    /// arbitrary byte remainder (FR-TEST-5). Because a device is an integer number of
    /// logical blocks, every chunk (including the last) is a whole number of blocks.
    ///
    /// - Throws: ``ChunkPlanError`` if `ioSizeBytes` is not a positive multiple of the
    ///   device's `logicalBlockSize`.
    public func chunkPlan() throws -> [Chunk] {
        let blockSize = device.logicalBlockSize
        guard ioSizeBytes > 0 else {
            throw ChunkPlanError.ioSizeNotPositive(ioSizeBytes: ioSizeBytes)
        }
        guard ioSizeBytes % blockSize == 0 else {
            throw ChunkPlanError.ioSizeNotBlockAligned(ioSizeBytes: ioSizeBytes, logicalBlockSize: blockSize)
        }

        let blocksPerChunk = UInt64(ioSizeBytes / blockSize)
        let totalBlocks = device.blockCount

        var chunks: [Chunk] = []
        var offsetBlocks: UInt64 = 0
        var index = 0
        while offsetBlocks < totalBlocks {
            let remaining = totalBlocks - offsetBlocks
            let thisBlocks = min(blocksPerChunk, remaining)   // final chunk = exact remainder
            chunks.append(Chunk(index: index,
                                byteOffset: offsetBlocks * UInt64(blockSize),
                                byteLength: Int(thisBlocks) * blockSize,
                                startBlock: offsetBlocks,
                                blockCount: thisBlocks))
            offsetBlocks += thisBlocks
            index += 1
        }
        return chunks
    }
}
