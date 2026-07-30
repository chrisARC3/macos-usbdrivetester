//
//  MountedVolumes.swift
//  USBDriveTester (app target — unprivileged)
//
//  Which volumes are currently mounted, so the device list can say so (NFR-USE-3).
//
//  ## What this is NOT
//
//  This is **not** the mount guard. Step 6 owns that: the guard is helper-side, uses
//  DiskArbitration, and is the only thing that may permit a run (FR-SAFE-1/2, NFR-REL-3).
//  Nothing here gates anything. It is a label on a list row, and it exists because the
//  machine this is built on lists the drive holding the source tree among the
//  candidate devices. A list that shows that drive without saying what is on it is a
//  list that invites exactly one mistake.
//
//  ## The APFS wrinkle
//
//  The obvious implementation — read the mount table, turn `/dev/disk6s2` into
//  `disk6` — is wrong on any APFS volume. The mount table does not name the physical
//  disk. `1TB_Samsung` is mounted from `/dev/disk7s1`, and `disk7` is a *synthesized*
//  APFS container that only reaches the physical `disk6` through the IOKit registry:
//
//      IOMedia disk6                     <- the physical whole disk
//        IOMedia disk6s2                 <- the APFS container's backing partition
//          AppleAPFSContainerScheme
//            AppleAPFSMedia disk7        <- synthesized; the mount table stops here
//              AppleAPFSVolume disk7s1   <- "/dev/disk7s1" -> /Volumes/1TB_Samsung
//
//  So the mapping runs the other way: `IOKitDeviceEnumerator` collects every BSD name
//  in the registry subtree *below* a physical whole disk and hands that set to
//  ``MountTable/volumeNames(on:in:)``. The parsing and matching below are pure and
//  unit-tested; only ``MountTable/current()`` touches the system.
//

import Foundation

/// One entry from the system mount table.
nonisolated struct MountedVolume: Equatable {

    /// The device node the volume is mounted from, e.g. `/dev/disk7s1`.
    let deviceNode: String

    /// The BSD name parsed out of ``deviceNode``, e.g. `disk7s1`, or `nil` for
    /// synthetic mounts (`map auto_home`, network shares) that have no device node.
    let bsdName: String?

    /// Where it is mounted, e.g. `/Volumes/1TB_Samsung`.
    let mountPoint: String

    /// The name to show the user, e.g. `1TB_Samsung`.
    var volumeName: String { MountTable.volumeName(fromMountPoint: mountPoint) }
}

nonisolated enum MountTable {

    // MARK: - Reading the system mount table

    /// Snapshot the current mount table.
    ///
    /// Uses `getfsstat` rather than `getmntinfo`: `getmntinfo` returns a pointer to a
    /// static buffer that is overwritten by the next caller anywhere in the process,
    /// which is a poor fit for something invoked from a hot-plug callback.
    ///
    /// `MNT_NOWAIT` returns cached information rather than asking each filesystem to
    /// update its statistics. That is what is wanted here — this runs on every device
    /// refresh, and a stalled network mount must not be able to hang the device list.
    static func current() -> [MountedVolume] {
        let count = getfsstat(nil, 0, MNT_NOWAIT)
        guard count > 0 else { return [] }

        var stats = Array(repeating: statfs(), count: Int(count))
        let written = getfsstat(&stats,
                                Int32(MemoryLayout<statfs>.stride * Int(count)),
                                MNT_NOWAIT)
        guard written > 0 else { return [] }

        return stats.prefix(Int(written)).map { entry in
            let deviceNode = string(from: entry.f_mntfromname)
            return MountedVolume(deviceNode: deviceNode,
                                 bsdName: bsdName(fromDeviceNode: deviceNode),
                                 mountPoint: string(from: entry.f_mntonname))
        }
    }

    /// Convert one of `statfs`' fixed-size `CChar` tuples into a `String`.
    private static func string<T>(from tuple: T) -> String {
        withUnsafePointer(to: tuple) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) {
                String(cString: $0)
            }
        }
    }

    // MARK: - Pure helpers

    /// `/dev/disk7s1` -> `disk7s1`.
    ///
    /// Returns `nil` for anything that is not a `/dev/` node — `map auto_home`,
    /// `devfs`, network shares — which are mounts with no block device behind them and
    /// so can never belong to a listed disk.
    static func bsdName(fromDeviceNode node: String) -> String? {
        let prefix = "/dev/"
        guard node.hasPrefix(prefix) else { return nil }
        let name = String(node.dropFirst(prefix.count))
        return name.isEmpty ? nil : name
    }

    /// `/Volumes/1TB_Samsung` -> `1TB_Samsung`.
    ///
    /// The root mount point has no last component; it is returned as `/` rather than
    /// guessed at. The device list only ever shows USB disks, so the root volume does
    /// not appear there — this is defined behaviour rather than a case being handled.
    static func volumeName(fromMountPoint mountPoint: String) -> String {
        let name = (mountPoint as NSString).lastPathComponent
        return name.isEmpty || name == "/" ? mountPoint : name
    }

    /// The names of any mounted volumes living on the given set of BSD names.
    ///
    /// - Parameters:
    ///   - bsdNames: Every BSD name in the registry subtree below one physical whole
    ///     disk — including the whole disk itself, its partitions, and any synthesized
    ///     container and volumes beneath them (see the file header).
    ///   - table: A snapshot from ``current()``.
    /// - Returns: Volume names in mount-table order, de-duplicated. Order is preserved
    ///   rather than sorted so a device's volumes read the same way twice running.
    static func volumeNames(on bsdNames: Set<String>, in table: [MountedVolume]) -> [String] {
        var seen = Set<String>()
        var names: [String] = []

        for volume in table {
            guard let bsdName = volume.bsdName, bsdNames.contains(bsdName) else { continue }
            let name = volume.volumeName
            if seen.insert(name).inserted {
                names.append(name)
            }
        }
        return names
    }
}
