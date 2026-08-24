//
//  PreRunControls.swift
//  USBDriveTester (app target — unprivileged)
//
//  Step 11, increment 6. **The two pre-run controls**, as pure logic: when they are live, where the
//  I/O size is kept, and how a size is rendered for a person.
//
//  Both moved to the main window in this increment. The failure-mode picker (FR-CTRL-7) sat in the
//  diagnostics window from Step 10 purely as scaffolding — there was no Start control to put it
//  beside until increment 5 — and the I/O-size dropdown (FR-CTRL-8) had never been built at all;
//  the size was the documented default, hardcoded at the wiring seam.
//
//  ## ONE RULE FOR BOTH CONTROLS: chosen before a run, fixed for the whole of it
//
//  Live in `idle` and `finished`; dead in the six states where a run is under way, **`paused`
//  included**. That is `RunControlState.isRunActive` exactly, and it is derived from it rather than
//  restated — the pre-run controls freezing is the same fact as the device list freezing and an
//  uninstall being refused, and two statements of one fact is what this project deletes rather than
//  fixes.
//
//  ## Why `paused` is on the dead side, which is a REVERSAL (user decision 2026-08-19)
//
//  FR-CTRL-8 said *"configurable before a run starts and while a run is paused or stopped"* from
//  2026-08-04, and the 2026-08-14 revision kept that clause while changing what a change did
//  (ending the run rather than resuming at the new size). Increment 6 built exactly that — and it
//  was **looked at in front of the user, paused, on real hardware**, which is what settled it:
//
//  > *"Having seen it in real life, I no longer like the idea of those two controls having
//  > different behavior after pausing the test. The user should either be able to change both or
//  > neither."* — user, 2026-08-19
//
//  The two controls genuinely could not be made to agree on the *live* side, and the asymmetry is
//  not cosmetic:
//
//    * **The I/O size cannot resume across a change.** Percentiles do not compose and a minimum
//      cannot be un-seen, so a run spanning two sizes reports figures that describe neither. That
//      is the whole of FR-CTRL-8's 2026-08-14 amendment.
//    * **The failure mode CAN resume across a change** — it is per call, it is a stored property on
//      `RunSequencer` set once at `start()`, and it contaminates no measurement: it changes what
//      happens *on* a failure, not how bytes are read or written. What stops it is not mechanism.
//      It is that `RunReport.failureMode` is a single field taken from the **last** call's reply,
//      so a run that logged-and-continued for hours and then switched would be reported as
//      `stopOnFirstError` throughout; and that **`stopOnFirstError` selected after failures already
//      exist has no defined meaning** — stop now, or stop at the next one? A control whose meaning
//      depends on run history is worse than one that is simply unavailable.
//
//  So "both live" would have meant one control ending the run and the other not, or widening the
//  report to carry a list of modes to buy an ambiguity with no principled answer. **Both dead is
//  the consistency that costs nothing**, and the way to change either is Stop → change → Start,
//  where the Stop is itself the deliberate act.
//
//  ## What went with that decision, and why it is not a loss
//
//  The confirmation dialog this increment first built — `IOSizeChangePrompt`, an alert, a
//  `RunController.endRunForIOSizeChange()`, and the two log routes for it — is **deleted**. With
//  the control dead for the whole run there is no state in which changing it ends anything, so the
//  dialog had no trigger left. *Nothing untriggerable is built in advance* (CONSTRAINTS section 2):
//  a sound mechanism behind a trigger that never fires looks exactly like a broken one, and keeping
//  it would have left ~150 lines and two test suites standing over a path no user can reach.
//
//  Full account of the reversal in the FR document's 2026-08-19 amendment.
//
//  `nonisolated` throughout, for the reason `RunControlState.swift` records: the app target
//  compiles with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, which would otherwise make even these
//  value types main-actor-isolated and unusable from the non-isolated test target.
//

import Foundation
import os

private nonisolated let ioSizeLog = Logger(subsystem: HelperIdentity.loggingSubsystem,
                                           category: "io")

// MARK: - When the pre-run controls are live

/// Whether the I/O size and the failure mode may be changed right now (FR-CTRL-7, FR-CTRL-8,
/// FR-FAIL-1).
///
/// **One answer for both controls**, which is the point: two pre-run controls behaving differently
/// after a pause was confusing in front of the user, and the fix was to make them agree rather than
/// to explain the difference better.
nonisolated enum PreRunControls {

    /// Live before a run and once one has finished; dead for the whole of a run, `paused` included.
    ///
    /// **Derived from ``RunControlState/isRunActive`` rather than walking the eight states again.**
    /// That property already answers "is a run under way?" for the device-list freeze (FR-DEV-7),
    /// the uninstall guard (NFR-INST-3) and the quit confirmation, and the pre-run controls
    /// freezing is the same fact — not a parallel one that happens to agree today. A second table
    /// here could drift from it silently, and a state added later would have to be remembered in
    /// two places instead of one.
    ///
    /// `PreRunControlTableTests` still walks all eight states, so the derivation is pinned rather
    /// than trusted.
    static func availability(in state: RunControlState) -> RunControlAvailability {
        guard state.isRunActive else { return .enabled }
        return .disabled(rule)
    }

    /// The rule, in one sentence, **shown whether or not a run is under way** (user decision
    /// 2026-08-24).
    ///
    /// ## Why it is a standing line and not only a refusal
    ///
    /// It used to be rendered only while the controls were dimmed, *below* them, as the reason
    /// they were dead. That is the wrong moment: by the time it appears, the choice it describes
    /// has already been made and frozen. The user's reason for moving it — *"the user should read
    /// this before a run is started and those parameters become frozen for the run"* — is a
    /// statement about **when**, and a conditional line cannot satisfy it. So it is unconditional
    /// and it sits directly above the I/O size row it governs.
    ///
    /// ## Why the wording changed with the position
    ///
    /// It read *"…are fixed for the whole run — stop it to change them."* Both halves presupposed
    /// a run in progress: *"the whole run"* means this one, and *"stop it"* has no referent before
    /// there is anything to stop. Moving that sentence without rewording it would have put a
    /// sentence about a run in front of a user who has not started one.
    ///
    /// ## What could not change, and why
    ///
    /// **The corrective step stays.** NFR-USE-5 is Mandatory and requires a message to name *"the
    /// actual cause and the corrective step"*. A tidier rule — *"…apply to the whole run and are
    /// fixed once it starts."* — was written first and rejected on that ground: it states the cause
    /// and leaves a user who wants to change the size with nowhere to go.
    /// `PreRunControlsTests.theOneReasonNamesBothControls` pins all three obligations by substring
    /// — both controls named, and a way out given — so a later edit cannot quietly drop one.
    ///
    /// One string, two jobs: the standing caption *and* the reason `availability(in:)` carries when
    /// the controls are dead. A second literal for the dimmed case is the drift this file has
    /// already paid for twice.
    static let rule =
        "I/O size and failure handling are fixed once a run starts — stop the run to change them."
}

// MARK: - The I/O size itself

/// How an I/O size is rendered and how a stored one is made safe to use (FR-CTRL-8).
nonisolated enum IOSizeSelection {

    /// One size rendered for a person. **The only spelling of it in the app.**
    ///
    /// Three call sites — the dropdown's menu, the report window and the exported Markdown — and
    /// until this increment the latter two each carried their own copy of the expression. Two
    /// literals of one fact is the defect `ThroughputFraming` was written to end, found on
    /// 2026-08-18 having already drifted within a day.
    static func label(_ bytes: Int) -> String {
        "\(bytes / (1 << 20)) MiB"
    }

    /// A stored size, made safe to use.
    ///
    /// **The persisted value is not trusted**, and the reason is not hypothetical: the preferences
    /// file is a plist in the user's home directory, and a size this build does not permit — one
    /// hand-edited, or written by a version whose permitted set differed — would be refused by the
    /// helper at the XPC boundary (`RunCoordinator` validates it there, and rightly). That refusal
    /// would turn the user's Start into a *refused call*, which produces no report and reads as the
    /// drive failing rather than the preference being wrong.
    ///
    /// So an unrecognised value becomes FR-CTRL-8's default rather than travelling any further.
    /// This is the app reading back its own preference, not a trust boundary evaluating a caller —
    /// which is why defaulting is right here and **wrong** for `FailureModeCode` arriving over XPC,
    /// where an unrecognised code is refused and never defaulted.
    ///
    /// It also gives the default by construction, the way `UserDefaultsPreRunWarningSuppression`
    /// does: `integer(forKey:)` returns `0` for a key that has never been set, `0` is not a
    /// permitted size, and so a fresh install, a new user account and a deleted preferences file
    /// all start at 4 MiB with no default having been registered anywhere.
    static func permitted(_ stored: Int) -> Int {
        TesterProtocol.permittedIOSizes.contains(stored) ? stored : TesterProtocol.defaultIOSizeBytes
    }
}

// MARK: - The route

/// What happened at the pre-run controls (NFR-OBS-1).
///
/// Smaller than it was: with the controls dead for the whole of a run there is no confirmation to
/// raise and no run ended from here, so the two log routes for that went with the dialog.
nonisolated enum IOSizeLog {

    /// The size was changed.
    static func changed(from previous: Int, to selected: Int) {
        ioSizeLog.notice("""
                         I/O size changed: \(IOSizeSelection.label(previous), privacy: .public) \
                         -> \(IOSizeSelection.label(selected), privacy: .public)
                         """)
    }

    /// A change was issued while a run was under way — reachable only by a caller that did not
    /// consult the control, which is what a menu item or a keyboard shortcut does. Logged rather
    /// than swallowed: a request arriving where the state says it cannot is how a wiring defect
    /// announces itself.
    static func changeRefused(_ reason: String) {
        ioSizeLog.error("pre-run control change refused: \(reason, privacy: .public)")
    }
}

// MARK: - Where the choice is kept

/// Where the selected I/O size persists between launches (user decision, increment 6 scoping).
///
/// A protocol for the reason `PreRunWarningSuppressionStore` is one: a test that wrote to
/// `UserDefaults.standard` would change the preferences of whoever ran the suite — a real side
/// effect on a real machine, from a unit test.
nonisolated protocol IOSizeStore: AnyObject {

    /// The size to use for the next run, always one of ``TesterProtocol/permittedIOSizes``.
    var ioSizeBytes: Int { get set }
}

/// A store that forgets. For tests and for `tools/ui-probe`.
///
/// **The probe needs this specifically.** A render must not read or write the machine's real
/// preferences: ambient machine state leaking into an offscreen render is a trap this project has
/// paid for twice — the appearance bug of 2026-08-10, and the progress bar measuring two different
/// fills on one day with nothing in the diff touching it.
nonisolated final class InMemoryIOSize: IOSizeStore {

    private var stored: Int

    init(ioSizeBytes: Int = TesterProtocol.defaultIOSizeBytes) {
        self.stored = ioSizeBytes
    }

    /// Routed through ``IOSizeSelection/permitted(_:)`` like the real store, so the two cannot
    /// behave differently. A double that admits a value the real one would reject is a double that
    /// makes a green test mean less than it appears to.
    var ioSizeBytes: Int {
        get { IOSizeSelection.permitted(stored) }
        set { stored = newValue }
    }
}

/// The real store: the **app's** `UserDefaults`, which is per logged-in user by construction.
///
/// The reasoning for that is `UserDefaultsPreRunWarningSuppression`'s and is not repeated here —
/// the short version is that the App Sandbox is off, so this writes to
/// `~/Library/Preferences/<bundle-id>.plist`, and the alternative that must be avoided is the
/// **helper** persisting anything, because it runs as root and its settings would silently apply
/// to every account on the machine.
///
/// - Note: **No `defaults` command addressed by DOMAIN reaches this file** — not `read`, and not
///   `write` or `delete` either (measured 2026-08-19, and the write half the hard way on
///   2026-08-20, when a `defaults delete` of a saved window frame silently did nothing and a
///   checklist item was recorded as failing because of it). Address the plist **by path**, or use
///   `plutil -p`. A stale sandbox container from 7 July still exists under `~/Library/Containers/`,
///   and the `defaults` CLI prefers a container path whenever that directory is present — so it
///   reads a file this app has never written and reports *"does not exist"*, which is
///   indistinguishable from the preference not having been saved. Read the plist by path instead;
///   `progress/step-11-human-checklist.md` chunk 8 carries the command.
nonisolated final class UserDefaultsIOSize: IOSizeStore {

    /// The stored key. Only referred to here, so there is one spelling of it.
    static let key = "runIOSizeBytes"

    private let defaults: UserDefaults

    /// - Parameter defaults: injectable so tests can use a throwaway suite.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// FR-CTRL-8's default arrives through ``IOSizeSelection/permitted(_:)`` rather than through a
    /// registered default — see that function for why an unset key, a hand-edited plist and a
    /// value from another version are all one check.
    var ioSizeBytes: Int {
        get { IOSizeSelection.permitted(defaults.integer(forKey: Self.key)) }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}
