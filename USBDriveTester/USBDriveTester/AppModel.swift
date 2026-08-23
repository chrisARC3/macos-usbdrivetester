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
//  ## The run state collapsed here in Step 11 increment 5
//
//  Three things used to answer "is a run happening", and each was consulted by a different part of
//  the app:
//
//    * `simulatedRunActive` — Step 4/5's stand-in, which blocked uninstall and froze the list;
//    * `cycleIsRunning` — Step 9's real bounded cycle, and the quit's call boundary;
//    * `helperHoldsDevice` — **deleted rather than fixed.** It was written from
//      `checkDeviceReadiness`'s `helperHoldsThisDevice`, a *per-device* answer, and read at every
//      use site as "the helper holds *some* device". Do not reintroduce a selection-scoped flag.
//
//  All three are gone. ``runControl`` is the single authoritative source, and everything that used
//  to ask one of the three now asks it. One consequence simplifies the quit path considerably:
//  **the app never holds a claim outside a run any more.** The claim's lifetime is exactly the
//  run's, by construction rather than by bookkeeping — which is the property `helperHoldsDevice`
//  was failing to state.
//
//  ## Why device discovery is here and not in `ContentView`
//
//  It was `@State` on the main window until increment 5, and moving it is not tidiness. The run
//  controller needs the selected drive, and it needs it from an **escaping closure**. A SwiftUI
//  `View` is a struct, and a closure created inside one captures what the view was built with —
//  the defect that headed every first-run report "Unidentified drive". Owning discovery here means
//  every closure the controller holds captures exactly one long-lived class and nothing else.
//
//  Discovery is app-lifetime anyway: it starts once and keeps itself current (FR-DEV-7), and
//  closing the main window quits the app.
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

    /// The device list, and the selection a run is started against (FR-DEV-1/3/4/7).
    ///
    /// Owned here from increment 5 — see this file's header for why it left `ContentView`.
    let discovery: DeviceDiscovery

    /// Answers `windowShouldClose(_:)` for the main window. Owned here because it must outlive any
    /// window — `NSWindow.delegate` is a *weak* reference, so a guard owned by the view that
    /// installs it would leave the window with no delegate at all the moment that view went away.
    let mainWindowCloseGuard = MainWindowCloseGuard()

    /// **The** run state (FR-CTRL-1…9). Everything that used to ask one of the three deleted
    /// sources asks this.
    ///
    /// `nil` until the main window has appeared, which is where it is built — and that is honest
    /// rather than a gap: **no run can be in flight before the UI that starts one exists**, which
    /// is the same reasoning `USBDriveTesterApp` already relies on for wiring the lifecycle
    /// delegate at `onAppear`. A ⌘Q arriving before then finds no run and terminates immediately.
    ///
    /// Built in the view rather than in `init` because its dependencies close over this object,
    /// and a class cannot hand `self` to something it is in the middle of constructing.
    var runControl: RunController?

    /// Where the suppression preference is kept. See ``warningsSuppressed``.
    private let suppressionStore: PreRunWarningSuppressionStore

    /// Where the selected I/O size is kept between launches. See ``ioSizeBytes``.
    private let ioSizeStore: IOSizeStore

    /// - Parameters:
    ///   - suppressionStore: injected by tests and by `tools/ui-probe` so neither touches the real
    ///     user's preferences. The default is the only one the app ever uses.
    ///   - ioSizeStore: injected for the same reason and by the same two consumers (increment 6).
    ///   - deviceSource: injected for the same two consumers, so a render and a test can present a
    ///     known device list with no hardware attached.
    init(suppressionStore: PreRunWarningSuppressionStore = UserDefaultsPreRunWarningSuppression(),
         ioSizeStore: IOSizeStore = UserDefaultsIOSize(),
         deviceSource: DeviceSource = IOKitDeviceEnumerator()) {
        self.suppressionStore = suppressionStore
        self.ioSizeStore = ioSizeStore
        self.discovery = DeviceDiscovery(source: deviceSource)
        self.warningsSuppressed = suppressionStore.warningsSuppressed
        self.ioSizeBytes = ioSizeStore.ioSizeBytes
        mainWindowCloseGuard.model = self
    }

    /// Whether the user has asked not to see the pre-run **warning text** again (decision 5).
    ///
    /// **Stored here and written through to the store, rather than computed from it**, and that is
    /// a deliberate choice with one reason: `@Observable` tracks stored properties. A computed
    /// property reading a plain object would leave SwiftUI with nothing to observe, so the
    /// diagnostics window's "Show pre-run warnings again" control would not update when it changed
    /// — a correct value nobody can see, which is the defect this step has already paid for twice.
    ///
    /// The two cannot drift: this is the only writer, and it writes through on every set. The store
    /// is the persistence, this is the value.
    ///
    /// **Suppressing the text never suppresses the deliberate act** (NFR-USE-4 as qualified
    /// 2026-08-09). `PreRunPrompt.forRun` still raises a dialog; only its content changes.
    var warningsSuppressed: Bool {
        didSet { suppressionStore.warningsSuppressed = warningsSuppressed }
    }

    /// The pre-run dialog Start raised, or `nil` when none is up (FR-WARN-1/2/3).
    ///
    /// **It was `@State` inside `RunControlsView` until chunk 11.11 found what that costs.** The
    /// menu item that raises the report lives in the scene's `commands` builder, which has no
    /// environment and cannot see a view's state — so it could not know a dialog was already on
    /// this window. Whether a modal is up is a fact about the *window*, and the thing that must not
    /// raise a second one is outside the view that owns the first.
    ///
    /// The checkbox inside the dialog stays view-local, and deliberately: see
    /// `RunControlsView.suppressionRequested`. What moved here is only the fact that a dialog
    /// exists.
    var pendingPrompt: PreRunPrompt?

    // MARK: - The end-of-run report (Step 10)

    /// The report the most recent **run** produced, or `nil` when no run has finished this
    /// session — or when the last call was **refused**, which is not a run and gets no report.
    ///
    /// Not history: FR-RPT keeps each run standalone and this is replaced by the next one.
    /// Export is the only persistence (FR-RPT-5).
    var lastRunReport: RunReport?

    /// Whether the report is on screen.
    ///
    /// The report is a **sheet on the main window** (user decision 2026-08-19) rather than a window
    /// of its own, and this flag is the whole of its presentation. What the change buys is a
    /// forcing function: a window-modal sheet puts the run controls out of reach, so **a run cannot
    /// start underneath an open report**. That is the defect it was moved for — a run beginning
    /// clears the previous run's report (``runBegan()``), and on hardware that emptied a report
    /// somebody was still reading.
    var reportIsPresented = false

    /// A run finished: replace the report, and put it on screen.
    ///
    /// Here rather than inside `RunControllerWiring`'s closure so that a test can reach it. What a
    /// finished run does to the report is a decision, and while it lived in a closure that needs a
    /// helper and a drive to construct it had no cover at all.
    ///
    /// **A refused call is not a run.** It produces no report and raises nothing, and the log says
    /// why so the absence is explicable rather than looking like a lost one: a sheet reading "No run
    /// has finished yet" immediately after pressing Start would be worse than no sheet.
    func runProduced(_ report: RunReport?) {
        lastRunReport = report
        guard let report else {
            RunReportLog.noReportForRefusedCall("the request did not become a run")
            return
        }
        RunReportLog.reportProduced(report)
        reportIsPresented = true
    }

    /// A run began. The previous run's report is not this run's, and leaving it in place while a
    /// new run is in flight is the stale-pane defect Step 9 was reported for.
    func runBegan() {
        lastRunReport = nil
    }

    /// Whether the **Run Report** menu item may raise the report (⇧⌘R).
    ///
    /// - Important: this is **not** the question of whether the report may be *shown*, and
    ///   answering both with this one property would suppress every report the app produces.
    ///   ``runProduced(_:)`` is called from `finishing`, which is run-active — so a menu item
    ///   disabled at that instant is right, and a raise refused at that instant is not. One flag
    ///   stating two facts is a misdiagnosis this project has already paid for once, in the ⌘Q
    ///   defect chunk 6 found.
    ///
    /// Disabled during a run for two reasons, of which the first is enough on its own: a run clears
    /// the report as it begins, so there is nothing left to raise but the empty state. The second is
    /// that a window-modal sheet would put **Pause and Stop** out of reach until it was dismissed
    /// (user decision, 2026-08-21).
    ///
    /// ## And disabled while a pre-run dialog is up — found at the keyboard, 2026-08-21
    ///
    /// **A window-modal sheet does not swallow menu commands.** This project had believed it did,
    /// from check 6.1 in increment 5, where ⌘Q during the pre-run dialog never reached `QuitPolicy`.
    /// Chunk 11.11 pressed ⇧⌘R with that dialog open and found the command *runs*: SwiftUI cannot
    /// present a second sheet on one window, so it **queues** it — and the report appeared on its
    /// own the moment the dialog was cancelled, a modal arriving at a time nobody asked for it.
    ///
    /// 6.1's observation is not overturned, only narrowed: ⌘Q is AppKit's terminate and reaches a
    /// different path from an app-declared command. What is corrected is the inference drawn from
    /// it — that a sheet makes the menu bar inert.
    var reportMayBeRaisedFromMenu: Bool { !runIsActive && pendingPrompt == nil }

    /// The menu asked for the report. **Raises it only if that is allowed.**
    ///
    /// The rule is enforced here rather than only advertised by the menu item's `.disabled`, for
    /// the reason mutation R12 measured: nothing automated can see a view modifier, so a rule that
    /// lives only in one is a rule that can be deleted silently. The item is greyed *and* the raise
    /// refuses.
    ///
    /// The refusal is silent, which is normally this app's defect rather than its behaviour — but
    /// the control offering the command is disabled in exactly the same states, so a user cannot
    /// reach this. It is a backstop for a route nobody enumerated, not the answer to a press.
    ///
    /// - Note: ``runProduced(_:)`` deliberately does **not** consult this. See the note above.
    func reportRequestedFromMenu() {
        guard reportMayBeRaisedFromMenu else { return }
        reportIsPresented = true
    }

    /// A failure the user has to be told about — a drive that could not be prepared, or a run
    /// control that never reached the daemon. `nil` when there is nothing to say.
    ///
    /// **Failures interrupt; a successful unmount reports nothing** (user decision 2026-08-09,
    /// `OutcomePresentation`). Held here rather than in the view's `@State` because the thing that
    /// produces it is `RunController`, and a closure cannot write a `View` struct's state.
    var runFailure: RunFailureMessage?

    /// FR-FAIL-1's mode for the next run, chosen before it starts. FR-FAIL-4's default.
    ///
    /// The control that sets it is the main window's pre-run controls (increment 6), beside the
    /// I/O-size dropdown, where FR-CTRL-7 wants it. It lived in the diagnostics window from Step 10
    /// until then, as scaffolding — there was no Start control to put it beside. **The value never
    /// moved**, which is what made the relocation a view change rather than a state change.
    var failureMode: FailureModeCode = .standard

    /// FR-CTRL-8's I/O size for the next run. Always one of `TesterProtocol.permittedIOSizes`.
    ///
    /// **Stored here and written through to the store**, for the reason ``warningsSuppressed``
    /// gives at length: `@Observable` tracks stored properties, and a computed property reading a
    /// plain object would leave SwiftUI with nothing to observe — a correct value nobody can see,
    /// which is the defect this step has already paid for twice. The two cannot drift because this
    /// is the only writer and it writes through on every set.
    ///
    /// **Nothing enforces here that a run is not under way**, deliberately. That decision is
    /// `IOSizeSelection`'s table and the control is what consults it; a second copy of the rule on
    /// the property would be two statements of one fact — and the property is also what a
    /// *confirmed* change writes, after the run it ended. A guard here would refuse that write.
    var ioSizeBytes: Int {
        didSet { ioSizeStore.ioSizeBytes = ioSizeBytes }
    }

    /// Whether anything is happening that must freeze the device list (FR-DEV-7), block an
    /// uninstall (NFR-INST-3) and make a quit ask first.
    ///
    /// One source, where there were three. `false` before the main window exists, which is correct:
    /// nothing can be running.
    var runIsActive: Bool { runControl?.isRunActive ?? false }

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
    /// stop-at-the-boundary promise, and this is where it is kept — `RunSequencer` consults it
    /// before every call it issues.
    var mayIssueNewWork: Bool { quitState == .idle }

    /// Whether a run **already in flight** may issue its next call.
    ///
    /// **Not the same question as ``mayIssueNewWork``, and conflating them killed runs.** That one
    /// is false from the moment a quit is *pending* — correctly, because Start must be refused
    /// while the confirmation is up. This one is false only once the user has actually **chosen**
    /// to quit.
    ///
    /// Found by the human checklist on 2026-08-18: pressing ⌘Q during a run presented the
    /// confirmation and *simultaneously ended the run*, showing the report before any button was
    /// touched. `RunSequencer` consults its precondition before every call, `.confirming` made it
    /// false, and so merely **asking** the question answered it. "Continue Testing" was offering
    /// to resume something already dead.
    ///
    /// Nothing is weakened by letting the run continue through `.confirming`: a call is bounded,
    /// so the most a pending quit can wait is one call, and `cancelAndQuit()` does the real work
    /// with an explicit `stop()` that settles at a chunk boundary. The halt was never what kept
    /// that promise.
    var mayContinueRun: Bool {
        switch quitState {
        case .idle, .confirming: return true
        case .windingDown, .terminating: return false
        }
    }

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

    /// The main window has closed and the app should now go (user decision 2026-08-06).
    ///
    /// Called by `MainWindowCloseGuard` **one run-loop turn after** it allowed the close, so the
    /// window is actually gone by the time this runs.
    ///
    /// It **requests** a termination rather than performing one: `terminateAction` is
    /// `NSApp.terminate(_:)`, which lands in `applicationShouldTerminate` and picks up the same
    /// guard ⌘Q does. That routing is the point. `QuitPolicy` only produces
    /// ``WindowCloseDisposition/allowCloseAndQuit`` from the idle state, so the guard will allow
    /// it today — but a run started in the window between the close and this call, or a later
    /// change to that table, cannot turn closing a window into an abandoned run.
    func quitBecauseTheMainWindowClosed() {
        terminateAction()
    }

    /// "Continue Testing" — the run goes on and the app stays.
    func continueTesting() {
        if quitState == .confirming { quitState = .idle }
    }

    /// "Cancel and Quit" — issue nothing further, then quit at the call boundary.
    ///
    /// ## A quit issues a STOP (recorded default, 2026-08-12)
    ///
    /// Rather than waiting for the in-flight call to end by itself. That makes the existing promise
    /// **stronger**, not weaker — the wait shortens from one bounded call to one chunk — and it is
    /// what stops a **paused** run leaving the wind-down waiting for ever: a paused run has nothing
    /// in flight and no reply coming, so there is no boundary to wait for.
    func cancelAndQuit() {
        guard quitState == .confirming || quitState == .idle else { return }
        quitState = .windingDown

        if let runControl, runControl.isRunActive {
            // Refused while the drive is still being *prepared*, and that is fine rather than a
            // gap: `mayIssueNewWork` is already false, and `RunSequencer` consults it before every
            // call including the first — so a run that reaches `running` halts immediately and
            // settles by the ordinary path.
            runControl.stop()
            return
        }

        // The boundary may already have passed — a run takes as long as it takes and a dialog can
        // sit unanswered for longer. Without this the app would wait for a transition that had
        // already happened, and quitting would appear to do nothing at all.
        beginRelease()
    }

    /// The run has come to rest and the drive is released. Called by ``RunController``.
    ///
    /// **This is the call boundary**, and it replaces `cycleIsRunning` going false. It fires on
    /// every route out of a run — completed, stopped, failed, or a Start that aborted before any
    /// write — so there is no path on which a wind-down waits for something that will not come.
    func runSettled() {
        guard quitState == .windingDown else { return }
        beginRelease()
    }

    /// Terminate, once. See `QuitSequence` for the once-only and no-hang properties.
    private func beginRelease() {
        guard quitSequence == nil else { return }

        // **Nothing to release here any more.** Before increment 5 the app could hold a claim with
        // no run — `Acquire exclusive access` was a button — so the wind-down had to release it.
        // Now the claim's lifetime is exactly the run's and `RunController` releases it before it
        // reports settling, so by the time this runs there is nothing left to give back.
        let sequence = QuitSequence(release: nil) { [weak self] in
            guard let self else { return }
            // Recorded *before* terminating: the second `applicationShouldTerminate` this triggers
            // has to be able to tell the app's own quit from a user pressing ⌘Q again.
            self.quitState = .terminating
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
