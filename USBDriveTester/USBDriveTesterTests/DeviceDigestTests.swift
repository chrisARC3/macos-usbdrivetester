//
//  DeviceDigestTests.swift
//  Proof that the fingerprint the hardware gate rests on ACTUALLY READS THE DEVICE.
//
//  ## Why this file is load-bearing
//
//  Step 8's gate item 5 compares a fingerprint of `disk4` taken before the cycle with one taken
//  after, and requires them to be identical. Measured on hardware 2026-08-02, both fingerprints
//  have to be taken by the **helper**, through its own descriptor: while it holds `O_EXLOCK`, a
//  second process — root, carrying Terminal's Full Disk Access grant, requesting no lock at all
//  — is refused `EBUSY`.
//
//  That leaves a hole nothing on the hardware side can close. If `DeviceDigest.sha256` returned
//  a **constant**, "before == after" would pass unconditionally, on any drive, however badly the
//  cycle had corrupted it. The gate would be a check that cannot fail — the exact defect this
//  project has now caught in a probe that printed a verdict from the wrong phase, in a guard
//  that reported "assertion deleted" when it could not find the file, in an FR-TEST-9 timing
//  check that could not discriminate on a raw character device, and in an engine that reset a
//  counter another suite was asserting on.
//
//  So the digest is pinned here against **externally computed** SHA-256 values. Every constant
//  below came from Python's `hashlib` over the identical byte sequence, not from running this
//  code and recording what it said — which would pin the implementation to itself and prove
//  nothing.
//
//  The gate adds a cheap corroboration on hardware as well: a real device must not fingerprint
//  to one repeated value across all its windows. That catches a constant digest in production
//  too, but it is weaker (an all-zero region legitimately repeats), so the real proof is here.
//

import Testing
import Foundation
@testable import USBDriveTester

struct DeviceDigestTests {

    // MARK: Fixtures

    /// A device whose block *k* is filled with the byte value *k*. Position-dependent, so a
    /// digest that read the wrong place, or read nothing, cannot match by accident.
    private func device(blockSize: Int, blocks: UInt64) throws -> InMemoryBlockDevice {
        let device = InMemoryBlockDevice(logicalBlockSize: blockSize, blockCount: blocks)
        for block in 0 ..< blocks {
            let content = [UInt8](repeating: UInt8(block & 0xFF), count: blockSize)
            try content.withUnsafeBytes { buffer -> Void in
                try device.write(buffer, atByteOffset: block * UInt64(blockSize))
            }
        }
        return device
    }

    // MARK: Known answers, computed elsewhere

    /// `hashlib.sha256(b'')` — the well-known empty digest.
    @Test func anEmptyRangeHashesToTheEmptyDigest() throws {
        let device = try self.device(blockSize: 512, blocks: 4)
        let hex = try DeviceDigest.sha256(of: device, startBlock: 0, blockCount: 0)
        #expect(hex == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    /// `hashlib.sha256(bytes(2048))`.
    @Test func anAllZeroDeviceMatchesTheExternallyComputedDigest() throws {
        let device = InMemoryBlockDevice(logicalBlockSize: 512, blockCount: 4)
        let hex = try DeviceDigest.sha256(of: device, startBlock: 0, blockCount: 4)
        #expect(hex == "e5a00aa9991ac8a5ee3109844d84a55583bd20572ad3ffcd42792f3c36b183ad")
    }

    /// `hashlib.sha256(b''.join(bytes([k])*512 for k in range(4)))`.
    @Test func aPositionDependentDeviceMatchesTheExternallyComputedDigest() throws {
        let device = try self.device(blockSize: 512, blocks: 4)
        let hex = try DeviceDigest.sha256(of: device, startBlock: 0, blockCount: 4)
        #expect(hex == "9a62d6c7b90b4ff89818c67f5b5fb93f6b11d80a26b64cb04d4c33309c63025d")
    }

    /// The other supported geometry (NFR-COMPAT-5). Different block size, different content,
    /// different answer — and both externally computed.
    @Test func the4096ByteGeometryMatchesItsOwnExternallyComputedDigest() throws {
        let device = try self.device(blockSize: 4096, blocks: 4)
        let hex = try DeviceDigest.sha256(of: device, startBlock: 0, blockCount: 4)
        #expect(hex == "25e79343a4ddebe0ce23672d43680b9598b78a3e906dc261dc0d43a15a59e177")
    }

    // MARK: It reads the range it was asked for, and only that range

    /// `hashlib.sha256(bytes([1])*512)`.
    @Test func asubRangeCoversExactlyThatSubRange() throws {
        let device = try self.device(blockSize: 512, blocks: 4)
        let hex = try DeviceDigest.sha256(of: device, startBlock: 1, blockCount: 1)
        #expect(hex == "6caf38d537984e261527b8caef5f990fb91415a1db917198821a79ed28997973")
    }

    /// `hashlib.sha256(bytes([1])*512 + bytes([2])*512)`.
    @Test func aTwoBlockSubRangeCoversExactlyThoseTwoBlocks() throws {
        let device = try self.device(blockSize: 512, blocks: 4)
        let hex = try DeviceDigest.sha256(of: device, startBlock: 1, blockCount: 2)
        #expect(hex == "2ddfe0faea440b60d8945f30cee07b2a1eae8d5cab910494889fbc263c524ffe")
    }

    @Test func differentSubRangesOfTheSameDeviceDiffer() throws {
        let device = try self.device(blockSize: 512, blocks: 4)
        let first = try DeviceDigest.sha256(of: device, startBlock: 0, blockCount: 1)
        let second = try DeviceDigest.sha256(of: device, startBlock: 1, blockCount: 1)
        #expect(first != second)
    }

    // MARK: The property the gate depends on

    /// **This is the one the gate rests on.** A single flipped bit, in one block, must change
    /// the digest — and to the value an external tool computes for the same corrupted bytes,
    /// not merely to *some* different value.
    ///
    /// `flipped = bytearray(dev); flipped[2*512] ^= 0x01`
    @Test func oneFlippedBitChangesTheDigestToTheExternallyComputedValue() throws {
        let device = try self.device(blockSize: 512, blocks: 4)
        let before = try DeviceDigest.sha256(of: device, startBlock: 0, blockCount: 4)

        // Flip the low bit of the first byte of block 2 — the same corruption
        // `InMemoryBlockDevice.injectSilentCorruption` applies.
        var block2 = [UInt8](repeating: 2, count: 512)
        block2[0] ^= 0x01
        try block2.withUnsafeBytes { buffer -> Void in
            try device.write(buffer, atByteOffset: 2 * 512)
        }

        let after = try DeviceDigest.sha256(of: device, startBlock: 0, blockCount: 4)
        #expect(after != before, "a flipped bit did not change the digest")
        #expect(after == "f40d89ca97b479b30cf4231a6d6b9103904f08368de6cca01c705c223a259a6c")
    }

    /// A digest that varied with how the range was read would produce spurious differences
    /// between a before-pass and an after-pass, which is the only comparison it is used for.
    @Test func theDigestIsIndependentOfTheReadSize() throws {
        let device = try self.device(blockSize: 512, blocks: 64)
        let reference = try DeviceDigest.sha256(of: device, startBlock: 0, blockCount: 64)

        for readSize in [512, 1_024, 4_096, 32_768, 1 << 20] {
            let hex = try DeviceDigest.sha256(of: device, startBlock: 0, blockCount: 64,
                                              readSizeBytes: readSize)
            #expect(hex == reference, "read size \(readSize) produced a different digest")
        }
    }

    /// A read size smaller than one block must not produce a misaligned request — raw devices
    /// refuse those with `EINVAL`, and the simulated device throws `misaligned`.
    @Test func aReadSizeBelowOneBlockStillWorks() throws {
        let device = try self.device(blockSize: 4096, blocks: 4)
        let hex = try DeviceDigest.sha256(of: device, startBlock: 0, blockCount: 4,
                                          readSizeBytes: 1)
        #expect(hex == "25e79343a4ddebe0ce23672d43680b9598b78a3e906dc261dc0d43a15a59e177")
    }

    // MARK: Refusals

    @Test func arangePastTheEndOfTheDeviceIsRefused() throws {
        let device = try self.device(blockSize: 512, blocks: 4)
        #expect(throws: DeviceDigest.Failure.rangeNotWithinDevice(startBlock: 2,
                                                                  blockCount: 3,
                                                                  deviceBlockCount: 4)) {
            _ = try DeviceDigest.sha256(of: device, startBlock: 2, blockCount: 3)
        }
    }

    @Test func astartPastTheEndOfTheDeviceIsRefused() throws {
        let device = try self.device(blockSize: 512, blocks: 4)
        #expect(throws: DeviceDigest.Failure.rangeNotWithinDevice(startBlock: 9,
                                                                  blockCount: 1,
                                                                  deviceBlockCount: 4)) {
            _ = try DeviceDigest.sha256(of: device, startBlock: 9, blockCount: 1)
        }
    }

    /// The exact final block is legal — an off-by-one here would make the last window of every
    /// device unfingerprintable.
    @Test func theExactFinalBlockIsLegal() throws {
        let device = try self.device(blockSize: 512, blocks: 4)
        let hex = try DeviceDigest.sha256(of: device, startBlock: 3, blockCount: 1)
        #expect(!hex.isEmpty)
    }

    @Test func areadFailureIsReportedWithItsOffset() throws {
        let device = try self.device(blockSize: 512, blocks: 8)
        device.injectReadFault(blocks: 4 ..< 5)

        #expect(throws: DeviceDigest.Failure.readFailed(atByteOffset: 4 * 512, length: 512)) {
            _ = try DeviceDigest.sha256(of: device, startBlock: 0, blockCount: 8,
                                        readSizeBytes: 512)
        }
    }
}
