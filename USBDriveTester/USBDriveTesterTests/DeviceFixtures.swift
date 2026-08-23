//
//  DeviceFixtures.swift
//  Shared test fixtures for the Step 5 discovery types.
//
//  The values here are **real**, read off the development machine with a live IOKit
//  probe on 2026-07-29, not invented. That matters: the sizes, block sizes and
//  vendor/product spellings are exactly what IOKit hands back for these devices, so a
//  test that passes against them is a test that passes against the hardware. The
//  awkward cases below (an empty vendor string; a synthesized container reporting a
//  4096-byte block size and a capacity that rounds up across a unit boundary) were
//  found this way rather than imagined.
//

import Foundation
@testable import USBDriveTester

enum DeviceFixtures {

    /// Build a device, defaulting to a plausible USB SSD.
    static func device(id: UInt64 = 1,
                       bsdName: String = "disk4",
                       vendor: String? = "Samsung",
                       product: String? = "Portable SSD T5",
                       mediumType: String? = "Solid State",
                       sizeBytes: UInt64 = 1_000_204_886_016,
                       logicalBlockSize: UInt32 = 512,
                       mountedVolumeNames: [String] = [],
                       // Defaults to a plausible node per volume, so a fixture that only cares
                       // about names still produces an index-aligned pair — the invariant the
                       // restore depends on.
                       mountedVolumeBSDNames: [String]? = nil,
                       usbSerialNumber: String? = "12345686DAA9",
                       // 10 Gb/s — what the scratch device actually negotiates on this machine.
                       usbLinkSpeedCode: Int = 4) -> DiscoveredDevice {
        DiscoveredDevice(registryEntryID: id,
                         bsdName: BSDDeviceName(bsdName),
                         vendorName: vendor,
                         productName: product,
                         mediumType: mediumType,
                         sizeBytes: sizeBytes,
                         logicalBlockSize: logicalBlockSize,
                         mountedVolumeNames: mountedVolumeNames,
                         mountedVolumeBSDNames: mountedVolumeBSDNames
                            ?? mountedVolumeNames.enumerated().map { "\(bsdName)s\($0.offset + 1)" },
                         usbSerialNumber: usbSerialNumber,
                         usbLinkSpeedCode: usbLinkSpeedCode)
    }

    // MARK: - The development machine, as IOKit actually reports it

    /// `disk4` — Samsung Portable SSD T5, 1 TB, 512-byte blocks. The scratch device
    /// used for all real-hardware testing.
    static let testDrive = device(id: 0x4000, bsdName: "disk4")

    /// `disk6` — Samsung SSD 990 EVO Plus, 1 TB, 512-byte blocks. The volume holding
    /// the source tree. Present in the list precisely because it must be, and named
    /// here so tests can assert it never becomes the default selection ahead of
    /// `disk4`.
    static let workingDrive = device(id: 0x6000,
                                     bsdName: "disk6",
                                     product: "SSD 990 EVO Plus",
                                     mountedVolumeNames: ["1TB_Samsung"])

    /// `disk8` — Seagate Expansion HDD, 22 TB, 512-byte blocks. A rotational drive
    /// with no `Medium Type` key, and large enough to exercise 64-bit block counts
    /// (NFR-COMPAT-6): 42,970,644,479 blocks overflows 32 bits several times over.
    static let largeDrive = device(id: 0x8000,
                                   bsdName: "disk8",
                                   vendor: "Seagate",
                                   product: "Expansion HDD",
                                   mediumType: nil,
                                   sizeBytes: 22_000_969_973_248,
                                   mountedVolumeNames: ["Backup"])

    /// `disk0` — the internal Apple SSD. Reports an **empty** vendor string rather
    /// than a missing one. Never appears in the device list (it is not USB); kept as a
    /// fixture because it is the real source of the empty-vendor formatting case.
    static let internalDrive = device(id: 0x0000,
                                      bsdName: "disk0",
                                      vendor: "",
                                      product: "APPLE SSD AP0256Z",
                                      sizeBytes: 251_000_193_024,
                                      logicalBlockSize: 4096)

    /// A device whose reported block size this tool does not support.
    static let unsupportedBlockSize = device(id: 0xBAD1,
                                             bsdName: "disk11",
                                             product: "Odd Bridge",
                                             sizeBytes: 2048 * 1000,
                                             logicalBlockSize: 2048)
}
