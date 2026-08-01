//
//  HelperRegistration.swift
//  USBDriveTester (app target — unprivileged)
//
//  Owns the `SMAppService` lifecycle of the privileged LaunchDaemon (FR-ARCH-3,
//  NFR-SEC-5) and reports its status clearly, including guiding the user through the
//  System Settings approval when one is required (NFR-INST-1).
//
//  Registering a daemon does NOT elevate this process. The app stays unprivileged
//  for its whole life (FR-ARCH-2, NFR-SEC-1); it asks launchd to install a daemon,
//  and the user authorises that in System Settings. Nothing here runs as root.
//
//  Both ends of the lifecycle live here: `register()` (Step 3, FR-ARCH-3) and
//  `uninstall(using:runIsActive:)` (Step 4, NFR-INST-3) — installation and removal
//  are two halves of one problem and drift apart when kept in separate places.
//

import AppKit
import Foundation
import Observation
import ServiceManagement
import os

private let log = Logger(subsystem: HelperIdentity.loggingSubsystem, category: "lifecycle")

@MainActor
@Observable
final class HelperRegistration {

    /// The daemon as `SMAppService` sees it. The plist name must match the file in
    /// `Contents/Library/LaunchDaemons/` exactly; a mismatch is the single most
    /// common cause of a permanent `.notFound`, which is why the name is derived
    /// from ``HelperIdentity`` rather than written out here.
    private let service = SMAppService.daemon(plistName: HelperIdentity.daemonPlistName)

    /// Last status read from the system. Refreshed explicitly, never cached across
    /// an action — `SMAppService.status` is a live query.
    private(set) var status: SMAppService.Status

    /// Human-readable result of the last action taken, shown verbatim in the UI.
    private(set) var lastActionMessage: String = "No action taken yet."

    /// True while an async action is in flight, so the UI can disable its controls.
    private(set) var isBusy = false

    init() {
        let initialStatus = service.status
        status = initialStatus
        // Bound to a local rather than read through `self`: the Logger interpolation
        // is an autoclosure, so touching `self.service` here would capture self.
        let statusName = Self.name(for: initialStatus)
        log.notice("""
                   registration manager initialised; daemon \
                   \(HelperIdentity.daemonPlistName, privacy: .public) status \
                   \(statusName, privacy: .public)
                   """)
    }

    // MARK: - Actions

    /// Re-read the daemon's status from the system.
    func refresh() {
        let previous = status
        status = service.status
        if previous != status {
            log.notice("""
                       daemon status changed \(Self.name(for: previous), privacy: .public) -> \
                       \(Self.name(for: self.status), privacy: .public)
                       """)
        }
    }

    /// Install the daemon (FR-ARCH-3).
    ///
    /// ## Why a thrown error is not necessarily a failure
    ///
    /// On a first registration `SMAppService.register()` throws
    /// `SMAppServiceErrorDomain` code 1 — "Operation not permitted" — *even though the
    /// daemon is successfully submitted*, because it cannot be enabled until the user
    /// approves it. The status transitions `notFound -> requiresApproval` regardless.
    /// Observed on macOS 26 on 2026-07-27.
    ///
    /// Reporting that verbatim would tell the user registration failed at precisely
    /// the moment they need to be sent to System Settings to approve it — the opposite
    /// of the guidance NFR-INST-1 requires. So the *resulting status* is the source of
    /// truth for the message, and the thrown error is only surfaced when the status
    /// agrees that something actually went wrong.
    func register() {
        log.notice("register() requested for \(HelperIdentity.daemonPlistName, privacy: .public)")

        var thrown: NSError?
        do {
            try service.register()
        } catch {
            thrown = error as NSError
        }
        refresh()

        switch (thrown, status) {
        case (_, .requiresApproval):
            lastActionMessage = """
                                The helper was installed and now needs your approval. Choose \
                                "Open Login Items…", enable this app under "Allow in the \
                                Background", then choose Refresh.
                                """
            log.notice("register() submitted; awaiting user approval")

        case (nil, _):
            lastActionMessage = "Registration submitted."
            log.notice("register() succeeded")

        case (let error?, _):
            lastActionMessage = """
                                Registration failed: \(error.localizedDescription) \
                                [\(error.domain) \(error.code)]
                                """
            log.error("""
                      register() failed: \(error.domain, privacy: .public) \
                      \(error.code, privacy: .public) — \
                      \(error.localizedDescription, privacy: .public)
                      """)
        }
    }

    /// Fully remove the privileged helper (NFR-INST-3, NFR-SEC-5).
    ///
    /// The sequence, in this order for a reason:
    ///
    ///   1. **App-side guard.** If a run is active, refuse immediately — no XPC round
    ///      trip is needed to know the answer.
    ///   2. **Ask the helper.** It is the authority on whether it holds a device, and
    ///      this is what makes it release one (NFR-REL-5). Failure here means
    ///      *unknown*, not unsafe — see ``UninstallPrecondition``.
    ///   3. **Drain the connection** before removing the daemon it points at, so the
    ///      app is not left holding a connection to a service that no longer exists.
    ///   4. **Unregister, then poll** — see ``performUnregister(warning:)``.
    ///
    /// - Parameters:
    ///   - connection: The live XPC connection, needed for steps 2 and 3.
    ///   - runIsActive: The app's view of run state. Simulated in Step 4; driven by
    ///     the run-control state machine from Step 11.
    func uninstall(using connection: HelperConnection, runIsActive: Bool) {
        log.notice("uninstall requested (runIsActive=\(runIsActive, privacy: .public))")

        // 1. Cheap, local refusal first.
        if runIsActive, case .refuse(let reason) = UninstallPrecondition.evaluate(runIsActive: true) {
            lastActionMessage = reason
            log.notice("uninstall refused: a run is active")
            return
        }

        isBusy = true

        // 2. The helper decides whether it is safe.
        connection.prepareForShutdown { [weak self] readiness in
            guard let self else { return }

            switch UninstallPrecondition.evaluate(runIsActive: runIsActive,
                                                  helperReadiness: readiness) {
            case .refuse(let reason):
                self.lastActionMessage = reason
                self.isBusy = false
                log.notice("uninstall refused by the helper: \(reason, privacy: .public)")

            case .proceed(let warning):
                if let warning {
                    log.notice("uninstall proceeding without confirmation: \(warning, privacy: .public)")
                } else {
                    log.notice("helper confirmed it is idle; proceeding with uninstall")
                }
                // 3. Drain before removing.
                connection.invalidate()
                // 4. Remove.
                self.performUnregister(warning: warning)
            }
        }
    }

    /// Unregister and then **poll** until the status actually settles.
    ///
    /// Two behaviours make polling necessary rather than tidy. `unregister()` is
    /// asynchronous inside the system, so the status lags the call returning
    /// (BUILD-PLAN Step 4, risks). And — as `register()` already demonstrated in
    /// Step 3 — `SMAppService` can report an error for an operation that nonetheless
    /// takes effect, so the settled status is more trustworthy than the thrown error.
    /// The error is therefore kept and reported only if removal genuinely did not
    /// happen.
    private func performUnregister(warning: String?) {
        Task {
            defer { isBusy = false }

            var thrown: NSError?
            do {
                try await service.unregister()
                log.notice("unregister() returned without error")
            } catch {
                thrown = error as NSError
                log.error("""
                          unregister() reported: \(thrown!.domain, privacy: .public) \
                          \(thrown!.code, privacy: .public) — \
                          \(thrown!.localizedDescription, privacy: .public) \
                          (polling status to see whether it took effect anyway)
                          """)
            }

            let removed = await pollUntilNotRegistered(timeout: 10)
            let prefix = warning.map { "\($0)\n\n" } ?? ""

            if removed {
                lastActionMessage = prefix + "The helper was removed. Status is now notRegistered."
                log.notice("uninstall complete; status notRegistered")
            } else if let thrown {
                lastActionMessage = prefix + """
                                    Removal failed: \(thrown.localizedDescription) \
                                    [\(thrown.domain) \(thrown.code)]. Status is \(statusName).
                                    """
                log.error("uninstall failed; status \(self.statusName, privacy: .public)")
            } else {
                lastActionMessage = prefix + """
                                    Removal was submitted but the status is still \(statusName) \
                                    after 10s. Choose Refresh in a moment.
                                    """
                log.error("""
                          uninstall did not settle within 10s; status \
                          \(self.statusName, privacy: .public)
                          """)
            }
        }
    }

    /// Poll `.status` until the daemon is gone or the timeout expires.
    /// - Returns: whether the status reached `.notRegistered`.
    private func pollUntilNotRegistered(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            refresh()
            if status == .notRegistered { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        refresh()
        return status == .notRegistered
    }

    /// Open System Settings at Login Items & Extensions so the user can approve the
    /// daemon (NFR-INST-1). The daemon appears under the *app's* name there, which
    /// is what the plist's `AssociatedBundleIdentifiers` key buys us.
    func openLoginItemsSettings() {
        log.notice("opening System Settings > Login Items & Extensions for approval")
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Open System Settings at Privacy & Security › Full Disk Access (NFR-INST-4).
    ///
    /// A different pane from the one above, and a different permission: Login Items
    /// approves the *daemon*, Full Disk Access is what lets it open a raw device at all.
    /// Both are required, neither implies the other, and being sent to the wrong one is a
    /// dead end — so they are separate actions rather than one "Open Settings" button.
    ///
    /// There is no `SMAppService`-style API for this pane, so it is a URL. It is a
    /// documented, long-standing one, but it is still a string that could stop working on
    /// a future macOS — hence the failure is logged rather than ignored, and the message
    /// the user sees always names the path in words as well.
    static func openFullDiskAccessSettings() {
        let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        guard let url = URL(string: pane) else { return }
        if !NSWorkspace.shared.open(url) {
            log.error("""
                      could not open the Full Disk Access pane; the user must navigate to \
                      System Settings > Privacy & Security > Full Disk Access manually
                      """)
        }
    }

    // MARK: - Presentation

    /// Whether the user must approve the daemon in System Settings before it runs.
    var needsApproval: Bool { status == .requiresApproval }

    /// Whether the daemon is installed, approved, and expected to answer XPC.
    var isEnabled: Bool { status == .enabled }

    var statusName: String { Self.name(for: status) }

    /// What the current status means and what to do about it. Status alone is not
    /// actionable — `.notFound` in particular reads as a bug in the app when it is
    /// almost always a build-configuration mismatch.
    var statusExplanation: String {
        switch status {
        case .notRegistered:
            return "The daemon is not installed. Choose Register helper to install it."
        case .enabled:
            return "The daemon is installed and approved. It should answer XPC requests."
        case .requiresApproval:
            return """
                   The daemon is installed but is waiting for your approval. Open Login Items \
                   & Extensions and enable it under this app's name, then choose Refresh.
                   """
        case .notFound:
            return """
                   The system cannot find the daemon's plist in this app bundle. Check that \
                   Contents/Library/LaunchDaemons/\(HelperIdentity.daemonPlistName) is embedded \
                   and that its Label matches the file name.
                   """
        @unknown default:
            return "Unrecognised status. Choose Refresh."
        }
    }

    /// Status conveyed by symbol as well as text — never colour alone (NFR-USE-8).
    var statusSymbolName: String {
        switch status {
        case .enabled:          return "checkmark.circle.fill"
        case .requiresApproval: return "exclamationmark.triangle.fill"
        case .notRegistered:    return "circle.dashed"
        case .notFound:         return "xmark.octagon.fill"
        @unknown default:       return "questionmark.circle"
        }
    }

    /// Where this app is running from.
    var bundlePath: String { Bundle.main.bundlePath }

    /// `SMAppService` records the *path* of the app that registered the daemon. A
    /// DerivedData path is rebuilt and replaced constantly, which strands the
    /// registration pointing at a binary that no longer exists — the classic
    /// symptom being a status that will not move off `.notFound` or
    /// `.requiresApproval` no matter how often you re-register. Running from
    /// /Applications keeps the path stable across rebuilds.
    var locationWarning: String? {
        guard !bundlePath.hasPrefix("/Applications/") else { return nil }
        return """
               Running from a temporary build location. SMAppService remembers the registering \
               app's path, so rebuilding can strand the registration here. Use \
               scripts/install-app.sh and run from /Applications for a stable test loop.
               """
    }

    private static func name(for status: SMAppService.Status) -> String {
        switch status {
        case .notRegistered:    return "notRegistered"
        case .enabled:          return "enabled"
        case .requiresApproval: return "requiresApproval"
        case .notFound:         return "notFound"
        @unknown default:       return "unknown(\(status.rawValue))"
        }
    }
}
