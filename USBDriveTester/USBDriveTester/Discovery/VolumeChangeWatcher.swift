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

import Foundation
import DiskArbitration
import os

private nonisolated let log = Logger(subsystem: HelperIdentity.loggingSubsystem,
                                     category: "discovery")

/// Watches for volumes being mounted and unmounted.
///
/// Reports *that* something changed, not what: the device list is rebuilt wholesale, so
/// the callback is a prompt to re-read the mount table rather than a description of the
/// change. Callbacks are delivered on the main queue.
nonisolated final class VolumeChangeWatcher {

    private var session: DASession?
    private var onChange: (() -> Void)?

    deinit {
        stop()
    }

    func start(onChange: @escaping () -> Void) {
        guard session == nil else { return }

        guard let session = DASessionCreate(kCFAllocatorDefault) else {
            log.error("DASessionCreate failed; mounted-volume state will not live-update")
            return
        }
        self.session = session
        self.onChange = onChange

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
        DARegisterDiskAppearedCallback(session, nil, volumeAppeared, context)
        DARegisterDiskDisappearedCallback(session, nil, volumeAppeared, context)

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
        log.notice("stopped watching for volume mount/unmount")
    }

    /// Called from the DiskArbitration callbacks, on the main queue.
    fileprivate func volumeSetChanged() {
        onChange?()
    }
}

private nonisolated func volumeDescriptionChanged(_ disk: DADisk,
                                      _ keys: CFArray,
                                      _ context: UnsafeMutableRawPointer?) {
    notifyWatcher(context)
}

private nonisolated func volumeAppeared(_ disk: DADisk, _ context: UnsafeMutableRawPointer?) {
    notifyWatcher(context)
}

private nonisolated func notifyWatcher(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    Unmanaged<VolumeChangeWatcher>.fromOpaque(context).takeUnretainedValue().volumeSetChanged()
}
