//
//  RunControlsView.swift
//  USBDriveTester (app target — unprivileged)
//
//  Step 11, increment 5. The run controls, and the pre-run gate they raise.
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
//  ## Every control's state comes from the policy, and so does every reason
//
//  Nothing here decides whether a command is legal. `RunControlPolicy.controls` derives the buttons
//  from the same table that answers the commands, so a control can never be offered for something
//  the table would refuse — and a refusal's wording is the same whether the user reads it beside a
//  dimmed button or sees it after pressing one. **Dimming is not a message** (NFR-USE-8): every
//  disabled control's reason is rendered, without exception.
//
//  ## Restart is deliberately absent until increment 7
//
//  `RunControlPolicy` offers it from `running` and `paused`, and the machine is ready for it — but
//  FR-CTRL-5 owes two things this increment does not build: a confirmation before discarding hours
//  of work irrecoverably (an interrupted run cannot be resumed, FR-FAIL-7), and raising the pre-run
//  gate again. Shipping the button without them would be worse than not shipping it.
//

import SwiftUI

struct RunControlsView: View {

    @Environment(AppModel.self) private var model

    /// The dialog Start raised, or `nil` when none is up (FR-WARN-1/2/3, NFR-USE-4).
    @State private var pendingPrompt: PreRunPrompt?

    /// The suppression checkbox's state **while the dialog is open**.
    ///
    /// Deliberately *not* bound to `model.warningsSuppressed`. Binding the checkbox straight to the
    /// persisted value would record the preference the instant it was ticked — including for a user
    /// who then presses **Cancel**, which `PreRunWarningPolicy.outcome` exists to prevent: the
    /// preference is recorded only by a run that actually starts. Reset every time the dialog is
    /// raised.
    @State private var suppressionRequested = false

    private var controls: RunControls? { model.runControl?.controls }

    var body: some View {
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

            // **Dimming is not a message.** Every disabled control says why, in the same words the
            // table would give if the command were issued anyway.
            ForEach(disabledReasons, id: \.self) { reason in
                Label(reason, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        .sheet(item: $pendingPrompt) { prompt in
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
    private var disabledReasons: [String] {
        guard let controls, let state = model.runControl?.state else { return [] }

        var candidates = [controls.start.disabledReason]
        if state.isRunActive {
            candidates += [controls.pause.disabledReason, controls.stop.disabledReason]
        }

        // Deduplicated: Start and Stop refuse for the same reason in several states, and printing
        // one sentence twice reads as two different problems.
        var seen: [String] = []
        for reason in candidates.compactMap({ $0 }) where !seen.contains(reason) {
            seen.append(reason)
        }
        return seen
    }

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
            pendingPrompt = prompt
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
        pendingPrompt = nil

        // The gate, relocated rather than re-implemented. `startAuthorised(by:)` takes the outcome
        // as proof the gate ran and re-checks it — so wiring Start straight to a run means
        // fabricating an acknowledgement that never happened, which is a deliberate act visible in
        // a diff rather than a one-word edit.
        model.runControl?.startAuthorised(by: outcome)
    }

    private func pausePressed(_ command: RunCommand) {
        switch command {
        case .pause:  model.runControl?.pause()
        case .resume: model.runControl?.resume()
        case .start, .stop, .restart:
            // `RunControlPolicy.controls` only ever puts `.pause` or `.resume` on this control, and
            // deriving both label and action from one value is what keeps them in step. Logged
            // rather than silently ignored: reaching here is a wiring defect announcing itself.
            RunControlLog.unexpectedPauseCommand(command)
        }
    }
}
