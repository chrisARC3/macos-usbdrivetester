//
//  RetentionTestEngineTests.swift
//  Exercises the Step 2 engine stub: the block-aligned chunk plan, with particular
//  attention to the exact-remainder final chunk (FR-TEST-5), on both 512 B and
//  4096 B geometries and for I/O sizes that do NOT divide the device evenly.
//

import Testing
import Foundation

struct RetentionTestEngineTests {

    // MARK: Final chunk = exact remaining blocks (FR-TEST-5)

    @Test func finalChunkIsExactRemainder512() throws {
        // 512-byte blocks, 4 KiB I/O => 8 blocks/chunk. 20 blocks => 8, 8, 4.
        let device = InMemoryBlockDevice(logicalBlockSize: 512, blockCount: 20)
        let plan = try RetentionTestEngine(device: device, ioSizeBytes: 4096).chunkPlan()

        #expect(plan.map(\.blockCount) == [8, 8, 4])
        #expect(plan.map(\.byteOffset) == [0, 4096, 8192])
        #expect(plan.map(\.byteLength) == [4096, 4096, 2048])
        try assertPlanInvariants(plan, device: device)
    }

    @Test func finalChunkIsExactRemainder4096() throws {
        // 4096-byte blocks, 4 MiB I/O => 1024 blocks/chunk. 2500 blocks => 1024, 1024, 452.
        let device = InMemoryBlockDevice(logicalBlockSize: 4096, blockCount: 2500)
        let plan = try RetentionTestEngine(device: device, ioSizeBytes: 4 << 20).chunkPlan()

        #expect(plan.count == 3)
        #expect(plan.map(\.blockCount) == [1024, 1024, 452])
        #expect(plan.last?.byteLength == 452 * 4096)
        try assertPlanInvariants(plan, device: device)
    }

    // MARK: Exact multiple => uniform chunks, no short final chunk

    @Test func exactMultipleHasUniformChunks() throws {
        let device = InMemoryBlockDevice(logicalBlockSize: 512, blockCount: 24)
        let plan = try RetentionTestEngine(device: device, ioSizeBytes: 4096).chunkPlan()   // 8/chunk

        #expect(plan.map(\.blockCount) == [8, 8, 8])
        try assertPlanInvariants(plan, device: device)
    }

    // MARK: Device smaller than one I/O => single partial chunk

    @Test func deviceSmallerThanIOSizeIsOneChunk() throws {
        let device = InMemoryBlockDevice(logicalBlockSize: 512, blockCount: 3)
        let plan = try RetentionTestEngine(device: device, ioSizeBytes: 4096).chunkPlan()   // 8/chunk

        #expect(plan.count == 1)
        #expect(plan[0].blockCount == 3)
        #expect(plan[0].byteLength == 3 * 512)
        try assertPlanInvariants(plan, device: device)
    }

    // MARK: Empty device => empty plan

    @Test func emptyDeviceHasEmptyPlan() throws {
        let device = InMemoryBlockDevice(logicalBlockSize: 512, blockCount: 0)
        let plan = try RetentionTestEngine(device: device, ioSizeBytes: 4096).chunkPlan()
        #expect(plan.isEmpty)
    }

    // MARK: Invalid I/O size

    @Test func nonBlockAlignedIOSizeThrows() throws {
        let device = InMemoryBlockDevice(logicalBlockSize: 4096, blockCount: 10)
        #expect(throws: ChunkPlanError.ioSizeNotBlockAligned(ioSizeBytes: 512, logicalBlockSize: 4096)) {
            _ = try RetentionTestEngine(device: device, ioSizeBytes: 512).chunkPlan()
        }
    }

    @Test func nonPositiveIOSizeThrows() throws {
        let device = InMemoryBlockDevice(logicalBlockSize: 512, blockCount: 10)
        #expect(throws: ChunkPlanError.ioSizeNotPositive(ioSizeBytes: 0)) {
            _ = try RetentionTestEngine(device: device, ioSizeBytes: 0).chunkPlan()
        }
    }

    // MARK: Shared invariants

    /// The plan must tile `[0, byteCount)` with no gaps or overlaps, be block-aligned,
    /// and index sequentially from 0.
    private func assertPlanInvariants(_ plan: [Chunk], device: RawBlockDevice) throws {
        let blockSize = UInt64(device.logicalBlockSize)
        var expectedOffsetBlocks: UInt64 = 0
        for (i, chunk) in plan.enumerated() {
            #expect(chunk.index == i)
            #expect(chunk.startBlock == expectedOffsetBlocks)
            #expect(chunk.byteOffset == expectedOffsetBlocks * blockSize)
            #expect(chunk.byteLength == Int(chunk.blockCount) * device.logicalBlockSize)
            #expect(chunk.blockCount > 0)
            expectedOffsetBlocks += chunk.blockCount
        }
        // Full, exact coverage of the device.
        #expect(expectedOffsetBlocks == device.blockCount)
        let coveredBytes = plan.reduce(UInt64(0)) { $0 + UInt64($1.byteLength) }
        #expect(coveredBytes == device.byteCount)
    }
}
