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
//  Whether a run is permitted *at all* — a device being held, a call already in flight, a cycle
//  already running. Those already gate the control that issues work, and a second copy of them here
//  would be a second source of truth for one fact. That is precisely the defect BUILD-PLAN Step 11
//  is documented as deleting rather than fixing: `AppModel.helperHoldsDevice` is written from a
//  *per-device* answer and read everywhere as *some device*, and the two can disagree.
//
//  The **one** precondition this type does re-check is ``AppModel/mayIssueNewWork``, and only
//  because it is the one that can change *while the sheet is up*: the quit confirmation is
//  window-modal on the main window, so the diagnostics window — where this sheet is raised until
//  Step 11 builds Start — stays clickable underneath it (measured, Step 9 increment 4). Step 11's
//  inherited note is explicit that `mayIssueNewWork` is "a precondition, not a hint" to be checked
//  **before every call issued**. Checking it at the moment the sheet was *raised* is not that.
//

import Foundation

/// Which dialog a Start press must put in front of the user.
///
/// Both cases carry the drive, because both must name it. The suppressed case has nothing else to
/// say, so if it did not name the drive it would say nothing at all.
nonisolated enum PreRunPrompt: Equatable {

    /// FR-WARN-1/2/3 in full, plus FR-WARN-4's framing, plus the "Don't show this warning again"
    /// checkbox. Proceed / Cancel.
    case fullWarnings(ReportedDevice)

    /// The user has suppressed the text. One line naming the drive by model and USB serial, and the
    /// same two buttons. **No checkbox** — there is nothing left to suppress, and the way back is
    /// the diagnostics window's "Show pre-run warnings again" (decision 7).
    case briefConfirmation(ReportedDevice)

    /// The drive this prompt is about.
    var device: ReportedDevice {
        switch self {
        case .fullWarnings(let device), .briefConfirmation(let device): return device
        }
    }

    /// For the log, so which dialog the user was shown is recoverable after the fact.
    ///
    /// The two names differ deliberately. Step 10's mutation **S4** — *"a silent outcome logs the
    /// same as inline"* — is the same defect in the same place: a log that cannot distinguish two
    /// routes is a log that cannot answer the question it exists for.
    var logName: String {
        switch self {
        case .fullWarnings:     return "full warnings"
        case .briefConfirmation: return "brief confirmation (warnings suppressed)"
        }
    }

    /// **The rule.** Suppressed or not, a dialog is raised; only its content changes.
    static func forRun(warningsSuppressed: Bool, device: ReportedDevice) -> PreRunPrompt {
        warningsSuppressed ? .briefConfirmation(device) : .fullWarnings(device)
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
