//
//  InMemoryBlockDeviceTests.swift
//  Proves the in-memory harness itself is sound (Step 2 gate): bit-for-bit
//  round-trips on both 512-byte and 4096-byte geometries, and that fault injection
//  can force a read error, a write error, and a silent (verify-mismatch) corruption.
//
//  The Core types are compiled directly into this test target (Core/ is a member of
//  both the helper and the test targets), so no `@testable import` is needed.
//

import Testing
import Foundation

struct InMemoryBlockDeviceTests {

    // MARK: Round-trip (gate: read/write on 512 B and 4096 B)

    @Test func roundTrip512() throws { try roundTrip(blockSize: 512, blocks: 2048) }   // 1 MiB
    @Test func roundTrip4096() throws { try roundTrip(blockSize: 4096, blocks: 512) }  // 2 MiB

    /// Fill a known pseudo-random pattern, write it through `write` (in several
    /// chunks, to exercise non-zero offsets), read it back through `read`, and assert
    /// bit-for-bit equality.
    private func roundTrip(blockSize: Int, blocks: UInt64) throws {
        let device = InMemoryBlockDevice(logicalBlockSize: blockSize, blockCount: blocks)
        let total = Int(blocks) * blockSize

        var expected = [UInt8](repeating: 0, count: total)
        fillPseudoRandom(&expected, seed: 0xDEAD_BEEF_CAFE_F00D)

        let chunkBytes = blockSize * 4
        var offset = 0
        while offset < total {
            let n = min(chunkBytes, total - offset)
            let piece = Array(expected[offset ..< offset + n])
            try piece.withUnsafeBytes { _ = try device.write($0, atByteOffset: UInt64(offset)) }
            offset += n
        }

        var readBack = [UInt8](repeating: 0, count: total)
        try readBack.withUnsafeMutableBytes { _ = try device.read(into: $0, atByteOffset: 0) }

        #expect(readBack == expected)
        #expect(device.snapshot() == expected)
    }

    // MARK: Fault injection — read error (gate)

    @Test func readFaultThrowsExactError() throws {
        let blockSize = 512
        let device = InMemoryBlockDevice(logicalBlockSize: blockSize, blockCount: 16)
        device.injectReadFault(blocks: 4 ..< 6)

        // A read overlapping blocks 4..<6 throws the exact typed error.
        var buf = [UInt8](repeating: 0, count: blockSize * 4)   // covers blocks 3..<7
        let offset = UInt64(3 * blockSize)
        #expect(throws: DeviceIOError.readError(atByteOffset: offset, length: blockSize * 4)) {
            try buf.withUnsafeMutableBytes { try device.read(into: $0, atByteOffset: offset) }
        }

        // A read that avoids the faulted range succeeds (would throw and fail the test otherwise).
        var ok = [UInt8](repeating: 0, count: blockSize)        // block 0
        try ok.withUnsafeMutableBytes { _ = try device.read(into: $0, atByteOffset: 0) }
    }

    // MARK: Fault injection — write error (gate)

    @Test func writeFaultThrowsAndLeavesStoreUnchanged() throws {
        let blockSize = 4096
        let device = InMemoryBlockDevice(logicalBlockSize: blockSize, blockCount: 8)
        let before = device.snapshot()
        device.injectWriteFault(blocks: 2 ..< 3)

        let payload = [UInt8](repeating: 0xAB, count: blockSize)   // target block 2
        let offset = UInt64(2 * blockSize)
        #expect(throws: DeviceIOError.writeError(atByteOffset: offset, length: blockSize)) {
            try payload.withUnsafeBytes { try device.write($0, atByteOffset: offset) }
        }
        // Nothing was persisted.
        #expect(device.snapshot() == before)
    }

    // MARK: Fault injection — silent corruption => verify mismatch (gate)

    @Test func silentCorruptionCausesReadBackMismatch() throws {
        let blockSize = 512
        let device = InMemoryBlockDevice(logicalBlockSize: blockSize, blockCount: 8)
        device.injectSilentCorruption(blocks: 2 ..< 3)   // corrupt only block 2

        let written = [UInt8](repeating: 0x5A, count: blockSize * 4)   // blocks 0..<4
        try written.withUnsafeBytes { _ = try device.write($0, atByteOffset: 0) }

        var readBack = [UInt8](repeating: 0, count: blockSize * 4)
        try readBack.withUnsafeMutableBytes { _ = try device.read(into: $0, atByteOffset: 0) }

        // The write "succeeded", but read-back differs — exactly what the Step 8
        // read-verify will flag as a mismatch (NFR-REL-8, single-bit difference).
        #expect(readBack != written)

        // The difference is confined to block 2; neighbours are intact.
        func block(_ i: Int, of bytes: [UInt8]) -> ArraySlice<UInt8> {
            bytes[i * blockSize ..< (i + 1) * blockSize]
        }
        #expect(block(0, of: readBack) == block(0, of: written))
        #expect(block(1, of: readBack) == block(1, of: written))
        #expect(block(2, of: readBack) != block(2, of: written))
        #expect(block(3, of: readBack) == block(3, of: written))
    }

    // MARK: Alignment / range guards

    @Test func misalignedOffsetIsRejected() throws {
        let device = InMemoryBlockDevice(logicalBlockSize: 512, blockCount: 8)
        var buf = [UInt8](repeating: 0, count: 512)
        #expect(throws: DeviceIOError.misaligned(atByteOffset: 100, length: 512, logicalBlockSize: 512)) {
            try buf.withUnsafeMutableBytes { try device.read(into: $0, atByteOffset: 100) }
        }
    }

    @Test func outOfRangeIsRejected() throws {
        let device = InMemoryBlockDevice(logicalBlockSize: 512, blockCount: 8)   // 4096 bytes total
        var buf = [UInt8](repeating: 0, count: 512)
        // Offset 4096 is exactly at the end: a 512-byte read there is out of range.
        #expect(throws: DeviceIOError.outOfRange(atByteOffset: 4096, length: 512, deviceByteCount: 4096)) {
            try buf.withUnsafeMutableBytes { try device.read(into: $0, atByteOffset: 4096) }
        }
    }

    // MARK: Local deterministic fill (SplitMix64 finalizer per byte)

    private func fillPseudoRandom(_ bytes: inout [UInt8], seed: UInt64) {
        for i in bytes.indices {
            var z = seed &+ (UInt64(i) &+ 1) &* 0x9E37_79B9_7F4A_7C15
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z = z ^ (z >> 31)
            bytes[i] = UInt8(truncatingIfNeeded: z)
        }
    }
}
