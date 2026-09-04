//
//  QuitPolicy.swift
//  USBDriveTester (app target — unprivileged)
//
//  What ⌘Q and the main window's close button do while a run is active (user decision,
//  2026-08-05), as pure logic.
//
//  ## The decision this encodes
//
//  > Closing the main window or pressing ⌘Q while a run is active shows a modal —
//  > **"Cancel and Quit" / "Continue Testing"**. *Cancel and Quit* means **stop at the call
//  > boundary, then quit**: issue no further work, wait for the in-flight privileged call to
//  > return, release the device cleanly, then terminate. **Not an immediate kill.** The same
//  > dialog for both entry points.
//
//  ## Why "stop at the call boundary" is the only honest promise
//
//  There is no cancellation of a privileged call once issued — that is Step 11's work, and it is
//  precisely why the per-call cap exists (`TesterProtocol.maximumBytesPerCall`, 1 GiB, ≈7 s on
//  `disk4`). An app that claimed to *stop* a run would be claiming something the trust boundary
//  cannot deliver: the helper is inside `pread`/`pwrite` on a raw device and will finish the chunk
//  plan it was given whatever the client does. So the app promises the two things it can actually
//  do — **issue nothing further**, and **wait rather than walk away**.
//
//  Quitting without waiting is not *unsafe*: the helper releases a claim when the connection that
//  took it goes away (NFR-REL-5, `HelperActivity.releaseIfOwned(by:)`), so an abrupt exit still
//  ends with the device released and the volumes remounted. What waiting buys is a **clean,
//  observable** shutdown — the release is issued and acknowledged rather than inferred from a
//  socket closing — and, from Step 11 onward, it is what stops a whole-device run being abandoned
//  half way through by a keystroke that looks like housekeeping.
//
//  ## Why the release cannot be issued *during* the run, which is what forces the wait
//
//  Measured 2026-08-04 (`scripts/xpc-concurrency-check.sh`): while the helper is inside a blocking
//  privileged call, **a second message on that same connection is not delivered until the call
//  returns**. `releaseDevice` goes out on the owning connection, so issuing it mid-run would put it
//  in a queue behind the very call it was meant to shorten. Waiting for the boundary is therefore
//  not a stylistic choice about tidiness; it is the only order in which these two messages can
//  happen at all.
//
//  ## What counts as "a run is active" here, and what counts as "the boundary"
//
//  They are deliberately **different questions with different answers**:
//
//    * **Whether to ask** uses `AppModel.runIsActive` — the real bounded cycle *or* the Step 4/5
//      stand-in toggle. The toggle already means "a run is active" everywhere else in the app (it
//      refuses an uninstall, and it freezes the device list), and a stand-in that is honoured in
//      two places out of three is a stand-in that teaches the wrong lesson. It also makes this
//      dialog exercisable without writing a gibibyte to somebody's drive.
//    * **When to quit** uses `AppModel.cycleIsRunning` — a *real* privileged call in flight. There
//      is nothing to wait for when the only "run" is a toggle, and waiting for it would wait
//      forever.
//
//  Step 11 collapses both into the run-control state machine, at which point this policy takes its
//  input from one authoritative source instead of a union of two.
//
//  `nonisolated` throughout: the app target compiles with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor,
//  which would otherwise make even these enums main-actor-isolated and their `Equatable`
//  conformance unusable from the non-isolated test target.
//

import Foundation

/// Where the app is in a quit request.
///
/// One value rather than a set of booleans, because the states are mutually exclusive and the
/// interesting bugs are the combinations: "confirming *and* winding down" is not a state, and a
/// pair of flags is a way of writing it down.
nonisolated enum QuitState: Equatable {

    /// Nothing has been asked. The ordinary state.
    case idle

    /// The confirmation is on screen and the user has not chosen yet.
    case confirming

    /// "Cancel and Quit" was chosen. No further work is issued, and the app is waiting for the
    /// in-flight privileged call to return so it can release the device and terminate.
    case windingDown

    /// The boundary has been reached and termination has been asked for. Exists as a distinct
    /// state for one specific reason — see ``QuitPolicy/disposition(runIsActive:quitState:)``.
    case terminating
}

/// What the caller of a quit request should do about it.
nonisolated enum QuitDisposition: Equatable {

    /// Let the app terminate now.
    case quitImmediately

    /// Refuse this termination and put the confirmation on screen.
    case askFirst

    /// Refuse this termination and change nothing: the user has already chosen to quit, and the
    /// wind-down will terminate the app when the call boundary is reached. A second ⌘Q must not
    /// escalate into the immediate kill the decision rules out. (macOS still offers Force Quit,
    /// which is the right place for that to live.)
    case waitForBoundary
}

/// What the main window should do about a close attempt.
nonisolated enum WindowCloseDisposition: Equatable {

    /// Let the window close and leave the app running.
    ///
    /// Reached only while the app is **already terminating**, where AppKit is closing every window
    /// on its way out. Closing the main window is otherwise a request to quit — see
    /// ``allowCloseAndQuit``.
    case allowClose

    /// Let the window close, then ask the app to terminate (user decision 2026-08-06).
    ///
    /// ## Why closing the main window quits, rather than only closing the last window
    ///
    /// The first version of this used AppKit's
    /// `applicationShouldTerminateAfterLastWindowClosed`, which fires only when **no window at
    /// all** is left. Observed in the product, that reads as arbitrary: closing the main window
    /// quit the app, or didn't, depending on whether a diagnostics panel the user had opened
    /// earlier happened to still be up. The rule was a fact about AppKit's window count, not
    /// about anything the user did.
    ///
    /// > *"I don't think that this is an intuitive user experience. I think closing the main
    /// > window should always try to terminate the app."* — user, 2026-08-06
    ///
    /// So the main window's close **is** the quit request, and the auxiliary windows are what they
    /// look like: panels belonging to the app, which go when it goes.
    ///
    /// ## "Try to terminate", precisely
    ///
    /// The termination is *requested*, not performed — it goes out as an ordinary
    /// `NSApp.terminate(_:)` and lands in `applicationShouldTerminate`, which applies the same
    /// guard every other route does. This case is only ever produced from the idle state, so that
    /// guard will allow it; but routing it through rather than around means a run can never be
    /// abandoned by this path even if this table is later changed.
    case allowCloseAndQuit

    /// Refuse the close and put the confirmation on screen. The window never closes as part of
    /// this: the decision treats closing the main window as a *quit* request, so either the app
    /// terminates (taking the window with it) or the window stays exactly where it was.
    case askFirst

    /// Refuse the close and change nothing — the confirmation is already up, or the app is already
    /// winding down and the window is where the wind-down is visible.
    case refuseSilently
}

/// The quit and close decisions, as one truth table each.
nonisolated enum QuitPolicy {

    /// - Parameters:
    ///   - runIsActive: `AppModel.runIsActive` — a real cycle *or* the run-state stand-in.
    ///   - quitState: where the app already is in a quit request.
    static func disposition(runIsActive: Bool, quitState: QuitState) -> QuitDisposition {
        switch quitState {
        // The wind-down's own `NSApp.terminate(_:)` arrives here like any other quit request, and
        // it must not be turned away by the very state that scheduled it. Without this case the
        // app deadlocks the moment the run-state stand-in is left on: `runIsActive` is still true,
        // the state is still winding down, and every termination — including the app's own — is
        // answered "wait for the boundary" that has already passed.
        case .terminating:
            return .quitImmediately

        case .windingDown:
            // `runIsActive` is not consulted: the user has chosen, and asking again would offer a
            // decision that has already been made.
            return .waitForBoundary

        case .confirming:
            // The confirmation is already on screen. Re-presenting it would stack a second copy
            // over the first and leave the older one unanswered underneath.
            return .waitForBoundary

        case .idle:
            return runIsActive ? .askFirst : .quitImmediately
        }
    }

    /// - Parameters:
    ///   - runIsActive: `AppModel.runIsActive` — a real cycle *or* the run-state stand-in.
    ///   - quitState: where the app already is in a quit request.
    static func closeDisposition(runIsActive: Bool,
                                 quitState: QuitState) -> WindowCloseDisposition {
        switch quitState {
        // AppKit closes every window as it terminates. Obstructing that would be refusing a close
        // the app itself asked for.
        case .terminating:
            return .allowClose

        case .windingDown:
            // The window carries the wind-down banner and the live metrics of the call being
            // waited on. Letting it vanish would leave a privileged write finishing behind an app
            // with nothing on screen — which is the picture a user reads as "it crashed".
            return .refuseSilently

        case .confirming:
            return .refuseSilently

        case .idle:
            // Closing the main window is a quit request (user decision 2026-08-06). During a run
            // it is the same quit request every other route makes, and gets the same dialog.
            return runIsActive ? .askFirst : .allowCloseAndQuit
        }
    }
}

// MARK: - Quitting from under a modal (Step 11 increment 12)

/// A window-modal surface this app can have on screen.
///
/// ## Why the app has to name these at all
///
/// `NSApp.terminate(_:)` is refused **before** `applicationShouldTerminate` while a sheet is
/// attached (measured 2026-08-27, CONSTRAINTS §1), so ⌘Q under one of these runs no code of this
/// app's whatever. The app therefore declares its own Quit command to get a say at all — see
/// ``AppModel/quitRequestedFromMenu()``, where that is written out. Once it has a say, the
/// question it must answer is *which* modal is in the way, because the answer differs per
/// surface: a report is a document somebody has finished reading, and the pre-run prompt is the
/// last thing between a selected drive and a write.
///
/// ## FIVE, where the increment plan named three
///
/// A SwiftUI `.alert` on macOS is presented as a window-modal sheet like any other, so the quit
/// confirmation and the run-failure/Full-Disk-Access alert block ⌘Q exactly as the three
/// `.sheet`s do. Found by grepping for every modal in the app rather than by trusting the plan's
/// list — *a plan naming one surface is not evidence there is only one*, which is what the
/// `Covering` deletion paid for.
///
/// ## The case order IS the precedence
///
/// ``topmost(of:)`` consults `allCases` in order, so reordering these cases changes which modal a
/// quit is answered against. The consequences are pinned **by name** in `QuitPolicyTests` rather
/// than by a test that reads this order back — a test that agrees with any change is not a check.
nonisolated enum AppModal: Hashable, CaseIterable {

    /// "A test run is in progress" — the confirmation ⌘Q raises during a run. It outranks
    /// everything: the user is already being asked about quitting, and a second question behind
    /// the first is not an answer to it.
    case quitConfirmation

    /// The launch-time helper gate (increment 9). The app cannot be used at all until it clears.
    case helperGate

    /// FR-WARN-1/2/3's pre-run dialog.
    case preRunPrompt

    /// A failure that interrupts — a drive that could not be prepared, or the Full Disk Access
    /// alert (increment 10).
    case runFailure

    /// The end-of-run report, a sheet on the main window since increment 8.
    case runReport

    /// What the log calls this. Not user-facing: the sentences a user is owed are
    /// ``QuitPolicy/disposition(underModals:)``'s refusal reasons.
    var loggingName: String {
        switch self {
        case .quitConfirmation: return "quit confirmation"
        case .helperGate:       return "helper gate"
        case .preRunPrompt:     return "pre-run prompt"
        case .runFailure:       return "failure alert"
        case .runReport:        return "run report"
        }
    }

    /// Which of the presented modals a quit is answered against.
    ///
    /// **More than one can be flagged at once**, and this is reachable rather than hypothetical: a
    /// run finishing while the quit confirmation is up sets `reportIsPresented` underneath it.
    /// SwiftUI cannot show two sheets on one window and **queues** the second (measured at the
    /// keyboard 2026-08-21, chunk 11.11) — and nothing in the model can see that queue, so the
    /// model's idea of which one is *visible* may simply be wrong.
    ///
    /// That is why this only chooses the sentence. Which modal may be *discarded* is
    /// ``QuitPolicy/disposition(underModals:)``'s, and it refuses outright whenever more than one
    /// is flagged — see the note there.
    static func topmost(of presented: Set<AppModal>) -> AppModal? {
        allCases.first { presented.contains($0) }
    }
}

/// What a quit request should do about whatever modal is on screen.
nonisolated enum ModalQuitDisposition: Equatable {

    /// Nothing is in the way. Ask for the termination exactly as any other route would, and let
    /// `applicationShouldTerminate` take the vote.
    case requestTermination

    /// Take **this** modal down first — through its own presentation state, not with
    /// `endSheet(_:)` — and then ask for the termination.
    ///
    /// **It carries which one on purpose.** A bare case would let a caller take down whichever
    /// modal it happened to think was up, and dismissing the wrong one leaves the visible one
    /// attached with the termination still refused, silently: the original defect, rebuilt by the
    /// code meant to fix it.
    case dismiss(AppModal)

    /// This modal must be answered first, and here is why in a sentence.
    ///
    /// **The refusal is kept, and only its silence is removed.** The sentence reaches the log
    /// (NFR-OBS-1) and the menu item greys out; there is nowhere on a disabled menu item to show
    /// prose, and pretending otherwise would be the "correct value nobody can observe" defect in
    /// a new place. What the user sees is that Quit is *unavailable*, rather than that it is
    /// available and does nothing — which is the half of this defect that mattered.
    case refuse(reason: String)
}

extension QuitPolicy {

    /// The third truth table: what ⌘Q does about the modals that are up.
    ///
    /// **It does not duplicate ``disposition(runIsActive:quitState:)``, and must not.** This one
    /// answers *"is anything in the way, and may it be discarded"*; that one answers *"would
    /// quitting abandon a run"*. They compose — a report dismissed while the run is still
    /// `finishing` still meets `.askFirst` a moment later — and collapsing them would be one flag
    /// stating two facts, which is the misdiagnosis this project has already paid for.
    ///
    /// ## Which modals a quit may discard (user decision, 2026-09-04)
    ///
    /// | modal | answer | why |
    /// |---|---|---|
    /// | none | request the termination | unchanged from before this increment |
    /// | launch gate | dismiss | increment 9 decided it for the gate's own Quit button; this generalises it |
    /// | run report | dismiss | a document somebody has finished reading. Chunk 11.7 left this open *"until this has been seen"*; it has been |
    /// | pre-run prompt | refuse | **2026-08-18 stands** — it is the last thing between a selected drive and a write, and a keystroke meaning "leave" must not answer it |
    /// | failure alert | refuse | it interrupts on purpose, and one keystroke clears it |
    /// | quit confirmation | refuse | a quit is already being asked about. `disposition(runIsActive:quitState:)` answers `.waitForBoundary` there, and dismissing this to re-terminate would ask the same question again |
    ///
    /// ## Why an EXHAUSTIVE switch and not a lookup
    ///
    /// A sixth modal added later is then a **compile error** here rather than a sixth silently
    /// dead ⌘Q. That is the failure mode that produced this increment: three sheets were added
    /// over three increments and each one quietly killed the keystroke, because nothing anywhere
    /// had to have an opinion about them.
    ///
    /// ## Why more than one flagged is refused outright
    ///
    /// The model cannot see SwiftUI's presentation queue, so with two flagged it does not know
    /// which is actually on screen — and taking down the one that is *not* leaves the termination
    /// refused with nothing to show for it. Refusing is the honest answer and it is logged. The
    /// consequence is structural rather than argued: ``ModalQuitDisposition/dismiss(_:)`` is
    /// produced **only** when exactly one modal is flagged, and `everyAmbiguousSetIsRefused` walks
    /// all 32 subsets to say so.
    static func disposition(underModals presented: Set<AppModal>) -> ModalQuitDisposition {
        guard let topmost = AppModal.topmost(of: presented) else {
            return .requestTermination
        }

        guard presented.count == 1 else {
            return .refuse(reason: "More than one dialog is open. Answer them before quitting.")
        }

        switch topmost {
        case .helperGate, .runReport:
            return .dismiss(topmost)

        case .preRunPrompt:
            return .refuse(reason: "Cancel the pre-run confirmation first. It is the last check "
                                 + "before the drive is written to.")

        case .runFailure:
            return .refuse(reason: "Dismiss the failure message first.")

        case .quitConfirmation:
            return .refuse(reason: "A quit is already being confirmed. Answer that dialog.")
        }
    }
}
