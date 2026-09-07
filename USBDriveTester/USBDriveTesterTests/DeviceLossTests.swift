//
//  DeviceLossTests.swift
//  Step 12, chunk 1 — a drive that leaves the bus is not a drive with two million bad blocks.
//
//  ## The defect these tests are about actually happened
//
//  On 2026-08-06 the 1 TB scratch T5 de-enumerated part-way through `retention-cycle-check.sh`.
//  The helper's descriptor returned `errno 6` — `ENXIO`, *"Device not configured"* — for every
//  subsequent read **including the one at offset 0**, and the run, doing precisely what
//  log-and-continue is built to do with a failing drive, recorded every remaining chunk as a
//  failed range. The drive re-enumerated healthy about two seconds later. Nothing in the product
//  could tell the difference between a dead drive and an absent one.
//
//  ## What is provable here, and what is not
//
//  The *discrimination* is decidable with no hardware: given `ENXIO`, does this code classify it
//  as the device's absence rather than the device's failure, and does a run that meets it report
//  zero bad blocks? Both are checked below, against the in-memory device and against the pure
//  `errno` mapping.
//
//  What no host-only test can show is that a real de-enumerating drive returns `ENXIO` in the
//  first place. That claim has **one observation** behind it — the incident above — which is
//  evidence and not a gate, and it stays on the hardware side of the line until Step 12's gate
//  unplugs a drive on purpose. `FileDescriptorBlockDevice`'s header table carries the same split.
//
//  ## Why the pair at one offset is the centre of this file
//
//  A test that only showed device loss ending a run would pass against an engine that ended a run
//  on *any* read failure — which would be a worse product than the one being fixed, because it
//  would stop testing a drive at its first genuine bad block. So the load-bearing test runs the
//  **same offset on the same fixture twice**: once with a bad block, once with the device gone,
//  and asserts the two produce different outcomes AND different failure counts. Either half alone
//  is satisfiable by a mistake.
//

import Testing
import Foundation
@testable import USBDriveTester

// MARK: - Fixture

/// Deliberately the geometry `RunControlEngineTests` and `RetentionCycleTests` use — 8,193 blocks
/// of 512 B at a 64 KiB I/O size, so 128 blocks per chunk and **65 chunks, the last one block
/// long**. Sharing it means device loss is exercised against the same short-final-chunk case
/// (FR-TEST-5) as everything else, rather than a rounder geometry that would hide it.
private enum LossFixture {

    static let seed: UInt64 = 0x4C_4F_53_53_54_45_53_54
    static let ioSizeBytes = 64 * 1024
    static let blocks: UInt64 = 8_193
    static let blocksPerChunk: UInt64 = 128
    static let chunkCount = 65
    static let deviceName = "disk9"

    /// Bytes in a full chunk — what `bytesRead` moves per healthy chunk.
    static let chunkBytes = UInt64(ioSizeBytes)

    static let grant = DeviceAccessGrant(deviceName: deviceName,
                                         claimHeld: true,
                                         exclusiveOpenHeld: true)

    static func device() throws -> InMemoryBlockDevice {
        let device = InMemoryBlockDevice(logicalBlockSize: 512, blockCount: blocks)
        try TestPattern.fill(device, seed: seed)
        return device
    }

    static var assessment: CacheBypassAssessment {
        CacheBypassAssessment(UncachedIOConfiguration(devicePath: "/dev/rdisk9",
                                                      nodeKind: .character,
                                                      noCacheResult: 0,
                                                      globalNoCacheResult: 0))
    }

    static func startBlock(ofChunk index: Int) -> UInt64 { UInt64(index) * blocksPerChunk }

    /// Run the whole device, log-and-continue, with whatever faults the caller injected.
    static func run(_ device: InMemoryBlockDevice)
        throws -> (summary: RunSummary, observer: RecordingRunObserver) {

        let engine = RetentionTestEngine(device: device, ioSizeBytes: ioSizeBytes)
        let observer = RecordingRunObserver()
        let summary = try engine.run(buffers: ChunkBuffers(ioSizeBytes: ioSizeBytes),
                                     deviceName: deviceName,
                                     cacheBypass: assessment,
                                     grant: { grant },
                                     control: RunControl.uninterrupted,
                                     observer: observer)
        return (summary, observer)
    }
}

// MARK: - The `errno` mapping (pure — no device, no descriptor)

struct DeviceLossErrnoTests {

    /// **`ENXIO` alone.** The table is written out rather than looped over a "loss set", because
    /// the property being pinned is that the set has exactly one member: every other `errno` that
    /// has ever been seen at this boundary must stay a hard failure.
    @Test func enxioIsTheOnlyErrnoThatMeansTheDeviceIsGone() {
        let offset: UInt64 = 4_096
        let length = 512

        for operation in [FileDescriptorBlockDevice.Operation.read, .write] {
            #expect(FileDescriptorBlockDevice.ioError(forErrno: ENXIO, operation: operation,
                                                      atByteOffset: offset, length: length)
                    == .deviceLost(atByteOffset: offset, length: length),
                    "operation=\(operation)")
        }

        let hardFailures: [Int32] = [EIO, EBADF, EINVAL, EPERM, ENOSPC, EACCES, ENODEV, EAGAIN]
        for code in hardFailures {
            #expect(FileDescriptorBlockDevice.ioError(forErrno: code, operation: .read,
                                                      atByteOffset: offset, length: length)
                    == .readError(atByteOffset: offset, length: length),
                    "errno=\(code) must not read as device loss")
            #expect(FileDescriptorBlockDevice.ioError(forErrno: code, operation: .write,
                                                      atByteOffset: offset, length: length)
                    == .writeError(atByteOffset: offset, length: length),
                    "errno=\(code) must not read as device loss")
        }
    }

    /// **`EIO` is the one that must not be folded in**, and the direction of the mistake is the
    /// reason it gets its own test. `EIO` is what a single unreadable block returns, so treating
    /// it as loss would end a run at the first genuine bad block — turning the one thing this tool
    /// exists to find into a reason to stop looking. BUILD-PLAN's Step 12 detailed step 1 said
    /// "`ENXIO`/`EIO`" until 2026-09-05, contradicting its own incident note two paragraphs above
    /// it; this is that decision, pinned.
    @Test func eioStaysABadBlockAndIsNeverDeviceLoss() {
        let error = FileDescriptorBlockDevice.ioError(forErrno: EIO, operation: .read,
                                                      atByteOffset: 0, length: 512)
        #expect(error == .readError(atByteOffset: 0, length: 512))
        if case .deviceLost = error { Issue.record("EIO must never classify as device loss") }
    }

    /// The incident recorded `errno 6`. This pins the number to the constant the code tests, so
    /// the log line in `progress/` and the branch above cannot drift apart.
    @Test func theIncidentsErrnoSixIsEnxio() {
        #expect(ENXIO == 6)
    }

    /// `EBADF` is a closed or invalid descriptor — *this program's* mistake, not the device's
    /// absence — and `FileDescriptorBlockDeviceTests` pins it to a hard failure through a real
    /// syscall. Stated here too, because "we lost track of the descriptor" reported as "the drive
    /// was unplugged" would be a hardware event that did not happen.
    @Test func aBadDescriptorIsOurMistakeAndNotTheDevicesAbsence() {
        #expect(FileDescriptorBlockDevice.ioError(forErrno: EBADF, operation: .read,
                                                  atByteOffset: 0, length: 512)
                == .readError(atByteOffset: 0, length: 512))
    }
}

// MARK: - The in-memory hook

struct InMemoryDeviceLossTests {

    private func device() -> InMemoryBlockDevice {
        InMemoryBlockDevice(logicalBlockSize: 512, blockCount: 64)
    }

    private func read(_ device: InMemoryBlockDevice, at offset: UInt64, bytes: Int = 512) throws {
        var buffer = [UInt8](repeating: 0, count: bytes)
        _ = try buffer.withUnsafeMutableBytes { try device.read(into: $0, atByteOffset: offset) }
    }

    private func write(_ device: InMemoryBlockDevice, at offset: UInt64, bytes: Int = 512) throws {
        let source = [UInt8](repeating: 0xAB, count: bytes)
        _ = try source.withUnsafeBytes { try device.write($0, atByteOffset: offset) }
    }

    /// **Loss is total, not ranged** — the distinction the whole step rests on. No range fault is
    /// injected anywhere here, and yet every offset fails, offset 0 included.
    @Test func aLostDeviceFailsEveryOffsetIncludingZero() throws {
        let device = self.device()
        device.injectDeviceLoss()

        for offset: UInt64 in [0, 512, 4_096, 32_256] {
            #expect(throws: DeviceIOError.deviceLost(atByteOffset: offset, length: 512)) {
                try read(device, at: offset)
            }
            #expect(throws: DeviceIOError.deviceLost(atByteOffset: offset, length: 512)) {
                try write(device, at: offset)
            }
        }
    }

    /// **Ordering fidelity with the real device.** `FileDescriptorBlockDevice` checks alignment
    /// and range before it issues any syscall, so a misaligned request to a dead device is an
    /// addressing fault — *our* bug — and never reaches an `errno`. The fake must agree, or the
    /// engine's `classify` would be exercised against an ordering hardware does not have.
    @Test func aMisalignedRequestToALostDeviceIsStillAnAddressingFault() throws {
        let device = self.device()
        device.injectDeviceLoss()

        #expect(throws: DeviceIOError.misaligned(atByteOffset: 100, length: 512,
                                                 logicalBlockSize: 512)) {
            try read(device, at: 100)
        }
        #expect(throws: DeviceIOError.outOfRange(atByteOffset: 32_768, length: 512,
                                                 deviceByteCount: 32_768)) {
            try read(device, at: 32_768)
        }
    }

    /// A zero-length request never reaches a syscall on the real device, so it cannot see the
    /// device's absence there either. Same here, for the same reason.
    @Test func aZeroLengthRequestDoesNotSeeTheDevicesAbsence() throws {
        let device = self.device()
        device.injectDeviceLoss()

        var empty = [UInt8]()
        let read = try empty.withUnsafeMutableBytes { try device.read(into: $0, atByteOffset: 0) }
        #expect(read == 0)
    }

    /// `afterCalls` counts down across reads *and* writes, and once it fires the device stays
    /// lost — there is no un-inject, because a de-enumerated device does not come back on the
    /// same descriptor.
    @Test func lossCanBeDeferredAndIsPermanentOnceItFires() throws {
        let device = self.device()
        device.injectDeviceLoss(afterCalls: 3)

        try read(device, at: 0)          // 1
        try write(device, at: 512)       // 2
        try read(device, at: 1_024)      // 3

        for _ in 0 ..< 3 {
            #expect(throws: DeviceIOError.deviceLost(atByteOffset: 0, length: 512)) {
                try read(device, at: 0)
            }
        }
    }

    /// Nothing changes for a device nobody lost. Without this, every assertion above is
    /// satisfiable by a fake that throws `deviceLost` unconditionally.
    @Test func aDeviceWithNoInjectedLossIsUnaffected() throws {
        let device = self.device()
        try read(device, at: 0)
        try write(device, at: 512)
    }
}

// MARK: - The engine

struct DeviceLossRunTests {

    /// **The load-bearing test.** The same offset on the same fixture, twice: once with a bad
    /// block, once with the device gone. Two things must differ — the outcome *and* the number of
    /// ranges recorded against the drive — because an engine that ended the run on any read
    /// failure would pass the first check and fail the drive on the second.
    @Test func atOneOffsetABadBlockIsRecordedAndALostDeviceIsNot() throws {
        let faultBlocks = LossFixture.startBlock(ofChunk: 0) ..< LossFixture.blocksPerChunk

        let badBlock = try LossFixture.device()
        badBlock.injectReadFault(blocks: faultBlocks)
        let (bad, badObserver) = try LossFixture.run(badBlock)

        let lost = try LossFixture.device()
        lost.injectDeviceLoss()
        let (gone, goneObserver) = try LossFixture.run(lost)

        // The drive with a bad block: recorded, and the run carries on over the whole device
        // (FR-FAIL-3). This half is the regression guard.
        #expect(bad.outcome == .completed)
        #expect(bad.chunksProcessed == UInt64(LossFixture.chunkCount))
        #expect(bad.failures.totalRangeCount == 1)
        #expect(badObserver.failures.count == 1)

        // The drive that is not there: the run ends, and **nothing is recorded against it**.
        #expect(gone.outcome == .deviceLost(atBlock: 0, phase: .reading))
        #expect(gone.chunksProcessed == 1)
        #expect(gone.failures.totalRangeCount == 0)
        #expect(gone.failures.failedBlockCount == 0)
        #expect(goneObserver.failures.isEmpty,
                "the observer must not be told a drive failed when the drive is absent")

        #expect(bad.outcome != gone.outcome)
    }

    /// **The 2026-08-06 incident, in the shape it actually took**: `ENXIO` from offset 0 onward.
    /// Before Step 12 this produced a failed range for every remaining chunk — on the 1 TB drive,
    /// roughly two million blocks' worth. The assertion that matters is the *absence* of those.
    @Test func aDriveThatLeavesTheBusIsNotADriveWithMillionsOfBadBlocks() throws {
        let device = try LossFixture.device()
        device.injectDeviceLoss()

        let (summary, observer) = try LossFixture.run(device)

        #expect(summary.failures.failedBlockCount == 0)
        #expect(summary.failures.totalRangeCount == 0)
        #expect(!summary.failures.isTruncated)
        #expect(summary.chunksProcessed < UInt64(LossFixture.chunkCount),
                "the run must stop, not walk the rest of an absent device")
        #expect(observer.measurements.count == 1)
        #expect(!summary.isComplete)
    }

    /// **Failures found before the device left are real readings of a real drive** and survive.
    /// The run below finds a bad block in chunk 1, keeps going, and loses the device in chunk 3.
    ///
    /// The intermediate assertions are not decoration: the call arithmetic behind `afterCalls: 7`
    /// — three calls for chunk 0, one for chunk 1's failed read, three for chunk 2 — is exactly
    /// the kind of thing that can silently drift to a different chunk and still "pass", so the
    /// chunk count and the range's own start block are checked rather than only the totals.
    @Test func failuresFoundBeforeTheDeviceLeftAreKeptAndNothingIsAddedAfter() throws {
        let device = try LossFixture.device()
        device.injectReadFault(blocks: LossFixture.startBlock(ofChunk: 1)
                                       ..< LossFixture.startBlock(ofChunk: 2))
        device.injectDeviceLoss(afterCalls: 7)

        let (summary, observer) = try LossFixture.run(device)

        #expect(observer.measurements.count == 4, "chunks 0, 1, 2 and the lost 3")
        #expect(summary.chunksProcessed == 4)
        #expect(summary.outcome == .deviceLost(atBlock: LossFixture.startBlock(ofChunk: 3),
                                               phase: .reading))

        let ranges = summary.failures.ranges
        #expect(ranges.count == 1, "one bad block found before the loss, and nothing after it")
        #expect(ranges.first?.startBlock == LossFixture.startBlock(ofChunk: 1))
        #expect(ranges.first?.kind == .readError)
        #expect(summary.failures.failedBlockCount == Int(LossFixture.blocksPerChunk))
    }

    /// Which phase the device left in, and the bytes that moved agreeing with the claim. The
    /// phase is carried because nothing else in `RunSummary` records it, and the three are not
    /// equally bad for the data: `writingBack` is the only one where this run held the chunk's
    /// only copy of the original and had not finished putting it back.
    @Test func theOutcomeNamesThePhaseTheDeviceLeftIn() throws {
        let cases: [(afterCalls: Int, phase: DeviceLossPhase,
                     read: UInt64, written: UInt64, verified: UInt64)] = [
            (0, .reading,     0,                       0,                       0),
            (1, .writingBack, LossFixture.chunkBytes,  0,                       0),
            (2, .verifying,   LossFixture.chunkBytes,  LossFixture.chunkBytes,  0),
        ]

        for expected in cases {
            let device = try LossFixture.device()
            device.injectDeviceLoss(afterCalls: expected.afterCalls)
            let (summary, observer) = try LossFixture.run(device)

            #expect(summary.outcome == .deviceLost(atBlock: 0, phase: expected.phase),
                    "afterCalls=\(expected.afterCalls)")
            #expect(summary.bytesRead == expected.read, "afterCalls=\(expected.afterCalls)")
            #expect(summary.bytesWritten == expected.written, "afterCalls=\(expected.afterCalls)")
            #expect(summary.bytesVerified == expected.verified, "afterCalls=\(expected.afterCalls)")
            #expect(summary.failures.totalRangeCount == 0, "afterCalls=\(expected.afterCalls)")

            // The once-per-chunk measurement property, on the path Step 12 added. A new way out
            // of the loop that forgot to measure would stall a metrics consumer's progress.
            #expect(observer.measurements.count == 1, "afterCalls=\(expected.afterCalls)")
            #expect(summary.chunksProcessed == 1, "afterCalls=\(expected.afterCalls)")
        }
    }

    /// **FR-FAIL-7: a lost device is not a resume point.** The value that would let somebody
    /// resume across it does not exist rather than existing and being ignored — and the drive
    /// that comes back may not even be the drive that left.
    @Test func aLostDeviceIsNotAResumePoint() throws {
        let device = try LossFixture.device()
        device.injectDeviceLoss(afterCalls: 3)

        let (summary, _) = try LossFixture.run(device)

        #expect(summary.outcome.resumeBlock == nil)
        #expect(!summary.isComplete)
    }

    /// A run that never loses its device is untouched by any of this. Without it, every assertion
    /// above is satisfiable by an engine that reports device loss unconditionally.
    @Test func anUnaffectedRunStillCompletesEveryChunkAndFindsNothing() throws {
        let (summary, observer) = try LossFixture.run(try LossFixture.device())

        #expect(summary.outcome == .completed)
        #expect(summary.chunksProcessed == UInt64(LossFixture.chunkCount))
        #expect(observer.measurements.count == LossFixture.chunkCount)
        #expect(summary.failures.totalRangeCount == 0)
    }
}

// MARK: - What is *not* device loss

/// **Found by Step 12's mutation round, not by design.** Moving `.shortTransfer` out of the
/// block-failure arm of `RetentionTestEngine.classify` and into `.deviceLost` passed all 1,288
/// tests. The engine's treatment of a short transfer was unpinned in either direction.
///
/// The reason it was unpinned is worth keeping, because it is a shape that will recur: nothing
/// could *drive* a short transfer through the engine. `FileDescriptorBlockDeviceTests` pins that
/// running off the end of a backing store **produces** a `.shortTransfer`, and that is a fact
/// about the descriptor; `InMemoryBlockDevice` — the only device the engine tests run against —
/// had no hook that could produce one, because the case was reserved for the real device in Step
/// 2 and never revisited. **The gap was in the fake, not in the engine**, which is why the fix is
/// two lines of hook and this file.
///
/// The classification itself is `RetentionTestEngine.classify`'s stated reading: the transfer was
/// legal and it did not complete, so it is the drive's failure. What is still open — and stays
/// open here, because no host-only test can close it — is whether a *real* de-enumerating drive
/// produces a short read before it produces `ENXIO`. That is Step 12's hardware gate, and the
/// `- Note:` on `classify` says so. These tests pin the decision, not the physics.
struct ShortTransferIsNotDeviceLossTests {

    /// **The load-bearing test**, in the same shape as
    /// `atOneOffsetABadBlockIsRecordedAndALostDeviceIsNot`: the same offset on the same fixture,
    /// three ways. A bad block and a short read must agree with each other, and both must differ
    /// from an absent device — in the outcome *and* in what is recorded against the drive.
    ///
    /// Pairing it with the bad block rather than only asserting `.completed` is what makes it a
    /// test of the *classification* rather than of the engine's willingness to continue.
    @Test func atOneOffsetAShortReadIsRecordedTheWayABadBlockIsAndALostDeviceIsNot() throws {
        let faultBlocks = LossFixture.startBlock(ofChunk: 0) ..< LossFixture.blocksPerChunk

        let badBlock = try LossFixture.device()
        badBlock.injectReadFault(blocks: faultBlocks)
        let (bad, _) = try LossFixture.run(badBlock)

        let short = try LossFixture.device()
        short.injectShortRead(blocks: faultBlocks, transferring: 1_024)
        let (cut, cutObserver) = try LossFixture.run(short)

        let lost = try LossFixture.device()
        lost.injectDeviceLoss()
        let (gone, _) = try LossFixture.run(lost)

        // A short read reads exactly like a bad block: recorded once, run carries on (FR-FAIL-3).
        #expect(cut.outcome == bad.outcome)
        #expect(cut.outcome == .completed)
        #expect(cut.chunksProcessed == UInt64(LossFixture.chunkCount))
        #expect(cut.failures.totalRangeCount == bad.failures.totalRangeCount)
        #expect(cut.failures.totalRangeCount == 1)
        #expect(cutObserver.failures.count == 1)

        // And nothing like an absent device.
        #expect(cut.outcome != gone.outcome)
        #expect(cut.failures.totalRangeCount != gone.failures.totalRangeCount)
        if case .deviceLost = cut.outcome {
            Issue.record("a short transfer must never end a run as device loss")
        }
    }

    /// The direction survives the classification. `classify` takes `operation:` **only** for
    /// `shortTransfer`, which is neutral about direction — so if that parameter were ignored, or
    /// threaded from the wrong call site, every short transfer would be recorded as a read
    /// failure and this is the one test that would notice.
    @Test func aShortWriteBackIsRecordedAsAWriteFailureAndNotAReadOne() throws {
        let faultBlocks = LossFixture.startBlock(ofChunk: 2) ..< LossFixture.startBlock(ofChunk: 3)

        let device = try LossFixture.device()
        device.injectShortWrite(blocks: faultBlocks, transferring: 1_024)

        let (summary, _) = try LossFixture.run(device)

        #expect(summary.outcome == .completed)
        #expect(summary.chunksProcessed == UInt64(LossFixture.chunkCount))

        let ranges = summary.failures.ranges
        #expect(ranges.count == 1)
        #expect(ranges.first?.kind == .writeError)
        #expect(ranges.first?.startBlock == LossFixture.startBlock(ofChunk: 2))
    }

    /// A short read that is genuinely followed by the device going — the sequence
    /// `classify`'s `- Note:` says is plausible on real hardware. One spurious range and then the
    /// run ends, which is the behaviour that note describes and accepts: **one** bad range, not
    /// two million, and the loss still ends the run.
    ///
    /// This is what makes the open question a bounded one. If the hardware gate shows a real
    /// drive does this, the cost is already known and already pinned here.
    @Test func aShortReadFollowedByTheDeviceLeavingCostsOneRangeAndStillEndsTheRun() throws {
        let device = try LossFixture.device()
        device.injectShortRead(blocks: LossFixture.startBlock(ofChunk: 0)
                                       ..< LossFixture.blocksPerChunk,
                               transferring: 1_024)
        // Chunk 0's read is the only call before the loss: it fails short, is recorded, and the
        // run moves to chunk 1, whose read finds the device gone.
        device.injectDeviceLoss(afterCalls: 1)

        let (summary, _) = try LossFixture.run(device)

        #expect(summary.outcome == .deviceLost(atBlock: LossFixture.startBlock(ofChunk: 1),
                                               phase: .reading))
        #expect(summary.failures.totalRangeCount == 1, "the short read, and nothing after it")
        #expect(summary.failures.ranges.first?.startBlock == 0)
        #expect(!summary.isComplete)
    }

    /// The pure classification, stated without an engine run, so a future reader can see the
    /// decision rather than infer it from a summary. `classify` is private, so this asserts the
    /// same thing through the smallest run that reaches it — and pins that the short transfer is
    /// recorded at all, which an engine that swallowed it would not do.
    @Test func aShortTransferIsRecordedAgainstTheDriveRatherThanSwallowed() throws {
        let device = try LossFixture.device()
        device.injectShortRead(blocks: LossFixture.startBlock(ofChunk: 4)
                                       ..< LossFixture.startBlock(ofChunk: 5),
                               transferring: 0)

        let (summary, observer) = try LossFixture.run(device)

        #expect(summary.failures.failedBlockCount == Int(LossFixture.blocksPerChunk))
        #expect(observer.failures.count == 1,
                "the observer is told, the way it is told about any failing range")
        #expect(summary.outcome == .completed)
    }
}

// MARK: - What the outcome says

struct DeviceLossOutcomeTests {

    /// The sentence a person reads. It has to name the device rather than the drive's condition:
    /// at v14 this `description` is the **only** thing that crosses the wire saying what happened,
    /// because the fifth `RunOutcomeCode` does not exist until chunk 3 and the helper sends
    /// `unrecognised` with this string as the message.
    @Test func theDescriptionSaysTheDeviceWasLostAndWhichPhase() {
        let outcome = RunOutcome.deviceLost(atBlock: 4_096, phase: .writingBack)

        #expect(outcome.description.contains("device was lost"))
        #expect(outcome.description.contains("4096"))
        #expect(outcome.description.contains("writing the original back"))
    }

    /// It must not read as a verdict on the drive. A message saying the drive failed is the
    /// untruth the whole step exists to remove, and the message is what a user sees at v14.
    @Test func theDescriptionDoesNotAccuseTheDrive() {
        for phase in [DeviceLossPhase.reading, .writingBack, .verifying] {
            let text = RunOutcome.deviceLost(atBlock: 0, phase: phase).description
            #expect(!text.contains("bad block"), "phase=\(phase)")
            #expect(!text.contains("failure"), "phase=\(phase)")
            #expect(!text.contains("failed"), "phase=\(phase)")
        }
    }

    /// Every phase says something, and they say different things — a `description` that collapsed
    /// to one string would satisfy the test above while losing the distinction it exists for.
    @Test func eachPhaseDescribesItselfDistinctly() {
        let descriptions = [DeviceLossPhase.reading, .writingBack, .verifying].map(\.description)
        #expect(Set(descriptions).count == 3)
        for description in descriptions { #expect(!description.isEmpty) }
    }

    /// The five outcomes are five, and each names itself. `Equatable` over associated values is
    /// what the engine tests compare on, so a case that equalled another would quietly weaken
    /// every assertion in this file.
    @Test func theFiveOutcomesAreDistinct() {
        let outcomes: [RunOutcome] = [
            .completed,
            .stoppedOnFailure(BlockRangeFailure(startBlock: 0, blockCount: 1, kind: .readError)),
            .pausedByUser(atBlock: 0),
            .stoppedByUser(atBlock: 0),
            .deviceLost(atBlock: 0, phase: .reading),
        ]

        for (index, outcome) in outcomes.enumerated() {
            for (otherIndex, other) in outcomes.enumerated() where otherIndex != index {
                #expect(outcome != other, "\(outcome) == \(other)")
            }
        }
        #expect(Set(outcomes.map(\.description)).count == outcomes.count)
    }
}
