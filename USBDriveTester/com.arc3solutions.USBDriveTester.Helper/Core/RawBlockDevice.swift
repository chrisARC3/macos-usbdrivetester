//
//  RawBlockDevice.swift
//  Core — the seam between the retention / hard-fault algorithm and a device.
//
//  This is the single abstraction that lets the entire read -> write-back ->
//  read-verify engine (Steps 7-10) be developed and unit-tested against an
//  in-memory device, with NO privileged hardware and NO IOKit/DiskArbitration
//  involved (NFR-MAINT-2). The real hardware implementation arrives in Step 7 and
//  conforms to this same protocol, so the engine's code path is identical for the
//  simulated and the real device.
//
//  Purity / trust boundary: everything in Core/ is deliberately pure — Foundation
//  only, no UIKit, no IOKit, no Dispatch, no privilege. It compiles into the helper
//  target (where it will eventually run against /dev/rdiskN) and into the unit-test
//  target (where it runs against InMemoryBlockDevice). It is NOT part of the GUI app
//  module, which keeps it free of the app's default MainActor isolation.
//

import Foundation

/// A block device addressed by byte offset, whose I/O happens in whole units of its
/// logical block size.
///
/// ## Contract
/// - **Alignment.** Every `atByteOffset` and every transfer length (the `count` of
///   the supplied buffer) must be a whole multiple of ``logicalBlockSize``.
///   Implementations reject a violation with
///   ``DeviceIOError/misaligned(atByteOffset:length:logicalBlockSize:)`` rather than
///   performing a partial-block transfer. (Raw macOS devices likewise reject
///   misaligned I/O with `EINVAL`; Step 7 depends on this.)
/// - **Range.** A request must lie entirely within `[0, byteCount)`; anything past
///   the end is rejected with
///   ``DeviceIOError/outOfRange(atByteOffset:length:deviceByteCount:)``.
/// - **64-bit.** Offsets and block counts are 64-bit so multi-terabyte devices are
///   addressable with no capacity limit short of the device's own (NFR-COMPAT-6).
/// - **Full transfer.** On success, `read`/`write` move exactly `buffer.count` bytes
///   and return that count. A caller receiving fewer bytes than requested should
///   treat it as a failure
///   (``DeviceIOError/shortTransfer(atByteOffset:expected:actual:)``).
///
/// The engine must never assume the selected I/O size divides the device evenly —
/// the final chunk is sized to the exact remaining blocks (FR-TEST-5).
public protocol RawBlockDevice {

    /// Logical block size in bytes. In practice 512 or 4096 (NFR-COMPAT-5).
    var logicalBlockSize: Int { get }

    /// Total number of addressable logical blocks (64-bit, NFR-COMPAT-6).
    var blockCount: UInt64 { get }

    /// Read `buffer.count` bytes starting at `offset` into `buffer`.
    /// - Returns: bytes read (equal to `buffer.count` on success).
    /// - Throws: ``DeviceIOError`` on misalignment, out-of-range, or read failure.
    @discardableResult
    func read(into buffer: UnsafeMutableRawBufferPointer, atByteOffset offset: UInt64) throws -> Int

    /// Write `buffer.count` bytes from `buffer` starting at `offset`.
    /// - Returns: bytes written (equal to `buffer.count` on success).
    /// - Throws: ``DeviceIOError`` on misalignment, out-of-range, or write failure.
    @discardableResult
    func write(_ buffer: UnsafeRawBufferPointer, atByteOffset offset: UInt64) throws -> Int
}

public extension RawBlockDevice {
    /// Total addressable size in bytes (`blockCount * logicalBlockSize`).
    var byteCount: UInt64 { blockCount * UInt64(logicalBlockSize) }
}

/// Failures surfaced at the raw-device boundary.
///
/// `Equatable` so tests can assert the *exact* failure (offset, length, kind) that
/// fault injection is expected to produce.
public enum DeviceIOError: Error, Equatable {

    /// A hard read failure covering `length` bytes at `atByteOffset` (models `EIO` from
    /// `pread`, or an injected read fault).
    ///
    /// `ENXIO` was in this list until Step 12 and is not any more — it is ``deviceLost``.
    case readError(atByteOffset: UInt64, length: Int)

    /// A hard write failure covering `length` bytes at `atByteOffset` (models a
    /// `pwrite` error, or an injected write fault).
    case writeError(atByteOffset: UInt64, length: Int)

    /// Fewer bytes transferred than requested. Reserved for the real device
    /// (Step 7); the in-memory device always transfers whole aligned requests.
    case shortTransfer(atByteOffset: UInt64, expected: Int, actual: Int)

    /// The offset or length was not a whole multiple of `logicalBlockSize`.
    case misaligned(atByteOffset: UInt64, length: Int, logicalBlockSize: Int)

    /// The request extended beyond `[0, deviceByteCount)`.
    case outOfRange(atByteOffset: UInt64, length: Int, deviceByteCount: UInt64)

    /// **The device is gone** — de-enumerated, unplugged, or otherwise off the bus (Step 12,
    /// FR-DEV-8). Models `ENXIO` from `pread`/`pwrite`, or an injected device loss.
    ///
    /// ## Why this is not a read or write error
    ///
    /// Every other case on this enum describes something about a *place on a device*. This one
    /// describes the absence of the device, and the difference is the whole reason it exists:
    /// on 2026-08-06 the scratch drive de-enumerated part-way through a gate, every subsequent
    /// read returned `ENXIO` including the one at offset 0, and the run — doing exactly what
    /// log-and-continue is built to do — reported the drive as having roughly two million bad
    /// blocks. A tool whose entire output is a judgement about somebody's hardware must not
    /// confuse "this drive is broken" with "this drive is not here".
    ///
    /// The offset and length are where the run was when it found out, not a claim that
    /// anything is wrong with that range. Nothing here is recorded against the drive.
    case deviceLost(atByteOffset: UInt64, length: Int)
}
