//
//  DiscoveredDeviceTests.swift
//  FR-DEV-2/5/6, NFR-USE-3, NFR-COMPAT-5/6 — the device model and how it presents.
//
//  The block counts asserted below are cross-checked against `diskutil info`, which
//  reports its own count in 512-byte units: the T5 as "exactly 1953525168
//  512-Byte-Units" and the Seagate as "exactly 42970644479". Deriving the same numbers
//  from IOKit's `Size` and `Preferred Block Size` is evidence that FR-DEV-5's geometry
//  is being read correctly, independent of any assumption in this code.
//

import Testing
import Foundation
@testable import USBDriveTester

struct DiscoveredDeviceTests {

    // MARK: - Geometry (FR-DEV-5, NFR-COMPAT-5/6)

    @Test func derivesTheBlockCountDiskutilReports() {
        #expect(DeviceFixtures.testDrive.blockCount == 1_953_525_168)
        #expect(DeviceFixtures.testDrive.geometryProblem == nil)
        #expect(DeviceFixtures.testDrive.isSelectable)
    }

    /// 42,970,644,479 blocks does not fit in 32 bits — the whole point of NFR-COMPAT-6.
    @Test func handlesAMultiTerabyteDevice() {
        #expect(DeviceFixtures.largeDrive.blockCount == 42_970_644_479)
        #expect(DeviceFixtures.largeDrive.blockCount! > UInt64(UInt32.max))
        #expect(DeviceFixtures.largeDrive.isSelectable)
    }

    @Test func acceptsFourKilobyteBlocks() {
        // The internal SSD's geometry — not a USB device, but a real 4096-byte
        // reporter, and NFR-COMPAT-5 requires both geometries work.
        #expect(DeviceFixtures.internalDrive.logicalBlockSize == 4096)
        #expect(DeviceFixtures.internalDrive.blockCount == 61_279_344)
        #expect(DeviceFixtures.internalDrive.isSelectable)
    }

    @Test func rejectsAnUnsupportedBlockSize() {
        let device = DeviceFixtures.unsupportedBlockSize
        #expect(device.geometryProblem == .unsupportedBlockSize(2048))
        #expect(!device.isSelectable)
        #expect(device.blockCount == nil)
    }

    @Test func rejectsAZeroCapacityDevice() {
        let device = DeviceFixtures.device(sizeBytes: 0)
        #expect(device.geometryProblem == .noCapacity)
        #expect(!device.isSelectable)
    }

    @Test func rejectsACapacityThatIsNotAWholeNumberOfBlocks() {
        let device = DeviceFixtures.device(sizeBytes: 1_000_204_886_017, logicalBlockSize: 512)
        #expect(device.geometryProblem
                == .sizeNotBlockAligned(sizeBytes: 1_000_204_886_017, logicalBlockSize: 512))
        #expect(!device.isSelectable)
    }

    /// Checks run in the same order as `RunParameterValidator`, so the app and the
    /// helper name the same root cause for the same device rather than two different
    /// symptoms of it.
    @Test func reportsBlockSizeBeforeCapacityWhenBothAreWrong() {
        let device = DeviceFixtures.device(sizeBytes: 0, logicalBlockSize: 2048)
        #expect(device.geometryProblem == .unsupportedBlockSize(2048))
    }

    /// A `blockCount` derived from geometry already judged inconsistent would look
    /// authoritative and not be. It must stay absent.
    @Test func noBlockCountIsOfferedForUnusableGeometry() {
        #expect(DeviceFixtures.device(sizeBytes: 0).blockCount == nil)
        #expect(DeviceFixtures.device(logicalBlockSize: 2048).blockCount == nil)
        #expect(DeviceFixtures.device(sizeBytes: 513, logicalBlockSize: 512).blockCount == nil)
    }

    // MARK: - Problem messages (NFR-USE-5)

    @Test func everyProblemNamesItsCauseAndItsConsequence() {
        let problems: [DeviceGeometryProblem] = [
            .unsupportedBlockSize(2048),
            .noCapacity,
            .sizeNotBlockAligned(sizeBytes: 513, logicalBlockSize: 512),
        ]
        for problem in problems {
            #expect(!problem.description.isEmpty)
            #expect(problem.description.contains("cannot be tested")
                    || problem.description.contains("nothing to test"))
        }
    }

    @Test func theUnsupportedBlockSizeMessageNamesWhatIsSupported() {
        let message = DeviceGeometryProblem.unsupportedBlockSize(2048).description
        #expect(message.contains("2048"))
        #expect(message.contains("512"))
        #expect(message.contains("4096"))
    }

    // MARK: - Model naming (FR-DEV-6)

    @Test func combinesVendorAndProduct() {
        #expect(DeviceFixtures.testDrive.modelDescription == "Samsung Portable SSD T5")
        #expect(DeviceFixtures.largeDrive.modelDescription == "Seagate Expansion HDD")
    }

    /// IOKit reports the internal SSD with an **empty** vendor string, not a missing
    /// one — concatenating blindly would yield a leading space.
    @Test func anEmptyVendorStringDoesNotLeaveAGap() {
        #expect(DeviceFixtures.internalDrive.modelDescription == "APPLE SSD AP0256Z")
    }

    /// Some bridges repeat the manufacturer inside the product string.
    @Test func doesNotRepeatAVendorAlreadyInTheProductName() {
        let device = DeviceFixtures.device(vendor: "Samsung", product: "Samsung T7 Shield")
        #expect(device.modelDescription == "Samsung T7 Shield")
    }

    @Test func matchesTheVendorPrefixCaseInsensitively() {
        let device = DeviceFixtures.device(vendor: "SAMSUNG", product: "Samsung T7")
        #expect(device.modelDescription == "Samsung T7")
    }

    @Test func fallsBackToWhicheverNameIsPresent() {
        #expect(DeviceFixtures.device(vendor: "Samsung", product: nil).modelDescription
                == "Samsung")
        #expect(DeviceFixtures.device(vendor: nil, product: "Portable SSD T5").modelDescription
                == "Portable SSD T5")
    }

    /// A device with no identifying strings must still be describable — it is still
    /// listed, and it still must not be confusable with another one.
    @Test func anUnidentifiedDeviceStillHasAName() {
        let device = DeviceFixtures.device(vendor: nil, product: nil)
        #expect(device.modelDescription == "Unidentified device")
        #expect(device.displayTitle == "disk4 — Unidentified device")
    }

    @Test func alsoTreatsWhitespaceOnlyNamesAsAbsent() {
        let device = DeviceFixtures.device(vendor: "   ", product: "  ")
        #expect(device.modelDescription == "Unidentified device")
    }

    // MARK: - Presentation (NFR-USE-3)

    /// The BSD name always leads, because it is the one identifier that ties what the
    /// UI shows to what `diskutil` and the raw device node say.
    @Test func theDisplayTitleLeadsWithTheBSDName() {
        #expect(DeviceFixtures.testDrive.displayTitle == "disk4 — Samsung Portable SSD T5")
    }

    @Test func showsCapacityBothWays() {
        #expect(DeviceFixtures.testDrive.capacityDescription == "1.00 TB")
        // Grouped with the locale's separator; `grouped` is asserted against explicit
        // separators in CapacityFormattingTests, so this checks the wiring, not the
        // machine's region.
        let expected = CapacityFormatting.grouped(1_000_204_886_016) + " bytes"
        #expect(DeviceFixtures.testDrive.exactCapacityDescription == expected)
    }

    @Test func describesGeometryForTheSelectedDevice() {
        let description = DeviceFixtures.testDrive.geometryDescription
        #expect(description == "\(CapacityFormatting.grouped(1_953_525_168)) blocks × 512 bytes")
    }

    @Test func geometryDescriptionSaysSoWhenTheCountIsUnavailable() {
        let description = DeviceFixtures.device(sizeBytes: 0).geometryDescription
        #expect(description.contains("unavailable"))
    }

    @Test func mountedVolumesAreListedWhenPresent() {
        #expect(DeviceFixtures.workingDrive.mountedVolumesDescription == "1TB_Samsung")
        #expect(DeviceFixtures.testDrive.mountedVolumesDescription == nil)
    }

    @Test func multipleMountedVolumesAreJoined() {
        let device = DeviceFixtures.device(mountedVolumeNames: ["Macintosh HD", "Data"])
        #expect(device.mountedVolumesDescription == "Macintosh HD, Data")
    }

    // MARK: - Ordering (FR-DEV-2)

    @Test func sortsByBSDNameNumerically() {
        let unsorted = [DeviceFixtures.largeDrive,
                        DeviceFixtures.workingDrive,
                        DeviceFixtures.testDrive]
        let sorted = DiscoveredDevice.sorted(unsorted).map(\.bsdName.rawValue)
        #expect(sorted == ["disk4", "disk6", "disk8"])
    }

    @Test func sortIsIdempotent() {
        let once = DiscoveredDevice.sorted([DeviceFixtures.largeDrive,
                                            DeviceFixtures.testDrive,
                                            DeviceFixtures.workingDrive])
        let twice = DiscoveredDevice.sorted(once)
        #expect(once.map(\.id) == twice.map(\.id))
    }

    // MARK: - Identity

    /// Selection is keyed on the registry entry ID, so two devices that happen to
    /// share a BSD name across a replug are still distinct.
    @Test func identityIsTheRegistryEntryIDNotTheBSDName() {
        let first = DeviceFixtures.device(id: 1, bsdName: "disk4")
        let replugged = DeviceFixtures.device(id: 2, bsdName: "disk4")
        #expect(first.id != replugged.id)
        #expect(first != replugged)
    }
}
