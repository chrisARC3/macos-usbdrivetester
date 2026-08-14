//
//  RunSlicingTests.swift
//  Where a whole-device run's bounded calls fall (Step 11, increment 4). FR-TEST-4, FR-TEST-10.
//
//  ## The suite cross-checks against the helper's rule rather than restating this file's arithmetic
//
//  `RunSlicing` lives in the app module and `RunPlacement` lives in `Core/`, which compiles into
//  the helper and into this target but deliberately **not** into the app. This suite is the only
//  place both are visible at once — the same arrangement `RunControlWireTests` and
//  `DeviceAccessPreconditionTests.causeCodesMatchTheWireEnum` use — so every slice below is offered
//  to **the rule that actually refuses on hardware**, not to a second copy of the app's own
//  reasoning. A test that computed the expected slices the way the code computes them would agree
//  with any change, which is a check this project has already been bitten by.
//
//  ## Why a ragged cap is here, and why it is the only thing that makes the rounding observable
//
//  Measured 2026-08-14 against `RunPlacement.validate` over the 1 TB T5, the 4 TB T5 EVO, the 22 TB
//  Seagate and a 4,096-byte geometry: a sequencer advancing by a naive `min(cap, remaining)` — with
//  no rounding at all — produces **0 refusals and slices identical to `RunSlicing`'s** on every one
//  of them. It is safe only because `TesterProtocol.maximumBytesPerCall` happens to be a whole
//  multiple of 1 MiB.
//
//  So a suite that only ever sliced real devices at the real cap **could not tell the two apart**,
//  and a mutation deleting `RunSlicing`'s `* blocksPerBoundary` rounding would survive it. That is
//  predicted, not discovered. ``aRaggedCapStillProducesOnlyCallsTheHelperWouldAccept`` is what
//  kills it: at a cap of 1 GiB + 512 KiB the unrounded form asks for 1,024.5 MiB on **call 1**, a
//  length that is not a whole number of MiB and does not end at the device's last block.
//
//  (CONSTRAINTS section 1 and BUILD-PLAN Step 11 attribute that refusal to the naive form "on its
//  last-but-one call". It belongs to a different sequencer — one that backs the final call up to a
//  full 1 GiB — and is corrected in increment 7's docs pass. See `RunSlicing`'s header.)
//

import Testing
import Foundation
// `TesterProtocol` lives in `Shared/` and arrives through the app module, the way
// `RunPlacementTests` takes it. `RunPlacement` and `DeviceGeometry` are `Core/` and compile
// directly into this target.
@testable import USBDriveTester

// MARK: - Fixtures

private enum Slicing {

    static let mib: UInt64 = 1 << 20

    /// The 1 TB T5 scratch drive (serial `12345686DAA9`). **Not** a whole number of MiB —
    /// 953,869 MiB plus 1,456 blocks — which is what the final-call exemption exists for.
    static let scratch = DeviceGeometry(logicalBlockSize: 512, blockCount: 1_953_525_168)

    /// The 4 TB T5 EVO fixture (serial `00000S7CLNJ0WC02266P`). 7,814,037,168 blocks, **above
    /// 2³²** — the NFR-COMPAT-6 case, and also not a whole number of MiB.
    static let fixture = DeviceGeometry(logicalBlockSize: 512, blockCount: 7_814_037_168)

    /// The other supported geometry (NFR-COMPAT-5), ragged in blocks as well as in MiB.
    static let largeBlocks = DeviceGeometry(logicalBlockSize: 4_096, blockCount: 244_190_646)

    /// Exactly 32 MiB, so there is no short final call at all.
    static let wholeMiB = DeviceGeometry(logicalBlockSize: 512, blockCount: 32 * 2_048)

    /// Smaller than one call at the real cap, and ragged: one short call covers the whole thing.
    static let tiny = DeviceGeometry(logicalBlockSize: 512, blockCount: 3_000)

    /// 100 MiB plus 700 blocks. Small enough to slice at a 1 MiB cap in a hundred calls, and
    /// ragged in the same way the real drives are — which is the whole of what the ragged-cap
    /// cases need, since the property under test belongs to the cap and not to the device.
    static let smallRagged = DeviceGeometry(logicalBlockSize: 512, blockCount: 205_500)

    /// The same idea on 4,096-byte geometry: 30 MiB plus 50 blocks.
    static let smallRagged4096 = DeviceGeometry(logicalBlockSize: 4_096, blockCount: 7_730)

    /// What a walk of a whole device found.
    struct Walk {
        var calls: [RunCall] = []
        /// Every reason a call was refused by `RunPlacement` — the helper's own rule — or by
        /// `RunParameterValidator`, the device's contract, or by the per-call cap.
        var refusals: [String] = []
        var endedCleanly = false
    }

    /// Slice a whole device and offer **every** call to the helper's rule.
    ///
    /// - Parameter callLimit: a runaway guard. A slicer that returned a zero-length call would
    ///   otherwise loop forever, and a hung suite is a worse failure report than a red one.
    static func walk(_ geometry: DeviceGeometry,
                     cap: UInt64,
                     callLimit: Int = 100_000) -> Walk {
        var walk = Walk()
        var position: UInt64 = 0

        while walk.calls.count < callLimit {
            switch RunSlicing.nextCall(from: position,
                                       logicalBlockSize: geometry.logicalBlockSize,
                                       deviceBlockCount: geometry.blockCount,
                                       maximumBytesPerCall: cap) {
            case .deviceCovered:
                walk.endedCleanly = true
                return walk

            case .cannotSlice(let reason):
                walk.refusals.append("cannotSlice: \(reason)")
                return walk

            case .call(let call):
                walk.calls.append(call)

                // The product's placement policy — what the helper refuses on hardware.
                do {
                    try RunPlacement.validate(startBlock: call.startBlock,
                                              blockCount: call.blockCount,
                                              geometry: geometry)
                } catch {
                    walk.refusals.append("call \(walk.calls.count): \(error)")
                }

                // The device's own contract: alignment and range.
                let blockSize = UInt64(geometry.logicalBlockSize)
                do {
                    _ = try RunParameterValidator.validate(
                        byteOffset: call.startBlock * blockSize,
                        byteLength: call.blockCount * blockSize,
                        geometry: geometry)
                } catch {
                    walk.refusals.append("call \(walk.calls.count) device contract: \(error)")
                }

                // The per-call cap the helper also enforces.
                if call.blockCount * blockSize > cap {
                    walk.refusals.append("call \(walk.calls.count) exceeds the cap")
                }

                if call.blockCount == 0 {
                    walk.refusals.append("call \(walk.calls.count) is zero-length")
                    return walk
                }
                position = call.endBlock
            }
        }
        walk.refusals.append("the walk did not terminate within \(callLimit) calls")
        return walk
    }

    /// Whether the calls tile the device exactly, in order, with no gap and no overlap.
    static func tilesExactly(_ walk: Walk, _ geometry: DeviceGeometry) -> Bool {
        var expected: UInt64 = 0
        for call in walk.calls {
            if call.startBlock != expected { return false }
            expected = call.endBlock
        }
        return expected == geometry.blockCount && walk.endedCleanly
    }

    /// Whether only the **final** call is short of a whole number of MiB.
    static func onlyTheFinalCallIsShort(_ walk: Walk, _ geometry: DeviceGeometry) -> Bool {
        let blockSize = UInt64(geometry.logicalBlockSize)
        for call in walk.calls.dropLast() where (call.blockCount * blockSize) % mib != 0 {
            return false
        }
        return true
    }
}

// MARK: - The two constants duplicated from Core

struct RunSlicingConstantTests {

    /// `RunSlicing.boundaryBytes` is a copy of `RunPlacement.boundaryBytes`, because `Core/` is not
    /// visible to the app module. Two copies of a constant is exactly the duplication that survives
    /// until somebody changes one of them, so this is the pin — and it reads each from its own
    /// side rather than from a shared literal, which would be a test that agrees with any change.
    @Test func theBoundaryMatchesTheHelpersOwn() {
        #expect(RunSlicing.boundaryBytes == RunPlacement.boundaryBytes)
        #expect(RunSlicing.boundaryBytes == 1_048_576)
    }

    @Test func theSupportedBlockSizesMatchTheHelpersOwn() {
        #expect(RunSlicing.supportedBlockSizes == DeviceGeometry.supportedBlockSizes)
    }

    @Test func blocksPerBoundaryMatchesTheHelpersOwn() {
        for size in DeviceGeometry.supportedBlockSizes {
            #expect(RunSlicing.blocksPerBoundary(logicalBlockSize: size)
                    == RunPlacement.blocksPerBoundary(logicalBlockSize: size))
        }
        #expect(RunSlicing.blocksPerBoundary(logicalBlockSize: 512) == 2_048)
        #expect(RunSlicing.blocksPerBoundary(logicalBlockSize: 4_096) == 256)
    }
}

// MARK: - Whole-device walks at the real cap

struct RunSlicingWalkTests {

    private static let realCap = TesterProtocol.maximumBytesPerCall

    /// Every geometry this project actually addresses, sliced end to end, with **every** call
    /// offered to `RunPlacement.validate`.
    @Test(arguments: [Slicing.scratch, Slicing.fixture, Slicing.largeBlocks,
                      Slicing.wholeMiB, Slicing.tiny])
    func everyCallOfARealDeviceIsOneTheHelperWouldAccept(_ geometry: DeviceGeometry) {
        let walk = Slicing.walk(geometry, cap: Self.realCap)

        #expect(walk.refusals.isEmpty, "the helper's own rule refused a call this slicer produced")
        #expect(Slicing.tilesExactly(walk, geometry), "the calls do not tile the device exactly")
        #expect(Slicing.onlyTheFinalCallIsShort(walk, geometry),
                "a call other than the last covers a partial MiB")
        #expect(!walk.calls.isEmpty)
    }

    /// The counts are stated rather than merely "some number of calls", so a slicer that covered
    /// the device in one enormous call — or in twice as many as it should — is a failure and not a
    /// pass.
    @Test func theScratchDriveIsSlicedIntoTheExpectedCalls() {
        let walk = Slicing.walk(Slicing.scratch, cap: Self.realCap)
        #expect(walk.calls.count == 932)
        #expect(walk.calls.first == RunCall(startBlock: 0, blockCount: 2_097_152))
        // 931 whole gibibytes, then 525 MiB + 1,456 blocks to the end.
        #expect(walk.calls.last == RunCall(startBlock: 1_952_448_512, blockCount: 1_076_656))
        #expect(walk.calls.last?.endBlock == Slicing.scratch.blockCount)
    }

    @Test func aDeviceThatIsAWholeNumberOfMiBHasNoShortFinalCall() {
        let walk = Slicing.walk(Slicing.wholeMiB, cap: 4 * Slicing.mib)
        #expect(walk.refusals.isEmpty)
        #expect(walk.calls.count == 8)
        for call in walk.calls {
            #expect(call.blockCount * 512 % Slicing.mib == 0)
        }
    }

    @Test func aDeviceSmallerThanOneCallIsCoveredByOneShortCall() {
        let walk = Slicing.walk(Slicing.tiny, cap: Self.realCap)
        #expect(walk.refusals.isEmpty)
        #expect(walk.calls == [RunCall(startBlock: 0, blockCount: 3_000)])
    }

    @Test func theEndOfTheDeviceReportsCoveredRatherThanAnEmptyCall() {
        let outcome = RunSlicing.nextCall(from: Slicing.scratch.blockCount,
                                          logicalBlockSize: 512,
                                          deviceBlockCount: Slicing.scratch.blockCount,
                                          maximumBytesPerCall: Self.realCap)
        #expect(outcome == .deviceCovered)
    }
}

// MARK: - The ragged cap: what makes the rounding observable at all

/// A cap that is **not** a whole multiple of 1 MiB, paired with a device to slice at it.
///
/// The pairing is not decoration. A small ragged cap over a 1 TB device is ~119,000 calls, which
/// is a slow test that proves nothing the same cap over a 100 MiB device does not — the property
/// under test is a property of the **cap**. The two large geometries are therefore paired only
/// with the large cap, where the walk is under 4,000 calls.
fileprivate struct RaggedCase: CustomStringConvertible {
    let label: String
    let cap: UInt64
    let geometry: DeviceGeometry

    /// **Derived by walking, not asserted from arithmetic** (2026-08-14), so a slicer that stopped
    /// early or covered the device in one call is a failure here rather than a silent pass. Without
    /// it "no refusals" would also be satisfied by a slicer that refused to slice at all.
    let expectedCalls: Int

    var description: String { label }
}

/// File scope rather than a static on the suite below, because a `@Test(arguments:)` attribute
/// cannot name a member of the type it is attached to.
fileprivate let raggedCases: [RaggedCase] = [
    // 1 GiB + 512 KiB: the unrounded form asks for 1,024.5 MiB on call 1 — a length that is not a
    // whole number of MiB and does not end at the device's last block. This is the case that kills
    // the "delete the rounding" mutation against a real drive.
    RaggedCase(label: "1 GiB + 512 KiB over the 1 TB T5",
               cap: (1 << 30) + (512 << 10), geometry: Slicing.scratch, expectedCalls: 932),
    RaggedCase(label: "1 GiB + 512 KiB over the 4 TB T5 EVO",
               cap: (1 << 30) + (512 << 10), geometry: Slicing.fixture, expectedCalls: 3_727),
    RaggedCase(label: "8 MiB + 256 KiB",
               cap: (8 << 20) + (256 << 10), geometry: Slicing.smallRagged, expectedCalls: 13),
    // A whole MiB plus exactly one 512-byte block.
    RaggedCase(label: "3 MiB + one block",
               cap: (3 << 20) + 512, geometry: Slicing.smallRagged, expectedCalls: 34),
    // Not even a multiple of the block size.
    RaggedCase(label: "1 MiB + 100 bytes",
               cap: (1 << 20) + 100, geometry: Slicing.smallRagged, expectedCalls: 101),
    // Just *under* a whole MiB, on 4,096-byte geometry: rounds down to 4 MiB, not up to 5.
    RaggedCase(label: "5 MiB − one block, 4,096-byte blocks",
               cap: (5 << 20) - 512, geometry: Slicing.smallRagged4096, expectedCalls: 8),
    // A device that is a whole number of MiB, so nothing is short and every call must still align.
    RaggedCase(label: "1 MiB + 100 bytes over a whole-MiB device",
               cap: (1 << 20) + 100, geometry: Slicing.wholeMiB, expectedCalls: 32),
    RaggedCase(label: "1 MiB + 100 bytes over a sub-call device",
               cap: (1 << 20) + 100, geometry: Slicing.tiny, expectedCalls: 2),
]

struct RunSlicingRaggedCapTests {

    @Test(arguments: raggedCases)
    fileprivate func aRaggedCapStillProducesOnlyCallsTheHelperWouldAccept(_ testCase: RaggedCase) {
        let walk = Slicing.walk(testCase.geometry, cap: testCase.cap)

        #expect(walk.refusals.isEmpty,
                "a ragged cap produced a call the helper's own rule refuses")
        #expect(Slicing.tilesExactly(walk, testCase.geometry))
        #expect(Slicing.onlyTheFinalCallIsShort(walk, testCase.geometry))
        #expect(walk.calls.count == testCase.expectedCalls)
    }

    /// Stated concretely as well as as a property, because "no refusals" would also be satisfied by
    /// a slicer that refused to slice at all.
    @Test func aRaggedCapIsRoundedDownToTheWholeMiBBelowIt() {
        let outcome = RunSlicing.nextCall(from: 0,
                                          logicalBlockSize: 512,
                                          deviceBlockCount: Slicing.scratch.blockCount,
                                          maximumBytesPerCall: (1 << 30) + (512 << 10))
        // 1,024.5 MiB rounded down to 1,024 MiB — not the 2,098,176 blocks the cap would allow.
        #expect(outcome == .call(RunCall(startBlock: 0, blockCount: 2_097_152)))
    }
}

// MARK: - What cannot be sliced, and says so

struct RunSlicingRefusalTests {

    /// **The reason this is three cases and not an optional.** A cap below the boundary can produce
    /// no call at all, and an optional would make that indistinguishable from "the device is
    /// covered" — a sequencer reading that answer would report a completed run that covered
    /// nothing.
    @Test func aCapBelowOneMiBCannotSliceRatherThanReportingTheDeviceCovered() {
        let outcome = RunSlicing.nextCall(from: 0,
                                          logicalBlockSize: 512,
                                          deviceBlockCount: 1_000_000,
                                          maximumBytesPerCall: (1 << 20) - 1)
        #expect(outcome != .deviceCovered)
        guard case .cannotSlice(let reason) = outcome else {
            Issue.record("expected a refusal, got \(outcome)")
            return
        }
        #expect(reason.contains("1 MiB"))
    }

    @Test(arguments: [UInt32(0), 1, 511, 1_024, 2_048, 8_192])
    func anUnsupportedBlockSizeCannotSlice(_ blockSize: UInt32) {
        let outcome = RunSlicing.nextCall(from: 0,
                                          logicalBlockSize: blockSize,
                                          deviceBlockCount: 1_000_000,
                                          maximumBytesPerCall: TesterProtocol.maximumBytesPerCall)
        guard case .cannotSlice = outcome else {
            Issue.record("block size \(blockSize) should not be sliceable, got \(outcome)")
            return
        }
    }

    @Test func aDeviceWithNoBlocksCannotSlice() {
        let outcome = RunSlicing.nextCall(from: 0,
                                          logicalBlockSize: 512,
                                          deviceBlockCount: 0,
                                          maximumBytesPerCall: TesterProtocol.maximumBytesPerCall)
        guard case .cannotSlice = outcome else {
            Issue.record("a zero-block device should not be sliceable, got \(outcome)")
            return
        }
    }

    /// A resume point is always 1 MiB-aligned — a run starts on a boundary and every chunk is 1, 2,
    /// 4 or 8 MiB, measured aligned in all four pre-flight cases. This refuses one that is not
    /// rather than issuing a call the helper would reject, so a wiring defect is named here instead
    /// of arriving as a refusal with no report attached.
    @Test func aMisalignedPositionIsRefusedRatherThanIssued() {
        let outcome = RunSlicing.nextCall(from: 1,
                                          logicalBlockSize: 512,
                                          deviceBlockCount: 1_000_000,
                                          maximumBytesPerCall: TesterProtocol.maximumBytesPerCall)
        guard case .cannotSlice(let reason) = outcome else {
            Issue.record("a misaligned position should be refused, got \(outcome)")
            return
        }
        #expect(reason.contains("1 MiB"))
    }

    @Test func aPositionPastTheEndIsRefusedRatherThanReportedCovered() {
        let outcome = RunSlicing.nextCall(from: 1_000_001,
                                          logicalBlockSize: 512,
                                          deviceBlockCount: 1_000_000,
                                          maximumBytesPerCall: TesterProtocol.maximumBytesPerCall)
        #expect(outcome != .deviceCovered)
        guard case .cannotSlice = outcome else {
            Issue.record("expected a refusal, got \(outcome)")
            return
        }
    }
}
