//
//  RunMetricsObserverTests.swift
//  Step 9's wiring: the engine's per-chunk measurement, the fan-out, and metrics from a real
//  simulated run.
//
//  ## The property this file exists for
//
//  `RunMetrics` is arithmetic and is tested as arithmetic in `RunMetricsTests`. What cannot be
//  tested there is the thing that actually went wrong in Step 8's seam: **the engine emitting a
//  per-chunk event on some paths and not others.**
//
//  `chunkCompleted` fired only for chunks that got through every phase — all three `catch`
//  blocks `continue` past it — which was harmless while nothing computed statistics from it and
//  became a defect the moment something did. An accumulator fed only completed chunks stalls its
//  progress counter while the engine walks on: percent frozen, ETA running away, on exactly the
//  failing drive this tool exists to find.
//
//  So ``MeasurementCompletenessTests`` drives runs with every mix of injected faults and asserts
//  **one measurement per planned chunk, no more and no fewer**, with the right outcome on each.
//  "Every path remembered to emit" is precisely the kind of property that is true until somebody
//  adds a path, so it is asserted rather than reviewed.
//
//  ## Why the overhead arithmetic can be asserted exactly
//
//  The engine reads its injected clock a fixed number of times per chunk, so under a clock that
//  advances by a constant step every reading, host overhead is an exact multiple of that step —
//  4 × step for a chunk that completes, 1 × step for one whose read failed. That makes the
//  subtraction testable without any real timing at all. **The resulting ratio is nonsense as a
//  performance figure** (it says host work outweighs device work 4:3), because a stepping clock
//  gives every operation the same duration; NFR-PERF-3's real ratio comes from hardware.
//

import Testing
import Foundation

// MARK: - Fixtures

private enum Wiring {

    static let seed: UInt64 = 0x5749_5249_4E47_0000              // "WIRING\0\0"
    static let ioSizeBytes = 64 * 1024
    static let blockSize = 512

    /// 8,193 blocks of 512 B = 64 full chunks + a final chunk of one block (FR-TEST-5).
    static let blocks: UInt64 = 8_193
    static let chunkCount = 65
    static let blocksPerChunk: UInt64 = 128

    static let deviceName = "disk9"

    static let grant = DeviceAccessGrant(deviceName: deviceName,
                                         claimHeld: true,
                                         exclusiveOpenHeld: true)

    static func device() throws -> InMemoryBlockDevice {
        let device = InMemoryBlockDevice(logicalBlockSize: blockSize, blockCount: blocks)
        try TestPattern.fill(device, seed: seed)
        return device
    }

    static func buffers() throws -> ChunkBuffers {
        try ChunkBuffers(ioSizeBytes: ioSizeBytes)
    }

    /// The FR-TEST-9 verdict a real acquire on a healthy raw device produces.
    static var bypassed: CacheBypassAssessment {
        CacheBypassAssessment(UncachedIOConfiguration(devicePath: "/dev/rdisk9",
                                                      nodeKind: .character,
                                                      noCacheResult: 0,
                                                      globalNoCacheResult: 0))
    }

    /// Run the cycle over `device`, reporting to `observer`.
    @discardableResult
    static func run(_ device: RawBlockDevice,
                    observer: RunObserver,
                    clock: @escaping MonotonicClock) throws -> RunSummary {
        let engine = RetentionTestEngine(device: device, ioSizeBytes: ioSizeBytes)
        return try engine.run(buffers: buffers(),
                              deviceName: deviceName,
                              cacheBypass: bypassed,
                              grant: { grant },
                              observer: observer,
                              clock: clock)
    }
}

/// Advances by a fixed step on every reading, so every duration the engine measures is exactly
/// one step and the overhead subtraction has an exact expected answer.
private final class SteppedClock {

    static let step: UInt64 = 1_000_000                          // 1 ms

    private var current: UInt64 = 0

    func now() -> UInt64 {
        defer { current &+= Self.step }
        return current
    }
}

/// An observer that answers a configurable disposition and counts what it was asked.
private final class DecidingObserver: RunObserver {

    private(set) var starts = 0
    private(set) var measured = 0
    private(set) var failuresSeen = 0
    private(set) var finishes = 0

    var disposition: FailureDisposition = .continueRun

    func runStarted(_ start: RunStart) { starts += 1 }
    func chunkMeasured(_ chunk: Chunk, measurement: ChunkMeasurement) { measured += 1 }
    func runFinished(_ summary: RunSummary) { finishes += 1 }

    func failureDetected(_ failure: BlockRangeFailure) -> FailureDisposition {
        failuresSeen += 1
        return disposition
    }
}

// MARK: - One measurement per chunk, on every path (D5)

struct MeasurementCompletenessTests {

    /// Outcomes in chunk order, for asserting the whole shape of a run at once.
    private func outcomes(_ recorder: RecordingRunObserver) -> [ChunkOutcome] {
        recorder.measurements.map(\.measurement.outcome)
    }

    @Test func aCleanRunMeasuresEveryChunkExactlyOnce() throws {
        let recorder = RecordingRunObserver()
        try Wiring.run(try Wiring.device(), observer: recorder, clock: SteppedClock().now)

        #expect(recorder.measurements.count == Wiring.chunkCount)
        #expect(outcomes(recorder).allSatisfy { $0 == .completed })
        #expect(recorder.completedChunks.count == Wiring.chunkCount)
    }

    /// The chunk indices are the point: a measurement arrives for the *failed* chunk, in place,
    /// and every other chunk is untouched.
    @Test func aReadFaultStillProducesAMeasurementForThatChunk() throws {
        let device = try Wiring.device()
        device.injectReadFault(blocks: 128 ..< 256)                       // exactly chunk 1

        let recorder = RecordingRunObserver()
        try Wiring.run(device, observer: recorder, clock: SteppedClock().now)

        #expect(recorder.measurements.count == Wiring.chunkCount)
        #expect(outcomes(recorder)[1] == .failedReading)
        #expect(outcomes(recorder)[0] == .completed)
        #expect(outcomes(recorder)[2] == .completed)

        // Nothing was read from it, so nothing was written or verified either.
        let failed = recorder.measurements[1].measurement
        #expect(failed.readNanoseconds != nil)
        #expect(failed.writeNanoseconds == nil)
        #expect(failed.verifyNanoseconds == nil)
    }

    @Test func aWriteFaultStillProducesAMeasurementForThatChunk() throws {
        let device = try Wiring.device()
        device.injectWriteFault(blocks: 256 ..< 384)                      // exactly chunk 2

        let recorder = RecordingRunObserver()
        try Wiring.run(device, observer: recorder, clock: SteppedClock().now)

        #expect(recorder.measurements.count == Wiring.chunkCount)
        #expect(outcomes(recorder)[2] == .failedWriting)

        // The read succeeded and is timed; the verify never happened (rule 3 of the cycle).
        let failed = recorder.measurements[2].measurement
        #expect(failed.readNanoseconds != nil)
        #expect(failed.writeNanoseconds != nil)
        #expect(failed.verifyNanoseconds == nil)
    }

    @Test func corruptionProducesAVerifyMismatchWithAllThreePhasesTimed() throws {
        let device = try Wiring.device()
        device.injectSilentCorruption(blocks: 1_000 ..< 1_002)            // chunk 7

        let recorder = RecordingRunObserver()
        try Wiring.run(device, observer: recorder, clock: SteppedClock().now)

        #expect(recorder.measurements.count == Wiring.chunkCount)
        #expect(outcomes(recorder)[7] == .verifyMismatch)

        // Every byte moved, so it is timing-wise a complete chunk — and must count toward the
        // rates and both latency distributions.
        let mismatched = recorder.measurements[7].measurement
        #expect(mismatched.readNanoseconds != nil)
        #expect(mismatched.writeNanoseconds != nil)
        #expect(mismatched.verifyNanoseconds != nil)
        #expect(mismatched.outcome.didCompleteAllPhases)
        #expect(!mismatched.outcome.isPhaseFailure)
    }

    /// Every failure kind at once. The count is what matters: 65 planned, 65 measured, whatever
    /// happened to each.
    @Test func everyMixOfOutcomesStillMeasuresEveryChunkExactlyOnce() throws {
        let device = try Wiring.device()
        device.injectReadFault(blocks: 128 ..< 256)                       // chunk 1
        device.injectWriteFault(blocks: 256 ..< 384)                      // chunk 2
        device.injectSilentCorruption(blocks: 1_000 ..< 1_002)            // chunk 7

        let recorder = RecordingRunObserver()
        try Wiring.run(device, observer: recorder, clock: SteppedClock().now)

        let seen = outcomes(recorder)
        #expect(seen.count == Wiring.chunkCount)
        #expect(seen[1] == .failedReading)
        #expect(seen[2] == .failedWriting)
        #expect(seen[7] == .verifyMismatch)

        for (index, outcome) in seen.enumerated() where ![1, 2, 7].contains(index) {
            #expect(outcome == .completed, "chunk \(index) should have completed")
        }
    }

    /// The chunks are measured **in order**, and each one's position matches its own chunk.
    @Test func eachMeasurementCarriesItsOwnChunksPositionAndLength() throws {
        let recorder = RecordingRunObserver()
        try Wiring.run(try Wiring.device(), observer: recorder, clock: SteppedClock().now)

        for (index, entry) in recorder.measurements.enumerated() {
            #expect(entry.chunk.index == index)
            #expect(entry.measurement.endBlock == entry.chunk.startBlock + entry.chunk.blockCount)
            #expect(entry.measurement.byteLength == entry.chunk.byteLength)
        }

        // FR-TEST-5: the final chunk is the exact remainder — one block here.
        let last = try #require(recorder.measurements.last)
        #expect(last.measurement.byteLength == Wiring.blockSize)
        #expect(last.measurement.endBlock == Wiring.blocks)
    }

    /// A stop ends the run, but the chunk it happened on still gets its measurement — otherwise
    /// the last thing a user saw before the run stopped would be missing from the report.
    @Test func theChunkAStopHappenedOnIsStillMeasured() throws {
        let device = try Wiring.device()
        device.injectReadFault(blocks: 128 ..< 256)                       // chunk 1

        let recorder = RecordingRunObserver()
        recorder.dispositionForFailure = { _ in .stopRun }
        let summary = try Wiring.run(device, observer: recorder, clock: SteppedClock().now)

        // Two chunks attempted: chunk 0 completed, chunk 1 failed and stopped the run.
        #expect(recorder.measurements.count == 2)
        #expect(outcomes(recorder) == [.completed, .failedReading])
        #expect(summary.chunksProcessed == 2)
        if case .stoppedOnFailure = summary.outcome {} else {
            Issue.record("expected the run to stop, got \(summary.outcome)")
        }
    }
}

// MARK: - The overhead subtraction

struct HostOverheadMeasurementTests {

    /// The engine reads its clock 8 times for a chunk that completes: the span start, then two
    /// readings for each of the three phases, then one after the compare. Under a constant-step
    /// clock the span is 7 steps and the device phases are 3, so overhead is **exactly 4 steps**.
    ///
    /// - Note: 4:3 host-to-device is an absurd ratio for a real run, and that is the stepping
    ///   clock's doing — it gives a `memcmp` the same duration as a 64 KiB device read.
    ///   NFR-PERF-3's real number comes from hardware; what is asserted here is that the
    ///   *subtraction* is right.
    @Test func overheadIsTheChunkSpanMinusItsDevicePhases() throws {
        let recorder = RecordingRunObserver()
        try Wiring.run(try Wiring.device(), observer: recorder, clock: SteppedClock().now)

        let step = SteppedClock.step
        for entry in recorder.measurements {
            let measurement = entry.measurement
            #expect(measurement.readNanoseconds == step)
            #expect(measurement.writeNanoseconds == step)
            #expect(measurement.verifyNanoseconds == step)
            #expect(measurement.hostOverheadNanoseconds == 4 * step,
                    "chunk \(entry.chunk.index): overhead \(measurement.hostOverheadNanoseconds)")
        }
    }

    /// A chunk whose read failed is only three clock readings long: span start, read start, and
    /// the failure. Span 2 steps, device 1 step, overhead 1 step.
    @Test func aFailedReadsOverheadIsMeasuredFromItsShorterSpan() throws {
        let device = try Wiring.device()
        device.injectReadFault(blocks: 128 ..< 256)

        let recorder = RecordingRunObserver()
        try Wiring.run(device, observer: recorder, clock: SteppedClock().now)

        let failed = recorder.measurements[1].measurement
        #expect(failed.readNanoseconds == SteppedClock.step)
        #expect(failed.hostOverheadNanoseconds == SteppedClock.step)
    }
}

// MARK: - The fan-out

struct ObserverFanOutTests {

    @Test func everyEventReachesEveryObserver() throws {
        let first = DecidingObserver()
        let second = DecidingObserver()
        let device = try Wiring.device()
        device.injectReadFault(blocks: 128 ..< 256)

        try Wiring.run(device,
                       observer: ObserverFanOut([first, second]),
                       clock: SteppedClock().now)

        for observer in [first, second] {
            #expect(observer.starts == 1)
            #expect(observer.measured == Wiring.chunkCount)
            #expect(observer.failuresSeen == 1)
            #expect(observer.finishes == 1)
        }
    }

    /// **Stop wins.** Adding a passive observer — one that answers with the default
    /// `.continueRun` — must never be able to override a decision to stop.
    @Test func oneObserverAskingToStopStopsTheRun() throws {
        let stopper = DecidingObserver()
        stopper.disposition = .stopRun
        let passive = DecidingObserver()                     // answers .continueRun

        let device = try Wiring.device()
        device.injectReadFault(blocks: 128 ..< 256)

        let summary = try Wiring.run(device,
                                     observer: ObserverFanOut([passive, stopper]),
                                     clock: SteppedClock().now)

        if case .stoppedOnFailure = summary.outcome {} else {
            Issue.record("a passive observer overrode a stop: \(summary.outcome)")
        }
        #expect(summary.chunksProcessed == 2)
    }

    /// Order must not matter, and no observer may be skipped once an answer is known: the
    /// stopper is asked even though the passive one was asked first, and vice versa.
    @Test(arguments: [true, false])
    func everyObserverIsAskedWhicheverOrderTheyAreIn(stopperFirst: Bool) throws {
        let stopper = DecidingObserver()
        stopper.disposition = .stopRun
        let passive = DecidingObserver()

        let device = try Wiring.device()
        device.injectReadFault(blocks: 128 ..< 256)

        let observers: [RunObserver] = stopperFirst ? [stopper, passive] : [passive, stopper]
        let summary = try Wiring.run(device,
                                     observer: ObserverFanOut(observers),
                                     clock: SteppedClock().now)

        #expect(stopper.failuresSeen == 1)
        #expect(passive.failuresSeen == 1, "an observer was skipped once the answer was known")
        if case .stoppedOnFailure = summary.outcome {} else {
            Issue.record("expected a stop, got \(summary.outcome)")
        }
    }

    @Test func anEmptyFanOutIsHarmless() throws {
        let summary = try Wiring.run(try Wiring.device(),
                                     observer: ObserverFanOut([]),
                                     clock: SteppedClock().now)
        #expect(summary.outcome == .completed)
    }
}

// MARK: - Metrics from a real simulated run

struct RunMetricsFromARunTests {

    @Test func aCleanRunProducesACompleteSnapshot() throws {
        let clock = SteppedClock()
        let metrics = RunMetricsObserver(clock: clock.now)

        try Wiring.run(try Wiring.device(), observer: metrics, clock: clock.now)
        let snapshot = try #require(metrics.snapshot())

        let deviceBytes = Wiring.blocks * UInt64(Wiring.blockSize)

        #expect(snapshot.chunksAttempted == UInt64(Wiring.chunkCount))
        #expect(snapshot.chunksPlanned == UInt64(Wiring.chunkCount))
        #expect(snapshot.chunksFailed == 0)
        #expect(snapshot.isComplete)
        #expect(snapshot.fractionComplete == 1.0)

        #expect(snapshot.rangeBytesTotal == deviceBytes)
        #expect(snapshot.rangeBytesCovered == deviceBytes)
        #expect(snapshot.bytesRead == deviceBytes)
        #expect(snapshot.bytesWritten == deviceBytes)
        #expect(snapshot.bytesVerified == deviceBytes)
        #expect(snapshot.currentBlock == Wiring.blocks)

        // Both distributions saw every chunk (D4: the original read and the verify read).
        #expect(snapshot.readLatency.count == UInt64(Wiring.chunkCount))
        #expect(snapshot.verifyLatency.count == UInt64(Wiring.chunkCount))
        #expect(snapshot.readLatency.overflowCount == 0)

        // Every phase is one clock step under this clock, so min == max exactly.
        #expect(snapshot.readLatency.minimumNanoseconds == SteppedClock.step)
        #expect(snapshot.readLatency.maximumNanoseconds == SteppedClock.step)

        #expect(snapshot.estimatedRemainingNanoseconds == 0)
    }

    /// **The A7 hazard, end to end.** A run in which chunks fail must still reach 100% and must
    /// still finish at the last block. Progress that counted only successes would stop short.
    @Test func progressReachesTheEndEvenWhenChunksFail() throws {
        let clock = SteppedClock()
        let device = try Wiring.device()
        device.injectReadFault(blocks: 128 ..< 256)                       // chunk 1
        device.injectWriteFault(blocks: 256 ..< 384)                      // chunk 2

        let metrics = RunMetricsObserver(clock: clock.now)
        try Wiring.run(device, observer: metrics, clock: clock.now)
        let snapshot = try #require(metrics.snapshot())

        let deviceBytes = Wiring.blocks * UInt64(Wiring.blockSize)
        let chunkBytes = UInt64(Wiring.ioSizeBytes)

        // Ground covered: all of it. Data moved: two chunks fewer.
        #expect(snapshot.fractionComplete == 1.0)
        #expect(snapshot.rangeBytesCovered == deviceBytes)
        #expect(snapshot.currentBlock == Wiring.blocks)
        #expect(snapshot.chunksAttempted == UInt64(Wiring.chunkCount))
        #expect(snapshot.chunksFailed == 2)

        // Chunk 1's read failed, so it read nothing. Chunk 2 read fine but wrote nothing.
        #expect(snapshot.bytesRead == deviceBytes - chunkBytes)
        #expect(snapshot.bytesWritten == deviceBytes - 2 * chunkBytes)
        #expect(snapshot.bytesVerified == deviceBytes - 2 * chunkBytes)

        // The two failing phases' time is reported, not folded into the read/write rates.
        #expect(snapshot.failedPhaseNanoseconds == 2 * SteppedClock.step)
        #expect(snapshot.readLatency.count == UInt64(Wiring.chunkCount) - 1)
    }

    @Test func theSnapshotIsNilBeforeARunStarts() {
        let metrics = RunMetricsObserver(clock: SteppedClock().now)
        #expect(metrics.snapshot() == nil)
        #expect(metrics.metrics == nil)
    }

    /// The run's shape reaches the accumulator through `RunStart` — including the block size
    /// added in Step 9, without which a range's size in bytes is not derivable.
    @Test func theRunsByteTotalComesFromTheStartEvent() throws {
        let recorder = RecordingRunObserver()
        try Wiring.run(try Wiring.device(), observer: recorder, clock: SteppedClock().now)

        let start = try #require(recorder.start)
        #expect(start.logicalBlockSize == Wiring.blockSize)
        #expect(start.rangeByteCount == Wiring.blocks * UInt64(Wiring.blockSize))
        #expect(start.chunkCount == UInt64(Wiring.chunkCount))
    }
}
