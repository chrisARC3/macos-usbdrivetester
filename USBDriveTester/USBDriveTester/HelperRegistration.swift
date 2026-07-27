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
//  Scope note: `unregister()` below is a **development affordance** for Step 3's
//  interactive gate — registration has to be undone repeatedly to re-test it. The
//  product teardown path (mid-run guard, connection draining, device release,
//  status reflection) is Step 4's deliverable, NFR-INST-3.
//

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

    /// Remove the daemon. **Development affordance only** — see the file header.
    func unregister() {
        log.notice("unregister() requested (development affordance; Step 4 productises this)")
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await service.unregister()
                lastActionMessage = "Unregistration submitted."
                log.notice("unregister() succeeded")
            } catch {
                let nsError = error as NSError
                lastActionMessage = """
                                    Unregistration failed: \(nsError.localizedDescription) \
                                    [\(nsError.domain) \(nsError.code)]
                                    """
                log.error("""
                          unregister() failed: \(nsError.domain, privacy: .public) \
                          \(nsError.code, privacy: .public) — \
                          \(nsError.localizedDescription, privacy: .public)
                          """)
            }
            // `unregister()` is asynchronous inside the system too: the status can
            // lag behind the call returning, so this reading is a first look, not a
            // settled answer (BUILD-PLAN Step 4, risks). The UI offers Refresh.
            refresh()
        }
    }

    /// Open System Settings at Login Items & Extensions so the user can approve the
    /// daemon (NFR-INST-1). The daemon appears under the *app's* name there, which
    /// is what the plist's `AssociatedBundleIdentifiers` key buys us.
    func openLoginItemsSettings() {
        log.notice("opening System Settings > Login Items & Extensions for approval")
        SMAppService.openSystemSettingsLoginItems()
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
