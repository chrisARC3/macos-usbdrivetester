//
//  VolumeChangeWatcher.swift
//  USBDriveTester (app target — unprivileged)
//
//  Reports volume mount and unmount, so the device list's mounted-volume column stays
//  true (NFR-USE-3).
//
//  ## Why IOKit alone is not enough — the defect this exists to fix
//
//  `IOKitDeviceEnumerator` watches the IOKit *media* set: whole disks appearing and
//  disappearing. Mounting is not a change to that set. Observed on 2026-07-30, with the
//  device list watching IOKit only:
//
//      $ diskutil unmount /Volumes/Test_Drive
//      Volume Test_Drive on disk4s2 unmounted
//      ... no notification fired; the list still read "mounted  Test_Drive"
//
//  The same gap appears on replug, which is how it was first noticed: a drive
//  enumerates, the list rebuilds within ~50 ms, and `diskarbitrationd` mounts the
//  volumes some time *after* that. The snapshot is taken before there is anything to
//  see, and nothing ever asks again.
//
//  It is worse than a merely stale field. The mounted-volume column exists to stop the
//  wrong drive being chosen, and both of its failure directions mislead: a mounted drive
//  that reads as empty invites selecting it, and an unmounted drive that reads as
//  mounted trains the user to ignore the warning.
//
//  ## Why this was not caught earlier
//
//  APFS hides it. Mounting an APFS volume publishes a new `AppleAPFSMedia` object, which
//  *is* a whole-media change and so does fire the IOKit notification — so an
//  APFS-formatted drive appears to work. The exFAT scratch drive has no such side
//  effect. Any test using an APFS drive would have passed.
//
//  ## Choice of mechanism
//
//  DiskArbitration rather than `NSWorkspace`'s `didMountNotification`. NSWorkspace is
//  fewer lines, but it is AppKit-level and does not reliably deliver in a plain
//  command-line process — which would have meant `scripts/device-probe.sh` could no
//  longer reproduce or verify this exact defect. A fix whose regression test cannot run
//  headlessly is a fix that quietly rots. DiskArbitration also matches Step 6, which
//  uses it helper-side for the unmount and the exclusive claim.
//
//  ## Step 12 (2026-09-05): disappearance is no longer anonymous
//
//  Until chunk 2 this file registered `DARegisterDiskDisappearedCallback` **with the appearance
//  handler**, and every path threw the `DADisk` away — because "something changed, re-read the
//  mount table" was all anybody needed. Route (b) of device-loss detection needs the opposite:
//  *which* disk, and it needs it on the one path where nothing else can see the event. A paused
//  run issues no syscalls, so `ENXIO` never arrives; this callback is the only thing that fires.
//
//  Three things were measured rather than assumed, on 2026-09-05, against a real DiskArbitration
//  session driven by `hdiutil` ram disks (full account in `CONSTRAINTS.md`):
//
//    1. **An unmounted whole disk does fire `DADiskDisappeared`.** That is the shape a claimed
//       device has — Step 6 unmounts it before the run — so the obvious worry, that an already
//       unmounted disk has nothing left to report, is not the case.
//    2. **`DADiskGetBSDName` and `DADiskCopyDescription` both still work inside the callback**,
//       and the description carries `DAMediaWhole`. Neither is obvious for an object describing
//       something that no longer exists.
//    3. **A partitioned drive fires once for the whole disk and once per slice**, so a consumer
//       must be idempotent. `DAVolumePath` is already absent by then even for a volume that was
//       mounted a moment earlier — so a disappearance cannot be matched by its mount point.
//       *(2026-09-11: that is an **unclaimed** drive's unplug — the ram disks had nothing
//       claimed. Under a run's exclusive claim the slices go at the claim, and the unplug fires
//       the whole disk only: eight of eight on two drives, 2026-09-09 and 2026-09-11, in
//       `CONSTRAINTS.md` §1, *Under a claim*.)*
//

import Foundation
import DiskArbitration
import os

private nonisolated let log = Logger(subsystem: HelperIdentity.loggingSubsystem,
                                     category: "discovery")

/// A disk that has just left the machine — as much as DiskArbitration can still say about it.
///
/// Deliberately not a `DADisk`: this is what route (b) hands to a decision, and a decision that
/// takes a DiskArbitration handle cannot be tested without DiskArbitration.
nonisolated struct DisappearedDisk: Equatable {

    /// The name the disk had. Read with `DADiskGetBSDName` inside the disappearance callback —
    /// **measured 2026-09-05 to still be readable there**, which is not obvious for an object
    /// describing something that no longer exists.
    let bsdName: BSDDeviceName

    /// Whether this was a whole disk rather than one of its slices.
    ///
    /// From `DAMediaWhole` on the disappearing disk's own description, which is **also** still
    /// readable in the callback. Preferred over parsing the name because it is what the system
    /// says rather than what the string looks like — `BSDDeviceName.isWholeDiskName` is the
    /// fallback for the case where the description cannot be copied at all.
    let isWholeDisk: Bool

    init(bsdName: BSDDeviceName, isWholeDisk: Bool) {
        self.bsdName = bsdName
        self.isWholeDisk = isWholeDisk
    }
}

/// Watches for volumes being mounted and unmounted, and for disks leaving.
///
/// The mount/unmount side reports *that* something changed, not what: the device list is rebuilt
/// wholesale, so the callback is a prompt to re-read the mount table rather than a description of
/// the change. **Disappearance is the exception** — it names the disk, because route (b) of
/// device-loss detection has to know whether the disk that went was the one under test.
///
/// Callbacks are delivered on the main queue.
nonisolated final class VolumeChangeWatcher {

    private var session: DASession?
    private var onChange: (() -> Void)?
    private var onDiskDisappeared: ((DisappearedDisk) -> Void)?

    deinit {
        stop()
    }

    /// - Parameters:
    ///   - onChange: something in the mount table or the disk set changed. Says nothing about
    ///     *what*, because the device list is rebuilt wholesale.
    ///   - onDiskDisappeared: a disk left, and **which one** (Step 12, chunk 4). Delivered
    ///     straight from the callback, deliberately **not** through the enumerator's 200 ms
    ///     coalescing window: that window exists to collapse a burst of events into one list
    ///     rebuild, and collapsing is exactly what throws the subject away. A run holding an
    ///     exclusive claim on a drive that has gone should not wait behind a debounce meant for
    ///     a table view.
    func start(onChange: @escaping () -> Void,
               onDiskDisappeared: @escaping (DisappearedDisk) -> Void) {
        guard session == nil else { return }

        guard let session = DASessionCreate(kCFAllocatorDefault) else {
            log.error("DASessionCreate failed; mounted-volume state will not live-update")
            return
        }
        self.session = session
        self.onChange = onChange
        self.onDiskDisappeared = onDiskDisappeared

        let context = Unmanaged.passUnretained(self).toOpaque()

        // The precise signal: a disk's volume path appearing or disappearing is exactly
        // a mount or an unmount.
        let watchedKeys = [kDADiskDescriptionVolumePathKey] as CFArray
        DARegisterDiskDescriptionChangedCallback(session, nil, watchedKeys,
                                                 volumeDescriptionChanged, context)

        // Appearance and disappearance are registered too, for the case where a disk
        // object shows up already carrying a volume path rather than acquiring one.
        // These fire for every partition, and DiskArbitration replays them for existing
        // disks when the session starts — both harmless, because every path funnels into
        // the enumerator's coalescing window rather than triggering a rebuild directly.
        //
        // **Two handlers, not one.** Disappearance used to be registered with `diskAppeared`;
        // it now has its own, because it is the one event whose *subject* matters (Step 12
        // route (b)). The replay at session start is appearances only, so the disappearance
        // handler never fires for a disk that is still present.
        DARegisterDiskAppearedCallback(session, nil, diskAppeared, context)
        DARegisterDiskDisappearedCallback(session, nil, diskDisappeared, context)

        DASessionSetDispatchQueue(session, DispatchQueue.main)
        log.notice("watching for volume mount/unmount")
    }

    func stop() {
        guard let session else { return }

        // Detaching the dispatch queue stops delivery, and dropping the last reference
        // to the session tears the registrations down with it. `DAUnregisterCallback`
        // is deliberately not used: it takes the callback as a raw pointer, which from
        // Swift means bitcasting a function value — unsound, and buying nothing here
        // because the session is going away regardless.
        DASessionSetDispatchQueue(session, nil)
        self.session = nil
        onChange = nil
        onDiskDisappeared = nil
        log.notice("stopped watching for volume mount/unmount")
    }

    /// Called from the DiskArbitration callbacks, on the main queue.
    fileprivate func volumeSetChanged() {
        onChange?()
    }

    /// A disk left the machine (Step 12 route (b), NFR-OBS-1).
    ///
    /// **Logged whether or not a run is in progress**, and at notice level rather than debug: a
    /// drive leaving is rare, so the volume is negligible, and the whole point of NFR-OBS-1 is
    /// that an interrupted run can be reconstructed *after the fact*. A log that only records
    /// disappearances during runs cannot answer "did the drive drop out just before I pressed
    /// Start?", which is the question a person actually asks.
    ///
    /// Slices are logged too, and labelled, because "disk7 went and so did disk7s1" is the shape
    /// of a real unplug and its absence would be worth noticing.
    ///
    /// The mount table is re-read as well, exactly as before — a disk leaving is also a change
    /// the device list needs, and that path is unchanged and still coalesced.
    fileprivate func diskLeft(_ disk: DisappearedDisk) {
        log.notice("a disk disappeared: \(disk.bsdName.rawValue, privacy: .public) (\(disk.isWholeDisk ? "whole disk" : "slice", privacy: .public))")

        // **The named channel first, then the anonymous one.** A run whose drive has just left is
        // the more urgent consumer, and the ordering costs nothing: the list rebuild is coalesced
        // behind a 200 ms window either way, so it cannot be starved by going second.
        onDiskDisappeared?(disk)
        onChange?()
    }
}

private nonisolated func volumeDescriptionChanged(_ disk: DADisk,
                                      _ keys: CFArray,
                                      _ context: UnsafeMutableRawPointer?) {
    notifyWatcher(context)
}

private nonisolated func diskAppeared(_ disk: DADisk, _ context: UnsafeMutableRawPointer?) {
    notifyWatcher(context)
}

/// A disk went away. Unlike every other callback here, **the subject matters** — see the header.
private nonisolated func diskDisappeared(_ disk: DADisk, _ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let watcher = Unmanaged<VolumeChangeWatcher>.fromOpaque(context).takeUnretainedValue()
    watcher.diskLeft(describe(disk))
}

/// Read what DiskArbitration will still say about a disk that has just gone.
///
/// Both reads are measured to work inside the disappearance callback (2026-09-05). The fallbacks
/// exist because "measured to work" is a fact about one macOS on one day, and a root-adjacent
/// path that traps on a nil the API is entitled to return is worse than one that degrades: a
/// missing name yields an empty `BSDDeviceName`, which matches no device under test, and a
/// missing description falls back to parsing the name for whole-ness.
private nonisolated func describe(_ disk: DADisk) -> DisappearedDisk {
    let name = DADiskGetBSDName(disk).map { String(cString: $0) } ?? ""
    let bsdName = BSDDeviceName(name)

    guard let description = DADiskCopyDescription(disk) as? [String: Any],
          let whole = description[kDADiskDescriptionMediaWholeKey as String] else {
        return DisappearedDisk(bsdName: bsdName, isWholeDisk: bsdName.isWholeDiskName)
    }

    // `DAMediaWhole` arrives as a `CFBoolean`, which bridges to `NSNumber` rather than to `Bool`
    // through `[String: Any]`. Both are tried rather than assuming which, because getting it
    // wrong would silently report every whole disk as a slice.
    let isWhole = (whole as? NSNumber)?.boolValue ?? (whole as? Bool) ?? bsdName.isWholeDiskName
    return DisappearedDisk(bsdName: bsdName, isWholeDisk: isWhole)
}

private nonisolated func notifyWatcher(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    Unmanaged<VolumeChangeWatcher>.fromOpaque(context).takeUnretainedValue().volumeSetChanged()
}
