//
//  ChunkPlanTests.swift
//  The lazy chunk plan (NFR-PERF-2) and the exact-remainder final chunk (FR-TEST-5) at scales
//  no in-memory device can represent.
//
//  `RetentionTestEngineTests` still covers the small, exactly-enumerated plans through
//  `chunkPlan()`; those tests are unchanged by Step 7 and are the clearest statement of a
//  plan's precise shape. This file covers what they cannot reach:
//
//    * `disk4` and `disk8`'s **real** geometries, rather than invented awkward sizes.
//      `InMemoryBlockDevice` allocates its entire backing store, so it cannot represent a
//      22 TB device at all — but a `ChunkPlan` over that geometry costs four integers.
//    * That the plan is genuinely lazy, proved by building one whose materialisation would
//      need ~176 TB of RAM and then using it.
//

import Testing
import Foundation

struct ChunkPlanTests {

    private let fourMiB = 4 << 20

    // MARK: - The real hardware geometries (measured 2026-08-02)

    /// `disk4`: 1,953,525,168 blocks of 512 B at 4 MiB chunks.
    @Test func disk4PlanMatchesItsMeasuredGeometry() throws {
        let plan = try ChunkPlan(logicalBlockSize: 512,
                                 blockCount: 1_953_525_168,
                                 ioSizeBytes: fourMiB)

        #expect(plan.blocksPerChunk == 8192)
        #expect(plan.chunkCount == 238_468)
        #expect(plan.totalByteCount == 1_000_204_886_016)

        let final = try #require(plan.finalChunk)
        #expect(final.blockCount == 3_504, "the exact remainder, not a rounded value (FR-TEST-5)")
        #expect(final.byteLength == 3_504 * 512)
        #expect(final.byteLength == 1_794_048)
        #expect(final.index == 238_467)
        #expect(final.startBlock + final.blockCount == plan.blockCount, "covers the last block")
    }

    /// `disk8`: 42,970,644,479 blocks — **ten times past 2³²**, and an odd number, so the final
    /// chunk lands one block short of full. This is the geometry an in-memory device cannot
    /// represent at any price.
    @Test func disk8PlanMatchesItsMeasuredGeometry() throws {
        let plan = try ChunkPlan(logicalBlockSize: 512,
                                 blockCount: 42_970_644_479,
                                 ioSizeBytes: fourMiB)

        #expect(plan.blockCount > UInt64(UInt32.max), "past 2^32 — NFR-COMPAT-6")
        #expect(plan.chunkCount == 5_245_440)
        #expect(plan.totalByteCount == 22_000_969_973_248)

        let final = try #require(plan.finalChunk)
        #expect(final.blockCount == 8_191, "one block short of a full 8,192-block chunk")
        #expect(final.byteLength == 4_193_792)
        #expect(final.startBlock + final.blockCount == plan.blockCount)
    }

    /// Full traversal of `disk8`'s plan, accumulating counters only. Proves the tiling has no
    /// gaps and no overlaps across 5.2 million chunks — and that iterating that many costs
    /// nothing but time.
    @Test func disk8PlanTilesTheWholeDeviceWithoutGapsOrOverlaps() throws {
        let plan = try ChunkPlan(logicalBlockSize: 512,
                                 blockCount: 42_970_644_479,
                                 ioSizeBytes: fourMiB)

        var expectedNextBlock: UInt64 = 0
        var chunks: UInt64 = 0
        var coveredBytes: UInt64 = 0
        var shortChunks = 0

        for chunk in plan {
            #expect(chunk.startBlock == expectedNextBlock)
            #expect(chunk.blockCount > 0)
            if chunk.blockCount != plan.blocksPerChunk { shortChunks += 1 }
            expectedNextBlock += chunk.blockCount
            coveredBytes += UInt64(chunk.byteLength)
            chunks += 1
        }

        #expect(chunks == plan.chunkCount)
        #expect(expectedNextBlock == plan.blockCount, "exact coverage, first block to last")
        #expect(coveredBytes == plan.totalByteCount)
        #expect(shortChunks == 1, "only the final chunk may be short")
    }

    // MARK: - Laziness, proved by making materialisation impossible

    /// A plan over an 18-exabyte device: 4,398,046,511,104 chunks, which as an array of
    /// 40-byte `Chunk`s would be **~176 TB**. Constructing it, asking its size, and reading
    /// chunks from either end all complete instantly — which they could not do if the plan
    /// were built eagerly.
    ///
    /// This is the assertion that would fail if `ChunkPlan` ever went back to storing its
    /// chunks, and it fails by exhausting memory rather than by reporting a wrong value.
    @Test func aPlanTooLargeToMaterialiseIsStillFullyUsable() throws {
        let blocks = UInt64.max / 512                       // 36,028,797,018,963,967
        let plan = try ChunkPlan(logicalBlockSize: 512,
                                 blockCount: blocks,
                                 ioSizeBytes: fourMiB)

        #expect(plan.chunkCount == 4_398_046_511_104)

        // What an array of these would cost, stated so the number is not abstract.
        let bytesIfMaterialised = plan.chunkCount * UInt64(MemoryLayout<Chunk>.stride)
        #expect(bytesIfMaterialised > 175_000_000_000_000)

        let first = try #require(plan.chunk(at: 0))
        #expect(first.startBlock == 0)
        #expect(first.blockCount == 8192)

        let last = try #require(plan.finalChunk)
        #expect(last.startBlock + last.blockCount == blocks)
        #expect(last.blockCount == 8_191)

        // And the iterator starts producing immediately rather than after any preparation.
        var iterator = plan.makeIterator()
        #expect(iterator.next()?.startBlock == 0)
        #expect(iterator.next()?.startBlock == 8192)
    }

    // MARK: - Random access agrees with traversal

    @Test func chunkAtIndexAgreesWithIteration() throws {
        let plan = try ChunkPlan(logicalBlockSize: 512, blockCount: 20, ioSizeBytes: 4096)

        let iterated = Array(plan)
        #expect(iterated.count == Int(plan.chunkCount))
        for (index, chunk) in iterated.enumerated() {
            #expect(plan.chunk(at: UInt64(index)) == chunk)
        }
        #expect(plan.chunk(at: plan.chunkCount) == nil, "one past the end")
        #expect(plan.finalChunk == iterated.last)
    }

    /// The 4096-byte geometry (NFR-COMPAT-5) — no hardware here reports it, so it exists only
    /// in tests.
    @Test func fourKilobyteBlocksPlanCorrectly() throws {
        let plan = try ChunkPlan(logicalBlockSize: 4096, blockCount: 2500, ioSizeBytes: fourMiB)

        #expect(plan.blocksPerChunk == 1024)
        #expect(plan.chunkCount == 3)
        let final = try #require(plan.finalChunk)
        #expect(final.blockCount == 452)
        #expect(final.byteLength == 452 * 4096)
    }

    // MARK: - Construction from geometry

    @Test func aPlanCanBeBuiltStraightFromDeviceGeometry() throws {
        let geometry = DeviceGeometry(logicalBlockSize: 512, blockCount: 1_953_525_168)
        let plan = try ChunkPlan(geometry: geometry, ioSizeBytes: fourMiB)

        #expect(plan.logicalBlockSize == 512)
        #expect(plan.blockCount == 1_953_525_168)
        #expect(plan.chunkCount == 238_468)
    }

    // MARK: - Edges and rejections

    @Test func anEmptyDeviceHasNoChunksAndNoFinalChunk() throws {
        let plan = try ChunkPlan(logicalBlockSize: 512, blockCount: 0, ioSizeBytes: 4096)
        #expect(plan.chunkCount == 0)
        #expect(plan.finalChunk == nil)
        #expect(plan.chunk(at: 0) == nil)
        #expect(Array(plan).isEmpty)
    }

    @Test func aDeviceSmallerThanOneChunkIsASinglePartialChunk() throws {
        let plan = try ChunkPlan(logicalBlockSize: 512, blockCount: 3, ioSizeBytes: 4096)
        #expect(plan.chunkCount == 1)
        let only = try #require(plan.finalChunk)
        #expect(only.blockCount == 3)
        #expect(only.byteLength == 1536)
    }

    @Test func anExactMultipleHasNoShortFinalChunk() throws {
        let plan = try ChunkPlan(logicalBlockSize: 512, blockCount: 24, ioSizeBytes: 4096)
        #expect(plan.chunkCount == 3)
        #expect(plan.finalChunk?.blockCount == 8)
        #expect(Array(plan).allSatisfy { $0.blockCount == 8 })
    }

    @Test func anInvalidIOSizeIsRejectedAtConstruction() {
        #expect(throws: ChunkPlanError.ioSizeNotPositive(ioSizeBytes: 0)) {
            _ = try ChunkPlan(logicalBlockSize: 512, blockCount: 10, ioSizeBytes: 0)
        }
        #expect(throws: ChunkPlanError.ioSizeNotBlockAligned(ioSizeBytes: 512,
                                                              logicalBlockSize: 4096)) {
            _ = try ChunkPlan(logicalBlockSize: 4096, blockCount: 10, ioSizeBytes: 512)
        }
    }

    // MARK: - The engine's two accessors agree

    /// `chunkPlan()` is kept for tests and diagnostics; `chunks()` is what a run iterates. They
    /// must describe the same plan, or the Step 2 tests would be validating something the run
    /// does not do.
    @Test func theEagerAndLazyAccessorsDescribeTheSamePlan() throws {
        let device = InMemoryBlockDevice(logicalBlockSize: 512, blockCount: 20)
        let engine = RetentionTestEngine(device: device, ioSizeBytes: 4096)

        let eager = try engine.chunkPlan()
        let lazyPlan = try engine.chunks()

        #expect(eager == Array(lazyPlan))
        #expect(UInt64(eager.count) == lazyPlan.chunkCount)
        #expect(eager.last == lazyPlan.finalChunk)
    }
}
