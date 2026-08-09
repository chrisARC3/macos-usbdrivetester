//
//  OutcomePresentationTests.swift
//  Which route a mount/unmount/acquire/release result takes to the user.
//
//  ## The defect behind this file
//
//  On 2026-08-09 the unmount rollback's error message was **correct, complete, and never seen**.
//  Not erased — the unified log showed `outcome shown (error): Could not unmount Vol_ExFAT…` with
//  no clearing line after it, ever. It was the last element inside the detail pane's `ScrollView`,
//  below the fold on a drive with several mounted volumes.
//
//  It survived four rounds of work on this control and repeated hands-on testing by the project's
//  owner, who reported it the way that settles the design question:
//
//  > *"if I missed the error message multiple times, and I'm the owner of this project, a user is
//  > also very likely to miss it"*
//
//  ## What these tests can and cannot reach
//
//  They cover the decision — **which outcomes interrupt, and what the dialog is headed**. They
//  cannot cover the dialog appearing: a SwiftUI `alert` gets its own window, which `render-ui.sh`
//  cannot capture. That limitation is why Step 10 gave the run report a `Window` scene instead of
//  a sheet, and it is recorded rather than papered over. What is achievable is that the branch
//  reaching the alert is decided somewhere a test can see, instead of inside a `body`.
//

import Testing
@testable import USBDriveTester

struct OutcomePresentationTests {

    // MARK: The rule

    /// **The requirement.** A failure must interrupt — that is the whole point of the change, and
    /// a mutation returning `.inline` for failures reproduces the original defect exactly.
    @Test func everyFailureInterrupts() {
        for operation in OutcomeOperation.allCases {
            let route = OutcomePresentation.forOutcome(ok: false, operation: operation)
            #expect(route.interrupts, "a failed \(operation) must interrupt the user")
        }
    }

    /// The other half, and it is not decoration. A modal on every success trains the user to
    /// dismiss the dialog unread, which spends the prominence precisely when it is next needed.
    @Test func noSuccessInterrupts() {
        for operation in OutcomeOperation.allCases {
            let route = OutcomePresentation.forOutcome(ok: true, operation: operation)
            #expect(!route.interrupts, "a successful \(operation) must not interrupt the user")
        }
    }

    // MARK: A successful unmount says nothing (user decision 2026-08-09)

    /// Three surfaces already report it — Finder, the standing `Mounted volumes — None mounted`
    /// row, and shortly Step 11's run itself — so a fourth is noise competing with the messages
    /// that do need reading.
    @Test func aSuccessfulUnmountIsNotReportedAtAll() {
        #expect(OutcomePresentation.forOutcome(ok: true, operation: .unmount) == .silent)
    }

    /// **The asymmetry, and it is the load-bearing half.** A successful `mountAll` can mount
    /// nothing — an unformatted drive, or a filesystem macOS cannot read — with no dissenter
    /// either way, and the standing pane shows "None mounted" for both "nothing was asked" and
    /// "everything was asked and nothing could". Its message is the only thing that separates
    /// them, so silencing it would delete the explanation rather than a duplicate of one.
    @Test func aSuccessfulMountIsStillReported() {
        #expect(OutcomePresentation.forOutcome(ok: true, operation: .mount) == .inline)
    }

    @Test func acquireAndReleaseStillReportTheirSuccesses() {
        #expect(OutcomePresentation.forOutcome(ok: true, operation: .acquire) == .inline)
        #expect(OutcomePresentation.forOutcome(ok: true, operation: .release) == .inline)
    }

    /// Silencing is a **success**-only rule. A failed unmount is the one outcome in this whole
    /// area a user must act on, and an operation-keyed exemption that leaked into the failure
    /// branch would suppress exactly it.
    @Test func aFailedUnmountIsNeverSilent() {
        let route = OutcomePresentation.forOutcome(ok: false, operation: .unmount)
        #expect(route != .silent)
        #expect(route.interrupts)
        #expect(route.showsInline)
    }

    /// Silent to the user is never silent to the log. An outcome nobody was told about and
    /// nobody recorded is the state that cost this control two extra rounds.
    @Test func aSilentOutcomeIsStillDistinguishableInTheLog() {
        let silent = OutcomePresentation.silent
        #expect(!silent.logName.isEmpty)
        #expect(silent.logName != OutcomePresentation.inline.logName)
        #expect(!silent.showsInline)
    }

    /// Success and failure must not resolve to the same route for any operation — the conjunction
    /// neither single-direction test can state. A policy that ignored `ok` entirely would satisfy
    /// one of the two tests above depending on which way it was broken.
    @Test func theTwoDirectionsNeverAgree() {
        for operation in OutcomeOperation.allCases {
            #expect(OutcomePresentation.forOutcome(ok: true, operation: operation)
                    != OutcomePresentation.forOutcome(ok: false, operation: operation))
        }
    }

    // MARK: The headline

    /// An alert's title is the one line a user reliably reads, so it must say what did not happen
    /// rather than head every failure with the same banner (NFR-USE-5).
    @Test func everyOperationHasItsOwnFailureTitle() {
        let titles = OutcomeOperation.allCases.map(\.failureTitle)
        #expect(Set(titles).count == OutcomeOperation.allCases.count)
        #expect(!titles.contains { $0.isEmpty })
    }

    @Test func theFailureTitleReachesThePresentation() {
        for operation in OutcomeOperation.allCases {
            guard case .interrupt(let title) =
                    OutcomePresentation.forOutcome(ok: false, operation: operation) else {
                Issue.record("\(operation) did not interrupt")
                continue
            }
            #expect(title == operation.failureTitle)
        }
    }

    /// A title that named the wrong operation would be worse than a generic one: it sends the user
    /// to check something that did not fail. Pinned per case rather than by a rule, because the
    /// mapping is the thing being asserted.
    @Test func titlesNameTheOperationTheyBelongTo() {
        #expect(OutcomeOperation.unmount.failureTitle.contains("unmounted"))
        #expect(OutcomeOperation.mount.failureTitle.contains("mounted"))
        #expect(OutcomeOperation.acquire.failureTitle.contains("Exclusive access"))
        #expect(OutcomeOperation.release.failureTitle.contains("released"))
    }

    // MARK: The log

    /// The route is recorded, so which path ran is recoverable after the fact rather than
    /// depending on whether somebody remembers seeing a dialog. That distinction is what took
    /// three rounds to establish for this control's *state*; it is cheaper to build in than to
    /// retrofit.
    @Test func theTwoRoutesAreDistinguishableInTheLog() {
        let quiet = OutcomePresentation.forOutcome(ok: true, operation: .unmount)
        let loud = OutcomePresentation.forOutcome(ok: false, operation: .unmount)
        #expect(quiet.logName != loud.logName)
        #expect(loud.logName.contains("alert"))
    }

    /// The inline copy is kept on both routes, so the log name for an interrupt must not read as
    /// though the message went *only* to a dialog — the text remains on screen to be re-read and
    /// text-selected after dismissal.
    @Test func theInterruptingRouteSaysItIsAlsoInline() {
        let loud = OutcomePresentation.forOutcome(ok: false, operation: .unmount)
        #expect(loud.logName.contains("inline"))
    }
}
