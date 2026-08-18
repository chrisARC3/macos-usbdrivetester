//
//  VolumeMounter.swift
//  USBDriveTester (app target — unprivileged)
//
//  Mounts or unmounts every volume of a selected device (FR-SAFE-5), through
//  DiskArbitration.
//
//  ## Why this is app-side and not in the helper
//
//  It needs no privilege: `diskutil unmountDisk` succeeds without `sudo` on an external
//  drive, and DiskArbitration authorises the caller itself. Keeping it here holds the
//  privileged XPC surface down to check / acquire / release (NFR-SEC-3) — the helper runs
//  as root, so every method that does not have to exist there should not.
//
//  ## Unmount is PER VOLUME, BY NODE. Mount All is whole-disk. The asymmetry is the point.
//
//  This file used to drive both directions with the whole-disk options, on the reasoning that
//  `kDADiskUnmountOptionWhole` acts on "the volumes tied to the whole disk object" — what
//  `diskutil unmountDisk` does — so letting `diskarbitrationd` resolve the physical-disk ↔
//  APFS-volume relationship was "both less code and correct for filesystems we have not tested
//  against".
//
//  **MEASURED FALSE, 2026-08-09.** `DADiskUnmount` with `kDADiskUnmountOptionWhole` on a
//  physical disk unmounts that disk's **direct partitions only**. It does not reach volumes
//  inside an APFS container on the disk, and it reports **success with no dissenter** having
//  skipped them. From `diskarbitrationd`'s own log, on a GPT drive with exFAT + APFS + HFS+:
//
//      unmounted disk, id = /dev/disk8s2, success.     <- exFAT,  a direct partition
//      unmounted disk, id = /dev/disk8s4, success.     <- HFS+,   a direct partition
//      (no line for /dev/disk9s1 — the APFS volume was never attempted)
//
//  …while this file logged "Unmounted every volume on disk8: Vol_ExFAT, Vol_APFS, Vol_HFS."
//
//  That is also the true mechanism behind the 2026-08-06 observation recorded as *"DADiskUnmount
//  reports success while a volume is still mounted"*. It did — but not as a general property of
//  the success signal. `1TB_Samsung` is an APFS volume on synthesized `disk7`; it was never
//  unmounted and never would have been. The narrower statement is the actionable one.
//
//  **So unmount names its volumes.** The set is exactly `DiscoveredDevice.mountedVolumeBSDNames`,
//  from the enumerator's IOKit subtree walk — which is what connects `disk6` to `/dev/disk7s1`
//  when a BSD-name prefix match cannot (see MountedVolumes.swift). A volume that is mounted is by
//  definition in the mount table, so it can always be enumerated and always has a node.
//
//  **Mount All still cannot be**, and that asymmetry is not an inconsistency: the mount table
//  cannot list the volumes that are *not* mounted, so "mount every mountable volume" has nothing
//  to enumerate and must ask DiskArbitration to work it out. Hence `mountAll` keeps
//  `kDADiskMountOptionWhole`, and the **restore** path — which puts back a known set — does not
//  (see ``mount(volumeBSDNames:completion:)``, where using `…Whole` put an EFI partition on the
//  desktop).
//
//  Nothing here may go back to a whole-disk unmount. The suite cannot catch that on its own —
//  the option lives inside a call that needs DiskArbitration and a real drive — so it is pinned
//  by this comment, by the per-volume fan-out being tested where it is decided, and by the
//  hardware evidence above.
//
//  ## What it never does
//
//  Nothing here is ever called as part of starting a test (FR-SAFE-6). It runs only when
//  the user presses the control. That separation is the whole point of the FR-SAFE-5/6
//  amendment: a mounted volume produces a refusal that names it, never a silent unmount.
//

import Foundation
import DiskArbitration
import os

private nonisolated let log = Logger(subsystem: HelperIdentity.loggingSubsystem,
                                     category: "safety")

/// The result of a mount or unmount, in words the user can act on (NFR-USE-5).
nonisolated enum VolumeMountOutcome: Equatable {

    /// The operation was accepted. The message points at the device list rather than
    /// asserting what is now mounted — the list is the authoritative display and updates
    /// itself through the `VolumeChangeWatcher`.
    case succeeded(String)

    /// It was refused or failed. The message names the volume and the reason.
    case failed(String)

    var isSuccess: Bool { if case .succeeded = self { return true } else { return false } }

    var message: String {
        switch self {
        case .succeeded(let text), .failed(let text): return text
        }
    }

    /// The reason text for the case DiskArbitration does not report: **it said the unmount
    /// succeeded and the volumes are still mounted** (measured 2026-08-06).
    ///
    /// There is no dissenter to quote here — nothing refused — so the message cannot name a cause
    /// and must not invent one. It says what was asked, what was observed, and the likeliest
    /// explanation, in that order.
    static func unmountReportedSuccessButVolumesRemain(_ volumeNames: [String]) -> String {
        let named = volumeNames.isEmpty
            ? "one or more volumes"
            : volumeNames.joined(separator: ", ")
        return "The unmount did not take: macOS reported success, but \(named) "
             + (volumeNames.count == 1 ? "is" : "are")
             + " still mounted. No reason was given — macOS raised no objection to the request. "
             + "The usual cause is a file still open on the volume, which some filesystems refuse "
             + "silently. Close any open files or applications using the drive, then try again."
    }

    /// What to tell the user after a failed unmount has been rolled back
    /// (user decision 2026-08-06).
    ///
    /// ## Why an unmount that fails is undone rather than left where it stopped
    ///
    /// `DADiskUnmount` with `kDADiskUnmountOptionWhole` dissents as a unit, but **volumes it
    /// already unmounted stay unmounted**. So a refusal by one busy volume leaves a multi-volume
    /// drive half-dismounted — and the user is left holding a state they did not ask for. Reported
    /// from real use with the *wrong drive selected*:
    ///
    /// > *"I very much wanted an easy way to restore the mounted volumes."*
    ///
    /// The first attempt at this flipped the button's label to "Mount All" so the way back was one
    /// press away. The user's answer was better and is what this implements: **put it back
    /// automatically.** The operation then either fully succeeds or leaves the drive as it found
    /// it, which is what a user pressing one button reasonably expects — and it needs no new
    /// control state, so the existing label rule stays correct with nothing added to it.
    ///
    /// That matters beyond this control, which Step 11 deletes: Step 11's Start owns
    /// unmount → acquire → run, and its abort path reaches exactly this situation with no manual
    /// control left at all. Rollback is the behaviour that survives the button.
    ///
    /// - Parameters:
    ///   - failure: the unmount's own message, which already names the volume and the
    ///     DiskArbitration reason (`DAStatus.explain`).
    ///   - restore: what the remount attempt reported.
    static func unmountRolledBack(failure: String, restore: VolumeMountOutcome) -> String {
        switch restore {
        case .succeeded:
            // Deliberately "asked macOS to remount" and not "restored": the mount is asynchronous
            // and the device list below is what actually shows the result. Claiming a restored
            // state we have not observed would be the same error as a report saying "0 bad
            // blocks" without saying whether it could tell.
            return failure + "\n\nAny volumes that had already unmounted have been asked to "
                 + "remount, so the drive should be back as it was. The list above shows what is "
                 + "mounted now."
        case .failed(let restoreMessage):
            // The worse outcome, and it must not be buried under the first error: the drive has
            // been left changed and this app could not change it back.
            return failure + "\n\n⚠️ Some volumes had already unmounted and could NOT be "
                 + "remounted: " + restoreMessage
                 + "\n\nThe drive has been left partly unmounted. Use Disk Utility or the Finder "
                 + "to remount it."
        }
    }
}

/// Mounts and unmounts all volumes of a device.
///
/// One instance per use is fine; it holds no state between calls. Completions are
/// delivered on the main queue so the UI can bind to them directly.
nonisolated final class VolumeMounter {

    /// Guards the case where DiskArbitration neither completes nor dissents. A control
    /// stuck on "Working…" forever is worse than an honest "no answer": the user cannot
    /// tell whether the drive is busy or the app is.
    private static let timeout: TimeInterval = 20

    init() {}

    /// Unmount every volume, and **put the drive back if that fails** (user decision 2026-08-06).
    ///
    /// ## Why the sequencing is here, with its operations injected
    ///
    /// It was written inline in `DeviceListView` first, and a mutation showed the cost: deleting
    /// the rollback entirely — the whole point of the change — was **caught by nothing**, because
    /// no test can reach a closure inside a SwiftUI view's action. That is the same hole Step 10's
    /// increment 2 found in `RunCoordinator`'s observer composition, and it takes the same fix:
    /// move the decision to where a test can see it.
    ///
    /// Both operations are parameters rather than calls on `self`, for the reason `QuitSequence`
    /// takes its release the same way — it makes "does a failure trigger the remount, and does a
    /// success leave it alone?" answerable without DiskArbitration, a drive, or a window.
    ///
    /// ## And why the dissenter is not believed (measured 2026-08-06)
    ///
    /// **`DADiskUnmount` can call back with no dissenter — success — while a volume is still
    /// mounted.** Observed in the shipped app and confirmed from the unified log, which recorded:
    ///
    /// ```
    /// unmount succeeded on disk6: Unmounted every volume on disk6: 1TB_Samsung.
    /// ```
    ///
    /// …for a volume that was, at that moment and for hours afterwards, mounted and in active use.
    /// The device pane beside the control showed it still mounted, correctly, at the same time.
    ///
    /// So a `nil` dissenter means *nothing refused the request*, not *the volumes are unmounted*.
    /// Every earlier attempt at this feature was built on that signal and could not work: the
    /// label never flipped and the rollback never fired, because the app believed it had
    /// succeeded.
    ///
    /// The postcondition is therefore **checked, not inferred** — the mount table is read back and
    /// is what decides. That is the same rule the run report follows about its own claims, and the
    /// same lesson as `fcntl(F_NOCACHE)` returning 0 on `/dev/null`: an API accepting a request is
    /// not the request having had its intended effect.
    ///
    /// - Parameters:
    ///   - unmount: performs the unmount.
    ///   - volumesStillMounted: **reads the mount table back** and returns this device's volumes
    ///     that are still mounted. Called after `unmount` settles, whatever it reported.
    ///   - remount: performs the restoring mount. Called only when the unmount did not take.
    ///   - completion: the composed result. Always a failure when volumes remain, whether or not
    ///     the drive could be put back — the user asked for an unmount and did not get one.
    /// ## And why the check is retried rather than taken once (measured 2026-08-06)
    ///
    /// The first version read the mount table immediately after the callback and treated any
    /// remaining volume as failure. **The table lags the callback**: a genuinely successful
    /// unmount still listed its volume at that instant, so every unmount was judged failed and
    /// rolled back — which is what put the EFI partition on the desktop. Observed on `disk8`,
    /// whose unmount succeeded and was undone 3 s later.
    ///
    /// So the table is re-read until it settles or `attempts` is exhausted. A drive that really
    /// did unmount clears on an early pass and costs nothing; a drive that did not spends the
    /// whole budget, which is the right way round.
    ///
    /// - Parameters:
    ///   - unmount: performs the unmount.
    ///   - volumesStillMounted: reads the mount table back — the device's volumes still mounted.
    ///   - retry: schedules the next re-read. Injected so a test needs no real clock.
    ///   - attempts: how many times to look before concluding the unmount did not take.
    ///   - restore: remounts **exactly** the volumes given — the ones that were mounted before
    ///     and are not now. Never a whole-disk mount; see ``mount(volumeBSDNames:completion:)``.
    ///   - mountedBefore: `(volumeName, bsdName)` pairs captured before the unmount.
    static func restoringUnmount(
        unmount: (@escaping (VolumeMountOutcome) -> Void) -> Void,
        mountedBefore: [(name: String, bsdName: String)],
        volumesStillMounted: @escaping () -> [String],
        retry: @escaping (@escaping () -> Void) -> Void,
        attempts: Int = 12,
        restore: @escaping ([String], @escaping (VolumeMountOutcome) -> Void) -> Void,
        completion: @escaping (VolumeMountOutcome) -> Void
    ) {
        unmount { outcome in
            func look(_ remainingAttempts: Int) {
                let stillMounted = volumesStillMounted()

                if stillMounted.isEmpty {
                    // It took. Whatever the dissenter said, the postcondition is what decides —
                    // and a genuine success passes through untouched, with nothing remounted.
                    completion(outcome.isSuccess
                               ? outcome
                               : .succeeded("The volumes are unmounted."))
                    return
                }

                guard remainingAttempts <= 1 else {
                    retry { look(remainingAttempts - 1) }
                    return
                }

                // It did not take. Put back exactly what went — the volumes that were mounted
                // before and are not now. EFI was never in that set, so it can never be in this
                // one, which is what the whole-disk mount got wrong.
                let lost = mountedBefore
                    .filter { !stillMounted.contains($0.name) }
                    .map(\.bsdName)

                let reason = outcome.isSuccess
                    ? VolumeMountOutcome.unmountReportedSuccessButVolumesRemain(stillMounted)
                    : outcome.message

                restore(lost) { restored in
                    completion(.failed(VolumeMountOutcome.unmountRolledBack(failure: reason,
                                                                            restore: restored)))
                }
            }
            look(attempts)
        }
    }

    /// Unmount every mounted volume of `device`, **one volume at a time, by device node**
    /// (FR-SAFE-5). See the file header for why this is not a whole-disk unmount.
    func unmountAll(_ device: DiscoveredDevice,
                    completion: @escaping (VolumeMountOutcome) -> Void) {

        // Index-aligned by construction: both arrays come from one mount-table snapshot and one
        // IOKit subtree walk in `IOKitDeviceEnumerator`, with the same de-duplication key.
        let volumes = Array(zip(device.mountedVolumeNames, device.mountedVolumeBSDNames))
            .map { (name: $0.0, bsdName: $0.1) }

        Self.unmountEach(volumes,
                         on: device.bsdName.rawValue,
                         using: { node, done in self.unmountOne(node, completion: done) },
                         completion: completion)
    }

    /// Unmount each of `volumes` and report **once**, for all of them.
    ///
    /// ## Why this is a static function with its operation injected
    ///
    /// Same reason as ``restoringUnmount(unmount:mountedBefore:volumesStillMounted:retry:attempts:restore:completion:)``,
    /// and the same reason `RunObservers.forRun` exists: written inline in `unmountAll` the
    /// fan-out would need DiskArbitration and a real drive to exercise, so "does every mounted
    /// volume get an attempt, and does one refusal fail the whole operation?" would be answerable
    /// only by running the app. That is precisely how the whole-disk unmount survived from Step 6
    /// to 2026-08-09 with a green suite over it.
    ///
    /// What remains outside the tested boundary is a single call in `unmountAll` and the option
    /// constant inside ``unmountOne(_:completion:)``. Both are pinned by comment and by the
    /// hardware evidence in the file header; neither is claimed to be covered.
    ///
    /// - Parameters:
    ///   - volumes: the device's mounted volumes, name and node. Nodes come from
    ///     `DiscoveredDevice.mountedVolumeBSDNames` — a name cannot be unmounted and a node can.
    ///   - wholeDiskName: the physical disk, for the message only. Never used to unmount.
    ///   - unmountOne: unmounts one volume by node.
    ///   - completion: `.succeeded` only if **every** volume went. A partial result is a failure
    ///     naming the volumes that refused and why — which is the state the rollback then undoes.
    static func unmountEach(
        _ volumes: [(name: String, bsdName: String)],
        on wholeDiskName: String,
        using unmountOne: @escaping (String, @escaping (VolumeMountOutcome) -> Void) -> Void,
        completion: @escaping (VolumeMountOutcome) -> Void
    ) {
        guard !volumes.isEmpty else {
            // Nothing was mounted, so the postcondition already holds. Worded so it cannot be
            // read as "an unmount was performed" — the same distinction `mount(volumeBSDNames:)`
            // draws between "nothing needed doing" and "the operation worked".
            completion(.succeeded("No volumes were mounted on \(wholeDiskName)."))
            return
        }

        var remaining = volumes.count
        var refusals: [String] = []

        for volume in volumes {
            unmountOne(volume.bsdName) { outcome in
                if case .failed(let reason) = outcome {
                    refusals.append("\(volume.name): \(reason)")
                }
                remaining -= 1
                guard remaining == 0 else { return }

                if refusals.isEmpty {
                    completion(.succeeded("Unmounted every volume on \(wholeDiskName): "
                                        + volumes.map(\.name).joined(separator: ", ") + "."))
                } else {
                    // Names ONLY the volumes that refused, and each one's own reason (NFR-USE-5).
                    // The whole-disk version named every volume on the drive whatever had actually
                    // happened, which told a user with one busy volume that all of them had
                    // failed — and left them guessing which to close.
                    completion(.failed("Could not unmount "
                                     + refusals.joined(separator: "; ")
                                     + " Close any open files or applications using the drive, "
                                     + "then try again."))
                }
            }
        }
    }

    /// One volume, by node. `kDADiskUnmountOptionDefault` rather than `…Whole`: this is the
    /// volume's own disk object, and `Whole` on it would reach back up to the physical drive —
    /// which is the defect this method exists to avoid, and the exact mirror of the note on
    /// ``mountOne(_:completion:)``.
    ///
    /// - Note: **not covered by a test**, for the same reason `mountOne` is not — the call needs
    ///   DiskArbitration and a real drive. What *is* tested is ``unmountEach(_:on:using:completion:)``,
    ///   which decides *which* volumes are attempted, and that is where the whole-disk defect
    ///   actually lived.
    private func unmountOne(_ bsdName: String,
                            completion: @escaping (VolumeMountOutcome) -> Void) {
        perform(on: bsdName, verb: "unmount", completion: completion) { disk, callback, context in
            DADiskUnmount(disk, DADiskUnmountOptions(kDADiskUnmountOptionDefault),
                          callback, context)
        } describeSuccess: {
            "unmounted"
        } describeFailure: { reason in
            reason
        }
    }

    /// Mount **exactly** the named volumes, by device node, and report once for all of them.
    ///
    /// ## Why this exists rather than reusing the whole-disk mount
    ///
    /// `mountAll` asks macOS to mount every *mountable* volume, which is right for a control
    /// labelled "Mount All" and wrong for a **restore**: on a GPT drive it brings up the EFI
    /// partition, which was not mounted before the unmount and has no business being mounted
    /// after it. Observed 2026-08-06 — the rollback put EFI on the desktop.
    ///
    /// A restore must put back what went and nothing else, so it names its volumes.
    ///
    /// - Parameter volumeBSDNames: device nodes, e.g. `disk8s2`. From
    ///   `DiscoveredDevice.mountedVolumeBSDNames`, captured **before** the unmount.
    func mount(volumeBSDNames: [String],
               completion: @escaping (VolumeMountOutcome) -> Void) {

        guard !volumeBSDNames.isEmpty else {
            // Nothing went, so nothing is owed. Distinct from "the restore worked": there was no
            // restore to do, and saying otherwise would claim an action never taken.
            completion(.succeeded("No volumes needed remounting."))
            return
        }

        var remaining = volumeBSDNames.count
        var failures: [String] = []

        for node in volumeBSDNames {
            mountOne(node) { outcome in
                if case .failed(let message) = outcome { failures.append("\(node): \(message)") }
                remaining -= 1
                guard remaining == 0 else { return }

                if failures.isEmpty {
                    completion(.succeeded("Asked macOS to remount "
                                        + volumeBSDNames.joined(separator: ", ") + "."))
                } else {
                    completion(.failed(failures.joined(separator: "; ")))
                }
            }
        }
    }

    /// One volume, by node. `kDADiskMountOptionDefault` rather than `…Whole`: this is the
    /// volume's own disk object, not the physical drive's, and `Whole` on it would reach back up
    /// to the drive and mount everything — which is the EFI defect this method exists to avoid.
    ///
    /// - Note: **not covered by a test.** A mutation swapping the option for `…Whole` is caught by
    ///   nothing, because this call needs DiskArbitration and a real drive. What *is* tested is
    ///   the decision above it — which volumes are restored — and that is where the EFI behaviour
    ///   is actually determined. This line rests on the API contract and on observation, in the
    ///   same way `TableSelectionPolicy` rests on `List` being `NSTableView`-backed.
    ///
    ///   **Observed on hardware 2026-08-09**, which is better standing than it had: a rollback on
    ///   the four-partition fixture produced, in `diskarbitrationd`'s own log,
    ///   `queued solicitation, kind = disk mount, disk = /dev/disk8s2, options = 0x00000000` —
    ///   `kDADiskMountOptionDefault` on the wire, per node, with **no solicitation for the EFI
    ///   partition**. Still not a test; it is an observation from outside the process, and it is
    ///   recorded because it is the only evidence this line can have.
    private func mountOne(_ bsdName: String,
                          completion: @escaping (VolumeMountOutcome) -> Void) {
        // Through `perform` rather than hand-rolled, as it was until 2026-08-09. The duplicate
        // implementation had no `os_log` in it, so the entire rollback path — the one this
        // control has now cost five attempts on — was invisible to the unified log, and the
        // 2026-08-09 failure could only be reconstructed because `diskarbitrationd` happens to
        // log on our behalf. NFR-OBS-1: the paths that are hardest to reason about are the ones
        // that most need to say what they did.
        perform(on: bsdName, verb: "mount", completion: completion) { disk, callback, context in
            DADiskMount(disk, nil, DADiskMountOptions(kDADiskMountOptionDefault),
                        callback, context)
        } describeSuccess: {
            "mounted"
        } describeFailure: { reason in
            reason
        }
    }

    // MARK: - Plumbing

    /// Shared body of every direction: create a session, run the DiskArbitration call, and settle
    /// exactly once — on the callback, or on the timeout.
    ///
    /// Takes a **BSD name**, not a `DiscoveredDevice`, because three of its four callers now act
    /// on a *volume* node rather than a whole disk. That is also what lets `mountOne` and
    /// `unmountOne` inherit the logging instead of duplicating the plumbing without it.
    private func perform(on bsdName: String,
                         verb: String,
                         completion: @escaping (VolumeMountOutcome) -> Void,
                         _ operation: (DADisk, @escaping DADiskUnmountCallback,
                                       UnsafeMutableRawPointer) -> Void,
                         describeSuccess: @escaping () -> String,
                         describeFailure: @escaping (String) -> String) {

        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, bsdName) else {
            log.error("""
                      \(verb, privacy: .public) failed for \
                      \(bsdName, privacy: .public): no DiskArbitration session
                      """)
            completion(.failed("""
                               Could not talk to the disk-management service, so \
                               \(bsdName) was not changed.
                               """))
            return
        }

        let box = OperationBox(session: session,
                               describeSuccess: describeSuccess,
                               describeFailure: describeFailure) { outcome in
            switch outcome {
            case .succeeded(let message):
                log.notice("""
                           \(verb, privacy: .public) succeeded on \
                           \(bsdName, privacy: .public): \
                           \(message, privacy: .public)
                           """)
            case .failed(let message):
                log.error("""
                          \(verb, privacy: .public) failed on \
                          \(bsdName, privacy: .public): \
                          \(message, privacy: .public)
                          """)
            }
            completion(outcome)
        }

        // The session must outlive this scope for the callback to arrive, and the
        // callback is a C function pointer that cannot capture — so the box is retained
        // here and released by the callback, exactly as `DeviceClaim` does.
        //
        // The timeout below does NOT release it. That is deliberate: releasing from
        // whichever path ran first would mean deciding, from the timeout, whether a
        // callback is still coming — and getting that wrong is a use-after-free, which
        // cost the exclusivity probe a crash mid-measurement. If DiskArbitration never
        // calls back at all, this leaks one small object; a bounded leak on a path that
        // should not occur is the right trade against corrupting memory on one that does.
        DASessionSetDispatchQueue(session, DispatchQueue.main)
        let context = Unmanaged.passRetained(box).toOpaque()

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeout) {
            box.settle(.failed("""
                               \(bsdName) did not respond to the \(verb) request \
                               within \(Int(Self.timeout)) seconds. The drive may be busy; \
                               try again, or use Disk Utility.
                               """))
        }

        operation(disk, operationCallback, context)
    }
}

// MARK: - Callback plumbing

/// Carries a single operation's completion across the C callback boundary.
///
/// Two paths can finish an operation — the DiskArbitration callback and the timeout — and
/// exactly one of them may deliver a result. ``settle(_:)`` enforces that: settling twice
/// would report two outcomes for one button press.
///
/// `@unchecked Sendable` without a lock, unusually: every path into this type is on the
/// main queue. The session's callbacks are scheduled there
/// (`DASessionSetDispatchQueue(session, .main)`) and the timeout is a
/// `DispatchQueue.main.asyncAfter`. A lock would suggest a concurrency that does not
/// exist here — and would not help, since the completion it calls updates SwiftUI state
/// that has to be on the main actor anyway.
private nonisolated final class OperationBox: @unchecked Sendable {

    private let session: DASession
    private let describeSuccess: () -> String
    private let describeFailure: (String) -> String
    private let completion: (VolumeMountOutcome) -> Void
    private var settled = false

    init(session: DASession,
         describeSuccess: @escaping () -> String,
         describeFailure: @escaping (String) -> String,
         completion: @escaping (VolumeMountOutcome) -> Void) {
        self.session = session
        self.describeSuccess = describeSuccess
        self.describeFailure = describeFailure
        self.completion = completion
    }

    /// Deliver `outcome`, unless the operation has already been settled by the other
    /// path. Called only on the main queue.
    func settle(_ outcome: VolumeMountOutcome) {
        guard !settled else { return }
        settled = true
        DASessionSetDispatchQueue(session, nil)
        completion(outcome)
    }

    /// A `nil` dissenter is DiskArbitration's way of saying the operation succeeded.
    func settle(dissenter: DADissenter?) {
        guard let dissenter else {
            settle(.succeeded(describeSuccess()))
            return
        }
        settle(.failed(describeFailure(DAStatus.explain(dissenter))))
    }
}

/// Shared by mount and unmount — the two callback types have identical signatures.
private nonisolated let operationCallback: DADiskUnmountCallback = { _, dissenter, context in
    guard let context else { return }
    let box = Unmanaged<OperationBox>.fromOpaque(context).takeRetainedValue()
    box.settle(dissenter: dissenter)
}

// MARK: - Making a dissenter readable

/// Turns a DiskArbitration refusal into something worth showing a user (NFR-USE-5).
private nonisolated enum DAStatus {

    /// Prefer the dissenter's own status string — it is the most specific thing
    /// available, and for a busy volume it often names the responsible process. Fall back
    /// to the status code, which is still far better than "an error occurred".
    static func explain(_ dissenter: DADissenter) -> String {
        if let reason = DADissenterGetStatusString(dissenter) as String?, !reason.isEmpty {
            return reason.hasSuffix(".") ? reason : reason + "."
        }
        return describe(DADissenterGetStatus(dissenter))
    }

    private static func describe(_ status: DAReturn) -> String {
        switch status {
        case DAReturn(kDAReturnBusy):
            return "the disk is in use."
        case DAReturn(kDAReturnExclusiveAccess):
            return "another process holds exclusive access to the disk."
        case DAReturn(kDAReturnNotMounted):
            return "it is not mounted."
        case DAReturn(kDAReturnNotPermitted), DAReturn(kDAReturnNotPrivileged):
            return "macOS did not permit the operation."
        case DAReturn(kDAReturnNotReady):
            return "the disk is not ready."
        case DAReturn(kDAReturnNotFound):
            return "the disk could not be found."
        case DAReturn(kDAReturnUnsupported):
            return "the operation is not supported on this disk."
        case DAReturn(kDAReturnNoResources):
            return "the system is out of resources for the operation."
        case DAReturn(kDAReturnBadArgument):
            return "the request was rejected as invalid."
        default:
            let hex = String(UInt32(bitPattern: Int32(status)), radix: 16)
            return "DiskArbitration refused it (status 0x\(hex))."
        }
    }
}
