//
//  AppModel.swift
//  USBDriveTester (app target — unprivileged)
//
//  Step 9. The state that has to outlive any one window, and be the same object in all of them.
//
//  ## Why this exists at all
//
//  Until Step 9 the app was one window, so `ContentView` could own everything with `@State`. The
//  diagnostics panel then moved into its own window, and one piece of that state stopped being a
//  convenience and became a **correctness requirement**:
//
//  > The helper ties a device claim to the XPC connection that acquired it, and releases the
//  > claim when that connection goes away (NFR-REL-5). Two windows each creating their own
//  > `HelperConnection` would be two owners — and closing one window could drop a claim out from
//  > under a run happening in the other, leaving a half-written device.
//
//  That is the same hazard Step 6 hit when the device list gained its own reason to talk to the
//  helper, and it was solved the same way: one connection, hoisted to where every consumer shares
//  it. The scene split just moves "where" up a level.
//
//  ## Why the run state is here too
//
//  The bounded cycle is started from the **diagnostics** window and displayed by the metrics panel
//  in the **main** window. Neither can own that fact. And the app deliberately does not ask the
//  helper whether a run is active — it issues the run itself and receives the completion, so it
//  already knows (user decision 2026-08-04); a second source for the same fact would be a second
//  thing that can be wrong.
//
//  Step 11 replaces `simulatedRunActive` and `cycleIsRunning` with the run-control state machine,
//  which becomes the single authoritative source this class is standing in for.
//
//  ## Why quitting is coordinated here too (2026-08-05)
//
//  ⌘Q and the main window's close button both have to ask the same question and get the same
//  answer, and neither of them is a view: one arrives at `AppLifecycleDelegate`, the other at
//  `MainWindowCloseGuard`. The state they share — and the run they are asking about — is here.
//  The *decisions* are in `QuitPolicy`, where the whole truth table can be tested; this class
//  holds the state and performs the consequences.
//

import AppKit
import SwiftUI

/// State shared by every window in the app.
@MainActor
@Observable
final class AppModel {

    /// **The** connection to the privileged helper. One per app, for the reason above.
    ///
    /// Not `private(set)`-able usefully — views need to call through it — but there must never be
    /// a second one. `HelperConnection` internally owns a second *XPC* connection for progress
    /// polling, which is a different thing entirely: it is non-owning, never acquires, and its
    /// death releases nothing.
    let helper = HelperConnection()

    /// Answers `windowShouldClose(_:)` for the main window. Owned here because it must outlive any
    /// window — `NSWindow.delegate` is a *weak* reference, so a guard owned by the view that
    /// installs it would leave the window with no delegate at all the moment that view went away.
    let mainWindowCloseGuard = MainWindowCloseGuard()

    init() {
        mainWindowCloseGuard.model = self
    }

    /// Step 4/5's stand-in toggle: blocks uninstall (NFR-REL-5) and freezes discovery (FR-DEV-7).
    var simulatedRunActive = false

    /// True while Step 9's bounded cycle is actually in flight.
    var cycleIsRunning = false {
        didSet {
            // Capture *which drive* and *when*, at the moment the run starts. See
            // `lastRunDeviceName` and `lastRunStartedAt` for why the metrics panel needs both.
            if cycleIsRunning {
                lastRunDeviceName = heldDeviceName
                lastRunDeviceSerial = heldDeviceSerial
                lastRunStartedAt = Date()
            } else if quitState == .windingDown {
                // **This is the call boundary.** The privileged call has returned, so the device
                // can be released — which it could not be a moment ago, because a message on the
                // connection running the cycle is not delivered until that cycle ends (measured
                // 2026-08-04, `xpc-concurrency-check.sh`).
                beginRelease()
            }
        }
    }

    /// BSD name of the drive the helper currently holds, or `nil` when it holds none.
    ///
    /// Tracked alongside ``helperHoldsDevice`` rather than derived from the device list, because
    /// the claim belongs to the *helper* and outlives any particular selection — which is exactly
    /// the property the list's selection does not have.
    var heldDeviceName: String?

    /// Serial number of the drive the helper currently holds, or `nil` when it holds none or the
    /// drive reported none.
    ///
    /// Carried beside ``heldDeviceName`` because the BSD name is a locator and this is the
    /// identity — see `DiscoveredDevice.usbSerialNumber`.
    var heldDeviceSerial: String?

    /// BSD name of the drive the most recent run was performed on.
    ///
    /// ## Why the metrics panel has to name its drive (2026-08-05, user decision)
    ///
    /// The panel is headed "Last run" and keeps its figures after the run ends — correctly, since
    /// they are the run's result. But it sat under a *device list*, so after selecting a different
    /// drive it read as that drive's numbers. Reported as one of three panes showing stale
    /// information for a device that was no longer selected.
    ///
    /// Naming the drive fixes it without deleting evidence, which clearing the panel would have
    /// done. A measurement whose subject is unstated is the same defect as a percentile printed
    /// without its bound: not wrong, just not saying what it is about.
    ///
    /// Step 10's report supersedes this — it records device identity as a matter of course.
    var lastRunDeviceName: String?

    /// Serial number of the drive the most recent run was performed on.
    ///
    /// The one field that survives a replug as an answer to "which drive was this?". `nil` when
    /// that drive reported no serial, which the metrics panel states with a warning rather than
    /// leaving the model name to imply an identification it cannot make.
    var lastRunDeviceSerial: String?

    /// When the most recent run started.
    ///
    /// Same reasoning as ``lastRunDeviceName``, in the other dimension: the panel keeps its
    /// figures after the run ends, so "Last run" alone never says *when*. Within one sitting that
    /// is merely unhelpful; across a long session it is misleading, because a reading taken hours
    /// ago looks exactly like one taken a moment ago.
    ///
    /// - Note: this app retains **no run history** (FR-RPT — each run stands alone, and export is
    ///   the only persistence), so this cannot outlive the process and a displayed run is always
    ///   from the current session. The timestamp is still worth carrying: it is what Step 10's
    ///   exported report needs, and the report *does* outlive the session — which is the case
    ///   where an undated measurement really can be read as current years later.
    var lastRunStartedAt: Date?

    /// Negotiated USB link speed of the held device, from `deviceProfile`. Shown beside measured
    /// throughput so a rate can be judged against the manufacturer's advertised sustained figure
    /// "after accounting for negotiated speed limits" — the user's stated method, which needs
    /// both numbers.
    var linkSpeedCode = -1

    /// Whether the helper currently holds exclusive access to a device.
    ///
    /// Owned here because the two windows disagree about it otherwise: the **main** window is
    /// where a device is acquired and released, and the **diagnostics** window is where the
    /// bounded cycle is started — and that cycle cannot run without one.
    ///
    /// Added 2026-08-04 after the button was reported as doing nothing. It was in fact working
    /// perfectly: the helper answered *"no device is held"* in 25 ms, the spinner flashed for a
    /// frame, and a failure message was the only trace. Every other control in this app disables
    /// itself and names the corrective step rather than failing on press (FR-SAFE-4, NFR-USE-5);
    /// this one said "requires a device to be acquired first" in prose and then looked live.
    /// Prose is not a precondition.
    ///
    /// - Note: the app's belief, refreshed from `checkDeviceReadiness` and the acquire/release
    ///   results. The helper remains the authority — this only decides whether a control is
    ///   offered, never whether a run may proceed.
    var helperHoldsDevice = false

    /// Whether anything that must freeze the device list is happening (FR-DEV-7).
    ///
    /// Either source is enough, so this is an `or` rather than two independent switches. A real
    /// cycle freezes discovery for exactly the reason the stand-in does: the list must not rebuild
    /// underneath a run.
    var runIsActive: Bool { simulatedRunActive || cycleIsRunning }

    // MARK: - Quitting during a run (user decision 2026-08-05)

    /// Where the app is in a quit request. See `QuitPolicy` for what each state means and why the
    /// states are one value rather than a handful of booleans.
    private(set) var quitState: QuitState = .idle

    /// Live for the length of one wind-down. Held so its callbacks and its deadline survive.
    private var quitSequence: QuitSequence?

    /// What "quit" actually does.
    ///
    /// Injected for two consumers that must not really terminate: the unit tests, and
    /// `tools/ui-probe`, which renders the winding-down banner — a state no render could otherwise
    /// reach, since getting there through the UI means quitting.
    var terminateAction: () -> Void = { NSApp.terminate(nil) }

    /// Whether new privileged work may still be issued.
    ///
    /// False from the moment a quit is *pending*, not merely decided: the confirmation is a
    /// window-modal sheet on the main window, so the diagnostics window stays clickable
    /// underneath it, and starting a gibibyte of writes while a "shall I quit?" dialog is open is
    /// not a thing to leave available. "Issue no further work" is the first half of the
    /// stop-at-the-boundary promise, and this is where it is kept — Step 11's run sequencer must
    /// consult it before every call it issues.
    var mayIssueNewWork: Bool { quitState == .idle }

    /// True while the app is waiting for the call boundary so it can quit.
    var isWindingDown: Bool { quitState == .windingDown }

    /// Whether the confirmation is on screen. Settable so SwiftUI's `alert(isPresented:)` can
    /// bind to it; a separate stored flag would be a second copy of `quitState` and would
    /// eventually disagree with it.
    var quitConfirmationIsPresented: Bool {
        get { quitState == .confirming }
        set {
            // Only ever *clears* the confirmation, and only if that is still what is showing. A
            // dismissal that arrives after "Cancel and Quit" has already moved the app on must not
            // drag it back to idle — SwiftUI's ordering between the button's action and the
            // binding write is not something to depend on.
            if !newValue, quitState == .confirming { quitState = .idle }
        }
    }

    /// The app has been asked to terminate. Returns what the caller should do about it.
    func quitRequested() -> QuitDisposition {
        let disposition = QuitPolicy.disposition(runIsActive: runIsActive, quitState: quitState)
        if disposition == .askFirst { quitState = .confirming }
        return disposition
    }

    /// The main window has been asked to close. Returns what the caller should do about it.
    func mainWindowCloseRequested() -> WindowCloseDisposition {
        let disposition = QuitPolicy.closeDisposition(runIsActive: runIsActive,
                                                      quitState: quitState)
        if disposition == .askFirst { quitState = .confirming }
        return disposition
    }

    /// "Continue Testing" — the run goes on and the app stays.
    func continueTesting() {
        if quitState == .confirming { quitState = .idle }
    }

    /// "Cancel and Quit" — issue nothing further, then quit at the call boundary.
    func cancelAndQuit() {
        guard quitState == .confirming || quitState == .idle else { return }
        quitState = .windingDown

        // The boundary may already have passed: a bounded cycle takes about seven seconds and a
        // dialog can sit unanswered for longer. Without this the app would wait for a
        // `cycleIsRunning` transition that had already happened, and quitting would appear to do
        // nothing at all.
        if !cycleIsRunning { beginRelease() }
    }

    /// Release the device, then terminate. See `QuitSequence` for the once-only and no-hang
    /// properties this delegates to.
    private func beginRelease() {
        guard quitSequence == nil else { return }

        // `nil` when nothing is held — there is then nothing to release and nothing to wait for.
        let release: QuitSequence.Release? = helperHoldsDevice
            ? { [helper] done in helper.releaseDevice { _ in done() } }
            : nil

        // The acknowledgement deadline is `QuitSequence`'s own default rather than a figure
        // restated here: two statements of one number are two things that can drift, and the
        // reason it is five seconds is documented where it is used.
        let sequence = QuitSequence(release: release) { [weak self] in
            guard let self else { return }
            // Recorded *before* terminating: the second `applicationShouldTerminate` this triggers
            // has to be able to tell the app's own quit from a user pressing ⌘Q again.
            self.quitState = .terminating
            self.helperHoldsDevice = false
            self.heldDeviceName = nil
            self.heldDeviceSerial = nil
            self.terminateAction()
        }
        quitSequence = sequence
        sequence.begin()
    }
}

/// Identifiers for the app's windows, shared by the scene that declares each one and the controls
/// that open it. A string literal in two places is a typo waiting to silently open nothing.
enum WindowID {
    static let main = "main"
    static let diagnostics = "diagnostics"
}
