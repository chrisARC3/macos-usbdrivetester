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

    case allowClose

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
            return runIsActive ? .askFirst : .allowClose
        }
    }
}
