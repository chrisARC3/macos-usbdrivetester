//
//  ChunkBuffersTests.swift
//  NFR-PERF-1: peak buffer memory ~2x the I/O size, and never scaling with device capacity.
//
//  The most important case in this file is `theTwoBuffersAreDistinctMemory`. If `original`
//  and `verify` ever aliased, Step 8's cycle would compare a buffer against itself and
//  succeed unconditionally — the same shape of vacuous pass that FR-TEST-9 exists to prevent
//  at the caching layer, arriving instead through a pointer. Nothing else in the system would
//  notice: every run would report a clean drive.
//

import Testing
import Foundation

struct ChunkBuffersTests {

    private let fourMiB = 4 << 20

    // MARK: - Exactly two buffers, exactly the I/O size

    @Test func aPairIsTwoBuffersOfTheRequestedSize() throws {
        let buffers = try ChunkBuffers(ioSizeBytes: fourMiB)

        #expect(ChunkBuffers.bufferCount == 2)
        #expect(buffers.capacityBytes == fourMiB)
        #expect(buffers.totalAllocatedBytes == 2 * fourMiB)
        #expect(buffers.original.count == fourMiB)
        #expect(buffers.verify.count == fourMiB)
    }

    /// Every I/O size FR-CTRL-8 offers, each allocating exactly twice itself.
    @Test(arguments: [1 << 20, 2 << 20, 4 << 20, 8 << 20])
    func everyOfferedIOSizeAllocatesExactlyTwiceItself(ioSize: Int) throws {
        let buffers = try ChunkBuffers(ioSizeBytes: ioSize)
        #expect(buffers.totalAllocatedBytes == 2 * ioSize)
        #expect(buffers.isCorrectlyAligned)
    }

    // MARK: - THE case: the two buffers must not be the same memory

    /// If these aliased, FR-TEST-3's comparison would compare a buffer with itself and pass
    /// for every chunk of every drive, including a failing one.
    @Test func theTwoBuffersAreDistinctMemory() throws {
        let buffers = try ChunkBuffers(ioSizeBytes: fourMiB)

        #expect(buffers.original.baseAddress != buffers.verify.baseAddress)

        // Proven behaviourally as well as by address, because an address comparison would
        // still pass if the two views overlapped without sharing a base.
        memset(buffers.original.baseAddress!, 0xAA, fourMiB)
        memset(buffers.verify.baseAddress!, 0x55, fourMiB)

        let firstOriginal = buffers.original.load(fromByteOffset: 0, as: UInt8.self)
        let lastOriginal = buffers.original.load(fromByteOffset: fourMiB - 1, as: UInt8.self)
        let firstVerify = buffers.verify.load(fromByteOffset: 0, as: UInt8.self)
        let lastVerify = buffers.verify.load(fromByteOffset: fourMiB - 1, as: UInt8.self)

        #expect(firstOriginal == 0xAA)
        #expect(lastOriginal == 0xAA, "writing verify must not have run into original")
        #expect(firstVerify == 0x55)
        #expect(lastVerify == 0x55)
    }

    // MARK: - Independent of device capacity, by construction

    /// The guarantee NFR-PERF-1/2 actually needs, stated the way the type enforces it:
    /// `ChunkBuffers` has no parameter through which a device's size could reach it.
    ///
    /// The contrast is the point. At 4 MiB, `disk4` is 238,468 chunks and `disk8` is
    /// 5,245,440 — a 22x difference in the work to be done — and the memory held while doing
    /// it is byte-for-byte identical.
    @Test func capacityCannotInfluenceAllocationBecauseItIsNotAnInput() throws {
        let disk4Blocks: UInt64 = 1_953_525_168        // 1.0 TB, measured
        let disk8Blocks: UInt64 = 42_970_644_479       // 22 TB, measured
        let blocksPerChunk = UInt64(fourMiB / 512)

        let disk4Chunks = (disk4Blocks + blocksPerChunk - 1) / blocksPerChunk
        let disk8Chunks = (disk8Blocks + blocksPerChunk - 1) / blocksPerChunk
        #expect(disk4Chunks == 238_468)
        #expect(disk8Chunks == 5_245_440)
        #expect(disk8Chunks / disk4Chunks == 21)       // 22x the work, to the nearest whole

        // Same call, because there is no other call to make.
        let forDisk4 = try ChunkBuffers(ioSizeBytes: fourMiB)
        let forDisk8 = try ChunkBuffers(ioSizeBytes: fourMiB)

        #expect(forDisk4.totalAllocatedBytes == forDisk8.totalAllocatedBytes)
        #expect(forDisk8.totalAllocatedBytes == 2 * fourMiB)
    }

    // MARK: - Page alignment

    @Test func buffersArePageAlignedByDefault() throws {
        let buffers = try ChunkBuffers(ioSizeBytes: fourMiB)

        #expect(buffers.alignment == Int(getpagesize()))
        #expect(buffers.alignment == 16384, "Apple Silicon page size, measured 2026-08-02")
        #expect(buffers.isCorrectlyAligned)
        #expect(UInt(bitPattern: buffers.original.baseAddress!) % 16384 == 0)
        #expect(UInt(bitPattern: buffers.verify.baseAddress!) % 16384 == 0)
    }

    @Test func anExplicitAlignmentIsHonoured() throws {
        let buffers = try ChunkBuffers(ioSizeBytes: fourMiB, alignment: 4096)
        #expect(buffers.alignment == 4096)
        #expect(buffers.isCorrectlyAligned)
    }

    // MARK: - The short final chunk (FR-TEST-5)

    /// The last chunk is the exact remaining blocks, so it is shorter than the I/O size —
    /// 3,504 blocks for `disk4` and 8,191 for `disk8`, both measured. Reading a full I/O size
    /// there would run past the end of the device.
    @Test func prefixViewsServeTheShortFinalChunk() throws {
        let buffers = try ChunkBuffers(ioSizeBytes: fourMiB)

        let disk4FinalChunk = 3_504 * 512               // 1,794,048 bytes
        let disk8FinalChunk = 8_191 * 512               // 4,193,792 bytes

        #expect(buffers.original(byteCount: disk4FinalChunk).count == disk4FinalChunk)
        #expect(buffers.verify(byteCount: disk4FinalChunk).count == disk4FinalChunk)
        #expect(buffers.original(byteCount: disk8FinalChunk).count == disk8FinalChunk)

        // A prefix starts where the full buffer starts — it is a view, not a copy.
        #expect(buffers.original(byteCount: disk4FinalChunk).baseAddress
                == buffers.original.baseAddress)
        // And the full capacity is still available.
        #expect(buffers.original(byteCount: fourMiB).count == fourMiB)
    }

    // MARK: - Rejections

    @Test(arguments: [0, -1, -4096])
    func aNonPositiveIOSizeIsRejected(ioSize: Int) {
        #expect(throws: ChunkBufferError.ioSizeNotPositive(ioSizeBytes: ioSize)) {
            _ = try ChunkBuffers(ioSizeBytes: ioSize)
        }
    }

    @Test(arguments: [3, 100, 12288])
    func aNonPowerOfTwoAlignmentIsRejected(alignment: Int) {
        #expect(throws: ChunkBufferError.alignmentNotAPowerOfTwo(alignment: alignment)) {
            _ = try ChunkBuffers(ioSizeBytes: 4096, alignment: alignment)
        }
    }

    /// These strings reach the user, so they must name the corrective step rather than only
    /// the fault (NFR-USE-5).
    @Test func errorsExplainThemselves() {
        #expect(ChunkBufferError.ioSizeNotPositive(ioSizeBytes: 0).description.contains("positive"))
        #expect(ChunkBufferError.alignmentNotAPowerOfTwo(alignment: 3).description.contains("power of two"))

        let failure = ChunkBufferError.allocationFailed(bytesRequested: 8 << 20, errnoCode: ENOMEM)
        #expect(failure.description.contains("smaller I/O size"), "offers a way out")
    }
}

// MARK: - Instrumentation

/// Serialised because these assertions read process-wide counters. Nothing else in the suite
/// allocates `ChunkBuffers` today; if a future test does, it must either live here or the
/// assertions below must be loosened to deltas that tolerate concurrent allocation.
@Suite(.serialized)
struct ChunkBuffersInstrumentationTests {

    private let fourMiB = 4 << 20

    /// BUILD-PLAN 7.6's gate asks for peak buffer memory to be *instrumented and confirmed*,
    /// not merely reasoned about.
    @Test func peakAllocationTracksTwiceTheIOSizeAndFallsBackOnRelease() throws {
        ChunkBuffers.resetPeakAllocatedBytes()
        let baseline = ChunkBuffers.liveAllocatedBytes

        do {
            let buffers = try ChunkBuffers(ioSizeBytes: fourMiB)
            #expect(ChunkBuffers.liveAllocatedBytes == baseline + 2 * fourMiB)
            #expect(ChunkBuffers.peakAllocatedBytes >= baseline + 2 * fourMiB)
            _ = buffers.capacityBytes                       // keep it alive to here
        }

        #expect(ChunkBuffers.liveAllocatedBytes == baseline, "deinit released both buffers")
    }

    /// Running the whole of `disk8` would be 5,245,440 chunks. The peak must be the same as
    /// for one chunk, because the buffers are reused rather than accumulated — that is the
    /// difference between NFR-PERF-2 being satisfied and merely being intended.
    @Test func reusingOnePairAcrossManyChunksDoesNotAccumulate() throws {
        ChunkBuffers.resetPeakAllocatedBytes()
        let baseline = ChunkBuffers.liveAllocatedBytes

        let buffers = try ChunkBuffers(ioSizeBytes: fourMiB)
        let expected = baseline + 2 * fourMiB

        // Stand in for the per-chunk loop: touch both buffers repeatedly, as a run would.
        for chunk in 0 ..< 1_000 {
            memset(buffers.original.baseAddress!, Int32(chunk & 0xFF), 4096)
            memset(buffers.verify.baseAddress!, Int32(chunk & 0xFF), 4096)
            #expect(ChunkBuffers.liveAllocatedBytes == expected)
        }

        #expect(ChunkBuffers.peakAllocatedBytes == expected,
                "1,000 chunks must peak no higher than one chunk")
    }
}
