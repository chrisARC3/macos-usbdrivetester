//
//  RunControlsView.swift
//  USBDriveTester (app target — unprivileged)
//
//  Step 11, increments 5 and 6. The run controls, the pre-run gate they raise, and — from
//  increment 6 — the two pre-run controls above them (FR-CTRL-7/8).
//
//  ## What increment 6 brought in
//
//  The **I/O-size dropdown**, which had never existed anywhere: the size was hardcoded at the
//  wiring seam, because until increment 4 nothing app-side chose one. And the **failure-mode
//  picker**, relocated from the diagnostics window where Step 10 parked it as scaffolding for want
//  of a Start control to put it beside.
//
//  When they are live is `PreRunControls.swift`'s decision, and it is **one rule for both**: chosen
//  before a run, fixed for the whole of it, `paused` included.
//
//  This increment first built the other shape — the size live while paused, changing it ending the
//  run behind a confirmation, per FR-CTRL-8 as it read from 2026-08-04. Seen on hardware, paused,
//  two adjacent controls with different rules read as one of them being broken, and the requirement
//  was reversed (user decision 2026-08-19). The confirmation alert went with it: with the control
//  dead for the whole run, no change here can end anything, and *nothing untriggerable is built*.
//
//  ## Pinned outside every scroll region, and that is a bug fix rather than a layout choice
//
//  This is the **fourth** time a control on this screen has had to be placed with that in mind. A
//  control below the fold in a scroll region that does not advertise itself as scrollable has cost
//  this project three times already: Step 10 lost two of five rounds to it, `OutcomePresentation`
//  exists because an error message did it, and on 2026-08-11 `Acquire exclusive access` was
//  entirely off-screen at the app's own `minHeight`, presenting as *"Run one bounded cycle stays
//  disabled no matter what I do."*
//
//  **Raising a constant is not the fix.** The block above these controls grows with the selected
//  drive's mounted-volume count, so any fixed height is a threshold some drive crosses. These
//  controls live in `ContentView`, which has no `ScrollView` at all — so "outside the scroll
//  region" holds by construction rather than by a measured number that expires silently when the
//  content above it changes.
//
//  ## Every control's state comes from the policy
//
//  Nothing here decides whether a command is legal. `RunControlPolicy.controls` derives the buttons
//  from the same table that answers the commands, so a control can never be offered for something
//  the table would refuse — and a refusal's wording is the same whether it is logged or shown after
//  a command is issued anyway.
//
//  ## The refusal sentences under the buttons are gone (user decision, 2026-08-22)
//
//  This view printed every disabled control's reason, under the rule *"dimming is not a message"*.
//  That rule came from a **Step 4 defect**: two dimmed buttons were reported as *missing entirely*.
//  It was right when nothing else on screen said anything.
//
//  **By increment 8 everything those sentences said was said elsewhere**, and the sentences were
//  checked one by one against the screen before they were deleted rather than judged as a group:
//
//    * the four transient states — starting, pausing, stopping, finishing — refuse for
//      reasons that *are* the state, and `statusDescription` is a sentence naming it directly above;
//    * *"Select a drive to test. A drive whose geometry this tool cannot read cannot be tested"* is
//      the empty list, or the drive list's **Unusable** badge;
//    * *"The app has been asked to quit"* is the confirmation alert, or the winding-down banner.
//
//  **No mandatory requirement asked for them.** FR-SAFE-4 is about a run that cannot *start* —
//  mounted volumes, a claimed device node — and that is served by the failure alert. NFR-USE-5 is
//  about error messages. NFR-USE-8's absolute is about pass/fail by colour, which the report obeys.
//
//  What this costs, stated rather than discovered later: **the Unusable badge is now the only thing
//  explaining a dim Start for a drive that cannot be read.** It was belt-and-braces; it is not now.
//
//  It also deletes the collapse machinery — the four-sentences-in-one-state defect, the 40 pt-per-
//  sentence measurements, `statesTheStatusLineExplains`, and both human-checklist items that
//  counted sentences (9.7 and 10.5). A block that does not exist cannot print one thing four ways.
//
//  ## There is no Restart button, and there was one for a day (user decision, 2026-08-22)
//
//  Increment 8 built it in full — a fourth button, a ninth state, a confirmation carrying the
//  discard warning, and a release-and-re-acquire so the new run's accumulators were its own. It was
//  walked at the keyboard, passed all seven of its checklist items, and was then removed, because
//  **Stop then Start reaches the same end state** and a second route to one outcome is complexity
//  without capability. FR-CTRL-5 is still met, by composition; the requirements document carries an
//  amendment of the same date saying so.
//

import SwiftUI

struct RunControlsView: View {

    @Environment(AppModel.self) private var model

    /// The suppression checkbox's state **while the dialog is open**.
    ///
    /// Deliberately *not* bound to `model.warningsSuppressed`. Binding the checkbox straight to the
    /// persisted value would record the preference the instant it was ticked — including for a user
    /// who then presses **Cancel**, which `PreRunWarningPolicy.outcome` exists to prevent: the
    /// preference is recorded only by a run that actually starts. Reset every time the dialog is
    /// raised.
    @State private var suppressionRequested = false

    private var controls: RunControls? { model.runControl?.controls }

    private var state: RunControlState { model.runControl?.state ?? .idle }

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                // Decorative section marker, not a status — hidden so it is not read as one.
                Image(systemName: "play.circle")
                    .accessibilityHidden(true)
                Text("Run")
                    .font(.headline)
                Spacer()
                statusLabel
            }

            preRunControls

            HStack(spacing: 10) {
                Button("Start") { startPressed() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!(controls?.start.isEnabled ?? false))

                if let pause = controls?.pause {
                    Button(pause.label) { pausePressed(pause.command) }
                        .disabled(!pause.isEnabled)
                }

                Button("Stop") { model.runControl?.stop() }
                    .disabled(!(controls?.stop.isEnabled ?? false))

                Spacer()
            }
        }
        // FR-WARN-1/2/3 and NFR-USE-4. A sheet rather than an `alert` because decision 5 puts a
        // `Toggle` in it, which an alert cannot hold. `item:` rather than `isPresented:` so the
        // prompt and its presentation are one value — two would be a state pair that can disagree.
        //
        // ## The sheet is modal to the window, and that GATES QUITTING (user decision 2026-08-18)
        //
        // Observed on hardware: while this sheet is up, **neither ⌘Q nor File ▸ Quit does
        // anything**. The sheet intercepts them before `applicationShouldTerminate` is reached, so
        // `QuitPolicy.disposition` — which would answer `.quitImmediately`, there being no run
        // active — is never consulted at all. The user must answer or Cancel first.
        //
        // **This is wanted, and is not to be "fixed".** The sheet is the last thing standing
        // between a selected drive and a write; making it dismissable by a keystroke that means
        // something else would be the wrong direction. Cancel is one click away, and nothing is
        // claimed while the sheet is up, so nothing can be stranded by refusing the quit.
        //
        // Worth knowing that no test can see this: `AppModelQuitTests` exercises the policy, and
        // the policy is not the thing deciding. It is the same blind spot that hid the paused
        // panel — presentation-layer behaviour that the model tests cannot reach — and it is why
        // the human checklist covers it.
        //
        // ## WHAT THIS DOES **NOT** MEAN, measured 2026-08-21
        //
        // The paragraph above is about ⌘Q, and the inference drawn from it — that this sheet makes
        // the menu bar inert — is **wrong**. Chunk 11.11 pressed ⇧⌘R with this dialog open: the
        // app's own menu command **ran**, and because SwiftUI cannot present a second sheet on one
        // window it queued the report and presented it the instant this dialog was cancelled. ⌘Q is
        // AppKit's terminate and takes a different path from an app-declared command; only that
        // path is intercepted. `AppModel.reportMayBeRaisedFromMenu` is where the consequence lives.
        // **The dialog's state is `AppModel.pendingPrompt`, not this view's** (2026-08-21). It was
        // `@State` here until chunk 11.11 pressed ⇧⌘R with this sheet open: the menu item lives in
        // the scene's `commands` builder, which has no environment and could not see a view's
        // state, so it raised a second sheet that SwiftUI queued and then presented the moment this
        // one was cancelled. Whether a modal is up is a fact about the window.
        .sheet(item: $model.pendingPrompt) { prompt in
            PreRunPromptSheet(prompt: prompt,
                              suppressFutureWarnings: $suppressionRequested,
                              onProceed: { promptDismissed(.proceed) },
                              onCancel: { promptDismissed(.cancel) })
        }
        // **Failures interrupt** (user decision 2026-08-09, `OutcomePresentation`'s rule). This
        // alert moved here from `DeviceListView` with the sequence it reports on: an alert attached
        // to a deleted view is an error path with nowhere to surface. The message it replaced was
        // correct and never seen — the last element inside a `ScrollView`, below the fold on a
        // drive with several mounted volumes.
        .alert(model.runFailure?.title ?? "",
               isPresented: Binding(get: { model.runFailure != nil },
                                    set: { presented in if !presented { model.runFailure = nil } }),
               presenting: model.runFailure) { _ in
            Button("OK", role: .cancel) { }
        } message: { failure in
            Text(failure.text)
        }
    }

    // MARK: - The pre-run controls (FR-CTRL-7/8)

    /// The I/O size and the failure mode, chosen before a run and fixed for the whole of it.
    ///
    /// Above Start rather than below it: these are what Start acts *with*, and a user reads down.
    /// They are inside this view — and therefore inside `ContentView`, which has no `ScrollView` at
    /// all — so "not below the fold" holds by construction. That is the fourth control on this
    /// screen placed with that in mind and it is a bug fix, not a preference; see this file's header.
    ///
    /// **One availability for both**, and therefore one sentence when they are dead. An earlier
    /// version of this increment gave them different rules — the size live while paused, the mode
    /// not — and rendered a reason for each. Seen on real hardware, paused, that read as one
    /// control being broken rather than as two requirements differing (user decision 2026-08-19).
    @ViewBuilder
    private var preRunControls: some View {
        @Bindable var model = model

        let availability = PreRunControls.availability(in: state)

        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("I/O size")
                    .frame(minWidth: 110, alignment: .leading)
                // Not bound to `model.ioSizeBytes` directly: the setter consults the policy, so a
                // change issued while a run is under way is refused and logged rather than written.
                // The `get` still reads the model, so the control always shows the truth.
                Picker("I/O size", selection: ioSizeBinding) {
                    ForEach(TesterProtocol.permittedIOSizes, id: \.self) { size in
                        Text(IOSizeSelection.label(size)).tag(size)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
                .disabled(!availability.isEnabled)
            }
            GridRow {
                Text("On failure")
                    .frame(minWidth: 110, alignment: .leading)
                // FR-FAIL-1, relocated from the diagnostics window in this increment. The value
                // never moved — it has been `AppModel.failureMode` since Step 10 — which is what
                // made this a view change rather than a state change.
                Picker("On failure", selection: $model.failureMode) {
                    Text("Log and continue").tag(FailureModeCode.logAndContinue)
                    Text("Stop on first error").tag(FailureModeCode.stopOnFirstError)
                }
                .labelsHidden()
                .frame(width: 200)
                .disabled(!availability.isEnabled)
                .onChange(of: model.failureMode) { _, mode in RunReportLog.modeSelected(mode) }
            }
        }

        // The consequence of the selected mode. This line is why the control is worth rendering at
        // all: what changes between the two selections is not which item is chosen, it is that
        // everything past the first failure is left **untested**, which is not the same as passed.
        //
        // **Both branches cut to one line in increment 7** (user, 2026-08-19). They carried the
        // wording from the diagnostics window, where the panel had a window to itself and height
        // was free; here each wrapped line costs 15 pt of the main window's minimum, and a
        // 13.3-inch Mac at its smallest scaling has none to give. Trimming them also made the two
        // branches cost the **same** height, which matters more than the 15 pt: until then the
        // window had to reserve room for whichever caption was taller, so choosing a failure mode
        // silently moved the minimum window size.
        //
        // The stop-on-error branch lost its trailing gloss, *"which is not the same as passed"*.
        // The other was rewritten rather than trimmed: it used to end *"and the rest of the drive
        // is still refreshed"*, which stated the contrast with the other branch outright. Saying
        // the run **continues** implies it, and what a user can still do about it is answered by
        // the Pause and Stop buttons directly below — a caption that lists the controls under it
        // is describing the screen rather than the choice.
        //
        // *Untested is not the same as passed* is not lost with it: it is `HonestFraming`'s, it is
        // in the **report**, and it is asserted there by `RunReportTests`. That is the surface
        // where the distinction has to survive being read months later — a picker's caption is
        // read once, at the moment of choosing, with the choice itself right beside it.
        Text(model.failureMode == .stopOnFirstError
             ? """
               The run halts at the first failed block range. **Everything past it is left \
               untested**.
               """
             : """
               Every failed block range is recorded while the test continues to run.
               """)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        // One sentence for both controls, because there is one rule — printing it twice would be
        // the "saying the same thing several times" shape that cost the run controls 120 pt of
        // height before their equivalent block was deleted outright (user decision, 2026-08-22).
        //
        // **This line stays, and the distinction is the reason.** Why a *setting* is frozen is not
        // the same fact as what the run is doing, and nothing else on screen carries it — where
        // every sentence the run controls used to print was a restatement of the status line
        // above them, the drive list's Unusable badge, or the quit banner.
        if let reason = availability.disabledReason {
            Label(reason, systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The dropdown's binding. **Reads the model, and writes only what the policy allows.**
    private var ioSizeBinding: Binding<Int> {
        Binding(get: { model.ioSizeBytes },
                set: { requested in ioSizeRequested(requested) })
    }

    /// What the run is doing, in words. The two transient states say *why* they are transient —
    /// "Pausing…" on its own reads as a stall, where a user told the drive is finishing a chunk
    /// knows both that it is working and that nothing is being left half-written.
    private var statusLabel: some View {
        let state = model.runControl?.state ?? .idle
        return Label(state.statusDescription, systemImage: symbol(for: state))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(state.statusDescription)
    }

    private func symbol(for state: RunControlState) -> String {
        switch state {
        case .idle:      return "circle"
        case .starting:  return "externaldrive.badge.minus"
        case .running:   return "play.circle.fill"
        case .pausing:   return "pause.circle"
        case .paused:    return "pause.circle.fill"
        case .stopping:  return "stop.circle"
        case .finishing: return "externaldrive.badge.checkmark"
        case .finished:  return "checkmark.circle.fill"
        }
    }

    /// The refusals worth reading, in the order the controls appear.
    ///
    /// ## Dimming is not a message — but neither is saying the same thing four times
    ///
    /// Step 4 had two disabled buttons reported as **missing entirely**, which is why every refusal
    /// in this app names its cause (NFR-USE-8, FR-SAFE-4, NFR-USE-5). Rendering the four run states
    /// showed the other failure mode of that rule: at rest it printed *"There is no run to pause"*
    /// and *"There is no run to stop"* beside a status line already reading **Idle**, and while the
    /// drive was being prepared it printed three sentences that each restated *"Preparing the
    /// drive…"*. Found by looking, not by reasoning.
    ///
    /// **Start's refusal is always shown**, and exactly one thing is suppressed: Pause's and Stop's
    /// *"there is no run to pause"* when no run is active, which is precisely what the status line
    /// and a live Start button already say between them.
    ///
    /// ## The narrower rule is what a render forced, after a wider one hid the wrong thing
    ///
    /// The first attempt also suppressed everything when *no* control was enabled, on the reasoning
    /// that the status line must then be the whole explanation. Rendering `content-quit-pending`
    /// refuted it: with a run finished and a quit pending, **Start was disabled with nothing on
    /// screen saying why** — the status line read "Finished", which explains nothing about Start —
    /// and that is the Step 4 defect this rule exists to prevent, reintroduced by the rule itself.
    ///
    /// The lesson is the project's own: a plausible rule about what is self-evident is not evidence
    /// of what a screen actually says. Start is the actionable control and its refusal is never
    /// self-evident; Pause's and Stop's, at rest, always are.
    // MARK: - Actions

    /// **This is the only thing pressing Start does**: it raises the dialog. Nothing is unmounted
    /// and nothing is claimed until the dialog is answered.
    private func startPressed() {
        guard let runControl = model.runControl else { return }

        // Reset before every raise: a checkbox that remembered a previous dialog's tick would
        // record a preference the user expressed about a run they then cancelled.
        suppressionRequested = false

        switch runControl.startRequested(warningsSuppressed: model.warningsSuppressed) {
        case .prompt(let prompt):
            model.pendingPrompt = prompt
        case .refused(let reason):
            // Reached only by a caller that issued the command without consulting the control that
            // would have offered it. Shown rather than swallowed: a button that does nothing is the
            // defect this app has been reported for twice.
            model.runFailure = RunFailureMessage(title: "The run could not start", text: reason)
        }
    }

    /// The dialog was dismissed. Everything that follows is decided by `PreRunWarningPolicy`, not
    /// here — this applies the decision and records it.
    private func promptDismissed(_ button: PreRunButton) {
        let outcome = PreRunWarningPolicy.outcome(button: button,
                                                  suppressionRequested: suppressionRequested,
                                                  mayIssueNewWork: model.mayIssueNewWork)
        PreRunWarningLog.dismissed(button, outcome: outcome)

        if outcome.persistsSuppression { model.warningsSuppressed = true }

        // Read before the sheet is dismissed — `pendingPrompt` is what carries the purpose, and
        model.pendingPrompt = nil

        // The gate, relocated rather than re-implemented. `startAuthorised(by:)` takes the outcome
        // as proof the gate ran and re-checks it, so wiring a run straight to a press would mean
        // fabricating an acknowledgement that never happened — a deliberate act visible in a diff
        // rather than a one-word edit.
        model.runControl?.startAuthorised(by: outcome)
    }

    /// The dropdown was changed. Whether that is allowed is ``PreRunControls``' decision, not this
    /// view's — the control is dimmed with the same sentence, so a change arriving here while a run
    /// is under way came from a caller that did not consult it (a menu item, a keyboard shortcut).
    ///
    /// **No confirmation, because there is nothing to confirm.** The controls are dead for the
    /// whole of a run, `paused` included (user decision 2026-08-19), so no change here can end a
    /// run or discard a measurement. Changing the size mid-run is Stop → change → Start, and the
    /// Stop is the deliberate act.
    private func ioSizeRequested(_ requested: Int) {
        let availability = PreRunControls.availability(in: state)
        guard availability.isEnabled else {
            IOSizeLog.changeRefused(availability.disabledReason ?? "a run is in progress")
            return
        }
        let previous = model.ioSizeBytes
        model.ioSizeBytes = requested
        IOSizeLog.changed(from: previous, to: requested)
    }

    private func pausePressed(_ command: RunCommand) {
        switch command {
        case .pause:  model.runControl?.pause()
        case .resume: model.runControl?.resume()
        case .start, .stop:
            // `RunControlPolicy.controls` only ever puts `.pause` or `.resume` on this control, and
            // deriving both label and action from one value is what keeps them in step. Logged
            // rather than silently ignored: reaching here is a wiring defect announcing itself.
            RunControlLog.unexpectedPauseCommand(command)
        }
    }
}
