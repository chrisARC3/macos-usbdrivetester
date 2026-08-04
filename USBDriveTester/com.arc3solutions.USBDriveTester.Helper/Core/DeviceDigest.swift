//
//  DeviceDigest.swift
//  Core — a fingerprint of what is on a device, so "nothing changed" can be checked.
//
//  Step 8 (AI-6), gate item 5. Satisfies nothing in the requirements directly: this is
//  *instrumentation*, and it exists because the run's own verify cannot answer the question the
//  gate asks.
//
//  ## Why the cycle's verify is not enough
//
//  FR-TEST-3's verify compares what came back **at the offset the cycle intended to write**. A
//  write that lands somewhere else is invisible to it. `RetentionCycleTests`'
//  `aMisdirectedWriteIsDetectedByTheSameAssertion` demonstrates exactly that in simulation: a
//  device that writes one block late corrupts the store, and only a whole-device comparison
//  catches it. A run can report "0 bad blocks" and still have moved data.
//
//  In simulation the comparison is `InMemoryBlockDevice.snapshot()`. On a 1 TB drive there is no
//  snapshot to take, so this is the equivalent — the same evidence, compressed to 32 bytes per
//  window.
//
//  ## Why this is in Core, and why it is not in `tools/media-digest`
//
//  It was going to be a separate process. Measured on hardware 2026-08-02: **it cannot be.**
//  With the helper holding `O_EXLOCK`, a second process — root, carrying Terminal's Full Disk
//  Access grant, requesting *no lock at all* — is refused `EBUSY`. So both fingerprints have to
//  be taken through the helper's own descriptor, which means this code runs inside the daemon.
//
//  And that is precisely why it is **here**, in Core, rather than in the helper: a fingerprint
//  taken by the same process on both sides of the cycle is only evidence if the fingerprint
//  function itself is known to work. A digest that returned a constant would make "before ==
//  after" pass unconditionally — a check that cannot fail, which this project has now caught
//  four times in other guises. Living in Core means it is unit-testable against
//  `InMemoryBlockDevice` with known content: known SHA-256 vectors, and a single flipped bit
//  producing a different digest, both with no hardware and no root.
//
//  ## CryptoKit, and Core's import rule
//
//  Core is Foundation-only by rule — no UIKit, no IOKit, no Dispatch, nothing privileged. This
//  file adds `CryptoKit`, deliberately. It does not weaken any of the reasons that rule exists:
//  CryptoKit is unprivileged, hardware-free, deterministic and fully testable off-device. The
//  rule is about keeping the algorithm pure and provable, not about the literal import list, and
//  hand-rolling SHA-256 to honour the letter of it would be a far worse trade.
//
//  ## What a digest is, and is not, for privacy
//
//  A SHA-256 is a fingerprint, not the data (NFR-SEC-6). It goes in a gate's output and in logs.
//  Note the one caveat honestly: a hash is an *oracle* — somebody who can already guess a
//  region's exact contents could confirm the guess. That is a negligible exposure next to a tool
//  whose whole job is reading the region, and it is not a route by which contents leave the host.
//

import Foundation
import CryptoKit

/// Fingerprints a range of a device.
public enum DeviceDigest {

    /// Bytes read per `read` call while digesting. A whole number of blocks at both supported
    /// geometries (NFR-COMPAT-5), and page-sized-aligned in practice via ``ChunkBuffers``.
    public static let defaultReadSizeBytes = 4 << 20

    /// Why a digest could not be taken.
    public enum Failure: Error, Equatable, CustomStringConvertible {

        /// The requested range is not entirely on the device.
        case rangeNotWithinDevice(startBlock: UInt64, blockCount: UInt64, deviceBlockCount: UInt64)

        /// A read failed. Carries the offset so a partial digest names where it stopped.
        case readFailed(atByteOffset: UInt64, length: Int)

        public var description: String {
            switch self {
            case .rangeNotWithinDevice(let start, let count, let deviceBlocks):
                return "Cannot digest blocks \(start)–\(start &+ count &- 1): the device has "
                     + "\(deviceBlocks) blocks."
            case .readFailed(let offset, let length):
                return "Cannot digest: reading \(length) bytes at offset \(offset) failed."
            }
        }
    }

    /// SHA-256 over `startBlock ..< startBlock + blockCount`, as lower-case hex.
    ///
    /// - Parameters:
    ///   - device: what to read. The same `RawBlockDevice` seam the cycle uses, so this works
    ///     identically against the simulated device and the real one.
    ///   - startBlock: first block to cover.
    ///   - blockCount: how many blocks. `0` is legal and yields the digest of the empty string,
    ///     which is a well-known constant and therefore a usable canary in its own right.
    ///   - readSizeBytes: transfer size. Only affects how the range is read, never the result —
    ///     `digestIsIndependentOfReadSize` pins that, because a digest that depended on it would
    ///     produce spurious differences between a run and its comparison.
    /// - Throws: ``Failure``.
    public static func sha256(of device: RawBlockDevice,
                              startBlock: UInt64,
                              blockCount: UInt64,
                              readSizeBytes: Int = DeviceDigest.defaultReadSizeBytes) throws -> String {

        guard startBlock <= device.blockCount,
              blockCount <= device.blockCount - startBlock else {
            throw Failure.rangeNotWithinDevice(startBlock: startBlock,
                                               blockCount: blockCount,
                                               deviceBlockCount: device.blockCount)
        }

        let blockSize = device.logicalBlockSize
        // Round the read size down to a whole number of blocks, and never below one block: raw
        // devices refuse misaligned lengths with EINVAL.
        let blocksPerRead = Swift.max(UInt64(1), UInt64(readSizeBytes / blockSize))

        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: Int(blocksPerRead) * blockSize)

        var covered: UInt64 = 0
        while covered < blockCount {
            let blocks = Swift.min(blocksPerRead, blockCount - covered)
            let byteCount = Int(blocks) * blockSize
            let offset = (startBlock + covered) * UInt64(blockSize)

            try buffer.withUnsafeMutableBytes { raw -> Void in
                let slice = UnsafeMutableRawBufferPointer(start: raw.baseAddress, count: byteCount)
                do {
                    try device.read(into: slice, atByteOffset: offset)
                } catch {
                    throw Failure.readFailed(atByteOffset: offset, length: byteCount)
                }
            }

            buffer.withUnsafeBytes { raw in
                hasher.update(bufferPointer: UnsafeRawBufferPointer(start: raw.baseAddress,
                                                                    count: byteCount))
            }

            covered += blocks
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
