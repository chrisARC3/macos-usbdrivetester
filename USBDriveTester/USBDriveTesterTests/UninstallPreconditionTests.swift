//
//  UninstallPreconditionTests.swift
//  Exercises the Step 4 uninstall safety policy (NFR-INST-3).
//
//  The whole cross-product is covered on purpose. The policy has an intentional
//  asymmetry — refuse on a *known* active run, but proceed when the helper's state is
//  *unknown* — and an asymmetry that is not pinned down by tests is one that gets
//  "tidied up" into symmetry by a later well-meaning edit, quietly making a wedged
//  root daemon unremovable.
//

import Testing
import Foundation
@testable import USBDriveTester

struct UninstallPreconditionTests {

    // MARK: An active run blocks, whatever the helper says

    @Test func activeRunRefusesEvenWhenHelperSaysSafe() {
        let decision = UninstallPrecondition.evaluate(
            runIsActive: true,
            helperReadiness: .safeToRemove("released nothing; idle"))
        #expect(decision.isRefusal)
    }

    @Test func activeRunRefusesWhenHelperIsBusy() {
        let decision = UninstallPrecondition.evaluate(
            runIsActive: true,
            helperReadiness: .busy(reason: "verifying block 12."))
        #expect(decision.isRefusal)
    }

    @Test func activeRunRefusesWhenHelperUnknown() {
        let decision = UninstallPrecondition.evaluate(
            runIsActive: true,
            helperReadiness: .unknown(detail: "connection invalid"))
        #expect(decision.isRefusal)
    }

    /// The caller short-circuits before asking the helper when a run is active, so
    /// the default argument must also refuse.
    @Test func activeRunRefusesWithoutQueryingHelper() {
        #expect(UninstallPrecondition.evaluate(runIsActive: true).isRefusal)
    }

    @Test func activeRunRefusalNamesTheCorrectiveAction() {
        guard case .refuse(let reason) =
                UninstallPrecondition.evaluate(runIsActive: true) else {
            Issue.record("expected a refusal")
            return
        }
        #expect(reason.contains("Stop the run"))
    }

    // MARK: Idle app, helper answers

    @Test func idleAndHelperSafeProceedsWithoutWarning() {
        let decision = UninstallPrecondition.evaluate(
            runIsActive: false,
            helperReadiness: .safeToRemove("no device held; nothing to release."))
        #expect(decision == .proceed(warning: nil))
    }

    @Test func idleButHelperBusyRefuses() {
        let decision = UninstallPrecondition.evaluate(
            runIsActive: false,
            helperReadiness: .busy(reason: "a run is in progress."))
        #expect(decision.isRefusal)
    }

    /// The helper is authoritative: its refusal must survive into the message the
    /// user sees, because it is the only party that knows what it is holding.
    @Test func helperBusyReasonReachesTheUser() {
        guard case .refuse(let reason) = UninstallPrecondition.evaluate(
            runIsActive: false,
            helperReadiness: .busy(reason: "still verifying block 12.")) else {
            Issue.record("expected a refusal")
            return
        }
        #expect(reason.contains("still verifying block 12."))
    }

    // MARK: Fail-open — the load-bearing asymmetry
    //
    // If any of these start refusing, an unreachable or out-of-date privileged
    // daemon becomes impossible to uninstall.

    @Test func unknownReadinessProceeds() {
        let decision = UninstallPrecondition.evaluate(
            runIsActive: false,
            helperReadiness: .unknown(detail: "connection invalid"))
        #expect(!decision.isRefusal)
    }

    @Test func unknownReadinessProceedsWithAWarning() {
        guard case .proceed(let warning) = UninstallPrecondition.evaluate(
            runIsActive: false,
            helperReadiness: .unknown(detail: "connection invalid")) else {
            Issue.record("expected to proceed")
            return
        }
        #expect(warning != nil)
        #expect(warning?.contains("connection invalid") == true)
    }

    /// The specific scenario the protocol v1 -> v2 bump creates: an older registered
    /// daemon that does not implement `prepareForShutdown`. It must remain removable.
    @Test func outOfDateHelperRemainsRemovable() {
        let decision = UninstallPrecondition.evaluate(
            runIsActive: false,
            helperReadiness: .unknown(
                detail: "the installed helper does not implement prepareForShutdown"))
        #expect(!decision.isRefusal)
    }

    /// A helper that was never reachable at all must not strand the daemon either.
    @Test func neverQueriedHelperRemainsRemovable() {
        #expect(!UninstallPrecondition.evaluate(runIsActive: false).isRefusal)
    }

    // MARK: Exhaustive matrix
    //
    // Guards against a future case being added to HelperShutdownReadiness and
    // silently picking up the wrong default.

    @Test func fullMatrixMatchesThePolicy() {
        let readinessCases: [HelperShutdownReadiness] = [
            .safeToRemove("idle"),
            .busy(reason: "working."),
            .unknown(detail: "no answer"),
        ]

        for readiness in readinessCases {
            // Run active: always refuse.
            #expect(UninstallPrecondition.evaluate(runIsActive: true,
                                                   helperReadiness: readiness).isRefusal,
                    "an active run must block uninstall regardless of helper state")

            // Idle: refuse only when the helper positively reports it is busy.
            let idle = UninstallPrecondition.evaluate(runIsActive: false,
                                                      helperReadiness: readiness)
            if case .busy = readiness {
                #expect(idle.isRefusal, "a busy helper must block uninstall")
            } else {
                #expect(!idle.isRefusal,
                        "only a positive 'busy' may block; unknown must fail open")
            }
        }
    }

    // MARK: Message quality (NFR-USE-5)

    @Test func everyOutcomeCarriesUsableText() {
        guard case .refuse(let runReason) =
                UninstallPrecondition.evaluate(runIsActive: true) else {
            Issue.record("expected a refusal"); return
        }
        #expect(!runReason.isEmpty)

        guard case .refuse(let busyReason) = UninstallPrecondition.evaluate(
            runIsActive: false, helperReadiness: .busy(reason: "x.")) else {
            Issue.record("expected a refusal"); return
        }
        #expect(!busyReason.isEmpty)

        guard case .proceed(let warning) = UninstallPrecondition.evaluate(
            runIsActive: false, helperReadiness: .unknown(detail: "y")) else {
            Issue.record("expected to proceed"); return
        }
        #expect(warning?.isEmpty == false)
    }
}
