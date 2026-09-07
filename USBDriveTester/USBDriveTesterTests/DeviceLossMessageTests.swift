//
//  DeviceLossMessageTests.swift
//  USBDriveTesterTests
//
//  Step 12, chunk 6. The alert a lost drive raises when there is no report to raise instead.
//

import Testing
@testable import USBDriveTester

@Suite("Device-loss alert (Step 12, FR-DEV-8)")
struct DeviceLossMessageTests {

    /// Every ending, so a case added later is a failing test rather than an empty dialog.
    static let everyEnding: [DeviceLossEnding?] = [.theHelperNeverAnswered, .nothingWasInFlight, nil]

    @Test func everyEndingProducesAHeadedMessageWithABody() {
        for ending in Self.everyEnding {
            let message = DeviceLossMessage.forRunWithNoReport(endedBy: ending)
            #expect(!message.title.isEmpty, "ending=\(String(describing: ending))")
            #expect(message.text.count > 80, "ending=\(String(describing: ending))")
        }
    }

    /// **The alert renders as `Text(failure.text)` — a `String`, which SwiftUI does not parse as
    /// Markdown.** Only `LocalizedStringKey` does. So an asterisk pair that reads as emphasis in
    /// the report would be shown to the user literally, as `**this**`, in the one dialog raised on
    /// the path where the most is at stake.
    ///
    /// This is the counterpart of chunk 5's opposite defect, where the report's callout was passed
    /// `.plain` and lost the emphasis it should have had. Same fault line, both directions: **the
    /// surface decides whether Markdown is text or formatting, and the string has to know which
    /// surface it is going to.**
    @Test func noMessageCarriesMarkdownTheAlertCannotRender() {
        for ending in Self.everyEnding {
            let message = DeviceLossMessage.forRunWithNoReport(endedBy: ending)
            #expect(!message.text.contains("**"), "ending=\(String(describing: ending))")
            #expect(!message.title.contains("**"), "ending=\(String(describing: ending))")
        }
    }

    /// FR-FAIL-7, in every case: the run cannot be continued and the user is told what to do
    /// instead. A dialog that says only what went wrong leaves somebody looking for a Resume button
    /// that is deliberately not there.
    @Test func everyMessageSaysTheRunMustStartAgain() {
        for ending in Self.everyEnding {
            let text = DeviceLossMessage.forRunWithNoReport(endedBy: ending).text
            #expect(text.contains("cannot be continued"), "ending=\(String(describing: ending))")
            #expect(text.contains("beginning"), "ending=\(String(describing: ending))")
        }
    }

    /// The write-back warning, where it is owed.
    @Test func theUnansweredCaseWarnsThatAChunkMayBeHalfWritten() {
        let text = DeviceLossMessage.forRunWithNoReport(endedBy: .theHelperNeverAnswered).text
        #expect(text.contains("cannot be ruled out"))
        #expect(text.contains("partly written"))
    }

    /// **And where it is not.** Same trap as `DeviceLossAccount.nothingWasInFlight`, in the other
    /// surface: a run that was paused had nothing outstanding, and telling that user a chunk may be
    /// half-written is a false alarm — in a dialog rather than a document this time, which is
    /// worse, because a dialog is read once and believed.
    ///
    /// The case is unreachable in the app (a paused run has had the reply that settled the pause,
    /// so a report exists and this function is not called). It is pinned because it is reachable
    /// here, and because a future change that makes it reachable must not inherit a warning that
    /// was written for a different ending.
    @Test func thePausedCaseDoesNotWarnAboutAWriteBackThatCannotHaveHappened() {
        let text = DeviceLossMessage.forRunWithNoReport(endedBy: .nothingWasInFlight).text
        #expect(!text.contains("cannot be ruled out"))
        #expect(!text.contains("partly written"))
        #expect(text.contains("Nothing was being written"))
    }

    /// The claim's fate is the second fact this ending implies, and the only ending that implies
    /// it: the deadline expiring means the owning connection is still inside the call that went
    /// quiet, so the release could not be acknowledged either.
    @Test func onlyTheUnansweredCaseSaysExclusiveAccessCouldNotBeConfirmed() {
        for ending in Self.everyEnding {
            let text = DeviceLossMessage.forRunWithNoReport(endedBy: ending).text
            let saysSo = text.contains("Exclusive access could not be confirmed")
            #expect(saysSo == (ending == .theHelperNeverAnswered),
                    "ending=\(String(describing: ending))")
        }
    }

    /// The three endings read differently. Asserting each is non-empty is what a placeholder
    /// passes; asserting they are **distinct** is what catches one case falling through to
    /// another's text — which is the defect that would make the paused case warn wrongly.
    @Test func theThreeEndingsEachSaySomethingDifferent() {
        let bodies = Self.everyEnding.map { DeviceLossMessage.forRunWithNoReport(endedBy: $0).text }
        #expect(Set(bodies).count == 3)
    }

    /// The title names what happened rather than accusing the app of failing.
    ///
    /// `OutcomeOperation.failureTitle`'s rule — *say what did not happen* — does not carry here:
    /// nothing failed, a drive left. "The test could not finish" would blame the app for the cable.
    @Test func theTitleNamesTheEventRatherThanAFailedOperation() {
        #expect(DeviceLossMessage.title.contains("disconnected"))
        #expect(!DeviceLossMessage.title.lowercased().contains("could not"))
        #expect(!DeviceLossMessage.title.lowercased().contains("failed"))
    }

    /// Every case opens with the same clause, because the first thing the user needs is the same
    /// fact whichever way the run ended.
    @Test func everyMessageOpensByNamingTheDisconnection() {
        for ending in Self.everyEnding {
            let text = DeviceLossMessage.forRunWithNoReport(endedBy: ending).text
            #expect(text.hasPrefix("The drive left the USB bus part-way through the run"),
                    "ending=\(String(describing: ending))")
        }
    }

    /// No dialog on this path offers a one-click fix, and there is not one to offer: the drive is
    /// not attached, so nothing the app could open would change anything.
    @Test func theAlertOffersNoRemedyBecauseThereIsNone() {
        for ending in Self.everyEnding {
            #expect(DeviceLossMessage.forRunWithNoReport(endedBy: ending).remedy == nil,
                    "ending=\(String(describing: ending))")
        }
    }
}
