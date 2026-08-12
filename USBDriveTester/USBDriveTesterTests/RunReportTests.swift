//
//  RunReportTests.swift
//  The end-of-run report and its Markdown rendering. Step 10, increment 4.
//  FR-RPT-1/2/3/4/5, FR-TEST-9, NFR-USE-7, BUILD-PLAN 10.3/10.4/10.5.
//
//  ## Why a report gets this much testing
//
//  Everything else this product produces is transient — a panel that will be redrawn, a log line
//  that will roll off. **The report is the only thing it persists**, and it is the copy that
//  gets forwarded, filed, and read again months later with no memory of the session that made
//  it. Every claim in it therefore has to be true on its own, detached from the UI that was on
//  screen and from whoever ran it.
//
//  So the suite below is mostly about what the report must **not** be able to say:
//
//  - it must not print "no failures" when it could not read the list (`nil` is not `[]`);
//  - it must not print a truncated list without saying it is truncated;
//  - it must not omit the FR-TEST-9 qualification, in **any** verdict, ever;
//  - it must not identify the drive by its BSD name, and must say so when it has no serial;
//  - it must not read as a health certificate;
//  - it must not grade throughput;
//  - it must not print p99 as a point;
//  - and it must not exist at all for a call the helper refused.
//
//  Each of those is a way for a plausible, correctly-formatted file to be wrong — which is this
//  project's recurring failure mode, arriving in the one artefact that outlives everything.
//

import Testing
import Foundation
@testable import USBDriveTester

// MARK: - Fixtures

private enum Fixture {

    static let utc = TimeZone(identifier: "UTC")!

    /// The scratch device's real shape, so the numbers in these tests are the ones a reader
    /// would actually see.
    static func device(serial: String? = "12345686DAA9",
                       bsdName: String? = "disk8") -> ReportedDevice {
        ReportedDevice(modelDescription: "Samsung Portable SSD T5",
                       usbSerialNumber: serial,
                       bsdNameAtRunTime: bsdName,
                       capacityBytes: 1_000_204_886_016,
                       logicalBlockSize: 512)
    }

    static let started = Date(timeIntervalSince1970: 1_785_000_000)   // fixed, so tests are stable
    static let finished = Date(timeIntervalSince1970: 1_785_000_007)

    /// A finished 1 GiB run with nothing wrong.
    static func reply(outcome: RunOutcomeCode = .completed,
                      interruptedAtBlock: UInt64 = 0,
                      chunksProcessed: UInt64 = 256,
                      failedRangeCount: Int = 0,
                      failedRangesEncoded: String = "",
                      failedBlockCount: UInt64 = 0,
                      failureModeUsedCode: Int = 2,
                      cacheBypassCode: Int = 1,
                      readBytesPerSecond: Double = 517_000_000,
                      writeBytesPerSecond: Double = 491_000_000,
                      readLatencySampleCount: UInt64 = 256,
                      readLatencyMinimumNanoseconds: UInt64 = 1_100_000,
                      readLatencyMaximumNanoseconds: UInt64 = 9_900_000,
                      readLatencyP99UpperBoundNanoseconds: UInt64 = 2_195_000) -> RunCycleOutcome {
        RunCycleOutcome(runOutcomeCode: outcome.rawValue,
                        interruptedAtBlock: interruptedAtBlock,
                        chunksProcessed: chunksProcessed,
                        failedRangeCount: failedRangeCount,
                        failureSummary: "",
                        cacheBypassCode: cacheBypassCode,
                        bufferBytesHeld: 8 << 20,
                        hostOverheadFraction: 0.0255,
                        helperCoreFraction: 0.0422,
                        failureModeUsedCode: failureModeUsedCode,
                        failedRangesEncoded: failedRangesEncoded,
                        failedBlockCount: failedBlockCount,
                        readBytesPerSecond: readBytesPerSecond,
                        writeBytesPerSecond: writeBytesPerSecond,
                        readLatencySampleCount: readLatencySampleCount,
                        readLatencyMinimumNanoseconds: readLatencyMinimumNanoseconds,
                        readLatencyMaximumNanoseconds: readLatencyMaximumNanoseconds,
                        readLatencyP99UpperBoundNanoseconds: readLatencyP99UpperBoundNanoseconds,
                        message: "Cycle completed")
    }

    static func report(_ reply: RunCycleOutcome = Fixture.reply(),
                       device: ReportedDevice = Fixture.device(),
                       ioSizesUsed: [Int] = [4 << 20],
                       blockCount: UInt64 = 2_097_152,
                       linkSpeed: String? = "10 Gb/s (USB 3.1 Gen 2)") -> RunReport {
        RunReport(reply: reply,
                  startBlock: 0,
                  blockCount: blockCount,
                  ioSizesUsed: ioSizesUsed,
                  device: device,
                  startedAt: started,
                  finishedAt: finished,
                  usbLinkSpeedDescription: linkSpeed)!
    }

    static func markdown(_ report: RunReport) -> String {
        RunReportMarkdown.render(report, timeZone: utc)
    }
}

// MARK: - Which run gets a report at all

struct ReportExistenceTests {

    /// FR-FAIL-5 requires every **run** to conclude with a report. A request the helper refused
    /// is not a run: nothing was read, nothing was written, and there is nothing to say about the
    /// drive. Writing a file for one would put a description of a test that never touched the
    /// hardware on somebody's disk.
    @Test func aRefusedCallProducesNoReport() {
        let refused = Fixture.reply(outcome: .unrecognised,
                                    chunksProcessed: 0,
                                    failureModeUsedCode: 0,   // no run happened
                                    cacheBypassCode: 0,
                                    readBytesPerSecond: -1,
                                    writeBytesPerSecond: -1,
                                    readLatencySampleCount: 0)
        #expect(RunReport(reply: refused, startBlock: 0, blockCount: 2_097_152,
                          ioSizesUsed: [4 << 20], device: Fixture.device(),
                          startedAt: Fixture.started, finishedAt: Fixture.finished) == nil)
    }

    /// The discriminator is the mode echo — the helper stating what it did — and not the chunk
    /// count, which would be the app inferring it from an implementation detail.
    @Test func aRunThatStoppedOnItsFirstChunkStillGetsAReport() {
        let stopped = Fixture.reply(outcome: .stoppedOnFailure,
                                    chunksProcessed: 1,
                                    failedRangeCount: 1,
                                    failedRangesEncoded: "200:2:3",
                                    failedBlockCount: 2,
                                    failureModeUsedCode: 1)
        #expect(RunReport(reply: stopped, startBlock: 0, blockCount: 2_097_152,
                          ioSizesUsed: [4 << 20], device: Fixture.device(),
                          startedAt: Fixture.started, finishedAt: Fixture.finished) != nil)
    }

    @Test func aReplyFromANewerHelperWithAnUnknownModeProducesNoReport() {
        let strange = Fixture.reply(failureModeUsedCode: 99)
        #expect(RunReport(reply: strange, startBlock: 0, blockCount: 2_097_152,
                          ioSizesUsed: [4 << 20], device: Fixture.device(),
                          startedAt: Fixture.started, finishedAt: Fixture.finished) == nil)
    }
}

// MARK: - FR-RPT-4: the outcome

struct ReportOutcomeTests {

    @Test func aCleanRunCompletesClean() {
        #expect(Fixture.report().outcome == .completedClean)
    }

    @Test func aCompletedRunWithFailuresSaysSo() {
        let reply = Fixture.reply(failedRangeCount: 2,
                                  failedRangesEncoded: "200:2:3;5000:4:1",
                                  failedBlockCount: 6)
        #expect(Fixture.report(reply).outcome == .completedWithFailures)
    }

    @Test func aHaltedRunIsStoppedOnError() {
        let reply = Fixture.reply(outcome: .stoppedOnFailure, chunksProcessed: 2,
                                  failedRangeCount: 1, failedRangesEncoded: "200:2:3",
                                  failedBlockCount: 2, failureModeUsedCode: 1)
        #expect(Fixture.report(reply).outcome == .stoppedOnError)
    }

    /// The case that exists so the report cannot lie about a reply it cannot classify. Not a
    /// mechanism awaiting a trigger — a refusal to guess about an input the app does not control.
    @Test func aRunThatEndedEarlyWithNoFailureIsCalledIncompleteRatherThanGuessedAt() {
        let reply = Fixture.reply(outcome: .stoppedOnFailure, chunksProcessed: 10)
        let report = Fixture.report(reply)
        #expect(report.outcome == .incomplete)
        #expect(report.outcome.didCoverTheRequestedRange == false)
        #expect(report.outcome.foundFailures == false)
    }

    /// Failures may be evidenced by the block count, the range count, or a decoded list. Any one
    /// is enough — a report must not read as clean because a single field arrived as zero.
    @Test func anyEvidenceOfFailureIsEnoughToNotReadAsClean() {
        let byBlockCount = Fixture.reply(failedBlockCount: 4)
        let byRangeCount = Fixture.reply(failedRangeCount: 1)
        let byList = Fixture.reply(failedRangesEncoded: "8:1:2")

        #expect(Fixture.report(byBlockCount).outcome == .completedWithFailures)
        #expect(Fixture.report(byRangeCount).outcome == .completedWithFailures)
        #expect(Fixture.report(byList).outcome == .completedWithFailures)
    }

    /// BUILD-PLAN 10.5. The word "healthy" must not appear, and the clean headline must say what
    /// was observed rather than what the drive is.
    @Test func aCleanOutcomeIsNeverWordedAsAHealthCertificate() {
        let headline = RunReportOutcome.completedClean.headline.lowercased()
        #expect(headline.contains("no currently-unreadable blocks were found"))
        #expect(headline.contains("healthy") == false)
        #expect(headline.contains("good") == false)
        #expect(headline.contains("pass") == false)
    }

    /// "Untested is not passed" is the substance of stop-on-first-error, and the outcome text is
    /// where a reader meets it.
    @Test func stoppingOnErrorSaysTheRestWasNotTested() {
        let explanation = RunReportOutcome.stoppedOnError.explanation.lowercased()
        #expect(explanation.contains("not tested"))
    }

    @Test func everyOutcomeCarriesAHeadlineAndAnExplanation() {
        for outcome: RunReportOutcome in [.completedClean, .completedWithFailures,
                                          .stoppedOnError, .incomplete] {
            #expect(outcome.headline.isEmpty == false)
            #expect(outcome.explanation.count > 40, "\(outcome) has no real explanation")
        }
    }
}

// MARK: - FR-TEST-9: mandatory, in every verdict

struct ReportCacheBypassTests {

    /// **The requirement that would be silently satisfiable by doing nothing.** A line that
    /// appears only when the check failed is indistinguishable from a missing line — so every
    /// verdict, including the passing one, prints a statement.
    @Test func everyVerdictProducesAStatement() {
        for code in [1, 2, 3, 0] {
            let report = Fixture.report(Fixture.reply(cacheBypassCode: code))
            #expect(report.cacheBypassStatement.count > 40,
                    "verdict \(code) produced no statement")
            #expect(Fixture.markdown(report).contains(report.cacheBypassStatement),
                    "verdict \(code)'s statement is not in the document")
        }
    }

    @Test func aPassingVerdictSaysTheResultMeansWhatItSays() {
        let report = Fixture.report(Fixture.reply(cacheBypassCode: 1))
        #expect(report.cacheBypass == .bypassed)
        #expect(report.verifyResultIsQualified == false)
        #expect(report.cacheBypassStatement.lowercased().contains("verified"))
    }

    /// FR-TEST-9's two halves: the fault detection is in doubt, the refresh is not. Both must be
    /// said, because a reader told only the first would conclude the run was worthless.
    @Test func aQualifiedVerdictSaysWhichHalfIsInDoubtAndWhichIsNot() {
        for code in [2, 3] {
            let report = Fixture.report(Fixture.reply(cacheBypassCode: code))
            let document = Fixture.markdown(report).lowercased()
            #expect(report.verifyResultIsQualified)
            #expect(document.contains("may be unreliable"), "verdict \(code)")
            #expect(document.contains("refresh"), "verdict \(code) does not say the refresh holds")
            #expect(document.contains("remains valid"), "verdict \(code)")
        }
    }

    /// A verdict this build does not know must never be read as success — the same rule the wire
    /// enum follows, carried into the prose.
    @Test func anUnrecognisedVerdictIsTreatedAsUnverified() {
        let report = Fixture.report(Fixture.reply(cacheBypassCode: 0))
        #expect(report.cacheBypass == .unrecognised)
        #expect(report.verifyResultIsQualified)
        #expect(report.cacheBypassStatement.lowercased().contains("unverified"))
    }

    /// **The headline carries the qualification, not just the paragraph below it.**
    ///
    /// Found by rendering (2026-08-06): a qualified clean run led with a bold
    /// *"Completed — no currently-unreadable blocks were found"* and put the doubt underneath.
    /// Every word true, correctly ordered — and a reader skimming for the verdict takes the bold
    /// line. FR-TEST-9 asks for a qualification that cannot be read past, which a footnote to an
    /// already-drawn conclusion is not.
    @Test func aQualifiedCleanRunSaysSoInTheHeadlineItself() {
        let report = Fixture.report(Fixture.reply(cacheBypassCode: 2))
        #expect(report.headline.contains("NOT VERIFIED"))
        #expect(report.headline != report.outcome.headline)

        let firstBoldLine = Fixture.markdown(report)
            .components(separatedBy: "\n")
            .first { $0.hasPrefix("**") } ?? ""
        #expect(firstBoldLine.contains("NOT VERIFIED"),
                "the first bold line a skimmer reads must carry the qualification")
    }

    /// A cached read cannot invent a mismatch, but it can hide one — so a failure count under an
    /// unverified bypass is a floor, not a count, and every outcome carries the caveat.
    @Test func everyQualifiedOutcomeCarriesTheCaveatInItsHeadline() {
        let replies: [RunCycleOutcome] = [
            Fixture.reply(cacheBypassCode: 3),
            Fixture.reply(failedRangeCount: 1, failedRangesEncoded: "8:2:1",
                          failedBlockCount: 2, cacheBypassCode: 3),
            Fixture.reply(outcome: .stoppedOnFailure, chunksProcessed: 1, failedRangeCount: 1,
                          failedRangesEncoded: "8:2:3", failedBlockCount: 2,
                          failureModeUsedCode: 1, cacheBypassCode: 2),
            Fixture.reply(outcome: .stoppedOnFailure, chunksProcessed: 3, cacheBypassCode: 0),
        ]
        for reply in replies {
            #expect(Fixture.report(reply).headline.contains("NOT VERIFIED"))
        }
    }

    /// And a verified run says nothing extra — the caveat must not become decoration that a
    /// reader learns to skip.
    @Test func aVerifiedRunsHeadlineIsUnadorned() {
        let report = Fixture.report()
        #expect(report.headline == report.outcome.headline)
        #expect(report.headline.contains("NOT VERIFIED") == false)
    }

    /// **Placement is part of the requirement.** A reader skimming for the verdict must not be
    /// able to reach "no block ranges failed" without passing the qualification first.
    @Test func theStatementSitsAboveTheFailureSection() {
        let document = Fixture.markdown(Fixture.report(Fixture.reply(cacheBypassCode: 2)))
        let statement = document.range(of: "Cache bypass NOT verified")
        let failures = document.range(of: "## Failed block ranges")
        #expect(statement != nil)
        #expect(failures != nil)
        if let statement, let failures {
            #expect(statement.lowerBound < failures.lowerBound,
                    "the qualification appears below the failure list, where it is a footnote")
        }
    }
}

// MARK: - FR-RPT-1: the failed ranges

struct ReportFailureListTests {

    @Test func rangesAreTabulatedWithStartLengthAndKind() {
        let reply = Fixture.reply(failedRangeCount: 2,
                                  failedRangesEncoded: "200:2:3;5000:4:1",
                                  failedBlockCount: 6)
        let document = Fixture.markdown(Fixture.report(reply))

        #expect(document.contains("| First block | Last block | Blocks | Failure |"))
        #expect(document.contains("| 200 | 201 | 2 | verify mismatch |"))
        #expect(document.contains("| 5,000 | 5,003 | 4 | read error |"))
    }

    @Test func allThreeKindsAreNamedInTheTable() {
        let reply = Fixture.reply(failedRangeCount: 3,
                                  failedRangesEncoded: "10:1:1;20:1:2;30:1:3",
                                  failedBlockCount: 3)
        let document = Fixture.markdown(Fixture.report(reply))
        #expect(document.contains("read error"))
        #expect(document.contains("write error"))
        #expect(document.contains("verify mismatch"))
    }

    @Test func aCleanRunSaysNothingFailed() {
        #expect(Fixture.markdown(Fixture.report()).contains("No block ranges failed."))
    }

    /// **`nil` is not `[]`.** A list that could not be decoded must not render as a clean drive —
    /// the worst available way for this particular field to be wrong.
    @Test func anUndecodableListIsNeverPrintedAsNoFailures() {
        let reply = Fixture.reply(failedRangeCount: 5,
                                  failedRangesEncoded: "garbage",
                                  failedBlockCount: 40)
        let report = Fixture.report(reply)
        #expect(report.failureListIsUnavailable)

        let document = Fixture.markdown(report)
        #expect(document.contains("No block ranges failed.") == false)
        #expect(document.contains("could not be read"))
        #expect(document.contains("Do not read this section as"))
        // The counts the helper *did* send still reach the reader.
        #expect(document.contains("40"))
    }

    /// A truncated list that does not announce itself reads exactly like a complete one.
    @Test func aTruncatedListSaysItIsTruncated() {
        let reply = Fixture.reply(failedRangeCount: 1_030,
                                  failedRangesEncoded: "0:1:1;10:1:1;20:1:1",
                                  failedBlockCount: 4_096)
        let report = Fixture.report(reply)
        #expect(report.listIsTruncated)
        #expect(report.droppedRangeCount == 1_027)

        let document = Fixture.markdown(report)
        #expect(document.contains("This list is truncated"))
        #expect(document.contains("1,027"))
        #expect(document.contains("includes every failing block, shown or not"))
    }

    /// The block count is authoritative even when the range list is not — it counts blocks in
    /// ranges the cap dropped.
    @Test func theBlockCountIsPrintedEvenWhenTheListIsCapped() {
        let reply = Fixture.reply(failedRangeCount: 1_030,
                                  failedRangesEncoded: "0:1:1",
                                  failedBlockCount: 4_096)
        #expect(Fixture.markdown(Fixture.report(reply)).contains("4,096 block(s) failed"))
    }

    @Test func aCompleteListDoesNotClaimTruncation() {
        let reply = Fixture.reply(failedRangeCount: 1,
                                  failedRangesEncoded: "200:2:3",
                                  failedBlockCount: 2)
        let report = Fixture.report(reply)
        #expect(report.listIsTruncated == false)
        #expect(Fixture.markdown(report).contains("This list is truncated") == false)
    }

    /// The three kinds say different things about a drive, and a reader who has one bad range
    /// needs to know which they have.
    @Test func theDocumentExplainsWhatEachKindMeans() {
        let reply = Fixture.reply(failedRangeCount: 1, failedRangesEncoded: "200:2:3",
                                  failedBlockCount: 2)
        let document = Fixture.markdown(Fixture.report(reply))
        #expect(document.contains("could not return the data at all"))
        #expect(document.contains("refused the write"))
        #expect(document.contains("returned different bytes"))
    }
}

// MARK: - Device identity (the 2026-08-06 rule)

struct ReportDeviceIdentityTests {

    /// The report outlives the enumeration that produced it, so the drive it is *about* is named
    /// by serial.
    @Test func theDriveIsIdentifiedByItsSerialNumber() {
        let document = Fixture.markdown(Fixture.report())
        #expect(document.contains("| USB serial number | 12345686DAA9 |"))
        #expect(Fixture.device().identification.contains("12345686DAA9"))
    }

    /// The BSD name may appear — it ties the report to a `diskutil` transcript from the same
    /// session — but **only labelled as the locator it was**.
    @Test func theBsdNameAppearsOnlyAsALabelledLocator() {
        let document = Fixture.markdown(Fixture.report())
        #expect(document.contains("/dev/disk8"))
        #expect(document.contains("a locator, not an identity"))
        #expect(document.contains("may name a different drive after a replug or a reboot"))
    }

    /// A drive with no serial cannot be identified, and the report has to say so rather than let
    /// the model name imply an identification it cannot make.
    @Test func aDriveWithNoSerialIsLabelledAsUnidentifiable() {
        let report = Fixture.report(device: Fixture.device(serial: nil))
        #expect(report.device.identificationCaveat != nil)

        let document = Fixture.markdown(report)
        #expect(document.contains("*none reported*"))
        #expect(document.contains("cannot be told apart from results for a different drive of "
                                + "the same model and capacity"))
    }

    @Test func aDriveWithASerialCarriesNoCaveat() {
        #expect(Fixture.device().identificationCaveat == nil)
        #expect(Fixture.markdown(Fixture.report()).contains("cannot be told apart") == false)
    }

    /// The export file name is part of what persists — a folder of `disk4-…` files would be a
    /// folder that no longer says which drive each is about.
    @Test func theSuggestedFileNameIsKeyedOnTheSerialAndNotTheBsdName() {
        let name = Fixture.report().suggestedFileName(timeZone: Fixture.utc)
        #expect(name.contains("12345686DAA9"))
        #expect(name.contains("disk8") == false)
        #expect(name.hasSuffix(".md"))
    }

    @Test func aDriveWithNoSerialGetsAVisiblyNonIdentifyingFileName() {
        let name = Fixture.report(device: Fixture.device(serial: nil))
            .suggestedFileName(timeZone: Fixture.utc)
        #expect(name.contains("unidentified-drive"))
    }

    /// A serial is normally alphanumeric. This is here so an unusual one cannot produce a path
    /// separator in a name that is about to be handed to a save panel.
    @Test func anAwkwardSerialCannotProduceAPathSeparator() {
        let name = Fixture.report(device: Fixture.device(serial: "../../etc/passwd"))
            .suggestedFileName(timeZone: Fixture.utc)
        #expect(name.contains("/") == false)
        #expect(name.contains("..") == false)
    }

    @Test func theFileNameCarriesTheRunsOwnDateAndTime() {
        let name = Fixture.report().suggestedFileName(timeZone: Fixture.utc)
        #expect(name.contains("2026-07-25"), "the name should carry the run's date, got \(name)")
    }
}

// MARK: - FR-RPT-2/3: the measurements

struct ReportMeasurementTests {

    @Test func throughputAndLatencyAreTabulated() {
        let document = Fixture.markdown(Fixture.report())
        #expect(document.contains("| Average read throughput | 517 MB/s |"))
        #expect(document.contains("| Average write throughput | 491 MB/s |"))
        #expect(document.contains("Read latency, minimum"))
        #expect(document.contains("Read latency, maximum"))
        #expect(document.contains("| Reads measured | 256 |"))
    }

    /// FR-RPT-3's p99 is an **upper bound** and prints as one. A bare "p99 = x" would be a
    /// bucket's midpoint presented as a measurement.
    @Test func theP99IsPrintedAsAnUpperBoundAndNeverAsAPoint() {
        let document = Fixture.markdown(Fixture.report())
        #expect(document.contains("≤ 2.195 ms"))
        #expect(document.contains("p99 is an upper bound"))
        #expect(document.contains("p99 = ") == false)
    }

    /// The bound is explained only when there is a percentile to explain. A run with no samples
    /// would otherwise carry a paragraph about a figure it does not have.
    @Test func theUpperBoundNoteIsAbsentWhenNothingWasMeasured() {
        let reply = Fixture.reply(readLatencySampleCount: 0)
        let document = Fixture.markdown(Fixture.report(reply))
        #expect(document.contains("p99 is an upper bound") == false)
    }

    /// An unmeasured figure renders as something visibly not a number. `0 MB/s` would mean
    /// *stalled*, which is a real and very different condition.
    @Test func unmeasuredFiguresRenderAsAnEmDashAndNeverAsZero() {
        let reply = Fixture.reply(readBytesPerSecond: -1,
                                  writeBytesPerSecond: -1,
                                  readLatencySampleCount: 0)
        let report = Fixture.report(reply)
        #expect(report.readBytesPerSecond == nil)

        let document = Fixture.markdown(report)
        #expect(document.contains("| Average read throughput | — |"))
        #expect(document.contains("| Average write throughput | — |"))
        #expect(document.contains("0 MB/s") == false)
        #expect(document.contains("-1") == false)
    }

    /// A genuinely stalled drive reports zero, and that must survive as a measurement.
    @Test func aZeroRateIsPrintedBecauseItIsAMeasurement() {
        let reply = Fixture.reply(readBytesPerSecond: 0)
        // Falls through to kB/s at this magnitude, which is still a number and still zero.
        #expect(Fixture.markdown(Fixture.report(reply)).contains("| Average read throughput | 0 kB/s |"))
    }

    /// D9, in the artefact where it matters most: a bare pair of numbers in a file invites the
    /// reader to supply the missing verdict themselves.
    @Test func throughputIsReportedAndExplicitlyNotGraded() {
        let document = Fixture.markdown(Fixture.report())
        #expect(document.contains("**reported, not graded**"))
        #expect(document.contains("It measures; it does not diagnose."))
        #expect(document.lowercased().contains("degraded") == false)
        #expect(document.lowercased().contains("slow for") == false)
    }

    /// The link speed is what a reader needs in order to judge the rate themselves, which is the
    /// whole basis for refusing to judge it for them.
    @Test func theNegotiatedLinkSpeedIsShownBesideTheThroughput() {
        #expect(Fixture.markdown(Fixture.report())
                    .contains("| Negotiated USB link speed | 10 Gb/s (USB 3.1 Gen 2) |"))
    }

    @Test func anAbsentLinkSpeedSimplyOmitsTheRow() {
        let document = Fixture.markdown(Fixture.report(linkSpeed: nil))
        #expect(document.contains("Negotiated USB link speed") == false)
        #expect(document.contains("Average read throughput"))
    }
}

// MARK: - Step 9's inherited note: which I/O sizes were used

struct ReportIOSizeTests {

    @Test func asingleSizeIsNamedPlainly() {
        #expect(Fixture.markdown(Fixture.report()).contains("| I/O size | 4 MiB |"))
    }

    /// FR-CTRL-8 lets the size change mid-run and the latency statistics deliberately keep
    /// accumulating across it — so the distribution is bimodal, and a report showing one figure
    /// over two populations without saying so invites a comparison that is not sound.
    @Test func severalSizesAreNamedAndTheDistributionIsFlaggedAsSpanningThem() {
        let report = Fixture.report(ioSizesUsed: [4 << 20, 1 << 20])
        #expect(report.latencySpansMultipleIOSizes)

        let document = Fixture.markdown(report)
        #expect(document.contains("4 MiB, then 1 MiB"))
        #expect(document.contains("accumulate across the change"))
        #expect(document.contains("should not be compared with a run that used a single size"))
    }

    /// A size repeated is still one size — the caveat is about the distribution, not about how
    /// many times the size was recorded.
    @Test func theSameSizeRecordedTwiceIsNotTreatedAsAChange() {
        let report = Fixture.report(ioSizesUsed: [4 << 20, 4 << 20])
        #expect(report.latencySpansMultipleIOSizes == false)
        #expect(Fixture.markdown(report).contains("accumulate across the change") == false)
    }
}

// MARK: - NFR-USE-7: the shape of the document

struct ReportMarkdownShapeTests {

    /// > *"headings, a clear pass/fail outcome, and tabulated bad-block ranges and statistics."*
    @Test func theDocumentHasTheSectionsTheRequirementAsksFor() {
        let document = Fixture.markdown(Fixture.report())
        for heading in ["# USB drive test report", "## Outcome", "## Drive", "## Run",
                        "## Failed block ranges", "## Measurements",
                        "## What this test does and does not prove"] {
            #expect(document.contains(heading), "missing \(heading)")
        }
    }

    /// The outcome must be findable without reading the document — it is the first thing under
    /// the first heading.
    @Test func theOutcomeIsTheFirstThingAfterTheTitle() {
        let document = Fixture.markdown(Fixture.report())
        let outcome = document.range(of: "## Outcome")
        let drive = document.range(of: "## Drive")
        #expect(outcome != nil && drive != nil)
        if let outcome, let drive { #expect(outcome.lowerBound < drive.lowerBound) }
        #expect(document.contains("**Completed — no currently-unreadable blocks were found**"))
    }

    /// Every table is a well-formed Markdown table: a header row, a separator, and rows with a
    /// matching column count. A report that will not render is not a report.
    @Test func everyTableIsWellFormed() {
        let reply = Fixture.reply(failedRangeCount: 2,
                                  failedRangesEncoded: "200:2:3;5000:4:1",
                                  failedBlockCount: 6)
        let lines = Fixture.markdown(Fixture.report(reply)).components(separatedBy: "\n")

        var index = 0
        var tablesSeen = 0
        while index < lines.count {
            if lines[index].hasPrefix("|"), index + 1 < lines.count,
               lines[index + 1].hasPrefix("|---") {
                let columns = lines[index].components(separatedBy: "|").count
                var row = index + 2
                while row < lines.count, lines[row].hasPrefix("|") {
                    #expect(lines[row].components(separatedBy: "|").count == columns,
                            "ragged table row: \(lines[row])")
                    row += 1
                }
                tablesSeen += 1
                index = row
            } else {
                index += 1
            }
        }
        #expect(tablesSeen >= 4, "expected drive, run, failures and measurements tables")
    }

    /// A bounded run is not a whole-drive pass, and a report that did not say so would invite
    /// being read as one. Whole-device runs arrive with Step 11.
    @Test func aPartialRangeIsNotAllowedToReadAsAWholeDrivePass() {
        let document = Fixture.markdown(Fixture.report())
        #expect(document.contains("**not the whole drive**"))
        #expect(document.contains("Blocks outside it were not tested."))
    }

    @Test func aWholeDriveRunCarriesNoPartialRangeCaveat() {
        // 1,000,204,886,016 bytes / 512 = the whole device.
        let report = Fixture.report(blockCount: 1_953_525_168)
        #expect(Fixture.markdown(report).contains("**not the whole drive**") == false)
    }

    /// NFR-USE-6 and Step 14's detailed step 3: the honest framing is echoed **into the report**,
    /// not only shown before the run. This is the copy that gets forwarded and re-read.
    @Test func theHonestFramingIsInTheDocumentAndNotOnlyOnScreen() {
        let document = Fixture.markdown(Fixture.report())
        #expect(document.contains("degrading but still correctable"))
        #expect(document.contains("cannot be detected at the USB block level"))
        #expect(document.contains("does not prove the medium retained it"))
        #expect(document.contains("refreshes charge retention"))
    }

    /// The dual role (FR-WARN-4) is named, so a reader knows what a qualified verify costs them
    /// and what it does not.
    @Test func theDualRoleIsStated() {
        let document = Fixture.markdown(Fixture.report())
        #expect(document.contains("refreshes charge retention"))
        #expect(document.contains("detects hard faults"))
    }

    /// A stopped run's untested remainder is repeated in the framing section, because that is
    /// where a reader looks to find out what the result is worth.
    @Test func aStoppedRunRepeatsThatTheRestIsUntested() {
        let reply = Fixture.reply(outcome: .stoppedOnFailure, chunksProcessed: 2,
                                  failedRangeCount: 1, failedRangesEncoded: "200:2:3",
                                  failedBlockCount: 2, failureModeUsedCode: 1)
        let document = Fixture.markdown(Fixture.report(reply))
        #expect(document.contains("Untested is not the same as passed."))
    }

    /// NFR-SEC-6: block addressing only, never device contents. There is no field on this type
    /// that could carry data, and this test is what keeps it that way if one is ever added.
    @Test func theDocumentCarriesAddressingAndNeverContents() {
        let reply = Fixture.reply(failedRangeCount: 1, failedRangesEncoded: "200:2:3",
                                  failedBlockCount: 2)
        let document = Fixture.markdown(Fixture.report(reply))
        #expect(document.contains("0x") == false, "no hex dump may appear")
        #expect(document.lowercased().contains("bytes read:") == false)
    }

    /// The run's configuration is on the record — a report whose reader cannot tell which mode
    /// produced it cannot tell whether an absent failure means "none" or "stopped at the first".
    @Test func theFailureModeIsRecorded() {
        #expect(Fixture.markdown(Fixture.report())
                    .contains("| Failure-handling mode | Log and continue |"))

        let stopped = Fixture.reply(outcome: .stoppedOnFailure, chunksProcessed: 2,
                                    failedRangeCount: 1, failedRangesEncoded: "200:2:3",
                                    failedBlockCount: 2, failureModeUsedCode: 1)
        #expect(Fixture.markdown(Fixture.report(stopped))
                    .contains("| Failure-handling mode | Stop on first error |"))
    }

    /// Timestamps are ISO 8601 with an offset. A persisted file is exactly the kind of document
    /// that travels: `05/08/2026` is 5 August or 8 May depending on who opens it, and a bare
    /// local time means nothing once the file leaves the machine that wrote it.
    @Test func timestampsAreUnambiguousAcrossLocales() {
        let document = Fixture.markdown(Fixture.report())
        #expect(document.contains("2026-"))
        #expect(document.contains("Z") || document.contains("+00:00"))
        #expect(document.contains("| Elapsed | 7.0 s |"))
    }

    /// The whole point of the file: it must be renderable and non-empty in every outcome.
    @Test func everyOutcomeProducesANonTrivialDocument() {
        let replies: [RunCycleOutcome] = [
            Fixture.reply(),
            Fixture.reply(failedRangeCount: 1, failedRangesEncoded: "8:2:1", failedBlockCount: 2),
            Fixture.reply(outcome: .stoppedOnFailure, chunksProcessed: 1, failedRangeCount: 1,
                          failedRangesEncoded: "8:2:3", failedBlockCount: 2,
                          failureModeUsedCode: 1),
            Fixture.reply(outcome: .stoppedOnFailure, chunksProcessed: 3),
        ]
        for reply in replies {
            let document = Fixture.markdown(Fixture.report(reply))
            #expect(document.count > 1_500)
            #expect(document.hasSuffix("\n"))
            #expect(document.hasPrefix("# USB drive test report"))
        }
    }
}
