//
//  HonestFramingTests.swift
//  The one wording of what this tool proves and does not prove (FR-WARN-1/2/3/4, NFR-USE-6).
//
//  ## The defect behind this file
//
//  Before `HonestFraming` existed there were two copies of this text — the exported Markdown report
//  and the result screen — written in the same increment, and on 2026-08-10 they were found to have
//  **already drifted**. The screen's version of the verify claim had lost the clause that explains
//  why a matching verify does not prove retention, and the dual-role opener had been reworded.
//  Nothing failed: `RunReportTests` asserts the Markdown contains "degrading but still correctable"
//  and never looks at the view, so there was no test in a position to notice.
//
//  Step 14 was about to add a third copy for the pre-run dialog.
//
//  These tests therefore guard something narrower and more useful than "the text is right": they
//  guard that **there is only one text**. A renderer that re-inlines a sentence is the mutation
//  they exist to catch, because that is the mutation that actually happened.
//

import Foundation
import Testing
@testable import USBDriveTester

struct HonestFramingTests {

    // MARK: - The claim type

    /// Emphasis is decoration; removing it must not remove words. A `plain` that dropped anything
    /// else would let a SwiftUI surface be quietly weaker than the exported file, which is the
    /// original defect with a different mechanism.
    @Test func plainDiffersFromMarkdownOnlyByTheEmphasisMarkers() {
        for claim in HonestFraming.claims + [HonestFraming.summary,
                                             HonestFraming.rangeBeyondTheFailureWasNotTested] {
            #expect(claim.plain == claim.markdown.replacingOccurrences(of: "**", with: ""))
            #expect(!claim.plain.contains("*"), "emphasis leaked into a plain-text surface")
        }
    }

    /// An odd number of markers renders as literal asterisks in the report and swallows a phrase on
    /// screen — a typo that no reader of the source would see, in the product's central claim.
    @Test func everyClaimHasBalancedEmphasis() {
        for claim in allClaims() {
            let markers = claim.markdown.components(separatedBy: "**").count - 1
            #expect(markers % 2 == 0, "unbalanced emphasis in: \(claim.markdown)")
            #expect(markers > 0, "a claim with no emphasis at all: \(claim.markdown)")
        }
    }

    // MARK: - There is only one text

    /// **The requirement this file exists for.** Every claim shown on the result screen and in the
    /// pre-run dialog must be the *same object* the report renders — not an equal-looking literal.
    /// A renderer that re-inlines the sentence fails here.
    @Test func theReportRendersTheSharedClaimsRatherThanItsOwnLiterals() {
        let document = RunReportMarkdown.render(Fixture.cleanReport(), timeZone: Fixture.utc)
        for claim in HonestFraming.claims {
            #expect(document.contains(claim.markdown),
                    "the report no longer renders the shared wording of: \(claim.plain.prefix(48))")
        }
        #expect(document.contains(HonestFraming.summary.markdown))
    }

    /// The clause the result screen had lost. Named as its own test because it is the specific
    /// sentence that went missing, and a regression that drops it again should say so by name
    /// rather than by a generic containment failure.
    @Test func theVerifyClaimStillExplainsWhyARoundTripIsNotRetention() {
        let claim = HonestFraming.verifyProvesRoundTripNotRetention
        #expect(claim.plain.contains("the drive's own cache sits below every check a host can make"))
    }

    /// The conditional claim belongs to the report surfaces only — it says "the failure above", and
    /// there is no "above" in a dialog shown before the run starts. A mutation adding it to
    /// ``HonestFraming/claims`` would put that sentence in the pre-run dialog.
    @Test func theStoppedRunClaimIsNotShownOnEverySurface() {
        #expect(!HonestFraming.claims.contains(HonestFraming.rangeBeyondTheFailureWasNotTested))
    }

    /// It must still reach the report when a run did stop on an error — the other half, so a
    /// mutation that simply deletes it is caught rather than passing the test above.
    @Test func theStoppedRunClaimReachesAReportThatStoppedOnAnError() {
        let stopped = RunReportMarkdown.render(Fixture.stoppedOnErrorReport(), timeZone: Fixture.utc)
        #expect(stopped.contains(HonestFraming.rangeBeyondTheFailureWasNotTested.markdown))

        let clean = RunReportMarkdown.render(Fixture.cleanReport(), timeZone: Fixture.utc)
        #expect(!clean.contains(HonestFraming.rangeBeyondTheFailureWasNotTested.markdown),
                "a clean run has no failure for a range to lie beyond")
    }

    // MARK: - The three mandatory warnings

    /// Asserted **by requirement**, not by counting three of something: a mutation that drops one
    /// warning and duplicates another keeps the count and is caught here.
    @Test func allThreeMandatoryWarningsArePresent() {
        let requirements = PreRunWarningText.mandatory.map(\.requirement)
        #expect(requirements == ["FR-WARN-1", "FR-WARN-2", "FR-WARN-3"])
    }

    @Test func everyWarningHasATitleAndSomethingToSay() {
        for warning in PreRunWarningText.mandatory {
            #expect(!warning.title.isEmpty, "\(warning.requirement) has no title")
            #expect(!warning.points.isEmpty, "\(warning.requirement) has no body")
            for point in warning.points {
                #expect(!point.plain.isEmpty)
            }
        }
    }

    /// **FR-WARN-3 must draw from the shared claims, not restate them.** It is the one sentence
    /// NFR-USE-6 exists to protect, and it appears both before the run and in the report — so if
    /// this warning ever carries its own literal, the two can disagree about it.
    @Test func theCleanPassWarningIsBuiltFromTheSharedClaims() {
        #expect(PreRunWarningText.cleanPassIsNotHealth.points
                == [HonestFraming.cleanResultMeans, HonestFraming.degradingBlocksAreInvisible])
    }

    /// FR-WARN-1's whole point is the gap between *by design* and *guaranteed*: stating only the
    /// first is how a user concludes the second and skips the backup.
    @Test func theBackupWarningSaysBothThatItIsSafeByDesignAndThatDesignIsNotAGuarantee() {
        let text = PreRunWarningText.backUpFirst.points.map(\.plain).joined(separator: " ")
        #expect(text.contains("non-destructive by design"))
        #expect(text.contains("Design is not a guarantee"))
        #expect(text.lowercased().contains("back up"))
    }

    /// FR-WARN-2 must say what the cost *is*. "Run this infrequently" with no reason is advice the
    /// user has no way to weigh, and this tool does not issue judgements it will not support.
    @Test func theFlashWarningSaysWhatTheCostActuallyIs() {
        let text = PreRunWarningText.infrequentOnFlash.points.map(\.plain).joined(separator: " ")
        #expect(text.contains("every block on the device"))
        #expect(text.contains("endurance"))
    }

    /// No mandatory warning may promise a health verdict — the failure mode NFR-USE-6 names.
    @Test func noWarningClaimsTheDriveIsHealthy() {
        for warning in PreRunWarningText.mandatory {
            for point in warning.points {
                #expect(!point.plain.lowercased().contains("is healthy"),
                        "\(warning.requirement) implies a health verdict")
            }
        }
    }

    // MARK: - The dialogs' own wording (increment 3)

    /// Decision 6: the confirmation that stands in for the suppressed warnings must identify the
    /// drive by **model, capacity and USB serial**. A question whose subject is "disk4" is a
    /// question about a name — and on this machine the scratch drive moved from `disk8` to `disk10`
    /// inside three days.
    @Test func theConfirmationQuestionNamesTheDriveByModelCapacityAndSerial() {
        let question = PreRunWarningText.confirmationQuestion(for: Fixture.seagate())
        #expect(question.contains("Seagate Expansion HDD"))
        #expect(question.contains("00000000NT17XBRA"))
        #expect(question.contains("22.00 TB"))
        #expect(!question.contains("disk4"),
                "the BSD name is a locator; it must not stand as the identity in the question")
    }

    /// The case where this dialog is the *only* identification the user gets. It must leave the
    /// serial out rather than print a placeholder — a question naming "serial unknown" reads as an
    /// identification, and this drive has none.
    @Test func theConfirmationQuestionOmitsASerialItDoesNotHaveRatherThanInventingOne() {
        let question = PreRunWarningText.confirmationQuestion(for: Fixture.seagate(serial: nil))
        #expect(question.contains("Seagate Expansion HDD"))
        #expect(!question.lowercased().contains("serial"),
                "a drive with no serial must not have the word 'serial' in its question at all")
        #expect(!question.contains("nil") && !question.contains("unknown"))
    }

    /// **The checkbox must not promise what it does not deliver.** Suppression removes the warning
    /// text, never the confirmation (NFR-USE-4 as qualified 2026-08-09) — and this is the one
    /// screen whose job is not overstating things.
    @Test func theSuppressionCheckboxSaysAConfirmationStillHappens() {
        let caveat = PreRunWarningText.suppressionCaveat.lowercased()
        #expect(caveat.contains("still"))
        #expect(caveat.contains("confirm"))
        #expect(caveat.contains("each run"))
    }

    /// A confirmation that named the drive but not what is about to happen to it would be asking
    /// the user to agree to something unstated. It has to say that it writes.
    @Test func theConfirmationSaysWhatIsAboutToHappenToTheDrive() {
        let consequence = PreRunWarningText.confirmationConsequence.lowercased()
        #expect(consequence.contains("every block"))
        #expect(consequence.contains("written"))
        #expect(consequence.contains("verify"))
    }

    // MARK: - The standing advice on the device pane (2026-08-10)

    /// It replaced *"Testing a drive you are using is not advisable"*, withdrawn by the user as
    /// **not necessarily true**. The risk is not conditional on the drive being in use, so the
    /// replacement must not reintroduce that framing — a warning that ties danger to "using" the
    /// drive teaches the wrong thing about when to be careful.
    @Test func theStandingAdviceDoesNotTieTheRiskToUsingTheDrive() {
        let advice = PreRunWarningText.standingBackupAdvice.lowercased()
        #expect(!advice.contains("advisable"))
        #expect(!advice.contains("you are using"))
    }

    /// What it must actually say: that testing can lose data, and to back up first.
    @Test func theStandingAdviceNamesTheRiskAndTheCorrectiveStep() {
        let advice = PreRunWarningText.standingBackupAdvice
        #expect(advice.contains("data loss"))
        #expect(advice.lowercased().contains("backed up"))
        #expect(advice.contains("test drive"))
    }

    /// It says the files **on the test drive** need backing up — not that they need backing up
    /// *onto* it, which is the opposite instruction and the reading the first draft allowed.
    /// Caught by the user before it shipped; pinned so a later edit cannot reintroduce it.
    @Test func theStandingAdviceSaysWhichFilesRatherThanWhereToPutThem() {
        #expect(PreRunWarningText.standingBackupAdvice
                    .contains("files on the test drive are backed up"))
        #expect(!PreRunWarningText.standingBackupAdvice.contains("backed up on the test drive"))
    }

    /// It is the product's **second** place for "back up first", beside FR-WARN-1. They may be
    /// worded differently — one is a standing one-liner, the other a pre-run dialog — but they must
    /// not disagree about what the risk is, which is why they live in one file.
    @Test func theStandingAdviceAndTheMandatoryWarningAgreeAboutTheRisk() {
        let mandatory = PreRunWarningText.backUpFirst.points.map(\.plain)
            .joined(separator: " ").lowercased()
        #expect(mandatory.contains("back up"))
        #expect(PreRunWarningText.standingBackupAdvice.lowercased().contains("backed up"))
    }

    // MARK: - Helpers

    private func allClaims() -> [HonestFramingClaim] {
        HonestFraming.claims
            + [HonestFraming.summary, HonestFraming.rangeBeyondTheFailureWasNotTested]
            + PreRunWarningText.mandatory.flatMap(\.points)
    }

    private enum Fixture {

        static let utc = TimeZone(identifier: "UTC")!

        static func device() -> ReportedDevice {
            ReportedDevice(modelDescription: "Samsung Portable SSD T5",
                           usbSerialNumber: "12345686DAA9",
                           bsdNameAtRunTime: "disk10",
                           capacityBytes: 1_000_204_886_016,
                           logicalBlockSize: 512)
        }

        /// The drive FR-DEV-3 default-selects on this machine, with a live Time Machine on it — the
        /// one the confirmation exists to keep from being written to by accident.
        static func seagate(serial: String? = "00000000NT17XBRA") -> ReportedDevice {
            ReportedDevice(modelDescription: "Seagate Expansion HDD",
                           usbSerialNumber: serial,
                           bsdNameAtRunTime: "disk4",
                           capacityBytes: 22_000_969_973_248,
                           logicalBlockSize: 512)
        }

        /// Built through the real initialiser, so the outcome is *derived* the way the shipped app
        /// derives it rather than asserted into place by the test.
        static func report(outcome: RunOutcomeCode,
                           failedRangesEncoded: String,
                           failedBlockCount: UInt64) -> RunReport {
            let reply = RunCycleOutcome(runOutcomeCode: outcome.rawValue,
                                        interruptedAtBlock: 0,
                                        chunksProcessed: 256,
                                        failedRangeCount: failedBlockCount > 0 ? 1 : 0,
                                        failureSummary: "",
                                        cacheBypassCode: 1,
                                        bufferBytesHeld: 8 << 20,
                                        hostOverheadFraction: 0.0255,
                                        helperCoreFraction: 0.0422,
                                        failureModeUsedCode: 2,
                                        failedRangesEncoded: failedRangesEncoded,
                                        failedBlockCount: failedBlockCount,
                                        readBytesPerSecond: 517_000_000,
                                        writeBytesPerSecond: 491_000_000,
                                        readLatencySampleCount: 256,
                                        readLatencyMinimumNanoseconds: 1_100_000,
                                        readLatencyMaximumNanoseconds: 9_900_000,
                                        readLatencyP99UpperBoundNanoseconds: 2_195_000,
                                        message: "Cycle completed")
            return RunReport(reply: reply,
                             startBlock: 0,
                             blockCount: 2_097_152,
                             ioSizesUsed: [4 << 20],
                             device: device(),
                             startedAt: Date(timeIntervalSince1970: 1_785_000_000),
                             finishedAt: Date(timeIntervalSince1970: 1_785_000_007),
                             usbLinkSpeedDescription: "10 Gb/s (USB 3.1 Gen 2)")!
        }

        static func cleanReport() -> RunReport {
            report(outcome: .completed, failedRangesEncoded: "", failedBlockCount: 0)
        }

        static func stoppedOnErrorReport() -> RunReport {
            report(outcome: .stoppedOnFailure, failedRangesEncoded: "4096:8:1", failedBlockCount: 8)
        }
    }
}
