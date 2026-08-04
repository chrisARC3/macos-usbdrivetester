//
//  ChunkCycleAudit.swift
//  Test support — the instrumentation BUILD-PLAN Step 8's gate item 4 asks for.
//
//  ## What this is for
//
//  NFR-REL-4 bounds the in-flight data-loss window to one chunk, and the gate asks for
//  "instrumentation [that] confirms only one chunk's worth of original data is ever held."
//  Step 7 already instruments the *buffers* — `ChunkBuffers.peakAllocatedBytes` — and that is
//  not sufficient on its own. Bounded buffers say nothing about whether the engine read a
//  second chunk before finishing the first, and NFR-REL-4 is about the data in flight, not the
//  bytes allocated.
//
//  So this records every operation the engine issues at the device boundary and checks the
//  *sequence*. The properties it enforces are the ones the cycle's correctness rests on:
//
//  | Property | Requirement | Violation if broken |
//  |---|---|---|
//  | A write is always preceded by a successful read of the same range | FR-TEST-7, and the stale-buffer hazard | ``Violation/writeWithoutPrecedingRead`` |
//  | The write covers exactly what was read | FR-TEST-7, NFR-REL-2 | ``Violation/writeDiffersFromRead`` |
//  | The verify read happens **after** the write, at the same place | FR-TEST-3 | ``Violation/verifyReadDiffersFromWrite`` |
//  | Only one chunk is ever open | **NFR-REL-4** | ``Violation/chunkOpenedWhilePreviousInFlight`` |
//  | No write follows a failed read | the sixth hazard, 2026-08-02 | ``Violation/writeAfterFailedRead`` |
//  | No verify follows a failed write | rule 3 of the cycle | ``Violation/verifyAfterFailedWrite`` |
//
//  ## Why the checker is pure, and separate from the recorder
//
//  Because a check that has never been seen to fail is not evidence. ``check(_:)`` is a
//  function from `[DeviceOperation]` to `[Violation]` with no device, no engine and no I/O
//  anywhere near it, so `ChunkCycleAuditTests` can hand it sequences that are deliberately
//  wrong and assert it catches each one. If the checker only ever ran against the real engine,
//  a green result would be indistinguishable from a checker that returns `[]` unconditionally —
//  which is the precise defect Step 7's calibration probe was written to avoid, in a new place.
//

import Foundation

// MARK: - What the engine did

/// One operation issued at the `RawBlockDevice` boundary.
struct DeviceOperation: Equatable, CustomStringConvertible {

    enum Kind: Equatable, CustomStringConvertible {
        case read
        case write

        var description: String { self == .read ? "read" : "write" }
    }

    let kind: Kind
    let byteOffset: UInt64
    let byteLength: Int

    /// Whether the underlying device returned rather than threw.
    let succeeded: Bool

    var description: String {
        "\(kind) \(byteLength)B @ \(byteOffset)\(succeeded ? "" : " [failed]")"
    }
}

/// A `RawBlockDevice` that records every call and forwards it unchanged.
///
/// Deliberately transparent: it injects nothing and changes nothing, so a run through it is
/// the same run. Fault injection stays where it already is, in `InMemoryBlockDevice`.
final class RecordingBlockDevice: RawBlockDevice {

    private let underlying: RawBlockDevice

    /// Every operation, in the order it was issued.
    private(set) var operations: [DeviceOperation] = []

    init(_ underlying: RawBlockDevice) {
        self.underlying = underlying
    }

    var logicalBlockSize: Int { underlying.logicalBlockSize }
    var blockCount: UInt64 { underlying.blockCount }

    @discardableResult
    func read(into buffer: UnsafeMutableRawBufferPointer, atByteOffset offset: UInt64) throws -> Int {
        do {
            let transferred = try underlying.read(into: buffer, atByteOffset: offset)
            record(.read, offset: offset, length: buffer.count, succeeded: true)
            return transferred
        } catch {
            record(.read, offset: offset, length: buffer.count, succeeded: false)
            throw error
        }
    }

    @discardableResult
    func write(_ buffer: UnsafeRawBufferPointer, atByteOffset offset: UInt64) throws -> Int {
        do {
            let transferred = try underlying.write(buffer, atByteOffset: offset)
            record(.write, offset: offset, length: buffer.count, succeeded: true)
            return transferred
        } catch {
            record(.write, offset: offset, length: buffer.count, succeeded: false)
            throw error
        }
    }

    private func record(_ kind: DeviceOperation.Kind, offset: UInt64, length: Int, succeeded: Bool) {
        operations.append(DeviceOperation(kind: kind, byteOffset: offset,
                                          byteLength: length, succeeded: succeeded))
    }

    /// Every write that reached the device, successful or not.
    var writes: [DeviceOperation] { operations.filter { $0.kind == .write } }

    /// Whether anything was ever written at `byteOffset`.
    func wroteAnythingAt(byteOffset: UInt64) -> Bool {
        operations.contains { $0.kind == .write && $0.byteOffset == byteOffset }
    }
}

// MARK: - The checker

/// Checks that a recorded operation sequence is a well-formed run of read → write → verify
/// cycles, one chunk at a time.
enum ChunkCycleAudit {

    /// A way the sequence departs from the cycle's contract.
    ///
    /// Each carries the operation index so a failure names the exact point, not just the fact.
    enum Violation: Equatable, CustomStringConvertible {

        /// A write with no preceding successful read in flight. The dangerous one: the buffers
        /// are reused, so this write carries whatever the *previous* chunk left behind.
        case writeWithoutPrecedingRead(index: Int, byteOffset: UInt64)

        /// A write followed a read that **failed**. Same hazard, named precisely because the
        /// preceding failure is what makes it diagnosable.
        case writeAfterFailedRead(index: Int, readOffset: UInt64, writeOffset: UInt64)

        /// The write did not cover exactly what was read (FR-TEST-7, NFR-REL-2).
        case writeDiffersFromRead(index: Int,
                                  readOffset: UInt64, readLength: Int,
                                  writeOffset: UInt64, writeLength: Int)

        /// A second chunk was started while one was still in flight (**NFR-REL-4**).
        case chunkOpenedWhilePreviousInFlight(index: Int,
                                              inFlightOffset: UInt64,
                                              newOffset: UInt64)

        /// The chunk was written twice with no verify read between.
        case writtenTwiceWithoutVerify(index: Int, byteOffset: UInt64)

        /// The verify read did not address exactly what had just been written (FR-TEST-3).
        case verifyReadDiffersFromWrite(index: Int,
                                        writeOffset: UInt64, writeLength: Int,
                                        readOffset: UInt64, readLength: Int)

        /// A read at the just-failed write's offset — a verify of a write that did not happen,
        /// which compares buffer A against the data that was already there.
        case verifyAfterFailedWrite(index: Int, byteOffset: UInt64)

        /// The sequence ended with a chunk still open. Legitimate when a run aborted between
        /// the read and the write (NFR-REL-5 requires exactly that: no further writes), so
        /// tests assert on this one rather than treating it as automatically wrong.
        case incompleteCycleAtEnd(byteOffset: UInt64, wasWritten: Bool)

        var description: String {
            switch self {
            case .writeWithoutPrecedingRead(let i, let offset):
                return "op \(i): write @ \(offset) with no chunk loaded — the buffer holds the "
                     + "previous chunk's data"
            case .writeAfterFailedRead(let i, let readOffset, let writeOffset):
                return "op \(i): write @ \(writeOffset) after the read @ \(readOffset) failed — "
                     + "the buffer holds the previous chunk's data"
            case .writeDiffersFromRead(let i, let ro, let rl, let wo, let wl):
                return "op \(i): wrote \(wl)B @ \(wo) but read \(rl)B @ \(ro)"
            case .chunkOpenedWhilePreviousInFlight(let i, let inFlight, let new):
                return "op \(i): started a chunk @ \(new) while @ \(inFlight) was still in "
                     + "flight — two chunks held at once"
            case .writtenTwiceWithoutVerify(let i, let offset):
                return "op \(i): wrote @ \(offset) twice with no verify read between"
            case .verifyReadDiffersFromWrite(let i, let wo, let wl, let ro, let rl):
                return "op \(i): verify read \(rl)B @ \(ro) does not match the write of "
                     + "\(wl)B @ \(wo)"
            case .verifyAfterFailedWrite(let i, let offset):
                return "op \(i): read @ \(offset) after the write there failed — a verify of "
                     + "a write that never happened"
            case .incompleteCycleAtEnd(let offset, let written):
                return "sequence ended with the chunk @ \(offset) still open "
                     + "(\(written ? "written, not verified" : "read, not written"))"
            }
        }
    }

    /// One completed cycle: a successful read, write and verify read at the same place.
    struct CompletedCycle: Equatable {
        let byteOffset: UInt64
        let byteLength: Int
    }

    /// What the sequence was doing at each point.
    private enum State: Equatable {
        case idle
        case loaded(offset: UInt64, length: Int)          // read done, awaiting the write
        case written(offset: UInt64, length: Int)         // write done, awaiting the verify
        case readFailed(offset: UInt64)                   // the chunk is over; no write may follow
        case writeFailed(offset: UInt64)                  // the chunk is over; no verify may follow
    }

    /// Check a recorded sequence.
    ///
    /// - Returns: every violation found, in order. Empty means the sequence is a well-formed
    ///   series of one-chunk-at-a-time cycles.
    static func check(_ operations: [DeviceOperation]) -> [Violation] {
        var violations: [Violation] = []
        var state = State.idle

        for (index, operation) in operations.enumerated() {
            switch (state, operation.kind) {

            // --- nothing in flight ---
            case (.idle, .read):
                state = operation.succeeded
                    ? .loaded(offset: operation.byteOffset, length: operation.byteLength)
                    : .readFailed(offset: operation.byteOffset)

            case (.idle, .write):
                violations.append(.writeWithoutPrecedingRead(index: index,
                                                             byteOffset: operation.byteOffset))
                state = .idle

            // --- the previous chunk's read failed ---
            case (.readFailed(let failedAt), .write):
                violations.append(.writeAfterFailedRead(index: index,
                                                        readOffset: failedAt,
                                                        writeOffset: operation.byteOffset))
                state = .idle

            case (.readFailed, .read):
                state = operation.succeeded
                    ? .loaded(offset: operation.byteOffset, length: operation.byteLength)
                    : .readFailed(offset: operation.byteOffset)

            // --- the previous chunk's write failed ---
            case (.writeFailed(let failedAt), .read) where operation.byteOffset == failedAt:
                violations.append(.verifyAfterFailedWrite(index: index, byteOffset: failedAt))
                state = .idle

            case (.writeFailed, .read):
                state = operation.succeeded
                    ? .loaded(offset: operation.byteOffset, length: operation.byteLength)
                    : .readFailed(offset: operation.byteOffset)

            case (.writeFailed, .write):
                violations.append(.writeWithoutPrecedingRead(index: index,
                                                             byteOffset: operation.byteOffset))
                state = .idle

            // --- a chunk is loaded, awaiting its write ---
            case (.loaded(let offset, _), .read):
                // NFR-REL-4: a second original read while the first chunk is still held.
                violations.append(.chunkOpenedWhilePreviousInFlight(
                    index: index, inFlightOffset: offset, newOffset: operation.byteOffset))
                state = operation.succeeded
                    ? .loaded(offset: operation.byteOffset, length: operation.byteLength)
                    : .readFailed(offset: operation.byteOffset)

            case (.loaded(let offset, let length), .write):
                if operation.byteOffset != offset || operation.byteLength != length {
                    violations.append(.writeDiffersFromRead(
                        index: index,
                        readOffset: offset, readLength: length,
                        writeOffset: operation.byteOffset, writeLength: operation.byteLength))
                }
                state = operation.succeeded
                    ? .written(offset: operation.byteOffset, length: operation.byteLength)
                    : .writeFailed(offset: operation.byteOffset)

            // --- written, awaiting the verify read ---
            case (.written(let offset, let length), .read):
                if operation.byteOffset != offset || operation.byteLength != length {
                    violations.append(.verifyReadDiffersFromWrite(
                        index: index,
                        writeOffset: offset, writeLength: length,
                        readOffset: operation.byteOffset, readLength: operation.byteLength))
                }
                state = .idle

            case (.written(let offset, _), .write):
                violations.append(.writtenTwiceWithoutVerify(index: index, byteOffset: offset))
                state = .idle
            }
        }

        switch state {
        case .loaded(let offset, _):
            violations.append(.incompleteCycleAtEnd(byteOffset: offset, wasWritten: false))
        case .written(let offset, _):
            violations.append(.incompleteCycleAtEnd(byteOffset: offset, wasWritten: true))
        case .idle, .readFailed, .writeFailed:
            break
        }

        return violations
    }

    /// The cycles that completed — read, write and verify read, all successful, all at the
    /// same place. Used to assert that a run tiled exactly the range it was given.
    static func completedCycles(_ operations: [DeviceOperation]) -> [CompletedCycle] {
        var cycles: [CompletedCycle] = []
        var index = 0

        while index + 2 < operations.count {
            let read = operations[index]
            let write = operations[index + 1]
            let verify = operations[index + 2]

            if read.kind == .read, write.kind == .write, verify.kind == .read,
               read.succeeded, write.succeeded, verify.succeeded,
               read.byteOffset == write.byteOffset, write.byteOffset == verify.byteOffset,
               read.byteLength == write.byteLength, write.byteLength == verify.byteLength {
                cycles.append(CompletedCycle(byteOffset: read.byteOffset,
                                             byteLength: read.byteLength))
                index += 3
            } else {
                index += 1
            }
        }
        return cycles
    }
}

// MARK: - Watching a run from a test

/// Records everything a run reports, and answers failures with a configurable disposition.
final class RecordingRunObserver: RunObserver {

    private(set) var start: RunStart?
    private(set) var completedChunks: [Chunk] = []
    private(set) var timings: [ChunkTiming] = []
    private(set) var failures: [BlockRangeFailure] = []
    private(set) var summary: RunSummary?

    /// What to answer when a failure arrives. Defaults to carrying on (FR-FAIL-4).
    var dispositionForFailure: (BlockRangeFailure) -> FailureDisposition = { _ in .continueRun }

    func runStarted(_ start: RunStart) { self.start = start }

    func chunkCompleted(_ chunk: Chunk, timing: ChunkTiming) {
        completedChunks.append(chunk)
        timings.append(timing)
    }

    func failureDetected(_ failure: BlockRangeFailure) -> FailureDisposition {
        failures.append(failure)
        return dispositionForFailure(failure)
    }

    func runFinished(_ summary: RunSummary) { self.summary = summary }
}

// MARK: - Deterministic, position-dependent test data

/// A seedable PRNG, because the non-destructiveness proof has to be reproducible.
///
/// `SystemRandomNumberGenerator` cannot be seeded, so a run that failed could not be re-run
/// on the same data. SplitMix64 is small, well-distributed, and its whole state is one
/// integer.
struct SplitMix64: RandomNumberGenerator {

    private var state: UInt64

    init(seed: UInt64) { self.state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

enum TestPattern {

    /// Fill every block of `device` with content derived from **its own block index**.
    ///
    /// Not merely random: the first eight bytes of each block are the block number, and the
    /// rest is a PRNG stream keyed by seed *and* index. So "block *k* holds block *k*'s
    /// pattern" is directly checkable, and a write that lands at the wrong offset is
    /// detectable by content rather than only by a whole-device digest.
    ///
    /// A uniform or repeating fill would not do: writing the wrong chunk to the wrong place
    /// would still compare equal, which is the same family of vacuity as comparing a buffer
    /// with itself.
    ///
    /// - Important: fills **through** `write`, so call it before injecting any faults — a
    ///   corruption fault injected first would corrupt the fill itself.
    static func fill(_ device: RawBlockDevice, seed: UInt64) throws {
        let blockSize = device.logicalBlockSize
        var block = UInt64(0)
        var scratch = [UInt8](repeating: 0, count: blockSize)

        while block < device.blockCount {
            write(block: block, seed: seed, into: &scratch)
            // Explicitly `-> Void`: `write` is `@discardableResult`, so without this the
            // closure returns its `Int` and `withUnsafeBytes`'s result reads as unused.
            try scratch.withUnsafeBytes { buffer -> Void in
                try device.write(buffer, atByteOffset: block * UInt64(blockSize))
            }
            block += 1
        }
    }

    /// The bytes block `index` should contain.
    static func block(_ index: UInt64, seed: UInt64, blockSize: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: blockSize)
        write(block: index, seed: seed, into: &bytes)
        return bytes
    }

    private static func write(block index: UInt64, seed: UInt64, into bytes: inout [UInt8]) {
        var generator = SplitMix64(seed: seed &* 0x9E37_79B9_7F4A_7C15 &+ index)

        // The block number in the clear, so a mis-addressed write is visible by eye in a
        // failure message and not only by comparison.
        let tag = index.bigEndian
        withUnsafeBytes(of: tag) { source in
            for offset in 0 ..< Swift.min(8, bytes.count) {
                bytes[offset] = source[offset]
            }
        }

        var offset = 8
        while offset < bytes.count {
            let word = generator.next()
            withUnsafeBytes(of: word) { source in
                for byte in 0 ..< Swift.min(8, bytes.count - offset) {
                    bytes[offset + byte] = source[byte]
                }
            }
            offset += 8
        }
    }
}

/// The first index at which two byte arrays differ, or `nil` if they are identical.
///
/// Used instead of `#expect(before == after)`: Swift Testing renders both operands on failure,
/// and these arrays are tens of megabytes.
func firstDifference(_ left: [UInt8], _ right: [UInt8]) -> Int? {
    if left.count != right.count { return Swift.min(left.count, right.count) }
    return left.withUnsafeBytes { lhs in
        right.withUnsafeBytes { rhs -> Int? in
            guard let l = lhs.baseAddress, let r = rhs.baseAddress else { return nil }
            guard memcmp(l, r, left.count) != 0 else { return nil }
            for index in 0 ..< left.count where lhs[index] != rhs[index] { return index }
            return nil
        }
    }
}
