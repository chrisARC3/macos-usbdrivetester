//
//  RunParameterValidator.swift
//  Core — boundary validation of caller-supplied addressing parameters.
//
//  The helper runs as **root**. Authenticating the XPC peer's code signature
//  (FR-ARCH-5, NFR-SEC-2) establishes *who* is calling; it says nothing about
//  whether what they sent is sane. So every request is independently re-validated
//  here, before any privileged I/O is performed (NFR-REL-7, NFR-SEC-3).
//
//  This type is pure — Foundation only, no IOKit, no Dispatch, no privilege — so it
//  is exhaustively unit-testable with no hardware (NFR-MAINT-2), exactly like the
//  rest of Core/. It compiles into the helper target and the unit-test target, and
//  NOT into the GUI app module (which would impose the app's default MainActor
//  isolation on it).
//
//  Reuse across steps: Step 3 validates against geometry supplied over XPC, because
//  the helper cannot open a device yet. From Step 7 the helper obtains geometry
//  itself via DKIOCGETBLOCKSIZE / DKIOCGETBLOCKCOUNT and feeds *that* in instead.
//  The logic below does not change — only the provenance of `DeviceGeometry` does.
//

import Foundation

/// Addressable shape of a block device.
///
/// Deliberately a plain value type with no device handle attached, so the same
/// validation runs against simulated geometry in tests, caller-supplied geometry in
/// Step 3, and ioctl-derived geometry from Step 7 onward.
public struct DeviceGeometry: Equatable {

    /// Logical block size in bytes. Must be 512 or 4096 (NFR-COMPAT-5).
    public let logicalBlockSize: UInt32

    /// Total number of addressable logical blocks (64-bit, NFR-COMPAT-6).
    public let blockCount: UInt64

    public init(logicalBlockSize: UInt32, blockCount: UInt64) {
        self.logicalBlockSize = logicalBlockSize
        self.blockCount = blockCount
    }

    /// Block sizes this tool accepts. Some USB bridges report nonsense geometry;
    /// BUILD-PLAN Step 7 is explicit that impossible values are rejected rather
    /// than accommodated.
    public static let supportedBlockSizes: Set<UInt32> = [512, 4096]
}

/// A request that passed validation, re-expressed in the block domain.
///
/// Returning this (rather than `Void`) means the block-domain conversion happens
/// exactly once, in the validated path, instead of being redone — and possibly
/// redone differently — by each caller. Steps 7/8 address the device in blocks.
public struct ValidatedRunRange: Equatable {

    /// First block of the transfer.
    public let startBlock: UInt64

    /// Number of whole blocks in the transfer (always >= 1).
    public let blockCount: UInt64

    /// The validated byte offset (`startBlock * logicalBlockSize`).
    public let byteOffset: UInt64

    /// The validated byte length (`blockCount * logicalBlockSize`).
    public let byteLength: UInt64
}

/// Why a set of run parameters was refused.
///
/// `Equatable` so tests can assert the *exact* rejection rather than merely that
/// something was thrown. `CustomStringConvertible` because these strings cross the
/// XPC boundary to the GUI: each one must name the actual cause and, where there is
/// one, the corrective value — never a generic failure (NFR-USE-5).
public enum RunParameterRejection: Error, Equatable, CustomStringConvertible {

    /// Block size is not one this tool supports.
    case unsupportedBlockSize(UInt32)

    /// The device reports zero addressable blocks.
    case emptyDevice

    /// `logicalBlockSize * blockCount` does not fit in 64 bits — the reported
    /// geometry cannot describe a real device.
    case implausibleGeometry(logicalBlockSize: UInt32, blockCount: UInt64)

    /// A zero-length transfer was requested.
    case zeroLength

    /// Offset is not a whole multiple of the logical block size.
    case misalignedOffset(byteOffset: UInt64, logicalBlockSize: UInt32)

    /// Length is not a whole multiple of the logical block size.
    case misalignedLength(byteLength: UInt64, logicalBlockSize: UInt32)

    /// Offset lies at or past the end of the device.
    case offsetOutOfRange(byteOffset: UInt64, deviceByteCount: UInt64)

    /// Offset is inside the device but the transfer runs past its end. Also covers
    /// the case where `byteOffset + byteLength` overflows 64 bits, which is the
    /// arithmetic an attacker would reach for to make an out-of-range request look
    /// in-range.
    case rangeOverflowsDevice(byteOffset: UInt64, byteLength: UInt64, deviceByteCount: UInt64)

    public var description: String {
        switch self {
        case .unsupportedBlockSize(let size):
            let supported = DeviceGeometry.supportedBlockSizes.sorted()
                .map(String.init).joined(separator: " or ")
            return "Unsupported logical block size \(size) bytes; this tool supports \(supported)."

        case .emptyDevice:
            return "The device reports zero addressable blocks."

        case .implausibleGeometry(let size, let count):
            return "Implausible device geometry: \(count) blocks of \(size) bytes "
                 + "exceeds the addressable 64-bit range."

        case .zeroLength:
            return "Transfer length is zero; there is nothing to read or write."

        case .misalignedOffset(let offset, let size):
            let previous = offset - (offset % UInt64(size))
            return "Offset \(offset) is not a multiple of the \(size)-byte logical block size; "
                 + "the nearest valid offset at or below it is \(previous)."

        case .misalignedLength(let length, let size):
            let rounded = length - (length % UInt64(size))
            return "Length \(length) is not a multiple of the \(size)-byte logical block size; "
                 + "the nearest valid length at or below it is \(rounded)."

        case .offsetOutOfRange(let offset, let deviceByteCount):
            return "Offset \(offset) is at or past the end of the device "
                 + "(\(deviceByteCount) bytes); the last valid offset is \(deviceByteCount - 1)."

        case .rangeOverflowsDevice(let offset, let length, let deviceByteCount):
            let available = deviceByteCount - offset
            return "A \(length)-byte transfer at offset \(offset) runs past the end of the "
                 + "device (\(deviceByteCount) bytes); only \(available) bytes remain from "
                 + "that offset."
        }
    }
}

/// Validates caller-supplied addressing parameters against a device's geometry.
///
/// Stateless and side-effect-free by design: it is the one place the alignment and
/// range rules are expressed, so the guard cannot drift between the XPC boundary
/// (Step 3), the mount-guard write precondition (Step 6) and the chunked I/O path
/// (Steps 7/8).
public enum RunParameterValidator {

    /// Check a prospective transfer.
    ///
    /// Checks run cheapest-and-most-fundamental first, so the reported rejection is
    /// the root cause rather than a downstream symptom: geometry must make sense
    /// before a request against it can, and alignment is checked before range so a
    /// misaligned offset is not reported as merely out of range.
    ///
    /// - Parameters:
    ///   - byteOffset: Start of the transfer, in bytes from block 0.
    ///   - byteLength: Length of the transfer, in bytes.
    ///   - geometry: The device's addressable shape.
    /// - Returns: The request re-expressed in the block domain.
    /// - Throws: ``RunParameterRejection`` naming the precise cause.
    @discardableResult
    public static func validate(byteOffset: UInt64,
                                byteLength: UInt64,
                                geometry: DeviceGeometry) throws -> ValidatedRunRange {

        let blockSize = geometry.logicalBlockSize

        // --- Geometry sanity -------------------------------------------------
        guard DeviceGeometry.supportedBlockSizes.contains(blockSize) else {
            throw RunParameterRejection.unsupportedBlockSize(blockSize)
        }
        guard geometry.blockCount > 0 else {
            throw RunParameterRejection.emptyDevice
        }
        let (deviceByteCount, geometryOverflowed) =
            geometry.blockCount.multipliedReportingOverflow(by: UInt64(blockSize))
        guard !geometryOverflowed else {
            throw RunParameterRejection.implausibleGeometry(logicalBlockSize: blockSize,
                                                            blockCount: geometry.blockCount)
        }

        // --- Request sanity --------------------------------------------------
        guard byteLength > 0 else {
            throw RunParameterRejection.zeroLength
        }

        // Alignment. Raw macOS devices reject misaligned I/O with EINVAL, so this is
        // not a stylistic preference — it is the device's own contract, enforced
        // before we ever reach the device (BUILD-PLAN Step 7, risks).
        let blockSize64 = UInt64(blockSize)
        guard byteOffset % blockSize64 == 0 else {
            throw RunParameterRejection.misalignedOffset(byteOffset: byteOffset,
                                                         logicalBlockSize: blockSize)
        }
        guard byteLength % blockSize64 == 0 else {
            throw RunParameterRejection.misalignedLength(byteLength: byteLength,
                                                         logicalBlockSize: blockSize)
        }

        // Range. The overflow-checked addition matters: with a wrapping add, an
        // offset near UInt64.max plus a large length would produce a small sum and
        // sail through the bounds check below.
        guard byteOffset < deviceByteCount else {
            throw RunParameterRejection.offsetOutOfRange(byteOffset: byteOffset,
                                                         deviceByteCount: deviceByteCount)
        }
        let (end, addOverflowed) = byteOffset.addingReportingOverflow(byteLength)
        guard !addOverflowed, end <= deviceByteCount else {
            throw RunParameterRejection.rangeOverflowsDevice(byteOffset: byteOffset,
                                                             byteLength: byteLength,
                                                             deviceByteCount: deviceByteCount)
        }

        return ValidatedRunRange(startBlock: byteOffset / blockSize64,
                                 blockCount: byteLength / blockSize64,
                                 byteOffset: byteOffset,
                                 byteLength: byteLength)
    }
}
