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

// MARK: - A failed unmount is undone (user decision 2026-08-06)

/// `DADiskUnmount` with `kDADiskUnmountOptionWhole` dissents as a unit, but volumes it had
/// already unmounted **stay unmounted** — so a refusal by one busy volume leaves a multi-volume
/// drive half-dismounted. Reported from real use, with the wrong drive selected:
///
/// > *"I very much wanted an easy way to restore the mounted volumes."*
///
/// The operation now either fully succeeds or puts the drive back. What is tested here is the
/// **message**, because that is the whole user-visible surface of the rollback and it has two
/// outcomes that must not read alike: the drive was restored, or it was not and this app could
/// not restore it.
struct UnmountRollbackMessageTests {

    private static let refusal =
        "Could not unmount Test_Drive on disk8: the volume is in use by another process. "
      + "Close any open files or applications using the drive, then try again."

    /// The original DiskArbitration reason survives the rollback. It names the volume and the
    /// cause (NFR-USE-5), and a rollback notice that replaced it would leave the user knowing the
    /// drive is fine and not knowing why the unmount failed.
    @Test func theOriginalReasonIsAlwaysKept() {
        for restore in [VolumeMountOutcome.succeeded("ok"), .failed("no")] {
            let text = VolumeMountOutcome.unmountRolledBack(failure: Self.refusal,
                                                            restore: restore)
            #expect(text.contains("Could not unmount Test_Drive on disk8"))
            #expect(text.contains("in use by another process"))
        }
    }

    @Test func aSuccessfulRollbackSaysTheDriveShouldBeBackAsItWas() {
        let text = VolumeMountOutcome.unmountRolledBack(failure: Self.refusal,
                                                        restore: .succeeded("asked macOS"))
        #expect(text.contains("asked to remount"))
        #expect(text.contains("back as it was"))
    }

    /// **Deliberately not "restored".** The mount is asynchronous and the device list is what
    /// actually shows the result; asserting a state we have not observed is the same error as a
    /// report claiming "0 bad blocks" without saying whether it could tell.
    @Test func aSuccessfulRollbackDoesNotClaimAnObservedResult() {
        let text = VolumeMountOutcome.unmountRolledBack(failure: Self.refusal,
                                                        restore: .succeeded("asked macOS"))
        #expect(text.lowercased().contains("have been restored") == false)
        #expect(text.contains("shows what is mounted now"))
    }

    /// The worse outcome, and it must be unmistakable: the drive has been left changed and this
    /// app could not change it back. It must not read like the success case.
    @Test func aFailedRollbackSaysTheDriveWasLeftChanged() {
        let text = VolumeMountOutcome.unmountRolledBack(
            failure: Self.refusal,
            restore: .failed("Could not mount the volumes on disk8: not permitted"))

        #expect(text.contains("could NOT be remounted") || text.contains("NOT be remounted"))
        #expect(text.contains("left partly unmounted"))
        #expect(text.contains("Disk Utility"), "it must say where the user can go instead")
        #expect(text.contains("not permitted"), "the remount's own reason survives too")
    }

    /// The two outcomes must be distinguishable at a glance — this is the one place a user finds
    /// out whether their drive is as they left it.
    @Test func theTwoOutcomesDoNotReadAlike() {
        let restored = VolumeMountOutcome.unmountRolledBack(failure: Self.refusal,
                                                            restore: .succeeded("ok"))
        let stranded = VolumeMountOutcome.unmountRolledBack(failure: Self.refusal,
                                                            restore: .failed("no"))
        #expect(restored != stranded)
        #expect(restored.contains("back as it was"))
        #expect(stranded.contains("back as it was") == false)
    }
}

// MARK: - Unmount, verified and rolled back (user decisions 2026-08-06)

/// The sequencing, in full. Three defects were found here in three rounds, each hidden by the one
/// above it, and every one of them is a row below:
///
/// 1. **`DADiskUnmount` reports success while a volume is still mounted.** The log recorded
///    `unmount succeeded on disk6: Unmounted every volume on disk6: 1TB_Samsung` for a volume in
///    active use. Two features were built on `isSuccess` and were inert by construction.
/// 2. **The mount table lags that callback.** Reading it immediately judged a *successful*
///    unmount to have failed, so every unmount was rolled back.
/// 3. **The rollback used a whole-disk mount**, which mounts every *mountable* volume — putting
///    an EFI partition on the desktop that had never been mounted.
///
/// Both operations, the mount-table read and the retry are injected, so all of it is decided
/// without a drive, DiskArbitration, a clock or a window.
struct RestoringUnmountTests {

    private final class Log {
        var calls: [String] = []
        var restored: [String] = []
    }

    /// `mountTableReadings` is consumed one per look, so a lagging table can be modelled exactly:
    /// `[["Test_Drive"], []]` is "still there, then gone".
    private func run(unmountResult: VolumeMountOutcome,
                     mountedBefore: [(name: String, bsdName: String)] = [
                        (name: "Test_Drive", bsdName: "disk8s2")],
                     mountTableReadings: [[String]],
                     restoreResult: VolumeMountOutcome = .succeeded("asked macOS"),
                     attempts: Int = 12) -> (Log, VolumeMountOutcome?) {
        let log = Log()
        var readings = mountTableReadings
        var final: VolumeMountOutcome?

        VolumeMounter.restoringUnmount(
            unmount: { done in log.calls.append("unmount"); done(unmountResult) },
            mountedBefore: mountedBefore,
            volumesStillMounted: {
                log.calls.append("look")
                return readings.isEmpty ? [] : readings.removeFirst()
            },
            retry: { again in log.calls.append("retry"); again() },
            attempts: attempts,
            restore: { lost, done in
                log.calls.append("restore")
                log.restored = lost
                done(restoreResult)
            },
            completion: { final = $0 })
        return (log, final)
    }

    // MARK: Defect 1 — the dissenter cannot be believed

    @Test func aReportedSuccessWithVolumesStillMountedIsAFailure() {
        let (log, final) = run(unmountResult: .succeeded("Unmounted every volume on disk8: Test_Drive."),
                               mountTableReadings: [["Test_Drive"]],
                               attempts: 1)
        #expect(log.calls.contains("restore"))
        #expect(final?.isSuccess == false)
        #expect(final?.message.contains("macOS reported success") == true)
        #expect(final?.message.contains("No reason was given") == true)
    }

    /// A dissented unmount keeps quoting its own reason — the postcondition check adds a case, it
    /// does not replace the one that already worked.
    @Test func aDissentedUnmountStillQuotesItsReason() {
        let (_, final) = run(unmountResult: .failed("Could not unmount Test_Drive on disk8: busy."),
                             mountTableReadings: [["Test_Drive"]], attempts: 1)
        #expect(final?.message.contains("busy") == true)
        #expect(final?.message.contains("No reason was given") == false,
                "there was a reason; do not claim otherwise")
    }

    // MARK: Defect 2 — the table lags, so the look is retried

    /// **The row that stops a good unmount being undone.** The table still lists the volume on the
    /// first look and is clear on the second; that is a success, with nothing remounted.
    @Test func aLaggingMountTableIsWaitedOutRatherThanRolledBack() {
        let (log, final) = run(unmountResult: .succeeded("Unmounted every volume on disk8: Test_Drive."),
                               mountTableReadings: [["Test_Drive"], []])
        #expect(log.calls == ["unmount", "look", "retry", "look"])
        #expect(log.calls.contains("restore") == false, "nothing may be remounted")
        #expect(final?.isSuccess == true)
    }

    /// A table that clears immediately costs no retries at all.
    @Test func aCleanUnmountSettlesOnTheFirstLook() {
        let (log, final) = run(unmountResult: .succeeded("Unmounted every volume on disk8: Test_Drive."),
                               mountTableReadings: [[]])
        #expect(log.calls == ["unmount", "look"])
        #expect(final?.isSuccess == true)
    }

    /// And the budget is finite: a drive that never clears is concluded to have failed rather than
    /// retried forever.
    @Test func aVolumeThatNeverClearsExhaustsTheAttemptsAndRollsBack() {
        let (log, final) = run(unmountResult: .succeeded("ok"),
                               mountTableReadings: [["Test_Drive"], ["Test_Drive"], ["Test_Drive"]],
                               attempts: 3)
        #expect(log.calls.filter { $0 == "look" }.count == 3)
        #expect(log.calls.contains("restore"))
        #expect(final?.isSuccess == false)
    }

    // MARK: Defect 3 — restore exactly what went, never a whole-disk mount

    /// **The EFI row.** Two volumes were mounted, one stayed; only the one that went is put back.
    /// A whole-disk mount would have brought up EFI, which was never in `mountedBefore` because it
    /// was never mounted.
    @Test func onlyTheVolumesThatActuallyWentAreRestored() {
        let (log, _) = run(unmountResult: .failed("busy"),
                           mountedBefore: [(name: "Time Machine", bsdName: "disk4s2"),
                                           (name: "Backup", bsdName: "disk4s3")],
                           mountTableReadings: [["Backup"]],
                           attempts: 1)
        #expect(log.restored == ["disk4s2"], "Backup stayed mounted; only Time Machine went")
    }

    /// An EFI partition that was never mounted cannot appear in the restore set, whatever else
    /// happens — it is absent from `mountedBefore` by construction.
    @Test func anUnmountedEfiPartitionIsNeverRestored() {
        let (log, _) = run(unmountResult: .failed("busy"),
                           mountedBefore: [(name: "Test_Drive", bsdName: "disk8s2")],
                           mountTableReadings: [[]] + [["Test_Drive"]],
                           attempts: 1)
        #expect(log.restored.contains("disk8s1") == false)
        #expect(log.restored.allSatisfy { $0 == "disk8s2" })
    }

    /// Nothing went, so nothing is restored — the rollback must not mount a drive whose volumes
    /// all stayed put.
    @Test func nothingIsRestoredWhenNothingWentAway() {
        let (log, _) = run(unmountResult: .failed("busy"),
                           mountedBefore: [(name: "Test_Drive", bsdName: "disk8s2")],
                           mountTableReadings: [["Test_Drive"]],
                           attempts: 1)
        #expect(log.restored.isEmpty)
    }

    // MARK: The result

    /// The user asked for an unmount and did not get one, so this is a failure whether or not the
    /// drive was put back.
    @Test func theOutcomeIsAFailureEvenWhenTheRestoreWorked() {
        let (_, final) = run(unmountResult: .failed("busy"), mountTableReadings: [["Test_Drive"]],
                             restoreResult: .succeeded("ok"), attempts: 1)
        #expect(final?.isSuccess == false)
        #expect(final?.message.contains("back as it was") == true)
    }

    @Test func aFailedRestoreSaysTheDriveWasLeftChanged() {
        let (_, final) = run(unmountResult: .failed("busy"), mountTableReadings: [["Test_Drive"]],
                             restoreResult: .failed("nope"), attempts: 1)
        #expect(final?.message.contains("left partly unmounted") == true)
        #expect(final?.message.contains("Disk Utility") == true)
    }

    /// Exactly one result reaches the caller, on every path. Two would leave the control's
    /// in-flight flag and its message disagreeing about which operation they belong to.
    @Test func theCallerIsToldExactlyOnceOnEveryPath() {
        for readings in [[[String]()], [["Test_Drive"], []], [["Test_Drive"]]] {
            var count = 0
            VolumeMounter.restoringUnmount(
                unmount: { done in done(.failed("busy")) },
                mountedBefore: [(name: "Test_Drive", bsdName: "disk8s2")],
                volumesStillMounted: { var r = readings; return r.isEmpty ? [] : r.removeFirst() },
                retry: { $0() },
                attempts: 2,
                restore: { _, done in done(.succeeded("ok")) },
                completion: { _ in count += 1 })
            #expect(count == 1)
        }
    }
}

/// `VolumeMounter.unmountEach` — the per-volume unmount fan-out (2026-08-09).
///
/// ## The defect this replaced, and why nothing caught it for three steps
///
/// `unmountAll` used `DADiskUnmount(kDADiskUnmountOptionWhole)` on the *physical* disk, on the
/// documented reading that it acts on "the volumes tied to the whole disk object". Measured on
/// hardware, it unmounts the disk's **direct partitions only** and reports **success with no
/// dissenter** having skipped any volume inside an APFS container. From `diskarbitrationd`:
///
///     unmounted disk, id = /dev/disk8s2, success.     <- exFAT, a direct partition
///     unmounted disk, id = /dev/disk8s4, success.     <- HFS+,  a direct partition
///     (no line for /dev/disk9s1 — the APFS volume was never attempted)
///
/// It survived from Step 6 because **every write gate targets the scratch T5, whose only volume
/// is exFAT** — a direct partition. The one drive the apparatus may touch cannot exhibit the bug.
/// It is also the true mechanism behind the 2026-08-06 note *"DADiskUnmount reports success while
/// a volume is still mounted"*: `1TB_Samsung` is APFS on synthesized `disk7`, so it was never
/// unmounted rather than slow to unmount.
///
/// The operation is injected, so *which volumes are attempted* and *what a partial refusal
/// reports* are decided without DiskArbitration, a drive or a window — which is the half where
/// the defect actually lived.
struct UnmountEachTests {

    private final class Log {
        var attempted: [String] = []
    }

    private func run(_ volumes: [(name: String, bsdName: String)],
                     refusing: [String: String] = [:],
                     on wholeDisk: String = "disk8") -> (Log, VolumeMountOutcome?) {
        let log = Log()
        var final: VolumeMountOutcome?
        VolumeMounter.unmountEach(
            volumes,
            on: wholeDisk,
            using: { node, done in
                log.attempted.append(node)
                if let reason = refusing[node] { done(.failed(reason)) } else { done(.succeeded("unmounted")) }
            },
            completion: { final = $0 })
        return (log, final)
    }

    private static let threeVolumes = [
        (name: "Vol_ExFAT", bsdName: "disk8s2"),
        (name: "Vol_APFS",  bsdName: "disk9s1"),   // synthesized disk — the skipped one
        (name: "Vol_HFS",   bsdName: "disk8s4"),
    ]

    // MARK: The defect itself

    /// **The regression test for the whole-disk unmount.** Every mounted volume must be
    /// attempted *by its own node* — including one whose node is on a synthesized disk and is
    /// therefore not derivable from the physical disk by prefix. A reversion to a single
    /// whole-disk call attempts `disk8` and nothing else.
    @Test func everyMountedVolumeIsAttemptedByItsOwnNode() {
        let (log, final) = run(Self.threeVolumes)
        #expect(log.attempted == ["disk8s2", "disk9s1", "disk8s4"])
        #expect(log.attempted.contains("disk9s1"))   // the APFS volume the old code skipped
        #expect(!log.attempted.contains("disk8"))    // never the physical disk
        #expect(final?.isSuccess == true)
    }

    /// The success message may only claim what was actually attempted and succeeded. The old
    /// code logged "Unmounted every volume on disk8: Vol_ExFAT, Vol_APFS, Vol_HFS" while
    /// `Vol_APFS` stayed mounted — a true-looking sentence about an action never taken.
    @Test func theSuccessMessageNamesTheVolumesThatWent() {
        let (_, final) = run(Self.threeVolumes)
        #expect(final?.message.contains("Vol_ExFAT") == true)
        #expect(final?.message.contains("Vol_APFS") == true)
        #expect(final?.message.contains("Vol_HFS") == true)
        #expect(final?.message.contains("disk8") == true)
    }

    // MARK: Partial refusal — the state the rollback then undoes

    @Test func oneRefusalFailsTheWholeOperation() {
        let (log, final) = run(Self.threeVolumes, refusing: ["disk9s1": "the disk is in use."])
        #expect(final?.isSuccess == false)
        // The others are still attempted — that partial state is exactly what the rollback exists
        // to undo, so short-circuiting on the first refusal would hide it rather than avoid it.
        #expect(log.attempted.count == 3)
    }

    /// Only the volume that refused is named, with its own reason. The whole-disk version named
    /// every volume on the drive whatever had happened, telling a user with one busy volume that
    /// all three had failed and leaving them to guess which to close (NFR-USE-5).
    @Test func onlyTheRefusingVolumeIsNamedAndItQuotesItsOwnReason() {
        let (_, final) = run(Self.threeVolumes, refusing: ["disk9s1": "the disk is in use."])
        #expect(final?.message.contains("Vol_APFS") == true)
        #expect(final?.message.contains("the disk is in use.") == true)
        #expect(final?.message.contains("Vol_ExFAT") == false)
        #expect(final?.message.contains("Vol_HFS") == false)
    }

    @Test func severalRefusalsAreAllNamed() {
        let (_, final) = run(Self.threeVolumes,
                             refusing: ["disk9s1": "in use.", "disk8s4": "busy."])
        #expect(final?.message.contains("Vol_APFS") == true)
        #expect(final?.message.contains("Vol_HFS") == true)
        #expect(final?.message.contains("Vol_ExFAT") == false)
    }

    @Test func aRefusalTellsTheUserWhatToDo() {
        let (_, final) = run(Self.threeVolumes, refusing: ["disk8s2": "in use."])
        #expect(final?.message.contains("Close any open files") == true)
    }

    // MARK: Boundaries

    /// Nothing mounted is not an unmount. The postcondition already holds, and the message must
    /// not read as though volumes were dismounted — the same distinction `mount(volumeBSDNames:)`
    /// draws with "No volumes needed remounting."
    @Test func nothingMountedSucceedsWithoutClaimingAnUnmountHappened() {
        let (log, final) = run([])
        #expect(log.attempted.isEmpty)
        #expect(final?.isSuccess == true)
        #expect(final?.message.contains("No volumes were mounted") == true)
        #expect(final?.message.contains("Unmounted every volume") == false)
    }

    @Test func aSingleVolumeStillWorks() {
        let (log, final) = run([(name: "Test_Drive", bsdName: "disk10s2")])
        #expect(log.attempted == ["disk10s2"])
        #expect(final?.isSuccess == true)
    }

    /// Exactly one result reaches the caller however the volumes resolve — two would leave the
    /// control's in-flight flag and its message disagreeing about which operation they belong to.
    @Test func theCallerIsToldExactlyOnce() {
        for refusing in [[:], ["disk9s1": "in use."], ["disk8s2": "a.", "disk9s1": "b.", "disk8s4": "c."]] {
            var count = 0
            VolumeMounter.unmountEach(
                Self.threeVolumes,
                on: "disk8",
                using: { node, done in
                    if let reason = refusing[node] { done(.failed(reason)) } else { done(.succeeded("unmounted")) }
                },
                completion: { _ in count += 1 })
            #expect(count == 1)
        }
    }
}
