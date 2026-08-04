//
//  ChunkCycleAuditTests.swift
//  Proof that the Step 8 ordering audit CAN FAIL.
//
//  ## Why this file exists at all
//
//  `ChunkCycleAudit` is the instrumentation BUILD-PLAN Step 8's gate item 4 asks for, and it
//  will be run against every simulated cycle in `RetentionCycleTests`. If it only ever ran
//  there, a green result would be indistinguishable from a checker that returns `[]`
//  unconditionally — and this project has already shipped, and caught, exactly that shape of
//  defect more than once:
//
//    * a probe that printed "open IS exclusive" in a phase where both opens failed;
//    * a guard that reported "assertion deleted" when it could not find the file;
//    * an FR-TEST-9 timing check that could not have failed on a raw character device.
//
//  The project's standing rule, sharpened by Step 7: **a check must be shown capable of
//  failing, or it is a substitute for a test.** So every violation the audit can report is
//  produced here from a hand-built sequence, with no device and no engine anywhere near it —
//  which is only possible because the checker is a pure function of `[DeviceOperation]`.
//
//  Two of these deserve singling out. `aWriteAfterAFailedReadIsCaught` is the sixth hazard
//  (2026-08-02): the buffers are reused, so a write following a failed read carries the
//  *previous* chunk's data to this chunk's offset. `twoChunksInFlightIsCaught` is NFR-REL-4
//  itself — the property `ChunkBuffers.peakAllocatedBytes` cannot see.
//
//  The last three tests are the other half: sequences that are legitimate but *look* irregular
//  — a failed read, a failed write, a failed verify — must produce **no** violations. A
//  checker that flags those would make every fault-injection test in `RetentionCycleTests`
//  fail for the wrong reason, and would be trusted anyway because it was "strict".
//

import Testing
import Foundation

struct ChunkCycleAuditTests {

    // MARK: Helpers

    private func read(_ offset: UInt64, _ length: Int = 4096, ok: Bool = true) -> DeviceOperation {
        DeviceOperation(kind: .read, byteOffset: offset, byteLength: length, succeeded: ok)
    }

    private func write(_ offset: UInt64, _ length: Int = 4096, ok: Bool = true) -> DeviceOperation {
        DeviceOperation(kind: .write, byteOffset: offset, byteLength: length, succeeded: ok)
    }

    /// One well-formed cycle: read, write, verify read — all at the same place.
    private func cycle(_ offset: UInt64, _ length: Int = 4096) -> [DeviceOperation] {
        [read(offset, length), write(offset, length), read(offset, length)]
    }

    // MARK: The clean case

    @Test func aWellFormedRunProducesNoViolations() {
        let operations = cycle(0) + cycle(4096) + cycle(8192)
        #expect(ChunkCycleAudit.check(operations).isEmpty)
    }

    @Test func anEmptySequenceProducesNoViolations() {
        #expect(ChunkCycleAudit.check([]).isEmpty)
    }

    @Test func aShorterFinalCycleIsWellFormed() {
        // FR-TEST-5: the last chunk is the exact remainder, so its three operations are all
        // shorter than the rest. That must not read as a mismatch.
        let operations = cycle(0) + cycle(4096) + cycle(8192, 1024)
        #expect(ChunkCycleAudit.check(operations).isEmpty)
    }

    // MARK: Every violation, produced deliberately

    @Test func aWriteWithNoPrecedingReadIsCaught() {
        let violations = ChunkCycleAudit.check([write(0)])
        #expect(violations == [.writeWithoutPrecedingRead(index: 0, byteOffset: 0)])
    }

    /// The sixth hazard (2026-08-02). The buffers are reused, so this write puts the previous
    /// chunk's data at this chunk's offset — silent, permanent corruption of a region the tool
    /// was asked to preserve.
    @Test func aWriteAfterAFailedReadIsCaught() {
        // cycle(0) occupies indices 0–2; the failed read is 3 and the offending write is 4.
        let operations = cycle(0) + [read(4096, ok: false), write(4096)]
        let violations = ChunkCycleAudit.check(operations)
        #expect(violations == [.writeAfterFailedRead(index: 4, readOffset: 4096, writeOffset: 4096)])
    }

    /// NFR-REL-4: only one chunk's original may be held at a time. This is the property
    /// `ChunkBuffers.peakAllocatedBytes` is blind to — the buffers stay the same size whether
    /// the engine holds one chunk or reads a second over the top of the first.
    @Test func twoChunksInFlightIsCaught() {
        let operations = [read(0), read(4096), write(4096), read(4096)]
        let violations = ChunkCycleAudit.check(operations)
        #expect(violations == [.chunkOpenedWhilePreviousInFlight(index: 1,
                                                                 inFlightOffset: 0,
                                                                 newOffset: 4096)])
    }

    @Test func skippingTheWriteEntirelyIsCaught() {
        // read, read: the engine "verified" without ever writing, so the comparison is of the
        // original against itself and passes for every chunk of every drive.
        let violations = ChunkCycleAudit.check([read(0), read(0)])
        #expect(violations.contains(.chunkOpenedWhilePreviousInFlight(index: 1,
                                                                      inFlightOffset: 0,
                                                                      newOffset: 0)))
    }

    @Test func aWriteToTheWrongOffsetIsCaught() {
        let violations = ChunkCycleAudit.check([read(0), write(4096), read(4096)])
        #expect(violations == [.writeDiffersFromRead(index: 1,
                                                     readOffset: 0, readLength: 4096,
                                                     writeOffset: 4096, writeLength: 4096)])
    }

    @Test func aWriteOfTheWrongLengthIsCaught() {
        let violations = ChunkCycleAudit.check([read(0, 4096), write(0, 2048), read(0, 2048)])
        #expect(violations == [.writeDiffersFromRead(index: 1,
                                                     readOffset: 0, readLength: 4096,
                                                     writeOffset: 0, writeLength: 2048)])
    }

    @Test func aVerifyReadAtTheWrongPlaceIsCaught() {
        let violations = ChunkCycleAudit.check([read(0), write(0), read(4096)])
        #expect(violations == [.verifyReadDiffersFromWrite(index: 2,
                                                           writeOffset: 0, writeLength: 4096,
                                                           readOffset: 4096, readLength: 4096)])
    }

    /// Rule 3 of the cycle: reading back after a failed write compares buffer A against the
    /// data that was already there, and reports a mismatch that did not happen.
    @Test func aVerifyAfterAFailedWriteIsCaught() {
        let violations = ChunkCycleAudit.check([read(0), write(0, ok: false), read(0)])
        #expect(violations == [.verifyAfterFailedWrite(index: 2, byteOffset: 0)])
    }

    @Test func writingTwiceWithNoVerifyIsCaught() {
        let violations = ChunkCycleAudit.check([read(0), write(0), write(0)])
        #expect(violations == [.writtenTwiceWithoutVerify(index: 2, byteOffset: 0)])
    }

    @Test func aSequenceEndingAfterTheReadIsCaught() {
        let violations = ChunkCycleAudit.check([read(0)])
        #expect(violations == [.incompleteCycleAtEnd(byteOffset: 0, wasWritten: false)])
    }

    @Test func aSequenceEndingAfterTheWriteIsCaught() {
        let violations = ChunkCycleAudit.check([read(0), write(0)])
        #expect(violations == [.incompleteCycleAtEnd(byteOffset: 0, wasWritten: true)])
    }

    // MARK: The other half — legitimate irregularity must NOT be flagged

    @Test func aFailedReadFollowedByTheNextChunkIsClean() {
        // FR-FAIL-3: the chunk is recorded as failed and the run carries on. Nothing was
        // written, and that is correct, not a violation.
        let operations = [read(0, ok: false)] + cycle(4096)
        #expect(ChunkCycleAudit.check(operations).isEmpty)
    }

    @Test func aFailedWriteFollowedByTheNextChunkIsClean() {
        let operations = [read(0), write(0, ok: false)] + cycle(4096)
        #expect(ChunkCycleAudit.check(operations).isEmpty)
    }

    @Test func aFailedVerifyReadFollowedByTheNextChunkIsClean() {
        let operations = [read(0), write(0), read(0, ok: false)] + cycle(4096)
        #expect(ChunkCycleAudit.check(operations).isEmpty)
    }

    @Test func consecutiveFailedReadsAreClean() {
        let operations = [read(0, ok: false), read(4096, ok: false)] + cycle(8192)
        #expect(ChunkCycleAudit.check(operations).isEmpty)
    }

    // MARK: Extracting the cycles that completed

    @Test func completedCyclesReportsEachFullCycleOnce() {
        let operations = cycle(0) + cycle(4096, 1024)
        let cycles = ChunkCycleAudit.completedCycles(operations)
        #expect(cycles == [.init(byteOffset: 0, byteLength: 4096),
                           .init(byteOffset: 4096, byteLength: 1024)])
    }

    @Test func completedCyclesSkipsChunksThatFailed() {
        let operations = [read(0, ok: false)] + cycle(4096) + [read(8192), write(8192, ok: false)]
        let cycles = ChunkCycleAudit.completedCycles(operations)
        #expect(cycles == [.init(byteOffset: 4096, byteLength: 4096)])
    }
}
