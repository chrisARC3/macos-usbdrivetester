//
//  AppModelQuitTests.swift
//  Quitting during a run, end to end through `AppModel` (user decision 2026-08-05).
//
//  `QuitPolicyTests` pins the decisions and `QuitSequenceTests` pins the once-only termination.
//  What is left — and what this file is for — is the part that joins them to the run: **when the
//  app actually quits**, which is the promise "stop at the call boundary" is made of.
//
//  The two properties that matter here cannot be seen from either of the other files:
//
//    * a confirmed quit while a run is in flight terminates **at the moment the run settles**, not
//      before it and not never; and
//    * a confirmed quit when the run has *already* ended terminates straight away — the dialog can
//      easily sit on screen for longer than the run it is asking about, and an app that waited for
//      a transition that had already happened would appear to ignore the button entirely.
//
//  ## These used to be driven through a toggle, and now they are driven through the machine
//
//  Until Step 11 increment 5 the run-active fact came from `simulatedRunActive` — a settable
//  stand-in — or from `cycleIsRunning`, also settable. Both are deleted, and `AppModel.runIsActive`
//  now reads the real `RunControlState`. So these tests drive a **real `RunController`** with stub
//  operations, which is strictly stronger: the state they quit out of is one the machine actually
//  reached, through the same two steps the UI takes.
//
//  It also lets the second property be pinned where it really bites. **A quit while paused has
//  nothing in flight and no reply coming** — there is no call boundary to wait for at all — which
//  is exactly the case the recorded default *"a quit issues a stop"* exists for, and which the old
//  stand-in could only approximate.
//
//  `terminateAction` is injected, so "the app quits" is observable without any of these tests
//  taking the process down with them. Nothing here touches XPC or a drive.
//

import Testing
import Foundation
// `MemberImportVisibility`: `NSApplication` is AppKit's and a transitive import is not enough.
import AppKit
@testable import USBDriveTester

@MainActor
struct AppModelQuitTests {

    private final class Recorder {
        var terminations = 0
    }

    /// A sequencer that reports back only when the test says so.
    ///
    /// `@MainActor` explicitly: a nested type does **not** inherit its enclosing suite's isolation.
    @MainActor
    private final class StubSequencer: RunSequencing {
        let emit: (RunSequencerEvent) -> Void
        private(set) var stops = 0

        /// What `stop()` does, and the distinction is the whole point of this file's second
        /// property. **With a call in flight the helper settles at its next chunk boundary** — the
        /// reply arrives later, so `stop()` returns having ended nothing. **While paused there is
        /// nothing in flight and no reply coming**, so the real sequencer finishes synchronously.
        var stopEndsTheRunSynchronously = false

        init(emit: @escaping (RunSequencerEvent) -> Void) { self.emit = emit }

        func start(logicalBlockSize: UInt32, deviceBlockCount: UInt64,
                   ioSizeBytes: Int, failureMode: FailureModeCode) -> Bool { true }

        func resume() -> Bool { true }

        func stop() -> Bool {
            stops += 1
            if stopEndsTheRunSynchronously { emit(.runEnded(Self.completed)) }
            return true
        }

        static let completed = RunSequenceResult(outcome: .completed,
                                                 finalReply: nil,
                                                 ioSizesUsed: [],
                                                 startBlock: 0,
                                                 blockCount: 1_024)
    }

    /// A model whose run is stubbed end to end, and which reports quitting instead of doing it.
    @MainActor
    private final class Bench {
        let model: AppModel
        private let recorder = Recorder()
        var sequencer: StubSequencer?

        init() {
            model = AppModel(suppressionStore: InMemoryPreRunWarningSuppression(),
                             deviceSource: StubDeviceSource(devices: [DeviceFixtures.testDrive]))
            model.terminateAction = { [recorder] in recorder.terminations += 1 }
            model.discovery.start()

            model.runControl = RunController(
                preconditions: { [model] in
                    RunPreconditions(hasUsableSelection: true,
                                     mayIssueNewWork: model.mayIssueNewWork)
                },
                selectedDevice: { [model] in model.discovery.selectedDevice },
                // No drive is touched: preparation succeeds at once with a plausible geometry,
                // which is all the machine needs to reach `running`.
                prepare: { _, done in
                    done(.ready(PreparedDeviceGeometry(logicalBlockSize: 512,
                                                       deviceBlockCount: 1_024,
                                                       usbLinkSpeedCode: -1)))
                },
                makeSequencer: { [weak self] emit in
                    let stub = StubSequencer(emit: emit)
                    self?.sequencer = stub
                    return stub
                },
                setRunControl: { _, done in done(.success(())) },
                release: { done in done() },
                ioSizeBytes: { 1 << 22 },
                failureMode: { .logAndContinue },
                onReport: { _ in },
                onRunSettled: { [model] in model.runSettled() })
        }

        var terminations: Int { recorder.terminations }

        /// Drive a run to `running`, through the same two steps the UI takes.
        func startARun() {
            _ = model.runControl?.startRequested(warningsSuppressed: false)
            model.runControl?.startAuthorised(
                by: PreRunOutcome(issuesRun: true, persistsSuppression: false))
        }

        /// …and on to `paused`, where nothing is in flight and no reply is coming.
        func pauseTheRun() {
            model.runControl?.pause()
            sequencer?.emit(.pauseSettled(resumeBlock: 0))
            sequencer?.stopEndsTheRunSynchronously = true
        }

        /// The run came back. This is what `cycleIsRunning = false` used to be.
        func endTheRun() {
            sequencer?.emit(.runEnded(StubSequencer.completed))
        }
    }

    // MARK: - Asking

    @Test func quittingWithNoRunIsNotQuestioned() {
        let bench = Bench()
        #expect(bench.model.quitRequested() == .quitImmediately)
        #expect(bench.model.quitState == .idle)
        #expect(bench.terminations == 0, "AppKit terminates; the model does not do it itself")
    }

    @Test func aRunInProgressIsEnoughToBeAsked() {
        let bench = Bench()
        bench.startARun()

        #expect(bench.model.quitRequested() == .askFirst)
        #expect(bench.model.quitState == .confirming)
        #expect(bench.model.quitConfirmationIsPresented)
    }

    /// **Asking must not answer.** The run keeps going while the confirmation is up.
    ///
    /// Found by the human checklist on 2026-08-18, not by this suite: pressing ⌘Q during a run
    /// presented the dialog *and ended the run*, so the report appeared underneath a dialog still
    /// asking whether to quit, and "Continue Testing" was offering to resume something dead.
    ///
    /// The cause was one flag answering two questions. `mayIssueNewWork` is false from the moment
    /// a quit is pending — right for Start — and `RunSequencer` was consulting it before every
    /// call, so presenting the dialog halted the run. The two are now separate, and this asserts
    /// they disagree in exactly the state where they must.
    @Test func askingWhetherToQuitDoesNotItselfEndTheRun() {
        let bench = Bench()
        bench.startARun()

        #expect(bench.model.quitRequested() == .askFirst)
        #expect(bench.model.quitState == .confirming)

        #expect(bench.model.mayContinueRun,
                "the run must keep issuing calls until the user actually chooses")
        #expect(bench.model.mayIssueNewWork == false,
                "but Start must still be refused while the question is open")

        // Continue Testing puts everything back, with the run never having noticed.
        bench.model.continueTesting()
        #expect(bench.model.quitState == .idle)
        #expect(bench.model.mayContinueRun)
        #expect(bench.model.mayIssueNewWork)
    }

    /// And once the user HAS chosen, the run stops issuing calls.
    @Test func choosingToQuitDoesStopTheRunIssuingFurtherCalls() {
        let bench = Bench()
        bench.startARun()
        _ = bench.model.quitRequested()
        bench.model.cancelAndQuit()

        #expect(bench.model.quitState == .windingDown)
        #expect(bench.model.mayContinueRun == false, "the user chose; issue nothing further")
    }

    /// **A paused run counts.** The claim is held, the drive's volumes are unmounted, and an
    /// interrupted run cannot be resumed (FR-FAIL-7) — so a ⌘Q that took it without asking would
    /// cost the whole run.
    @Test func aPausedRunIsEnoughToBeAsked() {
        let bench = Bench()
        bench.startARun()
        bench.pauseTheRun()
        #expect(bench.model.runControl?.state == .paused)

        #expect(bench.model.quitRequested() == .askFirst)
    }

    @Test func closingTheWindowAsksTheSameQuestionAndKeepsTheWindow() {
        let bench = Bench()
        bench.startARun()

        #expect(bench.model.mainWindowCloseRequested() == .askFirst)
        #expect(bench.model.quitState == .confirming)
    }

    @Test func closingTheWindowWithNoRunClosesAndQuits() {
        let bench = Bench()
        #expect(bench.model.mainWindowCloseRequested() == .allowCloseAndQuit)
        #expect(bench.model.quitState == .idle,
                "the quit is requested by the guard, not entered here")
    }

    // MARK: - The app's own Quit menu item (increment 12, chunk 0)

    /// **Chunk 0 is a pre-flight and must change no behaviour**, so this pins the two halves of
    /// "does exactly what AppKit's item did": it terminates, once.
    ///
    /// `scheduleOnNextTurn` is made synchronous deliberately. The backstop that runs there exists
    /// to *report* a refused termination, and a backstop that terminated a second time would be
    /// the double-fire `QuitSequence` was built to rule out — so the count is asserted with that
    /// closure having actually run rather than with it still pending.
    @Test func theMenuQuitRequestsATerminationExactlyOnce() {
        let bench = Bench()
        bench.model.scheduleOnNextTurn = { $0() }

        bench.model.quitRequestedFromMenu()

        #expect(bench.terminations == 1)
    }

    /// **And it ends no sheet**, which is the half that says the pre-flight is not the fix.
    ///
    /// Ending a sheet from the general quit path is what chunks 1–2 are for, and it is gated on a
    /// per-surface decision the user took on 2026-09-04: the report may be discarded, the pre-run
    /// prompt and the failure alert may not. Doing it here — before that decision has a type to
    /// live in — would dismiss prompts nobody answered, which is the exact reason this was scoped
    /// out of increment 9.
    @Test func theMenuQuitEndsNoSheetYet() {
        let bench = Bench()
        var sheetsEnded = 0
        bench.model.dismissAttachedSheets = { sheetsEnded += 1 }

        bench.model.quitRequestedFromMenu()

        #expect(sheetsEnded == 0)
    }

    /// **The menu item takes no vote of its own**, with a run in flight — the state a second copy
    /// of the rule would be most tempting in, and most damaging in.
    ///
    /// The vote belongs to `applicationShouldTerminate` asking ``AppModel/quitRequested()``. Were
    /// it duplicated here, the two would eventually disagree and the run guard would have two
    /// answers — the `helperHoldsDevice` shape this project has already deleted once.
    @Test func theMenuQuitTakesNoVoteOfItsOwn() {
        let bench = Bench()
        bench.startARun()

        bench.model.quitRequestedFromMenu()

        #expect(bench.model.quitState == .idle,
                "the confirmation is entered by the delegate's vote, not by the menu item")
        #expect(bench.model.mayContinueRun, "and the run is untouched by the press")
    }

    /// **…and the guard it declines to duplicate is still met**, because the request goes out as an
    /// ordinary `NSApp.terminate(_:)`.
    ///
    /// The two halves above and here are separate facts and it is their conjunction that carries
    /// the property: the menu item decides nothing, *and* what it asks for is refused during a run.
    /// `terminateAction` is stubbed, so this drives the delegate directly — which is the same thing
    /// AppKit does with the real one, minus the process exiting.
    @Test func theMenuQuitStillMeetsTheRunGuardByTheOrdinaryRoute() {
        let bench = Bench()
        bench.startARun()
        let delegate = AppLifecycleDelegate()
        delegate.model = bench.model

        bench.model.quitRequestedFromMenu()
        let reply = delegate.applicationShouldTerminate(NSApplication.shared)

        #expect(reply == .terminateCancel)
        #expect(bench.model.quitState == .confirming)
        #expect(bench.model.quitConfirmationIsPresented)
    }

    // MARK: - Closing the MAIN window quits (user decision 2026-08-06)

    /// The termination the guard requests after the window has closed. It goes through
    /// `terminateAction`, which in the app is `NSApp.terminate(_:)` — so it lands in
    /// `applicationShouldTerminate` and picks up the same guard ⌘Q does, rather than killing the
    /// app directly.
    @Test func closingTheMainWindowRequestsATermination() {
        let bench = Bench()

        #expect(bench.model.mainWindowCloseRequested() == .allowCloseAndQuit)
        bench.model.quitBecauseTheMainWindowClosed()

        #expect(bench.terminations == 1)
    }

    /// The backstop, kept but no longer the rule. Step 9 left AppKit's default (`false`); the
    /// first fix set this flag alone, and observing *that* showed it fires only when no window is
    /// left — so closing the main window quit the app or not depending on whether a panel opened
    /// earlier was still up. The main-window rule replaced it; this remains for ending up with no
    /// UI by some route nobody enumerated.
    @Test func endingUpWithNoWindowsAtAllAlsoQuits() {
        #expect(AppLifecycleDelegate()
                    .applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }

    /// **The claim the comment makes, as a test rather than as prose.**
    ///
    /// `applicationShouldTerminateAfterLastWindowClosed` is only reached *after* a window has
    /// closed — so it can only ever fire from a state where the close was allowed. During a run
    /// the close is refused before AppKit gets that far, which is what stops "closing the last
    /// window quits" from becoming a way to end a run without being asked.
    ///
    /// The two halves are checked together here because separately they are two facts, and it is
    /// their conjunction that carries the safety property.
    @Test func aCloseDuringARunIsRefusedBeforeTerminationCouldBeReached() {
        let bench = Bench()
        bench.startARun()

        // Half one: the close never happens, so there is no "last window closed" to act on.
        #expect(bench.model.mainWindowCloseRequested() == .askFirst)

        // Half two: and even if a termination did arrive, the guard refuses it.
        #expect(bench.model.quitRequested() != .quitImmediately)
    }

    /// And from idle the termination goes straight through — no dialog for a user who closed the
    /// window of an app that is doing nothing.
    @Test func closingTheMainWindowWhenIdleQuitsWithoutAsking() {
        let bench = Bench()
        #expect(bench.model.mainWindowCloseRequested() == .allowCloseAndQuit)
        #expect(bench.model.quitRequested() == .quitImmediately)
    }

    /// **The window closes and the app quits — those are two steps, and the run guard sits
    /// between them.** `quitBecauseTheMainWindowClosed` requests rather than performs, so a run
    /// that somehow began between the close and the request still gets its dialog instead of
    /// being abandoned.
    @Test func aRunBeginningBetweenTheCloseAndTheQuitIsStillProtected() {
        let bench = Bench()
        #expect(bench.model.mainWindowCloseRequested() == .allowCloseAndQuit)

        bench.startARun()                    // the window has closed; a run starts
        #expect(bench.model.quitRequested() == .askFirst,
                "the termination request must still meet the guard")
    }

    // MARK: - Continue Testing

    @Test func continuingTestingRestoresEverything() {
        let bench = Bench()
        bench.startARun()
        _ = bench.model.quitRequested()

        bench.model.continueTesting()

        #expect(bench.model.quitState == .idle)
        #expect(bench.model.mayIssueNewWork)
        #expect(!bench.model.quitConfirmationIsPresented)
        #expect(bench.terminations == 0)
    }

    // MARK: - Cancel and Quit

    /// The promise, in one test: the app does not quit while the run is still coming back, and it
    /// does quit the moment it has.
    ///
    /// **A quit issues a stop** (recorded default 2026-08-12), so the wait is now for the helper to
    /// settle at its next chunk boundary rather than for a whole bounded call to finish — which
    /// makes the promise stronger, not weaker.
    @Test func quittingWaitsForTheRunToSettleAndThenGoes() {
        let bench = Bench()
        bench.startARun()
        _ = bench.model.quitRequested()

        bench.model.cancelAndQuit()
        #expect(bench.model.quitState == .windingDown)
        #expect(bench.sequencer?.stops == 1, "the run is stopped rather than merely waited out")
        #expect(bench.terminations == 0, "the in-flight call must still be allowed to come back")

        bench.endTheRun()
        #expect(bench.terminations == 1)
        #expect(bench.model.quitState == .terminating)
    }

    /// The race the wind-down would otherwise lose: a dialog can sit unanswered for far longer than
    /// the run it is asking about. Waiting for a transition that has already happened would look
    /// exactly like a button that does nothing.
    @Test func quittingAfterTheRunHasAlreadyFinishedDoesNotWaitForever() {
        let bench = Bench()
        bench.startARun()
        _ = bench.model.quitRequested()      // the dialog goes up while the run is live

        bench.endTheRun()                    // …and the run finishes underneath it
        #expect(bench.model.runIsActive == false)

        bench.model.cancelAndQuit()          // nothing is in flight, so this is the boundary

        #expect(bench.terminations == 1)
        #expect(bench.model.quitState == .terminating)
    }

    /// **The case the recorded default exists for, and the one the old stand-in could not reach.**
    /// A paused run has nothing in flight and no reply coming, so there is no call boundary to wait
    /// for at all. Without the stop, the wind-down would wait for ever.
    @Test func quittingAPausedRunStopsItRatherThanWaitingForACallThatWillNeverReturn() {
        let bench = Bench()
        bench.startARun()
        bench.pauseTheRun()
        _ = bench.model.quitRequested()

        bench.model.cancelAndQuit()

        #expect(bench.sequencer?.stops == 1)
        #expect(bench.terminations == 1, "it must not wait for a reply that is never coming")
        #expect(bench.model.quitState == .terminating)
    }

    @Test func noNewWorkMayBeIssuedOnceAQuitIsPending() {
        let bench = Bench()
        #expect(bench.model.mayIssueNewWork)

        bench.startARun()
        _ = bench.model.quitRequested()
        #expect(!bench.model.mayIssueNewWork,
                "the diagnostics window stays clickable under the sheet")

        bench.model.cancelAndQuit()
        #expect(!bench.model.mayIssueNewWork)
    }

    /// The app's own termination comes back through `quitRequested()`. If that answer were
    /// "wait for the boundary" the app could never quit.
    @Test func theAppsOwnTerminationIsNotRefusedByItsOwnGuard() {
        let bench = Bench()
        bench.startARun()
        _ = bench.model.quitRequested()
        bench.model.cancelAndQuit()
        bench.endTheRun()

        #expect(bench.model.quitState == .terminating)
        #expect(bench.model.quitRequested() == .quitImmediately)
    }

    @Test func aSecondQuitDuringTheWindDownDoesNotTerminateEarly() {
        let bench = Bench()
        bench.startARun()
        _ = bench.model.quitRequested()
        bench.model.cancelAndQuit()

        #expect(bench.model.quitRequested() == .waitForBoundary)
        #expect(bench.model.mainWindowCloseRequested() == .refuseSilently)
        #expect(bench.terminations == 0)

        bench.endTheRun()
        #expect(bench.terminations == 1)
    }

    /// SwiftUI writes `isPresented = false` when a button is chosen, and the order in which that
    /// write lands relative to the button's action is not something to depend on. Whichever way
    /// round it happens, the app must stay on its way out.
    @Test func dismissingTheAlertDoesNotUndoAConfirmedQuit() {
        let bench = Bench()
        bench.startARun()
        _ = bench.model.quitRequested()

        bench.model.cancelAndQuit()
        bench.model.quitConfirmationIsPresented = false

        #expect(bench.model.quitState == .windingDown)
    }

    @Test func dismissingTheAlertWithoutChoosingLeavesTheAppAlone() {
        let bench = Bench()
        bench.startARun()
        _ = bench.model.quitRequested()

        bench.model.quitConfirmationIsPresented = false

        #expect(bench.model.quitState == .idle)
        #expect(bench.model.mayIssueNewWork)
        #expect(bench.terminations == 0)
    }

    /// A run that ends by itself, with no quit pending, must not quit the app.
    @Test func anOrdinaryRunEndingDoesNotQuitTheApp() {
        let bench = Bench()
        bench.startARun()
        bench.endTheRun()

        #expect(bench.terminations == 0)
        #expect(bench.model.quitState == .idle)
    }
}
