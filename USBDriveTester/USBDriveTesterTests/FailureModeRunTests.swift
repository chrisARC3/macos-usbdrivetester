//
//  FailureModeRunTests.swift
//  FR-FAIL-2 and FR-FAIL-3 against a device with injected faults. Step 10, increment 2.
//
//  These are the two gate items of BUILD-PLAN Step 10, and **they can only be discharged here.**
//  A healthy scratch drive produces no failures, and this project does not manufacture one on
//  real hardware. `InMemoryBlockDevice` carries the three fault hooks precisely so the failure
//  modes are provable without a bad drive; the hardware half of Step 10's gate is a *clean* run
//  producing a report.
//
//  ## What is new here, and what was already true
//
//  `StopPathTests.stoppingOnTheFirstFailureIssuesNoFurtherIO` (Step 8) already proves the
//  **engine** stops when an observer says to — with the disposition set by hand. What increment 2
//  adds is that the **mode** is what says so. So these tests drive `FailureModeObserver`, which
//  is what `RunCoordinator` actually composes into the run, rather than a hand-set closure.
//
//  The distinction is not pedantic. A suite that only ever sets the disposition directly would
//  stay green against a coordinator that forgot to install the mode observer at all — which is
//  the same shape as Step 9's `chunkCompleted` firing only on the paths somebody remembered.
//
//  ## The comparison that proves the mode does anything
//
//  `theTwoModesDivergeOnIdenticalHardware` runs the *same* device with the *same* faults twice,
//  once in each mode, and requires the results to differ in the documented direction. A pair of
//  suites that each pass in isolation can both be describing a run that ignores the mode
//  entirely; two runs that must diverge cannot.
//

import Testing
import Foundation
@testable import USBDriveTester

// MARK: - Fixtures

/// The same shape `RetentionCycleTests` uses — its `Fixture` is file-private, and a shared one
/// would couple two suites' geometry together for no gain.
private enum Fixture {

    static let seed: UInt64 = 0x4641_494C_4D4F_4445   // "FAILMODE"

    static let ioSizeBytes = 64 * 1024

    /// 8,193 blocks of 512 B = 64 full chunks + a 1-block final chunk (FR-TEST-5).
    static let blocks512: UInt64 = 8_193
    static let chunksPlanned: UInt64 = 65

    /// Blocks per full chunk, at this geometry.
    static let blocksPerChunk: UInt64 = 128

    static let deviceName = "disk9"

    static let grant = DeviceAccessGrant(deviceName: deviceName,
                                         claimHeld: true,
                                         exclusiveOpenHeld: true)

    static func device() throws -> InMemoryBlockDevice {
        let device = InMemoryBlockDevice(logicalBlockSize: 512, blockCount: blocks512)
        try TestPattern.fill(device, seed: seed)
        return device
    }

    static func buffers() throws -> ChunkBuffers {
        try ChunkBuffers(ioSizeBytes: ioSizeBytes)
    }

    /// The FR-TEST-9 verdict a real acquire on a healthy raw device produces.
    static var bypassedAssessment: CacheBypassAssessment {
        CacheBypassAssessment(UncachedIOConfiguration(devicePath: "/dev/rdisk9",
                                                      nodeKind: .character,
                                                      noCacheResult: 0,
                                                      globalNoCacheResult: 0))
    }

    /// A clock slow enough that no read looks implausibly fast to FR-TEST-9's falsifier — the
    /// verdict must not be downgraded for reasons that have nothing to do with these tests.
    static func plausibleClock() -> MonotonicClock {
        var current: UInt64 = 0
        return { defer { current &+= 1_000_000 }; return current }
    }

    /// Runs through **`RunObservers.forRun`** — the same call `RunCoordinator.runCycle` makes,
    /// rather than an observer assembled here.
    ///
    /// That is the point of the helper: driving these tests through a hand-set
    /// `dispositionForFailure` closure, or a hand-built fan-out, would leave the composition
    /// untested and every test below would stay green against a coordinator that never installed
    /// the mode at all.
    static func run(_ device: RawBlockDevice,
                    mode: FailureMode,
                    watching extra: RunObserver? = nil) throws -> RunSummary {
        let engine = RetentionTestEngine(device: device, ioSizeBytes: ioSizeBytes)
        return try engine.run(buffers: buffers(),
                              deviceName: deviceName,
                              cacheBypass: bypassedAssessment,
                              grant: { grant },
                              control: RunControl.uninterrupted,
                              observer: RunObservers.forRun(mode: mode,
                                                            watchedBy: extra.map { [$0] } ?? []),
                              clock: plausibleClock())
    }

    /// First byte of the chunk containing `block`.
    static func chunkStartByte(containing block: UInt64) -> UInt64 {
        (block / blocksPerChunk) * UInt64(ioSizeBytes)
    }
}

// MARK: - FR-FAIL-2: stop on first error

/// > *"In **Stop on first error** mode, the system shall halt immediately on any I/O failure and
/// > report the offending block range."*
///
/// "Halt immediately" is checked two ways in each case below, because they can come apart: the
/// **summary** says the run stopped, and the **device recorder** says nothing was addressed past
/// the offending chunk. A run that recorded a stop and kept issuing I/O would satisfy the first
/// alone — and that is the failure that matters, since the promise of this mode is that a drive
/// already known to be failing stops being written to.
struct StopOnFirstErrorTests {

    @Test func aReadFailureHaltsTheRunAtTheOffendingRange() throws {
        let device = try Fixture.device()
        device.injectReadFault(blocks: 200 ..< 202)     // chunk 1
        device.injectReadFault(blocks: 5_000 ..< 5_002) // chunk 39
        let recorder = RecordingBlockDevice(device)

        let summary = try Fixture.run(recorder, mode: .stopOnFirstError)

        // The whole chunk is the offending range: a read that fails produces no data, so nothing
        // narrower than the request is knowable.
        let expected = BlockRangeFailure(startBlock: 128, blockCount: 128, kind: .readError)
        #expect(summary.outcome == .stoppedOnFailure(expected))
        #expect(summary.failures.ranges == [expected], "FR-FAIL-2: the offending range is reported")
        #expect(summary.chunksProcessed == 2)
        #expect(summary.chunksPlanned == Fixture.chunksPlanned)

        // Nothing past the stopping chunk was touched — the second fault was never reached.
        let stoppedAfter = UInt64(2 * Fixture.ioSizeBytes)
        #expect(recorder.operations.allSatisfy { $0.byteOffset < stoppedAfter })
    }

    @Test func aWriteFailureHaltsTheRunAtTheOffendingRange() throws {
        let device = try Fixture.device()
        device.injectWriteFault(blocks: 300 ..< 301)    // chunk 2
        let recorder = RecordingBlockDevice(device)

        let summary = try Fixture.run(recorder, mode: .stopOnFirstError)

        let expected = BlockRangeFailure(startBlock: 256, blockCount: 128, kind: .writeError)
        #expect(summary.outcome == .stoppedOnFailure(expected))
        #expect(summary.failures.ranges == [expected])
        #expect(summary.chunksProcessed == 3)

        let stoppedAfter = UInt64(3 * Fixture.ioSizeBytes)
        #expect(recorder.operations.allSatisfy { $0.byteOffset < stoppedAfter })
    }

    /// **The row FR-FAIL-2 does not obviously cover, and the reason `disposition(for:)` takes a
    /// kind.** A verify mismatch is not an I/O failure in the ordinary sense — the read
    /// succeeded, the write succeeded, and the drive returned different bytes — so a narrow
    /// reading of "any I/O failure" would let it continue in the mode whose promise is that it
    /// stops. FR-TEST-8 and FR-FAIL-6 are what make it a block-range failure.
    @Test func aVerifyMismatchHaltsTheRunAtTheOffendingRange() throws {
        let device = try Fixture.device()
        device.injectSilentCorruption(blocks: 200 ..< 202)     // chunk 1
        device.injectSilentCorruption(blocks: 5_000 ..< 5_002) // chunk 39
        let recorder = RecordingBlockDevice(device)

        let summary = try Fixture.run(recorder, mode: .stopOnFirstError)

        // Narrowed to the blocks that actually differ — the mismatch scan knows which they are.
        let expected = BlockRangeFailure(startBlock: 200, blockCount: 2, kind: .verifyMismatch)
        #expect(summary.outcome == .stoppedOnFailure(expected))
        #expect(summary.failures.ranges == [expected])
        #expect(summary.chunksProcessed == 2)

        let stoppedAfter = UInt64(2 * Fixture.ioSizeBytes)
        #expect(recorder.operations.allSatisfy { $0.byteOffset < stoppedAfter })
    }

    /// FR-FAIL-2 says *the* offending range, singular. A chunk holding two separate corrupted
    /// runs must report the first and stop, not both.
    @Test func onlyTheFirstRangeInAChunkIsReported() throws {
        let device = try Fixture.device()
        device.injectSilentCorruption(blocks: 10 ..< 12)
        device.injectSilentCorruption(blocks: 40 ..< 42)   // same chunk, not adjacent
        let recorder = RecordingBlockDevice(device)

        let summary = try Fixture.run(recorder, mode: .stopOnFirstError)

        #expect(summary.failures.ranges == [BlockRangeFailure(startBlock: 10, blockCount: 2,
                                                              kind: .verifyMismatch)])
        #expect(summary.chunksProcessed == 1)
    }

    /// A drive that fails on its very first chunk must not be written to at all beyond it. The
    /// boundary case, because "stop after the first" and "stop after none" are one chunk apart.
    @Test func aFailureInTheFirstChunkStopsBeforeTheSecond() throws {
        let device = try Fixture.device()
        device.injectReadFault(blocks: 0 ..< 1)
        let recorder = RecordingBlockDevice(device)

        let summary = try Fixture.run(recorder, mode: .stopOnFirstError)

        #expect(summary.chunksProcessed == 1)
        #expect(recorder.writes.isEmpty, "a run that never got a chunk read must write nothing")
        #expect(recorder.operations.allSatisfy { $0.byteOffset == 0 })
    }

    /// FR-FAIL-5 admits no exception: a run that stopped still reports. The report must not be
    /// empty just because the run did not finish.
    @Test func aHaltedRunStillCarriesItsFailureAndItsCounters() throws {
        let device = try Fixture.device()
        device.injectSilentCorruption(blocks: 200 ..< 202)

        let summary = try Fixture.run(device, mode: .stopOnFirstError)

        #expect(summary.failures.isEmpty == false)
        #expect(summary.failures.failedBlockCount == 2)
        #expect(summary.failures.totalRangeCount == 1)
        #expect(summary.isComplete == false)
        #expect(summary.bytesRead > 0, "statistics must survive an early stop")
        #expect(summary.bytesWritten > 0)
    }
}

// MARK: - FR-FAIL-3: log and continue

/// > *"In **Log and continue** mode, the system shall record each offending block range to a
/// > bad-block list and continue refreshing the remainder of the device."*
///
/// Both halves are checked. "Records each" is the failure list; "**continues refreshing the
/// remainder**" is the stronger claim, and it is checked against the device recorder rather than
/// against a chunk count — a run that walked to the end without writing anything would satisfy a
/// count and fail the requirement, and refreshing is the half of this product that still works
/// when fault detection does not (FR-TEST-9).
struct LogAndContinueTests {

    @Test func everyFailedRangeIsRecordedAndTheRunCompletes() throws {
        let device = try Fixture.device()
        device.injectSilentCorruption(blocks: 200 ..< 202)
        device.injectSilentCorruption(blocks: 3_000 ..< 3_004)
        device.injectSilentCorruption(blocks: 5_000 ..< 5_002)

        let summary = try Fixture.run(device, mode: .logAndContinue)

        #expect(summary.outcome == .completed)
        #expect(summary.chunksProcessed == Fixture.chunksPlanned)
        #expect(summary.failures.ranges == [
            BlockRangeFailure(startBlock: 200, blockCount: 2, kind: .verifyMismatch),
            BlockRangeFailure(startBlock: 3_000, blockCount: 4, kind: .verifyMismatch),
            BlockRangeFailure(startBlock: 5_000, blockCount: 2, kind: .verifyMismatch),
        ])
        #expect(summary.failures.failedBlockCount == 8)
    }

    /// All three kinds in one run (FR-FAIL-6), because a mode that survived one kind and not
    /// another would pass a single-kind suite.
    @Test func allThreeKindsAreRecordedAndTheRunStillCompletes() throws {
        let device = try Fixture.device()
        device.injectReadFault(blocks: 200 ..< 201)          // chunk 1
        device.injectWriteFault(blocks: 400 ..< 401)         // chunk 3
        device.injectSilentCorruption(blocks: 700 ..< 702)   // chunk 5

        let summary = try Fixture.run(device, mode: .logAndContinue)

        #expect(summary.outcome == .completed)
        #expect(summary.chunksProcessed == Fixture.chunksPlanned)
        #expect(summary.failures.ranges.map(\.kind) == [.readError, .writeError, .verifyMismatch])
        #expect(summary.failures.totalRangeCount == 3)
    }

    /// **The half a chunk count cannot prove.** Every chunk whose read succeeded must have been
    /// written back — that is the refresh, and it is what FR-FAIL-3 promises for the remainder of
    /// the device. Only the chunk with the injected read fault is exempt, because a failed read
    /// may never be followed by a write (`LoadedChunk`'s whole reason for existing).
    @Test func theRestOfTheDeviceIsActuallyRefreshed() throws {
        let device = try Fixture.device()
        device.injectReadFault(blocks: 200 ..< 201)          // chunk 1 — never written
        device.injectSilentCorruption(blocks: 5_000 ..< 5_002)
        let recorder = RecordingBlockDevice(device)

        let summary = try Fixture.run(recorder, mode: .logAndContinue)
        #expect(summary.outcome == .completed)

        let unreadableChunkStart = Fixture.chunkStartByte(containing: 200)
        let written = Set(recorder.writes.map(\.byteOffset))
        var expected = Set((0 ..< Fixture.chunksPlanned)
                            .map { $0 * UInt64(Fixture.ioSizeBytes) })
        expected.remove(unreadableChunkStart)

        #expect(written == expected,
                "every chunk but the unreadable one must have been written back")
        #expect(written.contains(unreadableChunkStart) == false,
                "a failed read must never be followed by a write")
    }

    /// The final short chunk (FR-TEST-5) is part of "the remainder of the device", and it is the
    /// one an off-by-one in the continue path would drop.
    @Test func theShortFinalChunkIsStillRefreshedAfterAFailure() throws {
        let device = try Fixture.device()
        device.injectSilentCorruption(blocks: 200 ..< 202)
        let recorder = RecordingBlockDevice(device)

        let summary = try Fixture.run(recorder, mode: .logAndContinue)

        let finalChunkStart = (Fixture.chunksPlanned - 1) * UInt64(Fixture.ioSizeBytes)
        let finalWrite = recorder.writes.first { $0.byteOffset == finalChunkStart }
        #expect(summary.chunksProcessed == Fixture.chunksPlanned)
        #expect(finalWrite?.byteLength == 512, "the last chunk is one 512-byte block")
    }

    /// A drive failing everywhere still completes, and the list still says how much it lost.
    /// This is the marginal-drive case log-and-continue exists for (ADR: "marginal drives still
    /// get fully refreshed and produce a complete bad-block report").
    @Test func aDeviceFailingEveryChunkStillCompletesAndCountsHonestly() throws {
        let device = try Fixture.device()
        device.injectSilentCorruption(blocks: 0 ..< Fixture.blocks512)

        let summary = try Fixture.run(device, mode: .logAndContinue)

        #expect(summary.outcome == .completed)
        #expect(summary.chunksProcessed == Fixture.chunksPlanned)
        #expect(summary.failures.failedBlockCount == Fixture.blocks512,
                "every block is accounted for, coalesced or not")
        // Contiguous and all the same kind, so the whole device coalesces to one range.
        #expect(summary.failures.ranges.count == 1)
        #expect(summary.failures.isTruncated == false)
    }
}

// MARK: - The two modes must actually differ

struct FailureModeDivergenceTests {

    /// **The test that proves the mode is wired to anything at all.** Identical device, identical
    /// faults, two runs. Each of the suites above could pass against a run that ignored the mode;
    /// two runs required to diverge cannot.
    @Test func theTwoModesDivergeOnIdenticalHardware() throws {
        func run(_ mode: FailureMode) throws -> (RunSummary, RecordingBlockDevice) {
            let device = try Fixture.device()
            device.injectSilentCorruption(blocks: 200 ..< 202)
            device.injectSilentCorruption(blocks: 5_000 ..< 5_002)
            let recorder = RecordingBlockDevice(device)
            return (try Fixture.run(recorder, mode: mode), recorder)
        }

        let (stopped, stoppedDevice) = try run(.stopOnFirstError)
        let (continued, continuedDevice) = try run(.logAndContinue)

        #expect(stopped.chunksProcessed < continued.chunksProcessed)
        #expect(stopped.chunksProcessed == 2)
        #expect(continued.chunksProcessed == Fixture.chunksPlanned)

        #expect(stopped.failures.totalRangeCount == 1)
        #expect(continued.failures.totalRangeCount == 2,
                "the second fault is only ever reached by the continuing run")

        #expect(stoppedDevice.writes.count < continuedDevice.writes.count)
        #expect(stopped.outcome != continued.outcome)
    }

    /// On a **healthy** device the two modes must be indistinguishable. A mode that changed a
    /// clean run would be changing the product's ordinary behaviour, not its failure behaviour.
    @Test func theTwoModesAreIndistinguishableOnACleanDevice() throws {
        func run(_ mode: FailureMode) throws -> RunSummary {
            try Fixture.run(try Fixture.device(), mode: mode)
        }

        let stopped = try run(.stopOnFirstError)
        let continued = try run(.logAndContinue)

        #expect(stopped.outcome == .completed)
        #expect(continued.outcome == .completed)
        #expect(stopped.chunksProcessed == continued.chunksProcessed)
        #expect(stopped.bytesWritten == continued.bytesWritten)
        #expect(stopped.failures.isEmpty)
        #expect(continued.failures.isEmpty)
    }
}

// MARK: - Composition (what `RunCoordinator` actually builds)

/// `RunCoordinator` fans out to three observers: a logger, this mode observer, and the metrics
/// accumulator. The logger and the accumulator both answer with the default `.continueRun`,
/// because they only watch — so the safety of the arrangement rests entirely on
/// `ObserverFanOut`'s stop-wins rule, and on the mode observer being in the list at all.
struct FailureModeObserverTests {

    private static let failure = BlockRangeFailure(startBlock: 8, blockCount: 2,
                                                   kind: .verifyMismatch)

    @Test func theObserverAnswersWithItsMode() {
        #expect(FailureModeObserver(mode: .stopOnFirstError)
                    .failureDetected(Self.failure) == .stopRun)
        #expect(FailureModeObserver(mode: .logAndContinue)
                    .failureDetected(Self.failure) == .continueRun)
    }

    /// A passive observer must not be able to talk the run out of stopping — **in either
    /// position**, because a fan-out that short-circuited on the first answer would pass with the
    /// mode observer first and fail with it second.
    @Test func aPassiveObserverCannotOverrideAStop() {
        let passive = RecordingRunObserver()      // answers `.continueRun` by default
        let deciding = FailureModeObserver(mode: .stopOnFirstError)

        #expect(ObserverFanOut([deciding, passive]).failureDetected(Self.failure) == .stopRun)
        #expect(ObserverFanOut([passive, deciding]).failureDetected(Self.failure) == .stopRun)
    }

    /// And every observer is still told, whichever way the decision goes — an observer that
    /// stopped being called once a stop was known would lose the failure it stopped on from the
    /// metrics and from the log.
    @Test func everyObserverIsToldEvenWhenTheRunIsStopping() {
        let watcher = RecordingRunObserver()
        let fanOut = ObserverFanOut([FailureModeObserver(mode: .stopOnFirstError), watcher])

        #expect(fanOut.failureDetected(Self.failure) == .stopRun)
        #expect(watcher.failures == [Self.failure])
    }

    /// The mode observer watches nothing and records nothing — it exists to answer one question.
    /// Anything else it acquired would be state that could disagree with the run's own summary.
    @Test func theObserverKeepsItsModeAndNothingElse() {
        let observer = FailureModeObserver(mode: .stopOnFirstError)
        #expect(observer.mode == .stopOnFirstError)

        // The default `RunObserver` implementations: it neither counts chunks nor holds a
        // summary, so a second run through the same observer answers identically.
        observer.runStarted(RunStart(deviceName: "disk9", startBlock: 0, blockCount: 1,
                                     ioSizeBytes: 512, logicalBlockSize: 512, chunkCount: 1,
                                     cacheBypass: .bypassed))
        #expect(observer.failureDetected(Self.failure) == .stopRun)
        #expect(observer.failureDetected(Self.failure) == .stopRun)
    }
}

// MARK: - The composition itself

/// `RunObservers.forRun` exists because the helper's `RunCoordinator` is **not** in the test
/// target, and the two observers it watches with — the logger and the metrics accumulator — both
/// answer a failure with the neutral `.continueRun`. So the whole of stop-on-first-error rests on
/// the deciding observer being in the list, and an array literal at that call site would put the
/// only thing that matters outside every test in this project.
///
/// These are the tests that make dropping it impossible to do quietly.
struct RunObserverCompositionTests {

    private static let failure = BlockRangeFailure(startBlock: 8, blockCount: 2,
                                                   kind: .verifyMismatch)

    /// The one that would have caught the defect this type exists to prevent: watchers that all
    /// say "carry on" must not produce a run that carries on.
    @Test func theModeSurvivesAListOfPurelyPassiveWatchers() {
        let watchers = [RecordingRunObserver(), RecordingRunObserver(), RecordingRunObserver()]
        let fanOut = RunObservers.forRun(mode: .stopOnFirstError, watchedBy: watchers)

        #expect(fanOut.failureDetected(Self.failure) == .stopRun)
        for watcher in watchers {
            #expect(watcher.failures == [Self.failure], "every watcher is still told")
        }
    }

    /// A watcher that actively asks to stop cannot be *overridden* by log-and-continue either —
    /// stop wins in both directions, which is what lets Step 11 add a stop for reasons that have
    /// nothing to do with the failure mode.
    @Test func aWatcherMayStillForceAStopInLogAndContinue() {
        let insistent = RecordingRunObserver()
        insistent.dispositionForFailure = { _ in .stopRun }

        let fanOut = RunObservers.forRun(mode: .logAndContinue, watchedBy: [insistent])
        #expect(fanOut.failureDetected(Self.failure) == .stopRun)
    }

    @Test func logAndContinueWithPassiveWatchersCarriesOn() {
        let fanOut = RunObservers.forRun(mode: .logAndContinue,
                                         watchedBy: [RecordingRunObserver()])
        #expect(fanOut.failureDetected(Self.failure) == .continueRun)
    }

    /// No watchers at all is still a mode-obeying run — the composition must not depend on
    /// anything being handed to it.
    @Test func theModeIsObeyedWithNoWatchersAtAll() {
        #expect(RunObservers.forRun(mode: .stopOnFirstError, watchedBy: [])
                    .failureDetected(Self.failure) == .stopRun)
        #expect(RunObservers.forRun(mode: .logAndContinue, watchedBy: [])
                    .failureDetected(Self.failure) == .continueRun)
    }

    /// Events other than failures still reach the watchers — the composition adds a decider, it
    /// does not filter what the watchers see.
    @Test func watchersStillReceiveEveryOtherEvent() throws {
        let watcher = RecordingRunObserver()
        let device = try Fixture.device()
        let summary = try Fixture.run(device, mode: .logAndContinue, watching: watcher)

        #expect(watcher.start?.deviceName == Fixture.deviceName)
        #expect(watcher.measurements.count == Int(Fixture.chunksPlanned))
        #expect(watcher.summary?.chunksProcessed == summary.chunksProcessed)
    }
}
