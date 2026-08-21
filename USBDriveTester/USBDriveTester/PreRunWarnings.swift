//
//  PreRunWarnings.swift
//  USBDriveTester (app target — unprivileged)
//
//  Step 14, increment 1. What stands between pressing Start and a write (FR-WARN-1/2/3/4,
//  NFR-USE-4, and the NFR document's 2026-08-09 qualification).
//
//  ## Why this is a type rather than an `if` in a view
//
//  Same reason as `OutcomePresentation`, arrived at the same way. The dialog this decides is a
//  SwiftUI **sheet**, and a sheet gets its own window — `scripts/render-ui.sh` cannot capture it in
//  place, so "a dialog appeared" will always need a person at the keyboard. That cost was accepted
//  knowingly (user decision 2026-08-09, decision 3), and the mitigation is the one Step 10 reached
//  after five rounds on a control whose message was correct and never seen: **put the decision
//  somewhere a mutation can reach it, and log the route taken.** Then the only thing left to a
//  human is *did a dialog appear*, not *was the right thing decided*.
//
//  ## The rule, in one line
//
//  **The warning text is suppressible. The deliberate act is not.**
//
//  > *"This tool may be utilized by people who test drives professionally and the warning could
//  > really get annoying."* — user, 2026-08-09
//
//  So `PreRunPrompt` has **two cases and no third**. There is deliberately no `.none`: a run that
//  begins with no dialog at all is not a state this type can express, so it cannot be reached by an
//  edit that forgets the requirement — only by adding a case, which shows up in every `switch` that
//  handles one. Same move as `FailureMode` having no unrecognised member and `LoadedChunk` being
//  unrepresentable when invalid: *prevent, don't detect.*
//
//  It matters here more than it reads. FR-DEV-3 default-selects the first usable device in
//  FR-DEV-2's BSD-name order, confirmed under challenge on 2026-08-06 and unchanged — and on
//  2026-08-09 that default was re-measured as the **22 TB Seagate with Backup and Time Machine
//  mounted**. The FR document's entry for that decision concludes that *"the entire mitigation sits
//  in Step 14's warnings"*, and BUILD-PLAN Step 11's deletion of the `Unmount All` / `Acquire`
//  controls is gated on this step for the same reason. A suppression that switched the dialog off
//  to *nothing* would hand that hazard straight back: one launch, one click, a write to whichever
//  drive happened to sort first. Switching it down to a drive-naming confirmation does not — and
//  that confirmation identifies the drive by **model and USB serial**, the axis that survives a
//  renumbering, which the three paragraphs never did.
//
//  ## What this deliberately does NOT own
//
//  Whether a run is permitted *at all* — a drive selected, a run already in progress. Those already
//  gate the control that issues work (`RunControlPolicy`), and a second copy of them here would be
//  a second source of truth for one fact. That is precisely the defect Step 11 increment 5 deleted
//  rather than fixed: `AppModel.helperHoldsDevice` was written from a *per-device* answer and read
//  everywhere as *some device*, and the two could disagree.
//
//  The **one** precondition this type does re-check is ``AppModel/mayIssueNewWork``, and only
//  because it is the one that can change *while the sheet is up*: the quit confirmation is
//  window-modal on the main window, and the sheet can sit unanswered for far longer than the run it
//  is asking about (measured, Step 9 increment 4). Step 11's
//  inherited note is explicit that `mayIssueNewWork` is "a precondition, not a hint" to be checked
//  **before every call issued**. Checking it at the moment the sheet was *raised* is not that.
//

import Foundation
import os

/// **What a run is being started IN PLACE OF** (FR-CTRL-5, Step 11 increment 8).
///
/// Orthogonal to which *form* the dialog takes, which is why it is a second dimension rather than a
/// third case. The form answers "has this user suppressed the standing warnings"; this answers "is
/// there a run that this press destroys" — and the two vary independently, so a user who has
/// suppressed the warnings still has to be told that Restart discards hours of work.
///
/// **Suppression does not reach it, and that is NFR-USE-4's rule rather than a choice made here.**
/// What is suppressible is the standing FR-WARN-1/2/3 text — advice about the tool, the same on
/// every run. The discard warning is about *this press*: it is a consequence, not a caution, and a
/// consequence the user has never been shown cannot have been consented to in advance.
nonisolated enum PreRunPurpose: Equatable, CaseIterable {

    /// Nothing is running. The ordinary Start (FR-CTRL-1).
    case newRun

    /// **A run is under way and this press ends it** (FR-CTRL-5). Its progress is discarded and
    /// cannot be resumed (FR-FAIL-7), so the new run begins from block 0.
    case restart
}

/// Which dialog a Start or Restart press must put in front of the user.
///
/// Both cases carry the drive, because both must name it. The suppressed case has nothing else to
/// say, so if it did not name the drive it would say nothing at all.
///
/// **Both also carry a ``PreRunPurpose``, with no default**, which cost every construction site an
/// edit — the same judgement increment 2 made about the engine's `control:` closure. A default of
/// `.newRun` would mean a future path that raises this dialog *during a run* silently omits the
/// one sentence that says the run is about to be destroyed, and nothing would fail. There is no
/// value it can safely default to, because the safe answer depends on the caller.
nonisolated enum PreRunPrompt: Equatable, Identifiable {

    /// FR-WARN-1/2/3 in full, plus FR-WARN-4's framing, plus the "Don't show this warning again"
    /// checkbox. Proceed / Cancel.
    case fullWarnings(ReportedDevice, purpose: PreRunPurpose)

    /// The user has suppressed the text. One line naming the drive by model and USB serial, and the
    /// same two buttons. **No checkbox** — there is nothing left to suppress, and the way back is
    /// the diagnostics window's "Show pre-run warnings again" (decision 7).
    case briefConfirmation(ReportedDevice, purpose: PreRunPurpose)

    /// The drive this prompt is about.
    var device: ReportedDevice {
        switch self {
        case .fullWarnings(let device, _), .briefConfirmation(let device, _): return device
        }
    }

    /// For `sheet(item:)`, which needs an identity to decide when a *different* prompt is being
    /// presented. Both halves matter: the form, so suppressing the text mid-session re-presents the
    /// right dialog, and the drive, so a prompt raised for one drive is never reused for another —
    /// the identity the whole acknowledgement is about.
    var id: String {
        "\(logName)|\(device.usbSerialNumber ?? device.modelDescription)"
    }

    /// For the log, so which dialog the user was shown is recoverable after the fact.
    ///
    /// The two names differ deliberately. Step 10's mutation **S4** — *"a silent outcome logs the
    /// same as inline"* — is the same defect in the same place: a log that cannot distinguish two
    /// routes is a log that cannot answer the question it exists for.
    var logName: String {
        let form: String
        switch self {
        case .fullWarnings:      form = "full warnings"
        case .briefConfirmation: form = "brief confirmation (warnings suppressed)"
        }
        // **The purpose is part of the name, and it has two jobs.** After the fact it says which
        // of the two acts the user acknowledged — a log that cannot tell a Start from a Restart
        // cannot answer the question it exists for, which is Step 10's mutation S4 exactly. And
        // because ``id`` is built from this, it is also what makes `sheet(item:)` treat a restart
        // prompt as a *different* prompt from a start prompt for the same drive.
        switch purpose {
        case .newRun:  return form
        case .restart: return form + ", restart"
        }
    }

    /// What this press is being made in place of.
    var purpose: PreRunPurpose {
        switch self {
        case .fullWarnings(_, let purpose), .briefConfirmation(_, let purpose): return purpose
        }
    }

    /// Whether this press ends a run that is already under way (FR-CTRL-5).
    var discardsRunInProgress: Bool { purpose == .restart }

    /// **The rule.** Suppressed or not, a dialog is raised; only its content changes.
    static func forRun(warningsSuppressed: Bool, device: ReportedDevice) -> PreRunPrompt {
        forPress(warningsSuppressed: warningsSuppressed, device: device, purpose: .newRun)
    }

    /// **FR-CTRL-5.** The same rule for a Restart: a dialog is always raised, the suppression
    /// preference still chooses its form, and the discard warning rides on both forms.
    static func forRestart(warningsSuppressed: Bool, device: ReportedDevice) -> PreRunPrompt {
        forPress(warningsSuppressed: warningsSuppressed, device: device, purpose: .restart)
    }

    /// One place deciding the form, so Start and Restart cannot drift about what suppression means.
    private static func forPress(warningsSuppressed: Bool,
                                 device: ReportedDevice,
                                 purpose: PreRunPurpose) -> PreRunPrompt {
        warningsSuppressed ? .briefConfirmation(device, purpose: purpose)
                           : .fullWarnings(device, purpose: purpose)
    }
}

/// Which button dismissed the dialog.
nonisolated enum PreRunButton: Equatable, CaseIterable {
    case proceed
    case cancel
}

/// What dismissing the dialog changes.
nonisolated struct PreRunOutcome: Equatable {

    /// Whether the run may now be issued.
    let issuesRun: Bool

    /// Whether "Don't show this warning again" should be written to the store.
    ///
    /// Only ever `true` to **set** it. Clearing is the diagnostics window's control (decision 7)
    /// and is not routed through here — stated so a reader does not go looking for it.
    let persistsSuppression: Bool
}

/// The decisions, gathered where a test can reach them.
nonisolated enum PreRunWarningPolicy {

    /// **The rule: the preference is recorded only by a run that actually starts.**
    ///
    /// Two rows carry that, and both are deliberate.
    ///
    /// **Cancel with the box ticked does not suppress.** Cancel is the button a user presses when
    /// something is wrong, and the most plausible something — on a screen whose entire job is
    /// stopping the wrong drive being written to — is that the selected drive is not the one they
    /// meant. Persisting *"never warn me again"* out of a dialog the user backed away from would
    /// reduce future warnings at the exact moment the warnings just did their job. The tick
    /// expresses a preference about a run that was then declined; it is not carried.
    ///
    /// The alternative was considered and is not unreasonable: the checkbox is a setting, settings
    /// are not conditional on the surrounding action, and this costs the user a re-tick. It was
    /// rejected because the two readings differ only in an edge case, and they differ there in
    /// favour of showing more warnings or fewer — which is not a symmetric choice in this product.
    ///
    /// **Proceed while a quit is pending issues nothing, and therefore suppresses nothing.**
    /// `mayIssueNewWork` is false from the moment a quit is *pending*, and the quit confirmation is
    /// window-modal on the main window, so the window this sheet is raised from stays clickable
    /// underneath it. A press that cannot start a run is not a run that started.
    static func outcome(button: PreRunButton,
                        suppressionRequested: Bool,
                        mayIssueNewWork: Bool) -> PreRunOutcome {
        let issuesRun = button == .proceed && mayIssueNewWork
        return PreRunOutcome(issuesRun: issuesRun,
                             persistsSuppression: suppressionRequested && issuesRun)
    }
}

// MARK: - The log

private nonisolated let warningLog = Logger(subsystem: HelperIdentity.loggingSubsystem,
                                            category: "safety")

/// What happened at the gate between pressing Start and a write (NFR-OBS-1).
///
/// ## Why this exists at all, and why it is not optional politeness
///
/// This surface **cannot be captured by `scripts/render-ui.sh`** — a SwiftUI sheet gets its own
/// window — so "did a dialog appear" is a question only a person can answer. That makes the log the
/// only durable record that the gate ran. Step 10 spent two of five rounds on a control whose
/// message was correct and whose route was invisible, and the thing that finally separated *never
/// produced* from *produced and never seen* was a log line.
///
/// It is also what catches the one defect this step's design cannot make unrepresentable: a Start
/// control wired **straight to the run**, skipping the dialog. `PreRunPrompt` has no "no dialog"
/// case, so that state cannot be expressed inside the decision — but a call site can always just
/// not ask. If it does, **no line is emitted here**, and the absence is the signal.
nonisolated enum PreRunWarningLog {

    /// A run was requested and the gate raised a dialog.
    static func promptRaised(_ prompt: PreRunPrompt) {
        warningLog.notice("""
                          pre-run prompt raised: \(prompt.logName, privacy: .public); \
                          drive serial \(prompt.device.usbSerialNumber ?? "none", privacy: .public)
                          """)
    }

    /// The dialog was dismissed, and what that decided.
    ///
    /// Both consequences are logged rather than only the run, because "the user proceeded" and "a
    /// run was issued" are **different facts** — a quit pending between the two makes them differ,
    /// and a log that conflated them would answer the wrong question afterwards.
    static func dismissed(_ button: PreRunButton, outcome: PreRunOutcome) {
        warningLog.notice("""
                          pre-run prompt dismissed: \(String(describing: button), privacy: .public); \
                          run issued: \(outcome.issuesRun, privacy: .public); \
                          suppression recorded: \(outcome.persistsSuppression, privacy: .public)
                          """)
    }

}

// MARK: - Where the suppression lives

/// Whether the user has asked not to see the pre-run warning text again.
///
/// A protocol for two consumers that must not touch the real user's preferences: the unit tests,
/// and `tools/ui-probe`, which has to render **both** dialogs — a state no render could otherwise
/// reach without writing to the machine's actual defaults. Same reasoning as
/// `AppModel.terminateAction` being injectable so the winding-down banner can be rendered at all.
///
/// ## Per logged-in user, and why the implementation may not move
///
/// The real store is the **app's** `UserDefaults` (decision 5, increment 4) — per-user by
/// construction, at `~/Library/Preferences/<bundle-id>.plist`, since the App Sandbox is off.
///
/// **It must never be the helper's.** The helper runs as root as a `LaunchDaemon`, so anything it
/// persisted would be system-wide and would silently apply to every account on the machine — the
/// opposite of what was asked for, and invisible to the user who would be affected by it.
nonisolated protocol PreRunWarningSuppressionStore: AnyObject {

    /// `true` once the user has ticked "Don't show this warning again" on a run that started.
    var warningsSuppressed: Bool { get set }
}

/// A store that forgets. For tests and for `tools/ui-probe`.
nonisolated final class InMemoryPreRunWarningSuppression: PreRunWarningSuppressionStore {

    var warningsSuppressed: Bool

    init(warningsSuppressed: Bool = false) {
        self.warningsSuppressed = warningsSuppressed
    }
}

/// The real store: the **app's** `UserDefaults`, which is per logged-in user by construction.
///
/// ## Why this is per-user without doing anything to make it so
///
/// `UserDefaults.standard` in the app writes to `~/Library/Preferences/<bundle-id>.plist` — inside
/// the home directory of whoever is logged in. The App Sandbox is off (and must stay off), so that
/// is the literal path. Nothing here has to *implement* per-user scoping; what it has to do is
/// **not be somewhere else**, and the somewhere else is real: the helper runs as root, so a setting
/// it persisted would be system-wide and would silently apply to every account on the machine. That
/// is the opposite of what was asked for and would be invisible to the account it affected.
///
/// ## The default is "show the warnings", by construction rather than by a written default
///
/// `bool(forKey:)` returns `false` for a key that has never been set, and `false` is *not
/// suppressed*. So a fresh install, a new user account, and a deleted preferences file all warn —
/// and none of them depends on a default having been registered. Registering one would add a second
/// place the answer lives, and the safe answer is already the one absence gives.
nonisolated final class UserDefaultsPreRunWarningSuppression: PreRunWarningSuppressionStore {

    /// The stored key. Only referred to here, so there is one spelling of it.
    static let key = "preRunWarningsSuppressed"

    private let defaults: UserDefaults

    /// - Parameter defaults: injectable so tests can use a throwaway suite. **A test that wrote to
    ///   `.standard` would change the preferences of whoever ran the suite** — a side effect on a
    ///   real machine, from a unit test, which is exactly the kind of thing this project's gates
    ///   exist to keep out of the apparatus.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var warningsSuppressed: Bool {
        get { defaults.bool(forKey: Self.key) }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}
