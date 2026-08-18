//
//  RunReportPresentationTests.swift
//  USBDriveTesterTests
//
//  NFR-USE-8's one absolute: **pass/fail is never conveyed by colour alone.**
//
//  Until 2026-08-11 the report header's symbol and tint were two private funcs inside
//  `RunReportView`, so nothing here could reach them and the rule was held up by a comment. The
//  defect that would have slipped through is specific: give two results the same symbol, and the
//  tint becomes the only thing telling them apart — which compiles, renders plausibly, and is
//  invisible to anyone who cannot see the difference between green and orange.
//
//  The property below is stated over the pair a reader can actually perceive without colour:
//  **(symbol, headline)**. If that pair is unique across every result the app can produce, then the
//  tint is decoration and the requirement holds. If two results collide, it does not.
//
//  Run in greyscale on 2026-08-11 as well, in both appearances, which is the same question asked of
//  the pixels rather than of the types. Both agreed.
//

import Testing
import Foundation
@testable import USBDriveTester

private enum Fixture {

    static let started = Date(timeIntervalSince1970: 1_785_000_000)
    static let finished = Date(timeIntervalSince1970: 1_785_000_007)

    static let device = ReportedDevice(modelDescription: "Samsung Portable SSD T5",
                                       usbSerialNumber: "12345686DAA9",
                                       bsdNameAtRunTime: "disk8",
                                       capacityBytes: 1_000_204_886_016,
                                       logicalBlockSize: 512)

    /// A reply that lands on `outcome`, driven through the fields `RunReport.init` actually reads
    /// rather than by setting the outcome directly — so these are the reports the app builds.
    ///
    /// `cacheBypassCode` 1 is `.bypassed` (verified); 3 is `.inconclusive`, which qualifies. Any
    /// non-`.bypassed` verdict qualifies, so 3 stands for all of them.
    static func report(_ outcome: RunReportOutcome, qualified: Bool) -> RunReport {
        let wireOutcome: RunOutcomeCode
        let failedBlocks: UInt64
        switch outcome {
        case .completedClean:        wireOutcome = .completed;        failedBlocks = 0
        case .completedWithFailures: wireOutcome = .completed;        failedBlocks = 8
        case .stoppedOnError:        wireOutcome = .stoppedOnFailure; failedBlocks = 8
        case .incomplete:            wireOutcome = .stoppedOnFailure; failedBlocks = 0
        }
        let reply = RunCycleOutcome(runOutcomeCode: wireOutcome.rawValue,
                                    interruptedAtBlock: 0,
                                    chunksProcessed: wireOutcome.didComplete ? 256 : 2,
                                    failedRangeCount: failedBlocks > 0 ? 1 : 0,
                                    failureSummary: "",
                                    cacheBypassCode: qualified ? 3 : 1,
                                    bufferBytesHeld: 8 << 20,
                                    hostOverheadFraction: 0.0255,
                                    helperCoreFraction: 0.0422,
                                    failureModeUsedCode: 2,
                                    failedRangesEncoded: failedBlocks > 0 ? "0:8" : "",
                                    failedBlockCount: failedBlocks,
                                    sustainedReadBytesPerSecond: 517_000_000,
                                    sustainedWriteBytesPerSecond: 491_000_000,
                                    coverageBytesPerSecond: 245_000_000,
                                    readLatencySampleCount: 256,
                                    readLatencyMinimumNanoseconds: 1_100_000,
                                    readLatencyMaximumNanoseconds: 9_900_000,
                                    readLatencyP99UpperBoundNanoseconds: 2_195_000,
                                    message: "")
        return RunReport(reply: reply,
                         startBlock: 0,
                         blockCount: 2_097_152,
                         ioSizesUsed: [4 << 20],
                         device: device,
                         startedAt: started,
                         finishedAt: finished,
                         usbLinkSpeedDescription: "10 Gb/s (USB 3.1 Gen 2)")!
    }

    /// Every result the app can produce: four outcomes, verified and unverified.
    static var everyState: [(outcome: RunReportOutcome, qualified: Bool)] {
        RunReportOutcome.allCases.flatMap { [($0, false), ($0, true)] }
    }

    static func presentation(_ outcome: RunReportOutcome,
                             qualified: Bool) -> RunReportPresentation {
        RunReportPresentation.forResult(outcome: outcome, verifyResultIsQualified: qualified)
    }
}

@Suite("Run report presentation — NFR-USE-8")
struct RunReportPresentationTests {

    /// **The property with actual teeth: the four verified outcomes carry four DISTINCT symbols.**
    ///
    /// This is the one a real regression trips. The broader (symbol, headline) check below cannot
    /// catch a symbol collision on its own — the four headlines are distinct by construction, so
    /// that pair stays unique however many symbols are made identical. Written that way first, and
    /// it would have passed the exact edit it was meant to prevent, which is this project's
    /// oldest recurring mistake. Mutation-tested 2026-08-11: giving `.stoppedOnError` the clean
    /// pass's checkmark fails here, and fails nothing else in the suite.
    ///
    /// Scoped to the verified states on purpose — the unverified four share a symbol deliberately,
    /// which `everyUnverifiedResultLooksIdenticalExceptForItsWords` pins.
    @Test func theFourVerifiedOutcomesHaveFourDistinctSymbols() {
        let symbols = RunReportOutcome.allCases.map {
            Fixture.presentation($0, qualified: false).symbolName
        }
        #expect(Set(symbols).count == RunReportOutcome.allCases.count,
                "two verified outcomes share a symbol, leaving the tint to separate them: \(symbols)")
    }

    /// A backstop, and weaker than it looks: the four headlines are always distinct, so this can
    /// only fail if the **wording** collides, never if the symbols do. Kept for that case, and
    /// labelled so nobody mistakes it for the symbol check above.
    @Test func noTwoResultsAreToldApartByTheirTintAlone() {
        var seen: [String: (RunReportOutcome, Bool)] = [:]
        for state in Fixture.everyState {
            let symbol = Fixture.presentation(state.outcome, qualified: state.qualified).symbolName
            let headline = Fixture.report(state.outcome, qualified: state.qualified).headline
            // The pair a reader perceives with no colour vision at all.
            let key = symbol + "\u{0}" + headline
            #expect(seen[key] == nil,
                    "two results share a symbol AND a headline, so only the tint separates them")
            seen[key] = (state.outcome, state.qualified)
        }
        #expect(seen.count == 8)
    }

    /// The property above is only worth having if the tint genuinely **cannot** carry the meaning
    /// on its own. Two tints across eight states: it cannot. Without this, a build that gave every
    /// state its own tint would make the test above pass for the wrong reason.
    @Test func tintAloneCouldNeverDistinguishTheseResults() {
        let tints = Set(Fixture.everyState.map {
            Fixture.presentation($0.outcome, qualified: $0.qualified).tint
        })
        #expect(tints == Set(RunStatusTint.allCases))
        #expect(tints.count < Fixture.everyState.count)
    }

    /// An unverified result shows the same symbol and the same tint whatever it concluded — so for
    /// those four states the **words are the only carrier**, which is exactly why the headline is
    /// in the property above rather than the symbol on its own.
    @Test func everyUnverifiedResultLooksIdenticalExceptForItsWords() {
        let unverified = RunReportOutcome.allCases.map {
            Fixture.presentation($0, qualified: true)
        }
        #expect(Set(unverified.map(\.symbolName)) == ["questionmark.circle.fill"])
        #expect(Set(unverified.map(\.tint)) == [.cautionary])

        let headlines = Set(RunReportOutcome.allCases.map {
            Fixture.report($0, qualified: true).headline
        })
        #expect(headlines.count == 4, "the words must still separate all four")
    }

    /// A clean pass is the one result a reader most wants to take at a glance, so it is the one
    /// whose symbol must not be reachable by anything else.
    @Test func onlyAVerifiedCleanPassGetsTheCheckmark() {
        for state in Fixture.everyState {
            let symbol = Fixture.presentation(state.outcome, qualified: state.qualified).symbolName
            let isCleanAndVerified = state.outcome == .completedClean && !state.qualified
            #expect((symbol == "checkmark.circle.fill") == isCleanAndVerified)
        }
    }

    /// The affirmative tint is likewise reachable only by a verified clean pass.
    @Test func onlyAVerifiedCleanPassIsTintedAffirmative() {
        for state in Fixture.everyState {
            let tint = Fixture.presentation(state.outcome, qualified: state.qualified).tint
            let isCleanAndVerified = state.outcome == .completedClean && !state.qualified
            #expect((tint == .affirmative) == isCleanAndVerified)
        }
    }

    /// Every symbol is a real, non-empty name. A blank symbol renders as nothing at all, which
    /// would silently leave the tint carrying the whole meaning — the exact failure this suite is
    /// about, arriving by omission rather than by collision.
    @Test func everyResultHasASymbol() {
        for state in Fixture.everyState {
            let symbol = Fixture.presentation(state.outcome, qualified: state.qualified).symbolName
            #expect(!symbol.isEmpty)
            #expect(!symbol.hasPrefix("."))
        }
    }
}
