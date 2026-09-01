//
//  HelperGateSheet.swift
//  USBDriveTester (app target — unprivileged)
//
//  Step 11, increment 9. The launch-time gate itself (NFR-INST-1, NFR-MAINT-1, NFR-USE-5/8).
//
//  ## A sheet rather than an `alert`, and the reason is that an alert cannot be looked at
//
//  A sheet's content is a `View` — instantiable, hostable offscreen, and therefore renderable by
//  `tools/ui-probe` exactly the way `PreRunPromptSheet` is. An **alert's content is not**:
//  `.alert(_:isPresented:actions:message:)` takes `ViewBuilder`s of buttons and text that AppKit
//  consumes, and there is no value to hand an `NSHostingView`. Choosing an alert would have meant
//  every word and every button of this dialog being human-only, on top of the wiring already being
//  so. CONSTRAINTS records that a sheet "can never be captured in place" — this one is captured
//  *out* of place, which is the whole trick that file's mitigation describes.
//
//  ## It takes values, not a model
//
//  `availability` in, `perform` out. That is what lets the five non-available states be rendered
//  before anything can present one — *a correct value that nobody can observe is indistinguishable
//  from a wrong one*, and this project has paid two rounds of Step 10 for learning it.
//
//  ## The buttons are pinned outside the scroll region
//
//  Not a style choice. A control below the fold in an unadvertised scroll region has cost this
//  project three times, most recently `Acquire exclusive access` sitting entirely off-screen at the
//  app's own minimum height. `unreachable(detail:)` carries a transport error's
//  `localizedDescription`, which has no length this app controls — so the message *must* be allowed
//  to scroll, and the only safe answer is a footer that is not inside the thing that scrolls.
//
//  ## No default and no cancel role, deliberately
//
//  Neither button takes `.defaultAction`, so Return does not fire a remedy by reflex — the same
//  reasoning `PreRunPromptSheet` records for not letting Return start a run. Quit does **not** take
//  `role: .cancel`, which would make **Escape quit the application**: the one keystroke every user
//  presses to dismiss a dialog would become the one that closes the app. Escape therefore does
//  nothing here, and `.interactiveDismissDisabled()` at the presentation site is what makes that
//  true rather than hoped for.
//

import SwiftUI

/// The modal raised at launch when the privileged helper cannot be used.
///
/// Which remedies it offers comes from ``HelperAvailability/actions``, so the decision made in
/// `HelperAvailability` is what reaches the screen — there is no second decision here about what to
/// offer. The `switch` that turns a pressed action into behaviour is in `AppModel`, where a test can
/// reach it.
struct HelperGateSheet: View {

    let availability: HelperAvailability

    /// The remedy currently running, or `nil` when the gate is idle. A value rather than a `Bool`
    /// so the footer can say *which* thing is happening; see ``HelperGateAction/progressLabel(from:)``.
    let actionInFlight: HelperGateAction?

    /// What a pressed button does. Injected so this view can be rendered and previewed with no
    /// model, no registration and no XPC connection behind it.
    let perform: (HelperGateAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            ScrollView {
                Text(availability.message)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }

            Divider()
            footer
        }
        .frame(minWidth: 420, idealWidth: 520, minHeight: 220, idealHeight: 300)
    }

    // MARK: - Header

    /// Symbol **and** words. NFR-USE-8: meaning never rests on colour or on a glyph alone, so the
    /// title states the condition and the symbol reinforces it. The symbol is hidden from the
    /// accessibility tree for the reason the other seven such sites in this app are — announcing a
    /// symbol name beside the sentence that already says it states the condition twice.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: availability.symbolName)
                .font(.title2)
                .accessibilityHidden(true)

            Text(availability.title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer

    /// The actions, in the order the state gives them: **remedy first, Quit last.**
    ///
    /// Rendered with `ForEach` over the data rather than written out per case, which is what keeps
    /// this view free of any branching about *which* remedy applies. A case added to
    /// `HelperGateAction` needs no edit here at all; it needs one in `AppModel`, where the compiler
    /// demands it.
    ///
    /// The one branch left is on ``HelperGateAction/isRemedy`` — a property of the data, not a
    /// question about which state this is. The remedy is the emphasised button, because a dialog
    /// whose prominent control is Quit reads as a dead end, which is the shape the 2026-08-26
    /// decision rejected.
    ///
    /// ## The busy state, and why it is a spinner rather than a cursor
    ///
    /// While a remedy runs, the remedies are disabled and a `ProgressView` with a label appears —
    /// **Quit stays live**, for the reason ``HelperGateAction/isEnabled(whileRunning:)`` gives.
    ///
    /// The user's suggestion was an hourglass cursor. There isn't one on macOS: that is a Windows
    /// idiom, and the nearest equivalent — the spinning wait cursor — is the system's way of saying
    /// *this app is not responding*, so using it deliberately would tell the user something false.
    /// Two more reasons specific to this project: a cursor is **invisible to the render harness**,
    /// which captures views and not cursors, whereas this is a renderable state with a case of its
    /// own (`helper-gate-busy`); and a state nothing automated can see is a state that drifts, which
    /// is the rule this whole gate was built under.
    private var footer: some View {
        HStack(spacing: 12) {
            if let actionInFlight {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)

                // The words carry the meaning, not the spinner (NFR-USE-8). A spinner alone says
                // "something is happening"; this says which something, and for how long it is
                // reasonable to expect it.
                Text(actionInFlight.progressLabel(from: availability))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            ForEach(availability.actions) { action in
                if action.isRemedy {
                    Button(action.label) { perform(action) }
                        .buttonStyle(.borderedProminent)
                        .disabled(!action.isEnabled(whileRunning: actionInFlight))
                } else {
                    Button(action.label) { perform(action) }
                        .disabled(!action.isEnabled(whileRunning: actionInFlight))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Not registered") {
    HelperGateSheet(availability: .notRegistered, actionInFlight: nil, perform: { _ in })
}

#Preview("Version mismatch") {
    HelperGateSheet(availability: .versionMismatch(helper: 11, app: 12),
                    actionInFlight: nil,
                    perform: { _ in })
}

#Preview("Replacing the helper") {
    HelperGateSheet(availability: .versionMismatch(helper: 12, app: 13),
                    actionInFlight: .registerHelper,
                    perform: { _ in })
}
