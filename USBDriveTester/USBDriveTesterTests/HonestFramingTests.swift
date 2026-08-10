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

        /// Built through the real initialiser, so the outcome is *derived* the way the shipped app
        /// derives it rather than asserted into place by the test.
        static func report(didComplete: Bool,
                           failedRangesEncoded: String,
                           failedBlockCount: UInt64) -> RunReport {
            let reply = RunCycleOutcome(didComplete: didComplete,
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
            report(didComplete: true, failedRangesEncoded: "", failedBlockCount: 0)
        }

        static func stoppedOnErrorReport() -> RunReport {
            report(didComplete: false, failedRangesEncoded: "4096:8:1", failedBlockCount: 8)
        }
    }
}
