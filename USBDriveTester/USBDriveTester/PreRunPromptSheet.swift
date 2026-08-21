//
//  PreRunPromptSheet.swift
//  USBDriveTester (app target — unprivileged)
//
//  Step 14, increment 3. The dialog itself (FR-WARN-1/2/3/4, NFR-USE-4/6/8).
//
//  ## Built before anything can present it, deliberately
//
//  A SwiftUI **sheet gets its own window**, so `scripts/render-ui.sh` cannot capture it in place.
//  This surface will always need a person to confirm it appeared — the cost was accepted knowingly
//  (user decision 2026-08-09, decision 3) and it is the same cost Step 10 accepted for the unmount
//  alert.
//
//  What that buys is a rule about the order of work. Step 10 cost five rounds on one control, and
//  the last two were spent not on a broken mechanism but on a correct one nobody could observe:
//  **a correct value that nobody can observe is indistinguishable from a wrong one.** So this view
//  is a **standalone `View` taking plain values**, with its own `render-ui.sh` cases, and it is
//  rendered and inspected *before* increment 5 gives anything the ability to present it. Everything
//  that can be checked headlessly is checked headlessly; the person is left with "did a dialog
//  appear", not "is the dialog right".
//
//  ## Layout: the buttons are pinned, and that is not a style choice
//
//  The scrolling region is the **middle only**. The drive being named stays at the top and the
//  buttons stay at the bottom, whatever the window size.
//
//  Scoping this step found the main window clipping its own mount controls at its stated
//  `minHeight` — content had outgrown a constant measured a step earlier, and the controls fell
//  into a scroll region that does not advertise itself as scrollable. That is the same defect that
//  cost Step 10 two rounds, in the same pane, and it is exactly what a tall pile of warning text
//  above a Proceed button would reproduce. Here it cannot: the footer is outside the `ScrollView`.
//
//  ## No default keyboard action, and that is deliberate too
//
//  Neither button takes `.defaultAction`, so **Return does not start a run**. Escape still cancels.
//  The precedent is Step 9's quit dialog, which made *Continue Testing* the default because Return
//  and Escape should both keep a run rather than end one; the same reasoning inverted says Return
//  must not *begin* one. A dialog whose whole purpose is a deliberate act should not be dismissible
//  by the reflex that dismisses every other dialog.
//

import SwiftUI

/// The dialog raised by pressing Start. Which of its two forms is drawn comes from `PreRunPrompt`,
/// so the decision made in increment 1 is what reaches the screen — there is no second decision
/// here about whether to warn.
struct PreRunPromptSheet: View {

    let prompt: PreRunPrompt

    /// Bound rather than owned: the value has to survive the sheet being dismissed so the caller
    /// can persist it, and only on a run that actually starts (see `PreRunWarningPolicy.outcome`).
    @Binding var suppressFutureWarnings: Bool

    let onProceed: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch prompt {
                    case .fullWarnings:      fullWarningsBody
                    case .briefConfirmation: briefConfirmationBody
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            footer
        }
        .frame(minWidth: 460, idealWidth: 560,
               minHeight: minimumHeight, idealHeight: idealHeight)
    }

    // MARK: - Header — the drive, on every form of the dialog

    /// **Model, capacity and serial, with the BSD name beside them as a labelled locator.**
    ///
    /// The 2026-08-06 rule: a live surface shows both, because the serial answers *which drive is
    /// this across time* and the BSD name answers *which of the things in front of me right now*,
    /// and a user who can cross-check one against the other is better off than one who cannot. What
    /// must never happen is the BSD name standing as the identity — this dialog is the subject of
    /// an acknowledgement, and on this machine `disk8` named two different drives in three days.
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            // The suppressed form has no separate heading — the question *is* the heading. With
            // one it read "Start testing this drive?" directly above "Start testing the 22.00 TB
            // Seagate Expansion HDD, serial …?", which the render caught and the source could not.
            if case .fullWarnings = prompt {
                Text(PreRunWarningText.fullDialogTitle)
                    .font(.headline)
            }

            Text(PreRunWarningText.confirmationQuestion(for: prompt.device))
                .font(isBrief ? .headline : .body)
                .fixedSize(horizontal: false, vertical: true)

            // **FR-CTRL-5, on both forms and in the PINNED header** (increment 8). Suppression
            // reaches the standing FR-WARN text, never this: it is a consequence of this press
            // rather than advice about the tool, and it is the one thing about Restart a user
            // cannot recover from having missed. In the header rather than the scroll region for
            // the reason the footer is pinned — the fold has cost this project three times.
            if prompt.discardsRunInProgress {
                Label(PreRunWarningText.restartDiscardsProgress,
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(PreRunWarningText.restartDiscardsProgress)
            }

            if let bsdName = prompt.device.bsdNameAtRunTime {
                Text("Currently \(bsdName) — a locator, not an identity; it may name a different "
                   + "drive after a replug or a reboot.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let caveat = prompt.device.identificationCaveat {
                Label(caveat, systemImage: "questionmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isBrief: Bool {
        if case .briefConfirmation = prompt { return true }
        return false
    }

    /// Sized per form. The suppressed dialog is three lines; giving it the full dialog's height
    /// left it two-thirds empty, which reads as something having failed to load.
    private var idealHeight: CGFloat { isBrief ? 260 : 620 }
    private var minimumHeight: CGFloat { isBrief ? 200 : 320 }

    // MARK: - The two bodies

    /// FR-WARN-1/2/3 in full, then FR-WARN-4's framing.
    ///
    /// Every string comes from `PreRunWarningText` / `HonestFraming`. Nothing is written here —
    /// increment 2 exists because two surfaces that each held their own copy had already drifted.
    @ViewBuilder private var fullWarningsBody: some View {
        ForEach(PreRunWarningText.mandatory) { warning in
            VStack(alignment: .leading, spacing: 6) {
                // NFR-USE-8: the symbol and the words carry it, never the colour on its own.
                Label(warning.title, systemImage: symbol(for: warning))
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(warning.points) { point in
                    Text(point.plain)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        VStack(alignment: .leading, spacing: 6) {
            Text("What this test does and does not prove")
                .font(.headline)
            Text(HonestFraming.summary.plain)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(HonestFraming.claims) { claim in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•")
                    Text(claim.plain)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What a user sees once they have suppressed the text. The drive is already named in the
    /// header, so this adds only what is about to happen to it.
    private var briefConfirmationBody: some View {
        Text(PreRunWarningText.confirmationConsequence)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One symbol per warning, chosen so the meaning survives greyscale (NFR-USE-8).
    private func symbol(for warning: PreRunWarning) -> String {
        switch warning.requirement {
        case "FR-WARN-1": return "externaldrive.badge.exclamationmark"
        case "FR-WARN-2": return "clock.arrow.circlepath"
        default:          return "questionmark.circle"
        }
    }

    // MARK: - Footer — pinned, so a Proceed button can never fall below the fold

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if case .fullWarnings = prompt {
                VStack(alignment: .leading, spacing: 2) {
                    Toggle(PreRunWarningText.suppressionCheckbox, isOn: $suppressFutureWarnings)
                    Text(PreRunWarningText.suppressionCaveat)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Spacer()
                // `.cancel` so Escape works. Neither button is `.defaultAction`: Return must not
                // start a run — see the note at the top of this file.
                Button("Cancel", role: .cancel) { onCancel() }
                Button("Proceed") { onProceed() }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Full warnings") {
    PreRunPromptSheet(
        prompt: .fullWarnings(ReportedDevice(modelDescription: "Seagate Expansion HDD",
                                             usbSerialNumber: "00000000NT17XBRA",
                                             bsdNameAtRunTime: "disk4",
                                             capacityBytes: 22_000_969_973_248,
                                             logicalBlockSize: 512),
                              purpose: .newRun),
        suppressFutureWarnings: .constant(false),
        onProceed: {}, onCancel: {})
}
