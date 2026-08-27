//
//  HelperAvailabilityTests.swift
//  The launch-time helper gate (Step 11, increment 9). NFR-INST-1, NFR-MAINT-1, NFR-USE-5/8.
//
//  **The table is covered in full**, for the reason `RunControlPolicyTests` and `PreRunControlsTests`
//  both give: the substance of "remedy-first, ordered by what the user must fix first" is a property
//  of the table *as a whole*, not a claim about the rows somebody happened to click. Increment 1's
//  mutation M9 blanked a disabled reason and passed all 827 tests because the check walked the
//  rendered surface rather than the table; every walk here is over `everyCase` or over all four
//  statuses.
//
//  ## What this suite provably cannot reach
//
//  That the modal is ever **presented**. The wiring lives in `USBDriveTesterApp.swift`, which no
//  automated harness compiles — mutation M4 is declared a survivor in advance for exactly that
//  reason, and the human chunk is its cover. What is pinned here is every decision the presentation
//  reads: which case, which words, which buttons, and in which order.
//
//  ## The unknown-status arm is covered, and that was a surprise
//
//  Measured 2026-08-27 rather than assumed: `SMAppService.Status(rawValue: 99)` **does** construct —
//  an `@objc` enum's raw-value initialiser admits values it does not name — and a switch missing
//  `@unknown default` both warns and traps at runtime on one. So the arm is reachable from a test
//  rather than being the declared blind spot it was about to be recorded as.
//

import Testing
import Foundation
import ServiceManagement
@testable import USBDriveTester

// MARK: - Fixtures

private enum Gate {

    /// Every case the type can be in, so a walk cannot silently miss one. Written out rather than
    /// derived: `HelperAvailability` has associated values and cannot be `CaseIterable`, and a list
    /// that has to be maintained by hand is exactly why `theWalkCoversEveryCase` exists below.
    static let everyCase: [HelperAvailability] = [
        .available,
        .notFound,
        .notRegistered,
        .requiresApproval,
        .unreachable(detail: "connection invalid"),
        .versionMismatch(helper: 11, app: 12)
    ]

    static let everyNonAvailableCase = everyCase.filter { !$0.isAvailable }

    /// The four statuses `SMAppService` names today.
    static let everyKnownStatus: [SMAppService.Status] =
        [.notRegistered, .enabled, .requiresApproval, .notFound]

    /// A transport failure of the kind `withProxy`'s error handler produces.
    static let transportFailure: Result<ProtocolVersionCheck, Error> =
        .failure(HelperConnectionError.proxyUnavailable)

    static let matching: Result<ProtocolVersionCheck, Error> =
        .success(.match(version: TesterProtocol.version))

    static let mismatching: Result<ProtocolVersionCheck, Error> =
        .success(.mismatch(helper: TesterProtocol.version - 1, app: TesterProtocol.version))
}

// MARK: - The mapping (the plan's six rows)

struct HelperAvailabilityDiagnosisTests {

    /// Row 1. The one genuinely unrepairable state: the daemon's plist is not in the bundle.
    @Test func aMissingPlistIsNotFound() {
        #expect(HelperAvailability.diagnose(status: .notFound, version: nil) == .notFound)
    }

    /// Row 2.
    @Test func anUninstalledDaemonIsNotRegistered() {
        #expect(HelperAvailability.diagnose(status: .notRegistered, version: nil) == .notRegistered)
    }

    /// Row 3.
    @Test func anUnapprovedDaemonRequiresApproval() {
        #expect(HelperAvailability.diagnose(status: .requiresApproval, version: nil)
                    == .requiresApproval)
    }

    /// Row 4. A transport error against an *enabled* daemon is the only thing that produces
    /// `unreachable` — which is the whole point of diagnosing from the status first, since the same
    /// error against a daemon that was never installed would be a wrong diagnosis.
    @Test func anEnabledDaemonThatDoesNotAnswerIsUnreachable() {
        let availability = HelperAvailability.diagnose(status: .enabled,
                                                       version: Gate.transportFailure)
        guard case .unreachable(let detail) = availability else {
            Issue.record("expected unreachable, got \(availability)")
            return
        }
        #expect(!detail.isEmpty, "the transport error's own words are what make this diagnosable")
    }

    /// Row 5. NFR-MAINT-1's handshake disagreeing.
    @Test func anEnabledDaemonOnAnotherVersionIsAMismatch() {
        #expect(HelperAvailability.diagnose(status: .enabled, version: Gate.mismatching)
                    == .versionMismatch(helper: TesterProtocol.version - 1,
                                        app: TesterProtocol.version))
    }

    /// Row 6. The only combination that raises nothing.
    @Test func anEnabledDaemonOnThisVersionIsAvailable() {
        #expect(HelperAvailability.diagnose(status: .enabled, version: Gate.matching) == .available)
    }

    /// **The interval the plan's table does not have a row for.** Between reading the status and the
    /// handshake returning, something has to be true — and reporting a problem there would put a
    /// modal on screen for a fraction of a second on every healthy launch.
    @Test func anEnabledDaemonWithNoAnswerYetIsAvailable() {
        #expect(HelperAvailability.diagnose(status: .enabled, version: nil) == .available)
    }

    /// **The status is resolved before the version, and this is what pins the order.** Mutation M3
    /// reorders the table; without this test a version answer left over from an earlier check could
    /// outrank a daemon that is not installed at all — telling the user to re-register something
    /// that was never registered.
    @Test func theStatusIsResolvedBeforeTheVersion() {
        for status in Gate.everyKnownStatus where status != .enabled {
            let expected = HelperAvailability.diagnose(status: status, version: nil)
            #expect(HelperAvailability.diagnose(status: status, version: Gate.mismatching) == expected,
                    "status=\(status.rawValue)")
            #expect(HelperAvailability.diagnose(status: status, version: Gate.matching) == expected,
                    "status=\(status.rawValue)")
            #expect(HelperAvailability.diagnose(status: status, version: Gate.transportFailure)
                        == expected, "status=\(status.rawValue)")
        }
    }

    /// Every known status maps somewhere, and only `.enabled` can reach `available`.
    @Test func onlyAnEnabledDaemonCanBeAvailable() {
        for status in Gate.everyKnownStatus {
            let availability = HelperAvailability.diagnose(status: status, version: Gate.matching)
            #expect(availability.isAvailable == (status == .enabled), "status=\(status.rawValue)")
        }
    }

    /// **The `@unknown default` arm, driven for real.** `SMAppService.Status(rawValue: 99)`
    /// constructs — measured 2026-08-27 — so this is a test rather than a comment about a hole.
    ///
    /// It maps to `unreachable` rather than to a seventh case: a case for a status Apple has not
    /// shipped would be a mechanism behind a trigger that never fires. Retry is the honest remedy,
    /// because it re-reads the status.
    @Test func anUnrecognisedStatusIsReportedRatherThanTrusted() {
        guard let unknown = SMAppService.Status(rawValue: 99) else {
            Issue.record("""
                         SMAppService.Status(rawValue: 99) no longer constructs — the unknown arm \
                         has become unreachable and this test can no longer cover it
                         """)
            return
        }
        let availability = HelperAvailability.diagnose(status: unknown, version: nil)

        guard case .unreachable(let detail) = availability else {
            Issue.record("expected unreachable, got \(availability)")
            return
        }
        #expect(detail.contains("99"), "the raw value is what makes it diagnosable: \(detail)")
        #expect(availability.actions == [.retry, .quit])
    }
}

// MARK: - What the gate offers (the remedy-first decision, 2026-08-26)

struct HelperGateActionTests {

    /// The walk's own guard. `HelperAvailability` cannot be `CaseIterable`, so `Gate.everyCase` is
    /// maintained by hand — and a hand-maintained list of cases is the drift `render-ui.sh`'s view
    /// list has suffered three times. This is the cheap check that it still covers the type: every
    /// case must produce a distinct `routeName`, and there must be one per name the type knows.
    @Test func theWalkCoversEveryCase() {
        let names = Set(Gate.everyCase.map(\.routeName))
        #expect(names == ["available", "notFound", "notRegistered",
                          "requiresApproval", "unreachable", "versionMismatch"])
        #expect(names.count == Gate.everyCase.count, "two entries share a route name")
    }

    /// **A user who cannot fix the problem must still be able to put the app down.**
    @Test func everyNonAvailableCaseOffersQuit() {
        for availability in Gate.everyNonAvailableCase {
            #expect(availability.actions.contains(.quit), "case=\(availability.routeName)")
        }
    }

    /// **Only `notFound` is Quit-only** — the decision of 2026-08-26, and the one this suite exists
    /// to stop being re-derived. A Quit-only modal anywhere else produces *quit → relaunch → same
    /// modal → quit*, with the dialog's own text naming a remedy the dialog prevents reaching.
    @Test func onlyAMissingPlistIsQuitOnly() {
        for availability in Gate.everyNonAvailableCase {
            let isQuitOnly = availability.actions == [.quit]
            #expect(isQuitOnly == (availability == .notFound), "case=\(availability.routeName)")
        }
    }

    /// The healthy state offers nothing, because nothing is shown.
    @Test func theAvailableCaseOffersNothing() {
        #expect(HelperAvailability.available.actions.isEmpty)
    }

    /// **Remedy first, Quit last.** The order is the message: a dialog whose first button is Quit
    /// reads as a dead end.
    @Test func remediesComeBeforeQuit() {
        for availability in Gate.everyNonAvailableCase {
            let actions = availability.actions
            // Hoisted out of `#expect`: `allSatisfy` is `rethrows`, and inside the macro's
            // expansion the key-path form is not proven non-throwing.
            let everyOtherActionIsARemedy = actions.dropLast().allSatisfy { $0.isRemedy }
            #expect(actions.last == .quit, "case=\(availability.routeName) actions=\(actions)")
            #expect(everyOtherActionIsARemedy,
                    "case=\(availability.routeName) actions=\(actions)")
        }
    }

    /// No case offers the same button twice — which would render as two identical buttons doing the
    /// same thing.
    @Test func noCaseRepeatsAnAction() {
        for availability in Gate.everyCase {
            #expect(Set(availability.actions).count == availability.actions.count,
                    "case=\(availability.routeName)")
        }
    }

    /// A version mismatch is **not** Quit-only, and the remedy is the one this project's own wording
    /// already prescribes. Asserted on its own because it is the row most likely to be argued back
    /// to Quit-only: the app looks broken, and re-registering looks like a developer's fix.
    @Test func aVersionMismatchOffersReRegistration() {
        #expect(HelperAvailability.versionMismatch(helper: 11, app: 12).actions
                    == [.registerHelper, .quit])
    }

    /// Every button says something. `label` feeding a `Button` means an empty one is a button a user
    /// cannot identify — dimming is not a message, and neither is a blank.
    @Test func everyActionHasALabel() {
        for action in HelperGateAction.allCases {
            #expect(action.label.count >= 4, "action=\(action.rawValue)")
        }
    }

    /// Quit is the only non-remedy. `isRemedy` decides which button is emphasised, so an inversion
    /// here would make Quit the prominent control on every state — the dead-end reading the
    /// remedy-first decision rejected.
    @Test func quitIsTheOnlyActionThatIsNotARemedy() {
        for action in HelperGateAction.allCases {
            #expect(action.isRemedy == (action != .quit), "action=\(action.rawValue)")
        }
    }
}

// MARK: - What it says (NFR-USE-5, Mandatory)

struct HelperGateMessageTests {

    /// **Dimming is not a message, and neither is a heading with nothing under it.** Walked over the
    /// whole table rather than over the cases a view happens to render — the shape M9 taught.
    @Test func everyNonAvailableCaseIsASentence() {
        for availability in Gate.everyNonAvailableCase {
            #expect(availability.title.count >= 20, "case=\(availability.routeName)")
            #expect(availability.title.hasSuffix("."), "case=\(availability.routeName)")
            #expect(availability.message.count >= 40, "case=\(availability.routeName)")
            #expect(availability.message.hasSuffix("."), "case=\(availability.routeName)")
        }
    }

    /// **NFR-USE-5 is Mandatory and requires the corrective step, not only the cause.** Every state
    /// that offers a remedy must name it in its own words, so a user reading the paragraph and a
    /// user reading the buttons are told the same thing.
    ///
    /// Matched on ``HelperGateAction/messageStem`` rather than on the button's label, and that is
    /// **the check having failed once and been corrected rather than a hole left open**: this
    /// demanded the literal "Register Helper" and met `ProtocolVersionCheck`'s own *"Re-register the
    /// helper…"*. Insisting on the label would have forced a second copy of that sentence, which is
    /// the drift the mismatch message is deliberately not making. The stem still discriminates — a
    /// message naming no remedy, or the wrong one, fails.
    @Test func everyRemedyIsNamedInItsOwnMessage() {
        for availability in Gate.everyNonAvailableCase {
            guard let remedy = availability.actions.first(where: { $0.isRemedy }) else { continue }
            #expect(availability.message.lowercased().contains(remedy.messageStem),
                    """
                    case=\(availability.routeName) wanted "\(remedy.messageStem)" \
                    in: \(availability.message)
                    """)
        }
    }

    /// And the stem is not vacuous: no remedy's stem appears in a message that does **not** offer
    /// it. Without this, a stem of `""` — or one so common every sentence contains it — would make
    /// the check above pass on any wording at all. The same "show it answering both ways" rule the
    /// device-operation slot check was built on.
    @Test func aMessageDoesNotNameARemedyItDoesNotOffer() {
        for availability in Gate.everyNonAvailableCase {
            let offered = Set(availability.actions)
            for action in HelperGateAction.allCases
            where action.isRemedy && !offered.contains(action) {
                #expect(!availability.message.lowercased().contains(action.messageStem),
                        """
                        case=\(availability.routeName) names "\(action.messageStem)" \
                        but does not offer it
                        """)
            }
        }
    }

    /// **The Quit-only case still has to say what to do.** It has no in-app remedy to name, which is
    /// exactly why it is the one at risk of being left with a cause and no cure.
    @Test func theQuitOnlyCaseStillNamesACorrectiveStep() {
        let message = HelperAvailability.notFound.message.lowercased()
        #expect(message.contains("reinstall"))
        // It also has to say what is missing, or "reinstall" is advice with no diagnosis behind it.
        // **Not the plist's filename**: reading `HelperIdentity.daemonPlistName` from a nonisolated
        // context would mean marking a `Shared/` type nonisolated, which moves the helper source
        // hash — see the comment at that message. The window that does name the file is pointed at
        // instead, and it is reachable from behind the gate.
        #expect(message.contains("launchd property list"))
        #expect(HelperAvailability.notFound.message.contains("⇧⌘D"),
                "the one state with no in-app remedy must still point somewhere")
    }

    /// A transport error's own words reach the user. Without this the modal would say "it did not
    /// answer" and discard the only sentence that says why.
    @Test func theUnreachableMessageCarriesTheTransportError() {
        let detail = "The connection to service was invalidated"
        #expect(HelperAvailability.unreachable(detail: detail).message.contains(detail))
    }

    /// **The detail punctuates itself, and the sentence carries on after it.**
    ///
    /// Found by looking at a render, not by this suite — the light `helper-gate-unreachable` capture
    /// read *"Sandbox restriction.. Choose Retry to ask again."* Every other assertion about this
    /// message is a `contains`, and a `contains` cannot see a doubled full stop. Written down here
    /// so the next edit to the wording has to keep it.
    @Test func theUnreachableMessageDoesNotDoubleThePunctuation() {
        for detail in ["Sandbox restriction.", "Sandbox restriction", "Sandbox restriction.  ",
                       "Sandbox restriction.\n"] {
            let message = HelperAvailability.unreachable(detail: detail).message
            #expect(!message.contains(".."), "detail=\(detail) message=\(message)")
            #expect(message.contains("Sandbox restriction. Choose Retry"),
                    "detail=\(detail) message=\(message)")
        }
    }

    /// **No ellipsis mid-sentence**, though the button that opens System Settings carries one.
    /// "Choose Open Login Items…, enable…" put an ellipsis immediately before a comma. Also a render
    /// finding: `messageStem` matches "login items" with or without it, so the suite was blind.
    @Test func noMessageCarriesAButtonsEllipsisIntoItsProse() {
        for availability in Gate.everyNonAvailableCase {
            #expect(!availability.message.contains("…"),
                    "case=\(availability.routeName) message=\(availability.message)")
        }
    }

    /// **One literal, not a second copy.** The mismatch wording — and the remedy it prescribes —
    /// already exists on `ProtocolVersionCheck`, which is what the diagnostics window shows. Two
    /// copies of one sentence is the drift `ThroughputFraming` was written to end, found there after
    /// it had already happened within a day.
    @Test func theMismatchMessageIsTheOneTheProtocolAlreadyStates() {
        #expect(HelperAvailability.versionMismatch(helper: 11, app: 12).message
                    == ProtocolVersionCheck.mismatch(helper: 11, app: 12).description)
    }

    /// Both version numbers reach the screen. A mismatch naming only one of them cannot be acted on:
    /// the user needs to know which side is behind.
    @Test func theMismatchMessageNamesBothVersions() {
        let message = HelperAvailability.versionMismatch(helper: 11, app: 12).message
        #expect(message.contains("11"))
        #expect(message.contains("12"))
    }

    /// The healthy state says nothing, because nothing is shown. An empty string here is correct
    /// rather than missing — but it must be asserted, or "the modal shows a blank" and "the modal is
    /// not shown" become indistinguishable in a render.
    @Test func theAvailableCaseSaysNothing() {
        #expect(HelperAvailability.available.title.isEmpty)
        #expect(HelperAvailability.available.message.isEmpty)
    }

    /// **Never colour alone** (NFR-USE-8). Every case carries a symbol, and no two conditions share
    /// one — a glyph that means two things carries nothing.
    @Test func everyCaseHasItsOwnSymbol() {
        let symbols = Gate.everyCase.map(\.symbolName)
        let everySymbolIsNamed = symbols.allSatisfy { !$0.isEmpty }
        #expect(everySymbolIsNamed)
        #expect(Set(symbols).count == symbols.count, "two cases share a symbol: \(symbols)")
    }
}
