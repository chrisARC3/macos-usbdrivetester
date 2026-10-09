//
//  HelperAvailability.swift
//  USBDriveTester (app target — unprivileged)
//
//  Step 11, increment 9. **Whether this app can work at all**, decided once at launch (NFR-INST-1,
//  NFR-MAINT-1, NFR-USE-5).
//
//  ## Why this is a type rather than an `if` in a view
//
//  The same reason `PreRunWarnings` and `OutcomePresentation` are types, reached the same way. The
//  thing this decides is a **modal**, and a modal gets its own window — so "did a dialog appear"
//  will always need a person at the keyboard. The mitigation CONSTRAINTS records is to *put the
//  decision somewhere a mutation can reach it, and log the route taken*, leaving the human with
//  "did it appear" rather than "was the right thing decided".
//
//  **Each case carries its own actions.** That is what makes the whole decision testable: the view
//  renders `actions` and maps each to a closure through an exhaustive `switch`, so it contains no
//  branching about *which* remedy to offer. The banner this replaces had that branching inside a
//  `ViewBuilder`, where nothing could reach it.
//
//  ## Why it is diagnosed app-wide, and not from a failed per-device call
//
//  The deleted readiness banner showed `readinessError`, which comes from `withProxy`'s error
//  handler in `HelperConnection` — and that handler catches **any** XPC transport error. The code's
//  own comment names them: *"no helper, wrong version, connection dropped"*. It conflates five
//  conditions, including a **transient blip while the daemon restarts**, which `install-app.sh`
//  warns happens on every helper change. A fatal modal fired on that would go off during a routine
//  reinstall.
//
//  `SMAppService.status` is a **local** query needing no daemon, and `checkProtocolVersion` is
//  NFR-MAINT-1's handshake. Together they separate all five; a failed per-device call separates
//  none. `AppModel.swift:25` already carries this lesson in its own words, about a *per-device*
//  answer read everywhere as an any-device one.
//
//  ## Remedy-first, not Quit-only (user decision 2026-08-26)
//
//  The first proposal was a fatal modal offering **only Quit**. It was rejected on evidence: this
//  app already contains `Button("Register helper")` and already calls
//  `SMAppService.openSystemSettingsLoginItems()`. A Quit-only modal produces *quit → relaunch →
//  still not registered → same modal → quit*, with the dialog's own remedy text naming a window the
//  dialog prevents reaching.
//
//  **``notFound`` is the only genuinely Quit-only state** — the daemon's plist is missing from the
//  bundle, which is a broken installation that nothing in-app can repair. A version mismatch is
//  **not** Quit-only: this project's own wording, `ProtocolVersionCheck.mismatch.description`,
//  already prescribes re-registering.
//
//  ## The gate is raised only at launch, and that is load-bearing
//
//  `AppModel.refreshHelperAvailability()` is called from the scene's `onAppear`, by the gate's own
//  actions, and on every activation **while the gate is up** (user request, 2026-08-27 — see
//  `USBDriveTesterApp.swift`). Nothing re-diagnoses on a timer, or on activation while the gate is
//  down, **deliberately**: `checkProtocolVersion` goes out on the *owning* connection, which is
//  blocked for the whole of a run (the D1 measurement of 2026-08-04), so a re-check that could fire
//  mid-run would queue behind the very call it interrupts. Every trigger after launch runs only
//  while the gate is up, so it can clear the gate or re-diagnose it but never raise it. Because the
//  gate can only be raised before the main window has been used, no run can be in flight while it
//  is up — which is also what makes dropping the XPC connection safe on the register path (see
//  `AppModel.performHelperGateAction(_:)`).
//
//  `nonisolated` throughout, for the reason `RunControlState.swift` records: the app target compiles
//  with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, which would otherwise make even these value types
//  main-actor-isolated and unusable from the non-isolated test target.
//

import Foundation
import ServiceManagement
import os

private nonisolated let gateLog = Logger(subsystem: HelperIdentity.loggingSubsystem,
                                         category: "lifecycle")

// MARK: - What the user can do about it

/// One button on the launch-time gate.
///
/// A value rather than a closure so a test can assert *which* remedies a state offers and in what
/// order. The mapping from an action to what it actually does is an exhaustive `switch` in
/// `AppModel.performHelperGateAction(_:)`, so a case added here is a compile error there rather
/// than a button that silently does nothing.
nonisolated enum HelperGateAction: String, Equatable, Hashable, Identifiable, CaseIterable {

    /// `SMAppService.register()`. Offered where installing or re-installing the daemon is the fix.
    case registerHelper

    /// System Settings ▸ Login Items & Extensions, where the daemon is approved (NFR-INST-1).
    case openLoginItems

    /// Ask again. Re-reads the status and re-runs the handshake.
    case retry

    /// Leave. **Every non-available state offers it**, because a user who cannot fix the problem
    /// must still be able to put the app down.
    case quit

    var id: String { rawValue }

    /// What the button says. The ellipsis on Login Items follows the platform convention that a
    /// control opening another window says so — and `HelperDiagnosticsView` already spells it this
    /// way, so the two windows do not name one action differently.
    var label: String {
        switch self {
        case .registerHelper: return "Register Helper"
        case .openLoginItems: return "Open Login Items…"
        case .retry:          return "Retry"
        case .quit:           return "Quit"
        }
    }

    /// Whether this is the way out rather than a way forward. Used to assert that remedies come
    /// first, and by the view to decide which button is prominent.
    var isRemedy: Bool { self != .quit }

    /// Whether this button may be pressed while `inFlight` is still running.
    ///
    /// **Quit is the exception, deliberately.** Every remedy is disabled while one is running — the
    /// user asked, and the app has not answered yet; a second press would start a second unregister
    /// on top of the first, and there is a real window during `replaceRunningDaemon` where the
    /// status is momentarily `notRegistered`, so a press landing in it would take a different branch
    /// than the one the user thought they were pressing (user observation, 2026-09-01).
    ///
    /// But Quit stays live, because **nobody may be trapped behind a modal with no way out**. The
    /// sequence is recoverable if they leave mid-flight: the worst case is a daemon removed and not
    /// re-registered, which relaunches into `notRegistered`, a state whose remedy works. That is a
    /// far better failure than a dialog with every control dead because a callback never came.
    func isEnabled(whileRunning inFlight: HelperGateAction?) -> Bool {
        inFlight == nil || self == .quit
    }

    /// What to say while this action is running. Empty for ``quit``, which never shows progress.
    ///
    /// Takes the availability because the honest wording differs by state: from ``versionMismatch``
    /// this **replaces** a daemon that is installed and running, and from ``notRegistered`` it
    /// **installs** one that is not there. Saying "installing" while removing a working daemon would
    /// be the kind of small untruth this project keeps deleting.
    func progressLabel(from availability: HelperAvailability) -> String {
        switch self {
        case .registerHelper:
            switch HelperRegistrationRemedy.forGate(availability) {
            case .replaceRunningDaemon: return "Replacing the helper…"
            case .registerOnly:         return "Installing the helper…"
            }
        case .openLoginItems, .retry:
            return "Checking…"
        case .quit:
            return ""
        }
    }

    /// The word a state's ``HelperAvailability/message`` must use for this remedy, lowercased.
    ///
    /// NFR-USE-5 requires the corrective step to be **named**, so that a user reading the paragraph
    /// and a user reading the buttons are told the same thing. What it does not require is the
    /// paragraph quoting the button verbatim — and demanding that would cost something real:
    /// `versionMismatch` reuses `ProtocolVersionCheck.mismatch.description`, which reads *"Re-register
    /// the helper…"*, so a literal-label rule would force either a **second copy** of that sentence
    /// (the drift `ThroughputFraming` exists to end) or a worse wording chosen to satisfy a test.
    ///
    /// Written out rather than derived from ``label``. It was found by the check failing —
    /// `everyRemedyIsNamedInItsOwnMessage` demanded "Register Helper" and met "Re-register the
    /// helper" — and a rule with one documented exception buried in it is how the *next* case slips
    /// through a table walk.
    var messageStem: String {
        switch self {
        case .registerHelper: return "register"
        case .openLoginItems: return "login items"
        case .retry:          return "retry"
        case .quit:           return "quit"
        }
    }
}

// MARK: - The state itself

/// Whether the privileged helper can be used, and what to do when it cannot.
///
/// Six cases and no seventh. There is deliberately no `checking` state: the value starts
/// ``available`` and is written only once an answer exists, so nothing flashes on screen during the
/// handshake — see ``diagnose(status:version:)``.
nonisolated enum HelperAvailability: Equatable {

    /// Registered, approved, and answering this app's protocol version. **No modal.**
    case available

    /// The daemon's plist is not in this app bundle. A broken installation; the one Quit-only state.
    case notFound

    /// The daemon has never been installed on this Mac.
    case notRegistered

    /// Installed, but macOS will not run it until the user allows it (NFR-INST-1).
    case requiresApproval

    /// Enabled, but the handshake failed. Carries the transport error's text.
    ///
    /// **A `String`, not the `Error`** — `Result<_, Error>` is not `Equatable`, and this type must
    /// be, so that a test can assert a mapping by value rather than by inspection.
    case unreachable(detail: String)

    /// Enabled and answering, with a version this app was not built against (NFR-MAINT-1).
    case versionMismatch(helper: Int, app: Int)

    /// Whether the app may be used. The gate is shown for everything else.
    var isAvailable: Bool { self == .available }

    // MARK: - Diagnosis

    /// Resolve the two things that can be known without touching a drive.
    ///
    /// **Ordered by what the user must fix first**, mirroring the helper's own readiness check in
    /// `main.swift`: a daemon that is not installed cannot be out of date, so the status is settled
    /// before the version is consulted at all. `theStatusIsResolvedBeforeTheVersion` pins that
    /// ordering — without it, a mismatch reply left over from an earlier check could outrank a
    /// missing daemon.
    ///
    /// - Parameters:
    ///   - status: `SMAppService.status`, a **local** query that needs no daemon.
    ///   - version: the NFR-MAINT-1 handshake's answer, or `nil` when there is not one — either
    ///     because the status made it pointless to ask, or because the check is still in flight.
    ///
    /// ## Why `.enabled` with no answer yet is ``available``
    ///
    /// There is a real interval between reading the status and the handshake returning, and
    /// something has to be true during it. Reporting a *problem* there would put a modal on screen
    /// for a fraction of a second on every healthy launch, and a `checking` case would exist only
    /// to be switched over — no modal is shown for it either way. So the optimistic answer is the
    /// honest one: nothing is known to be wrong yet.
    static func diagnose(status: SMAppService.Status,
                         version: Result<ProtocolVersionCheck, Error>?) -> HelperAvailability {
        switch status {
        case .notFound:
            return .notFound
        case .notRegistered:
            return .notRegistered
        case .requiresApproval:
            return .requiresApproval
        case .enabled:
            guard let version else { return .available }
            switch version {
            case .failure(let error):
                return .unreachable(detail: error.localizedDescription)
            case .success(let check):
                switch check {
                case .match:
                    return .available
                case .mismatch(let helper, let app):
                    return .versionMismatch(helper: helper, app: app)
                }
            }
        @unknown default:
            // **Mandatory, reachable, and covered — measured 2026-08-27, not assumed.** A switch
            // over the four known statuses without this arm both warns (which the zero-warnings
            // gate fails on) and **traps at runtime**: `Fatal error: unexpected enum case
            // 'SMAppServiceStatus(rawValue: 99)'`. And `SMAppService.Status(rawValue: 99)` *does*
            // construct — an `@objc` enum's raw-value initialiser admits values it does not name —
            // so this line is reachable from a unit test rather than being a declared blind spot,
            // which is what it was about to be recorded as.
            //
            // Mapped to `unreachable` rather than given a case of its own: a seventh case would
            // exist for a status Apple has not shipped, which is a mechanism behind a trigger that
            // never fires. Retry is the honest remedy — it re-reads the status.
            return .unreachable(
                detail: "the system reported an unrecognised helper status (raw value \(status.rawValue))")
        }
    }

    // MARK: - What the modal says

    /// The heading. A statement of the condition, not a question.
    var title: String {
        switch self {
        case .available:        return ""
        case .notFound:         return "The privileged helper is missing from this app."
        case .notRegistered:    return "The privileged helper is not installed yet."
        case .requiresApproval: return "The privileged helper is waiting for your approval."
        case .unreachable:      return "The privileged helper did not answer."
        case .versionMismatch:  return "The installed helper is a different version from this app."
        }
    }

    /// The cause **and the corrective step**, in sentences (NFR-USE-5, which is Mandatory).
    ///
    /// `everyMessageNamesItsOwnRemedy` walks the whole table rather than the cases a view happens
    /// to render — the shape increment 1's mutation M9 taught, where a check over the rendered
    /// surface let a blanked reason pass 827 tests.
    var message: String {
        switch self {
        case .available:
            return ""

        case .notFound:
            // **The daemon's plist is deliberately not named here, and that is a cost decision.**
            // `HelperIdentity.daemonPlistName` is a computed `static var` in `Shared/TesterControl.swift`,
            // which the **helper** compiles — so reading it from this nonisolated context would mean
            // marking `HelperIdentity` nonisolated, which moves the helper source hash and puts
            // Step 10's three hardware gates back in question. (`loggingSubsystem` above is read
            // freely because a `static let` of a Sendable type is nonisolated already; only the
            // computed property is not.)
            //
            // Increment 6 did make that change to `TesterProtocol` and verified the gates still
            // stood by comparing `__TEXT,__text`, so the precedent and the method both exist. It is
            // not worth spending here: the remedy is "reinstall" and needs no filename, and the
            // full path is already in `HelperRegistration.statusExplanation`, which ⇧⌘D reaches
            // from behind this gate. If something later needs the constant from a nonisolated
            // context for a *load-bearing* reason, make the change then and re-verify.
            return """
                   macOS cannot find the privileged helper's launchd property list inside this \
                   application, so the helper can be neither installed nor started. Nothing in the \
                   app can repair this. Quit, reinstall USBDriveTester from a complete copy, and \
                   open it again. The Privileged Helper & Diagnostics window (⇧⌘D) names the exact \
                   file it is looking for.
                   """

        case .notRegistered:
            return """
                   USBDriveTester needs its privileged helper in order to read and write a drive's \
                   raw device, and the helper has not been installed on this Mac. Choose Register \
                   Helper to install it.
                   """

        case .requiresApproval:
            // **No ellipsis in the prose**, though the button carries one. "Choose Open Login
            // Items…, enable…" put an ellipsis immediately before a comma, which reads as a typo.
            // Found by rendering; no test could see it, because `messageStem` matches "login items"
            // either way — which is the point of the render existing at all.
            //
            // **This state has no separate Retry, and no longer needs one.** The sentence used to
            // end "then choose Open Login Items once more to re-check", because the button did
            // double duty — open Settings, and re-check. Walking chunk 13 item 4 on 2026-08-27 the
            // user reported that as the weak point it had been flagged as, and the fix was neither
            // of the two options on the table: the app re-checks on activation now
            // (`USBDriveTesterApp.swift`), so returning from Settings clears the gate by itself.
            // The action table approved 2026-08-26 is unchanged — no button was added or removed.
            return """
                   The helper is installed, but macOS will not run it until you allow it. Choose \
                   Open Login Items and enable USBDriveTester under "Allow in the Background". \
                   This window checks again by itself as soon as you come back.
                   """

        case .unreachable(let detail):
            // **The detail is not this app's prose and usually punctuates itself** — "…failed at
            // lookup with error 159 - Sandbox restriction." — and the sentence carries on after it.
            // The light render read "Sandbox restriction.. Choose Retry to ask again."; the suite
            // could not see it, since every assertion about this message is a `contains`.
            //
            // Trimmed here rather than in `diagnose(status:version:)` so that a case constructed
            // directly — by a test, or by a render fixture — is punctuated the same way as one the
            // app produced. A normalisation that only the happy path applies is a second behaviour.
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            let fragment = trimmed.hasSuffix(".") ? String(trimmed.dropLast()) : trimmed
            return """
                   The helper is installed and approved, but this app could not complete its \
                   version handshake with it: \(fragment). Choose Retry to ask again.
                   """

        case .versionMismatch(let helper, let app):
            // **One literal, not a second copy.** `ProtocolVersionCheck` already words this, and
            // already prescribes the remedy this state offers; writing it out again here is the
            // two-copies-of-one-sentence drift `ThroughputFraming` exists to end.
            return ProtocolVersionCheck.mismatch(helper: helper, app: app).description
        }
    }

    /// A symbol, so the condition is never carried by dimming or colour alone (NFR-USE-8).
    var symbolName: String {
        switch self {
        case .available:        return "checkmark.circle.fill"
        case .notFound:         return "xmark.octagon.fill"
        case .notRegistered:    return "circle.dashed"
        case .requiresApproval: return "exclamationmark.triangle.fill"
        case .unreachable:      return "bolt.horizontal.circle.fill"
        case .versionMismatch:  return "arrow.triangle.2.circlepath.circle.fill"
        }
    }

    /// The buttons, **remedy first and Quit last**.
    ///
    /// The order is the message: a dialog whose first button is Quit reads as a dead end, which is
    /// exactly what the remedy-first decision rejected.
    var actions: [HelperGateAction] {
        switch self {
        case .available:        return []
        case .notFound:         return [.quit]
        case .notRegistered:    return [.registerHelper, .quit]
        case .requiresApproval: return [.openLoginItems, .quit]
        case .unreachable:      return [.retry, .quit]
        case .versionMismatch:  return [.registerHelper, .quit]
        }
    }

    /// A short name for the log, so a route can be followed without quoting a paragraph.
    var routeName: String {
        switch self {
        case .available:        return "available"
        case .notFound:         return "notFound"
        case .notRegistered:    return "notRegistered"
        case .requiresApproval: return "requiresApproval"
        case .unreachable:      return "unreachable"
        case .versionMismatch:  return "versionMismatch"
        }
    }
}

// MARK: - What "Register Helper" has to do

/// How far the Register Helper remedy has to go to be a remedy.
///
/// **Found by walking chunk 13 item 7 on 2026-08-31**, and it is the reason this is a value rather
/// than two lines inside a `switch`. From `versionMismatch` the button did nothing: the log showed
/// `register() succeeded` and the *same* daemon (pid unchanged) answering the *same* old protocol
/// version immediately afterwards. `SMAppService.register()` on a service that is already `enabled`
/// reports success and reloads nothing — so the state whose own message reads *"Re-register the
/// helper so the installed daemon matches this app"* was the one state where re-registering could
/// not possibly do that.
///
/// The project already knew the answer and had never wired it in: `install-app.sh` has printed
/// *"(or unregister and re-register in the app's Step 3 panel)"* — the **two**-step — since Step 4.
///
/// Split out so the mapping is unit-tested. The `SMAppService` calls themselves cannot be driven
/// from a test without changing machine state, which the checklist's no-cover list records; what
/// *can* be pinned is which of them each state asks for, and that is the part that was wrong.
nonisolated enum HelperRegistrationRemedy: Equatable {

    /// Install a daemon that is not installed. `register()` alone.
    case registerOnly

    /// Replace a daemon that is installed and running the wrong code. Unregister first, wait for
    /// the removal to settle, then register — because `register()` will not reload a running one.
    case replaceRunningDaemon

    static func forGate(_ availability: HelperAvailability) -> HelperRegistrationRemedy {
        switch availability {
        case .versionMismatch:
            return .replaceRunningDaemon

        // **`notRegistered` must NOT unregister**, and that is not a stylistic choice: there is
        // nothing installed to remove, and asking anyway would spend a failed round trip and ten
        // seconds of polling before doing the thing that was always going to work.
        case .notRegistered, .available, .notFound, .requiresApproval, .unreachable:
            return .registerOnly
        }
    }
}

// MARK: - The route

/// What happened at the launch gate (NFR-OBS-1).
///
/// **This is the cover the presentation does not have.** Mutation M4 — the modal is never presented
/// at all — passes the whole suite by construction, because the wiring lives in
/// `USBDriveTesterApp.swift`, which no automated harness compiles. What a person reads instead is
/// this log: `helper gate: notRegistered` is unambiguous where "a dialog appeared" is a judgement.
nonisolated enum HelperGateLog {

    /// What the ``available`` line should say, given the state it replaced.
    ///
    /// **A pure function, and deliberately not a string built inside the `Logger` call.** The first
    /// version of this line read "available — no modal raised" on *every* arrival at ``available``,
    /// including the one where a modal had just been dismissed — so on the single transition the
    /// human checklist's chunk 13 ends on, the instrument said the opposite of what had happened
    /// (reported at the keyboard, 2026-08-27). A log line that the checklist reads its verdicts off
    /// is load-bearing, and this project's rule is that a rule living only inside a view modifier
    /// or a logging call is one nothing automated can see. Extracted so two tests can pin it.
    static func availableLine(replacing previous: HelperAvailability) -> String {
        previous.isAvailable
            ? "helper gate: available — no modal raised"
            : "helper gate: available — modal dismissed, was \(previous.routeName)"
    }

    /// The diagnosis changed. Logged on every transition, including the one into ``available``, so
    /// a launch that raised nothing is *positively* recorded rather than merely silent.
    ///
    /// - Parameter previous: what the app believed immediately before. Needed only to tell a launch
    ///   that never raised a modal from a remedy that has just cleared one; see ``availableLine``.
    static func diagnosed(_ availability: HelperAvailability,
                          replacing previous: HelperAvailability) {
        if availability.isAvailable {
            gateLog.notice("\(availableLine(replacing: previous), privacy: .public)")
        } else {
            gateLog.error("""
                          helper gate: \(availability.routeName, privacy: .public) — \
                          \(availability.message, privacy: .public)
                          """)
        }
    }

    /// A remedy started, so the gate is busy: its buttons are disabled and a spinner is up.
    static func busyBegan(_ action: HelperGateAction) {
        gateLog.notice("gate busy: \(action.rawValue, privacy: .public)")
    }

    /// The remedy finished and the gate is live again — **with how long it took**.
    ///
    /// The duration is the point. The busy window is short enough that a person watching for the
    /// buttons to grey out will miss it (2026-09-01), so "were they actually disabled, and for how
    /// long?" is a question only the log can answer.
    static func busyEnded(_ action: HelperGateAction, after start: Date?) {
        let elapsed = start.map { Int(Date().timeIntervalSince($0) * 1000) }
        gateLog.notice("""
                       gate idle: \(action.rawValue, privacy: .public) finished after \
                       \(elapsed.map(String.init) ?? "unknown", privacy: .public) ms
                       """)
    }

    /// A button on the gate was pressed.
    static func actionTaken(_ action: HelperGateAction, from availability: HelperAvailability) {
        gateLog.notice("""
                       helper gate action: \(action.rawValue, privacy: .public) \
                       from \(availability.routeName, privacy: .public)
                       """)
    }
}
