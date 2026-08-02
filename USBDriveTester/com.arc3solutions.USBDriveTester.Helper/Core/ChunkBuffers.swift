//
//  ChunkBuffers.swift
//  Core — the two buffers a run owns, and the only two it will ever own.
//
//  Step 7 (AI-5), BUILD-PLAN 7.6. Satisfies NFR-PERF-1 (peak buffer memory ~2x the selected
//  I/O size) and the buffer half of NFR-PERF-2 (a bounded-memory stream of chunks, so a
//  multi-terabyte device is testable without proportional memory growth).
//
//  Pure Foundation. Allocation is `posix_memalign`, which is Darwin rather than IOKit or
//  privilege, so this stays inside Core's rule: no UIKit, no IOKit, no Dispatch, nothing
//  privileged, and fully testable with no hardware (NFR-MAINT-2).
//
//  ## The requirement is enforced by the shape of the type, not by a runtime check
//
//  `ChunkBuffers` has **no way to learn how big the device is.** Its initialiser takes an
//  I/O size and nothing else. So "memory must not scale with device capacity" is not a
//  property to be measured and hoped for — it is unrepresentable. A 1 TB device and a 22 TB
//  device produce byte-identical allocations because there is no parameter through which they
//  could differ.
//
//  That is the strongest form the guarantee can take, and it is worth stating because the
//  *other* half of NFR-PERF-2 was not written this way and quietly failed: Step 2's
//  `chunkPlan()` returned a materialised array, which is 9.1 MiB for `disk4` and 200.1 MiB
//  for `disk8`. Bounded buffers alongside an unbounded plan satisfied the gate's wording and
//  not its intent. See `RetentionTestEngine`, where the plan became lazy for the same reason.
//
//  ## Why exactly two
//
//  FR-TEST-3's cycle needs the original bytes held while the write-back and the verify read
//  happen: read original into A, write A back, read the result into B, compare A with B. A is
//  the *only* copy of the user's data during the write — which is also why NFR-REL-4 bounds
//  the in-flight data-loss window to exactly one chunk. A third buffer would widen that window
//  for no benefit; a shared buffer would destroy the comparison.
//
//  ## Page alignment is not decoration
//
//  Raw device I/O wants page-aligned buffers, and `pread`/`pwrite` against `/dev/rdiskN` can
//  otherwise take a slower bounce-buffer path in the kernel. 16,384 bytes on Apple Silicon
//  (measured). The alignment is asserted rather than assumed — `posix_memalign` guarantees
//  it, but a wrong alignment argument would be silently accepted as merely unhelpful.
//
//  ## Not thread-safe, deliberately
//
//  A run drives one device from a single task, matching the one-chunk-in-flight model
//  (NFR-REL-4) — the same contract `InMemoryBlockDevice` documents. Two tasks sharing these
//  buffers would be a correctness bug well before it was a data race.
//

import Foundation

/// Why a buffer pair could not be created.
public enum ChunkBufferError: Error, Equatable, CustomStringConvertible {

    /// The requested I/O size was zero or negative.
    case ioSizeNotPositive(ioSizeBytes: Int)

    /// The alignment was not a power of two, which `posix_memalign` requires.
    case alignmentNotAPowerOfTwo(alignment: Int)

    /// The allocator refused. Reported with its `errno` rather than as a generic failure: a
    /// run that cannot obtain 2 x I/O size of memory is in a situation the user can act on
    /// (close something, or choose a smaller I/O size).
    case allocationFailed(bytesRequested: Int, errnoCode: Int32)

    public var description: String {
        switch self {
        case .ioSizeNotPositive(let size):
            return "I/O size must be positive; got \(size) bytes."
        case .alignmentNotAPowerOfTwo(let alignment):
            return "Buffer alignment must be a power of two; got \(alignment)."
        case .allocationFailed(let bytes, let code):
            return "Could not allocate \(bytes) bytes for the run's buffers "
                 + "(errno \(code), \(String(cString: strerror(code)))). Try a smaller I/O "
                 + "size, or free memory and start again."
        }
    }
}

/// The original-read and verify-read buffers for a run, allocated once and reused for every
/// chunk.
public final class ChunkBuffers {

    /// Capacity of each buffer, in bytes — the run's fixed I/O size (FR-CTRL-8).
    public let capacityBytes: Int

    /// Byte alignment both allocations satisfy.
    public let alignment: Int

    /// Holds the bytes read from the device, and — unchanged — the bytes written back to it
    /// (FR-TEST-7: the data read is the only data written).
    private let originalStorage: UnsafeMutableRawPointer

    /// Holds the re-read used for the verify comparison.
    private let verifyStorage: UnsafeMutableRawPointer

    /// Number of buffers a run allocates. Two, always (NFR-PERF-1).
    public static let bufferCount = 2

    /// Total bytes held by this pair — `bufferCount * capacityBytes`, and independent of the
    /// device by construction.
    public var totalAllocatedBytes: Int { Self.bufferCount * capacityBytes }

    /// Allocate the pair.
    ///
    /// - Parameters:
    ///   - ioSizeBytes: the run's fixed I/O size. In production one of {1, 2, 4, 8} MiB
    ///     (FR-CTRL-8); any positive value is accepted so tests can use awkward sizes.
    ///   - alignment: byte alignment for both buffers; defaults to the page size.
    /// - Throws: ``ChunkBufferError``.
    public init(ioSizeBytes: Int, alignment: Int = Int(getpagesize())) throws {
        guard ioSizeBytes > 0 else {
            throw ChunkBufferError.ioSizeNotPositive(ioSizeBytes: ioSizeBytes)
        }
        guard alignment > 0, alignment & (alignment - 1) == 0 else {
            throw ChunkBufferError.alignmentNotAPowerOfTwo(alignment: alignment)
        }

        func allocate() throws -> UnsafeMutableRawPointer {
            var pointer: UnsafeMutableRawPointer?
            let result = posix_memalign(&pointer, alignment, ioSizeBytes)
            guard result == 0, let pointer else {
                // posix_memalign returns the error directly rather than setting errno.
                throw ChunkBufferError.allocationFailed(bytesRequested: ioSizeBytes,
                                                        errnoCode: result)
            }
            return pointer
        }

        let original = try allocate()
        do {
            verifyStorage = try allocate()
        } catch {
            // The first allocation must not leak because the second failed.
            free(original)
            throw error
        }
        originalStorage = original

        self.capacityBytes = ioSizeBytes
        self.alignment = alignment

        ChunkBuffers.recordAllocation(bytes: Self.bufferCount * ioSizeBytes)
    }

    deinit {
        // Wipe before releasing. These buffers hold the contents of somebody's drive, and this
        // process runs as root; the pages are not handed to another process without the kernel
        // zeroing them first, so this is hygiene rather than a boundary — but it is cheap, it
        // happens once, and NFR-SEC-6's posture is that device contents go nowhere they are
        // not needed.
        memset_s(originalStorage, capacityBytes, 0, capacityBytes)
        memset_s(verifyStorage, capacityBytes, 0, capacityBytes)

        free(originalStorage)
        free(verifyStorage)

        ChunkBuffers.recordDeallocation(bytes: Self.bufferCount * capacityBytes)
    }

    // MARK: Access

    /// The full original-read buffer.
    public var original: UnsafeMutableRawBufferPointer {
        UnsafeMutableRawBufferPointer(start: originalStorage, count: capacityBytes)
    }

    /// The full verify-read buffer.
    public var verify: UnsafeMutableRawBufferPointer {
        UnsafeMutableRawBufferPointer(start: verifyStorage, count: capacityBytes)
    }

    /// The first `byteCount` bytes of the original-read buffer.
    ///
    /// Needed because the **final chunk is shorter than the I/O size** (FR-TEST-5): the
    /// device is an integer number of blocks, and the last chunk is the exact remainder —
    /// 3,504 blocks for `disk4`, 8,191 for `disk8`, both measured. Reading a full `ioSize`
    /// there would run past the end of the device and be refused.
    public func original(byteCount: Int) -> UnsafeMutableRawBufferPointer {
        precondition(byteCount >= 0 && byteCount <= capacityBytes,
                     "requested \(byteCount) bytes from a \(capacityBytes)-byte buffer")
        return UnsafeMutableRawBufferPointer(start: originalStorage, count: byteCount)
    }

    /// The first `byteCount` bytes of the verify-read buffer. See ``original(byteCount:)``.
    public func verify(byteCount: Int) -> UnsafeMutableRawBufferPointer {
        precondition(byteCount >= 0 && byteCount <= capacityBytes,
                     "requested \(byteCount) bytes from a \(capacityBytes)-byte buffer")
        return UnsafeMutableRawBufferPointer(start: verifyStorage, count: byteCount)
    }

    /// Are both buffers aligned as requested?
    ///
    /// `posix_memalign` guarantees this, so the check is not defensive about the allocator —
    /// it is about the *argument*. An alignment that is silently unhelpful (say 8 bytes on a
    /// path that wanted pages) would produce correct results and slower I/O, which is exactly
    /// the kind of thing that never gets noticed.
    public var isCorrectlyAligned: Bool {
        UInt(bitPattern: originalStorage) % UInt(alignment) == 0
            && UInt(bitPattern: verifyStorage) % UInt(alignment) == 0
    }

    // MARK: Instrumentation (NFR-PERF-1's gate item)

    private static let accounting = NSLock()
    private static var liveBytes = 0
    private static var peakBytes = 0

    /// Bytes currently held by all live ``ChunkBuffers`` in this process.
    public static var liveAllocatedBytes: Int {
        accounting.withLock { liveBytes }
    }

    /// The high-water mark since the last ``resetPeakAllocatedBytes()``.
    ///
    /// This is what BUILD-PLAN 7.6's gate asks to be instrumented and confirmed: peak buffer
    /// memory ~2x the I/O size regardless of device size.
    public static var peakAllocatedBytes: Int {
        accounting.withLock { peakBytes }
    }

    /// Reset the high-water mark to the currently live total.
    public static func resetPeakAllocatedBytes() {
        accounting.withLock { peakBytes = liveBytes }
    }

    private static func recordAllocation(bytes: Int) {
        accounting.withLock {
            liveBytes += bytes
            if liveBytes > peakBytes { peakBytes = liveBytes }
        }
    }

    private static func recordDeallocation(bytes: Int) {
        accounting.withLock { liveBytes -= bytes }
    }
}
