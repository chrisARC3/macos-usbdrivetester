//
//  DiscoveredDevice.swift
//  USBDriveTester (app target — unprivileged)
//
//  One USB mass-storage whole disk as discovered by the GUI (FR-DEV-1, FR-DEV-5/6),
//  plus the presentation strings that make the selected device unambiguous
//  (NFR-USE-3).
//
//  Pure value type: Foundation only. `IOKitDeviceEnumerator` builds these from the
//  registry; everything downstream — sorting, selection, display, and every unit test
//  — works on the struct and never touches hardware. That is what keeps the
//  hardware-dependent part of Step 5's gate as small as it is.
//
//  ## Geometry here is provisional
//
//  `logicalBlockSize` and the derived `blockCount` come from IOKit's `Preferred Block
//  Size` and `Size`. They satisfy FR-DEV-5 for display and planning, but the **final
//  authority is the helper's own `DKIOCGETBLOCKSIZE` / `DKIOCGETBLOCKCOUNT` ioctls on
//  the opened raw device** in Step 7, which is where BUILD-PLAN says to reconcile and
//  prefer the device-reported values. Nothing is written to a device on the strength
//  of the numbers in this struct.
//

import Foundation

/// Why a discovered device cannot be used as a run target.
///
/// A device with a problem is still **listed** (FR-DEV-1 says enumerate all connected
/// USB mass-storage devices, not the convenient ones) but is not selectable, and the
/// UI shows this text. Hiding a drive the user can plainly see in Disk Utility would
/// look like a bug in discovery; saying why it is unusable does not.
nonisolated enum DeviceGeometryProblem: Equatable, CustomStringConvertible {

    /// The reported logical block size is not one this tool supports (NFR-COMPAT-5).
    case unsupportedBlockSize(UInt32)

    /// The device reports zero bytes.
    case noCapacity

    /// Capacity is not a whole multiple of the block size, so the device does not
    /// describe an integer number of logical blocks.
    case sizeNotBlockAligned(sizeBytes: UInt64, logicalBlockSize: UInt32)

    var description: String {
        switch self {
        case .unsupportedBlockSize(let size):
            let supported = DiscoveredDevice.supportedBlockSizes.sorted()
                .map(String.init).joined(separator: " or ")
            return "Reports a \(size)-byte logical block size; this tool supports "
                 + "\(supported). The device cannot be tested."

        case .noCapacity:
            return "Reports zero capacity, so there is nothing to test. This usually "
                 + "means the drive is still initialising or is failing to enumerate."

        case .sizeNotBlockAligned(let size, let blockSize):
            return "Reports \(size) bytes, which is not a whole multiple of its "
                 + "\(blockSize)-byte logical block size. The reported geometry is "
                 + "inconsistent, so the device cannot be tested safely."
        }
    }
}

/// A connected USB mass-storage whole disk.
nonisolated struct DiscoveredDevice: Identifiable, Hashable {

    /// IOKit registry entry ID — a 64-bit identifier unique to this registry object
    /// for as long as it exists.
    ///
    /// Used as the identity for selection across refreshes, in preference to the BSD
    /// name. BSD names are **reused**: unplug `disk4` and plug in a different drive
    /// and it may well come back as `disk4` too. Keying selection on the name would
    /// silently transfer the user's selection onto a different physical device — the
    /// exact accident NFR-USE-3 exists to prevent. A replugged drive is a genuinely
    /// new registry object and deliberately does not inherit the old selection.
    let registryEntryID: UInt64

    /// BSD name of the whole disk, e.g. `disk4` (FR-DEV-6).
    let bsdName: BSDDeviceName

    /// `Vendor Name` from the IOKit Device Characteristics, if present.
    let vendorName: String?

    /// `Product Name` from the IOKit Device Characteristics, if present (FR-DEV-6).
    let productName: String?

    /// `Medium Type`, e.g. `Solid State`. Absent on most rotational drives, which is
    /// itself informative. Captured now because it is free at enumeration time and
    /// Step 14's "run this infrequently on NAND" warning (FR-WARN-2) will want it.
    let mediumType: String?

    /// Total capacity in bytes (IOKit `Size`) (FR-DEV-6, NFR-USE-3).
    let sizeBytes: UInt64

    /// Logical block size in bytes (IOKit `Preferred Block Size`) (FR-DEV-5).
    let logicalBlockSize: UInt32

    /// Names of any currently-mounted volumes on this disk.
    ///
    /// Not a gate item, and **not** the mount guard — Step 6 owns that, helper-side,
    /// and is the only thing that may permit a run. This is a label, and it earns its
    /// place because the machine this is developed on lists the user's working volume
    /// among the candidates. A list that shows the drive holding your source tree
    /// without saying so is a list that invites exactly one mistake.
    let mountedVolumeNames: [String]

    /// The USB device's serial number, or `nil` when it did not supply a usable one.
    ///
    /// **This is the only stable identity in this type.** `bsdName` is assigned at enumeration and
    /// changes on replug; `registryEntryID` is deliberately *not* stable across a replug either,
    /// so that re-plugging a drive cannot silently restore a selection onto different hardware.
    /// Neither can say which drive a run was performed on, which is what this is for.
    ///
    /// Sanitised by ``USBSerialNumber`` — see there for why a value can be present and still be
    /// rejected, and for what a serial does and does not identify.
    let usbSerialNumber: String?

    var id: UInt64 { registryEntryID }

    /// The serial for display, or a plain statement that there is not one.
    ///
    /// Never an empty string and never a placeholder: a blank where an identifier belongs reads as
    /// a rendering fault, and the user cannot tell it from a drive whose serial simply has not
    /// loaded yet.
    var serialDescription: String {
        usbSerialNumber ?? "Serial number not available"
    }

    /// `S/N 12345686DAA9`, or the not-available phrase standing alone.
    ///
    /// The prefix is dropped when there is no number, because `S/N Serial number not available`
    /// doubles the label.
    var serialSummary: String {
        guard let usbSerialNumber else { return serialDescription }
        return "S/N \(usbSerialNumber)"
    }

    // MARK: - Geometry (FR-DEV-5, NFR-COMPAT-5/6)

    /// Block sizes this tool accepts.
    ///
    /// - Important: this deliberately duplicates `DeviceGeometry.supportedBlockSizes`
    ///   in `Core/RunParameterValidator.swift`. Core compiles into the helper and the
    ///   test target but **not** the app (it would inherit the app's default
    ///   `MainActor` isolation), so the app cannot reference it. The two must agree:
    ///   if this set is ever widened without widening Core's, the app will offer a
    ///   device that the helper then refuses at the trust boundary, and the user gets
    ///   a rejection from a drive the UI said was fine.
    static let supportedBlockSizes: Set<UInt32> = [512, 4096]

    /// What stops this device being used, or `nil` when it is usable.
    ///
    /// Checked in the same order as `RunParameterValidator` so the two report the same
    /// root cause for the same device rather than two different symptoms.
    var geometryProblem: DeviceGeometryProblem? {
        guard Self.supportedBlockSizes.contains(logicalBlockSize) else {
            return .unsupportedBlockSize(logicalBlockSize)
        }
        guard sizeBytes > 0 else {
            return .noCapacity
        }
        guard sizeBytes % UInt64(logicalBlockSize) == 0 else {
            return .sizeNotBlockAligned(sizeBytes: sizeBytes,
                                        logicalBlockSize: logicalBlockSize)
        }
        return nil
    }

    /// Whether this device may be chosen as a run target.
    var isSelectable: Bool { geometryProblem == nil }

    /// Total addressable blocks (64-bit, NFR-COMPAT-6), or `nil` when the reported
    /// geometry is unusable.
    ///
    /// Optional rather than a best-effort division on purpose: a block count derived
    /// from geometry we have already judged inconsistent is a number that looks
    /// authoritative and is not.
    var blockCount: UInt64? {
        guard isSelectable else { return nil }
        return sizeBytes / UInt64(logicalBlockSize)
    }

    // MARK: - Presentation (FR-DEV-6, NFR-USE-3)

    /// Manufacturer and model, de-duplicated: IOKit reports vendor `Samsung` with
    /// product `Portable SSD T5`, but also vendor `Samsung` with product `SSD 990 EVO
    /// Plus`, and some bridges put the vendor inside the product string as well.
    /// Concatenating blindly yields "Samsung Samsung SSD…".
    var modelDescription: String {
        let vendor = vendorName?.trimmingCharacters(in: .whitespaces) ?? ""
        let product = productName?.trimmingCharacters(in: .whitespaces) ?? ""

        switch (vendor.isEmpty, product.isEmpty) {
        case (true, true):
            return "Unidentified device"
        case (false, true):
            return vendor
        case (true, false):
            return product
        case (false, false):
            let alreadyNamed = product.lowercased().hasPrefix(vendor.lowercased())
            return alreadyNamed ? product : "\(vendor) \(product)"
        }
    }

    /// The one-line identity of the device: `disk4 — Samsung Portable SSD T5`.
    var displayTitle: String { "\(bsdName) — \(modelDescription)" }

    /// Rounded, human-readable capacity: `1.00 TB`.
    var capacityDescription: String { CapacityFormatting.humanReadable(sizeBytes) }

    /// Exact capacity: `1,000,204,886,016 bytes` — reconcilable against `diskutil`.
    var exactCapacityDescription: String { CapacityFormatting.exactBytes(sizeBytes) }

    /// Geometry as shown for the selected device (FR-DEV-5 gate item).
    var geometryDescription: String {
        guard let blockCount else {
            return "\(logicalBlockSize)-byte blocks — block count unavailable"
        }
        return "\(CapacityFormatting.grouped(blockCount)) blocks × \(logicalBlockSize) bytes"
    }

    /// `Test_Drive` / `Macintosh HD, Data`, or `nil` when nothing is mounted.
    var mountedVolumesDescription: String? {
        mountedVolumeNames.isEmpty ? nil : mountedVolumeNames.joined(separator: ", ")
    }

    // MARK: - Ordering (FR-DEV-2)

    /// The presentation order of the device list.
    ///
    /// Kept here, next to the type, so every producer of a list — the enumerator, the
    /// live-refresh path, and the tests — sorts through one function rather than each
    /// writing its own closure and one of them getting it wrong.
    static func sorted(_ devices: [DiscoveredDevice]) -> [DiscoveredDevice] {
        devices.sorted { $0.bsdName < $1.bsdName }
    }

    /// What changed between two enumerations.
    ///
    /// The list is rebuilt wholesale on every hot-plug event rather than patched, which
    /// keeps the refresh path simple but leaves nothing to log — and BUILD-PLAN Step 5
    /// asks for device connect/disconnect to be logged (NFR-OBS-1). Diffing the two
    /// lists recovers the event from the state. Comparison is by registry entry ID, so
    /// a drive replaced by a different one on the same BSD name reads as one departure
    /// and one arrival rather than as nothing happening.
    static func changes(from previous: [DiscoveredDevice],
                        to current: [DiscoveredDevice]) -> DeviceSetChange {
        let previousIDs = Set(previous.map(\.registryEntryID))
        let currentIDs = Set(current.map(\.registryEntryID))
        return DeviceSetChange(
            added: current.filter { !previousIDs.contains($0.registryEntryID) },
            removed: previous.filter { !currentIDs.contains($0.registryEntryID) })
    }
}

/// The difference between two device enumerations (NFR-OBS-1).
nonisolated struct DeviceSetChange: Equatable {

    let added: [DiscoveredDevice]
    let removed: [DiscoveredDevice]

    var isEmpty: Bool { added.isEmpty && removed.isEmpty }

    /// A single log line: `connected disk4; disconnected disk8`.
    ///
    /// BSD names and capacities only — never anything read from the device
    /// (NFR-SEC-6).
    var logDescription: String {
        var parts: [String] = []
        if !added.isEmpty {
            parts.append("connected " + added.map(\.bsdName.rawValue).joined(separator: ", "))
        }
        if !removed.isEmpty {
            parts.append("disconnected " + removed.map(\.bsdName.rawValue).joined(separator: ", "))
        }
        return parts.isEmpty ? "no change" : parts.joined(separator: "; ")
    }
}
