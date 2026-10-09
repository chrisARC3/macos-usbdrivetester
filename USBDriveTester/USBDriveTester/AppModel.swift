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
import os
// `MemberImportVisibility` is on, so `SMAppService.Status.enabled` needs its defining module
// imported *directly* even though `HelperRegistration` already brings it in transitively.
import ServiceManagement
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

    /// **The** `SMAppService` lifecycle of the privileged daemon (FR-ARCH-3, NFR-INST-1/3).
    ///
    /// Owned here from increment 9, and for the same reason ``helper`` is: there must be exactly
    /// one. It was `@State private var registration = HelperRegistration()` inside
    /// `HelperDiagnosticsView` until the launch gate needed `register()` too, and a second instance
    /// would be **two registration states that can disagree** — which is precisely what
    /// `USBDriveTesterApp` warns about when it explains why the diagnostics panel is a `Window` and
    /// not a `WindowGroup`, and precisely what `helperHoldsDevice` was deleted rather than fixed
    /// for.
    ///
    /// Constructing it here means every `AppModel()` reads `SMAppService.status` — including the ten
    /// in the test target and the two in `tools/ui-probe`. That is a **read** of machine state and
    /// changes nothing, unlike the preference stores beside it, which is why this is a plain
    /// property and not a thirteenth injected dependency. The probe already constructed one of these
    /// for its three `diagnostics*` renders before this moved.
    let registration = HelperRegistration()

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

        // **Route (b) of device-loss detection** (Step 12, FR-DEV-8): DiskArbitration names the
        // disk that left, discovery forwards it, and the run controller decides whether it was the
        // drive under test.
        //
        // Wired here rather than where `runControl` is built, and the optional chain is why:
        // discovery starts with the app and the controller does not exist until the main window
        // appears. Read through `self` on every event, so the closure finds whatever controller is
        // current — a closure that had *captured* one would be the "captured what the view was
        // built with" defect that headed every first-run report "Unidentified drive".
        //
        // `runControl` being nil is not a gap: no run can be in flight before the UI that starts
        // one exists, which is the same argument `runControl`'s own documentation already rests on.
        discovery.onDiskDisappeared = { [weak self] disk in
            self?.runControl?.deviceDisappeared(disk)
        }
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

    /// The drive under test left the machine and the run has come to rest: **re-run the initial
    /// device discovery routine** (FR-DEV-8, Step 12 chunk 6).
    ///
    /// The requirement asks for this in the same sentence as terminating the run and showing an
    /// error, and it is the practical half of the three: the drive that left is still in the list,
    /// because FR-DEV-7 freezes the list for the duration of a run and the run only just ended.
    /// Without this the user is looking at a row for a drive that is not attached, and the app's
    /// own selection still points at it.
    ///
    /// **`refresh(reason:)` bypasses the freeze, and that is correct exactly here.** Its own
    /// documentation says so and says why the GUI's Refresh button was removed in 2026-08-05 —
    /// a button offering this during a run is the one thing FR-DEV-7 exists to prevent. A
    /// deliberate recovery step after a run has ended is the other thing entirely. By the time
    /// `RunController` calls this the claim is given up and the run is settling, so the freeze has
    /// nothing left to protect.
    ///
    /// Reconnecting the drive repopulates the list by itself, through IOKit's arrival
    /// notification — that path is not this one and needs nothing from here.
    func deviceUnderTestWasLost() {
        discovery.refresh(reason: "device loss (FR-DEV-8)")
    }

    /// Whether the **View Last Run Report** menu item may raise the report (⇧⌘R).
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
    ///
    /// **And on 2026-08-27 the rest of 6.1 was explained, having sat here for two increments with
    /// the wrong cause attached.** ⌘Q did not merely "reach a different path": `NSApp.terminate(_:)`
    /// is a **silent no-op while a sheet is attached**, measured on an AppKit probe — AppKit refuses
    /// the termination *before* `applicationShouldTerminate` is consulted, so `QuitPolicy` is never
    /// asked at all. 6.1 saw the symptom and this file recorded a guess beside it.
    ///
    /// It failed safe — a run was never abandoned — but silently, and it was **not confined to the
    /// pre-run dialog**: ⌘Q was dead under the report sheet and the launch gate too, and under the
    /// two `.alert`s as well, since a SwiftUI alert on macOS is a window-modal sheet like any other.
    /// Increment 9 fixed only the gate's own Quit button, locally.
    ///
    /// **Fixed app-wide in increment 12 (2026-09-04), and the AppKit fact is unchanged.**
    /// `NSApp.terminate(_:)` is still refused before the delegate while a sheet is attached; what
    /// changed is that the app now declares its **own** Quit command, which does run under a sheet,
    /// and that command asks `QuitPolicy.disposition(underModals:)` per surface. The report and the
    /// launch gate are discarded and the app goes; the pre-run prompt, the failure alert and the
    /// quit confirmation are refused **visibly**, with the menu item greyed. Blunt "end every sheet
    /// then quit" was rejected for the reason 2026-08-27 gave: it dismisses prompts nobody answered.
    ///
    /// ## And while the launch gate is up (increment 9)
    ///
    /// The third condition, and it is the same defect in a new place rather than a new one. At
    /// launch `runIsActive` is false and `pendingPrompt` is nil, so this item is **enabled** — and
    /// the helper gate does not swallow menu commands any more than the pre-run dialog does. ⇧⌘R
    /// under the gate would queue the empty report and present it by itself the moment the gate was
    /// answered: a modal arriving at a time nobody asked for it, which is exactly what chunk 11.11
    /// found on 2026-08-22.
    ///
    /// **This clause is owed whether the gate is a sheet or an alert.** Both are window-modal, and
    /// what 11.11 established is about menu commands, not about which kind of modal is up.
    var reportMayBeRaisedFromMenu: Bool {
        !runIsActive && pendingPrompt == nil && helperAvailability.isAvailable
    }

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

    // MARK: - The launch-time helper gate (increment 9)

    /// Whether the privileged helper can be used at all (NFR-INST-1, NFR-MAINT-1).
    ///
    /// **Starts ``HelperAvailability/available`` and is written only when an answer exists**, so a
    /// healthy launch never flashes a modal while the handshake is in flight. See
    /// `HelperAvailability.diagnose(status:version:)` for why that is the honest default rather
    /// than an optimistic one.
    private(set) var helperAvailability: HelperAvailability = .available

    /// Diagnose the helper and raise or clear the gate.
    ///
    /// Called **from the scene's `onAppear`**, by ``performHelperGateAction(_:)``, and on every
    /// activation **while the gate is up** (`USBDriveTesterApp.swift`). Nothing re-diagnoses on a
    /// timer, or on activation while the gate is down, deliberately: `checkProtocolVersion` goes
    /// out on the *owning* connection, which is blocked for the whole of a run (the D1 measurement
    /// of 2026-08-04), so a re-check that could fire mid-run would queue behind the very call it
    /// interrupted. `HelperAvailability`'s header states the property that follows — no run can be
    /// in flight while the gate is up.
    ///
    /// The status is captured rather than re-read in the completion, so the reply is paired with
    /// the status it was asked about. Re-reading would let a status that changed mid-flight be
    /// paired with an answer about the previous one.
    ///
    /// Not guarded against a second call while one is in flight. Two Retries produce two checks,
    /// both of which write the same answer — a guard would be a mechanism with nothing to prevent.
    func refreshHelperAvailability() {
        registration.refresh()
        let status = registration.status

        guard status == .enabled else {
            setHelperAvailability(.diagnose(status: status, version: nil))
            return
        }

        helper.checkProtocolVersion { [weak self] result in
            self?.setHelperAvailability(.diagnose(status: status, version: result))
        }
    }

    /// A button on the gate was pressed.
    ///
    /// An exhaustive `switch`, which is the point of `HelperGateAction` being a value: a case added
    /// there is a compile error here rather than a button that silently does nothing. Every remedy
    /// re-diagnoses, so the modal is a function of state and walks the user forward one step at a
    /// time — `notRegistered` → Register → `requiresApproval` → Open Login Items → `available`.
    func performHelperGateAction(_ action: HelperGateAction) {
        HelperGateLog.actionTaken(action, from: helperAvailability)

        // **Every remedy is asynchronous**, even the ones that look instant: all four end in
        // `refreshHelperAvailability()`, whose answer arrives in an XPC completion. `registerHelper`
        // from `versionMismatch` is the slow one — measured at 719 ms end to end on 2026-09-01, with
        // a removal, a refused registration and a retry inside it. Marked in flight here and cleared
        // in `setHelperAvailability(_:)` when the answer lands, which is the one place a diagnosis
        // can arrive from.
        if action.isRemedy {
            helperGateActionInFlight = action
            helperGateActionStartedAt = Date()
            HelperGateLog.busyBegan(action)
        }

        switch action {
        case .registerHelper:
            // **Drop the connection first.** Only one path reaches here with a connection in
            // existence — `versionMismatch`, where the handshake has already run and the proxy
            // points at the *old* daemon. Registering replaces it, and a stale connection that
            // keeps answering the previous version would make Retry never clear: this project's
            // most expensive recurring trap, and the reason `install-app.sh` prints a
            // `launchctl kickstart` line. On the `notRegistered` path no connection exists and
            // this is a no-op.
            //
            // It is **not** moved into `HelperRegistration.register()`, which would give the
            // diagnostics window's Register button the same behaviour. That button is not disabled
            // during a run (only while `isBusy`), so an unconditional invalidate there would tear
            // down the owning connection and drop a live claim (NFR-REL-5). Here it is safe because
            // the gate is window-modal over the run controls at launch, so no run can exist.
            helper.invalidate()

            switch HelperRegistrationRemedy.forGate(helperAvailability) {
            case .registerOnly:
                registration.register()
                refreshHelperAvailability()

            case .replaceRunningDaemon:
                // **A running daemon cannot be replaced by registering over it** — measured
                // 2026-08-31, chunk 13 item 7: `register() succeeded` and the same pid went on
                // answering the same old protocol version. It has to be removed first.
                //
                // Through `uninstall(using:runIsActive:)` rather than a raw `unregister()`, so this
                // keeps the helper-idle check (NFR-INST-3) and the settle-polling that already
                // exist and are already tested. `runIsActive` is passed honestly even though the
                // gate is window-modal at launch and no run can exist: a remedy that lies about run
                // state to get its way is the shape of defect this project keeps finding.
                //
                // The completion runs on refusal too, so this cannot strand the gate waiting.
                //
                // **The whole two-step lives in `HelperRegistration`**, not spelled out here as
                // `uninstall { register() }`. That is what this was first written as, and it took
                // TWO presses: the register fired the instant the removal settled and was refused
                // with `Operation not permitted`, dropping the gate to `notRegistered`. Retrying
                // until the system accepts it is `SMAppService` knowledge, and it belongs beside the
                // rest of it rather than in a switch case in the model.
                registration.replaceRunningDaemon(using: helper,
                                                  runIsActive: runIsActive) { [weak self] in
                    self?.refreshHelperAvailability()
                }
            }

        case .openLoginItems:
            registration.openLoginItemsSettings()
            // Re-diagnosed on the way out. Since 2026-08-27 the gate also re-checks whenever the
            // app is activated, so returning from System Settings clears it without pressing
            // anything — this line is what makes a press *before* leaving still answer, and what
            // keeps the action's behaviour a property of the model rather than of a scene modifier.
            refreshHelperAvailability()

        case .retry:
            refreshHelperAvailability()

        case .quit:
            // **`NSApp.terminate(_:)` is a silent no-op while a sheet is attached**, so this button
            // was dead — found at the keyboard on 2026-08-27 (chunk 13 item 4), where it was pressed
            // four times without effect while the log recorded all four presses arriving here.
            //
            // Measured on an AppKit probe the same day, rather than reasoned:
            //
            // | sheet attached | `applicationShouldTerminate` | outcome |
            // |---|---|---|
            // | no | **reached** → `.terminateNow` | the app exits |
            // | yes | **never reached** | the app survives |
            //
            // AppKit refuses the termination *before* consulting the delegate, so `QuitPolicy` never
            // gets a vote — the guard is not bypassed, it is never asked. That is an AppKit fact and
            // it still holds; what increment 12 changed is that the app declares its own Quit
            // command, which *does* run under a sheet, so there is now a path a rule can live in.
            //
            // ## Why this was here and not in `terminateAction` — and where it went
            //
            // The same defect killed **⌘Q under every one of this app's five window-modal
            // surfaces**, and fixing it here fixed only this button. That was deliberate (user
            // decision, 2026-08-27): the general fix lands in the app's most safety-critical path,
            // and "end the sheet then quit" is too blunt, because under the pre-run dialog it
            // dismisses a prompt nobody answered. It was scoped as its own increment, and increment
            // 12 built it — as a per-surface rule in `QuitPolicy.disposition(underModals:)` rather
            // than as one blunt call.
            //
            // **This button did not move into that rule, and must not.** It shares only the
            // mechanism, `dismissThenTerminate(_:)`. See ``quitFromGate()`` for why: routing it
            // through the policy would make it refuse whenever a second modal happened to be
            // flagged, on the one screen the user cannot get past.
            //
            // Here it is safe for the reason the `registerHelper` case gives: the gate is
            // window-modal over the run controls at launch, so no run can exist to be abandoned.
            quitFromGate()
        }
    }

    /// Quits from the launch gate. The sheet has to go down first, and the *mechanism* for that is
    /// shared with ⌘Q — see ``dismissThenTerminate(_:)``, which holds the history.
    ///
    /// **What is deliberately NOT shared is the decision.** This button does not consult
    /// `QuitPolicy.disposition(underModals:)`; only the menu item does. The button *is* the
    /// decision, taken by a user who is looking at the gate and has nowhere else to go — and
    /// routing it through the policy would make it refuse the moment a second modal happened to be
    /// flagged, which is the single worst place in this app to reintroduce a Quit that does
    /// nothing.
    private func quitFromGate() {
        dismissThenTerminate(.helperGate)
    }

    /// Store a diagnosis and log the transition. **The only writer of ``helperAvailability``.**
    ///
    /// Logged on **every** transition including the one into `available`, so a launch that raised
    /// nothing is positively recorded rather than merely silent — which is what makes mutation M4
    /// (*the modal is never presented at all*) visible to a person, since no automated harness
    /// compiles the wiring that presents it.
    ///
    /// Internal rather than private so a test can put the model into a gated state without reading
    /// this machine's real `SMAppService` status. Deliberately **not** a settable property: one
    /// writer means the log route cannot be bypassed, which is the whole of M4's cover.
    func setHelperAvailability(_ availability: HelperAvailability) {
        let previous = helperAvailability
        helperAvailability = availability
        // The answer has arrived, whatever it says — so nothing is in flight any more. Cleared here
        // rather than at each remedy's call site so there is exactly one writer, for the reason this
        // method is the single writer of the availability itself.
        if let action = helperGateActionInFlight {
            HelperGateLog.busyEnded(action, after: helperGateActionStartedAt)
        }
        helperGateActionInFlight = nil
        helperGateActionStartedAt = nil
        HelperGateLog.diagnosed(availability, replacing: previous)
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

    /// Move the quit state, and say who moved it. **The only writer of ``quitState``.**
    ///
    /// Same discipline as ``setHelperAvailability(_:)``, for a sharper reason. `quitState` is the
    /// most consequential value in this app — it decides whether a run may issue its next call,
    /// whether Start is refused, whether the confirmation is on screen, and whether the app is on
    /// its way out — and until 2026-09-04 **nothing logged a single one of its transitions**.
    ///
    /// ## What that cost, and why this exists
    ///
    /// Walking checklist 16.5 found the confirmation going from `.confirming` back to `.idle` with
    /// the dialog still on screen: a second ⌘Q was therefore offered rather than greyed, and
    /// re-asked a question already being asked. It did not reproduce, and the log could not say what
    /// had moved the state, because only two things can and **neither said anything**:
    ///
    ///   * ``continueTesting()`` — the *Continue Testing* button. It is `role: .cancel`, so **Return
    ///     and Escape both trigger it** (deliberately: an accidental key keeps the run rather than
    ///     ending it). A stray keypress reaching the alert produces exactly what was seen, and that
    ///     would be the safety design working rather than a defect.
    ///   * the ``quitConfirmationIsPresented`` setter — SwiftUI writing `false` into the binding on
    ///     its own. That *would* be a defect: a quit the user asked for, silently cancelled.
    ///
    /// The two were indistinguishable from outside and indistinguishable on the log. They are not
    /// any more, and that is the whole of what this method buys.
    ///
    /// **The inventory rides along on purpose.** Whether AppKit still had the alert attached at the
    /// instant the state moved is what separates those two causes: a setter write with
    /// `1 sheet(s) [_NSAlertPanel]` still up is SwiftUI cancelling a quit under a visible dialog;
    /// one with `0 sheet(s)` is a dialog that had already gone.
    private func moveQuitState(to next: QuitState, by mover: String) {
        let previous = quitState
        guard previous != next else { return }
        quitState = next

        quitLog.notice("""
                       quit state: \(String(describing: previous), privacy: .public) → \
                       \(String(describing: next), privacy: .public), by \
                       \(mover, privacy: .public); \(AttachedSheets.inventory(), privacy: .public)
                       """)
    }

    /// Live for the length of one wind-down. Held so its callbacks and its deadline survive.
    private var quitSequence: QuitSequence?

    /// What "quit" actually does.
    ///
    /// Injected for two consumers that must not really terminate: the unit tests, and
    /// `tools/ui-probe`, which renders the winding-down banner — a state no render could otherwise
    /// reach, since getting there through the UI means quitting.
    var terminateAction: () -> Void = { NSApp.terminate(nil) } {
        didSet { terminationIsInjected = true }
    }

    /// Whether ``terminateAction`` has been replaced by something that does not terminate.
    ///
    /// **This exists to keep the `error` channel meaning something** (found walking checklist 16.8,
    /// 2026-09-04). ``reportARefusedTermination(after:)`` rests on one premise — *if the app is
    /// still here a turn after `terminateAction()`, the termination was refused* — and that premise
    /// is **false the moment the action is injected**. The unit suite replaces it with a counter and
    /// makes `scheduleOnNextTurn` synchronous, so every quit test reported a refusal that had not
    /// happened: **17 errors per run of `test.sh`, 112 in six hours**, all of them from the test
    /// host, which shares the app's process name because the bundle hosts it.
    ///
    /// That made 16.8 — *scan the log for the errors this path can emit* — unusable: a real one
    /// would have been indistinguishable from the noise around it. An error channel that cries wolf
    /// on every test run is not an instrument.
    ///
    /// **The backstop therefore belongs with the real termination, not with its callers**, which is
    /// what this records. `didSet` does not fire for the property's own default, so the shipping app
    /// leaves it `false` and reports refusals exactly as before; `tools/ui-probe` sets it too, and
    /// should, for the same reason the tests do.
    private var terminationIsInjected = false

    /// Detaches any sheet attached to one of the app's windows, so that a termination is not
    /// silently refused. See the `.quit` case of `performHelperGateAction(_:)` for the measurement.
    ///
    /// **Belt and braces, not the fix.** A sheet SwiftUI owns comes down only when its presentation
    /// state reads `false` — `endSheet(_:)` leaves it attached and the termination still refused,
    /// measured in the shipped app 2026-08-31 — so ``dismissForQuit(_:)`` is what actually takes one
    /// down. This runs beside it because it costs nothing and closes an AppKit session if one is
    /// somehow live.
    ///
    /// Injected for the same two consumers as `terminateAction` — the tests and `tools/ui-probe` —
    /// and so a test can assert that it runs *before* the termination, which is the ordering the
    /// fix depends on.
    var dismissAttachedSheets: () -> Void = { AttachedSheets.endAll() }

    /// Runs a closure on the next run-loop turn. Injected so a test can make it synchronous and
    /// assert the quit sequence in order; SwiftUI needs the turn to act on a state change.
    /// `@MainActor` on both the property and its parameter, deliberately. The obvious spelling —
    /// a plain `() -> Void` handed to `DispatchQueue.main.async(execute:)` — warns that a
    /// non-`Sendable` closure is being passed where a `@Sendable` one is expected, and this project
    /// ships with zero Swift warnings. A `Task { @MainActor in }` needs no `Sendable` promise
    /// because it never leaves the main actor, which is also the only place this may run.
    var scheduleOnNextTurn: @MainActor (@escaping @MainActor () -> Void) -> Void = { work in
        Task { @MainActor in work() }
    }

    /// Set only by the gate's Quit, and never cleared: the app is on its way out.
    private var gateIsDismissedForQuit = false

    /// The gate remedy currently running, or `nil` when the gate is idle.
    ///
    /// Drives the sheet's busy state: remedies disabled, a spinner and a label, Quit still live.
    /// Raised by the user on 2026-09-01 — *"I'm uncomfortable with the application letting the user
    /// perform a new action before the first one is completed"* — and they were right: the remedy is
    /// a multi-step sequence and every button stayed pressable throughout it.
    private(set) var helperGateActionInFlight: HelperGateAction?

    /// When the in-flight remedy started, so the busy window can be reported in milliseconds.
    ///
    /// **The window is too short to judge by eye** — the user watched for the buttons to grey out on
    /// 2026-09-01, saw the progress label appear and could not see the disable, which are drawn by
    /// the *same* evaluation of the *same* view body. A measurement settles what watching cannot.
    private var helperGateActionStartedAt: Date?

    /// Whether the launch gate is on screen.
    ///
    /// **The sheet binds to this rather than to `helperAvailability` directly**, and that is the
    /// whole of what makes Quit work. `NSApp.terminate(_:)` is refused while a sheet is attached,
    /// and the gate's sheet is SwiftUI's: ending it with AppKit's `endSheet(_:)` left it attached
    /// and the termination still refused — measured in the shipped app on 2026-08-31, `1 still
    /// flagged afterwards` with no `terminate requested` line following it. SwiftUI gives the sheet
    /// up when this getter reads `false`, and since the binding's setter is deliberately a no-op,
    /// there is no other way to take it down.
    var helperGateIsPresented: Bool {
        !helperAvailability.isAvailable && !gateIsDismissedForQuit
    }

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
            guard !newValue else { return }
            guard quitState == .confirming else {
                // **An ignored write, logged rather than dropped.** A normal dismissal produces one
                // of these: the button's action moves the state first, and SwiftUI's binding write
                // lands afterwards on a state that has already moved on. What would be interesting
                // is a burst of them, or one arriving with no button pressed at all.
                quitLog.notice("""
                               quit alert: SwiftUI wrote isPresented=false with state=\
                               \(String(describing: self.quitState), privacy: .public) — ignored
                               """)
                return
            }
            moveQuitState(to: .idle, by: "SwiftUI dismissing the alert")
        }
    }

    // MARK: - Quitting from under a modal (increment 12)

    /// Which of the app's window-modal surfaces this model believes are on screen.
    ///
    /// **Derived, never stored.** Each of the five is already a fact this class holds for its own
    /// reasons — ``pendingPrompt`` because a menu command outside the view has to see it,
    /// ``helperGateIsPresented`` because SwiftUI is the only thing that can take that sheet down —
    /// and a sixth stored copy would be five facts free to disagree with the five they mirror.
    /// This reads them; it remembers nothing.
    ///
    /// **It is the model's belief, not AppKit's count**, and the two can honestly differ: SwiftUI
    /// cannot present two sheets on one window and **queues** the second invisibly (measured at the
    /// keyboard 2026-08-21, chunk 11.11). That is why `QuitPolicy.disposition(underModals:)`
    /// refuses outright when more than one is flagged, and why ``quitRequestedFromMenu()`` logs
    /// `AttachedSheets.inventory()` beside this — a disagreement between the two is the reading
    /// worth having.
    var presentedModals: Set<AppModal> {
        var presented: Set<AppModal> = []
        if quitConfirmationIsPresented { presented.insert(.quitConfirmation) }
        if helperGateIsPresented       { presented.insert(.helperGate) }
        if pendingPrompt != nil        { presented.insert(.preRunPrompt) }
        if runFailure != nil           { presented.insert(.runFailure) }
        if reportIsPresented           { presented.insert(.runReport) }
        return presented
    }

    /// Whether the **Quit** menu item is offered at all.
    ///
    /// Greying it is the whole of how a refusal is *shown*. There is nowhere on a menu item to put
    /// prose, and the half of this defect that actually mattered was never "⌘Q is unavailable" —
    /// it was "⌘Q is available and does nothing".
    ///
    /// **The cost is stated rather than hidden: a disabled item runs no action, so ⌘Q under the
    /// pre-run prompt now logs nothing at all.** A reader of the log sees silence there, and this
    /// is where they find out why it is silence by design. What replaces the line is a thing a
    /// person can see without a log, which the line never was.
    ///
    /// **This is not a way to strand the user.** Every state that greys it is a modal with its own
    /// buttons; the Dock icon's Quit is unaffected either way (it calls `NSApp.terminate(_:)`
    /// directly, which no app-declared command can intercept), and under a modal ⌘Q was dead
    /// before this increment regardless.
    var mayQuitFromMenu: Bool {
        if case .refuse = QuitPolicy.disposition(underModals: presentedModals) { return false }
        return true
    }

    /// The app's own **Quit** menu item was chosen — ⌘Q, or Apple menu ▸ Quit (increment 12).
    ///
    /// ## Why this app declares its own Quit at all
    ///
    /// `NSApp.terminate(_:)` is a **silent no-op while a sheet is attached**: AppKit refuses it
    /// *before* `applicationShouldTerminate` is consulted (measured 2026-08-27, the table is in
    /// CONSTRAINTS §1). So under any of this app's window-modal surfaces, ⌘Q runs **no code of this
    /// app's at all** — which means there is no quit path to put a rule in, because the quit path
    /// is never entered. That is the fact the increment plan's *"a rule per sheet"* rests on and
    /// does not state.
    ///
    /// What *does* reach the app under a sheet is an **app-declared menu command**. Measured at the
    /// keyboard on 2026-08-21 (chunk 11.11): ⇧⌘R ran with the pre-run dialog up, and SwiftUI queued
    /// the report behind it rather than swallowing the command. Replacing AppKit's Quit item with
    /// one of the app's own is therefore the only route by which any rule can be consulted — and on
    /// 2026-09-04 chunk 0 measured that the *declared* ⌘Q does fire under a sheet, which is the one
    /// premise the whole design rests on and was not covered by the ⇧⌘R measurement.
    ///
    /// ## What it does
    ///
    /// Asks `QuitPolicy.disposition(underModals:)` and then performs the answer, and nothing more:
    /// the three arms are *request*, *discard one modal then request*, and *refuse and say why*.
    /// **It still takes no vote about the run.** That stays where it was —
    /// `applicationShouldTerminate` asks ``quitRequested()`` — so the during-a-run confirmation is
    /// reached by this route on the same terms as every other. The two tables **compose**: a report
    /// discarded while the run is still `finishing` meets `.askFirst` a turn later, which is why
    /// they are not one table.
    ///
    /// ## The log lines are the instrument, not scaffolding (NFR-OBS-1)
    ///
    /// This path emitted nothing at all until 2026-08-27, which is why chunk 13's dead Quit button
    /// could not be diagnosed from the archive and needed an AppKit probe to explain. The inventory
    /// is logged on **every** press, including the ones that go straight through, because the
    /// interesting reading is the disagreement between what the model flags and what AppKit has
    /// attached — and a line printed only on the interesting presses cannot show you that a press
    /// was ordinary.
    func quitRequestedFromMenu() {
        let presented = presentedModals

        quitLog.notice("""
                       quit command: prompt=\(self.pendingPrompt != nil, privacy: .public) \
                       report=\(self.reportIsPresented, privacy: .public) \
                       gate=\(self.helperGateIsPresented, privacy: .public) \
                       confirming=\(self.quitConfirmationIsPresented, privacy: .public) \
                       failure=\(self.runFailure != nil, privacy: .public); \
                       \(AttachedSheets.inventory(), privacy: .public)
                       """)
        reportAnyModalNothingAccountsFor(given: presented)

        switch QuitPolicy.disposition(underModals: presented) {
        case .requestTermination:
            terminateAction()
            reportARefusedTermination(after: "a press with nothing in the way")

        case .dismiss(let modal):
            quitLog.notice("quit command: discarding the \(modal.loggingName, privacy: .public)")
            dismissThenTerminate(modal)

        case .refuse(let reason):
            quitLog.notice("quit command refused: \(reason, privacy: .public)")
        }
    }

    /// Take one modal down through SwiftUI, then ask for the termination on the following turn.
    ///
    /// **Third attempt at this, and the first two are recorded because they each looked correct.**
    ///
    /// 1. `terminateAction()` alone — dead. `NSApp.terminate(_:)` is refused while a sheet is
    ///    attached, *before* `applicationShouldTerminate` is consulted, so `QuitPolicy` never voted
    ///    and nothing was logged.
    /// 2. `AttachedSheets.endAll()` then `terminateAction()` — still dead. An AppKit probe said this
    ///    worked; the probe was not the app. In the app the log read `1 still flagged afterwards`
    ///    and **no** `terminate requested` line ever followed: `endSheet(_:)` does not take down a
    ///    sheet SwiftUI owns, because SwiftUI's binding still reads `true` and it keeps it.
    ///
    /// So the sheet is taken down **through SwiftUI**, by ``dismissForQuit(_:)`` making that
    /// surface's presentation state read `false`, and the termination is asked for on the following
    /// turn once SwiftUI has acted. `endAll()` stays as well: it is a no-op when nothing is
    /// attached, and it costs nothing to also close an AppKit session if one is somehow live.
    ///
    /// **The ordering is the whole fix**, and swapping the two restores the defect — which is why
    /// the tests assert the order rather than merely that both ran.
    ///
    /// **One turn, and no timer.** The hop exists because SwiftUI acts on a state change between
    /// turns; it is not a wait for a dismissal animation, and nothing here depends on how long one
    /// takes. The increment plan's *"no delay is needed"* bullet predates the 2026-08-31
    /// measurement above and is wrong as written.
    private func dismissThenTerminate(_ modal: AppModal) {
        dismissForQuit(modal)
        dismissAttachedSheets()

        scheduleOnNextTurn { [weak self] in
            guard let self else { return }
            self.terminateAction()
            self.reportARefusedTermination(after: "discarding the \(modal.loggingName)")
        }
    }

    /// Take **this** modal down, through the only thing that can take it down — its own
    /// presentation state.
    ///
    /// **Exhaustive on purpose, and paired with the policy's switch.** A sixth case added to
    /// `AppModal` is a compile error in both, so the two cannot drift into a surface the policy has
    /// an opinion about and nothing knows how to dismiss.
    ///
    /// The three surfaces a quit may not discard are reachable here only from a caller that ignored
    /// the policy, so they log and do nothing. Deliberately **not** a `fatalError`: what this
    /// increment replaces is an app that silently would not quit, and shipping one that dies on the
    /// way out instead would be a poor trade.
    private func dismissForQuit(_ modal: AppModal) {
        switch modal {
        case .helperGate:
            // The *availability* is deliberately left alone: the app is quitting, not becoming
            // healthy, and saying otherwise would be a lie on the way out. Never cleared — this
            // flag means "on the way out", and there is no way back from it.
            gateIsDismissedForQuit = true

        case .runReport:
            reportIsPresented = false

        case .preRunPrompt, .runFailure, .quitConfirmation:
            quitLog.error("""
                          refusing to discard the \(modal.loggingName, privacy: .public) for a \
                          quit: it has to be answered
                          """)
        }
    }

    /// Log a sheet that is attached while the model accounts for **no** modal at all.
    ///
    /// This is the shape of every instance of this defect so far: a surface is added, nothing is
    /// taught to have an opinion about it, and ⌘Q dies under it silently. The five flags are what
    /// the policy reasons about, so a sixth surface nobody added a flag for reads here as "nothing
    /// on screen", gets `.requestTermination`, and is refused by AppKit exactly as before this
    /// increment — with the one difference that this line then says so.
    ///
    /// **Only the *nothing accounted for* case is an error.** A model flagging two while AppKit
    /// shows one is expected rather than wrong — SwiftUI queues the second — and is already legible
    /// in the inventory line beside it.
    private func reportAnyModalNothingAccountsFor(given presented: Set<AppModal>) {
        let attached = AttachedSheets.attachedCount
        guard presented.isEmpty, attached > 0 else { return }

        quitLog.error("""
                      quit command: \(attached, privacy: .public) sheet(s) attached and the model \
                      accounts for none of them — a surface nothing has an opinion about; \
                      \(AttachedSheets.inventory(), privacy: .public)
                      """)
    }

    /// Report a termination that was asked for and did not happen.
    ///
    /// **The absence of this line is the measurement**, which is why it is emitted from a scheduled
    /// closure rather than guarded by a condition: if the app went, nothing runs and
    /// `AppLifecycleDelegate`'s `terminate requested` is the last word instead.
    ///
    /// It tells the two refusals apart, and they are not the same event:
    ///
    ///   * the app's **own** guard voting against it — a run is active, so the confirmation is up
    ///     and a wind-down is being asked about. That is the run-boundary promise working, and it
    ///     is a `notice`;
    ///   * **AppKit** refusing it before the delegate is consulted, with nothing pending to explain
    ///     it. That is this increment's defect, back again, and it is an `error`.
    ///
    /// Chunk 0 could not make that distinction and logged one line for both, which would have read
    /// as a failure on every ordinary quit-during-a-run.
    ///
    /// **`.terminating` is an ERROR, and getting that wrong hid a defect for a walk** (2026-09-04).
    /// The first version discriminated on `quitState == .idle` alone, so the wind-down's own
    /// refused termination — `.terminating`, nothing left to try again — would have been reported
    /// as *"the app's own guard answered it"*. It is the opposite: the app has decided to go and
    /// did not.
    private func reportARefusedTermination(after context: String) {
        // See ``terminationIsInjected``: with a stubbed termination "still running" is the expected
        // outcome, not a refusal, and reporting it drowns the real thing.
        guard !terminationIsInjected else { return }

        scheduleOnNextTurn { [weak self] in
            guard let self else { return }

            // **The inventory is on BOTH branches, and the notice one is the load-bearing copy.**
            // It was on the error branch only until 2026-09-04, and that is what made checklist
            // 16.7 unwalkable: the reading it asks for — what AppKit has attached one turn after
            // the quit confirmation is raised, which is the only measurement of whether a SwiftUI
            // `.alert` is a window-modal sheet at all — arrives on *this* branch, because the
            // app's own guard has just answered `.askFirst`.
            let inventory = AttachedSheets.inventory()

            switch self.quitState {
            case .confirming, .windingDown:
                quitLog.notice("""
                               quit command: still running after \(context, privacy: .public) — \
                               the app's own guard answered it, state=\
                               \(String(describing: self.quitState), privacy: .public); \
                               \(inventory, privacy: .public)
                               """)

            case .idle, .terminating:
                quitLog.error("""
                              quit command: still running after \(context, privacy: .public) — \
                              the termination was refused and nothing will retry it, state=\
                              \(String(describing: self.quitState), privacy: .public); \
                              \(inventory, privacy: .public)
                              """)
            }
        }
    }

    /// The app has been asked to terminate. Returns what the caller should do about it.
    func quitRequested() -> QuitDisposition {
        let disposition = QuitPolicy.disposition(runIsActive: runIsActive, quitState: quitState)
        if disposition == .askFirst { moveQuitState(to: .confirming, by: "a termination request") }
        return disposition
    }

    /// The main window has been asked to close. Returns what the caller should do about it.
    func mainWindowCloseRequested() -> WindowCloseDisposition {
        let disposition = QuitPolicy.closeDisposition(runIsActive: runIsActive,
                                                      quitState: quitState)
        if disposition == .askFirst {
            moveQuitState(to: .confirming, by: "the main window's close button")
        }
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
        if quitState == .confirming { moveQuitState(to: .idle, by: "Continue Testing") }
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
        moveQuitState(to: .windingDown, by: "Cancel and Quit")

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

    /// Take down every modal the model knows about, because the user has already said quit.
    ///
    /// **Deliberately blunter than ⌘Q's dismissal, and the difference is the whole point.**
    /// `QuitPolicy.disposition(underModals:)` refuses three surfaces because a ⌘Q arriving under
    /// one of them may be walking past a question nobody answered. By the time this runs the
    /// question has been asked *and answered*: the user pressed **Cancel and Quit**. User decision,
    /// 2026-09-04 — *"if quitting is enabled, it should abandon whatever it was doing and just
    /// quit."*
    ///
    /// ## What this fixes, found at the keyboard 2026-09-04
    ///
    /// **Cancel and Quit did not quit**, and had not since increment 8. A stopped run raises the
    /// report (`onReport` fires before `releaseTheDrive`, `RunController.swift`), so by the time
    /// the wind-down asked to terminate there was a sheet attached and `NSApp.terminate(_:)` was
    /// refused *before* `applicationShouldTerminate` — the same defect increment 12 fixed for every
    /// other route, on the one route nobody had routed through the fix. Checklist 6.3 passed on
    /// 2026-08-18; the report became a sheet on 2026-08-22. It was never re-walked, and
    /// `QuitSequence` logged nothing, so thirteen days and four increments went by in silence.
    ///
    /// The loop over `allCases` earns its keep by being **exhaustive**: a sixth modal is a compile
    /// error here as well as in `QuitPolicy`, so a new surface cannot silently become a new way for
    /// a confirmed quit to be refused.
    private func discardEveryModalForTheWindDown() {
        for modal in AppModal.allCases {
            switch modal {
            case .runReport:
                // The one that was actually blocking it. Nobody can read a report the app is
                // leaving with — export is its only persistence — so this costs nothing.
                reportIsPresented = false

            case .runFailure:
                // Reachable: a run that *fails* raises this and settles, so a wind-down waiting on
                // the boundary meets it on the way out.
                runFailure = nil

            case .preRunPrompt:
                pendingPrompt = nil

            case .helperGate:
                gateIsDismissedForQuit = true

            case .quitConfirmation:
                // **Not cleared, and this is the one case where clearing would be a defect rather
                // than a courtesy.** The confirmation's presentation *is* ``quitState``, so setting
                // it back would cancel the very quit this is performing. It cannot be on screen
                // anyway: `cancelAndQuit()` left `.confirming` before this could run.
                break
            }
        }

        dismissAttachedSheets()
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
            self.moveQuitState(to: .terminating, by: "the wind-down")

            // **The same shape as ⌘Q's dismiss arm, and for the same reason.** Take the modals down
            // through SwiftUI, then ask for the termination on the following turn once SwiftUI has
            // acted — `endSheet(_:)` cannot do it, measured in the shipped app 2026-08-31. This
            // route was left out of increment 12 and that is what checklist 16.5 caught.
            self.discardEveryModalForTheWindDown()
            self.scheduleOnNextTurn { [weak self] in
                guard let self else { return }
                self.terminateAction()
                self.reportARefusedTermination(after: "the wind-down")
            }
        }
        quitSequence = sequence
        sequence.begin()
    }
}

private nonisolated let quitLog = Logger(subsystem: HelperIdentity.loggingSubsystem,
                                         category: "quit")

/// Ending sheets so a termination can proceed.
///
/// **`isSheet` is not the test for "may I terminate now".** The probe that established this measured
/// `isSheet` still reporting `true` on the window immediately after `endSheet(_:)` returned — and
/// terminating right then worked anyway. What blocks the termination is the live sheet *session* on
/// the parent window, which `endSheet(_:)` closes synchronously; the window being ordered out
/// afterwards is cosmetic. So this ends sheets unconditionally rather than asking first, and no
/// caller should gate on `isSheet`.
enum AttachedSheets {

    /// Ends every sheet currently attached to an app window. A no-op when none is attached, which
    /// is what makes it safe to call from a quit path that does not know whether one is up.
    ///
    /// **Logged in detail, and that is not debug scaffolding** (NFR-OBS-1). The gate's Quit needed
    /// three presses on 2026-08-27 *after* the first fix, and it could not be diagnosed from the
    /// log because this whole path was silent — the same reason the original dead button needed an
    /// AppKit probe to explain. A sheet with no `sheetParent` is ended by nobody, and a count that
    /// does not fall to zero is the difference between "ended it" and "tried to".
    static func endAll() {
        let windows = NSApp.windows
        let sheets = windows.filter(\.isSheet)
        let parentless = sheets.filter { $0.sheetParent == nil }.count

        for sheet in sheets {
            sheet.sheetParent?.endSheet(sheet)
        }

        let remaining = NSApp.windows.filter(\.isSheet).count
        quitLog.notice("""
                       ending sheets: \(windows.count) window(s), \(sheets.count) sheet(s), \
                       \(parentless) with no parent; \(remaining) still flagged afterwards
                       """)
    }

    /// How many sheets are attached to the app's windows right now.
    ///
    /// **AppKit's answer, not the model's.** The two are supposed to agree — the model knows which
    /// modal it raised — and the interesting case is the one where they do not, because a modal
    /// nothing in the model accounts for is a modal that silently kills ⌘Q. That is the whole
    /// history of this defect: five window-modal surfaces, and nothing anywhere counted them.
    static var attachedCount: Int { NSApp.windows.filter(\.isSheet).count }

    /// What is attached right now, as one line for the log.
    ///
    /// Separate from ``endAll()`` on purpose: the quit path has to be able to *report* what it
    /// found on a press that ends nothing, and a description produced only while ending sheets
    /// cannot be read from a path that ends none.
    ///
    /// **The window class names are the point rather than decoration.** A SwiftUI `.alert` on
    /// macOS is presented as a window-modal sheet like any other — which is why this defect covers
    /// **five** surfaces and not the three the increment plan named — and the class name is what
    /// tells one kind from another in a log read at the keyboard.
    static func inventory() -> String {
        let windows = NSApp.windows
        let sheets = windows.filter(\.isSheet)
        let described = sheets.map { sheet in
            "\(type(of: sheet))\(sheet.sheetParent == nil ? " (no parent)" : "")"
        }
        let key = NSApp.keyWindow.map { "\(type(of: $0))" } ?? "none"
        return "\(windows.count) window(s), \(sheets.count) sheet(s)"
            + (described.isEmpty ? "" : " [\(described.joined(separator: ", "))]")
            + "; key=\(key)"
    }
}

/// Identifiers for the app's windows, shared by the scene that declares each one and the controls
/// that open it. A string literal in two places is a typo waiting to silently open nothing.
enum WindowID {
    static let main = "main"
    static let diagnostics = "diagnostics"
}
