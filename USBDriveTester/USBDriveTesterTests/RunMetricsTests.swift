//
//  RunMetricsTests.swift
//  Step 9's accumulator, driven by a clock the test owns.
//
//  ## Why there is no hardware anywhere near this file
//
//  `RunMetrics` calls no clock. Every entry point is handed the current monotonic reading, so a
//  run of any shape and any duration can be synthesised exactly — including the one thing the
//  BUILD-PLAN gate asks for and the 1 GiB cap makes unobservable on real media: **an ETA
//  converging over a long run whose true remaining time is known at every step**
//  (``ETATests/theETAConvergesTowardTheTrueRemainingTimeAsARunProceeds``).
//
//  ## The three assertions that would catch a real regression
//
//  Most of what follows is arithmetic. Three tests are not:
//
//  | Test | The defect it exists to catch |
//  |---|---|
//  | ``ThroughputTests/coverageIsAboutOneThirdOfTheReadRateAndTheyAreNotInterchangeable`` | Using read throughput as the ETA denominator. A cycle moves 3× its range, so that mistake makes every estimate ~3× too optimistic — and it looks right. |
//  | ``ProgressTests/progressAdvancesThroughAChunkThatFailed`` | Progress that counts only successes. It freezes on exactly the drive this tool exists to find, at the moment somebody is watching hardest. |
//  | ``LatencyAttributionTests/aFailedReadsDurationIsNotReadLatency`` | Folding a failed read's duration into the latency distribution, conflating "this drive is slow" with "this drive is broken". |
//
//  ## Fixed durations, not random ones
//
//  Every duration here is chosen so the expected answer can be computed by hand and written
//  into the assertion. A test that recomputes the answer the same way the code does is a test
//  that cannot fail.
//

import Testing
import Foundation

// MARK: - Fixtures

private enum Metrics {

    static let mebibyte = 1 << 20                      // 1 MiB
    static let chunkBytes = 4 << 20                    // 4 MiB, FR-CTRL-8's default
    static let millisecond: UInt64 = 1_000_000         // in nanoseconds
    static let blockSize: UInt64 = 512

    /// `4 MiB ÷ 10 ms`, the read rate used throughout — close to `disk4`'s measured ~475 MB/s.
    static let tenMilliseconds: UInt64 = 10 * millisecond

    /// Wall clock one ``healthyChunk`` really occupies: three 10 ms phases **plus its 50 us of
    /// host overhead**.
    ///
    /// The clock must advance by this, not by the phases alone. A fixture whose wall clock ran
    /// faster than its own accounted work is not a physically possible run, and this one did —
    /// which hid a 0.17% gap between elapsed and active time behind a 1e-6 tolerance.
    static let healthyChunkWall: UInt64 = 3 * tenMilliseconds + 50_000

    /// Blocks a 4 MiB chunk covers at 512-byte geometry.
    static var blocksPerChunk: UInt64 { UInt64(chunkBytes) / blockSize }

    /// A whole, healthy chunk: read, write and verify each taking `phase` nanoseconds.
    static func healthyChunk(index: UInt64,
                             phase: UInt64 = tenMilliseconds,
                             overhead: UInt64 = 50_000,
                             byteLength: Int = chunkBytes) -> ChunkMeasurement {
        ChunkMeasurement(byteLength: byteLength,
                         endBlock: (index + 1) * (UInt64(byteLength) / blockSize),
                         outcome: .completed,
                         readNanoseconds: phase,
                         writeNanoseconds: phase,
                         verifyNanoseconds: phase,
                         hostOverheadNanoseconds: overhead)
    }

    /// A fresh accumulator over `chunks` chunks of `chunkBytes`, started at clock zero.
    static func metrics(chunks: UInt64, byteLength: Int = chunkBytes) -> RunMetrics {
        RunMetrics(chunksPlanned: chunks,
                   deviceBytesTotal: chunks * UInt64(byteLength),
                   startBlock: 0,
                   startedAtNanoseconds: 0)
    }
}

/// Compare rates with a relative tolerance. Exact `==` on a value derived through a division by
/// `1e9` would be asserting the behaviour of binary floating point, not of this code.
private func expectClose(_ actual: Double?,
                         _ expected: Double,
                         relativeTolerance: Double = 0.000_001,
                         _ what: Comment,
                         sourceLocation: SourceLocation = #_sourceLocation) {
    guard let actual else {
        Issue.record("\(what): expected \(expected), got nil", sourceLocation: sourceLocation)
        return
    }
    let allowed = abs(expected) * relativeTolerance
    #expect(abs(actual - expected) <= allowed,
            "\(what): expected \(expected), got \(actual)",
            sourceLocation: sourceLocation)
}

// MARK: - Throughput (FR-METR-1)

struct ThroughputTests {

    @Test func eachRateDividesItsOwnBytesByItsOwnTime() {
        var metrics = Metrics.metrics(chunks: 10)
        var now: UInt64 = 0
        for index in UInt64(0) ..< 10 {
            metrics.record(Metrics.healthyChunk(index: index))
            now &+= Metrics.healthyChunkWall
        }
        let snapshot = metrics.snapshot(atNanoseconds: now)

        // 10 chunks x 4 MiB = 41,943,040 bytes, each phase 10 ms x 10 chunks = 0.1 s.
        let expectedPhaseRate = 41_943_040.0 / 0.1

        expectClose(snapshot.readBytesPerSecond, expectedPhaseRate, "read rate")
        expectClose(snapshot.writeBytesPerSecond, expectedPhaseRate, "write rate")
        expectClose(snapshot.verifyBytesPerSecond, expectedPhaseRate, "verify rate")
        #expect(snapshot.bytesRead == 41_943_040)
        #expect(snapshot.bytesWritten == 41_943_040)
        #expect(snapshot.bytesVerified == 41_943_040)
    }

    /// **The anti-collapse test.** A cycle moves three times the range it covers, so the rate
    /// that drives an ETA is not the rate labelled "read speed". Swapping them produces an
    /// estimate that is about three times too optimistic and looks entirely plausible.
    @Test func coverageIsAboutOneThirdOfTheReadRateAndTheyAreNotInterchangeable() throws {
        var metrics = Metrics.metrics(chunks: 10)
        var now: UInt64 = 0
        for index in UInt64(0) ..< 10 {
            metrics.record(Metrics.healthyChunk(index: index))
            now &+= Metrics.healthyChunkWall            // three phases AND the overhead
        }
        let snapshot = metrics.snapshot(atNanoseconds: now)

        let readRate = try #require(snapshot.readBytesPerSecond)
        let coverageRate = try #require(snapshot.coverageBytesPerSecond)

        // 41,943,040 bytes of range in 0.3005 s of working time — three 10 ms phases and
        // 50 us of host overhead, ten times over.
        expectClose(coverageRate, 41_943_040.0 / 0.3005, "coverage rate")
        // "About" a third, and the 0.17% it is out by is the host overhead: coverage divides by
        // 3p + h where the phase rate divides by p. A 1e-6 tolerance here would be asserting
        // that the run does no host work at all.
        expectClose(coverageRate, readRate / 3.0, relativeTolerance: 0.01,
                    "coverage should be about a third of the read rate for a symmetric cycle")
        #expect(coverageRate < readRate)
    }

    /// Every gap counts, not just the most recent one.
    ///
    /// **Found by mutation M3 on 2026-08-18, which survived.** `RunSessionStabilityTests` pauses
    /// a two-call run, and two calls have exactly one gap — so `idleNanoseconds = nanoseconds`
    /// and `idleNanoseconds &+= nanoseconds` are indistinguishable there. A whole-device run is
    /// about a thousand calls, and a user who pauses twice would have the first pause charged to
    /// the drive's throughput.
    ///
    /// Asserted on the accumulator rather than through the engine because that is where the
    /// arithmetic is; that the observer calls this once per gap is M5's job, and M5 is caught.
    @Test func idleAccumulatesAcrossEveryGapAndNotJustTheLast() {
        var metrics = Metrics.metrics(chunks: 10)
        metrics.record(Metrics.healthyChunk(index: 0))

        metrics.noteIdle(nanoseconds: 100_000_000)      // first pause
        metrics.noteIdle(nanoseconds: 250_000_000)      // second pause

        let snapshot = metrics.snapshot(atNanoseconds: 10 * Metrics.healthyChunkWall)
        #expect(snapshot.idleNanoseconds == 350_000_000,
                "a session has as many gaps as it has calls; only the last was counted")
    }

    /// Idle time is subtracted from the denominator, so a gap in which no call was running
    /// cannot depress a rate.
    ///
    /// The accumulator's half of the story. Noticing the gap is ``RunSessionObserver``'s job —
    /// this type has no clock and cannot see one — and `RunSessionStabilityTests` covers that.
    @Test func idleTimeIsSubtractedFromTheRateDenominator() throws {
        var metrics = Metrics.metrics(chunks: 10)
        var now: UInt64 = 0
        for index in UInt64(0) ..< 10 {
            metrics.record(Metrics.healthyChunk(index: index))
            now &+= Metrics.healthyChunkWall
        }
        let busy = metrics.snapshot(atNanoseconds: now)

        // Half an hour in which nothing ran, declared as such.
        let pause: UInt64 = 30 * 60 * 1_000_000_000
        metrics.noteIdle(nanoseconds: pause)
        let afterAPause = metrics.snapshot(atNanoseconds: now &+ pause)

        #expect(afterAPause.runningNanoseconds == busy.runningNanoseconds,
                "the pause was not subtracted from the denominator")
        // `expectClose` takes the optional itself — it records an Issue on nil, with the label.
        expectClose(afterAPause.sustainedReadBytesPerSecond,
                    try #require(busy.sustainedReadBytesPerSecond),
                    "a declared idle span must not change the measured read rate")

        // And the wall clock still tells the truth about how long the run took.
        #expect(afterAPause.elapsedNanoseconds == busy.elapsedNanoseconds &+ pause)
        #expect(afterAPause.idleNanoseconds == pause)
    }

    @Test func ratesAreUnknownRatherThanZeroBeforeAnythingHasHappened() {
        let snapshot = Metrics.metrics(chunks: 10).snapshot(atNanoseconds: 0)

        #expect(snapshot.readBytesPerSecond == nil)
        #expect(snapshot.writeBytesPerSecond == nil)
        #expect(snapshot.coverageBytesPerSecond == nil)
        #expect(snapshot.sustainedReadBytesPerSecond == nil)
        #expect(snapshot.sustainedWriteBytesPerSecond == nil)
        #expect(snapshot.hostOverheadFraction == nil)
        #expect(snapshot.estimatedRemainingNanoseconds == nil)
    }

    /// **What the app displays**: bytes moved ÷ the time the run spent working.
    ///
    /// Read counts the verify read as well as the original, because both are reads and the
    /// kernel counts both. A figure that omitted the verify would be exactly half of what the
    /// user sees in Activity Monitor.
    @Test func theSustainedRatesDivideByWorkingTimeAndCountBothReads() throws {
        var metrics = Metrics.metrics(chunks: 10)
        var now: UInt64 = 0
        for index in UInt64(0) ..< 10 {
            metrics.record(Metrics.healthyChunk(index: index))
            now &+= Metrics.healthyChunkWall            // three phases AND the overhead
        }
        let snapshot = metrics.snapshot(atNanoseconds: now)

        // 41,943,040 bytes of range in 0.3005 s of working time. Every byte was read twice and
        // written once. The two relationships below are EXACT rather than approximate, because
        // all three rates divide by the same denominator — which is the point.
        let covering = try #require(snapshot.coverageBytesPerSecond)
        let read = try #require(snapshot.sustainedReadBytesPerSecond)
        let write = try #require(snapshot.sustainedWriteBytesPerSecond)

        expectClose(read, 2 * 41_943_040.0 / 0.3005, "sustained read")
        expectClose(write, 41_943_040.0 / 0.3005, "sustained write")
        expectClose(read, covering * 2,
                    "read should be twice covering — the original read and the verify")
        expectClose(write, covering,
                    "write should equal covering — one write per covered byte")
    }

    /// **The 2026-08-17 report, reproduced from first principles.**
    ///
    /// The user measured the 4 TB T5 EVO with DriveSpeed and with Activity Monitor — which agreed
    /// with each other exactly — and found the app reading about 50% high on read and over 3×
    /// high on write. Nothing was miscounted: the displayed rates divided by *phase* time, so
    /// each described the drive only during the fraction of the run that phase was running.
    ///
    /// For a perfectly symmetric cycle the arithmetic gives exactly 1.5× and 3×. The real run's
    /// slightly uneven phase times perturbed those into the 1.53 and 3.42 that were reported.
    ///
    /// Pinned here so that putting a phase rate back on a display fails a test rather than a
    /// user. Both kinds of rate are kept — "slow while working" and "spends a long time not
    /// working" are different faults — but only one kind is comparable to anything.
    @Test func aPhaseRateOverstatesWhatAnOutsideObserverCanSee() throws {
        var metrics = Metrics.metrics(chunks: 10)
        var now: UInt64 = 0
        for index in UInt64(0) ..< 10 {
            metrics.record(Metrics.healthyChunk(index: index))
            now &+= Metrics.healthyChunkWall
        }
        let snapshot = metrics.snapshot(atNanoseconds: now)

        let phaseRead = try #require(snapshot.readBytesPerSecond)
        let phaseWrite = try #require(snapshot.writeBytesPerSecond)
        let sustainedRead = try #require(snapshot.sustainedReadBytesPerSecond)
        let sustainedWrite = try #require(snapshot.sustainedWriteBytesPerSecond)

        // 1% rather than 1e-6: the exact ratios are 1.5 + h/2p and 3 + h/p, and the 0.17% they
        // are out by is this fixture's host overhead. The claim is the factor, not the decimals.
        expectClose(phaseRead / sustainedRead, 1.5, relativeTolerance: 0.01,
                    "the read rate v11 displayed was 1.5x what an outside observer measured")
        expectClose(phaseWrite / sustainedWrite, 3.0, relativeTolerance: 0.01,
                    "the write rate v11 displayed was 3x what an outside observer measured")
    }
}

// MARK: - Latency attribution (FR-METR-3)

struct LatencyAttributionTests {

    @Test func theTwoHistogramsSeeTheirOwnPhaseAndNotTheOther() throws {
        var metrics = Metrics.metrics(chunks: 4)
        for index in UInt64(0) ..< 4 {
            metrics.record(ChunkMeasurement(byteLength: Metrics.chunkBytes,
                                            endBlock: (index + 1) * Metrics.blocksPerChunk,
                                            outcome: .completed,
                                            readNanoseconds: 8 * Metrics.millisecond,
                                            writeNanoseconds: 12 * Metrics.millisecond,
                                            verifyNanoseconds: 3 * Metrics.millisecond,
                                            hostOverheadNanoseconds: 40_000))
        }
        let snapshot = metrics.snapshot(atNanoseconds: 100 * Metrics.millisecond)

        #expect(snapshot.readLatency.count == 4)
        #expect(snapshot.readLatency.minimumNanoseconds == 8 * Metrics.millisecond)
        #expect(snapshot.readLatency.maximumNanoseconds == 8 * Metrics.millisecond)

        #expect(snapshot.verifyLatency.count == 4)
        #expect(snapshot.verifyLatency.minimumNanoseconds == 3 * Metrics.millisecond)

        // The write is timed and counted, but it is not a *read* latency and must not appear
        // in either distribution.
        let writeDuration = 12 * Metrics.millisecond
        #expect(snapshot.readLatency.maximumNanoseconds != writeDuration)
        #expect(snapshot.verifyLatency.maximumNanoseconds != writeDuration)
    }

    /// **The conflation test.** A read that failed returned no data; its duration is a failure
    /// duration, possibly a long controller retry. Folding it into "read latency" would make
    /// p99 report a broken drive as a slow one.
    @Test func aFailedReadsDurationIsNotReadLatency() {
        var metrics = Metrics.metrics(chunks: 2)

        metrics.record(Metrics.healthyChunk(index: 0, phase: 8 * Metrics.millisecond))
        metrics.record(ChunkMeasurement(byteLength: Metrics.chunkBytes,
                                        endBlock: 2 * Metrics.blocksPerChunk,
                                        outcome: .failedReading,
                                        readNanoseconds: 30_000 * Metrics.millisecond,  // 30 s
                                        writeNanoseconds: nil,
                                        verifyNanoseconds: nil,
                                        hostOverheadNanoseconds: 10_000))

        let snapshot = metrics.snapshot(atNanoseconds: 31_000 * Metrics.millisecond)

        // One read latency recorded, not two — and the 30 s failure is not the maximum.
        #expect(snapshot.readLatency.count == 1)
        #expect(snapshot.readLatency.maximumNanoseconds == 8 * Metrics.millisecond)

        // …and it is not lost either.
        #expect(snapshot.failedPhaseNanoseconds == 30_000 * Metrics.millisecond)
        #expect(snapshot.chunksFailed == 1)

        // The failed chunk transferred nothing, so the read rate reflects one chunk.
        #expect(snapshot.bytesRead == UInt64(Metrics.chunkBytes))
    }

    @Test func p99ReflectsAnInjectedSlowTail() throws {
        var metrics = Metrics.metrics(chunks: 1_000)
        for index in UInt64(0) ..< 1_000 {
            // 985 fast, then 15 an order of magnitude slower — p99 must land in the tail.
            let phase = index < 985 ? 1 * Metrics.millisecond : 100 * Metrics.millisecond
            metrics.record(Metrics.healthyChunk(index: index, phase: phase))
        }
        let snapshot = metrics.snapshot(atNanoseconds: 10_000 * Metrics.millisecond)
        let p99 = try #require(snapshot.readLatency.p99)

        #expect(p99.lowerBoundNanoseconds > 1 * Metrics.millisecond,
                "p99 still contains the fast population, so it distinguishes nothing")
        #expect(p99.upperBoundNanoseconds <= 100 * Metrics.millisecond)
        #expect(snapshot.readLatency.minimumNanoseconds == 1 * Metrics.millisecond)
        #expect(snapshot.readLatency.maximumNanoseconds == 100 * Metrics.millisecond)
    }
}

// MARK: - Progress and position (FR-METR-5/6)

struct ProgressTests {

    @Test func fractionCompleteAndPositionTrackTheChunksAttempted() {
        var metrics = Metrics.metrics(chunks: 10)
        for index in UInt64(0) ..< 4 {
            metrics.record(Metrics.healthyChunk(index: index))
        }
        let snapshot = metrics.snapshot(atNanoseconds: 120 * Metrics.millisecond)

        #expect(snapshot.chunksAttempted == 4)
        #expect(snapshot.fractionComplete == 0.4)
        #expect(snapshot.currentBlock == 4 * Metrics.blocksPerChunk)
        #expect(snapshot.rangeBytesCovered == 4 * UInt64(Metrics.chunkBytes))
        #expect(!snapshot.isComplete)
    }

    /// **The A7 hazard, as an assertion.** A chunk that hard-errored still consumed time and
    /// still moved the position. Progress that counted only successes would sit still while the
    /// engine walked on — percent frozen, ETA running away — on precisely the failing drive
    /// this tool exists to find.
    @Test func progressAdvancesThroughAChunkThatFailed() {
        var metrics = Metrics.metrics(chunks: 4)

        metrics.record(Metrics.healthyChunk(index: 0))
        metrics.record(ChunkMeasurement(byteLength: Metrics.chunkBytes,
                                        endBlock: 2 * Metrics.blocksPerChunk,
                                        outcome: .failedReading,
                                        readNanoseconds: 5 * Metrics.millisecond,
                                        writeNanoseconds: nil,
                                        verifyNanoseconds: nil,
                                        hostOverheadNanoseconds: 1_000))
        metrics.record(Metrics.healthyChunk(index: 2))

        let snapshot = metrics.snapshot(atNanoseconds: 200 * Metrics.millisecond)

        #expect(snapshot.chunksAttempted == 3)
        #expect(snapshot.fractionComplete == 0.75)
        #expect(snapshot.currentBlock == 3 * Metrics.blocksPerChunk)
        #expect(snapshot.chunksFailed == 1)

        // Two chunks' worth of data actually moved, three chunks' worth of ground covered.
        #expect(snapshot.bytesRead == 2 * UInt64(Metrics.chunkBytes))
        #expect(snapshot.rangeBytesCovered == 3 * UInt64(Metrics.chunkBytes))
    }

    @Test func aShortFinalChunkStillCompletesTheRange() {
        // FR-TEST-5: three full 4 MiB chunks and a final one of a single block.
        let total = 3 * UInt64(Metrics.chunkBytes) + Metrics.blockSize
        var metrics = RunMetrics(chunksPlanned: 4,
                                 deviceBytesTotal: total,
                                 startBlock: 0,
                                 startedAtNanoseconds: 0)

        for index in UInt64(0) ..< 3 { metrics.record(Metrics.healthyChunk(index: index)) }
        metrics.record(ChunkMeasurement(byteLength: Int(Metrics.blockSize),
                                        endBlock: 3 * Metrics.blocksPerChunk + 1,
                                        outcome: .completed,
                                        readNanoseconds: 100_000,
                                        writeNanoseconds: 100_000,
                                        verifyNanoseconds: 100_000,
                                        hostOverheadNanoseconds: 500))

        let snapshot = metrics.snapshot(atNanoseconds: 200 * Metrics.millisecond)

        #expect(snapshot.rangeBytesCovered == total)
        #expect(snapshot.fractionComplete == 1.0)
        #expect(snapshot.isComplete)
        #expect(snapshot.estimatedRemainingNanoseconds == 0)
    }
}

// MARK: - ETA (FR-METR-5, NFR-PERF-6)

struct ETATests {

    /// **What the 1 GiB cap makes unobservable on hardware.** A run whose rate changes partway,
    /// with the true remaining time known exactly at every step, so convergence is a measured
    /// property rather than an impression formed while watching a progress bar.
    ///
    /// 100 chunks of 1 MiB. The first 20 take 20 ms each, the remaining 80 take 5 ms each — so
    /// the true total is 800 ms, and an ETA built on a cumulative average necessarily starts
    /// pessimistic and has to work its way down.
    ///
    /// Measured error at the sample points: **1200 → 450 → 200 → 75 → 3.03 ms.**
    ///
    /// - Important: the first sample point is chunk **20**, the last slow chunk, and it must
    ///   stay there. Through the constant-rate opening the error is *flat* at 1200 ms — which
    ///   is correct, not a defect: while the rate is steady the cumulative average equals the
    ///   current rate, so the estimate is exactly right for a run that continues as it has
    ///   been, and the whole error is the future rate change that no measured-throughput ETA
    ///   can predict (NFR-COMPAT-7 forbids assuming one). Adding a sample point inside that
    ///   opening would compare 1200 against 1200 and fail the strictly-decreasing check for a
    ///   reason that has nothing to do with convergence.
    @Test func theETAConvergesTowardTheTrueRemainingTimeAsARunProceeds() throws {
        let chunkCount: UInt64 = 100
        let slowChunks: UInt64 = 20
        let slowDuration = 20 * Metrics.millisecond
        let fastDuration = 5 * Metrics.millisecond
        let trueTotalNanoseconds = slowChunks * slowDuration
                                 + (chunkCount - slowChunks) * fastDuration

        var metrics = Metrics.metrics(chunks: chunkCount, byteLength: Metrics.mebibyte)
        var now: UInt64 = 0
        var errorsAtSamplePoints: [UInt64: Double] = [:]
        let samplePoints: Set<UInt64> = [20, 40, 60, 80, 99]

        for index in UInt64(0) ..< chunkCount {
            let duration = index < slowChunks ? slowDuration : fastDuration
            let phase = duration / 3
            metrics.record(Metrics.healthyChunk(index: index,
                                                phase: phase,
                                                overhead: 0,
                                                byteLength: Metrics.mebibyte))
            now &+= duration

            let attempted = index + 1
            guard samplePoints.contains(attempted) else { continue }

            let snapshot = metrics.snapshot(atNanoseconds: now)
            let estimate = try #require(snapshot.estimatedRemainingNanoseconds)
            let trueRemaining = trueTotalNanoseconds - now
            errorsAtSamplePoints[attempted] =
                abs(Double(estimate) - Double(trueRemaining))
        }

        // Strictly decreasing error: the estimate is not merely finite, it is getting better.
        let ordered = samplePoints.sorted()
        for (position, point) in ordered.enumerated() where position > 0 {
            let previous = try #require(errorsAtSamplePoints[ordered[position - 1]])
            let current = try #require(errorsAtSamplePoints[point])
            #expect(current < previous,
                    "error at chunk \(point) (\(current) ns) did not improve on chunk \(ordered[position - 1]) (\(previous) ns)")
        }

        // And it lands close: under 1% of the run's true duration by the last chunk.
        let finalError = try #require(errorsAtSamplePoints[99])
        #expect(finalError < Double(trueTotalNanoseconds) * 0.01,
                "final error \(finalError) ns is not within 1% of \(trueTotalNanoseconds) ns")
    }

    /// At a steady rate the estimate is not merely converging — it is exact at every step.
    @Test func aConstantRateGivesAnExactETAFromTheFirstChunk() throws {
        let chunkCount: UInt64 = 50
        // Divisible by three, so the three phases sum to the chunk's wall time EXACTLY. At
        // 10 ms it did not: 10/3 truncates to 3,333,333 ns and three of those is a nanosecond
        // short, which the ETA now divides by and which this test asserts to the nanosecond.
        let phase = 4 * Metrics.millisecond
        let perChunk = 3 * phase

        var metrics = Metrics.metrics(chunks: chunkCount, byteLength: Metrics.mebibyte)
        var now: UInt64 = 0

        for index in UInt64(0) ..< chunkCount {
            metrics.record(Metrics.healthyChunk(index: index,
                                                phase: phase,
                                                overhead: 0,
                                                byteLength: Metrics.mebibyte))
            now &+= perChunk

            let snapshot = metrics.snapshot(atNanoseconds: now)
            let estimate = try #require(snapshot.estimatedRemainingNanoseconds)
            let trueRemaining = (chunkCount - index - 1) * perChunk

            // Integer conversion truncates; a nanosecond of slack, not a percentage.
            #expect(estimate <= trueRemaining + 1 && estimate + 1 >= trueRemaining,
                    "at chunk \(index + 1): estimate \(estimate) vs true \(trueRemaining)")
        }
    }

    @Test func theETAIsUnknownBeforeThereIsAnythingToExtrapolateFrom() {
        let metrics = Metrics.metrics(chunks: 100)

        #expect(metrics.snapshot(atNanoseconds: 0).estimatedRemainingNanoseconds == nil)
        // Time passing without a chunk completing is still nothing to extrapolate from.
        #expect(metrics.snapshot(atNanoseconds: 5_000_000_000).estimatedRemainingNanoseconds == nil)
    }
}

// MARK: - NFR-PERF-3's ratio

struct HostOverheadTests {

    @Test func theOverheadFractionIsHostTimeOverDeviceTime() throws {
        var metrics = Metrics.metrics(chunks: 100)
        var now: UInt64 = 0

        // Each chunk: 30 ms of device I/O, 60 us of host work. The ratio is 0.002 exactly.
        for index in UInt64(0) ..< 100 {
            metrics.record(Metrics.healthyChunk(index: index,
                                                phase: Metrics.tenMilliseconds,
                                                overhead: 60_000))
            now &+= 30 * Metrics.millisecond + 60_000
        }
        let snapshot = metrics.snapshot(atNanoseconds: now)

        #expect(snapshot.deviceNanoseconds == 100 * 30 * Metrics.millisecond)
        #expect(snapshot.hostOverheadNanoseconds == 100 * 60_000)
        expectClose(snapshot.hostOverheadFraction, 0.002, "overhead fraction")
    }

    /// The completeness check on the figure above. If the run's wall clock were mostly
    /// unaccounted for, an overhead fraction computed from the accounted part would be
    /// measuring a fraction of the story.
    @Test func unaccountedTimeIsTheRemainderAndNeverNegative() {
        var metrics = Metrics.metrics(chunks: 10)
        var now: UInt64 = 0
        for index in UInt64(0) ..< 10 {
            metrics.record(Metrics.healthyChunk(index: index, overhead: 50_000))
            now &+= 30 * Metrics.millisecond + 50_000 + 1_000_000     // 1 ms unaccounted
        }
        let snapshot = metrics.snapshot(atNanoseconds: now)

        #expect(snapshot.unaccountedNanoseconds == 10 * Metrics.millisecond)
        #expect(snapshot.deviceNanoseconds + snapshot.hostOverheadNanoseconds
                + snapshot.unaccountedNanoseconds == snapshot.elapsedNanoseconds)
    }

    /// A snapshot taken at a clock reading earlier than the run's start must not underflow into
    /// a `UInt64` of nineteen digits. The clock is monotonic; a metrics type is not the place
    /// to discover otherwise.
    @Test func aClockReadingBeforeTheStartYieldsZeroElapsedRatherThanAnUnderflow() {
        let metrics = RunMetrics(chunksPlanned: 10,
                                 deviceBytesTotal: 1_000,
                                 startBlock: 0,
                                 startedAtNanoseconds: 1_000_000)
        let snapshot = metrics.snapshot(atNanoseconds: 0)

        #expect(snapshot.elapsedNanoseconds == 0)
        #expect(snapshot.unaccountedNanoseconds == 0)
    }
}

// MARK: - Outcome semantics

struct ChunkOutcomeTests {

    /// Which counters each outcome moves, in one table. The point is the *differences* between
    /// rows: a failed write still has a valid read latency, a failed read has nothing at all,
    /// and a verify mismatch is timing-wise a complete chunk.
    @Test(arguments: [
        (ChunkOutcome.completed,       true,  true,  true,  UInt64(0), UInt64(0)),
        (ChunkOutcome.verifyMismatch,  true,  true,  true,  UInt64(0), UInt64(1)),
        (ChunkOutcome.failedReading,   false, false, false, UInt64(1), UInt64(0)),
        (ChunkOutcome.failedWriting,   true,  false, false, UInt64(1), UInt64(0)),
        (ChunkOutcome.failedVerifying, true,  true,  false, UInt64(1), UInt64(0)),
    ])
    func eachOutcomeMovesExactlyTheCountersItShould(
        outcome: ChunkOutcome,
        countsRead: Bool,
        countsWrite: Bool,
        countsVerify: Bool,
        expectedFailures: UInt64,
        expectedMismatches: UInt64
    ) {
        var metrics = Metrics.metrics(chunks: 1)
        metrics.record(ChunkMeasurement(
            byteLength: Metrics.chunkBytes,
            endBlock: Metrics.blocksPerChunk,
            outcome: outcome,
            readNanoseconds: Metrics.tenMilliseconds,
            // A phase that never ran carries no duration; one that ran and failed does.
            writeNanoseconds: outcome == .failedReading ? nil : Metrics.tenMilliseconds,
            verifyNanoseconds: (outcome == .failedReading || outcome == .failedWriting)
                ? nil : Metrics.tenMilliseconds,
            hostOverheadNanoseconds: 1_000))

        let snapshot = metrics.snapshot(atNanoseconds: 100 * Metrics.millisecond)
        let chunk = UInt64(Metrics.chunkBytes)

        #expect(snapshot.bytesRead == (countsRead ? chunk : 0))
        #expect(snapshot.bytesWritten == (countsWrite ? chunk : 0))
        #expect(snapshot.bytesVerified == (countsVerify ? chunk : 0))
        #expect(snapshot.readLatency.count == (countsRead ? 1 : 0))
        #expect(snapshot.verifyLatency.count == (countsVerify ? 1 : 0))
        #expect(snapshot.chunksFailed == expectedFailures)
        #expect(snapshot.chunksMismatched == expectedMismatches)

        // Whatever happened, the ground was covered and the position moved.
        #expect(snapshot.chunksAttempted == 1)
        #expect(snapshot.rangeBytesCovered == chunk)
        #expect(snapshot.currentBlock == Metrics.blocksPerChunk)
    }

    /// A verify mismatch is a **data** failure, not an I/O one: every byte moved, so it belongs
    /// in every rate and both histograms. Counting it as a phase failure would depress the
    /// throughput of a drive that is writing and reading perfectly well.
    @Test func aVerifyMismatchIsTimingWiseACompleteChunk() {
        var metrics = Metrics.metrics(chunks: 1)
        metrics.record(ChunkMeasurement(byteLength: Metrics.chunkBytes,
                                        endBlock: Metrics.blocksPerChunk,
                                        outcome: .verifyMismatch,
                                        readNanoseconds: Metrics.tenMilliseconds,
                                        writeNanoseconds: Metrics.tenMilliseconds,
                                        verifyNanoseconds: Metrics.tenMilliseconds,
                                        hostOverheadNanoseconds: 1_000))
        let snapshot = metrics.snapshot(atNanoseconds: 100 * Metrics.millisecond)

        #expect(snapshot.chunksFailed == 0)
        #expect(snapshot.chunksMismatched == 1)
        #expect(snapshot.failedPhaseNanoseconds == 0)
        #expect(snapshot.readLatency.count == 1)
        #expect(snapshot.verifyLatency.count == 1)
    }
}

// MARK: - Constant memory (NFR-PERF-7)

struct RunMetricsMemoryTests {

    /// Two histograms and about twenty scalars, whatever the run does. `LatencyHistogramTests`
    /// drives the bucket array past `disk8`'s full chunk count; this asserts the accumulator
    /// wrapped around them adds no growth of its own.
    @Test func alongRunLeavesTheFootprintUnchanged() {
        var metrics = Metrics.metrics(chunks: 200_000)
        let before = metrics.allocatedBucketCount

        var generator = SplitMix64(seed: 0x5255_4E4D_4554_5200)      // "RUNMETR\0"
        for index in UInt64(0) ..< 200_000 {
            let phase = UInt64.random(in: 1_000_000 ... 20_000_000, using: &generator)
            metrics.record(Metrics.healthyChunk(index: index, phase: phase))
        }

        #expect(metrics.allocatedBucketCount == before)
        #expect(before == 2 * LatencyHistogram.bucketCount)
        #expect(metrics.snapshot(atNanoseconds: 0).chunksAttempted == 200_000)
    }
}
