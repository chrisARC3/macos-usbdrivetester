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
//    * a confirmed quit while a real cycle is in flight terminates **at the moment the cycle
//      ends**, not before it and not never; and
//    * a confirmed quit when the cycle has *already* ended terminates straight away — the dialog
//      can easily sit on screen for longer than the ~7 s bounded call it is asking about, and an
//      app that waited for a transition that had already happened would appear to ignore the
//      button entirely.
//
//  `terminateAction` is injected, so "the app quits" is observable without any of these tests
//  taking the process down with them. Nothing here touches XPC: with no device held there is
//  nothing to release, which is exactly the seam `QuitSequence` already draws.
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

    /// A model that reports quitting instead of doing it.
    private func makeModel() -> (AppModel, Recorder) {
        let recorder = Recorder()
        let model = AppModel()
        model.terminateAction = { recorder.terminations += 1 }
        return (model, recorder)
    }

    // MARK: - Asking

    @Test func quittingWithNoRunIsNotQuestioned() {
        let (model, recorder) = makeModel()
        #expect(model.quitRequested() == .quitImmediately)
        #expect(model.quitState == .idle)
        #expect(recorder.terminations == 0, "AppKit terminates; the model does not do it itself")
    }

    /// The run-state stand-in counts as a run for the *question*. It is what makes the dialog
    /// exercisable without writing a gibibyte to a drive, and it is what the rest of the app
    /// already treats as a run (uninstall refusal, device-list freeze).
    @Test func theRunStateStandInIsEnoughToBeAsked() {
        let (model, _) = makeModel()
        model.simulatedRunActive = true

        #expect(model.quitRequested() == .askFirst)
        #expect(model.quitState == .confirming)
        #expect(model.quitConfirmationIsPresented)
    }

    @Test func aRealCycleIsEnoughToBeAsked() {
        let (model, _) = makeModel()
        model.cycleIsRunning = true

        #expect(model.quitRequested() == .askFirst)
        #expect(model.quitState == .confirming)
    }

    @Test func closingTheWindowAsksTheSameQuestionAndKeepsTheWindow() {
        let (model, _) = makeModel()
        model.cycleIsRunning = true

        #expect(model.mainWindowCloseRequested() == .askFirst)
        #expect(model.quitState == .confirming)
    }

    @Test func closingTheWindowWithNoRunClosesAndQuits() {
        let (model, _) = makeModel()
        #expect(model.mainWindowCloseRequested() == .allowCloseAndQuit)
        #expect(model.quitState == .idle, "the quit is requested by the guard, not entered here")
    }

    // MARK: - Closing the MAIN window quits (user decision 2026-08-06)

    /// The termination the guard requests after the window has closed. It goes through
    /// `terminateAction`, which in the app is `NSApp.terminate(_:)` — so it lands in
    /// `applicationShouldTerminate` and picks up the same guard ⌘Q does, rather than killing the
    /// app directly.
    @Test func closingTheMainWindowRequestsATermination() {
        let (model, recorder) = makeModel()

        #expect(model.mainWindowCloseRequested() == .allowCloseAndQuit)
        model.quitBecauseTheMainWindowClosed()

        #expect(recorder.terminations == 1)
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
        let (model, _) = makeModel()
        model.cycleIsRunning = true

        // Half one: the close never happens, so there is no "last window closed" to act on.
        #expect(model.mainWindowCloseRequested() == .askFirst)

        // Half two: and even if a termination did arrive, the guard refuses it.
        #expect(model.quitRequested() != .quitImmediately)
    }

    /// And from idle the termination goes straight through — no dialog for a user who closed the
    /// window of an app that is doing nothing.
    @Test func closingTheMainWindowWhenIdleQuitsWithoutAsking() {
        let (model, _) = makeModel()
        #expect(model.mainWindowCloseRequested() == .allowCloseAndQuit)
        #expect(model.quitRequested() == .quitImmediately)
    }

    /// **The window closes and the app quits — those are two steps, and the run guard sits
    /// between them.** `quitBecauseTheMainWindowClosed` requests rather than performs, so a run
    /// that somehow began between the close and the request still gets its dialog instead of
    /// being abandoned. Unreachable through the UI today; asserted because the whole point of
    /// routing through `applicationShouldTerminate` is that it stays true if this table changes.
    @Test func aRunBeginningBetweenTheCloseAndTheQuitIsStillProtected() {
        let (model, _) = makeModel()
        #expect(model.mainWindowCloseRequested() == .allowCloseAndQuit)

        model.cycleIsRunning = true                    // the window has closed; a run starts
        #expect(model.quitRequested() == .askFirst,
                "the termination request must still meet the guard")
    }

    // MARK: - Continue Testing

    @Test func continuingTestingRestoresEverything() {
        let (model, recorder) = makeModel()
        model.cycleIsRunning = true
        _ = model.quitRequested()

        model.continueTesting()

        #expect(model.quitState == .idle)
        #expect(model.mayIssueNewWork)
        #expect(!model.quitConfirmationIsPresented)
        #expect(recorder.terminations == 0)
    }

    // MARK: - Cancel and Quit

    /// The promise, in one test: the app does not quit while the privileged call is in flight, and
    /// it does quit the moment that call returns.
    @Test func quittingWaitsForTheCallBoundaryAndThenGoes() {
        let (model, recorder) = makeModel()
        model.cycleIsRunning = true
        _ = model.quitRequested()

        model.cancelAndQuit()
        #expect(model.quitState == .windingDown)
        #expect(recorder.terminations == 0, "the in-flight call must be allowed to finish")

        model.cycleIsRunning = false
        #expect(recorder.terminations == 1)
        #expect(model.quitState == .terminating)
    }

    /// The race the wind-down would otherwise lose: a bounded cycle is about seven seconds, and a
    /// dialog can sit unanswered for much longer. Waiting for a transition that has already
    /// happened would look exactly like a button that does nothing.
    @Test func quittingAfterTheRunHasAlreadyFinishedDoesNotWaitForever() {
        let (model, recorder) = makeModel()
        model.simulatedRunActive = true          // still "a run" as far as the question goes
        _ = model.quitRequested()

        model.cancelAndQuit()                    // nothing is in flight, so this is the boundary

        #expect(recorder.terminations == 1)
        #expect(model.quitState == .terminating)
    }

    @Test func noNewWorkMayBeIssuedOnceAQuitIsPending() {
        let (model, _) = makeModel()
        #expect(model.mayIssueNewWork)

        model.cycleIsRunning = true
        _ = model.quitRequested()
        #expect(!model.mayIssueNewWork, "the diagnostics window stays clickable under the sheet")

        model.cancelAndQuit()
        #expect(!model.mayIssueNewWork)
    }

    /// The app's own termination comes back through `quitRequested()`. If that answer were
    /// "wait for the boundary" the app could never quit — and with the stand-in toggle left on,
    /// `runIsActive` stays true for as long as the process lives.
    @Test func theAppsOwnTerminationIsNotRefusedByItsOwnGuard() {
        let (model, _) = makeModel()
        model.simulatedRunActive = true
        _ = model.quitRequested()
        model.cancelAndQuit()

        #expect(model.quitState == .terminating)
        #expect(model.quitRequested() == .quitImmediately)
    }

    @Test func aSecondQuitDuringTheWindDownDoesNotTerminateEarly() {
        let (model, recorder) = makeModel()
        model.cycleIsRunning = true
        _ = model.quitRequested()
        model.cancelAndQuit()

        #expect(model.quitRequested() == .waitForBoundary)
        #expect(model.mainWindowCloseRequested() == .refuseSilently)
        #expect(recorder.terminations == 0)

        model.cycleIsRunning = false
        #expect(recorder.terminations == 1)
    }

    /// SwiftUI writes `isPresented = false` when a button is chosen, and the order in which that
    /// write lands relative to the button's action is not something to depend on. Whichever way
    /// round it happens, the app must stay on its way out.
    @Test func dismissingTheAlertDoesNotUndoAConfirmedQuit() {
        let (model, _) = makeModel()
        model.cycleIsRunning = true
        _ = model.quitRequested()

        model.cancelAndQuit()
        model.quitConfirmationIsPresented = false

        #expect(model.quitState == .windingDown)
    }

    @Test func dismissingTheAlertWithoutChoosingLeavesTheAppAlone() {
        let (model, recorder) = makeModel()
        model.cycleIsRunning = true
        _ = model.quitRequested()

        model.quitConfirmationIsPresented = false

        #expect(model.quitState == .idle)
        #expect(model.mayIssueNewWork)
        #expect(recorder.terminations == 0)
    }

    /// A run that ends by itself, with no quit pending, must not quit the app.
    @Test func anOrdinaryRunEndingDoesNotQuitTheApp() {
        let (model, recorder) = makeModel()
        model.cycleIsRunning = true
        model.cycleIsRunning = false

        #expect(recorder.terminations == 0)
        #expect(model.quitState == .idle)
    }
}
