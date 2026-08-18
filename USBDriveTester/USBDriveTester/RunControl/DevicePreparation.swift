//
//  DevicePreparation.swift
//  USBDriveTester (app target — unprivileged)
//
//  Step 11, increment 5. Everything that happens between pressing Start and the first byte being
//  read: **unmount → verify → acquire → geometry → clear the run-control level.** This is the whole
//  of `RunControlState.starting`, and the whole of the abort that has to undo it.
//
//  ## Why the sequencing is here rather than in the coordinator, and why every step is injected
//
//  Because the thing that must not be silently deletable is the **rollback**, and this project has
//  already measured what happens when a rollback lives inside a SwiftUI action:
//
//  > *"a mutation deleting the rollback outright was caught by nothing"* — `VolumeMounter`, of the
//  > identical decision on the control this increment deletes.
//
//  So this is the same shape `VolumeMounter.restoringUnmount` and `QuitSequence` already use: a
//  `nonisolated` type with static functions whose every operation is a parameter. "Does an *acquire
//  refusal* roll the unmounts back?" is then answerable with no DiskArbitration, no helper, no
//  drive and no window — which is the only way it will still be answerable in six months.
//
//  ## The abort can be triggered after a SUCCESSFUL unmount, which is what `restoringUnmount`
//  cannot express
//
//  `VolumeMounter.restoringUnmount` couples unmount → verify → restore into one call, because the
//  control it was written for had exactly one thing that could fail. Start has four, and three of
//  them happen *after* the volumes are already down:
//
//    * the selected drive stopped being the selected drive (nothing unmounted yet);
//    * a volume refused to unmount, or the unmount did not take (FR-SAFE-4(a));
//    * the claim was refused — mounted elsewhere, or held by another process (FR-SAFE-4(b));
//    * the geometry could not be read, or the run-control level could not be cleared.
//
//  Every one of the last three leaves a drive whose volumes this app took down and whose user has
//  **no manual control left to put them back** — the three that existed were deleted in this same
//  increment, deliberately and at the same time. That is the hazard BUILD-PLAN Step 11 states in
//  the user's own words:
//
//  > *"I very much wanted an easy way to restore the mounted volumes."*
//
//  ## Four measured facts this file is built around, none of which is intuitive
//
//  1. **`DADiskUnmount` reports success with no dissenter while a volume is still mounted**
//     (2026-08-06). So the unmount's reply decides nothing here; the **mount table** does.
//  2. **The mount table lags the callback.** Reading it the instant the unmount returns still lists
//     a volume that has gone, so a *successful* unmount reads as failed. Re-read until it settles —
//     twelve looks at 150 ms. Without this, Start would abort every run it was about to perform.
//  3. **Restore exactly what went, by device node.** A whole-disk mount brings up every *mountable*
//     volume, which on a GPT drive means an EFI partition that was never mounted — observed, on the
//     desktop. `mountedBefore` is captured before anything is unmounted and the restore set is
//     `before − still mounted`. An APFS volume's node is **not** derivable from the physical disk by
//     prefix; it lives on a synthesized disk.
//  4. **macOS remounts the volumes itself within ~4 ms of a claim being released** (Step 6). That is
//     why the success path has no restore in it at all — and why the rollback, on the one branch
//     that *did* take a claim, settles the table before deciding what is missing. See ``rollBack``.
//
//  ## The run-control level, and the hang it causes if this file forgets it
//
//  `RunControlChannel` is a **process-wide slot that never clears itself**, by design, and its own
//  header states the obligation it left for this increment: *"The app owns the state and sets
//  `proceed` before every run and on every resume."*
//
//  Nothing did, until this file. A Start following any paused-or-stopped run would otherwise read a
//  stale `pause` at its **first** chunk boundary, and the result is not a wrong message — it is a
//  hang: the call returns `pausedByUser`, `RunSequencer` emits `pauseSettled`, and the state machine
//  is in `running` where that event is *ignored*. Sequencer paused, machine running, nothing in
//  flight, nothing coming.
//
//  So clearing the level is a **step of the preparation**, with the same standing as the acquire —
//  and it is **awaited**. `setRunControl` travels on the second, non-owning connection while the
//  cycle travels on the owning one, so there is no ordering guarantee between them: fired and
//  forgotten, the helper can still process the cycle first and read the stale value. The wait costs
//  0.46–0.62 ms, measured on hardware in increment 2's pre-flight.
//
//  `nonisolated` throughout: the app target compiles with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor,
//  which would otherwise make these types main-actor-isolated and unusable from the non-isolated
//  test target.
//

import Foundation

// MARK: - What preparing a drive produced

/// The geometry a run needs, from the claim's **authoritative ioctl answer** rather than from
/// IOKit's.
///
/// The device list shows IOKit's numbers and says so; the helper re-derives them from the descriptor
/// it holds and is the authority (`DeviceListView`'s own caption states this to the user). A run
/// sliced against IOKit's answer on a bridge that lies would address the device wrongly, which is
/// the failure NFR-COMPAT-5 exists for.
nonisolated struct PreparedDeviceGeometry: Equatable {
    let logicalBlockSize: UInt32
    let deviceBlockCount: UInt64

    /// The negotiated USB link speed, carried through because the same `deviceProfile` call answers
    /// it and the metrics panel shows it beside measured throughput. Read at the point it is
    /// already known rather than asked for again later.
    let usbLinkSpeedCode: Int
}

/// Why a Start was abandoned, and what was done about the volumes it had already taken down.
nonisolated struct DevicePreparationFailure: Equatable {

    /// What actually went wrong, in the words the user can act on (NFR-USE-5). Already names the
    /// volume and the DiskArbitration reason where there is one.
    let reason: String

    /// What the rollback reported, or `nil` when **nothing had been unmounted yet** — which is a
    /// different fact from "the rollback succeeded" and must not read as one.
    let restore: VolumeMountOutcome?

    /// Which step failed, for the dialog's heading. `nil` for the one abort that is not a mount
    /// operation at all — the selected drive changing before anything was touched.
    ///
    /// The heading itself is **not** written here: it comes from `OutcomePresentation`, which is
    /// where "what does a failed unmount call itself" is decided for the whole app. Two copies of
    /// that sentence is the drift the type exists to prevent.
    var operation: OutcomeOperation? = nil

    /// What to head the dialog with. An alert's title is the one line a user reliably reads, so it
    /// says *what did not happen*; the body carries the cause and the corrective step.
    var alertTitle: String {
        operation.flatMap { OutcomePresentation.forOutcome(ok: false, operation: $0).title }
            ?? "The run could not start"
    }

    /// What to put in front of the user.
    ///
    /// Composed by ``VolumeMountOutcome/unmountRolledBack(failure:restore:)`` rather than restated
    /// here: that function already owns the wording for both outcomes, including the one that
    /// matters most — *the drive has been left partly unmounted and this app could not change it
    /// back* — and two copies of one message is the drift `PreRunWarningText.standingBackupAdvice`
    /// exists to prevent.
    var message: String {
        guard let restore else { return reason }
        return VolumeMountOutcome.unmountRolledBack(failure: reason, restore: restore)
    }
}

/// How preparing a drive for a run ended.
nonisolated enum DevicePreparationOutcome: Equatable {

    /// The volumes are down, the claim is held, the geometry is known and the run-control level is
    /// `proceed`. The run may write.
    case ready(PreparedDeviceGeometry)

    /// It was abandoned. **The volumes have already been put back** by the time this is delivered,
    /// which is what `RunControlEvent.startAborted` promises its consumers.
    case aborted(DevicePreparationFailure)
}

// MARK: - The steps, injected

/// Every operation ``DevicePreparation`` performs, as a parameter.
///
/// A struct rather than eleven arguments, for legibility only — the reason each one is injected at
/// all is the file header's. A test builds this with stubs and asserts which of them ran, in which
/// order, and which did not.
nonisolated struct DevicePreparationOperations {

    /// Whether the drive named at the moment Start was pressed is **still** the selected drive.
    ///
    /// Checked immediately before the unmount, and it is not ceremony. The acquire is issued by
    /// **BSD name**, which is a locator assigned at enumeration — the pre-run dialog can sit
    /// unanswered for a long time, and a replug in that window renumbers the machine's drives. This
    /// is the one place a locator is used to act rather than to display, so it is the one place the
    /// identity behind it has to be re-confirmed.
    var selectionStillNamesTheDrive: () -> Bool

    /// Unmount every mounted volume, **one at a time by device node** (`VolumeMounter.unmountAll`).
    /// Never a whole-disk unmount: that reaches a disk's direct partitions only and reports success
    /// having skipped the volumes inside an APFS container.
    var unmount: (@escaping (VolumeMountOutcome) -> Void) -> Void

    /// Reads the **mount table** back and returns this device's volumes that are still mounted.
    /// The postcondition, not the reply — see fact 1 in the header.
    var volumesStillMounted: () -> [String]

    /// Schedules the next re-read. Injected so a test needs no real clock.
    var retry: (@escaping () -> Void) -> Void

    /// Take exclusive whole-disk access (FR-SAFE-3).
    var acquire: (@escaping (Result<DeviceAcquisition, Error>) -> Void) -> Void

    /// Read the claim's authoritative geometry and the negotiated link speed.
    var profile: (@escaping (Result<DeviceProfile, Error>) -> Void) -> Void

    /// `setRunControl(.proceed)`, on the second connection. **Awaited** — see the header.
    var clearRunControl: (@escaping (Result<Void, Error>) -> Void) -> Void

    /// Release the claim. Called only on an abort that had already taken one.
    var release: (@escaping () -> Void) -> Void

    /// Remount **exactly** these device nodes (`VolumeMounter.mount(volumeBSDNames:)`). Never a
    /// whole-disk mount — see fact 3.
    var restore: ([String], @escaping (VolumeMountOutcome) -> Void) -> Void
}

// MARK: - The sequence

/// Prepares a drive for a run, and undoes exactly what it did if it cannot.
nonisolated enum DevicePreparation {

    /// How many times the mount table is re-read before a conclusion is drawn.
    ///
    /// 12 × 150 ms ≈ 1.8 s of grace. Step 10's figure, unchanged: a drive that really did unmount
    /// clears on an early pass and costs nothing, and a drive that did not spends the whole budget —
    /// which is the right way round.
    static let settleAttempts = 12

    /// Unmount, verify, acquire, read the geometry, clear the run-control level.
    ///
    /// - Parameters:
    ///   - mountedBefore: `(volumeName, bsdName)` pairs captured **before** anything is unmounted.
    ///     The restore puts back exactly these and nothing else; EFI is absent from this list
    ///     precisely because it was not mounted.
    ///   - operations: see ``DevicePreparationOperations``.
    ///   - attempts: overridable only so a test does not have to write out the real budget.
    ///   - completion: called exactly once, on whichever path was taken.
    static func prepare(mountedBefore: [(name: String, bsdName: String)],
                        operations: DevicePreparationOperations,
                        attempts: Int = settleAttempts,
                        completion: @escaping (DevicePreparationOutcome) -> Void) {

        /// Abandon, putting the volumes back first. `claimHeld` decides whether there is a claim to
        /// drop **and** whether the table needs settling afterwards — one fact, used twice, rather
        /// than two flags that can disagree.
        func abort(_ reason: String, operation: OutcomeOperation? = nil, claimHeld: Bool) {
            rollBack(mountedBefore: mountedBefore,
                     claimHeld: claimHeld,
                     operations: operations,
                     attempts: attempts) { restore in
                completion(.aborted(DevicePreparationFailure(reason: reason,
                                                            restore: restore,
                                                            operation: operation)))
            }
        }

        // Nothing has been unmounted at this point, so there is nothing to put back — and saying
        // "the volumes were restored" would claim an action never taken.
        guard operations.selectionStillNamesTheDrive() else {
            completion(.aborted(DevicePreparationFailure(
                reason: "The drive this run was authorised for is no longer the selected drive — "
                      + "it was disconnected or replaced while the confirmation was open. Nothing "
                      + "has been unmounted and no drive has been written to. Select the drive "
                      + "again and start a new run.",
                restore: nil)))
            return
        }

        operations.unmount { unmountOutcome in
            settle(operations: operations, attempts: attempts) { stillMounted in

                guard stillMounted.isEmpty else {
                    // Whatever the dissenter said, the postcondition is what decides. A *success*
                    // with volumes remaining has no dissenter to quote, so it gets the message that
                    // says what was asked, what was observed, and the likeliest explanation —
                    // rather than inventing a cause.
                    abort(unmountOutcome.isSuccess
                          ? VolumeMountOutcome.unmountReportedSuccessButVolumesRemain(stillMounted)
                          : unmountOutcome.message,
                          operation: .unmount,
                          claimHeld: false)
                    return
                }

                operations.acquire { acquireResult in
                    switch acquireResult {
                    case .failure(let error):
                        // No permissive reading: if the helper could not be reached, access was not
                        // granted, and a run on a device nobody claimed is exactly what the mount
                        // guard exists to prevent.
                        abort("Exclusive access was NOT granted — the helper could not be reached: "
                              + error.localizedDescription,
                              operation: .acquire,
                              claimHeld: false)

                    case .success(.refused(_, let message)):
                        // FR-SAFE-4 distinguishes "still mounted" from "claimed elsewhere" and the
                        // helper's own words carry that distinction. Reported as a refusal rather
                        // than as a malfunction — but never as a success.
                        abort(message, operation: .acquire, claimHeld: false)

                    case .success(.acquired):
                        readGeometry()
                    }
                }
            }
        }

        /// From here on a claim is held, so every abort drops it before restoring.
        func readGeometry() {
            operations.profile { profileResult in
                guard case .success(let profile) = profileResult else {
                    let reason: String
                    if case .failure(let error) = profileResult {
                        reason = "The drive was claimed, but its geometry could not be read: "
                               + error.localizedDescription
                    } else {
                        reason = "The drive was claimed, but its geometry could not be read."
                    }
                    abort(reason, claimHeld: true)
                    return
                }

                guard profile.isAvailable,
                      profile.logicalBlockSize > 0,
                      profile.blockCount > 0 else {
                    abort("The drive was claimed, but it reported no usable geometry — "
                          + "\(profile.logicalBlockSize)-byte blocks, \(profile.blockCount) of "
                          + "them. A run cannot be placed on a device whose size this tool cannot "
                          + "establish.",
                          claimHeld: true)
                    return
                }

                // The same rule `RunSlicing` applies, read from the same constant, but checked
                // **here** — where an abort still has a rollback attached to it. Reaching
                // `RunSlicing` with an unsupported block size would refuse the run correctly and
                // leave the drive claimed and unmounted on a path that has no restore in it.
                guard RunSlicing.supportedBlockSizes.contains(profile.logicalBlockSize) else {
                    let supported = RunSlicing.supportedBlockSizes
                        .sorted().map(String.init).joined(separator: " or ")
                    abort("The drive reports \(profile.logicalBlockSize)-byte logical blocks; this "
                          + "tool supports \(supported). Some USB bridges report a geometry the "
                          + "drive does not have, and a run placed on a wrong one would address "
                          + "the wrong blocks.",
                          claimHeld: true)
                    return
                }

                clearRunControl(profile)
            }
        }

        /// The last step, and the one whose absence hangs the *next* run rather than this one.
        func clearRunControl(_ profile: DeviceProfile) {
            operations.clearRunControl { result in
                guard case .success = result else {
                    let detail: String
                    if case .failure(let error) = result {
                        detail = ": " + error.localizedDescription
                    } else {
                        detail = "."
                    }
                    // Abandoned rather than continued, and this is a judgement worth stating. The
                    // level is a process-wide slot the helper reads at every chunk boundary; a run
                    // started without knowing it says `proceed` is a run that may settle at its
                    // first chunk and leave the state machine waiting for an event it ignores.
                    // Refusing to start is recoverable. That is not.
                    abort("The run could not be started: the helper did not confirm the run-control "
                          + "signal was cleared\(detail) Pause and Stop are read from that signal, "
                          + "so a run started without it could stop at once for no visible reason.",
                          claimHeld: true)
                    return
                }

                completion(.ready(PreparedDeviceGeometry(
                    logicalBlockSize: profile.logicalBlockSize,
                    deviceBlockCount: profile.blockCount,
                    usbLinkSpeedCode: profile.usbLinkSpeedCode)))
            }
        }
    }

    // MARK: The rollback

    /// Put the drive back the way it was found.
    ///
    /// ## Why it re-reads the table on the claimed branch and not on the other
    ///
    /// **Releasing a claim makes macOS remount the volumes by itself, within ~4 ms** (measured
    /// Step 6). So on the one abort branch that took a claim, the restore set is a moving target:
    /// read too early and this app asks to mount volumes macOS is already mounting, and the answer
    /// comes back as a *failure* for volumes that are in fact perfectly fine — telling the user the
    /// drive was left broken when it was not. So that branch settles first, and stops as soon as
    /// there is nothing left to restore.
    ///
    /// On the branches where no claim was taken, nothing is going to change on its own: the table
    /// has already been settled by ``prepare``'s own budget, and polling it again would only add
    /// 1.8 s of dead waiting to an error path a person is reading a dialog about.
    ///
    /// **The restore is attempted whether or not macOS has already done it**, on both branches, and
    /// that is the point of this function existing rather than trusting the ~4 ms remount: an API
    /// accepting a request is not the request having had its intended effect. If macOS got there
    /// first the set is empty and `restore` reports *"No volumes needed remounting"* — which is
    /// honest, and distinct from *"the restore worked"*.
    ///
    /// - Parameter claimHeld: whether the abort happened after the claim was taken. **One fact used
    ///   twice** — whether to release, and whether the table can still change underneath the read —
    ///   rather than two parameters that could be given contradictory values.
    /// - Parameter completion: what the restore reported. Always called.
    static func rollBack(mountedBefore: [(name: String, bsdName: String)],
                         claimHeld: Bool,
                         operations: DevicePreparationOperations,
                         attempts: Int = settleAttempts,
                         completion: @escaping (VolumeMountOutcome) -> Void) {

        func restoreWhateverIsMissing() {
            // Read once, now. `before − still mounted`, by NODE — a name cannot be mounted and a
            // node can.
            let stillMounted = Set(operations.volumesStillMounted())
            let lost = mountedBefore.filter { !stillMounted.contains($0.name) }.map(\.bsdName)
            operations.restore(lost, completion)
        }

        guard claimHeld else {
            restoreWhateverIsMissing()
            return
        }

        operations.release {
            // Settle on "there is nothing left to put back", which is the question this branch is
            // actually asking — *not* on `stillMounted.isEmpty`, which is `prepare`'s question and
            // is the exact opposite of what is wanted here.
            settleUntilNothingIsMissing(mountedBefore: mountedBefore,
                                        operations: operations,
                                        attempts: attempts) {
                restoreWhateverIsMissing()
            }
        }
    }

    // MARK: Reading the table until it means something

    /// Re-read until **nothing of this device is mounted**, or the budget runs out.
    ///
    /// `prepare`'s question: *did the unmount take?* The table lags the callback, so a genuinely
    /// successful unmount still lists its volume at the instant the callback returns — reading once
    /// judged every unmount a failure and is what put an EFI partition on the desktop.
    private static func settle(operations: DevicePreparationOperations,
                               attempts: Int,
                               completion: @escaping ([String]) -> Void) {
        func look(_ remaining: Int) {
            let stillMounted = operations.volumesStillMounted()
            if stillMounted.isEmpty || remaining <= 1 {
                completion(stillMounted)
                return
            }
            operations.retry { look(remaining - 1) }
        }
        look(attempts)
    }

    /// Re-read until **everything that was mounted before is mounted again**, or the budget runs
    /// out.
    ///
    /// The rollback's question, and the mirror image of ``settle(operations:attempts:completion:)``.
    /// Two functions rather than one with a predicate, because the two exit conditions are opposite
    /// and a single parameterised version would let one call site be given the other's test — which
    /// is a defect that reads as correct at both call sites.
    private static func settleUntilNothingIsMissing(
        mountedBefore: [(name: String, bsdName: String)],
        operations: DevicePreparationOperations,
        attempts: Int,
        completion: @escaping () -> Void
    ) {
        func look(_ remaining: Int) {
            let stillMounted = Set(operations.volumesStillMounted())
            let missing = mountedBefore.filter { !stillMounted.contains($0.name) }
            if missing.isEmpty || remaining <= 1 {
                completion()
                return
            }
            operations.retry { look(remaining - 1) }
        }
        look(attempts)
    }
}
