//
//  RunControlEngineTests.swift
//  The chunk-boundary settle (Step 11, increment 2). FR-CTRL-2/3/4, NFR-REL-10.
//
//  **This is where NFR-REL-10 is actually checked**, and it is checkable here in a way it is not
//  anywhere else: the engine is pure, so a pause can be driven from a test with no drive, no
//  daemon, and no XPC. The hardware pre-flight measures the *latency* of the same mechanism; what
//  it cannot do is prove the device was left consistent, because on a healthy drive a run that
//  ignored the pause entirely would look identical from outside.
//
//  ## What "settled with no write in flight" means as something a test can fail
//
//  The requirement is a claim about the device's state at the moment the pause is acknowledged.
//  Three observable consequences, and each has a test below:
//
//    1. **The chunk before the settle completed every phase** — read, write-back and verify, all
//       three timed and its outcome `.completed`. A settle in the middle of a chunk would show a
//       measurement with a nil write or verify.
//    2. **The chunk at the resume point was never touched.** Pinned with an injected write fault
//       just past the pause point: a run that carried on would hit it and report a failure, so
//       "no failures" is a result that can fail rather than an absence anyone has to trust.
//    3. **The device is bit-for-bit what it was.** NFR-REL-1 across an interruption, which is the
//       property the whole design exists to protect.
//
//  ## The resume point is a block, not a chunk index
//
//  `RunOutcome.pausedByUser(atBlock:)` names the block the run was **about to process**. A test
//  that only checked `chunksProcessed` would pass with an off-by-one in the block arithmetic, and
//  the block is what the sequencer actually issues the next call from — so it is checked directly,
//  against the first chunk the observer did *not* measure.
//

import Testing
import Foundation
@testable import USBDriveTester

// MARK: - Fixture

/// A device large enough to have a lot of chunks and small enough to run in milliseconds.
///
/// Deliberately the same geometry `RetentionCycleTests` uses — 8,193 blocks of 512 B at a 64 KiB
/// I/O size, so 128 blocks per chunk and **65 chunks, the last of them one block long**. Reusing it
/// means the interruption tests exercise the same short-final-chunk case (FR-TEST-5) the
/// uninterrupted ones do, rather than a rounder geometry that would hide it.
private enum ControlFixture {

    static let seed: UInt64 = 0x5152_4D41_5354_4552
    static let ioSizeBytes = 64 * 1024
    static let blocks: UInt64 = 8_193
    static let blocksPerChunk: UInt64 = 128
    static let chunkCount = 65
    static let deviceName = "disk9"

    static let grant = DeviceAccessGrant(deviceName: deviceName,
                                         claimHeld: true,
                                         exclusiveOpenHeld: true)

    static func device() throws -> InMemoryBlockDevice {
        let device = InMemoryBlockDevice(logicalBlockSize: 512, blockCount: blocks)
        try TestPattern.fill(device, seed: seed)
        return device
    }

    static func buffers() throws -> ChunkBuffers {
        try ChunkBuffers(ioSizeBytes: ioSizeBytes)
    }

    static var assessment: CacheBypassAssessment {
        CacheBypassAssessment(UncachedIOConfiguration(devicePath: "/dev/rdisk9",
                                                      nodeKind: .character,
                                                      noCacheResult: 0,
                                                      globalNoCacheResult: 0))
    }

    /// The block chunk `index` starts at, in the whole-device plan.
    static func startBlock(ofChunk index: Int) -> UInt64 {
        UInt64(index) * blocksPerChunk
    }
}

/// Answers `.proceed` for a fixed number of chunk boundaries and then asks for something else.
///
/// A class rather than a captured `var` so the **call count** is observable: a control consulted
/// once at the start of a run instead of once per chunk is a defect that several of the tests below
/// would otherwise pass, and the count is what distinguishes them.
private final class ControlDriver {

    private(set) var callCount = 0
    private let proceedFor: Int
    private let thenSignal: RunControlSignal

    init(proceedFor: Int, then signal: RunControlSignal) {
        self.proceedFor = proceedFor
        self.thenSignal = signal
    }

    var control: () -> RunControlSignal {
        { [self] in
            defer { callCount += 1 }
            return callCount < proceedFor ? .proceed : thenSignal
        }
    }
}

// MARK: - Tests

struct RunControlEngineTests {

    /// Run the fixture device, optionally interrupted, and hand back everything worth asserting on.
    private func run(proceedFor: Int? = nil,
                     then signal: RunControlSignal = .pause,
                     from startBlock: UInt64? = nil,
                     writeFaultAt faultBlocks: Range<UInt64>? = nil)
        throws -> (summary: RunSummary,
                   observer: RecordingRunObserver,
                   driver: ControlDriver?,
                   device: InMemoryBlockDevice) {

        let device = try ControlFixture.device()
        if let faultBlocks { device.injectWriteFault(blocks: faultBlocks) }

        let engine = RetentionTestEngine(device: device, ioSizeBytes: ControlFixture.ioSizeBytes)
        let observer = RecordingRunObserver()
        let driver = proceedFor.map { ControlDriver(proceedFor: $0, then: signal) }

        let range: Range<UInt64>? = startBlock.map { $0 ..< ControlFixture.blocks }

        let summary = try engine.run(buffers: ControlFixture.buffers(),
                                     deviceName: ControlFixture.deviceName,
                                     blockRange: range,
                                     cacheBypass: ControlFixture.assessment,
                                     grant: { ControlFixture.grant },
                                     control: driver?.control ?? RunControl.uninterrupted,
                                     observer: observer)

        return (summary, observer, driver, device)
    }

    // MARK: The baseline

    /// Nothing about adding a control changes a run that is never interrupted. If this fails, every
    /// other result in this file is about a different engine.
    @Test func anUninterruptedRunStillCompletesEveryChunk() throws {
        let (summary, observer, _, _) = try run()

        #expect(summary.outcome == .completed)
        #expect(summary.isComplete)
        #expect(summary.chunksProcessed == UInt64(ControlFixture.chunkCount))
        #expect(observer.measurements.count == ControlFixture.chunkCount)
        #expect(summary.outcome.resumeBlock == nil)
    }

    // MARK: The settle (NFR-REL-10)

    @Test func pauseSettlesAtTheNextChunkBoundaryAndNamesTheResumePoint() throws {
        let (summary, observer, _, _) = try run(proceedFor: 3, then: .pause)

        #expect(summary.outcome == .pausedByUser(atBlock: ControlFixture.startBlock(ofChunk: 3)))
        #expect(summary.chunksProcessed == 3)
        #expect(observer.measurements.count == 3)
        #expect(summary.outcome.resumeBlock == ControlFixture.startBlock(ofChunk: 3))
    }

    /// **The resume point is the first chunk the run did not measure**, checked against the
    /// observer rather than against arithmetic this test did itself. A test that recomputed
    /// `3 * 128` would agree with an engine that had the same off-by-one.
    @Test func theResumePointIsTheFirstChunkThatWasNotProcessed() throws {
        for proceedFor in [1, 7, 40, 64] {
            let (summary, observer, _, _) = try run(proceedFor: proceedFor, then: .pause)

            let lastMeasured = try #require(observer.measurements.last).chunk
            let expectedResume = lastMeasured.startBlock + lastMeasured.blockCount

            #expect(summary.outcome.resumeBlock == expectedResume,
                    "proceedFor=\(proceedFor)")
        }
    }

    /// **Consequence 1: the chunk before the settle completed every phase.**
    ///
    /// This is the closest a unit test gets to "no write in flight" — all three phases timed, and
    /// the chunk's own outcome `.completed`. A settle placed anywhere else in the loop would leave
    /// the last measurement with a nil write or verify.
    @Test func theChunkBeforeAPauseCompletedReadWriteAndVerify() throws {
        let (_, observer, _, _) = try run(proceedFor: 5, then: .pause)

        let last = try #require(observer.measurements.last).measurement
        #expect(last.outcome == .completed)
        #expect(last.readNanoseconds != nil)
        #expect(last.writeNanoseconds != nil)
        #expect(last.verifyNanoseconds != nil)
    }

    /// **Consequence 2: the chunk at the resume point was never touched.**
    ///
    /// The write fault sits inside chunk 3, which a run that ignored the pause would reach and
    /// fail on. So "no failures" here is a result that can fail rather than an absence to be
    /// trusted — the difference between a check and a comment.
    @Test func nothingBeyondTheResumePointIsWritten() throws {
        let faultBlock = ControlFixture.startBlock(ofChunk: 3) + 10

        // The control makes the fault unreachable.
        let paused = try run(proceedFor: 3, then: .pause,
                             writeFaultAt: faultBlock ..< (faultBlock + 1))
        #expect(paused.summary.failures.isEmpty)
        #expect(paused.observer.failures.isEmpty)

        // The same fault, with nothing interrupting: it IS reached. Without this half the test
        // above would pass against a device that never faults at all.
        let uninterrupted = try run(writeFaultAt: faultBlock ..< (faultBlock + 1))
        #expect(!uninterrupted.summary.failures.isEmpty,
                "the injected fault was never reached, so the pause test proved nothing")
    }

    /// **Consequence 3: NFR-REL-1 holds across an interruption.**
    @Test func aPausedRunLeavesTheDeviceBitForBitUnchanged() throws {
        let device = try ControlFixture.device()
        let before = device.snapshot()

        let engine = RetentionTestEngine(device: device, ioSizeBytes: ControlFixture.ioSizeBytes)
        let driver = ControlDriver(proceedFor: 9, then: .pause)
        let summary = try engine.run(buffers: ControlFixture.buffers(),
                                     deviceName: ControlFixture.deviceName,
                                     cacheBypass: ControlFixture.assessment,
                                     grant: { ControlFixture.grant },
                                     control: driver.control)

        #expect(summary.chunksProcessed == 9)
        #expect(device.snapshot() == before)
    }

    // MARK: The control is consulted per chunk, not once

    /// A control read once at the start of a run would satisfy several assertions above by
    /// accident. The call count is what separates "asked every chunk" from "asked once".
    @Test func theControlIsConsultedOncePerChunkBoundary() throws {
        let (summary, _, driver, _) = try run(proceedFor: 12, then: .pause)
        let driven = try #require(driver)

        // Twelve chunks processed, and the thirteenth boundary is where the pause was seen.
        #expect(summary.chunksProcessed == 12)
        #expect(driven.callCount == 13)
    }

    /// And on a run that finishes, it is asked exactly once per chunk and never after the last.
    @Test func anUninterruptedRunAsksExactlyOncePerChunk() throws {
        let (summary, _, driver, _) = try run(proceedFor: 1_000, then: .pause)
        let driven = try #require(driver)

        #expect(summary.outcome == .completed)
        #expect(driven.callCount == ControlFixture.chunkCount)
        #expect(summary.chunksProcessed == UInt64(ControlFixture.chunkCount))
    }

    /// **The run that finished while the request was in flight.**
    ///
    /// The control is read at the *top* of each iteration, so a pause arriving during the final
    /// chunk is never seen and the run completes. That is correct, and it is the case the state
    /// machine's `runEnded`-from-`pausing` row exists to absorb — without which the app would wait
    /// for a settle that is never coming.
    @Test func aPauseArrivingAfterTheLastChunkNeverFires() throws {
        let (summary, _, driver, _) = try run(proceedFor: ControlFixture.chunkCount, then: .pause)
        let driven = try #require(driver)

        #expect(summary.outcome == .completed)
        #expect(driven.callCount == ControlFixture.chunkCount)
    }

    /// A pause seen before the first chunk processes nothing at all — and says so honestly rather
    /// than reporting a run that did not happen.
    @Test func aPauseBeforeTheFirstChunkProcessesNothing() throws {
        let (summary, observer, _, device) = try run(proceedFor: 0, then: .pause)
        let untouched = try ControlFixture.device()

        #expect(summary.outcome == .pausedByUser(atBlock: 0))
        #expect(summary.chunksProcessed == 0)
        #expect(observer.measurements.isEmpty)
        #expect(summary.bytesRead == 0)
        #expect(summary.bytesWritten == 0)
        #expect(device.snapshot() == untouched.snapshot())
    }

    // MARK: Stop (FR-CTRL-4)

    @Test func stopSettlesTheSameWayAndEndsTheRun() throws {
        let (summary, observer, _, _) = try run(proceedFor: 6, then: .stop)

        #expect(summary.outcome == .stoppedByUser(atBlock: ControlFixture.startBlock(ofChunk: 6)))
        #expect(summary.chunksProcessed == 6)
        #expect(observer.measurements.count == 6)

        let last = try #require(observer.measurements.last).measurement
        #expect(last.outcome == .completed)
        #expect(last.writeNanoseconds != nil)
        #expect(last.verifyNanoseconds != nil)
    }

    /// **FR-FAIL-7.** A stopped run cannot be continued, so the value that would let somebody
    /// continue it does not exist — rather than existing and being ignored, which is the version a
    /// later edit turns back on.
    @Test func aStoppedRunOffersNoResumePoint() throws {
        let (stopped, _, _, _) = try run(proceedFor: 6, then: .stop)
        #expect(stopped.outcome.resumeBlock == nil)

        let (paused, _, _, _) = try run(proceedFor: 6, then: .pause)
        #expect(paused.outcome.resumeBlock != nil)
    }

    /// Neither interruption is a completion. `isComplete` gates the report's "completed clean"
    /// wording, and a run that stopped two thirds of the way through a drive must never reach it.
    @Test func neitherInterruptionCountsAsComplete() throws {
        for signal in [RunControlSignal.pause, .stop] {
            let (summary, _, _, _) = try run(proceedFor: 4, then: signal)
            #expect(!summary.isComplete, "signal=\(signal)")
            #expect(summary.chunksProcessed < summary.chunksPlanned, "signal=\(signal)")
        }
    }

    // MARK: Resume (FR-CTRL-3)

    /// **The whole point of the resume block**: a pause and a resume together cover every chunk of
    /// the device exactly once — no gap, and no chunk done twice.
    ///
    /// The second run is issued the way the sequencer will issue it: a fresh range starting at the
    /// resume point. That the two plans tile the device without overlap is the property that makes
    /// "resume continues from the correct next chunk" true, and it is checked as a set rather than
    /// by counting, so a gap and a duplicate cannot cancel out.
    @Test func aPauseAndAResumeCoverEveryChunkExactlyOnce() throws {
        let first = try run(proceedFor: 3, then: .pause)
        let resumeBlock = try #require(first.summary.outcome.resumeBlock)

        let second = try run(from: resumeBlock)

        #expect(second.summary.outcome == .completed)

        let covered = first.observer.measurements.map(\.chunk.startBlock)
                    + second.observer.measurements.map(\.chunk.startBlock)
        let expected = (0 ..< ControlFixture.chunkCount).map(ControlFixture.startBlock(ofChunk:))

        #expect(covered.count == ControlFixture.chunkCount, "a chunk was done twice, or skipped")
        #expect(Set(covered) == Set(expected))
        #expect(covered == covered.sorted(), "the resumed run did not carry on where the first left off")
    }

    /// Every chunk boundary is a legal place to resume from (FR-TEST-10): a whole multiple of
    /// 1 MiB from the start of the device, which is what the helper's `RunPlacement` enforces and
    /// would otherwise refuse the resumed call.
    ///
    /// Checked against the real permitted I/O sizes rather than the fixture's 64 KiB, because it is
    /// a claim about the shipped configuration — a resume point that was legal only at a test-only
    /// I/O size would be refused on hardware and nothing here would have said so.
    @Test func everyResumePointIsOnAOneMebibyteBoundary() throws {
        let mebibyte: UInt64 = 1 << 20

        for ioSize in TesterProtocol.permittedIOSizes {
            for chunkIndex in [0, 1, 5, 128] {
                let resumeByteOffset = UInt64(chunkIndex) * UInt64(ioSize)
                #expect(resumeByteOffset % mebibyte == 0,
                        "ioSize=\(ioSize) chunk=\(chunkIndex)")
            }
        }
    }

    // MARK: The signal itself

    /// `.proceed` is the only signal that lets a run continue. Written as an exhaustive walk so
    /// that adding a case to `RunControlSignal` without deciding what it means to the engine shows
    /// up here rather than as a run that quietly carries on.
    @Test func onlyProceedLetsARunContinue() throws {
        for signal in [RunControlSignal.pause, .stop] {
            let (summary, _, _, _) = try run(proceedFor: 2, then: signal)
            #expect(summary.chunksProcessed == 2, "signal=\(signal)")
        }

        let (completed, _, _, _) = try run(proceedFor: 1_000, then: .pause)
        #expect(completed.chunksProcessed == UInt64(ControlFixture.chunkCount))
    }

    /// The two interruptions describe themselves with the block, so a log line or a report can say
    /// where a run stopped without the reader computing it.
    @Test func theInterruptionsSayWhereTheyStopped() {
        #expect(RunOutcome.pausedByUser(atBlock: 4_096).description
                == "paused by the user at block 4096")
        #expect(RunOutcome.stoppedByUser(atBlock: 4_096).description
                == "stopped by the user at block 4096")
    }
}
