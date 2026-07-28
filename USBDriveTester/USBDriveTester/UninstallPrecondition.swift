//
//  UninstallPrecondition.swift
//  USBDriveTester (app target — unprivileged)
//
//  Decides whether the privileged helper may be removed right now (NFR-INST-3).
//
//  Split out as a pure, side-effect-free decision so the policy can be unit-tested
//  exhaustively without an installed daemon, a live XPC connection, or any GUI. The
//  policy is small but it is a *safety* policy, and safety policies that live inline
//  in a button handler are the ones that quietly acquire a fifth branch nobody tested.
//
//  ## The policy, and why it leans the way it does
//
//  Two failure modes are in tension:
//
//    A. Removing the helper while it is mid-run — risking a half-written device and
//       a stranded DiskArbitration claim (NFR-REL-5).
//    B. Being unable to remove the helper because it is wedged, unreachable, or an
//       older build that does not implement the teardown handshake.
//
//  (A) is guarded by refusing when a run is *known* to be active. (B) is guarded by
//  treating "we could not get an answer" as **permission to proceed**, with a warning
//  — never as a refusal. A privileged root daemon that cannot be uninstalled is a
//  worse place to leave the user than the risk of tearing down an idle helper we
//  could not reach. This asymmetry is deliberate; see the decision record in
//  PROGRESS.md, Step 4.
//

import Foundation

/// What the helper told us when asked whether it is safe to remove.
///
/// Note the deliberate absence of a "definitely unsafe because we could not ask"
/// case: not knowing is ``unknown``, and unknown does not block (see the file
/// header).
enum HelperShutdownReadiness: Equatable {

    /// The helper answered and has released everything it held.
    case safeToRemove(String)

    /// The helper answered and is still doing something that must not be interrupted.
    /// This is the **authoritative** refusal — the helper, not the GUI, is the process
    /// actually holding the device.
    case busy(reason: String)

    /// No usable answer: the call failed, the helper is unreachable, it is an older
    /// build without `prepareForShutdown`, or it was never queried. Carries a
    /// human-readable detail for the warning shown to the user.
    case unknown(detail: String)
}

/// The verdict.
enum UninstallDecision: Equatable {

    /// Removal may go ahead. `warning` is non-nil when we are proceeding *despite*
    /// not having confirmation from the helper, and must be surfaced to the user
    /// rather than swallowed.
    case proceed(warning: String?)

    /// Removal is refused. `reason` names the actual cause and the corrective action
    /// (NFR-USE-5).
    case refuse(reason: String)

    var isRefusal: Bool { if case .refuse = self { return true } else { return false } }
}

enum UninstallPrecondition {

    /// Evaluate whether the helper may be removed.
    ///
    /// - Parameters:
    ///   - runIsActive: The app's own view of whether a test run is in progress. In
    ///     Step 4 this is a simulated toggle; from Step 11 it is driven by the run
    ///     state machine. Checked first so an obviously-blocked uninstall costs no
    ///     XPC round-trip.
    ///   - helperReadiness: What the helper said. Defaults to ``HelperShutdownReadiness/unknown(detail:)``
    ///     so a caller that short-circuited before asking does not have to fabricate
    ///     an answer.
    nonisolated static func evaluate(
        runIsActive: Bool,
        helperReadiness: HelperShutdownReadiness =
            .unknown(detail: "the helper was not queried")
    ) -> UninstallDecision {

        // The GUI's own run state blocks first. It is not authoritative — it lives in
        // a process the user can force-quit — but when it *does* say a run is active,
        // that is reason enough to stop, and it saves a pointless XPC call.
        if runIsActive {
            return .refuse(reason: """
                                  A test run is active. Stop the run before removing the helper, \
                                  so the device is released cleanly.
                                  """)
        }

        switch helperReadiness {
        case .busy(let reason):
            // The helper is the authority: it is the process holding the device node
            // and the DiskArbitration claim.
            return .refuse(reason: """
                                   The helper reports it is still working: \(reason) \
                                   Wait for it to finish, then try again.
                                   """)

        case .safeToRemove:
            return .proceed(warning: nil)

        case .unknown(let detail):
            // Fail open — see the file header. The warning is mandatory, not
            // cosmetic: the user is entitled to know the removal went ahead without
            // confirmation.
            return .proceed(warning: """
                                     Could not confirm with the helper that it is idle (\(detail)). \
                                     Removing it anyway so a helper that is unreachable or out of \
                                     date does not become impossible to remove.
                                     """)
        }
    }
}
