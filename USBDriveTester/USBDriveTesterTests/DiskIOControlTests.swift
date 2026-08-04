//
//  DiskIOControlTests.swift
//  Pins the `ioctl` request numbers, and exercises the geometry-reconciliation policy.
//
//  ## What the constant tests are actually protecting
//
//  These four numbers are sent by a **root daemon** to a block device driver. They cannot be
//  imported from the SDK (`macro 'DKIOCGETBLOCKSIZE' unavailable: structure not supported`),
//  so they are re-derived in Swift — and a re-derivation is exactly the kind of thing that
//  looks right, compiles, and is wrong.
//
//  The literals asserted below are not this file's opinion. They were obtained by compiling
//  `<sys/disk.h>` in C against the macOS 26.5 SDK and printing the macros (2026-08-02), then
//  the first two were confirmed against a real Samsung T5 through a USB bridge by
//  `scripts/nocache-calibration.sh disk4`, which read `logicalBlockSize=512` and
//  `blockCount=1953525168` — matching `diskutil info` exactly.
//
//  So the assertion here is deliberately redundant with the derivation: if someone "tidies"
//  `_IOR` and the derivation changes, these fail. If instead the SDK ever changed the macros,
//  `scripts/ioctl-constants-check.sh` re-measures against the current headers and would
//  disagree with these literals. Neither check alone is sufficient — one guards the code
//  against drift, the other guards the literal against staleness.
//

import Testing
import Foundation

struct DiskIOControlTests {

    // MARK: - The request numbers, pinned

    /// Measured from `<sys/disk.h>` by compiling C, 2026-08-02, macOS 26.5 SDK.
    @Test func requestNumbersMatchTheSDKMacros() {
        #expect(DiskIOControl.getBlockSize         == 0x4004_6418)   // DKIOCGETBLOCKSIZE
        #expect(DiskIOControl.getBlockCount        == 0x4008_6419)   // DKIOCGETBLOCKCOUNT
        #expect(DiskIOControl.getPhysicalBlockSize == 0x4004_644d)   // DKIOCGETPHYSICALBLOCKSIZE
        #expect(DiskIOControl.getMaxByteCountRead  == 0x4008_6446)   // DKIOCGETMAXBYTECOUNTREAD
        #expect(DiskIOControl.getMaxByteCountWrite == 0x4008_6447)   // DKIOCGETMAXBYTECOUNTWRITE
    }

    /// The `_IOR` encoding, field by field, so a failure says *which* part drifted rather
    /// than only that a hex literal changed.
    @Test func requestEncodingPacksDirectionLengthGroupAndNumber() {
        let request = DiskIOControl.request(readingOut: "d", 24, as: UInt32.self)

        #expect(request & 0xE000_0000 == 0x4000_0000, "IOC_OUT — the driver writes to us")
        #expect((request >> 16) & 0x1fff == 4,        "length field == sizeof(UInt32)")
        #expect((request >> 8) & 0xff == 0x64,        "group 'd'")
        #expect(request & 0xff == 24,                 "request number")
    }

    /// The size of the out-parameter is *part of the request number*, so using the wrong
    /// type does not truncate the answer — it produces a request the driver has never heard
    /// of. This is the failure mode most likely to be introduced by a careless edit, and the
    /// one least likely to be noticed by reading the call site.
    @Test func requestNumberDependsOnTheOutParameterType() {
        let asThirtyTwo = DiskIOControl.request(readingOut: "d", 25, as: UInt32.self)
        let asSixtyFour = DiskIOControl.request(readingOut: "d", 25, as: UInt64.self)

        #expect(asThirtyTwo != asSixtyFour)
        #expect(asSixtyFour == DiskIOControl.getBlockCount)
        #expect(asThirtyTwo != DiskIOControl.getBlockCount,
                """
                DKIOCGETBLOCKCOUNT declared with a UInt32 out-parameter is a different, \
                unrecognised request — not a truncated block count
                """)
    }

    // MARK: - Decision 3a: the invariant beneath `supportedBlockSizes`

    /// Every supported logical block size must be a **power of two** that divides every I/O
    /// size FR-CTRL-8 offers.
    ///
    /// Recorded as an executable invariant rather than a comment because "an even multiple of
    /// 512" was considered as the rule and is **not sufficient**: 1536 is an even multiple of
    /// 512 and divides none of 1/2/4/8 MiB, so a device reporting it would fail deep inside
    /// `ChunkPlanError.ioSizeNotBlockAligned` instead of being refused cleanly at the geometry
    /// check. If the allowlist is ever widened, a careless value fails here rather than
    /// shipping.
    @Test func supportedBlockSizesArePowersOfTwoThatDivideEveryOfferedIOSize() {
        let offeredIOSizes = [1 << 20, 2 << 20, 4 << 20, 8 << 20]   // FR-CTRL-8

        for blockSize in DeviceGeometry.supportedBlockSizes {
            #expect(blockSize > 0)
            #expect(blockSize & (blockSize - 1) == 0,
                    "\(blockSize) is not a power of two")
            #expect(blockSize <= UInt32(offeredIOSizes.min()!),
                    """
                    \(blockSize) exceeds the smallest offered I/O size, so no chunk could \
                    hold a whole block
                    """)
            for ioSize in offeredIOSizes {
                #expect(ioSize % Int(blockSize) == 0,
                        "\(blockSize)-byte blocks do not divide a \(ioSize)-byte I/O size")
            }
        }
    }

    /// NFR-COMPAT-5's floor, asserted directly: 512 and 4096 must both be accepted.
    @Test func supportedBlockSizesCoverTheRequiredGeometries() {
        #expect(DeviceGeometry.supportedBlockSizes.contains(512))
        #expect(DeviceGeometry.supportedBlockSizes.contains(4096))
    }

    // MARK: - Reconciliation: the ioctl wins

    /// `disk4`'s real numbers, measured 2026-08-02 (`diskutil` and the ioctls agree).
    private static let disk4BlockSize: UInt32 = 512
    private static let disk4BlockCount: UInt64 = 1_953_525_168
    private static let disk4Bytes: UInt64 = 1_000_204_886_016

    /// `disk8`'s real numbers — 42,970,644,479 blocks is ten times past 2³², which is the
    /// only NFR-COMPAT-6 evidence available without unmounting a 22 TB drive.
    private static let disk8BlockCount: UInt64 = 42_970_644_479
    private static let disk8Bytes: UInt64 = 22_000_969_973_248

    @Test func agreeingSourcesReconcileToTheIoctlValues() throws {
        let result = try DiskIOControl.reconcile(ioctlBlockSize: Self.disk4BlockSize,
                                                 ioctlBlockCount: Self.disk4BlockCount,
                                                 ioKitSizeBytes: Self.disk4Bytes,
                                                 ioKitBlockSize: Self.disk4BlockSize)

        #expect(result.agrees)
        #expect(result.disagreement == nil)
        #expect(result.authoritative == DeviceGeometry(logicalBlockSize: Self.disk4BlockSize,
                                                       blockCount: Self.disk4BlockCount))
        #expect(result.ioKit?.blockCount == Self.disk4BlockCount)
        // Both figures appear whether or not they agree — a line that only appears on
        // disagreement cannot be used to confirm agreement happened.
        #expect(result.logDescription.contains("ioctl reports"))
        #expect(result.logDescription.contains("IOKit reported"))
    }

    /// A 64-bit block count must survive reconciliation untouched. `disk4` cannot show this
    /// — it is below 2³² — so `disk8`'s measured geometry stands in.
    @Test func sixtyFourBitBlockCountsSurviveReconciliation() throws {
        let result = try DiskIOControl.reconcile(ioctlBlockSize: 512,
                                                 ioctlBlockCount: Self.disk8BlockCount,
                                                 ioKitSizeBytes: Self.disk8Bytes,
                                                 ioKitBlockSize: 512)

        #expect(result.agrees)
        #expect(result.authoritative.blockCount == Self.disk8BlockCount)
        #expect(result.authoritative.blockCount > UInt64(UInt32.max))
        // The value a 32-bit truncation would have produced, asserted as NOT the answer.
        #expect(result.authoritative.blockCount != Self.disk8BlockCount & 0xFFFF_FFFF)
    }

    @Test func aDisagreeingBlockCountIsReportedButTheIoctlStillWins() throws {
        let result = try DiskIOControl.reconcile(ioctlBlockSize: 512,
                                                 ioctlBlockCount: Self.disk4BlockCount,
                                                 ioKitSizeBytes: Self.disk4Bytes - 512 * 100,
                                                 ioKitBlockSize: 512)

        #expect(!result.agrees)
        #expect(result.authoritative.blockCount == Self.disk4BlockCount)
        #expect(result.disagreement?.contains("block count") == true)
        #expect(result.logDescription.contains("THEY DISAGREE"))
    }

    @Test func aDisagreeingBlockSizeIsReportedButTheIoctlStillWins() throws {
        let result = try DiskIOControl.reconcile(ioctlBlockSize: 4096,
                                                 ioctlBlockCount: 1000,
                                                 ioKitSizeBytes: 1000 * 512,
                                                 ioKitBlockSize: 512)

        #expect(!result.agrees)
        #expect(result.authoritative.logicalBlockSize == 4096)
        #expect(result.disagreement?.contains("block size") == true)
    }

    /// IOKit reports a byte size, so its block count is implied. A size that is not a whole
    /// number of blocks is itself a signal worth surfacing rather than rounding away.
    @Test func anIoKitSizeThatIsNotAWholeNumberOfBlocksIsReported() throws {
        let result = try DiskIOControl.reconcile(ioctlBlockSize: 512,
                                                 ioctlBlockCount: 100,
                                                 ioKitSizeBytes: 100 * 512 + 3,
                                                 ioKitBlockSize: 512)

        #expect(!result.agrees)
        #expect(result.disagreement?.contains("not a whole number") == true)
    }

    /// Missing IOKit numbers are not a disagreement — there is nothing to disagree with. The
    /// ioctl is the authority regardless, so the run is unaffected.
    @Test func absentIoKitGeometryIsNotTreatedAsDisagreement() throws {
        let result = try DiskIOControl.reconcile(ioctlBlockSize: 512,
                                                 ioctlBlockCount: Self.disk4BlockCount,
                                                 ioKitSizeBytes: nil,
                                                 ioKitBlockSize: nil)

        #expect(result.agrees)
        #expect(result.ioKit == nil)
        #expect(result.authoritative.blockCount == Self.disk4BlockCount)
        #expect(result.logDescription.contains("IOKit reported no usable geometry"))
    }

    // MARK: - Reconciliation: "prefer the ioctl" is not "believe anything it says"

    /// BUILD-PLAN Step 7's risks: *"Some USB bridges report odd geometry; trust the ioctl and
    /// reject impossible values."* Preferring the ioctl over IOKit does not mean accepting a
    /// block size no real device uses.
    @Test func anUnsupportedIoctlBlockSizeIsRefused() {
        #expect(throws: GeometryRefusal.implausible(.unsupportedBlockSize(1024))) {
            _ = try DiskIOControl.reconcile(ioctlBlockSize: 1024,
                                            ioctlBlockCount: 1000,
                                            ioKitSizeBytes: 1000 * 1024,
                                            ioKitBlockSize: 1024)
        }
    }

    @Test func aZeroBlockCountIsRefused() {
        #expect(throws: GeometryRefusal.implausible(.emptyDevice)) {
            _ = try DiskIOControl.reconcile(ioctlBlockSize: 512,
                                            ioctlBlockCount: 0,
                                            ioKitSizeBytes: 0,
                                            ioKitBlockSize: 512)
        }
    }

    /// A block count whose product with the block size overflows 64 bits cannot describe a
    /// real device, and would make every later range check meaningless.
    @Test func geometryThatOverflowsSixtyFourBitsIsRefused() {
        #expect(throws: GeometryRefusal.implausible(
            .implausibleGeometry(logicalBlockSize: 4096, blockCount: UInt64.max))) {
            _ = try DiskIOControl.reconcile(ioctlBlockSize: 4096,
                                            ioctlBlockCount: UInt64.max,
                                            ioKitSizeBytes: nil,
                                            ioKitBlockSize: nil)
        }
    }

    /// A refusal has to name the cause and say what the tool does about it — these strings
    /// reach the user through the XPC boundary (NFR-USE-5).
    @Test func refusalsExplainThemselves() {
        let ioctlFailure = GeometryRefusal.ioctlFailed(request: "DKIOCGETBLOCKCOUNT",
                                                        errnoCode: ENOTTY)
        #expect(ioctlFailure.description.contains("DKIOCGETBLOCKCOUNT"))
        #expect(ioctlFailure.description.contains("\(ENOTTY)"))

        let implausible = GeometryRefusal.implausible(.unsupportedBlockSize(1024))
        #expect(implausible.description.contains("1024"))
        #expect(implausible.description.contains("512"), "names the sizes it does support")
    }
}
