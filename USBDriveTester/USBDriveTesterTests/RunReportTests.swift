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
                      deviceReadBytesPerSecond: Double = 517_000_000,
                      writeBytesPerSecond: Double = 491_000_000,
                      coverageBytesPerSecond: Double = 245_000_000,
                      completedBytesPerSecond: Double = 238_000_000,
                      readLatencySampleCount: UInt64 = 256,
                      readLatencyMinimumNanoseconds: UInt64 = 1_100_000,
                      readLatencyMaximumNanoseconds: UInt64 = 9_900_000,
                      readLatencyP99UpperBoundNanoseconds: UInt64 = 2_195_000,
                      deviceLossPhaseCode: DeviceLossPhaseCode = .unrecognised) -> RunCycleOutcome {
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
                        deviceReadBytesPerSecond: deviceReadBytesPerSecond,
                        writeBytesPerSecond: writeBytesPerSecond,
                        coverageBytesPerSecond: coverageBytesPerSecond,
                        completedBytesPerSecond: completedBytesPerSecond,
                        readLatencySampleCount: readLatencySampleCount,
                        readLatencyMinimumNanoseconds: readLatencyMinimumNanoseconds,
                        readLatencyMaximumNanoseconds: readLatencyMaximumNanoseconds,
                        readLatencyP99UpperBoundNanoseconds: readLatencyP99UpperBoundNanoseconds,
                        message: "Cycle completed",
                        deviceLossPhaseCode: deviceLossPhaseCode.rawValue)
    }

    static func report(_ reply: RunCycleOutcome = Fixture.reply(),
                       endedBy: RunSequenceOutcome? = nil,
                       removalCallbackSaid: DeviceLossEnding? = nil,
                       device: ReportedDevice = Fixture.device(),
                       ioSizesUsed: [Int] = [4 << 20],
                       blockCount: UInt64 = 2_097_152,
                       linkSpeed: String? = "10 Gb/s (USB 3.1 Gen 2)") -> RunReport {
        RunReport(reply: reply,
                  endedBy: endedBy ?? ranTo(reply),
                  removalCallbackSaid: removalCallbackSaid,
                  startBlock: 0,
                  blockCount: blockCount,
                  ioSizesUsed: ioSizesUsed,
                  device: device,
                  startedAt: started,
                  finishedAt: finished,
                  usbLinkSpeedDescription: linkSpeed)!
    }

    /// **The ordinary case: a run that ended the way its last call did.**
    ///
    /// A fixture convenience and nothing more. It is deliberately the inference that
    /// ``RunReport/init(reply:endedBy:startBlock:blockCount:ioSizesUsed:device:startedAt:finishedAt:usbLinkSpeedDescription:)``
    /// **stopped** making in increment 8 — which is safe here and was not there, because a test
    /// that cares about the two diverging says so by passing `endedBy:` explicitly, and a test
    /// that does not is asserting about a run whose last call is the whole story.
    ///
    /// Its existence is what lets the tests written before increment 8 keep meaning exactly what
    /// they meant: they describe replies, and each one's run ended as that reply says.
    static func ranTo(_ reply: RunCycleOutcome) -> RunSequenceOutcome {
        switch reply.outcome {
        case .completed:                    return .completed
        case .stoppedOnFailure:             return .stoppedOnFailure
        case .pausedByUser, .stoppedByUser: return .stoppedByUser
        case .deviceLost:                   return .deviceLost
        case .unrecognised:                 return .callFailed(reason: reply.message)
        }
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
                                    deviceReadBytesPerSecond: -1,
                                    writeBytesPerSecond: -1,
                                    coverageBytesPerSecond: -1,
                                    completedBytesPerSecond: -1,
                                    readLatencySampleCount: 0)
        #expect(RunReport(reply: refused, endedBy: .callFailed(reason: "refused"),
                          removalCallbackSaid: nil,
                          startBlock: 0, blockCount: 2_097_152,
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
        #expect(RunReport(reply: stopped, endedBy: .stoppedOnFailure,
                          removalCallbackSaid: nil,
                          startBlock: 0, blockCount: 2_097_152,
                          ioSizesUsed: [4 << 20], device: Fixture.device(),
                          startedAt: Fixture.started, finishedAt: Fixture.finished) != nil)
    }

    @Test func aReplyFromANewerHelperWithAnUnknownModeProducesNoReport() {
        let strange = Fixture.reply(failureModeUsedCode: 99)
        #expect(RunReport(reply: strange, endedBy: .completed,
                          removalCallbackSaid: nil,
                          startBlock: 0, blockCount: 2_097_152,
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

    /// Walked over `allCases`, **not over a hand-written list**, which is what it was until
    /// increment 8. `RunReportOutcome` has been `CaseIterable` since 2026-08-11 precisely so a new
    /// outcome cannot arrive uncovered — and this test was written the same week with the four
    /// cases spelled out, which gave that conformance away in the one place it was for.
    @Test func everyOutcomeCarriesAHeadlineAndAnExplanation() {
        for outcome in RunReportOutcome.allCases {
            #expect(outcome.headline.isEmpty == false)
            #expect(outcome.explanation.count > 40, "\(outcome) has no real explanation")
        }
    }
}

// MARK: - FR-RPT-4: "stopped by user", and where the outcome comes from

/// **Increment 8.** The outcome is decided by how the *run* ended, not by how its last *call* did.
///
/// A run is a sequence of bounded calls (CONSTRAINTS section 2), so "the user stopped it" is a fact
/// no single reply holds. Inferring it from the last one was wrong in three ways, and these are
/// those three ways written down.
struct StoppedByUserOutcomeTests {

    /// The ordinary Stop press, from `running`: the helper acts on the level at its next chunk
    /// boundary and the call comes back saying so.
    @Test func aRunTheUserStoppedIsReportedAsStoppedByUser() {
        let reply = Fixture.reply(outcome: .stoppedByUser, chunksProcessed: 12)
        #expect(Fixture.report(reply, endedBy: .stoppedByUser).outcome == .stoppedByUser)
    }

    /// **The one that mattered.** Stop pressed while a call was already finishing: the helper
    /// completes that call normally and replies `completed`, and `RunSequencer` then declines to
    /// issue the next one — so the run ended `stoppedByUser` with a reply saying it completed.
    ///
    /// The reply-only inference read `didComplete` and called that **"Completed — no
    /// currently-unreadable blocks were found"**, against a `blockCount` of the whole device, for a
    /// run that may have covered a fraction of it. A false clean pass, in a file that outlives the
    /// session and is the artefact a drive's history is kept in.
    @Test func aStopThatRacedACompletingCallIsNotReportedAsACleanPass() {
        let reply = Fixture.reply(outcome: .completed, chunksProcessed: 256)
        let report = Fixture.report(reply, endedBy: .stoppedByUser)

        #expect(report.outcome == .stoppedByUser)
        #expect(report.outcome != .completedClean)
        #expect(report.outcome.didCoverTheRequestedRange == false)
        #expect(!report.headline.lowercased().contains("no currently-unreadable blocks were found"))
    }

    /// Stop from `paused`: nothing is in flight and no reply is coming, so the last thing the
    /// helper said was `pausedByUser`. That read as `incomplete` — *"no failure was recorded that
    /// would account for it"* — for a run a person deliberately ended.
    @Test func stoppingFromAPauseIsReportedAsStoppedByUserAndNotAsIncomplete() {
        let reply = Fixture.reply(outcome: .pausedByUser, chunksProcessed: 40)
        #expect(Fixture.report(reply, endedBy: .stoppedByUser).outcome == .stoppedByUser)
    }

    /// Decision 2026-08-20: quitting cancels the run, which the confirmation says outright, so the
    /// report says the same thing a Stop press does.
    @Test func quittingDuringARunIsReportedAsStoppedByUser() {
        let reply = Fixture.reply(outcome: .completed, chunksProcessed: 64)
        #expect(Fixture.report(reply, endedBy: .haltedForQuit).outcome == .stoppedByUser)
    }

    /// A user can stop a run that has already logged bad blocks. ``RunReportOutcome/foundFailures``
    /// says nothing either way for this case **on purpose** — the failed-range list is the
    /// authority, and it must survive the outcome not mentioning it.
    @Test func aRunTheUserStoppedAfterFailuresStillReportsThem() {
        let reply = Fixture.reply(outcome: .stoppedByUser,
                                  chunksProcessed: 12,
                                  failedRangeCount: 1,
                                  failedRangesEncoded: "200:2:3",
                                  failedBlockCount: 2)
        let report = Fixture.report(reply, endedBy: .stoppedByUser)

        #expect(report.outcome == .stoppedByUser)
        #expect(report.outcome.foundFailures == false, "the OUTCOME implies nothing either way")
        #expect(report.failedBlockCount == 2, "and the run's own findings must survive that")
        #expect(report.failedRanges?.isEmpty == false)
    }

    /// The contradiction guard on the completed path, which is the mirror of the one on
    /// `stoppedOnFailure`. Two sources disagreeing about whether the range was covered is not
    /// something to resolve by picking the cheerful one.
    @Test func aRunWhoseEndingAndReplyDisagreeAboutCompletionIsCalledIncomplete() {
        let reply = Fixture.reply(outcome: .stoppedByUser, chunksProcessed: 12)
        #expect(RunReportOutcome.forRun(endedBy: .completed,
                                        replyDidComplete: reply.didComplete,
                                        foundFailures: false) == .incomplete)
    }

    /// A call that could not be made or was refused. Where no call ever returned there is no report
    /// at all; where an earlier one did, this is what the report says.
    @Test func aCallFailureIsCalledIncomplete() {
        #expect(RunReportOutcome.forRun(endedBy: .callFailed(reason: "connection interrupted"),
                                        replyDidComplete: false,
                                        foundFailures: false) == .incomplete)
        #expect(RunReportOutcome.forRun(endedBy: .callFailed(reason: "connection interrupted"),
                                        replyDidComplete: false,
                                        foundFailures: true) == .incomplete)
    }

    /// **The property, stated over the whole table rather than over the rows above.** However the
    /// run ended, a reply claiming completion must never on its own produce a clean pass — that is
    /// the shape of the defect, and it is worth asserting as a rule so a future ending cannot
    /// reintroduce it by being added to the wrong branch.
    @Test func onlyARunThatActuallyCompletedCanBeReportedAsCompleted() {
        let endings: [RunSequenceOutcome] = [.stoppedOnFailure, .stoppedByUser, .haltedForQuit,
                                             .callFailed(reason: "x")]
        for ending in endings {
            for foundFailures in [false, true] {
                let outcome = RunReportOutcome.forRun(endedBy: ending,
                                                      replyDidComplete: true,
                                                      foundFailures: foundFailures)
                #expect(outcome.didCoverTheRequestedRange == false,
                        "\(ending) with a completing reply read as having covered the range")
            }
        }
    }

    /// And the other half: a run that did complete is still reported on its findings, so the rule
    /// above cannot be satisfied by refusing to say "completed" at all.
    @Test func aRunThatCompletedIsStillSplitByWhetherItFoundAnything() {
        #expect(RunReportOutcome.forRun(endedBy: .completed,
                                        replyDidComplete: true,
                                        foundFailures: false) == .completedClean)
        #expect(RunReportOutcome.forRun(endedBy: .completed,
                                        replyDidComplete: true,
                                        foundFailures: true) == .completedWithFailures)
    }

    // MARK: The wording

    /// The headline names the actor, because "stopped" alone is what `stoppedOnError` also says and
    /// the difference between them is the whole point.
    @Test func theStoppedByUserHeadlineSaysWhoStoppedItAndWhatThatLeftUntested() {
        let headline = RunReportOutcome.stoppedByUser.headline.lowercased()
        #expect(headline.contains("stopped by the user"))
        #expect(headline.contains("not tested"))
    }

    /// FR-FAIL-7 in the report's own voice: this is not a run that can be picked up again, and a
    /// reader deciding what to do next needs to be told so here rather than discovering it at the
    /// controls.
    @Test func theStoppedByUserExplanationSaysItCannotBeContinued() {
        let explanation = RunReportOutcome.stoppedByUser.explanation.lowercased()
        #expect(explanation.contains("cannot be continued"))
        #expect(explanation.contains("has not passed"))
    }

    /// BUILD-PLAN 10.5's wording rule reaches every outcome, not only the clean one: no outcome may
    /// call the drive healthy. `completedClean`'s explanation uses the phrase *"not a clean bill of
    /// health"*, which is the rule being stated rather than broken — so the word tested for is
    /// "healthy", which has no such negated use anywhere.
    @Test func noOutcomeCallsTheDriveHealthy() {
        for outcome in RunReportOutcome.allCases {
            let text = (outcome.headline + " " + outcome.explanation).lowercased()
            #expect(!text.contains("healthy"), "\(outcome) called the drive healthy")
        }
    }
}

// MARK: - FR-DEV-8: the drive left, and what the report may say about it

/// **Step 12, chunk 5.** The outcome that replaced chunks 3 and 4's interim `.incomplete`.
///
/// The distinction being defended throughout: a device loss is an event that happened to the
/// **drive's presence**, not a finding about the **data on it**. Every assertion here is either
/// "the report says what happened" or "the report does not accuse anybody of anything", and the
/// second kind is the reason this outcome exists rather than being folded into one of the four
/// that already existed.
struct DeviceLostOutcomeTests {

    /// The replacement itself. `.incomplete` was honest while the app could not say why a run
    /// ended; it asserts that *nothing accounts for* the ending, which stopped being true at
    /// chunk 3.
    @Test func aLostDeviceIsItsOwnOutcomeAndNoLongerIncomplete() {
        let outcome = RunReportOutcome.forRun(endedBy: .deviceLost,
                                              replyDidComplete: false,
                                              foundFailures: false)

        #expect(outcome == .deviceLost)
        #expect(outcome != .incomplete)
    }

    /// **Unconditional, unlike `stoppedOnFailure` beside it.**
    ///
    /// A stop-on-error with no failed range is a reply contradicting itself, and `forRun` refuses
    /// to report it. A device loss with no failed range is not a contradiction at all — most of
    /// them will have none — and a device loss *with* failures is an ordinary sequence: the run
    /// logged bad blocks and then the drive went. Both must land on `deviceLost`, and a guard
    /// copied from the case above would send the first to `incomplete`.
    @Test func aLostDeviceKeepsItsOutcomeWithOrWithoutFailures() {
        for foundFailures in [false, true] {
            for replyDidComplete in [false, true] {
                #expect(RunReportOutcome.forRun(endedBy: .deviceLost,
                                                replyDidComplete: replyDidComplete,
                                                foundFailures: foundFailures) == .deviceLost,
                        "failures=\(foundFailures) complete=\(replyDidComplete)")
            }
        }
    }

    /// It did not cover the range, and it did not find failures **on its own**.
    ///
    /// The second half is the one that matters: `foundFailures` is what a renderer would key on to
    /// decide whether to accuse the drive, and a device loss must not. The failed-range table is
    /// the authority on what a cut-short run found, exactly as it is for `stoppedByUser`.
    @Test func aLostDeviceCoversNothingAndAccusesNothing() {
        #expect(RunReportOutcome.deviceLost.didCoverTheRequestedRange == false)
        #expect(RunReportOutcome.deviceLost.foundFailures == false)
    }

    /// The headline states the observation and stops there.
    ///
    /// **It must not say "disconnected"** in a way that asserts a hand on a cable: both detection
    /// routes observe the same narrower fact — the device stopped being addressable — and which of
    /// unplug or de-enumeration produced it is the thing this tool cannot determine. The
    /// explanation is where that ambiguity is spelled out, which is why it is tested for there.
    @Test func theHeadlineSaysWhatWasObservedAndTheExplanationSaysWhatIsUnknown() {
        let headline = RunReportOutcome.deviceLost.headline.lowercased()
        #expect(headline.contains("disappeared"))
        #expect(headline.contains("not tested"))

        let explanation = RunReportOutcome.deviceLost.explanation.lowercased()
        #expect(explanation.contains("unplugged"))
        #expect(explanation.contains("dropped off the usb bus"))
        #expect(explanation.contains("cannot tell"), "the report claimed to know which of the two")
        #expect(explanation.contains("cannot be continued"), "FR-FAIL-7 went unsaid")
        #expect(explanation.contains("not tested"))
    }

    /// The wording no other outcome may borrow, and the one this whole step exists to prevent.
    ///
    /// On 2026-08-06 a de-enumeration was written up as **2,095,104 bad blocks**. The failure being
    /// tested for is not that phrasing coming back — it is the softer version, an outcome that
    /// mentions the drive failing when what failed was its presence.
    @Test func theLostDeviceOutcomeNeverBlamesTheDrive() {
        let text = (RunReportOutcome.deviceLost.headline + " "
                  + RunReportOutcome.deviceLost.explanation).lowercased()

        for accusation in ["bad block", "unreadable", "faulty", "the drive failed", "defective"] {
            #expect(!text.contains(accusation), "the outcome accused the drive: \(accusation)")
        }
    }

    // MARK: The account reaches the report

    /// Route (a): the reply carried the block and the phase, so the report does too.
    @Test func theHelpersOwnAccountReachesTheReport() {
        let report = Fixture.report(Fixture.reply(outcome: .deviceLost,
                                                  interruptedAtBlock: 4_194_304,
                                                  chunksProcessed: 12,
                                                  deviceLossPhaseCode: .writingBack),
                                    removalCallbackSaid: nil)

        #expect(report.outcome == .deviceLost)
        #expect(report.deviceLoss == .theHelperSaidWhere(block: 4_194_304, phase: .writingBack))
        #expect(report.deviceLoss?.aWriteBackMayBeUnfinished == true)
    }

    /// Route (b): the reply is the *previous* call's, so it carries no loss detail at all, and the
    /// removal callback is the only thing that can account for the ending.
    ///
    /// **This is the case the extra `RunReport.init` parameter exists for.** Without it the report
    /// would fall through to the conservative answer and warn about a part-written chunk on a run
    /// that was demonstrably paused with nothing outstanding.
    @Test func theRemovalCallbacksAccountReachesTheReportWhenTheReplyCannot() {
        let pausedReply = Fixture.reply(outcome: .pausedByUser, chunksProcessed: 12)

        let paused = Fixture.report(pausedReply, endedBy: .deviceLost,
                                    removalCallbackSaid: .nothingWasInFlight)
        #expect(paused.deviceLoss == .nothingWasInFlight)
        #expect(paused.deviceLoss?.aWriteBackMayBeUnfinished == false)

        let silent = Fixture.report(pausedReply, endedBy: .deviceLost,
                                    removalCallbackSaid: .theHelperNeverAnswered)
        #expect(silent.deviceLoss == .theHelperNeverAnswered)
        #expect(silent.deviceLoss?.aWriteBackMayBeUnfinished == true)
    }

    /// **The two halves of one fact cannot drift apart.**
    ///
    /// The renderers key on both — the outcome for the headline, the account for what may be said
    /// about the chunk in flight — so a report with one and not the other would print a headline
    /// about a vanished drive with no account of it, or an account under a headline that never
    /// mentions one. Walked over every outcome, so this holds for the five that must have no
    /// account as firmly as for the one that must.
    @Test func anAccountExistsExactlyWhenTheOutcomeSaysTheDriveWentAway() throws {
        let replies: [RunReportOutcome: RunCycleOutcome] = [
            .completedClean: Fixture.reply(),
            .completedWithFailures: Fixture.reply(failedRangeCount: 1,
                                                  failedRangesEncoded: "200:2:3",
                                                  failedBlockCount: 2),
            .stoppedOnError: Fixture.reply(outcome: .stoppedOnFailure, failedRangeCount: 1,
                                           failedRangesEncoded: "200:2:3", failedBlockCount: 2),
            .stoppedByUser: Fixture.reply(outcome: .stoppedByUser),
            .incomplete: Fixture.reply(outcome: .stoppedOnFailure),
            .deviceLost: Fixture.reply(outcome: .deviceLost, interruptedAtBlock: 64,
                                       deviceLossPhaseCode: .reading),
        ]

        for outcome in RunReportOutcome.allCases {
            let reply = try #require(replies[outcome])
            let report = Fixture.report(reply)
            #expect(report.outcome == outcome, "the fixture for \(outcome) built a different one")
            #expect(report.deviceLossAccountAgreesWithTheOutcome,
                    "\(outcome): outcome and account disagree")
        }
    }

    /// FR-TEST-9's clause reaches this outcome like every other non-clean one.
    ///
    /// Worth its own test rather than trusting the `switch`: an unverified read cannot invent a
    /// mismatch but it can hide one, and a run cut short by a vanishing drive may have found real
    /// failures before it went. "There may be more" is as true here as for a run a person stopped.
    @Test func anUnverifiedLostDeviceStillSaysThereMayBeMore() {
        let report = Fixture.report(Fixture.reply(outcome: .deviceLost,
                                                  cacheBypassCode: 3,
                                                  deviceLossPhaseCode: .reading))

        #expect(report.verifyResultIsQualified)
        #expect(report.headline.contains("NOT VERIFIED"))
        #expect(report.headline.contains("there may be more"))
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
        #expect(document.contains("| Read throughput | 517 MB/s |"))
        #expect(document.contains("| Write throughput | 491 MB/s |"))
        // Increment 11. A distinct fixture value, so this cannot pass with write's figure in it —
        // on real healthy hardware the two are equal and no assertion could tell them apart.
        #expect(document.contains("| R-W-R-C speed | 238 MB/s |"))
        // **No `Covering` row, since Step 11 increment 10.** Asserted as an absence rather than
        // simply dropped: the row was deleted from the panel, this export and the report sheet
        // together, and a test that merely stopped mentioning it would pass just as well if the
        // row came back. The figure it named counted *attempted* work under a label that reads as
        // successful work.
        #expect(document.contains("Covering") == false)
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
        let reply = Fixture.reply(deviceReadBytesPerSecond: -1,
                                  writeBytesPerSecond: -1,
                                  coverageBytesPerSecond: -1,
                                  completedBytesPerSecond: -1,
                                  readLatencySampleCount: 0)
        let report = Fixture.report(reply)
        #expect(report.deviceReadBytesPerSecond == nil)

        let document = Fixture.markdown(report)
        #expect(document.contains("| Read throughput | — |"))
        #expect(document.contains("| Write throughput | — |"))
        #expect(document.contains("| R-W-R-C speed | — |"))
        #expect(document.contains("Covering") == false)
        #expect(document.contains("0 MB/s") == false)
        #expect(document.contains("-1") == false)
    }

    /// A genuinely stalled drive reports zero, and that must survive as a measurement.
    @Test func aZeroRateIsPrintedBecauseItIsAMeasurement() {
        let reply = Fixture.reply(deviceReadBytesPerSecond: 0)
        // Falls through to kB/s at this magnitude, which is still a number and still zero.
        #expect(Fixture.markdown(Fixture.report(reply)).contains("| Read throughput | 0 kB/s |"))
    }

    /// **The report says what it measured.** A rate whose denominator is unstated cannot be
    /// checked against anything — which is how the app spent a week showing figures 1.5x and 3.4x
    /// what Activity Monitor showed for the same drive, with nothing on screen or in the file to
    /// reveal the mismatch (2026-08-17).
    ///
    /// The report matters more than the screen here: it is the copy that gets forwarded and
    /// re-read months later, detached from whatever was on screen at the time.
    /// **Asserted against the shared constant, not against a copy of its words.**
    ///
    /// A test spelling the sentence out again would be a third place it exists, and would pass
    /// while the report window showed something else — which is exactly what happened on
    /// 2026-08-18: the export was updated, the screen kept the stale text naming the
    /// manufacturer's advertised figure, and nothing failed. Comparing against
    /// `ThroughputFraming` is what makes this a check on the single definition rather than on a
    /// duplicate of it.
    @Test func theReportStatesWhatItsThroughputFiguresMean() {
        let document = Fixture.markdown(Fixture.report())
        #expect(document.contains(ThroughputFraming.definition.markdown),
                "the export no longer carries the shared definition verbatim")
        #expect(document.contains(ThroughputFraming.notGraded.markdown),
                "the export no longer carries the shared not-graded framing verbatim")
    }

    /// **The definition must name every rate the table shows, and must not explain one it does
    /// not** — and the list is read out of the rendered document rather than written here.
    ///
    /// This is the drift that has already happened twice in this file's history, both times in a
    /// sentence stating a *count*. Increment 10 deleted `Covering` from the table and left "All
    /// three rates" standing for a day; increment 11 added `R-W-R-C speed` and the same sentence
    /// had to move a third time. A count in prose is a fact about the table, and nothing
    /// recomputes prose.
    ///
    /// Deriving the labels is what makes this self-maintaining: a fourth rate added to the report
    /// and not to the definition fails here without anybody remembering to edit a test.
    @Test func theDefinitionNamesEveryRateTheReportTabulatesAndNoOther() throws {
        let document = Fixture.markdown(Fixture.report())
        let definition = ThroughputFraming.definition.plain

        // Table rows carrying a byte-rate unit. The link-speed row reads `Gb/s` and is not one.
        let rateNames = document
            .split(separator: "\n")
            .filter { $0.hasPrefix("| ") }
            .filter { $0.contains("MB/s") || $0.contains("GB/s") || $0.contains("kB/s") }
            .compactMap { $0.split(separator: "|").first?.trimmingCharacters(in: .whitespaces) }
            .compactMap { $0.split(separator: " ").first.map(String.init) }

        // An empty parse is not a pass. Three rates today; more would still have to be named.
        #expect(rateNames.count >= 3,
                "parsed \(rateNames.count) rate row(s) — the table or this parse has moved")

        for rate in rateNames {
            #expect(definition.contains(rate),
                    "the report tabulates a \(rate) rate the definition never explains")
        }

        // The other half, without which a definition naming everything would pass unconditionally:
        // it must not explain a figure no surface shows. `coverageBytesPerSecond` is on the wire
        // and on no screen, deliberately, since increment 10.
        #expect(definition.lowercased().contains("covering") == false,
                "the definition explains a rate no surface displays")
        #expect(document.contains("Covering") == false)
    }

    /// **The definition must warn that these figures will not match another tool, and this is the
    /// only thing asserting it.**
    ///
    /// FR-METR-1's 2026-09-02 amendment put the displayed rates back on phase time, where they
    /// read about 1.5× and 3.4× what Activity Monitor shows for the same drive. That exact
    /// discrepancy was filed as a bug on 2026-08-17 and was the reason for the v12 denominator;
    /// the amendment is defensible **only** because the reader is now told. The disclaimer is not
    /// commentary on the change, it is the half of it that makes the other half safe.
    ///
    /// Nothing covered it. `theDefinitionNamesEveryRateTheReportTabulatesAndNoOther` checks which
    /// rates are named, `theReportStatesWhatItsThroughputFiguresMean` compares the document
    /// against the constant — and both move together when the constant is edited, so the sentence
    /// could have been deleted outright with 1092 tests green. Written when that was noticed
    /// while trying to mutate it.
    ///
    /// **Asserted on meaning, not on a magic string.** The tool has to be named, because "measured
    /// over the time the drive spent doing that work" is technically complete and would not stop
    /// anyone opening Activity Monitor and concluding this app is broken. And the claim has to be
    /// a *denial*: the pre-v14 wording named the same tool to promise agreement, so naming alone
    /// would pass on a sentence saying the opposite of what is now true.
    @Test func theDefinitionWarnsThatTheFiguresDoNotMatchAnOutsideObserver() throws {
        let definition = ThroughputFraming.definition.plain

        #expect(definition.contains("Activity Monitor"),
                "the definition must name the tool these figures will not agree with")

        // The sentence carrying the name must deny comparability rather than assert it.
        let sentence = try #require(
            definition.split(separator: ".").first(where: { $0.contains("Activity Monitor") }),
            "no sentence names Activity Monitor")
        #expect(sentence.contains("not comparable"),
                "Activity Monitor is named without denying comparability: \(sentence)")

        // The v12-to-v13 wording, which named the tool to promise the opposite. Its return would
        // mean the figures and the sentence describing them had come apart again.
        #expect(definition.contains("directly comparable") == false,
                "the definition promises agreement with a tool it will disagree with")
    }

    /// The plain rendering a non-Markdown surface uses is *derived*, so it cannot say something
    /// different from the Markdown one.
    @Test func thePlainRenderingIsTheSameSentenceWithoutTheAsterisks() {
        for claim in [ThroughputFraming.definition, ThroughputFraming.notGraded] {
            #expect(claim.plain.contains("**") == false, "emphasis markers reached a plain surface")
            #expect(claim.plain == claim.markdown.replacingOccurrences(of: "**", with: ""))
        }
    }

    /// The advertised-rate comparison is gone from BOTH surfaces, and must stay gone.
    ///
    /// It was dropped on 2026-08-18: these rates describe a mixed read-write-verify workload and
    /// an advertised rating is pure sequential, so inviting the comparison makes a healthy drive
    /// look worn — the exact bias the FR document warns against.
    @Test func neitherSurfaceInvitesAComparisonAgainstTheAdvertisedRate() {
        let document = Fixture.markdown(Fixture.report())
        for surface in [document, ThroughputFraming.definition.plain,
                        ThroughputFraming.notGraded.plain] {
            #expect(surface.lowercased().contains("advertised sustained") == false)
            #expect(surface.lowercased().contains("compare these against") == false)
        }
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
        #expect(document.contains("Read throughput"))
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
    /// being read as one.
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

    /// **The row says what it holds** (increment 8). It is the range the run *asked for*, and it
    /// read "Range tested" until FR-CTRL-4's Stop control made those two different things — at
    /// which point a run stopped early printed its whole requested range under that word, three
    /// lines below an outcome saying the rest had not been tested.
    @Test func theRangeRowIsLabelledAsRequestedRatherThanTested() {
        let document = Fixture.markdown(Fixture.report())
        #expect(document.contains("| Range requested |"))
        #expect(document.contains("| Range tested |") == false,
                "the row claims the range was tested, which a stopped run makes false")
    }

    /// A run that did not reach the end of its range says so, **whether or not** the range was the
    /// whole drive — the two caveats are about different facts and neither substitutes for the
    /// other.
    @Test func aRunThatDidNotReachTheEndOfItsRangeSaysSo() {
        let stopped = Fixture.report(Fixture.reply(outcome: .stoppedByUser, chunksProcessed: 12),
                                     endedBy: .stoppedByUser,
                                     blockCount: 1_953_525_168)   // the whole drive, so only this caveat
        let document = Fixture.markdown(stopped)

        #expect(document.contains(HonestFraming.rangeWasNotReachedToItsEnd.markdown))
        #expect(document.contains("**not the whole drive**") == false,
                "a whole-device run must not be told its range was smaller than the drive")
    }

    /// Both at once, for a bounded run that was also stopped early. They compose rather than
    /// contradict — which is what the reworded bounded-range sentence is for.
    @Test func aBoundedRunStoppedEarlyCarriesBothCaveats() {
        let stopped = Fixture.report(Fixture.reply(outcome: .stoppedByUser, chunksProcessed: 12),
                                     endedBy: .stoppedByUser)
        let document = Fixture.markdown(stopped)

        #expect(document.contains(HonestFraming.rangeWasSmallerThanTheDrive.markdown))
        #expect(document.contains(HonestFraming.rangeWasNotReachedToItsEnd.markdown))
    }

    /// The bounded-range sentence no longer **asserts** that the run covered the range, which is
    /// the false claim it carried. Pinned on the phrase rather than on the whole sentence, so a
    /// reword cannot quietly put the assertion back.
    @Test func theBoundedRangeCaveatDoesNotClaimTheRunCoveredIt() {
        let text = HonestFraming.rangeWasSmallerThanTheDrive.plain.lowercased()
        #expect(text.contains("this run covered") == false,
                "the caveat asserts coverage again, which a stopped run makes false")
    }

    /// A whole-device run that finished has nothing to qualify — the case that stops the caveats
    /// being unconditional decoration.
    @Test func aCompletedWholeDriveRunCarriesNoRangeCaveatsAtAll() {
        let report = Fixture.report(blockCount: 1_953_525_168)
        #expect(report.rangeCaveats.isEmpty)
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

// MARK: - FR-DEV-8 in the exported document

/// **Step 12, chunk 5.** What the `.md` file says about a drive that left.
///
/// The exported file is the surface that matters most for this outcome, because it is the one that
/// outlives the drive being reattached. A person reading it a week later has no other way to find
/// out what the run was doing when the device went.
struct DeviceLostMarkdownTests {

    /// The account is in the document, and it is `HonestFraming`'s sentence verbatim.
    ///
    /// Compared against the shared claim rather than against a literal, which is this file's
    /// governing rule: a literal here would be a second copy of the sentence and the thing that
    /// lets the window and the export drift apart.
    @Test func theAccountIsInTheDocumentInTheSharedWording() {
        let account = DeviceLossAccount.theHelperSaidWhere(block: 4_194_304, phase: .writingBack)
        let document = Fixture.markdown(Fixture.report(
            Fixture.reply(outcome: .deviceLost, interruptedAtBlock: 4_194_304,
                          chunksProcessed: 12, deviceLossPhaseCode: .writingBack)))

        #expect(document.contains(HonestFraming.claim(about: account).markdown))
    }

    /// **The block is spelled the same way in the sentence and in the row.**
    ///
    /// It was not, when this was written: the sentence interpolated the raw `UInt64` while the row
    /// used the grouped formatter, so one document offered `block 4194304` and `block 4,194,304`
    /// as separate readings a paragraph apart. A reader comparing two reports would have had to
    /// work out that those are the same number.
    @Test func theBlockIsSpelledTheSameWayInTheSentenceAndTheRow() {
        let document = Fixture.markdown(Fixture.report(
            Fixture.reply(outcome: .deviceLost, interruptedAtBlock: 4_194_304,
                          chunksProcessed: 12, deviceLossPhaseCode: .writingBack)))

        #expect(document.contains("4,194,304"))
        #expect(!document.contains("4194304"), "the block appears ungrouped somewhere")
    }

    /// Where a route could say, the block and the phase get rows of their own — a reader comparing
    /// reports scans for figures rather than re-reading prose.
    @Test func aKnownBlockAndPhaseGetTheirOwnRows() {
        let document = Fixture.markdown(Fixture.report(
            Fixture.reply(outcome: .deviceLost, interruptedAtBlock: 512,
                          chunksProcessed: 4, deviceLossPhaseCode: .verifying)))

        #expect(document.contains("| Drive left at | block 512 |"))
        #expect(document.contains("| While | \(DeviceLossPhaseCode.verifying.description) |"))
    }

    /// **Where no route could say, there is no row — not a zero and not an em-dash.**
    ///
    /// This file's standing rule about a measurement that was not taken, applied to the one figure
    /// where a placeholder would be actively misleading: `block 0` is a real reading, and a reader
    /// has no way to tell an invented one from a genuine loss at the start of the drive.
    @Test func anUnknownBlockGetsNoRowAtAll() {
        let document = Fixture.markdown(Fixture.report(
            Fixture.reply(outcome: .pausedByUser, chunksProcessed: 12),
            endedBy: .deviceLost,
            removalCallbackSaid: .nothingWasInFlight))

        #expect(document.contains(HonestFraming.claim(about: .nothingWasInFlight).markdown))
        #expect(!document.contains("Drive left at"), "a block was printed that nothing measured")
        #expect(!document.contains("| While |"))
    }

    /// **The account sits below FR-TEST-9's statement and above the drive**, which is the placement
    /// argued for in both renderers.
    ///
    /// Below, because nothing may come between the outcome line and whether the check behind it can
    /// be trusted — this file's header states that as a requirement. Above everything else, because
    /// it is the only part of the document a reader cannot reconstruct once the drive is gone.
    @Test func theAccountSitsBelowTheCacheVerdictAndAboveTheDrive() {
        let report = Fixture.report(Fixture.reply(outcome: .deviceLost, interruptedAtBlock: 64,
                                                  chunksProcessed: 2,
                                                  deviceLossPhaseCode: .reading))
        let document = Fixture.markdown(report)

        let bypass = document.range(of: "Cache bypass")
        let account = document.range(of: HonestFraming.claim(about: .theHelperSaidWhere(
            block: 64, phase: .reading)).markdown)
        let drive = document.range(of: "## Drive")

        #expect(bypass != nil && account != nil && drive != nil)
        if let bypass, let account, let drive {
            #expect(bypass.lowerBound < account.lowerBound, "the account preceded the cache verdict")
            #expect(account.lowerBound < drive.lowerBound, "the account fell below the drive table")
        }
    }

    /// No account, no section. Every other outcome's document is unchanged by chunk 5.
    @Test func aRunThatKeptItsDriveGetsNoAccountAtAll() {
        for reply in [Fixture.reply(),
                      Fixture.reply(outcome: .stoppedByUser),
                      Fixture.reply(outcome: .stoppedOnFailure, failedRangeCount: 1,
                                    failedRangesEncoded: "8:2:3", failedBlockCount: 2)] {
            let document = Fixture.markdown(Fixture.report(reply))
            #expect(!document.contains("Drive left at"))
            #expect(!document.contains("The drive left while"))
            #expect(!document.lowercased().contains("partly written"))
        }
    }

    /// A device-loss document is a whole document: every heading, and the failed-range table that
    /// says what the run found before the drive went.
    @Test func aDeviceLossDocumentIsStillAWholeReport() {
        let document = Fixture.markdown(Fixture.report(
            Fixture.reply(outcome: .deviceLost, interruptedAtBlock: 200, chunksProcessed: 3,
                          failedRangeCount: 1, failedRangesEncoded: "200:2:3", failedBlockCount: 2,
                          deviceLossPhaseCode: .writingBack)))

        for heading in ["# USB drive test report", "## Outcome", "## Drive", "## Run",
                        "## Failed block ranges", "## Measurements",
                        "## What this test does and does not prove"] {
            #expect(document.contains(heading), "missing \(heading)")
        }
        #expect(document.contains(HonestFraming.rangeBeyondTheDisconnectionWasNotTested.markdown))
        #expect(document.count > 1_500)
        #expect(document.hasSuffix("\n"))
    }
}
