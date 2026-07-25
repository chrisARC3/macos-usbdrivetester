//
//  InMemoryBlockDevice.swift
//  Core — a fully in-memory RawBlockDevice for deterministic, host-only testing.
//
//  Backs the device with a flat byte array sized `logicalBlockSize * blockCount`
//  and adds fault-injection hooks so the failure-mode tests of Steps 8 and 10 can
//  force read errors, write errors, and silent (verify-mismatch) corruption without
//  any real hardware. Parameterized block size lets the same tests run over 512-byte
//  and 4096-byte geometries (NFR-COMPAT-5).
//
//  Not thread-safe: a run drives one device from a single task, matching the
//  one-chunk-in-flight model (NFR-REL-4). Pure Foundation; no privilege.
//

import Foundation

public final class InMemoryBlockDevice: RawBlockDevice {

    public let logicalBlockSize: Int
    public let blockCount: UInt64

    /// Flat backing store, exactly `byteCount` bytes.
    private var storage: [UInt8]

    /// Block ranges (in block units) whose reads fail, whose writes fail, and whose
    /// writes silently corrupt the persisted bytes.
    private var readFaults: [Range<UInt64>] = []
    private var writeFaults: [Range<UInt64>] = []
    private var corruptionFaults: [Range<UInt64>] = []

    /// Create a zero-filled device of `blockCount` blocks of `logicalBlockSize` bytes.
    public init(logicalBlockSize: Int, blockCount: UInt64) {
        precondition(logicalBlockSize > 0, "logicalBlockSize must be positive")
        self.logicalBlockSize = logicalBlockSize
        self.blockCount = blockCount
        self.storage = [UInt8](repeating: 0, count: Int(blockCount) * logicalBlockSize)
    }

    // MARK: RawBlockDevice

    @discardableResult
    public func read(into buffer: UnsafeMutableRawBufferPointer, atByteOffset offset: UInt64) throws -> Int {
        let count = buffer.count
        try validate(offset: offset, count: count)
        if count == 0 { return 0 }

        if intersects(readFaults, offset: offset, count: count) {
            throw DeviceIOError.readError(atByteOffset: offset, length: count)
        }

        let start = Int(offset)
        storage.withUnsafeBytes { raw in
            buffer.baseAddress!.copyMemory(from: raw.baseAddress! + start, byteCount: count)
        }
        return count
    }

    @discardableResult
    public func write(_ buffer: UnsafeRawBufferPointer, atByteOffset offset: UInt64) throws -> Int {
        let count = buffer.count
        try validate(offset: offset, count: count)
        if count == 0 { return 0 }

        if intersects(writeFaults, offset: offset, count: count) {
            throw DeviceIOError.writeError(atByteOffset: offset, length: count)
        }

        let start = Int(offset)
        storage.withUnsafeMutableBytes { raw in
            (raw.baseAddress! + start).copyMemory(from: buffer.baseAddress!, byteCount: count)
        }

        // Silent corruption: the write "succeeds" (bytes are stored and the call
        // returns `count`), but one bit is flipped in each overlapping block so a
        // later read-verify (Step 8) detects a mismatch on exactly those blocks.
        applyCorruption(offset: offset, count: count)
        return count
    }

    // MARK: Fault injection

    /// Make reads overlapping `blocks` throw ``DeviceIOError/readError``.
    public func injectReadFault(blocks: Range<UInt64>) { readFaults.append(blocks) }

    /// Make writes overlapping `blocks` throw ``DeviceIOError/writeError`` (nothing stored).
    public func injectWriteFault(blocks: Range<UInt64>) { writeFaults.append(blocks) }

    /// Make writes overlapping `blocks` succeed but silently corrupt one bit per
    /// overlapping block, so a subsequent read-verify mismatches.
    public func injectSilentCorruption(blocks: Range<UInt64>) { corruptionFaults.append(blocks) }

    // MARK: Test helpers

    /// A copy of the entire backing store — for before/after comparisons (e.g. the
    /// Step 8 bit-for-bit non-destructiveness check).
    public func snapshot() -> [UInt8] { storage }

    // MARK: Internals

    private func validate(offset: UInt64, count: Int) throws {
        let bs = UInt64(logicalBlockSize)
        guard offset % bs == 0, UInt64(count) % bs == 0 else {
            throw DeviceIOError.misaligned(atByteOffset: offset, length: count, logicalBlockSize: logicalBlockSize)
        }
        // Overflow-safe range check: offset <= byteCount and count <= byteCount - offset.
        let total = byteCount
        guard offset <= total, UInt64(count) <= total - offset else {
            throw DeviceIOError.outOfRange(atByteOffset: offset, length: count, deviceByteCount: total)
        }
    }

    /// Does the byte request `[offset, offset+count)` overlap any block range in
    /// `ranges`? (`count` is block-aligned, so the byte→block conversion is exact.)
    private func intersects(_ ranges: [Range<UInt64>], offset: UInt64, count: Int) -> Bool {
        guard !ranges.isEmpty else { return false }
        let requested = blockRange(offset: offset, count: count)
        for r in ranges where r.overlaps(requested) { return true }
        return false
    }

    /// Flip the low bit of the first byte of every corrupted block overlapping this write.
    private func applyCorruption(offset: UInt64, count: Int) {
        guard !corruptionFaults.isEmpty else { return }
        let bs = UInt64(logicalBlockSize)
        let requested = blockRange(offset: offset, count: count)
        storage.withUnsafeMutableBytes { raw in
            let base = raw.bindMemory(to: UInt8.self)
            for fault in corruptionFaults {
                let lo = max(fault.lowerBound, requested.lowerBound)
                let hi = min(fault.upperBound, requested.upperBound)
                var block = lo
                while block < hi {
                    base[Int(block * bs)] ^= 0x01
                    block += 1
                }
            }
        }
    }

    private func blockRange(offset: UInt64, count: Int) -> Range<UInt64> {
        let bs = UInt64(logicalBlockSize)
        return (offset / bs) ..< ((offset + UInt64(count)) / bs)
    }
}
