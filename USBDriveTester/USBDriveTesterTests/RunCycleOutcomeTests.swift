//
//  RunCycleOutcomeTests.swift
//  Decoding protocol v9's cycle reply — the values the end-of-run report is built from.
//  Step 10, increment 3.
//
//  ## What this suite is actually defending against
//
//  Not "does the decode work". **Transposition.** The reply is nineteen positional values, and
//  among them sit two adjacent `Double` rates and four adjacent `UInt64` latency figures. It is
//  assembled in the helper's `main.swift` and consumed inside an XPC reply closure — neither of
//  which any unit test can reach — so a read rate arriving in the write slot compiles, runs, and
//  puts the wrong number under the wrong heading in an exported report that outlives the session.
//
//  Two things are done about it. `RunCycleOutcome.init` takes **labelled** parameters, so the
//  untestable closure is a pass-through with each value's name beside it; and every test below
//  uses values that are **distinguishable from one another**. A suite that decoded `1.0` into
//  `readBytesPerSecond` and `1.0` into `writeBytesPerSecond` would pass with the two swapped,
//  which is the same vacuity as comparing a buffer with itself.
//
//  The third thing is not here, because it cannot be: `scripts/metrics-check.sh` compares these
//  six figures against a `runProgress` poll taken after the same run. Two independent routes to
//  one set of numbers is what makes a transposition in the helper's assembly visible on hardware.
//
//  ## And one distinction that carries real weight
//
//  `failedRanges` is an **optional array**. `[]` means the run found nothing; `nil` means this
//  build could not decode what the helper sent. Collapsing them would let a decode failure render
//  as a clean drive — the worst available way for this particular field to be wrong, on a tool
//  whose whole output is a judgement about somebody's hardware.
//

import Testing
import Foundation
@testable import USBDriveTester

struct RunCycleOutcomeTests {

    /// A complete, healthy reply. Every numeric value is deliberately different from every other,
    /// so any pair being swapped fails.
    private static func outcome(
        didComplete: Bool = true,
        chunksProcessed: UInt64 = 256,
        failedRangeCount: Int = 0,
        failureSummary: String = "no failed block ranges",
        cacheBypassCode: Int = 1,
        bufferBytesHeld: Int = 8 << 20,
        hostOverheadFraction: Double = 0.0255,
        helperCoreFraction: Double = 0.0422,
        failureModeUsedCode: Int = 2,
        failedRangesEncoded: String = "",
        failedBlockCount: UInt64 = 0,
        readBytesPerSecond: Double = 517_000_000,
        writeBytesPerSecond: Double = 491_000_000,
        readLatencySampleCount: UInt64 = 256,
        readLatencyMinimumNanoseconds: UInt64 = 1_100_000,
        readLatencyMaximumNanoseconds: UInt64 = 9_900_000,
        readLatencyP99UpperBoundNanoseconds: UInt64 = 2_195_000,
        message: String = "Cycle completed"
    ) -> RunCycleOutcome {
        RunCycleOutcome(didComplete: didComplete,
                        chunksProcessed: chunksProcessed,
                        failedRangeCount: failedRangeCount,
                        failureSummary: failureSummary,
                        cacheBypassCode: cacheBypassCode,
                        bufferBytesHeld: bufferBytesHeld,
                        hostOverheadFraction: hostOverheadFraction,
                        helperCoreFraction: helperCoreFraction,
                        failureModeUsedCode: failureModeUsedCode,
                        failedRangesEncoded: failedRangesEncoded,
                        failedBlockCount: failedBlockCount,
                        readBytesPerSecond: readBytesPerSecond,
                        writeBytesPerSecond: writeBytesPerSecond,
                        readLatencySampleCount: readLatencySampleCount,
                        readLatencyMinimumNanoseconds: readLatencyMinimumNanoseconds,
                        readLatencyMaximumNanoseconds: readLatencyMaximumNanoseconds,
                        readLatencyP99UpperBoundNanoseconds: readLatencyP99UpperBoundNanoseconds,
                        message: message)
    }

    // MARK: - Every field lands where it belongs

    /// Every value distinct, so a swapped pair cannot pass.
    @Test func aHealthyReplyDecodesFieldForField() {
        let result = Self.outcome()

        #expect(result.didComplete)
        #expect(result.chunksProcessed == 256)
        #expect(result.failedRangeCount == 0)
        #expect(result.failedRanges == [])
        #expect(result.failedBlockCount == 0)
        #expect(result.failureModeUsed == .logAndContinue)
        #expect(result.cacheBypass == .bypassed)
        #expect(result.bufferBytesHeld == 8 << 20)
        #expect(result.hostOverheadFraction == 0.0255)
        #expect(result.helperCoreFraction == 0.0422)
        #expect(result.readBytesPerSecond == 517_000_000)
        #expect(result.writeBytesPerSecond == 491_000_000)
        #expect(result.readLatencySampleCount == 256)
        #expect(result.readLatencyMinimum == .nanoseconds(1_100_000))
        #expect(result.readLatencyMaximum == .nanoseconds(9_900_000))
        #expect(result.readLatencyP99UpperBound == .nanoseconds(2_195_000))
        #expect(result.message == "Cycle completed")
    }

    /// The two rates are the pair most likely to be swapped and least likely to be noticed: both
    /// `Double`, adjacent, and plausible in either slot. Stated on its own so the failure message
    /// names the hazard.
    @Test func theTwoThroughputRatesAreNotInterchangeable() {
        let result = Self.outcome(readBytesPerSecond: 100, writeBytesPerSecond: 200)
        #expect(result.readBytesPerSecond == 100, "read rate took the write rate's value")
        #expect(result.writeBytesPerSecond == 200, "write rate took the read rate's value")
    }

    /// Likewise the three latency figures, which are adjacent `UInt64`s carrying the same unit.
    @Test func theThreeLatencyFiguresAreNotInterchangeable() {
        let result = Self.outcome(readLatencyMinimumNanoseconds: 1,
                                  readLatencyMaximumNanoseconds: 3,
                                  readLatencyP99UpperBoundNanoseconds: 2)
        #expect(result.readLatencyMinimum == .nanoseconds(1))
        #expect(result.readLatencyMaximum == .nanoseconds(3))
        #expect(result.readLatencyP99UpperBound == .nanoseconds(2))
    }

    /// And NFR-PERF-3's two fractions, for the same reason.
    @Test func theTwoPerformanceFractionsAreNotInterchangeable() {
        let result = Self.outcome(hostOverheadFraction: 0.1, helperCoreFraction: 0.2)
        #expect(result.hostOverheadFraction == 0.1)
        #expect(result.helperCoreFraction == 0.2)
    }

    // MARK: - The sentinels

    /// `-1` is "not measured" and **must not** become a rate. A negative throughput in a report
    /// would be absurd; a `0` would be worse, because `0` means *stalled*, which is a real and
    /// alarming condition.
    @Test func unmeasuredRatesBecomeNilRatherThanNegativeNumbers() {
        let result = Self.outcome(hostOverheadFraction: -1,
                                  helperCoreFraction: -1,
                                  readBytesPerSecond: -1,
                                  writeBytesPerSecond: -1)
        #expect(result.readBytesPerSecond == nil)
        #expect(result.writeBytesPerSecond == nil)
        #expect(result.hostOverheadFraction == nil)
        #expect(result.helperCoreFraction == nil)
    }

    /// A rate of zero is a **measurement** — the drive stalled — and must survive as one.
    @Test func aZeroRateIsAMeasurementAndNotASentinel() {
        let result = Self.outcome(readBytesPerSecond: 0, writeBytesPerSecond: 0)
        #expect(result.readBytesPerSecond == 0)
        #expect(result.writeBytesPerSecond == 0)
    }

    /// A sample count of `0` is what makes the latency figures meaningless — not their value,
    /// because `0` nanoseconds is a legitimate reading from a clock that could not resolve a read.
    @Test func latencyFiguresAreNilWithoutSamplesWhateverTheyContain() {
        let result = Self.outcome(readLatencySampleCount: 0,
                                  readLatencyMinimumNanoseconds: 1_100_000,
                                  readLatencyMaximumNanoseconds: 9_900_000,
                                  readLatencyP99UpperBoundNanoseconds: 2_195_000)
        #expect(result.readLatencyMinimum == nil)
        #expect(result.readLatencyMaximum == nil)
        #expect(result.readLatencyP99UpperBound == nil)
    }

    @Test func aZeroLatencyWithSamplesIsAMeasurement() {
        let result = Self.outcome(readLatencySampleCount: 4,
                                  readLatencyMinimumNanoseconds: 0)
        #expect(result.readLatencyMinimum == .nanoseconds(0))
    }

    /// A non-finite rate must not reach a formatter — "nan MB/s" and "inf MB/s" both read as data.
    @Test func nonFiniteRatesAreRefused() {
        let result = Self.outcome(readBytesPerSecond: .nan, writeBytesPerSecond: .infinity)
        #expect(result.readBytesPerSecond == nil)
        #expect(result.writeBytesPerSecond == nil)
    }

    /// Both replies carrying these figures — `runProgress` for the live run and
    /// `runRetentionCycle` for the finished one — must interpret the sentinels identically, or
    /// one drive would read one way live and another way in the exported report. `WireSentinel`
    /// is the single implementation; this is the test that says it is used by both.
    @Test func theCycleAndTheProgressReplyAgreeOnEverySentinel() {
        for value in [-1.0, 0.0, 517_000_000.0, Double.nan, .infinity, -0.5] {
            let live = RunProgressSnapshot(available: true, fractionComplete: 1, currentBlock: 0,
                                           readBytesPerSecond: value, writeBytesPerSecond: value,
                                           estimatedRemainingSeconds: -1,
                                           readLatencySampleCount: 1,
                                           readLatencyMinimumNanoseconds: 5,
                                           readLatencyMaximumNanoseconds: 5,
                                           readLatencyP99UpperBoundNanoseconds: 5,
                                           chunksFailed: 0)
            let finished = Self.outcome(readBytesPerSecond: value, writeBytesPerSecond: value)
            #expect(live.readBytesPerSecond == finished.readBytesPerSecond,
                    "the two replies disagree about \(value)")
            #expect(live.writeBytesPerSecond == finished.writeBytesPerSecond)
        }

        for samples in [UInt64(0), 1, 999] {
            let live = RunProgressSnapshot(available: true, fractionComplete: 1, currentBlock: 0,
                                           readBytesPerSecond: 1, writeBytesPerSecond: 1,
                                           estimatedRemainingSeconds: -1,
                                           readLatencySampleCount: samples,
                                           readLatencyMinimumNanoseconds: 7,
                                           readLatencyMaximumNanoseconds: 7,
                                           readLatencyP99UpperBoundNanoseconds: 7,
                                           chunksFailed: 0)
            let finished = Self.outcome(readLatencySampleCount: samples,
                                        readLatencyMinimumNanoseconds: 7,
                                        readLatencyMaximumNanoseconds: 7,
                                        readLatencyP99UpperBoundNanoseconds: 7)
            #expect(live.readLatencyMinimum == finished.readLatencyMinimum,
                    "the two replies disagree at \(samples) samples")
        }
    }

    // MARK: - The failed ranges (FR-RPT-1)

    @Test func failedRangesDecodeIntoTheReport() {
        let result = Self.outcome(failedRangeCount: 2,
                                  failedRangesEncoded: "200:2:3;5000:4:1",
                                  failedBlockCount: 6)
        #expect(result.failedRanges == [
            FailedBlockRange(startBlock: 200, blockCount: 2, kind: .verifyMismatch)!,
            FailedBlockRange(startBlock: 5_000, blockCount: 4, kind: .readError)!,
        ])
        #expect(result.failedBlockCount == 6)
        #expect(result.droppedRangeCount == 0)
        #expect(result.listIsTruncated == false)
    }

    /// **Empty is not the same as undecodable.** An empty list means the run found nothing; a
    /// `nil` means this build cannot say what the run found. If the second rendered as the first,
    /// a decode failure would report a clean drive.
    @Test func anUndecodableListIsNilAndNotEmpty() {
        let result = Self.outcome(failedRangeCount: 3, failedRangesEncoded: "garbage")
        #expect(result.failedRanges == nil)
        #expect(result.failedRanges?.isEmpty != true)
        #expect(result.droppedRangeCount == nil, "nothing can be said about what was dropped")
    }

    @Test func aCleanRunHasAnEmptyListAndNotNil() {
        #expect(Self.outcome().failedRanges == [])
    }

    /// The retention cap dropped ranges, and the report must be able to say so — a truncated list
    /// that does not announce itself reads exactly like a complete one.
    @Test func truncationIsDerivableAndSurfaced() {
        let result = Self.outcome(failedRangeCount: 1_030,
                                  failedRangesEncoded: "0:1:1;10:1:1;20:1:1",
                                  failedBlockCount: 4_096)
        #expect(result.failedRanges?.count == 3)
        #expect(result.droppedRangeCount == 1_027)
        #expect(result.listIsTruncated)
        #expect(result.failedBlockCount == 4_096,
                "the block count includes blocks in ranges the cap dropped")
    }

    /// A helper that reported fewer total ranges than it sent is nonsense, but the arithmetic must
    /// not go negative and print "-2 ranges were dropped".
    @Test func anInconsistentCountCannotProduceANegativeDropCount() {
        let result = Self.outcome(failedRangeCount: 1, failedRangesEncoded: "0:1:1;10:1:1")
        #expect(result.droppedRangeCount == 0)
        #expect(result.listIsTruncated == false)
    }

    // MARK: - The mode the run used

    /// The reason this field exists: `RunCoordinator` is not in the test target and a healthy
    /// drive produces no failure, so the echo is the only evidence the mode reached the run.
    @Test func theModeTheRunUsedIsReported() {
        #expect(Self.outcome(failureModeUsedCode: 1).failureModeUsed == .stopOnFirstError)
        #expect(Self.outcome(failureModeUsedCode: 2).failureModeUsed == .logAndContinue)
    }

    /// No run happened, so no mode was used. Distinct from either real mode, and it must not
    /// resolve to one.
    @Test func aRefusedRunReportsNoMode() {
        let refused = Self.outcome(didComplete: false, chunksProcessed: 0,
                                   failureModeUsedCode: 0)
        #expect(refused.failureModeUsed == .unrecognised)
        #expect(refused.failureModeUsed.isRunnable == false)
    }

    @Test func anUnknownModeCodeFromANewerHelperIsNotRunnable() {
        #expect(Self.outcome(failureModeUsedCode: 99).failureModeUsed == .unrecognised)
    }

    // MARK: - A refused run carries nothing

    /// **The shape that drove protocol v9.** The final figures are in this reply rather than
    /// polled from `runProgress` afterwards because `MetricsChannel`'s slot is replaced when a run
    /// *starts* — after validation — so at the moment a refusal returns, the slot still holds the
    /// **previous** run's numbers. A report assembled from a post-reply poll would export them.
    ///
    /// In the reply, a refused run has nothing to misattribute: no mode, no ranges, no rates, no
    /// latency samples.
    @Test func aRefusedRunHasNoFiguresToMisattribute() {
        let refused = Self.outcome(didComplete: false,
                                   chunksProcessed: 0,
                                   failedRangeCount: 0,
                                   failureSummary: "",
                                   cacheBypassCode: 0,
                                   bufferBytesHeld: 0,
                                   hostOverheadFraction: -1,
                                   helperCoreFraction: -1,
                                   failureModeUsedCode: 0,
                                   failedRangesEncoded: "",
                                   failedBlockCount: 0,
                                   readBytesPerSecond: -1,
                                   writeBytesPerSecond: -1,
                                   readLatencySampleCount: 0,
                                   readLatencyMinimumNanoseconds: 0,
                                   readLatencyMaximumNanoseconds: 0,
                                   readLatencyP99UpperBoundNanoseconds: 0,
                                   message: "Cannot run: no device is held.")

        #expect(refused.didComplete == false)
        #expect(refused.chunksProcessed == 0)
        #expect(refused.failureModeUsed == .unrecognised)
        #expect(refused.failedRanges == [])
        #expect(refused.failedBlockCount == 0)
        #expect(refused.readBytesPerSecond == nil)
        #expect(refused.writeBytesPerSecond == nil)
        #expect(refused.readLatencySampleCount == 0)
        #expect(refused.readLatencyMinimum == nil)
        #expect(refused.readLatencyMaximum == nil)
        #expect(refused.readLatencyP99UpperBound == nil)
        #expect(refused.cacheBypass == .unrecognised)
        #expect(refused.cacheBypass.qualifiesVerifyResult,
                "an unrecognised verdict is never read as success")
    }
}

// MARK: - The version handshake

struct ProtocolVersionNineTests {

    /// A signature change on both sides, so the bump is mandatory rather than merely cheap: a v8
    /// daemon would neither receive the failure mode nor encode the reply block this app decodes.
    /// The app and the helper are separately installed artefacts, so an old daemon can still be
    /// registered after an app update — and the handshake is what turns that into "too old"
    /// rather than a call that silently does something else.
    @Test func theProtocolVersionIsNine() {
        #expect(TesterProtocol.version == 9)
    }

    /// The bounded-call cap is unchanged by v9. It is not a tuning parameter — it is what makes
    /// an uncancellable privileged write safe to expose at all, and Step 11 is what replaces it.
    @Test func theCallCapIsUnchangedByTheBump() {
        #expect(TesterProtocol.maximumBytesPerCall == 1 << 30)
    }

    /// FR-CTRL-8's four sizes and FR-FAIL-4's default are likewise untouched.
    @Test func theRunParametersAreUnchangedByTheBump() {
        #expect(TesterProtocol.permittedIOSizes == [1 << 20, 2 << 20, 4 << 20, 8 << 20])
        #expect(TesterProtocol.defaultIOSizeBytes == 4 << 20)
        #expect(FailureModeCode.standard == .logAndContinue)
    }
}
