//
//  MountedVolumesTests.swift
//  NFR-USE-3 — attributing mounted volumes to the physical disk they live on.
//
//  The case that carries the weight is `resolvesAnAPFSVolumeToItsPhysicalDisk`. The
//  intuitive implementation — parse `disk7s1` down to `disk7` — produces a volume that
//  belongs to no listed device, because `disk7` is a synthesized container and the
//  physical disk is `disk6`. The symptom would be quiet and plausible: every
//  APFS-formatted drive simply showing no volumes, on a screen whose entire job is to
//  stop you picking the wrong drive.
//

import Testing
import Foundation
@testable import USBDriveTester

struct MountedVolumesTests {

    // MARK: - Device-node parsing

    @Test func parsesASliceNode() {
        #expect(MountTable.bsdName(fromDeviceNode: "/dev/disk7s1") == "disk7s1")
    }

    @Test func parsesAWholeDiskNode() {
        #expect(MountTable.bsdName(fromDeviceNode: "/dev/disk4") == "disk4")
    }

    /// Real entries from the mount table that have no block device behind them.
    @Test(arguments: ["map auto_home", "devfs", "map -hosts", "", "/dev/", "//dev/disk1"])
    func ignoresNodesThatAreNotBlockDevices(_ node: String) {
        #expect(MountTable.bsdName(fromDeviceNode: node) == nil)
    }

    // MARK: - Volume naming

    @Test func namesAVolumeAfterItsMountPoint() {
        #expect(MountTable.volumeName(fromMountPoint: "/Volumes/1TB_Samsung") == "1TB_Samsung")
        #expect(MountTable.volumeName(fromMountPoint: "/Volumes/Test_Drive") == "Test_Drive")
    }

    @Test func keepsSpacesInVolumeNames() {
        #expect(MountTable.volumeName(fromMountPoint: "/Volumes/Time Machine") == "Time Machine")
    }

    /// The root volume has no last path component. Defined behaviour rather than a
    /// guess — the device list only shows USB disks, so it never appears there.
    @Test func theRootMountPointIsReturnedAsIs() {
        #expect(MountTable.volumeName(fromMountPoint: "/") == "/")
    }

    // MARK: - Attribution

    /// The development machine, exactly as it is mounted: `1TB_Samsung` is mounted
    /// from `/dev/disk7s1`, but `disk7` is a synthesized APFS container and the
    /// physical disk is `disk6`. Only the registry subtree connects them.
    @Test func resolvesAnAPFSVolumeToItsPhysicalDisk() {
        let table = [
            MountedVolume(deviceNode: "/dev/disk3s1", bsdName: "disk3s1", mountPoint: "/"),
            MountedVolume(deviceNode: "/dev/disk7s1", bsdName: "disk7s1",
                          mountPoint: "/Volumes/1TB_Samsung"),
            MountedVolume(deviceNode: "/dev/disk4s2", bsdName: "disk4s2",
                          mountPoint: "/Volumes/Test_Drive"),
        ]

        // What the registry walk returns for the physical disk6: its own name, its
        // partitions, the synthesized container, and the container's volumes.
        let disk6Subtree: Set<String> = ["disk6", "disk6s1", "disk6s2", "disk7", "disk7s1"]

        #expect(MountTable.volumeNames(on: disk6Subtree, in: table) == ["1TB_Samsung"])
    }

    @Test func attributesOnlyItsOwnVolumes() {
        let table = [
            MountedVolume(deviceNode: "/dev/disk7s1", bsdName: "disk7s1",
                          mountPoint: "/Volumes/1TB_Samsung"),
            MountedVolume(deviceNode: "/dev/disk4s2", bsdName: "disk4s2",
                          mountPoint: "/Volumes/Test_Drive"),
        ]
        let disk4Subtree: Set<String> = ["disk4", "disk4s1", "disk4s2"]

        #expect(MountTable.volumeNames(on: disk4Subtree, in: table) == ["Test_Drive"])
    }

    @Test func findsSeveralVolumesOnOneDisk() {
        let table = [
            MountedVolume(deviceNode: "/dev/disk8s2", bsdName: "disk8s2",
                          mountPoint: "/Volumes/Backup"),
            MountedVolume(deviceNode: "/dev/disk9s1", bsdName: "disk9s1",
                          mountPoint: "/Volumes/Time Machine"),
        ]
        let disk8Subtree: Set<String> = ["disk8", "disk8s1", "disk8s2", "disk8s3",
                                         "disk9", "disk9s1"]

        #expect(MountTable.volumeNames(on: disk8Subtree, in: table)
                == ["Backup", "Time Machine"])
    }

    /// Mount-table order, not sorted, so a device's volumes read the same way twice
    /// running.
    @Test func preservesMountTableOrder() {
        let table = [
            MountedVolume(deviceNode: "/dev/disk8s3", bsdName: "disk8s3",
                          mountPoint: "/Volumes/Zulu"),
            MountedVolume(deviceNode: "/dev/disk8s2", bsdName: "disk8s2",
                          mountPoint: "/Volumes/Alpha"),
        ]
        #expect(MountTable.volumeNames(on: ["disk8s2", "disk8s3"], in: table)
                == ["Zulu", "Alpha"])
    }

    /// The same volume name reached twice (a bind-style duplicate mount) is listed
    /// once — a row reading "Backup, Backup" would look like a bug in the app.
    @Test func deduplicatesRepeatedNames() {
        let table = [
            MountedVolume(deviceNode: "/dev/disk8s2", bsdName: "disk8s2",
                          mountPoint: "/Volumes/Backup"),
            MountedVolume(deviceNode: "/dev/disk8s3", bsdName: "disk8s3",
                          mountPoint: "/Volumes/Backup"),
        ]
        #expect(MountTable.volumeNames(on: ["disk8s2", "disk8s3"], in: table) == ["Backup"])
    }

    @Test func findsNothingForAnUnmountedDisk() {
        let table = [MountedVolume(deviceNode: "/dev/disk3s1", bsdName: "disk3s1",
                                   mountPoint: "/")]
        #expect(MountTable.volumeNames(on: ["disk4", "disk4s1"], in: table).isEmpty)
    }

    @Test func findsNothingInAnEmptyTable() {
        #expect(MountTable.volumeNames(on: ["disk4"], in: []).isEmpty)
    }

    /// Synthetic mounts carry no BSD name and must never match a disk.
    @Test func ignoresSyntheticMounts() {
        let table = [MountedVolume(deviceNode: "map auto_home", bsdName: nil,
                                   mountPoint: "/System/Volumes/Data/home")]
        #expect(MountTable.volumeNames(on: ["disk4"], in: table).isEmpty)
    }

    // MARK: - Reading the real mount table

    /// A smoke test over the `getfsstat` wiring: every Mac has a root volume, and it
    /// has a name derived from its mount point. Asserts the plumbing, not the machine.
    @Test func readsTheSystemMountTable() {
        let table = MountTable.current()
        #expect(!table.isEmpty)
        #expect(table.contains { $0.mountPoint == "/" })
        #expect(table.allSatisfy { !$0.volumeName.isEmpty })
    }

    /// Whatever is mounted, entries with a `/dev/` node must parse into a BSD name —
    /// this is what connects the real table to the pure attribution above.
    @Test func realDeviceNodesParse() {
        for volume in MountTable.current() where volume.deviceNode.hasPrefix("/dev/") {
            #expect(volume.bsdName != nil,
                    "failed to parse a BSD name from \(volume.deviceNode)")
        }
    }
}
