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

    /// The conditional claims belong to the report surfaces only — one of them says "the failure
    /// above", and there is no "above" in a dialog shown before the run starts. A mutation adding
    /// either to ``HonestFraming/claims`` would put that sentence in the pre-run dialog.
    @Test func theStoppedRunClaimsAreNotShownOnEverySurface() {
        for conditional in conditionalClaims() {
            #expect(!HonestFraming.claims.contains(conditional),
                    "a conditional claim reached every surface: \(conditional.plain.prefix(48))")
        }
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

    /// **FR-RPT-4, increment 8.** A run the user stopped gets its own sentence, and it is not the
    /// stop-on-error one — that sentence points at "the failure above", which for a user-stopped
    /// run may not exist at all.
    @Test func aUserStoppedRunGetsItsOwnUntestedSentenceAndNotTheFailureOne() {
        let document = RunReportMarkdown.render(Fixture.stoppedByUserReport(), timeZone: Fixture.utc)

        #expect(document.contains(HonestFraming.rangeBeyondTheStopWasNotTested.markdown))
        #expect(!document.contains(HonestFraming.rangeBeyondTheFailureWasNotTested.markdown),
                "a user-stopped run was told the range beyond a failure went untested")

        let stopped = RunReportMarkdown.render(Fixture.stoppedOnErrorReport(), timeZone: Fixture.utc)
        #expect(!stopped.contains(HonestFraming.rangeBeyondTheStopWasNotTested.markdown),
                "a run that stopped on an error was told a user had stopped it")
    }

    /// The third one, and the trap it avoids: the sentence for a drive that left must not be either
    /// of the other two, because both of those name a cause — a failure, or a person — and this
    /// ending has neither. It must also not blame the drive: **whether the disconnection was the
    /// drive's fault is a question this tool cannot answer**, and a claim in a persisted file is
    /// exactly where a guess about it would do damage.
    @Test func aRunWhoseDriveLeftGetsItsOwnUntestedSentenceAndBlamesNobody() {
        let claim = HonestFraming.claim(addedBy: .deviceLost)
        #expect(claim == HonestFraming.rangeBeyondTheDisconnectionWasNotTested)
        #expect(claim != HonestFraming.rangeBeyondTheFailureWasNotTested)
        #expect(claim != HonestFraming.rangeBeyondTheStopWasNotTested)

        let plain = claim?.plain.lowercased() ?? ""
        #expect(plain.contains("no longer attached"))
        for accusation in ["failed", "faulty", "fault", "error", "bad"] {
            #expect(!plain.contains(accusation),
                    "the untested-remainder sentence accuses the drive of \(accusation)")
        }
    }

    /// All three conditional sentences say the thing the report exists to keep saying. Asserted on
    /// the wording rather than on which claim was chosen, so rewording any one of them cannot
    /// quietly drop the distinction that makes it worth printing.
    ///
    /// The count is pinned, and it earned that: `deviceLost` arriving in Step 12 chunk 5 failed
    /// this line rather than slipping in as a fourth outcome with no sentence, or with one that had
    /// dropped the clause. A `compactMap` over `allCases` that is never counted cannot tell those
    /// two apart from a correct addition.
    @Test func everyConditionalClaimSaysUntestedIsNotPassed() {
        let conditionals = RunReportOutcome.allCases.compactMap(HonestFraming.claim(addedBy:))
        #expect(conditionals.count == 3)
        for claim in conditionals {
            #expect(claim.plain.lowercased().contains("not tested"))
            #expect(claim.plain.lowercased().contains("untested is not the same as passed"))
        }
    }

    /// The outcomes that add nothing add nothing — the other half of the lookup, and the one a
    /// mutation returning a claim unconditionally would break.
    @Test func anOutcomeThatCoveredItsRangeAddsNoExtraSentence() {
        #expect(HonestFraming.claim(addedBy: .completedClean) == nil)
        #expect(HonestFraming.claim(addedBy: .completedWithFailures) == nil)
        #expect(HonestFraming.claim(addedBy: .incomplete) == nil)
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

    // MARK: - Helpers

    /// Every claim in the file, with **the outcome-conditional ones derived rather than listed**.
    ///
    /// It listed `rangeBeyondTheFailureWasNotTested` by hand until increment 8. That was fine while
    /// there was one; the moment a second arrived, a hand list is a thing to forget — and what
    /// would be forgotten is the balanced-emphasis and plain-derivation checks, which is how an
    /// unbalanced `**` reaches a report as literal asterisks. Walking `allCases` through
    /// `HonestFraming.claim(addedBy:)` means a third conditional claim is covered on the day it is
    /// written.

    // MARK: - What a vanished drive was left holding (Step 12, FR-DEV-8)

    /// **Every account, every case, and no two the same.**
    ///
    /// A collision is the failure that matters here: two genuinely different situations — a paused
    /// run with nothing outstanding, and a call that was never answered — rendering the same
    /// sentence would make the account decorative. It would still be present, still be true of one
    /// of them, and tell a reader nothing.
    @Test func everyDeviceLossAccountReadsDifferentlyFromEveryOther() {
        let sentences = Self.everyAccount.map { HonestFraming.claim(about: $0).markdown }

        #expect(Set(sentences).count == Self.everyAccount.count,
                "two device-loss accounts render the same sentence")
        for sentence in sentences {
            #expect(sentence.count > 60, "an account rendered a stub")
        }
    }

    /// **The load-bearing one: the words agree with the verdict.**
    ///
    /// `DeviceLossAccount.aWriteBackMayBeUnfinished` is what a caller reasons about; the sentence
    /// is what a person reads. If those two ever disagree, the one that is wrong is the one nobody
    /// can check — a report that computes "this may be unfinished" and then prints a reassuring
    /// paragraph is worse than one that prints nothing.
    ///
    /// Tested in **both** directions on purpose. Only asserting that the risky cases warn would
    /// pass a `HonestFraming` that warned on all six, which is precisely the over-claim this
    /// four-case split exists to avoid.
    @Test func theSentenceAgreesWithTheWriteBackVerdict() {
        for account in Self.everyAccount {
            let text = HonestFraming.claim(about: account).plain.lowercased()
            let warns = text.contains("may hold partly written data")
                     || text.contains("cannot be ruled out")

            #expect(warns == account.aWriteBackMayBeUnfinished,
                    "\(account) computes \(account.aWriteBackMayBeUnfinished) and says: \(text)")
        }
    }

    /// The one case with a real hazard in it says so, names the block, and bounds the damage.
    ///
    /// The bound matters as much as the warning. A drive that left during a write-back has **one**
    /// chunk at risk — every earlier one was written back and verified, and no later one was
    /// started — and a sentence that warned without saying so would leave a reader thinking the
    /// whole drive was suspect.
    @Test func theWriteBackCaseNamesTheBlockAndBoundsTheDamage() {
        let claim = HonestFraming.claim(about: .theHelperSaidWhere(block: 4_194_304,
                                                                   phase: .writingBack))
        let text = claim.plain

        #expect(text.contains("4,194,304"), "the block a reader needs was not printed")
        #expect(text.lowercased().contains("may hold partly written data"))
        #expect(text.lowercased().contains("no other chunk is affected"))
    }

    /// A paused run is the one route-(b) case allowed to reassure, and it must actually do so —
    /// this is the sentence that would be lost if the two route-(b) ways were collapsed into one.
    @Test func aPausedRunIsToldNothingWasLeftHalfWritten() {
        let text = HonestFraming.claim(about: .nothingWasInFlight).plain.lowercased()

        #expect(text.contains("paused"))
        #expect(text.contains("nothing was left half-written"))
        #expect(!text.contains("cannot be ruled out"), "a paused run was warned about a write-back")
    }

    /// **The only account that answers a second question**, and it is the claim's fate rather than
    /// the data's.
    ///
    /// The deadline expiring means the helper went quiet inside the owning connection's blocking
    /// call, and a second message on a connection with a call in flight is not delivered until that
    /// call returns (measured 2026-08-04) — so the release could not be acknowledged either. This
    /// is what surfaces `RunController.releaseCannotBeConfirmed` to a person: not a field on the
    /// report, but a sentence derived from the one ending that implies it.
    ///
    /// Asserted **exclusively**. A version that appended the release sentence to every device-loss
    /// claim would pass an assertion that only looked here, and would then be telling four other
    /// runs — including a paused one whose release completed normally — that exclusive access might
    /// still be held.
    @Test func onlyTheUnansweredCallReportsOnTheClaimAsWellAsTheData() {
        for account in Self.everyAccount {
            let text = HonestFraming.claim(about: account).plain.lowercased()
            let saysSo = text.contains("exclusive access could not be confirmed")

            #expect(saysSo == (account == .theHelperNeverAnswered),
                    "\(account) says: \(text)")
        }
    }

    /// And it says what that means the user will *see*, which is the actionable half.
    ///
    /// "Exclusive access could not be confirmed" on its own reads as an unbounded problem. The
    /// second clause bounds it: if the claim really was still held, the next Start says so in the
    /// helper's own words rather than failing mysteriously — so there is nothing to do now.
    @Test func theUnconfirmedReleaseSaysHowItWouldShowUp() {
        let text = HonestFraming.claim(about: .theHelperNeverAnswered).plain.lowercased()

        #expect(text.contains("the next test to start would have been refused"))
        #expect(text.contains("could not be confirmed"),
                "stated as a present hazard rather than as history")
    }

    /// Reading and verifying are the two phases that end with the drive intact, and each says why
    /// rather than merely declining to warn. "Unverified is not the same as bad" is the clause that
    /// stops a verify-phase loss reading as a failed comparison.
    @Test func theSafePhasesSayWhyTheyAreSafe() {
        let reading = HonestFraming.claim(about: .theHelperSaidWhere(block: 8, phase: .reading))
        #expect(reading.plain.lowercased().contains("nothing had been written"))

        let verifying = HonestFraming.claim(about: .theHelperSaidWhere(block: 8, phase: .verifying))
        #expect(verifying.plain.lowercased().contains("the write-back had already completed"))
        #expect(verifying.plain.lowercased().contains("unverified is not the same as bad"))
    }

    /// A phase this build cannot name is reported as unknown and treated as unsafe — and the
    /// sentence says which of the two it is doing, because "a step this version does not
    /// recognise" is actionable (update the app) where a bare warning is not.
    @Test func anUnrecognisedPhaseIsNamedAsUnknownRatherThanGuessed() {
        let text = HonestFraming.claim(about: .theHelperSaidWhere(block: 64,
                                                                   phase: .unrecognised)).plain
        #expect(text.lowercased().contains("does not recognise"))
        #expect(text.lowercased().contains("cannot be ruled out"))
        #expect(text.contains("64"), "the block was known and was not printed")

        // It must not name one of the three phases it cannot distinguish between.
        for phase in ["reading", "writing", "verify"] {
            #expect(!text.lowercased().contains(phase),
                    "an unrecognised phase was rendered as \(phase)")
        }
    }

    /// The contradiction case says the least, and says that it is saying the least.
    @Test func theAccountThatKnowsNothingSaysSo() {
        let text = HonestFraming.claim(about: .noRouteSaidAnything).plain.lowercased()

        #expect(text.contains("neither"))
        #expect(text.contains("cannot say what the run was doing"))
        #expect(text.contains("cannot be ruled out"))
    }

    /// Every device-loss sentence, from every route.
    static let everyAccount: [DeviceLossAccount] = [
        .theHelperSaidWhere(block: 4096, phase: .reading),
        .theHelperSaidWhere(block: 4096, phase: .writingBack),
        .theHelperSaidWhere(block: 4096, phase: .verifying),
        .theHelperSaidWhere(block: 4096, phase: .unrecognised),
        .nothingWasInFlight,
        .theHelperNeverAnswered,
        .noRouteSaidAnything,
    ]

    private func allClaims() -> [HonestFramingClaim] {
        HonestFraming.claims
            + [HonestFraming.summary]
            + conditionalClaims()
            + PreRunWarningText.mandatory.flatMap(\.points)
    }

    /// Every claim this file shows **conditionally**, from both families, derived rather than
    /// listed.
    ///
    /// `rangeCaveats(rangeIsWholeDrive: false, coveredTheRange: false)` is the call that returns
    /// all of them at once — the run that carries every caveat there is.
    private func conditionalClaims() -> [HonestFramingClaim] {
        RunReportOutcome.allCases.compactMap(HonestFraming.claim(addedBy:))
            + HonestFraming.rangeCaveats(rangeIsWholeDrive: false, coveredTheRange: false)
            + Self.everyAccount.map(HonestFraming.claim(about:))
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
        ///
        /// `endedBy` defaults to the ending implied by the reply — the ordinary case, where the run
        /// ended the way its last call did. A caller testing a run whose ending diverges from its
        /// last reply passes it explicitly.
        static func report(outcome: RunOutcomeCode,
                           endedBy ending: RunSequenceOutcome? = nil,
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
                                        deviceReadBytesPerSecond: 517_000_000,
                                        writeBytesPerSecond: 491_000_000,
                                        coverageBytesPerSecond: 245_000_000,
                                        completedBytesPerSecond: 238_000_000,
                                        readLatencySampleCount: 256,
                                        readLatencyMinimumNanoseconds: 1_100_000,
                                        readLatencyMaximumNanoseconds: 9_900_000,
                                        readLatencyP99UpperBoundNanoseconds: 2_195_000,
                                        message: "Cycle completed",
                                        deviceLossPhaseCode: DeviceLossPhaseCode.unrecognised.rawValue)
            return RunReport(reply: reply,
                             endedBy: ending ?? impliedEnding(outcome),
                             // This fixture's device-loss reply carries a phase, so route (a) is
                             // what accounted for it. The route-(b) accounts are `HonestFraming`'s
                             // own tests, which build them directly.
                             removalCallbackSaid: nil,
                             startBlock: 0,
                             blockCount: 2_097_152,
                             ioSizesUsed: [4 << 20],
                             device: device(),
                             startedAt: Date(timeIntervalSince1970: 1_785_000_000),
                             finishedAt: Date(timeIntervalSince1970: 1_785_000_007),
                             usbLinkSpeedDescription: "10 Gb/s (USB 3.1 Gen 2)")!
        }

        /// A run that ended the way its last call did.
        static func impliedEnding(_ outcome: RunOutcomeCode) -> RunSequenceOutcome {
            switch outcome {
            case .completed:                    return .completed
            case .stoppedOnFailure:             return .stoppedOnFailure
            case .pausedByUser, .stoppedByUser: return .stoppedByUser
            case .deviceLost:                   return .deviceLost
            case .unrecognised:                 return .callFailed(reason: "")
            }
        }

        static func cleanReport() -> RunReport {
            report(outcome: .completed, failedRangesEncoded: "", failedBlockCount: 0)
        }

        static func stoppedOnErrorReport() -> RunReport {
            report(outcome: .stoppedOnFailure, failedRangesEncoded: "4096:8:1", failedBlockCount: 8)
        }

        /// A run the **user** stopped, which had already logged a bad block before they did
        /// (FR-RPT-4, increment 8). The failures matter: this is the outcome whose own
        /// `foundFailures` says nothing either way, so a fixture without them cannot show that the
        /// failed range still reaches both surfaces.
        static func stoppedByUserReport() -> RunReport {
            report(outcome: .stoppedByUser,
                   failedRangesEncoded: "4096:8:1",
                   failedBlockCount: 8)
        }
    }
}
