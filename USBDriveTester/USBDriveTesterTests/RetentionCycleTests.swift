//
//  RetentionCycleTests.swift
//  Step 8's simulation proof — the four gate items, and the cases that make them mean something.
//
//  BUILD-PLAN Step 8's gate is ordered simulation-first on purpose: **nothing here has ever
//  touched real media, and the `disk4` run is not attempted until all of it passes.** These
//  tests are the entire reason it is safe to write the first byte.
//
//  ## What is proven where
//
//  | Gate item | Tests |
//  |---|---|
//  | 1 — non-destructive, bit-for-bit (NFR-REL-1) | ``NonDestructivenessTests`` |
//  | 2 — verify mismatch flags exactly that range (NFR-REL-8) | ``VerifyMismatchTests`` |
//  | 3 — hard errors classified correctly (FR-FAIL-6) | ``HardErrorTests`` |
//  | 4 — one chunk in flight (NFR-REL-4) | ``OneChunkInFlightTests`` + `ChunkCycleAuditTests` |
//  | added — a failed read leaves the device untouched | ``HardErrorTests`` |
//
//  ## The in-memory device is legitimately "cached", and that is a feature
//
//  `CacheBypassAssessment` flags any read faster than the transport could carry — 8 GB/s for
//  the fallback ceiling. An `InMemoryBlockDevice` read is a `memcpy`, measured at 71.3 GB/s on
//  this machine, so a run against it **is** answered from RAM and the falsifier says so. That
//  is not a defect to work around: ``theInMemoryDeviceIsItselfFlaggedAsCached`` turns it into
//  the strongest evidence available that FR-TEST-9's falsifier works, because nothing about it
//  is rigged — no fake clock, no constructed rate, just a device that really does answer from
//  memory being correctly identified as one.
//
//  Tests that need the verdict to *stay* `bypassed` therefore supply a slow clock, which is
//  what the injected `MonotonicClock` is for.
//
//  ## Sizes
//
//  Devices are ~4 MB with a 64 KiB I/O size, giving **65 chunks** — 64 full and a final chunk
//  of exactly one block. Enough chunks for ordering, coalescing and bounded-memory claims to
//  mean something; small enough that a whole-device snapshot is cheap. The one-block final
//  chunk is FR-TEST-5 in every single test here, not in a special case at the end.
//

import Testing
import Foundation
@testable import USBDriveTester

// MARK: - Fixtures

private enum Fixture {

    /// Fixed so a failing run can be reproduced exactly. `SystemRandomNumberGenerator` cannot
    /// be seeded, which is why `SplitMix64` exists.
    static let seed: UInt64 = 0x5152_4D41_5354_4552

    static let ioSizeBytes = 64 * 1024

    /// 8,193 blocks of 512 B = 64 full chunks + 1 block.
    static let blocks512: UInt64 = 8_193

    /// 1,025 blocks of 4,096 B = 64 full chunks + 1 block (NFR-COMPAT-5's other geometry).
    static let blocks4096: UInt64 = 1_025

    static let deviceName = "disk9"

    /// A complete grant on ``deviceName`` — what a successful acquire produces.
    static let grant = DeviceAccessGrant(deviceName: deviceName,
                                         claimHeld: true,
                                         exclusiveOpenHeld: true)

    /// A device filled with position-dependent data, ready to run.
    static func device(blockSize: Int = 512, blocks: UInt64 = blocks512) throws -> InMemoryBlockDevice {
        let device = InMemoryBlockDevice(logicalBlockSize: blockSize, blockCount: blocks)
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

    /// The verdict when the wrong node was opened — `/dev/diskN` rather than `/dev/rdiskN`.
    static var blockNodeAssessment: CacheBypassAssessment {
        CacheBypassAssessment(UncachedIOConfiguration(devicePath: "/dev/disk9",
                                                      nodeKind: .block,
                                                      noCacheResult: 0,
                                                      globalNoCacheResult: 0))
    }
}

/// A clock that advances by a fixed step on every reading.
///
/// The engine reads it twice per phase, so one phase measures exactly `step` nanoseconds.
/// At the 64 KiB I/O size, a 1 ms step is 65.5 MB/s — comfortably below every ceiling — and a
/// zero step is "no measurable time", which the falsifier treats as infinitely fast.
private final class SteppingClock {

    private var current: UInt64 = 0
    private let step: UInt64

    init(nanosecondsPerReading step: UInt64) { self.step = step }

    func now() -> UInt64 {
        defer { current &+= step }
        return current
    }

    /// A rate no transport could deliver: every phase takes zero time.
    static var immeasurablyFast: SteppingClock { SteppingClock(nanosecondsPerReading: 0) }

    /// 65.5 MB/s at a 64 KiB I/O size — plausible for any USB device.
    static var plausible: SteppingClock { SteppingClock(nanosecondsPerReading: 1_000_000) }
}

/// Writes one block later than it was asked to, and reads honestly.
///
/// Exists to prove the non-destructiveness assertion **can fail** — see
/// ``NonDestructivenessTests/aMisdirectedWriteIsDetectedByTheSameAssertion``. Without it, a
/// green bit-for-bit comparison is indistinguishable from a comparison that cannot fail, which
/// is the exact defect this project keeps finding.
private final class MisdirectingBlockDevice: RawBlockDevice {

    private let underlying: RawBlockDevice

    init(_ underlying: RawBlockDevice) { self.underlying = underlying }

    var logicalBlockSize: Int { underlying.logicalBlockSize }
    var blockCount: UInt64 { underlying.blockCount }

    @discardableResult
    func read(into buffer: UnsafeMutableRawBufferPointer, atByteOffset offset: UInt64) throws -> Int {
        try underlying.read(into: buffer, atByteOffset: offset)
    }

    @discardableResult
    func write(_ buffer: UnsafeRawBufferPointer, atByteOffset offset: UInt64) throws -> Int {
        let misdirected = offset &+ UInt64(logicalBlockSize)
        // Silently succeed rather than run off the end, so the damage is a wrong-place write
        // and not an error the engine would report.
        guard misdirected + UInt64(buffer.count) <= byteCount else { return buffer.count }
        return try underlying.write(buffer, atByteOffset: misdirected)
    }
}

// MARK: - Gate item 1: non-destructiveness (NFR-REL-1)

struct NonDestructivenessTests {

    @Test func aWholeDeviceRunLeavesTheBackingStoreBitForBitIdentical512() throws {
        let device = try Fixture.device()
        let before = device.snapshot()

        let engine = RetentionTestEngine(device: device, ioSizeBytes: Fixture.ioSizeBytes)
        let summary = try engine.run(buffers: Fixture.buffers(),
                                     deviceName: Fixture.deviceName,
                                     cacheBypass: Fixture.bypassedAssessment,
                                     grant: { Fixture.grant },
                                     control: RunControl.uninterrupted,
                                     clock: SteppingClock.plausible.now)

        let after = device.snapshot()
        #expect(firstDifference(before, after) == nil)

        #expect(summary.outcome == .completed)
        #expect(summary.failures.isEmpty)
        #expect(summary.chunksProcessed == summary.chunksPlanned)
        #expect(summary.chunksPlanned == 65)
        #expect(summary.bytesRead == device.byteCount)
        #expect(summary.bytesWritten == device.byteCount)
        #expect(summary.bytesVerified == device.byteCount)
    }

    @Test func aWholeDeviceRunLeavesTheBackingStoreBitForBitIdentical4096() throws {
        let device = try Fixture.device(blockSize: 4096, blocks: Fixture.blocks4096)
        let before = device.snapshot()

        let engine = RetentionTestEngine(device: device, ioSizeBytes: Fixture.ioSizeBytes)
        let summary = try engine.run(buffers: Fixture.buffers(),
                                     deviceName: Fixture.deviceName,
                                     cacheBypass: Fixture.bypassedAssessment,
                                     grant: { Fixture.grant },
                                     control: RunControl.uninterrupted,
                                     clock: SteppingClock.plausible.now)

        #expect(firstDifference(before, device.snapshot()) == nil)
        #expect(summary.outcome == .completed)
        #expect(summary.failures.isEmpty)
        #expect(summary.chunksPlanned == 65)
    }

    /// The test data has to be able to *reveal* a wrong-place write, or the comparison above
    /// proves nothing. Every block carries its own index, so this checks the property directly
    /// rather than trusting that a PRNG produced distinct blocks.
    @Test func everyBlockHoldsItsOwnPatternAndNoTwoBlocksAreAlike() throws {
        let device = try Fixture.device()
        let store = device.snapshot()

        for block in [UInt64(0), 1, 127, 128, 4_096, Fixture.blocks512 - 1] {
            let start = Int(block) * 512
            let expected = TestPattern.block(block, seed: Fixture.seed, blockSize: 512)
            #expect(Array(store[start ..< start + 512]) == expected,
                    "block \(block) does not hold its own pattern")
        }

        let first = Array(store[0 ..< 512])
        let second = Array(store[512 ..< 1024])
        #expect(first != second)
    }

    /// The canary. A device that writes one block off must make the bit-for-bit assertion
    /// **fail** — otherwise the assertion above is not a check.
    @Test func aMisdirectedWriteIsDetectedByTheSameAssertion() throws {
        let backing = try Fixture.device()
        let before = backing.snapshot()

        let engine = RetentionTestEngine(device: MisdirectingBlockDevice(backing),
                                         ioSizeBytes: Fixture.ioSizeBytes)
        _ = try engine.run(buffers: Fixture.buffers(),
                           deviceName: Fixture.deviceName,
                           cacheBypass: Fixture.bypassedAssessment,
                           grant: { Fixture.grant },
                           control: RunControl.uninterrupted,
                           clock: SteppingClock.plausible.now)

        #expect(firstDifference(before, backing.snapshot()) != nil,
                "a write landing one block away was not detected — the comparison is vacuous")
    }

    @Test func anEmptyRangeCompletesWithoutTouchingTheDevice() throws {
        let device = try Fixture.device()
        let recorder = RecordingBlockDevice(device)

        let engine = RetentionTestEngine(device: recorder, ioSizeBytes: Fixture.ioSizeBytes)
        let summary = try engine.run(buffers: Fixture.buffers(),
                                     deviceName: Fixture.deviceName,
                                     blockRange: 100 ..< 100,
                                     cacheBypass: Fixture.bypassedAssessment,
                                     grant: { Fixture.grant },
                                     control: RunControl.uninterrupted,
                                     clock: SteppingClock.plausible.now)

        #expect(summary.outcome == .completed)
        #expect(summary.chunksPlanned == 0)
        #expect(recorder.operations.isEmpty)
    }
}

// MARK: - Gate item 2: verify-mismatch detection (NFR-REL-8, FR-TEST-8)

struct VerifyMismatchTests {

    private func run(corrupting ranges: [Range<UInt64>],
                     observer: RecordingRunObserver? = nil) throws -> (RunSummary, InMemoryBlockDevice) {
        let device = try Fixture.device()
        for range in ranges { device.injectSilentCorruption(blocks: range) }

        let engine = RetentionTestEngine(device: device, ioSizeBytes: Fixture.ioSizeBytes)
        let summary = try engine.run(buffers: Fixture.buffers(),
                                     deviceName: Fixture.deviceName,
                                     cacheBypass: Fixture.bypassedAssessment,
                                     grant: { Fixture.grant },
                                     control: RunControl.uninterrupted,
                                     observer: observer,
                                     clock: SteppingClock.plausible.now)
        return (summary, device)
    }

    /// The gate's wording is "flags exactly that range **and no other**". A chunk is 128
    /// blocks here, so a chunk-granular report would flag 128 blocks for a 4-block fault.
    @Test func injectedCorruptionFlagsExactlyTheCorruptedBlocksAndNoOthers() throws {
        let (summary, _) = try run(corrupting: [100 ..< 104])

        #expect(summary.failures.ranges == [BlockRangeFailure(startBlock: 100,
                                                              blockCount: 4,
                                                              kind: .verifyMismatch)])
        #expect(summary.failures.failedBlockCount == 4)
        #expect(summary.failures.isTruncated == false)
        #expect(summary.outcome == .completed)     // FR-FAIL-3: the rest is still refreshed
        #expect(summary.chunksProcessed == 65)
    }

    /// NFR-REL-8 literally: one flipped bit, in one block. `injectSilentCorruption` flips the
    /// low bit of the first byte of each block it covers.
    @Test func aSingleBitDifferenceInOneBlockIsDetected() throws {
        let (summary, _) = try run(corrupting: [4_000 ..< 4_001])

        #expect(summary.failures.ranges == [BlockRangeFailure(startBlock: 4_000,
                                                              blockCount: 1,
                                                              kind: .verifyMismatch)])
    }

    /// A fault straddling a chunk boundary is reported by two chunks and must arrive as one
    /// range — the coalescing that keeps the failure list bounded (NFR-PERF-2).
    @Test func corruptionSpanningAChunkBoundaryIsCoalescedIntoOneRange() throws {
        // A chunk is 128 blocks, so blocks 126–129 straddle the chunk 0 / chunk 1 boundary.
        let (summary, _) = try run(corrupting: [126 ..< 130])

        #expect(summary.failures.ranges == [BlockRangeFailure(startBlock: 126,
                                                              blockCount: 4,
                                                              kind: .verifyMismatch)])
        #expect(summary.failures.totalRangeCount == 1)
    }

    @Test func separateCorruptedRangesStaySeparate() throws {
        let (summary, _) = try run(corrupting: [10 ..< 12, 5_000 ..< 5_003])

        #expect(summary.failures.ranges == [
            BlockRangeFailure(startBlock: 10, blockCount: 2, kind: .verifyMismatch),
            BlockRangeFailure(startBlock: 5_000, blockCount: 3, kind: .verifyMismatch),
        ])
        #expect(summary.failures.failedBlockCount == 5)
    }

    @Test func theObserverIsToldAboutEveryMismatch() throws {
        let observer = RecordingRunObserver()
        _ = try run(corrupting: [10 ..< 12, 5_000 ..< 5_003], observer: observer)

        #expect(observer.failures.count == 2)
        #expect(observer.failures.allSatisfy { $0.kind == .verifyMismatch })
        #expect(observer.start?.deviceName == Fixture.deviceName)
        #expect(observer.summary?.failures.failedBlockCount == 5)
    }

    /// The corrupted blocks really were changed on the device — so the mismatch is a genuine
    /// difference in the store, not an artefact of the comparison.
    @Test func theCorruptedBlocksDifferOnTheDeviceAfterwards() throws {
        let (_, device) = try run(corrupting: [100 ..< 104])
        let store = device.snapshot()

        for block in UInt64(100) ..< 104 {
            let start = Int(block) * 512
            let expected = TestPattern.block(block, seed: Fixture.seed, blockSize: 512)
            #expect(Array(store[start ..< start + 512]) != expected)
        }
        // ...and nothing either side of it was disturbed.
        for block in [UInt64(99), 104] {
            let start = Int(block) * 512
            let expected = TestPattern.block(block, seed: Fixture.seed, blockSize: 512)
            #expect(Array(store[start ..< start + 512]) == expected)
        }
    }
}

// MARK: - Gate item 3: hard-error classification (FR-FAIL-6)

struct HardErrorTests {

    @Test func anInjectedReadFaultIsClassifiedAsAReadError() throws {
        let device = try Fixture.device()
        device.injectReadFault(blocks: 128 ..< 256)          // exactly chunk 1

        let engine = RetentionTestEngine(device: device, ioSizeBytes: Fixture.ioSizeBytes)
        let summary = try engine.run(buffers: Fixture.buffers(),
                                     deviceName: Fixture.deviceName,
                                     cacheBypass: Fixture.bypassedAssessment,
                                     grant: { Fixture.grant },
                                     control: RunControl.uninterrupted,
                                     clock: SteppingClock.plausible.now)

        #expect(summary.failures.ranges == [BlockRangeFailure(startBlock: 128,
                                                              blockCount: 128,
                                                              kind: .readError)])
        #expect(summary.outcome == .completed)
        #expect(summary.chunksProcessed == 65)
    }

    @Test func anInjectedWriteFaultIsClassifiedAsAWriteError() throws {
        let device = try Fixture.device()
        device.injectWriteFault(blocks: 256 ..< 384)          // exactly chunk 2

        let engine = RetentionTestEngine(device: device, ioSizeBytes: Fixture.ioSizeBytes)
        let summary = try engine.run(buffers: Fixture.buffers(),
                                     deviceName: Fixture.deviceName,
                                     cacheBypass: Fixture.bypassedAssessment,
                                     grant: { Fixture.grant },
                                     control: RunControl.uninterrupted,
                                     clock: SteppingClock.plausible.now)

        #expect(summary.failures.ranges == [BlockRangeFailure(startBlock: 256,
                                                              blockCount: 128,
                                                              kind: .writeError)])
        #expect(summary.outcome == .completed)
    }

    /// **The sixth hazard (2026-08-02).** The buffers are reused, so a failed read must not be
    /// followed by a write — otherwise the previous chunk's data lands at this chunk's offset.
    /// Asserted three ways, because "the device is unchanged" is also true of a clean run and
    /// would pass whether or not the guard exists.
    @Test func aFailedReadIsNeverFollowedByAWrite() throws {
        let device = try Fixture.device()
        device.injectReadFault(blocks: 128 ..< 256)
        let before = device.snapshot()

        let recorder = RecordingBlockDevice(device)
        let engine = RetentionTestEngine(device: recorder, ioSizeBytes: Fixture.ioSizeBytes)
        let summary = try engine.run(buffers: Fixture.buffers(),
                                     deviceName: Fixture.deviceName,
                                     cacheBypass: Fixture.bypassedAssessment,
                                     grant: { Fixture.grant },
                                     control: RunControl.uninterrupted,
                                     clock: SteppingClock.plausible.now)

        // 1. No write was even attempted at the faulted chunk's offset.
        #expect(recorder.wroteAnythingAt(byteOffset: 128 * 512) == false)

        // 2. The ordering audit sees no write-after-failed-read anywhere.
        #expect(ChunkCycleAudit.check(recorder.operations).isEmpty)

        // 3. The faulted range still holds its own data, not chunk 0's.
        #expect(firstDifference(before, device.snapshot()) == nil)
        let store = device.snapshot()
        let start = 128 * 512
        #expect(Array(store[start ..< start + 512])
                == TestPattern.block(128, seed: Fixture.seed, blockSize: 512))

        // 4. And the bytes never written are missing from the accounting.
        #expect(summary.bytesWritten == device.byteCount - UInt64(Fixture.ioSizeBytes))
        #expect(summary.bytesRead == device.byteCount - UInt64(Fixture.ioSizeBytes))
    }

    /// Rule 3: reading back after a failed write would compare buffer A against the data that
    /// was already there and report a mismatch that did not happen.
    @Test func aFailedWriteIsNeverFollowedByAVerifyRead() throws {
        let device = try Fixture.device()
        device.injectWriteFault(blocks: 256 ..< 384)

        let recorder = RecordingBlockDevice(device)
        let engine = RetentionTestEngine(device: recorder, ioSizeBytes: Fixture.ioSizeBytes)
        let summary = try engine.run(buffers: Fixture.buffers(),
                                     deviceName: Fixture.deviceName,
                                     cacheBypass: Fixture.bypassedAssessment,
                                     grant: { Fixture.grant },
                                     control: RunControl.uninterrupted,
                                     clock: SteppingClock.plausible.now)

        #expect(ChunkCycleAudit.check(recorder.operations).isEmpty)

        // The faulted chunk contributed a read and a failed write, and nothing else.
        let faultedOffset = UInt64(256 * 512)
        let atFault = recorder.operations.filter { $0.byteOffset == faultedOffset }
        #expect(atFault.count == 2)
        #expect(atFault.first?.kind == .read)
        #expect(atFault.last?.kind == .write)
        #expect(atFault.last?.succeeded == false)

        // Exactly one chunk's worth is missing from the verify accounting, and only one
        // failure was reported — not a write error plus a phantom mismatch.
        #expect(summary.bytesVerified == device.byteCount - UInt64(Fixture.ioSizeBytes))
        #expect(summary.failures.totalRangeCount == 1)
    }

    @Test func readWriteAndVerifyFailuresAreAllClassifiedInOneRun() throws {
        let device = try Fixture.device()
        device.injectReadFault(blocks: 128 ..< 256)
        device.injectWriteFault(blocks: 256 ..< 384)
        device.injectSilentCorruption(blocks: 1_000 ..< 1_002)

        let engine = RetentionTestEngine(device: device, ioSizeBytes: Fixture.ioSizeBytes)
        let summary = try engine.run(buffers: Fixture.buffers(),
                                     deviceName: Fixture.deviceName,
                                     cacheBypass: Fixture.bypassedAssessment,
                                     grant: { Fixture.grant },
                                     control: RunControl.uninterrupted,
                                     clock: SteppingClock.plausible.now)

        #expect(summary.failures.ranges == [
            BlockRangeFailure(startBlock: 128, blockCount: 128, kind: .readError),
            BlockRangeFailure(startBlock: 256, blockCount: 128, kind: .writeError),
            BlockRangeFailure(startBlock: 1_000, blockCount: 2, kind: .verifyMismatch),
        ])
        #expect(summary.outcome == .completed)
    }

    /// Adjacent ranges of *different* kinds must not be coalesced: "blocks 128–383 failed" is
    /// useless when half could not be read and half could not be written.
    @Test func adjacentFailuresOfDifferentKindsAreNotCoalesced() throws {
        let device = try Fixture.device()
        device.injectReadFault(blocks: 128 ..< 256)
        device.injectWriteFault(blocks: 256 ..< 384)

        let engine = RetentionTestEngine(device: device, ioSizeBytes: Fixture.ioSizeBytes)
        let summary = try engine.run(buffers: Fixture.buffers(),
                                     deviceName: Fixture.deviceName,
                                     cacheBypass: Fixture.bypassedAssessment,
                                     grant: { Fixture.grant },
                                     control: RunControl.uninterrupted,
                                     clock: SteppingClock.plausible.now)

        #expect(summary.failures.ranges.count == 2)
        #expect(summary.failures.ranges.map(\.kind) == [.readError, .writeError])
    }
}

// MARK: - Gate item 4: one chunk in flight (NFR-REL-4)

struct OneChunkInFlightTests {

    @Test func aCleanRunIsAWellFormedSequenceOfOneChunkCycles() throws {
        let recorder = RecordingBlockDevice(try Fixture.device())
        let engine = RetentionTestEngine(device: recorder, ioSizeBytes: Fixture.ioSizeBytes)

        _ = try engine.run(buffers: Fixture.buffers(),
                           deviceName: Fixture.deviceName,
                           cacheBypass: Fixture.bypassedAssessment,
                           grant: { Fixture.grant },
                           control: RunControl.uninterrupted,
                           clock: SteppingClock.plausible.now)

        #expect(ChunkCycleAudit.check(recorder.operations).isEmpty)
        #expect(recorder.operations.count == 65 * 3)
    }

    @Test func theCyclesTileTheWholeDeviceExactlyOnceInOrder() throws {
        let device = try Fixture.device()
        let recorder = RecordingBlockDevice(device)
        let engine = RetentionTestEngine(device: recorder, ioSizeBytes: Fixture.ioSizeBytes)

        _ = try engine.run(buffers: Fixture.buffers(),
                           deviceName: Fixture.deviceName,
                           cacheBypass: Fixture.bypassedAssessment,
                           grant: { Fixture.grant },
                           control: RunControl.uninterrupted,
                           clock: SteppingClock.plausible.now)

        let cycles = ChunkCycleAudit.completedCycles(recorder.operations)
        #expect(cycles.count == 65)

        // FR-TEST-4: first addressable block to last, in order, with no gaps or overlaps.
        var expectedOffset: UInt64 = 0
        for cycle in cycles {
            #expect(cycle.byteOffset == expectedOffset)
            expectedOffset += UInt64(cycle.byteLength)
        }
        #expect(expectedOffset == device.byteCount)

        // FR-TEST-5: the final chunk is the exact remainder — one block, not a full I/O size.
        #expect(cycles.last?.byteLength == 512)
        #expect(cycles.dropLast().allSatisfy { $0.byteLength == Fixture.ioSizeBytes })
    }

    @Test func theSameHoldsWhenChunksFail() throws {
        let device = try Fixture.device()
        device.injectReadFault(blocks: 128 ..< 256)
        device.injectWriteFault(blocks: 256 ..< 384)

        let recorder = RecordingBlockDevice(device)
        let engine = RetentionTestEngine(device: recorder, ioSizeBytes: Fixture.ioSizeBytes)

        _ = try engine.run(buffers: Fixture.buffers(),
                           deviceName: Fixture.deviceName,
                           cacheBypass: Fixture.bypassedAssessment,
                           grant: { Fixture.grant },
                           control: RunControl.uninterrupted,
                           clock: SteppingClock.plausible.now)

        #expect(ChunkCycleAudit.check(recorder.operations).isEmpty)
        #expect(ChunkCycleAudit.completedCycles(recorder.operations).count == 63)
    }
}

// MARK: - The bounded range (D2, 2026-08-02)

struct BoundedRangeTests {

    @Test func aBoundedRunTouchesOnlyItsOwnRange() throws {
        let device = try Fixture.device()
        let before = device.snapshot()
        let recorder = RecordingBlockDevice(device)

        let engine = RetentionTestEngine(device: recorder, ioSizeBytes: Fixture.ioSizeBytes)
        let summary = try engine.run(buffers: Fixture.buffers(),
                                     deviceName: Fixture.deviceName,
                                     blockRange: 1_280 ..< 3_328,          // 16 whole chunks
                                     cacheBypass: Fixture.bypassedAssessment,
                                     grant: { Fixture.grant },
                                     control: RunControl.uninterrupted,
                                     clock: SteppingClock.plausible.now)

        #expect(summary.chunksPlanned == 16)
        #expect(summary.chunksProcessed == 16)
        #expect(firstDifference(before, device.snapshot()) == nil)

        let low = UInt64(1_280 * 512)
        let high = UInt64(3_328 * 512)
        #expect(recorder.operations.allSatisfy {
            $0.byteOffset >= low && $0.byteOffset + UInt64($0.byteLength) <= high
        })
    }

    /// The user's "stop the test as if the test were completed" (2026-08-02): a bounded run is
    /// expressed as the plan, so it ends `completed` rather than in some stopped-early state.
    @Test func aBoundedRunEndsAsCompleted() throws {
        let engine = RetentionTestEngine(device: try Fixture.device(),
                                         ioSizeBytes: Fixture.ioSizeBytes)
        let summary = try engine.run(buffers: Fixture.buffers(),
                                     deviceName: Fixture.deviceName,
                                     blockRange: 1_280 ..< 3_328,
                                     cacheBypass: Fixture.bypassedAssessment,
                                     grant: { Fixture.grant },
                                     control: RunControl.uninterrupted,
                                     clock: SteppingClock.plausible.now)

        #expect(summary.outcome == .completed)
        #expect(summary.isComplete)
    }

    /// The shape of the `disk4` gate: a chunk-aligned start and a length that is deliberately
    /// **not** a whole multiple of the I/O size, so the run ends on a short chunk without
    /// going near the end of the device.
    @Test func aBoundedRunEndsOnAShortFinalChunk() throws {
        let device = try Fixture.device()
        let recorder = RecordingBlockDevice(device)

        // 1,280 is chunk-aligned (10 x 128). 2,000 blocks is 15 full chunks + 80 blocks.
        let engine = RetentionTestEngine(device: recorder, ioSizeBytes: Fixture.ioSizeBytes)
        let summary = try engine.run(buffers: Fixture.buffers(),
                                     deviceName: Fixture.deviceName,
                                     blockRange: 1_280 ..< 3_280,
                                     cacheBypass: Fixture.bypassedAssessment,
                                     grant: { Fixture.grant },
                                     control: RunControl.uninterrupted,
                                     clock: SteppingClock.plausible.now)

        #expect(summary.chunksPlanned == 16)
        #expect(summary.outcome == .completed)

        let cycles = ChunkCycleAudit.completedCycles(recorder.operations)
        #expect(cycles.count == 16)
        #expect(cycles.last?.byteLength == 80 * 512)
        #expect(cycles.last?.byteOffset == UInt64(3_200 * 512))
        #expect(ChunkCycleAudit.check(recorder.operations).isEmpty)
    }

    @Test func aRangeRunningPastTheEndOfTheDeviceIsRefusedBeforeAnyIO() throws {
        let device = try Fixture.device()
        let recorder = RecordingBlockDevice(device)
        let engine = RetentionTestEngine(device: recorder, ioSizeBytes: Fixture.ioSizeBytes)

        #expect(throws: RunAbort.rangeNotWithinDevice(startBlock: 8_000,
                                                      blockCount: 1_000,
                                                      deviceBlockCount: Fixture.blocks512)) {
            _ = try engine.run(buffers: Fixture.buffers(),
                               deviceName: Fixture.deviceName,
                               blockRange: 8_000 ..< 9_000,
                               cacheBypass: Fixture.bypassedAssessment,
                               grant: { Fixture.grant },
                               control: RunControl.uninterrupted,
                               clock: SteppingClock.plausible.now)
        }
        #expect(recorder.operations.isEmpty)
    }

    @Test func buffersSmallerThanTheIOSizeAreRefusedBeforeAnyIO() throws {
        let recorder = RecordingBlockDevice(try Fixture.device())
        let engine = RetentionTestEngine(device: recorder, ioSizeBytes: Fixture.ioSizeBytes)
        let small = try ChunkBuffers(ioSizeBytes: 4_096)

        #expect(throws: RunAbort.buffersTooSmall(ioSizeBytes: Fixture.ioSizeBytes,
                                                 bufferCapacityBytes: 4_096)) {
            _ = try engine.run(buffers: small,
                               deviceName: Fixture.deviceName,
                               cacheBypass: Fixture.bypassedAssessment,
                               grant: { Fixture.grant },
                               control: RunControl.uninterrupted,
                               clock: SteppingClock.plausible.now)
        }
        #expect(recorder.operations.isEmpty)
    }
}

// MARK: - The write guard (NFR-REL-3, NFR-REL-5)

struct WriteGuardTests {

    @Test func aRunWithNoAccessHeldWritesNothing() throws {
        let device = try Fixture.device()
        let before = device.snapshot()
        let recorder = RecordingBlockDevice(device)
        let engine = RetentionTestEngine(device: recorder, ioSizeBytes: Fixture.ioSizeBytes)

        #expect(throws: RunAbort.writeRefused(.noAccessHeld(requested: Fixture.deviceName))) {
            _ = try engine.run(buffers: Fixture.buffers(),
                               deviceName: Fixture.deviceName,
                               cacheBypass: Fixture.bypassedAssessment,
                               grant: { nil },
                               control: RunControl.uninterrupted,
                               clock: SteppingClock.plausible.now)
        }

        #expect(recorder.writes.isEmpty)
        #expect(recorder.operations.isEmpty, "refused before even reading")
        #expect(firstDifference(before, device.snapshot()) == nil)
    }

    @Test func aGrantHeldOnADifferentDeviceIsRefused() throws {
        let recorder = RecordingBlockDevice(try Fixture.device())
        let engine = RetentionTestEngine(device: recorder, ioSizeBytes: Fixture.ioSizeBytes)
        let elsewhere = DeviceAccessGrant(deviceName: "disk0", claimHeld: true, exclusiveOpenHeld: true)

        #expect(throws: RunAbort.writeRefused(.wrongDevice(held: "disk0",
                                                           requested: Fixture.deviceName))) {
            _ = try engine.run(buffers: Fixture.buffers(),
                               deviceName: Fixture.deviceName,
                               cacheBypass: Fixture.bypassedAssessment,
                               grant: { elsewhere },
                               control: RunControl.uninterrupted,
                               clock: SteppingClock.plausible.now)
        }
        #expect(recorder.writes.isEmpty)
    }

    /// NFR-REL-5. `AcquiredDevice.grant` recomputes rather than caching, so a device released
    /// mid-run stops the **next** write — which only works because the guard is re-checked per
    /// chunk rather than once at the top.
    @Test func accessRevokedMidRunStopsTheVeryNextWrite() throws {
        let device = try Fixture.device()
        let before = device.snapshot()
        let recorder = RecordingBlockDevice(device)

        var chunksAllowed = 3
        let grant: () -> DeviceAccessGrant? = {
            defer { chunksAllowed -= 1 }
            return chunksAllowed > 0
                ? Fixture.grant
                : DeviceAccessGrant(deviceName: Fixture.deviceName,
                                    claimHeld: false,      // the claim was dropped
                                    exclusiveOpenHeld: false)
        }

        let engine = RetentionTestEngine(device: recorder, ioSizeBytes: Fixture.ioSizeBytes)
        #expect(throws: RunAbort.writeRefused(.claimNotHeld(Fixture.deviceName))) {
            _ = try engine.run(buffers: Fixture.buffers(),
                               deviceName: Fixture.deviceName,
                               cacheBypass: Fixture.bypassedAssessment,
                               grant: grant,
                               control: RunControl.uninterrupted,
                               clock: SteppingClock.plausible.now)
        }

        // One call at the top of the run, then one per chunk: chunks 0 and 1 wrote, chunk 2
        // was refused before its write.
        #expect(recorder.writes.count == 2)
        #expect(firstDifference(before, device.snapshot()) == nil)

        // NFR-REL-5: it stopped between the read and the write, and issued nothing further.
        #expect(ChunkCycleAudit.check(recorder.operations)
                == [.incompleteCycleAtEnd(byteOffset: UInt64(2 * Fixture.ioSizeBytes),
                                          wasWritten: false)])
    }
}

// MARK: - The stop path (D5, 2026-08-02)

struct StopPathTests {

    @Test func stoppingOnTheFirstFailureIssuesNoFurtherIO() throws {
        let device = try Fixture.device()
        device.injectSilentCorruption(blocks: 200 ..< 202)     // chunk 1
        device.injectSilentCorruption(blocks: 5_000 ..< 5_002) // chunk 39

        let recorder = RecordingBlockDevice(device)
        let observer = RecordingRunObserver()
        observer.dispositionForFailure = { _ in .stopRun }

        let engine = RetentionTestEngine(device: recorder, ioSizeBytes: Fixture.ioSizeBytes)
        let summary = try engine.run(buffers: Fixture.buffers(),
                                     deviceName: Fixture.deviceName,
                                     cacheBypass: Fixture.bypassedAssessment,
                                     grant: { Fixture.grant },
                                     control: RunControl.uninterrupted,
                                     observer: observer,
                                     clock: SteppingClock.plausible.now)

        let expected = BlockRangeFailure(startBlock: 200, blockCount: 2, kind: .verifyMismatch)
        #expect(summary.outcome == .stoppedOnFailure(expected))
        #expect(summary.failures.ranges == [expected])
        #expect(observer.failures.count == 1, "the second fault was never reached")

        // Nothing at all happened past the stopping chunk.
        let stoppedAfter = UInt64(2 * Fixture.ioSizeBytes)
        #expect(recorder.operations.allSatisfy { $0.byteOffset < stoppedAfter })
        #expect(summary.chunksProcessed == 2)
        #expect(summary.chunksPlanned == 65)
    }

    @Test func continuingIsTheDefaultWhenNoObserverIsWatching() throws {
        let device = try Fixture.device()
        device.injectSilentCorruption(blocks: 200 ..< 202)

        let engine = RetentionTestEngine(device: device, ioSizeBytes: Fixture.ioSizeBytes)
        let summary = try engine.run(buffers: Fixture.buffers(),
                                     deviceName: Fixture.deviceName,
                                     cacheBypass: Fixture.bypassedAssessment,
                                     grant: { Fixture.grant },
                                     control: RunControl.uninterrupted,
                                     clock: SteppingClock.plausible.now)

        #expect(summary.outcome == .completed)
        #expect(summary.chunksProcessed == 65)
    }
}

// MARK: - FR-TEST-9 (D6, 2026-08-02)

struct CacheBypassIntegrationTests {

    @Test func aCleanRunOnAPlausibleDeviceKeepsTheAcquireVerdict() throws {
        let engine = RetentionTestEngine(device: try Fixture.device(),
                                         ioSizeBytes: Fixture.ioSizeBytes)
        let summary = try engine.run(buffers: Fixture.buffers(),
                                     deviceName: Fixture.deviceName,
                                     cacheBypass: Fixture.bypassedAssessment,
                                     grant: { Fixture.grant },
                                     control: RunControl.uninterrupted,
                                     clock: SteppingClock.plausible.now)

        #expect(summary.cacheBypass.state == .bypassed)
        #expect(summary.cacheBypass.state.qualifiesVerifyResult == false)
    }

    /// The verdict is **seeded at acquire, not recomputed at run start** (BUILD-PLAN 8.8, as
    /// amended). Opening `/dev/diskN` instead of `/dev/rdiskN` is decided long before the run,
    /// and the run must carry that verdict rather than reach its own cheerful conclusion.
    @Test func aBlockDeviceVerdictSurvivesTheWholeRun() throws {
        let engine = RetentionTestEngine(device: try Fixture.device(),
                                         ioSizeBytes: Fixture.ioSizeBytes)
        let summary = try engine.run(buffers: Fixture.buffers(),
                                     deviceName: Fixture.deviceName,
                                     cacheBypass: Fixture.blockNodeAssessment,
                                     grant: { Fixture.grant },
                                     control: RunControl.uninterrupted,
                                     clock: SteppingClock.plausible.now)

        #expect(summary.cacheBypass.state.qualifiesVerifyResult)
        if case .likelyCached = summary.cacheBypass.state {} else {
            Issue.record("expected likelyCached, got \(summary.cacheBypass.state)")
        }
        #expect(summary.outcome == .completed, "FR-TEST-9 qualifies the result, it does not stop the run")
    }

    /// The falsifier firing. Reads that take no measurable time did not cross a wire.
    @Test func animplausiblyFastReadDowngradesTheVerdictMidRun() throws {
        let engine = RetentionTestEngine(device: try Fixture.device(),
                                         ioSizeBytes: Fixture.ioSizeBytes)
        let summary = try engine.run(buffers: Fixture.buffers(),
                                     deviceName: Fixture.deviceName,
                                     cacheBypass: Fixture.bypassedAssessment,
                                     grant: { Fixture.grant },
                                     control: RunControl.uninterrupted,
                                     clock: SteppingClock.immeasurablyFast.now)

        #expect(summary.cacheBypass.state.qualifiesVerifyResult,
                "a read that took no measurable time was accepted as having reached a device")
        #expect(summary.outcome == .completed)
        #expect(summary.failures.isEmpty, "the refresh still happened and still verified")
    }

    /// The same finding without any rigging: an `InMemoryBlockDevice` genuinely **is** RAM, so
    /// a real clock over a real run must reach the same conclusion. Nothing here is
    /// constructed — this is the falsifier judging actual measured throughput, and it is the
    /// strongest evidence available that it works.
    @Test func theInMemoryDeviceIsItselfFlaggedAsCached() throws {
        let engine = RetentionTestEngine(device: try Fixture.device(),
                                         ioSizeBytes: Fixture.ioSizeBytes)
        let summary = try engine.run(buffers: Fixture.buffers(),
                                     deviceName: Fixture.deviceName,
                                     cacheBypass: Fixture.bypassedAssessment,
                                     grant: { Fixture.grant },
                                     control: RunControl.uninterrupted)
                                                                       // the real monotonic clock

        #expect(summary.cacheBypass.state.qualifiesVerifyResult)
        #expect(summary.cacheBypass.fastestObservedBytesPerSecond
                > CacheBypassCheck.fallbackImplausibleThroughputBytesPerSecond)
    }

    /// Only ever downgrades. A plausible rate is what an uncached read looks like *and* what a
    /// slow cache hit looks like, so it is evidence of nothing and must not promote.
    @Test func aPlausibleRateNeverPromotesADowngradedVerdict() throws {
        let engine = RetentionTestEngine(device: try Fixture.device(),
                                         ioSizeBytes: Fixture.ioSizeBytes)
        let summary = try engine.run(buffers: Fixture.buffers(),
                                     deviceName: Fixture.deviceName,
                                     cacheBypass: Fixture.blockNodeAssessment,
                                     grant: { Fixture.grant },
                                     control: RunControl.uninterrupted,
                                     clock: SteppingClock.plausible.now)

        #expect(summary.cacheBypass.state != .bypassed)
    }
}

// MARK: - The XPC boundary's constants (Step 8)

/// The engine accepts any positive multiple of the logical block size so tests can use awkward
/// I/O sizes; the **privileged boundary** accepts only FR-CTRL-8's four. These pin the values
/// the boundary will let through, because an I/O size that is not a whole multiple of the
/// logical block size would be admitted by the boundary and then refused by the plan — a
/// refusal the caller could do nothing about, arriving after the device was already acquired.
struct CycleBoundaryConstantsTests {

    @Test func everyPermittedIOSizeWorksAtBothSupportedGeometries() throws {
        for ioSize in TesterProtocol.permittedIOSizes {
            for blockSize in [512, 4_096] {                    // NFR-COMPAT-5
                #expect(ioSize % blockSize == 0,
                        "\(ioSize) is not a whole multiple of a \(blockSize)-byte block")
                // And the plan the engine would build really is valid.
                let plan = try ChunkPlan(logicalBlockSize: blockSize,
                                         blockCount: 1_000_000,
                                         ioSizeBytes: ioSize)
                #expect(plan.blocksPerChunk >= 1)
            }
        }
    }

    @Test func thePermittedSizesAreFRCTRL8sFour() {
        #expect(TesterProtocol.permittedIOSizes == [1 << 20, 2 << 20, 4 << 20, 8 << 20])
        #expect(TesterProtocol.permittedIOSizes.contains(TesterProtocol.defaultIOSizeBytes))
        #expect(TesterProtocol.defaultIOSizeBytes == 4 << 20)
    }

    /// The cap has to be a whole number of chunks at every permitted I/O size, or the largest
    /// legal request would end on a short chunk for arithmetic reasons rather than because a
    /// caller asked for one.
    @Test func theCallCapIsAWholeNumberOfChunksAtEveryPermittedIOSize() {
        for ioSize in TesterProtocol.permittedIOSizes {
            #expect(TesterProtocol.maximumBytesPerCall % UInt64(ioSize) == 0)
        }
    }

    /// 3 GiB of I/O at the 200 MiB/s floor the user set is ~15 s — the number the 300 s client
    /// timeout and the "bounded by construction" argument both rest on.
    @Test func theCapIsOneGibibyte() {
        #expect(TesterProtocol.maximumBytesPerCall == 1_073_741_824)
    }
}

// MARK: - The bounded failure list (NFR-PERF-2)

struct FailureLogTests {

    private func failure(_ start: UInt64, _ count: UInt64,
                         _ kind: BlockFailureKind = .verifyMismatch) -> BlockRangeFailure {
        BlockRangeFailure(startBlock: start, blockCount: count, kind: kind)
    }

    @Test func anEmptyLogSaysSo() {
        var log = FailureLog()
        log.finish()
        #expect(log.isEmpty)
        #expect(log.ranges.isEmpty)
        #expect(log.isTruncated == false)
        #expect(log.summaryLine == "no failed block ranges")
    }

    @Test func adjacentRangesOfTheSameKindCoalesce() {
        var log = FailureLog()
        log.record(failure(10, 2))
        log.record(failure(12, 3))
        log.record(failure(15, 1))
        log.finish()

        #expect(log.ranges == [failure(10, 6)])
        #expect(log.failedBlockCount == 6)
        #expect(log.totalRangeCount == 1)
    }

    @Test func aGapPreventsCoalescing() {
        var log = FailureLog()
        log.record(failure(10, 2))
        log.record(failure(13, 2))
        log.finish()

        #expect(log.ranges == [failure(10, 2), failure(13, 2)])
        #expect(log.failedBlockCount == 4)
    }

    @Test func adjacentRangesOfDifferentKindsDoNotCoalesce() {
        var log = FailureLog()
        log.record(failure(10, 2, .readError))
        log.record(failure(12, 2, .writeError))
        log.finish()

        #expect(log.ranges.count == 2)
        #expect(log.ranges.map(\.kind) == [.readError, .writeError])
    }

    /// The cap must bound memory **and** say that it did. A list that quietly stops growing
    /// reads exactly like a complete one.
    @Test func thelogIsCappedAndSaysWhenItTruncated() {
        var log = FailureLog(retentionLimit: 4)
        for index in UInt64(0) ..< 10 {
            log.record(failure(index * 10, 1))     // ten separate, non-adjacent ranges
        }
        log.finish()

        #expect(log.ranges.count == 4)
        #expect(log.droppedRangeCount == 6)
        #expect(log.totalRangeCount == 10)
        #expect(log.isTruncated)
        #expect(log.failedBlockCount == 10, "the total is exact even when the list is not")
        #expect(log.summaryLine.contains("truncated"))
    }

    /// Coalescing must keep working past the cap, or a long contiguous run of bad blocks
    /// arriving late would be counted as thousands of dropped ranges instead of one.
    @Test func coalescingStillWorksAfterTheCapIsReached() {
        var log = FailureLog(retentionLimit: 2)
        log.record(failure(0, 1))
        log.record(failure(10, 1))
        log.record(failure(20, 1))          // the cap is now full; this one is pending
        for index in UInt64(0) ..< 100 {
            log.record(failure(21 + index, 1))   // all adjacent to it
        }
        log.finish()

        #expect(log.ranges.count == 2)
        #expect(log.droppedRangeCount == 1, "the 101 adjacent failures are one range, not 101")
        #expect(log.failedBlockCount == 103)
    }

    @Test func finishIsIdempotent() {
        var log = FailureLog()
        log.record(failure(10, 2))
        log.finish()
        log.finish()
        #expect(log.ranges == [failure(10, 2)])
    }
}
