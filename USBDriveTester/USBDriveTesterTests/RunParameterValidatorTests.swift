//
//  RunParameterValidatorTests.swift
//  Exercises the Step 3 boundary validator (NFR-REL-7) — the guard that stands
//  between an untrusted XPC caller and root-privileged raw I/O.
//
//  Coverage is deliberately exhaustive over the rejection cases rather than just
//  the happy path: this is the check that stops a malformed or hostile request from
//  reaching /dev/rdiskN, so every way it can say "no" is asserted by exact value,
//  and both supported geometries (512 B and 4096 B, NFR-COMPAT-5) are covered.
//

import Testing
import Foundation

struct RunParameterValidatorTests {

    private let g512 = DeviceGeometry(logicalBlockSize: 512, blockCount: 2048)      // 1 MiB
    private let g4096 = DeviceGeometry(logicalBlockSize: 4096, blockCount: 256)     // 1 MiB

    // MARK: Accepted requests

    @Test func wholeDeviceIsAccepted512() throws {
        let range = try RunParameterValidator.validate(byteOffset: 0,
                                                       byteLength: 1 << 20,
                                                       geometry: g512)
        #expect(range == ValidatedRunRange(startBlock: 0,
                                           blockCount: 2048,
                                           byteOffset: 0,
                                           byteLength: 1 << 20))
    }

    @Test func wholeDeviceIsAccepted4096() throws {
        let range = try RunParameterValidator.validate(byteOffset: 0,
                                                       byteLength: 1 << 20,
                                                       geometry: g4096)
        #expect(range == ValidatedRunRange(startBlock: 0,
                                           blockCount: 256,
                                           byteOffset: 0,
                                           byteLength: 1 << 20))
    }

    @Test func interiorAlignedRangeIsAccepted() throws {
        let range = try RunParameterValidator.validate(byteOffset: 4096,
                                                       byteLength: 2048,
                                                       geometry: g512)
        #expect(range.startBlock == 8)
        #expect(range.blockCount == 4)
    }

    /// A transfer ending exactly on the last byte is in range — the boundary case
    /// an off-by-one would break in the permissive direction.
    @Test func transferEndingExactlyAtDeviceEndIsAccepted() throws {
        let range = try RunParameterValidator.validate(byteOffset: (1 << 20) - 512,
                                                       byteLength: 512,
                                                       geometry: g512)
        #expect(range.startBlock == 2047)
        #expect(range.blockCount == 1)
    }

    @Test func singleBlockAtOffsetZeroIsAccepted() throws {
        let range = try RunParameterValidator.validate(byteOffset: 0,
                                                       byteLength: 4096,
                                                       geometry: g4096)
        #expect(range == ValidatedRunRange(startBlock: 0,
                                           blockCount: 1,
                                           byteOffset: 0,
                                           byteLength: 4096))
    }

    // MARK: Geometry rejections

    @Test func unsupportedBlockSizeIsRejected() {
        let odd = DeviceGeometry(logicalBlockSize: 1024, blockCount: 100)
        #expect(throws: RunParameterRejection.unsupportedBlockSize(1024)) {
            try RunParameterValidator.validate(byteOffset: 0, byteLength: 1024, geometry: odd)
        }
    }

    @Test func zeroBlockSizeIsRejected() {
        let zero = DeviceGeometry(logicalBlockSize: 0, blockCount: 100)
        #expect(throws: RunParameterRejection.unsupportedBlockSize(0)) {
            try RunParameterValidator.validate(byteOffset: 0, byteLength: 512, geometry: zero)
        }
    }

    @Test func emptyDeviceIsRejected() {
        let empty = DeviceGeometry(logicalBlockSize: 512, blockCount: 0)
        #expect(throws: RunParameterRejection.emptyDevice) {
            try RunParameterValidator.validate(byteOffset: 0, byteLength: 512, geometry: empty)
        }
    }

    /// A block count that cannot be converted to a byte count without wrapping is
    /// not a real device; rejecting it keeps every later `blockCount * blockSize`
    /// in the codebase safe.
    @Test func implausibleGeometryIsRejected() {
        let huge = DeviceGeometry(logicalBlockSize: 4096, blockCount: UInt64.max / 2)
        #expect(throws: RunParameterRejection.implausibleGeometry(logicalBlockSize: 4096,
                                                                  blockCount: UInt64.max / 2)) {
            try RunParameterValidator.validate(byteOffset: 0, byteLength: 4096, geometry: huge)
        }
    }

    // MARK: Request rejections

    @Test func zeroLengthIsRejected() {
        #expect(throws: RunParameterRejection.zeroLength) {
            try RunParameterValidator.validate(byteOffset: 0, byteLength: 0, geometry: g512)
        }
    }

    @Test func misalignedOffsetIsRejected512() {
        #expect(throws: RunParameterRejection.misalignedOffset(byteOffset: 513,
                                                               logicalBlockSize: 512)) {
            try RunParameterValidator.validate(byteOffset: 513, byteLength: 512, geometry: g512)
        }
    }

    /// An offset that is legal on a 512 B device is misaligned on a 4096 B one —
    /// the reason geometry is an input rather than an assumption (NFR-COMPAT-5).
    @Test func offsetLegalOn512IsMisalignedOn4096() {
        #expect(throws: RunParameterRejection.misalignedOffset(byteOffset: 512,
                                                               logicalBlockSize: 4096)) {
            try RunParameterValidator.validate(byteOffset: 512, byteLength: 4096, geometry: g4096)
        }
    }

    @Test func misalignedLengthIsRejected() {
        #expect(throws: RunParameterRejection.misalignedLength(byteLength: 1000,
                                                               logicalBlockSize: 512)) {
            try RunParameterValidator.validate(byteOffset: 0, byteLength: 1000, geometry: g512)
        }
    }

    /// Alignment is checked before range, so a request that is both misaligned and
    /// out of range reports the misalignment — the root cause, not the symptom.
    @Test func misalignmentIsReportedBeforeRange() {
        #expect(throws: RunParameterRejection.misalignedOffset(byteOffset: (1 << 30) + 1,
                                                               logicalBlockSize: 512)) {
            try RunParameterValidator.validate(byteOffset: (1 << 30) + 1,
                                               byteLength: 512,
                                               geometry: g512)
        }
    }

    @Test func offsetAtDeviceEndIsRejected() {
        #expect(throws: RunParameterRejection.offsetOutOfRange(byteOffset: 1 << 20,
                                                               deviceByteCount: 1 << 20)) {
            try RunParameterValidator.validate(byteOffset: 1 << 20, byteLength: 512, geometry: g512)
        }
    }

    @Test func offsetPastDeviceEndIsRejected() {
        #expect(throws: RunParameterRejection.offsetOutOfRange(byteOffset: 1 << 30,
                                                               deviceByteCount: 1 << 20)) {
            try RunParameterValidator.validate(byteOffset: 1 << 30, byteLength: 512, geometry: g512)
        }
    }

    /// Starts in range, ends past the end — by exactly one block.
    @Test func transferRunningOneBlockPastEndIsRejected() {
        #expect(throws: RunParameterRejection.rangeOverflowsDevice(byteOffset: (1 << 20) - 512,
                                                                   byteLength: 1024,
                                                                   deviceByteCount: 1 << 20)) {
            try RunParameterValidator.validate(byteOffset: (1 << 20) - 512,
                                               byteLength: 1024,
                                               geometry: g512)
        }
    }

    // MARK: Integer-overflow attack surface
    //
    // These are the requests a hostile caller would craft: values chosen so that a
    // naive `offset + length <= deviceByteCount` bounds check wraps and returns
    // true. They must be rejected, not merely "not crash".

    @Test func offsetPlusLengthWrappingIsRejected() {
        // Both operands are 512-aligned, so the request clears every alignment
        // check and is stopped only by the overflow-checked addition. The sum wraps
        // to 0, which would satisfy an unchecked `end <= deviceByteCount`.
        let offset: UInt64 = 0xFFFF_FFFF_FFFF_FE00      // UInt64.max - 511
        let length: UInt64 = 512
        #expect(throws: RunParameterRejection.offsetOutOfRange(byteOffset: offset,
                                                               deviceByteCount: 1 << 20)) {
            try RunParameterValidator.validate(byteOffset: offset,
                                               byteLength: length,
                                               geometry: g512)
        }
    }

    /// Offset genuinely inside the device, length large enough that the sum wraps.
    /// This one gets past the offset bounds check, so `rangeOverflowsDevice` is
    /// reached only because the addition is overflow-checked.
    @Test func inRangeOffsetWithWrappingLengthIsRejected() {
        let offset: UInt64 = 512
        let length: UInt64 = 0xFFFF_FFFF_FFFF_FE00      // 512-aligned; offset + length wraps to 0
        #expect(throws: RunParameterRejection.rangeOverflowsDevice(byteOffset: offset,
                                                                   byteLength: length,
                                                                   deviceByteCount: 1 << 20)) {
            try RunParameterValidator.validate(byteOffset: offset,
                                               byteLength: length,
                                               geometry: g512)
        }
    }

    // MARK: Rejection messages
    //
    // These strings cross XPC and are shown to the user, so they must name the real
    // cause and a corrective value (NFR-USE-5), never a generic failure.

    @Test func rejectionMessagesNameCauseAndRemedy() {
        let misaligned = RunParameterRejection.misalignedOffset(byteOffset: 513,
                                                                logicalBlockSize: 512)
        #expect(misaligned.description.contains("513"))
        #expect(misaligned.description.contains("512"))
        #expect(misaligned.description.contains("512."))     // nearest valid offset below

        let overflow = RunParameterRejection.rangeOverflowsDevice(byteOffset: 1024,
                                                                   byteLength: 4096,
                                                                   deviceByteCount: 2048)
        #expect(overflow.description.contains("1024"))
        #expect(overflow.description.contains("only 1024 bytes remain"))

        let unsupported = RunParameterRejection.unsupportedBlockSize(1024)
        #expect(unsupported.description.contains("512 or 4096"))
    }

    /// Every case must produce a non-empty message; a silent rejection at this
    /// boundary would surface in the GUI as an unexplained refusal.
    @Test func everyRejectionHasAMessage() {
        let all: [RunParameterRejection] = [
            .unsupportedBlockSize(1024),
            .emptyDevice,
            .implausibleGeometry(logicalBlockSize: 4096, blockCount: .max),
            .zeroLength,
            .misalignedOffset(byteOffset: 1, logicalBlockSize: 512),
            .misalignedLength(byteLength: 1, logicalBlockSize: 512),
            .offsetOutOfRange(byteOffset: 4096, deviceByteCount: 2048),
            .rangeOverflowsDevice(byteOffset: 1024, byteLength: 4096, deviceByteCount: 2048),
        ]
        for rejection in all {
            #expect(!rejection.description.isEmpty)
        }
    }
}
