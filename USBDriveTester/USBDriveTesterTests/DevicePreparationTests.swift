//
//  DevicePreparationTests.swift
//  Everything between pressing Start and the first byte read (Step 11, increment 5).
//  FR-SAFE-1/2/3/4, NFR-REL-3, and the partial-unmount hazard BUILD-PLAN Step 11 inherits.
//
//  Every operation is injected, which is the entire reason `DevicePreparation` exists as a type
//  rather than as a closure inside a SwiftUI action. Written the other way, the property that
//  matters most here — **a failure after the volumes are already down puts them back** — is
//  reachable by no test at all, and this project has measured exactly that: a mutation deleting the
//  rollback from `DeviceListView` was caught by nothing.
//
//  Four obligations are load-bearing, and three of them only exist because the three manual
//  controls were deleted in the same increment. There is no Mount All left to press.
//
//    * **Every abort that unmounted anything restores it**, including the three that happen *after*
//      a successful unmount — an acquire refused, a geometry that could not be read, a run-control
//      level that could not be cleared. `VolumeMounter.restoringUnmount` cannot express those: it
//      couples unmount and restore into one call because the control it was written for had one
//      thing that could fail.
//    * **The mount TABLE decides, not the unmount's reply.** `DADiskUnmount` reports success with
//      no dissenter while a volume is still mounted (measured 2026-08-06), and the table lags the
//      callback so a *successful* unmount reads as failed if it is read once. Both directions are
//      pinned below; getting either wrong makes Start unusable rather than merely wrong.
//    * **The restore puts back exactly what went, by NODE.** A whole-disk mount brings up every
//      mountable volume, which on a GPT drive means an EFI partition that was never mounted —
//      observed, on the desktop.
//    * **The run-control level is cleared before the run is declared ready.** `RunControlChannel` is
//      a process-wide slot that never clears itself; a Start after any paused-or-stopped run
//      otherwise settles at its first chunk boundary into a state the machine ignores, and hangs.
//

import Testing
import Foundation
@testable import USBDriveTester

// MARK: - The bench

/// The three volumes of the 4 TB T5 EVO fixture, which is the hardware this path is gated on.
///
/// `Vol_APFS` is deliberately here with its **synthesized** node: an APFS volume is not mounted
/// from the physical disk and its node cannot be derived from `disk8` by prefix. A restore set
/// built by prefix match would silently omit it.
private enum Fixture {
    static let before: [(name: String, bsdName: String)] = [
        (name: "Vol_ExFAT", bsdName: "disk8s2"),
        (name: "Vol_APFS", bsdName: "disk9s1"),
        (name: "Vol_HFS", bsdName: "disk8s4"),
    ]

    static let allNodes = ["disk8s2", "disk9s1", "disk8s4"]
    static let allNames = ["Vol_ExFAT", "Vol_APFS", "Vol_HFS"]

    static let profile = DeviceProfile(isAvailable: true,
                                       logicalBlockSize: 512,
                                       blockCount: 7_814_037_168,
                                       cacheBypass: .bypassed,
                                       usbLinkSpeedCode: 5,
                                       message: "held")
}

private struct StubError: Error, LocalizedError {
    let text: String
    var errorDescription: String? { text }
}

/// Scripts every step's answer and records what actually ran.
///
/// `retry` runs its work **synchronously**, so a whole settle happens inside `prepare` and the
/// assertions below need no expectation, no clock and no main queue. That is what injecting it was
/// for.
private final class Bench {

    // What each step answers.
    var selectionStillNames = true
    var unmountOutcome: VolumeMountOutcome = .succeeded("Unmounted every volume on disk8.")
    var acquireResult: Result<DeviceAcquisition, Error> = .success(.acquired("held"))
    var profileResult: Result<DeviceProfile, Error> = .success(Fixture.profile)
    var clearResult: Result<Void, Error> = .success(())
    var restoreOutcome: VolumeMountOutcome = .succeeded("Asked macOS to remount.")

    /// Successive answers from the mount table. The last element is repeated for every further
    /// read, so a two-element script means "changes once, then stays".
    var mountTableReads: [[String]] = [[]]

    // What ran.
    private(set) var steps: [String] = []
    private(set) var lookCount = 0
    private(set) var retryCount = 0
    private(set) var releaseCount = 0
    private(set) var restoreCallCount = 0
    private(set) var restoredNodes: [String]?
    private(set) var completions = 0
    private(set) var outcome: DevicePreparationOutcome?

    var operations: DevicePreparationOperations {
        DevicePreparationOperations(
            selectionStillNamesTheDrive: {
                self.steps.append("selection")
                return self.selectionStillNames
            },
            unmount: { done in
                self.steps.append("unmount")
                done(self.unmountOutcome)
            },
            volumesStillMounted: {
                let index = min(self.lookCount, self.mountTableReads.count - 1)
                self.lookCount += 1
                return self.mountTableReads[index]
            },
            retry: { again in
                self.retryCount += 1
                again()
            },
            acquire: { done in
                self.steps.append("acquire")
                done(self.acquireResult)
            },
            profile: { done in
                self.steps.append("profile")
                done(self.profileResult)
            },
            clearRunControl: { done in
                self.steps.append("clearRunControl")
                done(self.clearResult)
            },
            release: { done in
                self.steps.append("release")
                self.releaseCount += 1
                done()
            },
            restore: { nodes, done in
                self.steps.append("restore")
                self.restoreCallCount += 1
                self.restoredNodes = nodes
                done(self.restoreOutcome)
            })
    }

    /// Run the whole preparation and keep what it produced.
    func prepare(attempts: Int = DevicePreparation.settleAttempts) {
        DevicePreparation.prepare(mountedBefore: Fixture.before,
                                  operations: operations,
                                  attempts: attempts) { outcome in
            self.completions += 1
            self.outcome = outcome
        }
    }

    var failure: DevicePreparationFailure? {
        if case .aborted(let failure) = outcome { return failure }
        return nil
    }

    var geometry: PreparedDeviceGeometry? {
        if case .ready(let geometry) = outcome { return geometry }
        return nil
    }
}

// MARK: - The happy path

struct DevicePreparationReadyTests {

    @Test func aPreparedDriveRunsEveryStepInOrderAndRestoresNothing() {
        let bench = Bench()
        bench.prepare()

        #expect(bench.steps == ["selection", "unmount", "acquire", "profile", "clearRunControl"])
        #expect(bench.restoreCallCount == 0, "nothing failed, so nothing is put back")
        #expect(bench.releaseCount == 0)
        #expect(bench.completions == 1)
    }

    /// The geometry a run is sliced against is the **claim's ioctl answer**, not IOKit's. A USB
    /// bridge that reports a size the drive does not have would otherwise place the run on the
    /// wrong blocks (NFR-COMPAT-5).
    @Test func theGeometryReportedIsTheClaimsOwn() {
        let bench = Bench()
        bench.prepare()

        #expect(bench.geometry == PreparedDeviceGeometry(logicalBlockSize: 512,
                                                         deviceBlockCount: 7_814_037_168,
                                                         usbLinkSpeedCode: 5))
    }

    /// **The hang guard.** `RunControlChannel` is a process-wide slot that never clears itself, so
    /// a Start following any paused-or-stopped run reads a stale `pause` at its first chunk
    /// boundary. The call then returns `pausedByUser`, `RunSequencer` emits `pauseSettled`, and the
    /// state machine is in `running` where that event is ignored — sequencer paused, machine
    /// running, nothing in flight and nothing coming.
    ///
    /// Two halves, and the second is the one a mutation would reach: it is cleared, and it is
    /// cleared **before** the drive is declared ready.
    @Test func theRunControlLevelIsClearedBeforeTheRunIsDeclaredReady() {
        let bench = Bench()
        bench.prepare()

        #expect(bench.steps.contains("clearRunControl"))
        #expect(bench.steps.last == "clearRunControl", "cleared last, and ready is what follows it")
        #expect(bench.geometry != nil)
    }

    /// A successful unmount clears on the first pass and costs one look. The budget exists for the
    /// drive that has not settled yet, and must not be spent on the drive that has.
    @Test func aSuccessfulUnmountCostsOneLookAndNoRetries() {
        let bench = Bench()
        bench.prepare()

        #expect(bench.lookCount == 1)
        #expect(bench.retryCount == 0)
    }
}

// MARK: - The mount table decides, in both directions

struct DevicePreparationMountTableTests {

    /// **The table lags the callback** (measured 2026-08-06). Read once, a genuinely successful
    /// unmount still lists its volumes and reads as a failure — which would abort every run Start
    /// was about to perform, and is what put an EFI partition on the desktop when the same mistake
    /// was made in the rollback.
    @Test func theTableIsReReadUntilItSettles() {
        let bench = Bench()
        bench.mountTableReads = [Fixture.allNames, ["Vol_APFS", "Vol_HFS"], ["Vol_HFS"], []]
        bench.prepare()

        #expect(bench.lookCount == 4)
        #expect(bench.retryCount == 3)
        #expect(bench.geometry != nil, "it took; the lag is not a failure")
        #expect(bench.restoreCallCount == 0)
    }

    /// **`DADiskUnmount` reports success with no dissenter while a volume is still mounted**
    /// (measured 2026-08-06, from the unified log). So a `.succeeded` reply with a non-empty table
    /// is still an abort — and the message cannot name a dissenter, because nothing refused.
    @Test func anUnmountThatReportedSuccessButLeftVolumesMountedIsAnAbort() {
        let bench = Bench()
        bench.unmountOutcome = .succeeded("Unmounted every volume on disk8.")
        bench.mountTableReads = [["Vol_HFS"]]
        bench.prepare()

        #expect(bench.geometry == nil, "the reply said success; the postcondition says otherwise")
        #expect(bench.steps.contains("acquire") == false, "nothing is claimed on a mounted drive")
        #expect(bench.failure?.reason.contains("macOS reported success") == true)
        #expect(bench.failure?.reason.contains("Vol_HFS") == true)
    }

    @Test func theSettleGivesUpAfterItsBudgetRatherThanLoopingForever() {
        let bench = Bench()
        bench.mountTableReads = [Fixture.allNames]
        bench.prepare(attempts: 12)

        // 12 looks in the settle, then one more in the rollback to decide what is missing.
        #expect(bench.lookCount == 13)
        #expect(bench.retryCount == 11)
        #expect(bench.failure != nil)
    }
}

// MARK: - Every abort that unmounted anything puts it back

struct DevicePreparationRollbackTests {

    /// The one abort with nothing to undo, and it must not claim otherwise. `restore == nil` is a
    /// different fact from "the restore succeeded" and the message must not read as one.
    @Test func aSelectionThatChangedBeforeTheUnmountRestoresNothingBecauseNothingWentDown() {
        let bench = Bench()
        bench.selectionStillNames = false
        bench.prepare()

        #expect(bench.steps == ["selection"], "nothing is unmounted, nothing is claimed")
        #expect(bench.restoreCallCount == 0)
        #expect(bench.failure?.restore == nil)
        #expect(bench.failure?.message == bench.failure?.reason)
        #expect(bench.completions == 1)
    }

    /// FR-SAFE-4(a). The partial unmount this whole path exists for: one volume refuses, the two
    /// that already went stay down, and there is **no manual control left to put them back**.
    @Test func anUnmountRefusedByOneVolumePutsBackTheOnesThatWent() {
        let bench = Bench()
        bench.unmountOutcome = .failed("Could not unmount Vol_HFS: the disk is in use.")
        bench.mountTableReads = [["Vol_HFS"]]
        bench.prepare()

        #expect(bench.restoreCallCount == 1)
        // By NODE, and only the two that are actually missing. A name cannot be mounted.
        #expect(bench.restoredNodes == ["disk8s2", "disk9s1"])
        #expect(bench.failure?.reason.contains("Vol_HFS") == true)
    }

    /// **The case `VolumeMounter.restoringUnmount` cannot express**, and the reason this type
    /// exists: the unmount fully succeeded, so nothing in that call's own composition would ever
    /// run — and the drive is down with a user who has nothing to press.
    @Test func anAcquireRefusalPutsEveryVolumeBack() {
        let bench = Bench()
        bench.acquireResult = .success(.refused(cause: .claimedByAnotherProcess,
                                                message: "Another process holds this disk."))
        bench.prepare()

        #expect(bench.steps.contains("acquire"))
        #expect(bench.restoreCallCount == 1)
        #expect(bench.restoredNodes == Fixture.allNodes, "all three went, so all three come back")
        #expect(bench.releaseCount == 0, "no claim was taken, so there is none to drop")
        #expect(bench.failure?.reason == "Another process holds this disk.")
    }

    /// A transport failure has no permissive reading: access was not granted.
    @Test func anAcquireThatCouldNotReachTheHelperPutsEveryVolumeBack() {
        let bench = Bench()
        bench.acquireResult = .failure(StubError(text: "connection invalid"))
        bench.prepare()

        #expect(bench.restoredNodes == Fixture.allNodes)
        #expect(bench.failure?.reason.contains("NOT granted") == true)
        #expect(bench.failure?.reason.contains("connection invalid") == true)
    }

    /// From here a **claim is held**, so the rollback has one more thing to undo than the branches
    /// above — and it must drop it before it asks macOS to mount anything.
    @Test func aGeometryFailureReleasesTheClaimAndThenPutsTheVolumesBack() {
        let bench = Bench()
        bench.profileResult = .failure(StubError(text: "no device is held"))
        bench.prepare()

        #expect(bench.releaseCount == 1)
        #expect(bench.restoreCallCount == 1)
        // Unwrapped safely rather than with `!`. A force-unwrap here is a SIGTRAP that takes the
        // whole test process down instead of failing one test — and it destroys the evidence of
        // whatever went wrong, which is exactly when the evidence is wanted.
        guard let released = bench.steps.firstIndex(of: "release"),
              let restored = bench.steps.firstIndex(of: "restore") else {
            Issue.record("expected both a release and a restore, got: \(bench.steps)")
            return
        }
        #expect(released < restored,
                "the claim goes first; macOS will not mount a volume on a claimed disk")
        #expect(bench.failure?.reason.contains("geometry could not be read") == true)
    }

    @Test func geometryTheDriveCouldNotAnswerIsRefusedWhileTheRollbackStillExists() {
        let bench = Bench()
        bench.profileResult = .success(DeviceProfile(isAvailable: true,
                                                     logicalBlockSize: 512,
                                                     blockCount: 0,
                                                     cacheBypass: .bypassed,
                                                     usbLinkSpeedCode: 5,
                                                     message: ""))
        bench.prepare()

        #expect(bench.releaseCount == 1)
        #expect(bench.restoredNodes == Fixture.allNodes)
    }

    /// Checked **here** rather than left to `RunSlicing`. The slicer refuses it correctly, but by
    /// then the run has started and the drive is claimed and unmounted on a path with no rollback
    /// attached to it.
    @Test func anUnsupportedBlockSizeIsRefusedBeforeTheRunRatherThanInsideIt() {
        let bench = Bench()
        bench.profileResult = .success(DeviceProfile(isAvailable: true,
                                                     logicalBlockSize: 520,
                                                     blockCount: 1_000,
                                                     cacheBypass: .bypassed,
                                                     usbLinkSpeedCode: 5,
                                                     message: ""))
        bench.prepare()

        #expect(bench.geometry == nil)
        #expect(bench.releaseCount == 1)
        #expect(bench.restoredNodes == Fixture.allNodes)
        #expect(bench.failure?.reason.contains("520") == true)
    }

    /// The step whose failure would otherwise hang the *next* run rather than this one. Refusing to
    /// start is recoverable; a state machine waiting for an event it ignores is not.
    @Test func aRunControlLevelThatCouldNotBeClearedAbandonsTheRunAndRestores() {
        let bench = Bench()
        bench.clearResult = .failure(StubError(text: "helper unreachable"))
        bench.prepare()

        #expect(bench.geometry == nil)
        #expect(bench.releaseCount == 1)
        #expect(bench.restoredNodes == Fixture.allNodes)
        #expect(bench.failure?.reason.contains("run-control signal") == true)
    }

    /// A volume that was **not** mounted before cannot be in the restore set, whatever the table
    /// says now. This is the EFI property: a whole-disk mount brings up every *mountable* volume,
    /// and the observed consequence was an EFI partition on the desktop.
    @Test func nothingIsRestoredThatWasNotMountedBeforeTheUnmount() {
        let bench = Bench()
        bench.acquireResult = .success(.refused(cause: .volumesMounted, message: "refused"))
        // The table now lists a volume this device never had mounted.
        bench.mountTableReads = [[], ["EFI"]]
        bench.prepare()

        #expect(bench.restoredNodes?.contains("EFI") == false)
        #expect(bench.restoredNodes == Fixture.allNodes)
    }

    /// The worse outcome, and it must not be buried under the first error: the drive has been left
    /// changed and this app could not change it back.
    @Test func aRestoreThatFailsIsSaidPlainlyAndNotHiddenBehindTheOriginalFailure() {
        let bench = Bench()
        bench.acquireResult = .success(.refused(cause: .volumesMounted, message: "refused"))
        bench.restoreOutcome = .failed("disk8s4: the disk is in use.")
        bench.prepare()

        let message = bench.failure?.message ?? ""
        #expect(message.contains("refused"), "the original cause survives")
        #expect(message.contains("could NOT be remounted"))
        #expect(message.contains("left partly unmounted"))
    }
}

// MARK: - The rollback's own reading of the table

struct DevicePreparationRollbackSettleTests {

    /// **Releasing a claim makes macOS remount the volumes itself, within ~4 ms** (measured
    /// Step 6). Read too early and this app asks to mount volumes macOS is already mounting — and
    /// the answer comes back as a failure for volumes that are perfectly fine, telling the user the
    /// drive was left broken when it was not.
    @Test func afterAReleaseTheTableIsSettledBeforeDecidingWhatIsMissing() {
        let bench = Bench()
        bench.profileResult = .failure(StubError(text: "no device is held"))
        // Look 1: the unmount took. Then the release lands and macOS brings them back over three
        // further reads.
        bench.mountTableReads = [[],
                                 ["Vol_ExFAT"],
                                 ["Vol_ExFAT", "Vol_APFS"],
                                 Fixture.allNames]
        bench.prepare()

        #expect(bench.restoreCallCount == 1)
        #expect(bench.restoredNodes == [], "macOS got there first — nothing is owed")
        #expect(bench.failure?.message.contains("could NOT be remounted") == false)

        // **The count is the assertion, and it was added because a mutation survived without it.**
        // This branch must stop as soon as there is *nothing left to restore*; `prepare`'s settle
        // stops when the table goes *empty*. The two conditions are exact opposites, and swapping
        // them produces the same restore set here — so only the number of reads distinguishes
        // them. Three looks (`[Vol_ExFAT]`, `[…, Vol_APFS]`, all three) and two retries; asking
        // the other question would burn the whole budget instead.
        #expect(bench.retryCount == 2)
        #expect(bench.lookCount == 5, "one in prepare's settle, three here, one to decide")
    }

    /// …and it still puts them back when macOS does not. The ~4 ms remount is a measured behaviour,
    /// not a guarantee this app is entitled to assume: an API accepting a request is not the
    /// request having had its intended effect.
    @Test func afterAReleaseTheVolumesAreStillRestoredWhenMacOSDoesNotBringThemBack() {
        let bench = Bench()
        bench.profileResult = .failure(StubError(text: "no device is held"))
        bench.mountTableReads = [[]]
        bench.prepare(attempts: 4)

        #expect(bench.restoredNodes == Fixture.allNodes)
    }

    /// The branches with no claim do **not** poll again. Nothing is going to change on its own
    /// there, and `prepare` has already spent the budget — a second one would add 1.8 s of dead
    /// waiting to an error path a person is reading a dialog about.
    @Test func anAbortWithNoClaimReadsTheTableOnceMoreAndNoMore() {
        let bench = Bench()
        bench.acquireResult = .success(.refused(cause: .volumesMounted, message: "refused"))
        bench.prepare()

        // One look in the settle, one in the rollback.
        #expect(bench.lookCount == 2)
        #expect(bench.retryCount == 0)
    }
}
