//
//  RunPlacementTests.swift
//  FR-TEST-10: every run begins on a 1 MiB boundary, and covers whole MiB units unless it ends
//  at the device's last block.
//
//  ## Why this rule is worth testing carefully
//
//  It can only ever *refuse* things, so a bug in it is either a run that should have been allowed
//  and was not — which shows up immediately and loudly — or a misaligned run that was allowed and
//  shows up as nothing at all except a throughput figure that is quietly too low. The second is
//  the dangerous direction: FR-METR-1's throughput exists so the user can judge wear against the
//  manufacturer's advertised rate, and misaligned I/O makes a device read-modify-write internally.
//  A hole here would manufacture the exact signal the measurement exists to detect.
//
//  ## The regression this file pins
//
//  ``StepEightGateCompatibilityTests`` encodes a finding from 2026-08-04: Step 8's hardware gate
//  requested `1 GiB − 512 KiB` to force a short final chunk, which is 1023.5 MiB and would have
//  been **refused** by this rule — about 35 minutes into that gate's before-fingerprint pass. The
//  script now requests `1 GiB − 1 MiB`, which still yields a short final chunk. Both constants are
//  asserted here so the compatibility is a test rather than a memory.
//

import Testing
import Foundation
// `TesterProtocol` lives in `Shared/`, which compiles into the app and helper targets — not
// directly into this one, the way `Core/` does. It arrives through the app module.
@testable import USBDriveTester

// MARK: - Fixtures

private enum Placement {

    static let mib: UInt64 = 1 << 20

    /// `disk4` — 512-byte blocks, 1,953,525,168 blocks. **Not** a whole number of MiB: it is
    /// 953,869 MiB plus 1,456 blocks, which is why the final-range exemption exists.
    static let disk4 = DeviceGeometry(logicalBlockSize: 512, blockCount: 1_953_525_168)

    /// The other supported geometry (NFR-COMPAT-5).
    static let large = DeviceGeometry(logicalBlockSize: 4_096, blockCount: 1_000_000)

    static func blocks(_ mibCount: UInt64, _ geometry: DeviceGeometry) -> UInt64 {
        mibCount * mib / UInt64(geometry.logicalBlockSize)
    }
}

// MARK: - The start rule

struct RunStartAlignmentTests {

    /// Block 0 is where every real run begins (FR-TEST-4), so it had better be legal.
    @Test func blockZeroIsAlwaysAcceptable() throws {
        try RunPlacement.validate(startBlock: 0,
                                  blockCount: Placement.blocks(1, Placement.disk4),
                                  geometry: Placement.disk4)
        try RunPlacement.validate(startBlock: 0,
                                  blockCount: Placement.blocks(1, Placement.large),
                                  geometry: Placement.large)
    }

    @Test func blocksPerBoundaryMatchesBothGeometries() {
        #expect(RunPlacement.blocksPerBoundary(logicalBlockSize: 512) == 2_048)
        #expect(RunPlacement.blocksPerBoundary(logicalBlockSize: 4_096) == 256)
        #expect(RunPlacement.boundaryBytes == 1_048_576)
    }

    /// Arguments are MiB indices; the block address is derived, so every case genuinely is a
    /// boundary and none is quietly substituted for another.
    @Test(arguments: [UInt64(0), 1, 2, 1_000, 953_868])
    func aStartOnAMebibyteBoundaryIsAccepted(mibIndex: UInt64) throws {
        try RunPlacement.validate(startBlock: Placement.blocks(mibIndex, Placement.disk4),
                                  blockCount: Placement.blocks(1, Placement.disk4),
                                  geometry: Placement.disk4)
    }

    /// One block past a boundary, one block short of one, and the classic off-by-one of using the
    /// logical block size as though it were the boundary.
    @Test(arguments: [UInt64(1), 512, 1_024, 2_047, 2_049, 4_095])
    func aStartOffTheBoundaryIsRefused(startBlock: UInt64) {
        #expect(throws: RunPlacementRejection.self) {
            try RunPlacement.validate(startBlock: startBlock,
                                      blockCount: Placement.blocks(1, Placement.disk4),
                                      geometry: Placement.disk4)
        }
    }

    /// The refusal says which rule failed and names the offset, because a message that only says
    /// "invalid" sends someone to guess (NFR-USE-5).
    @Test func theRefusalNamesTheOffsetAndTheReason() throws {
        let error = #expect(throws: RunPlacementRejection.self) {
            try RunPlacement.validate(startBlock: 1,
                                      blockCount: Placement.blocks(1, Placement.disk4),
                                      geometry: Placement.disk4)
        }
        let rejection = try #require(error)
        #expect(rejection == .startNotOnBoundary(startBlock: 1, byteOffset: 512))
        #expect(rejection.description.contains("512"))
        #expect(rejection.description.contains("1 MiB"))
    }
}

// MARK: - The length rule

struct RunLengthTests {

    @Test(arguments: [UInt64(1), 2, 4, 8, 1_023, 1_024])
    func aWholeNumberOfMebibytesIsAccepted(mibCount: UInt64) throws {
        try RunPlacement.validate(startBlock: 0,
                                  blockCount: Placement.blocks(mibCount, Placement.disk4),
                                  geometry: Placement.disk4)
    }

    /// **The rule that keeps a *sequence* aligned.** A call covering a partial MiB would leave
    /// the next call's start misaligned, one call at a time.
    @Test func aPartialMebibyteInTheMiddleOfTheDeviceIsRefused() {
        let oneMibPlusOneBlock = Placement.blocks(1, Placement.disk4) + 1
        #expect(throws: RunPlacementRejection.self) {
            try RunPlacement.validate(startBlock: 0,
                                      blockCount: oneMibPlusOneBlock,
                                      geometry: Placement.disk4)
        }
    }

    /// **The exemption, and it is not optional.** `disk4` is 953,869 whole MiB plus 1,456 blocks,
    /// so the only way to cover the device at all is for the final range to be short — which is
    /// FR-TEST-5's short final chunk arriving one level up.
    @Test func aPartialMebibyteThatEndsAtTheDevicesLastBlockIsAccepted() throws {
        let lastBoundary = 953_869 * Placement.blocks(1, Placement.disk4)
        let remainder = Placement.disk4.blockCount - lastBoundary

        #expect(remainder == 1_456, "disk4's tail should be 1,456 blocks")
        #expect(remainder * 512 % Placement.mib != 0, "the tail is deliberately a partial MiB")

        try RunPlacement.validate(startBlock: lastBoundary,
                                  blockCount: remainder,
                                  geometry: Placement.disk4)
    }

    /// One block short of the end is not the end, and must still be refused — otherwise "ends at
    /// the device" would be a range rather than a point.
    @Test func aPartialMebibyteThatStopsOneBlockShortOfTheEndIsRefused() {
        let lastBoundary = 953_869 * Placement.blocks(1, Placement.disk4)
        #expect(throws: RunPlacementRejection.self) {
            try RunPlacement.validate(startBlock: lastBoundary,
                                      blockCount: 1_456 - 1,
                                      geometry: Placement.disk4)
        }
    }

    @Test func theSameExemptionAppliesAtFourKilobyteGeometry() throws {
        // 1,000,000 blocks of 4,096 B = 3,906.25 MiB — also not a whole number of MiB.
        let perMib = Placement.blocks(1, Placement.large)
        let lastBoundary = (Placement.large.blockCount / perMib) * perMib
        let remainder = Placement.large.blockCount - lastBoundary

        #expect(remainder > 0, "this geometry should have a partial tail too")
        try RunPlacement.validate(startBlock: lastBoundary,
                                  blockCount: remainder,
                                  geometry: Placement.large)
    }
}

// MARK: - The property that makes the rule self-maintaining

struct SelfMaintainingAlignmentTests {

    /// **Why the helper's check is a guard against a caller, never against the engine.**
    ///
    /// A run starts at block 0 (FR-TEST-4) and advances by whole chunks. FR-CTRL-8 (revised
    /// 2026-08-04) lets the transfer size change when a run is paused, so a run can advance by
    /// any *mix* of 1, 2, 4 and 8 MiB. Every position it can reach is therefore an integer
    /// number of MiB — so no size change can ever produce a misaligned resume.
    ///
    /// Asserted over a deliberately awkward sequence rather than argued, because "obviously
    /// always aligned" is the kind of claim that stops being true when somebody adds a size.
    @Test func everyPositionReachableByAnyMixOfTransferSizesIsAValidStart() throws {
        let sizes: [UInt64] = [1, 2, 4, 8]                       // MiB, FR-CTRL-8's set
        var generator = SplitMix64(seed: 0x414C_4947_4E00_0000)  // "ALIGN\0\0\0"
        var block: UInt64 = 0

        for step in 0 ..< 500 {
            // A size change at every step is not realistic; it is the worst case.
            let sizeMib = sizes[Int(UInt64.random(in: 0 ..< 4, using: &generator))]
            let chunkBlocks = Placement.blocks(sizeMib, Placement.disk4)

            guard block + chunkBlocks < Placement.disk4.blockCount else { break }

            // The position the run has reached must itself be a legal place to start.
            try RunPlacement.validate(startBlock: block,
                                      blockCount: chunkBlocks,
                                      geometry: Placement.disk4)
            block += chunkBlocks
            #expect(block * 512 % Placement.mib == 0, "step \(step) left block \(block) misaligned")
        }
    }

    /// Every permitted transfer size is itself a whole number of MiB, which is what makes the
    /// property above hold. If a size were ever added that is not, this fails first and says so.
    @Test func everyPermittedTransferSizeIsAWholeNumberOfMebibytes() {
        for size in TesterProtocol.permittedIOSizes {
            #expect(UInt64(size) % Placement.mib == 0,
                    "I/O size \(size) is not a whole number of MiB, which breaks FR-TEST-10")
        }
        #expect(UInt64(TesterProtocol.defaultIOSizeBytes) % Placement.mib == 0)
    }

    /// The per-call cap is also a whole number of MiB, so a full-size bounded call never leaves
    /// the next one misaligned.
    @Test func theMaximumBytesPerCallIsAWholeNumberOfMebibytes() {
        #expect(TesterProtocol.maximumBytesPerCall % Placement.mib == 0)
    }
}

// MARK: - The regression this rule caused, pinned

struct StepEightGateCompatibilityTests {

    /// Step 8's `retention-cycle-check.sh` requested `1 GiB − 512 KiB` to force a short final
    /// chunk on real media. Under FR-TEST-10 that is 1023.5 MiB in the middle of the device and
    /// is **refused** — which would have surfaced roughly 35 minutes into the gate, right after
    /// its before-fingerprint pass.
    @Test func theOldGateConstantWouldBeRefused() {
        let oldRunBytes: UInt64 = (1 << 30) - (512 * 1_024)
        #expect(throws: RunPlacementRejection.self) {
            try RunPlacement.validate(startBlock: Placement.blocks(4, Placement.disk4),
                                      blockCount: oldRunBytes / 512,
                                      geometry: Placement.disk4)
        }
    }

    /// The replacement, `1 GiB − 1 MiB`, is accepted **and still produces a short final chunk** —
    /// so FR-TEST-5 is exercised on hardware exactly as before and the gate's expected chunk
    /// count is unchanged at 256.
    @Test func theNewGateConstantIsAcceptedAndStillEndsOnAShortChunk() throws {
        let newRunBytes: UInt64 = (1 << 30) - Placement.mib
        let ioSize: UInt64 = 4 << 20

        try RunPlacement.validate(startBlock: Placement.blocks(4, Placement.disk4),
                                  blockCount: newRunBytes / 512,
                                  geometry: Placement.disk4)

        #expect(newRunBytes % ioSize != 0, "the final chunk must still be short (FR-TEST-5)")
        #expect(newRunBytes / ioSize == 255)
        #expect((newRunBytes + ioSize - 1) / ioSize == 256, "the gate expects 256 chunks")
    }
}
