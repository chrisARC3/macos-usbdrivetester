//
//  MetricsFormattingTests.swift
//  Step 9's presentation layer: NFR-USE-1 and NFR-USE-2, and the sentinels that must never
//  reach a display.
//
//  ## The two things worth testing here
//
//  Formatting tests are usually low-value — they assert that a string is the string somebody
//  wrote. Two properties in this file are not that:
//
//  1. **An unknown must never render as a number.** The wire cannot carry an optional, so the
//     helper sends `-1` for a rate it has not measured. If that ever reaches a view it prints as
//     `-1.0 MB/s`, or — worse, if somebody "fixes" it by clamping — as `0 MB/s`, which means
//     *stalled*: a real and alarming condition used to report that nothing has happened yet.
//     This is the same defect found in the D1 probe's own output on 2026-08-04, and it is closed
//     here structurally rather than by remembering.
//
//  2. **Throughput must be decimal MB, not MiB.** The entire purpose of showing a rate is that
//     the user can compare it with the manufacturer's advertised sustained figure, which is
//     quoted in decimal megabytes (user decision 2026-08-04). Using 2²⁰ would make every reading
//     ~4.8% lower than the number on the box, for no reason the user could see — a systematic
//     bias in the direction of "this drive looks worse than it is", on a tool whose output is a
//     judgement about somebody's hardware.
//

import Testing
import Foundation
@testable import USBDriveTester

// MARK: - Nothing unknown ever becomes a number

struct UnknownRenderingTests {

    @Test func everyFormatterRendersAnUnknownAsAnEmDash() {
        #expect(MetricsFormatting.throughput(nil) == MetricsFormatting.unknown)
        #expect(MetricsFormatting.latency(nil) == MetricsFormatting.unknown)
        #expect(MetricsFormatting.percentileUpperBound(nil) == MetricsFormatting.unknown)
        #expect(MetricsFormatting.remaining(nil) == MetricsFormatting.unknown)
        #expect(MetricsFormatting.linkSpeed(code: -1) == MetricsFormatting.unknown)
        #expect(MetricsFormatting.runTimestamp(nil) == MetricsFormatting.unknown)
    }

    /// A run's timestamp must carry the **date**, not just a clock time.
    ///
    /// The panel keeps its figures after a run ends and nothing else on screen says what day it
    /// is, so a bare "16:14" is unreadable as soon as it is not today's — and these figures are a
    /// measurement of somebody's hardware, which invites being compared against a later one as
    /// though both were current.
    ///
    /// Asserted by *content* rather than against an exact string, because the output is
    /// locale-formatted and pinning it would be testing `Foundation`'s formatter rather than this
    /// decision. The year is the part that must survive.
    @Test func aRunTimestampCarriesItsDateAndNotOnlyTheTimeOfDay() {
        // 2026-08-05 14:38:48 UTC — the real start of the run whose figures the probe renders.
        let stamp = MetricsFormatting.runTimestamp(Date(timeIntervalSince1970: 1_785_940_728))

        #expect(stamp != MetricsFormatting.unknown)
        #expect(stamp.contains("2026"), "the year must be present, or a stale reading reads as current")
        #expect(stamp.contains("5"), "the day must be present")
    }

    /// An em-dash and not "0", "-" or "n/a": each of those reads as a value, a range, or an
    /// error, and none of them reads as "not measured".
    @Test func theUnknownMarkerIsNotMistakableForAValue() {
        #expect(MetricsFormatting.unknown == "—")
        #expect(!MetricsFormatting.unknown.contains("0"))
    }

    /// A rate that is somehow negative or non-finite is an unknown, not a number to print.
    @Test(arguments: [-1.0, -0.5, Double.nan, Double.infinity])
    func aNonsensicalRateIsNotRendered(value: Double) {
        #expect(MetricsFormatting.throughput(value) == MetricsFormatting.unknown)
    }

    @Test(arguments: [-1.0, Double.nan, Double.infinity])
    func aNonsensicalRemainingTimeIsNotRendered(value: Double) {
        #expect(MetricsFormatting.remaining(value) == MetricsFormatting.unknown)
    }
}

// MARK: - The wire's sentinels stop at the snapshot

struct RunProgressSnapshotDecodingTests {

    /// `-1` on the wire means "not measured". It must become `nil` here and nowhere else.
    @Test func negativeRatesDecodeToNil() {
        let snapshot = RunProgressSnapshot(available: true,
                                           fractionComplete: 0,
                                           currentBlock: 0,
                                           readBytesPerSecond: -1,
                                           writeBytesPerSecond: -1,
                                           estimatedRemainingSeconds: -1,
                                           readLatencySampleCount: 0,
                                           readLatencyMinimumNanoseconds: 0,
                                           readLatencyMaximumNanoseconds: 0,
                                           readLatencyP99UpperBoundNanoseconds: 0,
                                           chunksFailed: 0)

        #expect(snapshot.readBytesPerSecond == nil)
        #expect(snapshot.writeBytesPerSecond == nil)
        #expect(snapshot.estimatedRemaining == nil)
    }

    /// **Zero is a legitimate reading, so it cannot be its own sentinel.** A latency of 0 ns
    /// means a read the clock could not resolve. What says the figures are meaningless is the
    /// sample count.
    @Test func latencyFiguresAreNilWhenThereAreNoSamplesEvenThoughZeroIsAValidLatency() {
        let none = RunProgressSnapshot(available: true, fractionComplete: 0, currentBlock: 0,
                                       readBytesPerSecond: -1, writeBytesPerSecond: -1,
                                       estimatedRemainingSeconds: -1,
                                       readLatencySampleCount: 0,
                                       readLatencyMinimumNanoseconds: 0,
                                       readLatencyMaximumNanoseconds: 0,
                                       readLatencyP99UpperBoundNanoseconds: 0,
                                       chunksFailed: 0)
        #expect(none.readLatencyMinimum == nil)
        #expect(none.readLatencyMaximum == nil)
        #expect(none.readLatencyP99UpperBound == nil)
        #expect(!none.hasLatencySamples)

        // Same zeroes, but samples exist — now they are real measurements of zero.
        let measured = RunProgressSnapshot(available: true, fractionComplete: 0, currentBlock: 0,
                                           readBytesPerSecond: -1, writeBytesPerSecond: -1,
                                           estimatedRemainingSeconds: -1,
                                           readLatencySampleCount: 12,
                                           readLatencyMinimumNanoseconds: 0,
                                           readLatencyMaximumNanoseconds: 0,
                                           readLatencyP99UpperBoundNanoseconds: 0,
                                           chunksFailed: 0)
        #expect(measured.readLatencyMinimum == .nanoseconds(0))
        #expect(measured.hasLatencySamples)
    }

    @Test func realValuesSurviveDecodingIntact() {
        let snapshot = RunProgressSnapshot(available: true,
                                           fractionComplete: 0.25,
                                           currentBlock: 1_048_576,
                                           readBytesPerSecond: 492_870_060,
                                           writeBytesPerSecond: 431_000_000,
                                           estimatedRemainingSeconds: 12.5,
                                           readLatencySampleCount: 256,
                                           readLatencyMinimumNanoseconds: 8_100_000,
                                           readLatencyMaximumNanoseconds: 21_400_000,
                                           readLatencyP99UpperBoundNanoseconds: 19_922_944,
                                           chunksFailed: 3)

        #expect(snapshot.fractionComplete == 0.25)
        #expect(snapshot.currentBlock == 1_048_576)
        #expect(snapshot.readBytesPerSecond == 492_870_060)
        #expect(snapshot.estimatedRemaining == 12.5)
        #expect(snapshot.readLatencyMinimum == .nanoseconds(8_100_000))
        #expect(snapshot.chunksFailed == 3)
    }

    @Test func aFractionOutsideZeroToOneIsClamped() {
        let over = RunProgressSnapshot(available: true, fractionComplete: 1.5, currentBlock: 0,
                                       readBytesPerSecond: -1, writeBytesPerSecond: -1,
                                       estimatedRemainingSeconds: -1, readLatencySampleCount: 0,
                                       readLatencyMinimumNanoseconds: 0,
                                       readLatencyMaximumNanoseconds: 0,
                                       readLatencyP99UpperBoundNanoseconds: 0, chunksFailed: 0)
        #expect(over.fractionComplete == 1.0)
    }

    @Test func theUnavailableSnapshotSaysNothing() {
        let snapshot = RunProgressSnapshot.unavailable
        #expect(!snapshot.isAvailable)
        #expect(snapshot.readBytesPerSecond == nil)
        #expect(!snapshot.hasLatencySamples)
    }
}

// MARK: - Throughput (FR-METR-1/2, NFR-USE-1)

struct ThroughputFormattingTests {

    /// **Decimal, not binary.** 500,000,000 B/s is what a drive advertised at "500 MB/s"
    /// delivers, and it must read as 500 — not as 477, which is what dividing by 2²⁰ gives.
    @Test func megabytesAreDecimalSoTheyCompareWithTheNumberOnTheBox() {
        #expect(MetricsFormatting.throughput(500_000_000) == "500 MB/s")
        #expect(MetricsFormatting.throughput(540_000_000) == "540 MB/s")

        // The MiB reading of the same figure, which this must NOT produce.
        #expect(MetricsFormatting.throughput(500_000_000) != "477 MB/s")
    }

    /// `disk4`'s measured rate, from Step 8's hardware gate.
    @Test func aMeasuredRateReadsAsItsManufacturerFigureWould() {
        #expect(MetricsFormatting.throughput(492_870_060) == "493 MB/s")
    }

    @Test func gigabytesPerSecondAboveAThousandMegabytes() {
        #expect(MetricsFormatting.throughput(1_340_000_000) == "1.34 GB/s")
        #expect(MetricsFormatting.throughput(2_000_000_000) == "2.00 GB/s")
    }

    @Test func slowRatesStayReadable() {
        #expect(MetricsFormatting.throughput(512_000) == "512 kB/s")
        #expect(MetricsFormatting.throughput(0) == "0 kB/s")     // stalled: a real reading
    }
}

// MARK: - Latency (FR-METR-3/4, NFR-USE-1)

struct LatencyFormattingTests {

    /// A 4 MiB read at ~500 MB/s is about 8.4 ms, and the differences worth seeing are smaller
    /// than that — hence three decimals at millisecond scale.
    @Test func millisecondScaleKeepsThreeDecimals() {
        #expect(MetricsFormatting.latency(.nanoseconds(8_400_000)) == "8.400 ms")
        #expect(MetricsFormatting.latency(.nanoseconds(8_412_345)) == "8.412 ms")
    }

    @Test func smallerAndLargerScalesSwitchUnits() {
        #expect(MetricsFormatting.latency(.nanoseconds(750)) == "750 ns")
        #expect(MetricsFormatting.latency(.nanoseconds(58_000)) == "58.0 µs")
        #expect(MetricsFormatting.latency(.nanoseconds(30_000_000_000)) == "30.00 s")
    }

    /// A latency the clock could not resolve is a real reading of zero, not an unknown.
    @Test func zeroIsRenderedAsAMeasurement() {
        #expect(MetricsFormatting.latency(.nanoseconds(0)) == "0 ns")
        #expect(MetricsFormatting.latency(.nanoseconds(0)) != MetricsFormatting.unknown)
    }

    /// p99 is an upper bound, and says so. The histogram knows it to within one bucket — at most
    /// 1.5625% — so a bare number would be a midpoint pretending to be a measurement.
    @Test func thePercentileIsLabelledAsAnUpperBound() {
        let formatted = MetricsFormatting.percentileUpperBound(.nanoseconds(19_922_944))
        #expect(formatted.hasPrefix("≤ "))
        #expect(formatted == "≤ 19.923 ms")
    }
}

// MARK: - Progress (FR-METR-5/6, NFR-USE-2)

struct ProgressFormattingTests {

    @Test func percentHasNoDecimalsSoItDoesNotJitterOncePerSecond() {
        #expect(MetricsFormatting.percent(0) == "0%")
        #expect(MetricsFormatting.percent(0.4567) == "46%")
        #expect(MetricsFormatting.percent(1) == "100%")
        #expect(MetricsFormatting.percent(1.5) == "100%")
        #expect(MetricsFormatting.percent(-0.5) == "0%")
    }

    /// A block offset on a 1 TB drive is ten digits. Grouped, or it cannot be read or compared.
    @Test func blockOffsetsAreGrouped() {
        #expect(MetricsFormatting.blockOffset(1_953_525_168) == "1,953,525,168")
        #expect(MetricsFormatting.blockOffset(0) == "0")
    }

    /// Coarser as it grows, because a measured-throughput extrapolation does not know the
    /// seconds of a three-hour estimate and should not imply that it does (NFR-PERF-6).
    @Test func remainingTimeGetsCoarserAsItGrows() {
        #expect(MetricsFormatting.remaining(0.4) == "less than a second")
        #expect(MetricsFormatting.remaining(45) == "45 s")
        #expect(MetricsFormatting.remaining(90) == "1 min 30 s")
        #expect(MetricsFormatting.remaining(3_600) == "1 h 0 min")
        #expect(MetricsFormatting.remaining(10_620) == "2 h 57 min")
        #expect(MetricsFormatting.remaining(180_000) == "2 d 2 h")
    }
}

// MARK: - Link speed, the other half of the user's judgement

struct LinkSpeedFormattingTests {

    /// `disk4`'s negotiated link, from Step 7's gate: code 4.
    @Test func knownCodesRenderWithBothTheRateAndTheGeneration() {
        #expect(MetricsFormatting.linkSpeed(code: 4) == "10 Gb/s (USB 3.1 Gen 2)")
        #expect(MetricsFormatting.linkSpeed(code: 3) == "5 Gb/s (USB 3.0)")
        #expect(MetricsFormatting.linkSpeed(code: 2) == "480 Mb/s (USB 2.0 high speed)")
    }

    /// The registry enumeration is **not** the one any SDK header declares, so a code this build
    /// does not know is reported as unrecognised **with its number** — never guessed at, and
    /// never silently mapped to a neighbour. `scripts/usb-speed-check.sh` is what detects a
    /// shift in the mapping.
    @Test func anUnrecognisedCodeSaysSoAndCarriesTheNumber() {
        let formatted = MetricsFormatting.linkSpeed(code: 99)
        #expect(formatted.contains("unrecognised"))
        #expect(formatted.contains("99"))
    }
}

// MARK: - What the live panel shows, and when (user decision 2026-08-06)

/// Step 10 gave the finished run its own window, with the full bad-block list and an export. The
/// metrics panel under the device list stopped retaining that result — it is the **live** panel
/// now, and nothing else.
///
/// The whole table is four rows and every one of them is a state a user reaches, so none is
/// sampled. The row the change turned over is `available + not running`: `runProgress` keeps
/// returning a finished run's figures until the next run replaces them, so before this the panel
/// displayed a completed run indefinitely.
struct RunMetricsPanelVisibilityTests {

    private func snapshot(available: Bool) -> RunProgressSnapshot {
        available
            ? RunProgressSnapshot(available: true, fractionComplete: 1, currentBlock: 2_097_152,
                                  readBytesPerSecond: 517_000_000,
                                  writeBytesPerSecond: 491_000_000,
                                  estimatedRemainingSeconds: 0,
                                  readLatencySampleCount: 256,
                                  readLatencyMinimumNanoseconds: 1_100_000,
                                  readLatencyMaximumNanoseconds: 9_900_000,
                                  readLatencyP99UpperBoundNanoseconds: 2_195_000,
                                  chunksFailed: 0)
            : .unavailable
    }

    /// FR-METR-2/4/5/6 are mandatory and require these figures **during** a run. This is the row
    /// that must never be lost while trimming the panel back.
    @Test func aRunInProgressShowsItsMeasurements() {
        #expect(RunMetricsView.showsMeasurements(snapshot: snapshot(available: true),
                                                 isRunning: true))
    }

    /// **The row Step 10 changed.** A finished run's figures are still in the helper's slot, and
    /// the panel must not go on presenting them: that result now lives in the Run Report window,
    /// where it is complete and exportable.
    @Test func aFinishedRunIsNoLongerRetainedByThePanel() {
        #expect(RunMetricsView.showsMeasurements(snapshot: snapshot(available: true),
                                                 isRunning: false) == false)
    }

    /// The first moment of a run, before anything has been measured. Step 9 fixed a placeholder
    /// that left a row of em-dashes visible behind it; this keeps that fixed.
    @Test func aRunWithNothingMeasuredYetShowsThePlaceholder() {
        #expect(RunMetricsView.showsMeasurements(snapshot: snapshot(available: false),
                                                 isRunning: true) == false)
    }

    @Test func nothingRunningAndNothingMeasuredShowsThePlaceholder() {
        #expect(RunMetricsView.showsMeasurements(snapshot: snapshot(available: false),
                                                 isRunning: false) == false)
    }

    /// Both inputs are load-bearing: exactly one of the four combinations shows figures.
    @Test func exactlyOneCombinationShowsFigures() {
        let showing = [(true, true), (true, false), (false, true), (false, false)]
            .filter { RunMetricsView.showsMeasurements(snapshot: snapshot(available: $0.0),
                                                       isRunning: $0.1) }
        #expect(showing.count == 1)
        #expect(showing.first?.0 == true && showing.first?.1 == true)
    }
}
