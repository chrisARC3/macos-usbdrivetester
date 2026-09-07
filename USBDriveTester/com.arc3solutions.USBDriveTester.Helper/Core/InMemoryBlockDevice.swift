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
//  Step 12 adds a fourth hook of a different shape. The first three are faults *at a place* and
//  take a block range; `injectDeviceLoss()` takes none, because the device leaving the bus is
//  not a property of any range. That distinction is the one the product got wrong on 2026-08-06.
//
//  Step 12's mutation round added a fifth and a sixth — `injectShortRead` and `injectShortWrite`
//  — which are faults at a place again, but ones that **partly succeed**. They exist because a
//  mutation moving `.shortTransfer` from block-failure to device-loss in
//  `RetentionTestEngine.classify` survived all 1,288 tests. Nothing could drive a short transfer
//  through the engine: the only device that could produce one was `FileDescriptorBlockDevice`,
//  and its own tests pin what *produces* a short transfer, never what the engine *does* with one.
//  The gap was in this fake, not in the engine.
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

    /// Block ranges whose reads and writes move only part of what was asked and then throw
    /// ``DeviceIOError/shortTransfer``. Kept apart from the three above because a short transfer
    /// is not a refusal: bytes really do move before it throws, and a test that did not see them
    /// move would be testing a fake the real device does not resemble.
    private var shortReadFaults: [ShortTransferFault] = []
    private var shortWriteFaults: [ShortTransferFault] = []

    /// Calls still to succeed before the device is lost, or `nil` if no loss is pending.
    ///
    /// Not a `Range`, and that is the point of it: every other fault here is a fault *at a
    /// place*, and device loss is the absence of the place. Once it reaches zero it stays
    /// there — there is no un-inject, because a de-enumerated device does not come back on the
    /// same descriptor (Step 12).
    private var callsBeforeLoss: Int?

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
        try checkDeviceLoss(offset: offset, count: count)

        if intersects(readFaults, offset: offset, count: count) {
            throw DeviceIOError.readError(atByteOffset: offset, length: count)
        }

        let start = Int(offset)

        // A short read delivers its prefix and *then* throws, exactly as the real one does: there,
        // `transferred` bytes are already in the caller's buffer when the guard at the bottom of
        // the loop fires. A fake that threw without copying would let a bug that reads the
        // untouched tail of the buffer pass here and fail on hardware.
        if let actual = shortTransferBytes(shortReadFaults, offset: offset, count: count) {
            storage.withUnsafeBytes { raw in
                buffer.baseAddress!.copyMemory(from: raw.baseAddress! + start, byteCount: actual)
            }
            throw DeviceIOError.shortTransfer(atByteOffset: offset, expected: count, actual: actual)
        }

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
        try checkDeviceLoss(offset: offset, count: count)

        if intersects(writeFaults, offset: offset, count: count) {
            throw DeviceIOError.writeError(atByteOffset: offset, length: count)
        }

        let start = Int(offset)

        // A short write *persists* its prefix and then throws — the half-written chunk that makes
        // an interrupted write-back the phase that matters (see `DeviceLossPhase.writingBack`).
        // No corruption is applied: `applyCorruption` models a write that reported success.
        if let actual = shortTransferBytes(shortWriteFaults, offset: offset, count: count) {
            storage.withUnsafeMutableBytes { raw in
                (raw.baseAddress! + start).copyMemory(from: buffer.baseAddress!, byteCount: actual)
            }
            throw DeviceIOError.shortTransfer(atByteOffset: offset, expected: count, actual: actual)
        }

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

    /// Make reads overlapping `blocks` deliver only their first `bytes` bytes and then throw
    /// ``DeviceIOError/shortTransfer``.
    ///
    /// Not the same fault as ``injectReadFault(blocks:)`` and not a milder version of it. A read
    /// fault is the device refusing; a short read is the device agreeing and running out. The
    /// engine must record both against the drive and neither as the drive's absence — which is
    /// the thing nothing pinned until Step 12's mutation round asked.
    ///
    /// - Parameters:
    ///   - blocks: which block range fires the fault, matched the same way as the other three.
    ///   - bytes: how much of the request completes. Clamped to the request's length, so a fault
    ///     declared wider than the request cannot claim more bytes moved than were asked for; at
    ///     or above that length the request simply completes, because a transfer that moved
    ///     everything is not short. Real hardware gives back whole blocks, but nothing here
    ///     requires that: ``DeviceIOError/shortTransfer`` does not, so neither does the fake.
    public func injectShortRead(blocks: Range<UInt64>, transferring bytes: Int) {
        precondition(bytes >= 0, "bytes must not be negative")
        shortReadFaults.append(ShortTransferFault(blocks: blocks, bytes: bytes))
    }

    /// Make writes overlapping `blocks` persist only their first `bytes` bytes and then throw
    /// ``DeviceIOError/shortTransfer``. See ``injectShortRead(blocks:transferring:)``.
    public func injectShortWrite(blocks: Range<UInt64>, transferring bytes: Int) {
        precondition(bytes >= 0, "bytes must not be negative")
        shortWriteFaults.append(ShortTransferFault(blocks: blocks, bytes: bytes))
    }

    /// Take the device off the bus: from then on **every** read and write throws
    /// ``DeviceIOError/deviceLost``, whatever it addresses (Step 12, FR-DEV-8).
    ///
    /// Deliberately not expressible as `injectReadFault(blocks: 0 ..< blockCount)`, which would
    /// simulate a drive with every block bad — the exact misreading Step 12 exists to stop the
    /// product making. What it models is the 2026-08-06 incident: a descriptor that answers
    /// `ENXIO` to everything, offset 0 included.
    ///
    /// - Parameter afterCalls: how many further reads or writes complete first. `0` — the
    ///   default — loses the device immediately, so even the first read of a run fails. Calls
    ///   are counted once they have passed validation and not been lost; a call that then hits
    ///   an injected range fault has still been counted, because the device saw it.
    public func injectDeviceLoss(afterCalls: Int = 0) {
        precondition(afterCalls >= 0, "afterCalls must not be negative")
        callsBeforeLoss = afterCalls
    }

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

    /// Throw if the device has been lost, and otherwise count this call towards a pending loss.
    ///
    /// Called **after** validation and after the zero-length early return, so that this fake and
    /// `FileDescriptorBlockDevice` disagree about nothing: there, alignment and range are checked
    /// before any syscall and a zero-length request never reaches one, so a misaligned request to
    /// a dead device is an addressing fault and a zero-length one quietly moves nothing. Both are
    /// true here for the same reason and not by coincidence.
    private func checkDeviceLoss(offset: UInt64, count: Int) throws {
        guard let remaining = callsBeforeLoss else { return }
        guard remaining == 0 else {
            callsBeforeLoss = remaining - 1
            return
        }
        throw DeviceIOError.deviceLost(atByteOffset: offset, length: count)
    }

    /// A request overlapping `blocks` moves `bytes` bytes and stops.
    private struct ShortTransferFault {
        let blocks: Range<UInt64>
        let bytes: Int
    }

    /// How many bytes of this request complete before it throws, or `nil` if it completes.
    ///
    /// The first overlapping fault wins, matching ``intersects(_:offset:count:)``, which stops at
    /// the first overlap too. Returns `nil` when the clamped count is the whole request, so
    /// `transferring:` at or above the request length is a complete transfer rather than a
    /// `shortTransfer(expected: n, actual: n)` — an error that would be a lie about itself.
    private func shortTransferBytes(_ faults: [ShortTransferFault],
                                    offset: UInt64, count: Int) -> Int? {
        guard !faults.isEmpty else { return nil }
        let requested = blockRange(offset: offset, count: count)
        for fault in faults where fault.blocks.overlaps(requested) {
            let actual = min(fault.bytes, count)
            return actual < count ? actual : nil
        }
        return nil
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
