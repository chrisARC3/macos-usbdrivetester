//
//  RunSessionTests.swift
//  Step 11, increment 3: a run is a sequence of bounded calls, and the accumulators belong to the
//  session that spans them (CONSTRAINTS section 2).
//
//  ## What this file exists to catch
//
//  Every test here is written so that it **fails under the per-call accumulator this increment
//  replaced**. That is the discipline: a session test that would also pass against the old code
//  is asserting something the change did not do.
//
//  The four properties Shape A was chosen for, and where each is pinned:
//
//    | property | test |
//    |---|---|
//    | a true whole-run p99 | ``oneDistributionSpansEveryCall`` — percentiles do not compose, so the union has to be accumulated, not combined |
//    | whole-device progress and ETA | ``progressIsAFractionOfTheDeviceNotOfTheCall`` — the old code read exactly 1.0 here |
//    | `FailureLog`'s cap applies once per run | ``aBadRegionSpanningACallBoundaryIsOneRange`` — two logs cannot coalesce across a boundary at all |
//    | the FR-TEST-9 verdict only ever downgrades | ``aDowngradeInOneCallSurvivesTheNextOne`` — the defect found while scoping this increment |
//
//  ## Two calls over one device, and why the split is uneven
//
//  The fixture is 8,193 blocks: 64 full 64 KiB chunks and a final chunk of one block (FR-TEST-5).
//  The split at block 4,096 puts 32 chunks in the first call and 33 in the second, so the short
//  final chunk lands in the second call rather than at a call boundary — the run's awkward chunk
//  and the session's awkward seam are then two separate things, and a test failing tells you
//  which. It also makes the first call's coverage a hair under half the device, so
//  ``progressIsAFractionOfTheDeviceNotOfTheCall`` cannot pass by accident on a round number.
//

import Testing
import Foundation

// MARK: - Fixture

private enum Session {

    static let seed: UInt64 = 0x5345_5353_494F_4E00                  // "SESSION\0"
    static let ioSizeBytes = 64 * 1024
    static let blockSize = 512

    /// 8,193 blocks of 512 B = 64 full chunks + a final chunk of one block (FR-TEST-5).
    static let blocks: UInt64 = 8_193
    static let blocksPerChunk: UInt64 = 128

    /// The whole device, in bytes — the session's progress denominator.
    static let deviceBytes = blocks * UInt64(blockSize)

    /// Where the run is cut into two calls. 32 chunks before it, 33 after.
    static let splitBlock: UInt64 = 4_096
    static let chunksBeforeSplit: UInt64 = 32
    static let chunksAfterSplit: UInt64 = 33
    static let chunksTotal = chunksBeforeSplit + chunksAfterSplit          // 65

    static let deviceName = "disk9"

    static let grant = DeviceAccessGrant(deviceName: deviceName,
                                         claimHeld: true,
                                         exclusiveOpenHeld: true)

    /// The FR-TEST-9 verdict a real acquire on a healthy raw character device produces.
    static var bypassed: CacheBypassAssessment {
        CacheBypassAssessment(UncachedIOConfiguration(devicePath: "/dev/rdisk9",
                                                      nodeKind: .character,
                                                      noCacheResult: 0,
                                                      globalNoCacheResult: 0))
    }

    static func device() throws -> InMemoryBlockDevice {
        let device = InMemoryBlockDevice(logicalBlockSize: blockSize, blockCount: blocks)
        try TestPattern.fill(device, seed: seed)
        return device
    }

    /// A fresh session over the whole fixture device.
    static func session(clock: @escaping MonotonicClock) -> RunSessionObserver {
        RunSessionObserver(deviceBytesTotal: deviceBytes, cacheBypass: bypassed, clock: clock)
    }

    /// Issue **one bounded call** of the run into `session`, the way `RunCoordinator` does.
    ///
    /// The assessment comes from the session and the result goes back into it — which is the
    /// wiring under test in ``aDowngradeInOneCallSurvivesTheNextOne``. `runFinished` is what puts
    /// it back, so nothing here does it by hand.
    @discardableResult
    static func call(_ device: RawBlockDevice,
                     blocks range: Range<UInt64>,
                     into session: RunSessionObserver,
                     clock: @escaping MonotonicClock,
                     alsoObservedBy extra: RunObserver? = nil) throws -> RunSummary {
        let engine = RetentionTestEngine(device: device, ioSizeBytes: ioSizeBytes)
        let observer: RunObserver = extra.map { ObserverFanOut([session, $0]) } ?? session
        return try engine.run(buffers: try ChunkBuffers(ioSizeBytes: ioSizeBytes),
                              deviceName: deviceName,
                              blockRange: range,
                              cacheBypass: session.cacheBypass,
                              grant: { grant },
                              control: RunControl.uninterrupted,
                              observer: observer,
                              clock: clock)
    }

    /// Both calls of the whole-device run, in order.
    static func wholeRun(_ device: RawBlockDevice,
                         into session: RunSessionObserver,
                         clock: @escaping MonotonicClock) throws {
        try call(device, blocks: 0 ..< splitBlock, into: session, clock: clock)
        try call(device, blocks: splitBlock ..< blocks, into: session, clock: clock)
    }
}

/// Advances by a fixed step on every reading, so every duration the engine measures is exactly
/// one step. Same device as `RunMetricsObserverTests`' clock, with the step made settable so a
/// read can be given an implausible rate on purpose.
private final class SteppingClock {

    static let millisecond: UInt64 = 1_000_000

    private var current: UInt64 = 0
    private let step: UInt64

    init(step: UInt64 = SteppingClock.millisecond) {
        self.step = step
    }

    func now() -> UInt64 {
        defer { current &+= step }
        return current
    }
}

// MARK: - The defining property: runStarted folds, it does not replace

struct RunSessionFoldingTests {

    /// **The whole increment, in one assertion.** The old accumulator replaced itself on every
    /// `runStarted`, so after two calls it held the second call's 33 chunks. It holds 65.
    @Test func theSessionHoldsEveryCallsWorkAndNotJustTheLastOnes() throws {
        let clock = SteppingClock()
        let session = Session.session(clock: clock.now)

        try Session.wholeRun(try Session.device(), into: session, clock: clock.now)
        let snapshot = try #require(session.snapshot())

        #expect(snapshot.chunksAttempted == Session.chunksTotal)
        #expect(snapshot.chunksPlanned == Session.chunksTotal)
        #expect(snapshot.rangeBytesCovered == Session.deviceBytes)
        #expect(snapshot.bytesRead == Session.deviceBytes)
        #expect(snapshot.bytesWritten == Session.deviceBytes)
        #expect(snapshot.bytesVerified == Session.deviceBytes)
        #expect(snapshot.isComplete)
    }

    /// The session's origin is its **first** call's start block, not the most recent one's.
    /// A replacing accumulator reports the last call's start, which on a whole-device run means
    /// the report names the final gibibyte as where the run began.
    @Test func theSessionKeepsItsOwnOriginAcrossCalls() throws {
        let clock = SteppingClock()
        let session = Session.session(clock: clock.now)

        try Session.wholeRun(try Session.device(), into: session, clock: clock.now)
        let snapshot = try #require(session.snapshot())

        #expect(snapshot.startBlock == 0)
        #expect(snapshot.currentBlock == Session.blocks)
    }

    /// `currentBlock` follows the calls across the seam rather than restarting at each one.
    @Test func theBlockPositionAdvancesThroughTheSeam() throws {
        let clock = SteppingClock()
        let session = Session.session(clock: clock.now)
        let device = try Session.device()

        try Session.call(device, blocks: 0 ..< Session.splitBlock, into: session, clock: clock.now)
        let afterFirst = try #require(session.snapshot())
        #expect(afterFirst.currentBlock == Session.splitBlock)

        try Session.call(device, blocks: Session.splitBlock ..< Session.blocks,
                         into: session, clock: clock.now)
        let afterSecond = try #require(session.snapshot())
        #expect(afterSecond.currentBlock == Session.blocks)
        #expect(afterSecond.currentBlock > afterFirst.currentBlock)
    }

    @Test func aSessionThatHasIssuedNoCallHasMeasuredNothing() {
        let session = Session.session(clock: SteppingClock().now)
        #expect(session.snapshot() == nil)
        #expect(session.metrics == nil)
        #expect(session.failureLog.isEmpty)
    }
}

// MARK: - Whole-device progress and ETA (FR-METR-5/6)

struct RunSessionProgressTests {

    /// **The old code read exactly 1.0 here**, because the denominator was the call's own range.
    /// A whole-device run would have shown 100% at the end of its first gibibyte.
    @Test func progressIsAFractionOfTheDeviceNotOfTheCall() throws {
        let clock = SteppingClock()
        let session = Session.session(clock: clock.now)

        try Session.call(try Session.device(), blocks: 0 ..< Session.splitBlock,
                         into: session, clock: clock.now)
        let snapshot = try #require(session.snapshot())

        // 4,096 of 8,193 blocks: a hair under half the device.
        #expect(snapshot.fractionComplete > 0.49)
        #expect(snapshot.fractionComplete < 0.51)

        // **And `isComplete` is `true` at the same instant, deliberately.** The two answer
        // different questions and are not derived from each other: `isComplete` is "every chunk
        // the calls asked for was attempted", which the sequencer needs in order to know a call
        // finished cleanly, while `fractionComplete` is "this much of the device". Collapsing
        // them would make one of the two lie — and it is the whole-device figure the user reads.
        #expect(snapshot.isComplete)
        #expect(snapshot.chunksAttempted == Session.chunksBeforeSplit)
    }

    @Test func progressReachesOneOnlyWhenTheDeviceIsCovered() throws {
        let clock = SteppingClock()
        let session = Session.session(clock: clock.now)

        try Session.wholeRun(try Session.device(), into: session, clock: clock.now)
        let snapshot = try #require(session.snapshot())

        #expect(snapshot.fractionComplete == 1.0)
        #expect(snapshot.deviceBytesTotal == Session.deviceBytes)
    }

    /// The ETA extrapolates to the **end of the device**, so after the first of two calls it is
    /// non-zero. Under the per-call denominator it was zero — the call had finished its range.
    @Test func theEstimateRemainsAgainstTheDeviceAfterACallEnds() throws {
        let clock = SteppingClock()
        let session = Session.session(clock: clock.now)

        let device = try Session.device()
        try Session.call(device, blocks: 0 ..< Session.splitBlock, into: session, clock: clock.now)

        let midRun = try #require(session.snapshot())
        let remaining = try #require(midRun.estimatedRemainingNanoseconds)
        #expect(remaining > 0)

        try Session.call(device, blocks: Session.splitBlock ..< Session.blocks,
                         into: session, clock: clock.now)
        let atEnd = try #require(session.snapshot())
        #expect(atEnd.estimatedRemainingNanoseconds == 0)
    }

    /// One origin for the whole run, so the coverage rate is measured against wall-clock that
    /// **includes the gap between calls** — which is what makes the ETA honest about a run whose
    /// calls are not back to back. A per-call accumulator restarts its clock and cannot see it.
    @Test func elapsedSpansTheGapBetweenCalls() throws {
        let clock = SteppingClock()
        let session = Session.session(clock: clock.now)
        let device = try Session.device()

        try Session.call(device, blocks: 0 ..< Session.splitBlock, into: session, clock: clock.now)
        let first = try #require(session.snapshot())
        let afterFirst = first.elapsedNanoseconds

        // The gap: readings the run did not take, exactly as an app pausing between calls costs.
        for _ in 0 ..< 100 { _ = clock.now() }

        try Session.call(device, blocks: Session.splitBlock ..< Session.blocks,
                         into: session, clock: clock.now)
        let second = try #require(session.snapshot())
        let afterSecond = second.elapsedNanoseconds

        let gap = 100 * SteppingClock.millisecond
        #expect(afterSecond > afterFirst + gap,
                "the session's clock restarted at the second call")
    }
}

// MARK: - A true whole-run p99 (FR-METR-3, FR-RPT-3)

struct RunSessionLatencyTests {

    /// Percentiles do not compose, which is the reason the accumulator had to move. So the
    /// distribution has to hold **every** call's samples: one per chunk, across the whole run.
    @Test func oneDistributionSpansEveryCall() throws {
        let clock = SteppingClock()
        let session = Session.session(clock: clock.now)

        try Session.wholeRun(try Session.device(), into: session, clock: clock.now)
        let snapshot = try #require(session.snapshot())

        #expect(snapshot.readLatency.count == Session.chunksTotal)
        #expect(snapshot.verifyLatency.count == Session.chunksTotal)
        #expect(snapshot.readLatency.overflowCount == 0)
        #expect(snapshot.readLatency.p99 != nil)
    }

    /// The extremes are the run's, not the last call's. A slow read in the first call must still
    /// be the run's maximum after the second call has come and gone — which is precisely what an
    /// accumulator that resets cannot say.
    @Test func theExtremesAreTheRunsAndNotTheLastCalls() throws {
        // A clock whose step is 1 ms except during the first call's slow chunk. Rather than
        // reach into the engine, the two calls are given clocks of different steps: the first
        // call's reads are 8 ms each, the second's are 1 ms.
        let session = Session.session(clock: SteppingClock().now)
        let device = try Session.device()

        try Session.call(device, blocks: 0 ..< Session.splitBlock, into: session,
                         clock: SteppingClock(step: 8 * SteppingClock.millisecond).now)
        let afterFirst = try #require(session.snapshot(atNanoseconds: 0))
        let slowest = try #require(afterFirst.readLatency.maximumNanoseconds)
        #expect(slowest == 8 * SteppingClock.millisecond)

        try Session.call(device, blocks: Session.splitBlock ..< Session.blocks, into: session,
                         clock: SteppingClock(step: SteppingClock.millisecond).now)
        let afterSecond = try #require(session.snapshot(atNanoseconds: 0))

        // The run's maximum is still the first call's slow read; its minimum is the second's.
        #expect(afterSecond.readLatency.maximumNanoseconds == slowest)
        #expect(afterSecond.readLatency.minimumNanoseconds == SteppingClock.millisecond)
        #expect(afterSecond.readLatency.count == Session.chunksTotal)
    }
}

// MARK: - FailureLog's cap applies once per run (FR-RPT-1)

struct RunSessionFailureTests {

    /// **Two logs cannot do this at all.** A bad region straddling a call boundary is one
    /// contiguous range of the device, and a report that printed it as two would be describing
    /// the tool's call structure rather than the drive.
    @Test func aBadRegionSpanningACallBoundaryIsOneRange() throws {
        let clock = SteppingClock()
        let session = Session.session(clock: clock.now)
        let device = try Session.device()

        // Straddles the split: the last chunk of call 1 (3,968–4,095) and the first of call 2
        // (4,096–4,223) both fail to read.
        device.injectReadFault(blocks: 4_000 ..< 4_200)

        try Session.wholeRun(device, into: session, clock: clock.now)

        let log = session.failureLog
        #expect(log.ranges.count == 1, "the seam split one bad region into \(log.ranges.count)")
        #expect(log.totalRangeCount == 1)

        let range = try #require(log.ranges.first)
        #expect(range.startBlock == 3_968)
        #expect(range.blockCount == 2 * Session.blocksPerChunk)
        #expect(range.kind == .readError)
        #expect(log.failedBlockCount == 2 * Session.blocksPerChunk)
    }

    /// Failures from calls that do not touch each other stay separate, so the coalescing above
    /// is adjacency and not a collapse of everything into one row.
    @Test func failuresInDifferentCallsStayDistinctWhenTheyDoNotAdjoin() throws {
        let clock = SteppingClock()
        let session = Session.session(clock: clock.now)
        let device = try Session.device()

        // Both faults sit **inside a single chunk**: 128–255 is chunk 1 exactly, and 6,020–6,099
        // is inside chunk 47 (6,016–6,143). A fault straddling a chunk boundary would fail two
        // chunks and coalesce into one 256-block range, which is a different property — it is the
        // one the test above measures, and keeping the two apart is the point of the arithmetic.
        device.injectReadFault(blocks: 128 ..< 256)                    // call 1, chunk 1
        device.injectReadFault(blocks: 6_020 ..< 6_100)                // call 2, chunk 47

        try Session.wholeRun(device, into: session, clock: clock.now)

        let log = session.failureLog
        #expect(log.ranges.count == 2)
        #expect(log.failedBlockCount == 2 * Session.blocksPerChunk)
    }

    /// The cap is the **run's**, so a caller reading the log mid-run must not close the range
    /// still being coalesced. Reading finishes a copy; the session's own pending range stays open.
    @Test func readingTheLogMidRunDoesNotEndTheCoalescing() throws {
        let clock = SteppingClock()
        let session = Session.session(clock: clock.now)
        let device = try Session.device()

        device.injectReadFault(blocks: 4_000 ..< 4_200)

        try Session.call(device, blocks: 0 ..< Session.splitBlock, into: session, clock: clock.now)

        // The poll a live display makes, arriving between the two calls.
        let midRun = session.failureLog
        #expect(midRun.ranges.count == 1)
        #expect(midRun.ranges.first?.blockCount == Session.blocksPerChunk)

        try Session.call(device, blocks: Session.splitBlock ..< Session.blocks,
                         into: session, clock: clock.now)

        // Still one range, still coalesced — the mid-run read did not sever it.
        let final = session.failureLog
        #expect(final.ranges.count == 1)
        #expect(final.ranges.first?.blockCount == 2 * Session.blocksPerChunk)
    }

    /// The session counts failing chunks across calls too, so a display's failure count does not
    /// reset every gibibyte.
    @Test func theFailedChunkCountIsTheRuns() throws {
        let clock = SteppingClock()
        let session = Session.session(clock: clock.now)
        let device = try Session.device()

        // One chunk each, for the reason given on the test above.
        device.injectReadFault(blocks: 128 ..< 256)                    // call 1, chunk 1
        device.injectWriteFault(blocks: 6_020 ..< 6_100)               // call 2, chunk 47

        try Session.wholeRun(device, into: session, clock: clock.now)
        let snapshot = try #require(session.snapshot())

        #expect(snapshot.chunksFailed == 2)
        #expect(snapshot.chunksAttempted == Session.chunksTotal)
    }
}

// MARK: - FR-TEST-9's verdict only ever downgrades, across calls too

struct RunSessionCacheBypassTests {

    /// **The defect this increment found.** The assessment was re-seeded from the acquire-time
    /// structural facts on every call, so a `likelyCached` verdict earned at 40% of a drive was
    /// gone by 41% — silently, and in the direction that matters, because the verdict qualifies
    /// whether the verify result can be believed at all.
    @Test func aDowngradeInOneCallSurvivesTheNextOne() throws {
        let session = Session.session(clock: SteppingClock().now)
        let device = try Session.device()

        // A 64 KiB read in 1 ns is 65 TB/s. No USB link of any generation carries that, so the
        // falsifier concludes the host answered (FR-TEST-9) and downgrades on the first chunk.
        try Session.call(device, blocks: 0 ..< Session.splitBlock, into: session,
                         clock: SteppingClock(step: 1).now)
        #expect(session.cacheBypass.state.qualifiesVerifyResult,
                "the fast clock did not trigger the falsifier; this test proves nothing")

        // A second call at an entirely plausible rate. It must not promote the verdict back.
        try Session.call(device, blocks: Session.splitBlock ..< Session.blocks, into: session,
                         clock: SteppingClock(step: SteppingClock.millisecond).now)
        #expect(session.cacheBypass.state.qualifiesVerifyResult,
                "a later call at a plausible rate promoted a downgraded verdict")
    }

    /// A healthy run leaves the verdict where the acquire put it, so the test above is measuring
    /// the downgrade rather than a verdict that was never good.
    @Test func aHealthyRunLeavesTheVerdictBypassed() throws {
        let clock = SteppingClock()
        let session = Session.session(clock: clock.now)

        #expect(!session.cacheBypass.state.qualifiesVerifyResult)
        try Session.wholeRun(try Session.device(), into: session, clock: clock.now)
        #expect(!session.cacheBypass.state.qualifiesVerifyResult)
    }

    /// The fastest read the falsifier saw is the **run's**, not the last call's — it is what the
    /// report quotes as what was actually observed, rather than only that a threshold held.
    @Test func theFastestObservedReadIsTheRuns() throws {
        let session = Session.session(clock: SteppingClock().now)
        let device = try Session.device()

        try Session.call(device, blocks: 0 ..< Session.splitBlock, into: session,
                         clock: SteppingClock(step: SteppingClock.millisecond).now)
        let afterFast = session.cacheBypass.fastestObservedBytesPerSecond
        #expect(afterFast > 0)

        // Slower reads throughout: the recorded fastest must not fall.
        try Session.call(device, blocks: Session.splitBlock ..< Session.blocks, into: session,
                         clock: SteppingClock(step: 50 * SteppingClock.millisecond).now)
        #expect(session.cacheBypass.fastestObservedBytesPerSecond == afterFast)
    }
}

// MARK: - Constant memory, at session scope (NFR-PERF-7)

struct RunSessionMemoryTests {

    /// NFR-PERF-7 was asserted for a run when a run was one call. A whole-device run is ~1,000
    /// calls, so the claim has to be re-made at the scope that now matters: the accumulator must
    /// not grow with the **number of calls** either.
    @Test func theAccumulatorDoesNotGrowWithTheNumberOfCalls() throws {
        let clock = SteppingClock()
        let session = Session.session(clock: clock.now)
        let device = try Session.device()

        // Thirty-two calls of two chunks each, rather than two of thirty-odd. The final block is
        // left uncovered: 32 × 256 is 8,192 of the fixture's 8,193, and a short 33rd call would
        // be testing FR-TEST-5 rather than the thing this test is about.
        var start: UInt64 = 0
        var afterFirstCall: Int?
        while start + 2 * Session.blocksPerChunk <= Session.blocks {
            try Session.call(device, blocks: start ..< (start + 2 * Session.blocksPerChunk),
                             into: session, clock: clock.now)
            let metrics = try #require(session.metrics)
            let buckets = metrics.allocatedBucketCount
            if afterFirstCall == nil { afterFirstCall = buckets }
            #expect(buckets == afterFirstCall,
                    "the histograms grew at the call starting \(start)")
            start += 2 * Session.blocksPerChunk
        }

        // 32 calls × 2 chunks. Asserted so a loop that silently stopped early could not make the
        // bucket check above pass by never having exercised the seam more than once.
        let snapshot = try #require(session.snapshot())
        #expect(snapshot.chunksAttempted == 64)
        #expect(snapshot.chunksPlanned == 64)
    }
}

// MARK: - The denominator is stable, and a pause costs nothing (2026-08-18)

/// **Both properties here were found missing by `metrics-check.sh`, not by a unit test**, and the
/// reason is worth keeping: unit tests drove a deterministic clock and never asked the same run
/// twice. The gate polls after a call's reply and compares, which is precisely the question no
/// test was asking.
///
/// Two denominators were tried on hardware before this one. `now - start` made a finished run's
/// throughput decay while nobody watched: on the first 1 GiB call the reply said 159.0 MB/s
/// covering and a poll 1.31 s later said 133.2 — a 16% drop with no new work done.
/// Device-plus-host fixed that and came within 1.35% (161.1), but it excludes the scheduling
/// inside a call, which an outside observer counts.
///
/// What is left is wall clock less the gaps between calls: 158.8 MB/s, 0.11% from the call's own
/// wall-clock rate, and free of the one span that is nobody's throughput.
struct RunSessionStabilityTests {

    /// Steps like `SteppingClock` so the engine measures real durations, but can also be jumped
    /// forward by a lump — which is what a pause, or simply nobody polling for a minute, is.
    private final class JumpableClock {
        private var current: UInt64 = 0
        private let step: UInt64
        init(step: UInt64 = 1_000_000) { self.step = step }
        func now() -> UInt64 { defer { current &+= step }; return current }
        func jump(_ nanoseconds: UInt64) { current &+= nanoseconds }
    }

    /// Ask a finished run twice, an hour apart. It must answer the same thing.
    @Test func aFinishedRunReportsTheSameRatesHoweverMuchLaterYouAsk() throws {
        let clock = JumpableClock()
        let device = try Session.device()
        let session = Session.session(clock: clock.now)
        try Session.call(device, blocks: 0 ..< Session.splitBlock, into: session, clock: clock.now)

        let atTheReply = try #require(session.snapshot())
        clock.jump(3_600 * 1_000_000_000)
        let anHourLater = try #require(session.snapshot())

        #expect(atTheReply.sustainedReadBytesPerSecond == anHourLater.sustainedReadBytesPerSecond)
        #expect(atTheReply.sustainedWriteBytesPerSecond == anHourLater.sustainedWriteBytesPerSecond)
        #expect(atTheReply.coverageBytesPerSecond == anHourLater.coverageBytesPerSecond)
        #expect(atTheReply.estimatedRemainingNanoseconds == anHourLater.estimatedRemainingNanoseconds)
        #expect(atTheReply.elapsedNanoseconds == anHourLater.elapsedNanoseconds,
                "between calls the reading is frozen at the last call's end")
    }

    /// A pause between two calls must not change what the drive is reported to have achieved.
    ///
    /// FR-CTRL-3 lets a user pause for as long as they like. Charged to the denominator, half an
    /// hour away from the keyboard would halve a healthy drive's reported throughput and inflate
    /// its ETA to match — the run would look like it had degraded because somebody had lunch.
    @Test func aPauseBetweenCallsChangesNeitherTheRateNorTheETA() throws {
        let pause: UInt64 = 30 * 60 * 1_000_000_000
        let device = try Session.device()

        func rateAfterBothCalls(pausing: Bool) throws -> (Double, UInt64) {
            let clock = JumpableClock()
            let session = Session.session(clock: clock.now)
            try Session.call(device, blocks: 0 ..< Session.splitBlock,
                             into: session, clock: clock.now)
            if pausing { clock.jump(pause) }
            try Session.call(device, blocks: Session.splitBlock ..< Session.blocks,
                             into: session, clock: clock.now)
            let snapshot = try #require(session.snapshot())
            return (try #require(snapshot.sustainedReadBytesPerSecond), snapshot.idleNanoseconds)
        }

        let (straightThrough, noIdle) = try rateAfterBothCalls(pausing: false)
        let (withAPause, idle) = try rateAfterBothCalls(pausing: true)

        #expect(withAPause == straightThrough,
                "a pause changed the reported read rate: \(withAPause) vs \(straightThrough)")
        // The pause is not lost — it is reported as time no call was running. Asserted so the
        // expectation above cannot pass because the pause never happened.
        #expect(idle >= pause, "the pause was not measured at all")
        #expect(noIdle < pause, "the un-paused run should have next to no idle time")
    }
}
