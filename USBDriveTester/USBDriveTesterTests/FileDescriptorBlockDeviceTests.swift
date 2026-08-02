//
//  FileDescriptorBlockDeviceTests.swift
//  The real RawBlockDevice, exercised against a temporary file.
//
//  ## What this file is allowed to claim
//
//  A temporary file is a substitute for a raw device, and this project's recurring defect is a
//  substitute's result being reported as the real thing's. So the boundary is stated up front
//  and the tests are named to respect it:
//
//    * A regular file **accepts misaligned reads happily**. So a test showing a misaligned
//      request throws does prove this device's guard fired — precisely because the backing
//      file would not have objected on its own.
//    * What no test here can show is that the guard is **necessary**: that `/dev/rdiskN` would
//      have refused with `EINVAL`. That is a fact about hardware and it is on Step 7's gate.
//
//  The same split applies to short transfers: a file shorter than its declared geometry
//  produces one on demand, which exercises the resumption path — but whether a USB bridge ever
//  produces one at 4 or 8 MiB was answered on hardware instead (it does not; measured
//  2026-08-02, `extraIterations=0` at both sizes).
//

import Testing
import Foundation

struct FileDescriptorBlockDeviceTests {

    // MARK: - Fixture

    /// A temp file sized to `blockSize * blockCount`, opened `O_RDWR`, wrapped, and cleaned up.
    ///
    /// `fileSizeBytes` can be given smaller than the declared geometry to manufacture a short
    /// transfer — the one failure this substitute can produce on demand.
    private func withTemporaryDevice(
        blockSize: UInt32 = 512,
        blockCount: UInt64 = 64,
        fileSizeBytes: UInt64? = nil,
        _ body: (FileDescriptorBlockDevice, Int32) throws -> Void
    ) throws {
        var template = Array(
            (NSTemporaryDirectory() + "usbdrivetester-fdbd-XXXXXX").utf8CString)
        let fd = template.withUnsafeMutableBufferPointer { mkstemp($0.baseAddress!) }
        try #require(fd >= 0, "mkstemp failed: errno \(errno)")

        let path = String(cString: template)
        defer {
            close(fd)
            unlink(path)
        }

        let size = fileSizeBytes ?? (blockCount * UInt64(blockSize))
        try #require(ftruncate(fd, off_t(size)) == 0, "ftruncate failed: errno \(errno)")

        let device = try FileDescriptorBlockDevice(
            fileDescriptor: fd,
            geometry: DeviceGeometry(logicalBlockSize: blockSize, blockCount: blockCount))
        try body(device, fd)
    }

    private func pattern(_ byteCount: Int, seed: UInt8) -> [UInt8] {
        (0 ..< byteCount).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ Int(seed)) }
    }

    // MARK: - Round trips, both required geometries (NFR-COMPAT-5)

    @Test(arguments: [UInt32(512), UInt32(4096)])
    func roundTripsAtBothSupportedBlockSizes(blockSize: UInt32) throws {
        try withTemporaryDevice(blockSize: blockSize, blockCount: 16) { device, _ in
            let length = Int(blockSize) * 4
            let offset = UInt64(blockSize) * 8
            var source = pattern(length, seed: 0x5A)

            let written = try source.withUnsafeBytes {
                try device.write($0, atByteOffset: offset)
            }
            #expect(written == length)

            var destination = [UInt8](repeating: 0, count: length)
            let read = try destination.withUnsafeMutableBytes {
                try device.read(into: $0, atByteOffset: offset)
            }
            #expect(read == length)
            #expect(destination == source)
            #expect(device.lastFailure == nil)
            _ = source.count
        }
    }

    @Test func geometryIsReportedThroughTheProtocol() throws {
        try withTemporaryDevice(blockSize: 4096, blockCount: 100) { device, _ in
            #expect(device.logicalBlockSize == 4096)
            #expect(device.blockCount == 100)
            #expect(device.byteCount == 409_600)
        }
    }

    // MARK: - The guards fire before the syscall

    /// The backing file would have accepted this. That it throws is the proof the guard ran.
    @Test func aMisalignedOffsetIsRefusedEvenThoughAFileWouldAllowIt() throws {
        try withTemporaryDevice(blockSize: 512, blockCount: 64) { device, fd in
            var buffer = [UInt8](repeating: 0, count: 512)

            #expect(throws: DeviceIOError.misaligned(atByteOffset: 100, length: 512,
                                                      logicalBlockSize: 512)) {
                _ = try buffer.withUnsafeMutableBytes {
                    try device.read(into: $0, atByteOffset: 100)
                }
            }

            // Same request straight to the file succeeds — which is exactly why the guard
            // cannot be left to the backing store.
            let direct = buffer.withUnsafeMutableBytes {
                pread(fd, $0.baseAddress!, 512, 100)
            }
            #expect(direct == 512, "a regular file accepts the misaligned read the guard refused")
        }
    }

    @Test func aMisalignedLengthIsRefused() throws {
        try withTemporaryDevice(blockSize: 512, blockCount: 64) { device, _ in
            var buffer = [UInt8](repeating: 0, count: 700)      // not a multiple of 512
            #expect(throws: DeviceIOError.misaligned(atByteOffset: 0, length: 700,
                                                      logicalBlockSize: 512)) {
                _ = try buffer.withUnsafeMutableBytes {
                    try device.read(into: $0, atByteOffset: 0)
                }
            }
        }
    }

    @Test func aRequestPastTheEndOfTheDeviceIsRefused() throws {
        try withTemporaryDevice(blockSize: 512, blockCount: 64) { device, _ in
            var buffer = [UInt8](repeating: 0, count: 1024)
            let deviceBytes: UInt64 = 64 * 512

            // Starts inside, runs past the end.
            #expect(throws: DeviceIOError.outOfRange(atByteOffset: deviceBytes - 512,
                                                      length: 1024,
                                                      deviceByteCount: deviceBytes)) {
                _ = try buffer.withUnsafeMutableBytes {
                    try device.read(into: $0, atByteOffset: deviceBytes - 512)
                }
            }

            // Starts at the end.
            #expect(throws: DeviceIOError.outOfRange(atByteOffset: deviceBytes,
                                                      length: 1024,
                                                      deviceByteCount: deviceBytes)) {
                _ = try buffer.withUnsafeMutableBytes {
                    try device.read(into: $0, atByteOffset: deviceBytes)
                }
            }
        }
    }

    /// The arithmetic an out-of-range request would use to look in-range.
    @Test func anOffsetThatOverflowsOnAdditionIsRefused() throws {
        try withTemporaryDevice(blockSize: 512, blockCount: 64) { device, _ in
            var buffer = [UInt8](repeating: 0, count: 512)
            let nearMax = UInt64.max - 511                       // 512-aligned
            #expect(throws: (any Error).self) {
                _ = try buffer.withUnsafeMutableBytes {
                    try device.read(into: $0, atByteOffset: nearMax)
                }
            }
        }
    }

    /// Geometry is checked once, at construction — it cannot change under a held exclusive open.
    @Test func implausibleGeometryIsRefusedAtConstruction() throws {
        try withTemporaryDevice { _, fd in
            #expect(throws: RunParameterRejection.unsupportedBlockSize(1024)) {
                _ = try FileDescriptorBlockDevice(
                    fileDescriptor: fd,
                    geometry: DeviceGeometry(logicalBlockSize: 1024, blockCount: 10))
            }
            #expect(throws: RunParameterRejection.emptyDevice) {
                _ = try FileDescriptorBlockDevice(
                    fileDescriptor: fd,
                    geometry: DeviceGeometry(logicalBlockSize: 512, blockCount: 0))
            }
        }
    }

    // MARK: - Zero-length, matching InMemoryBlockDevice

    /// The engine runs against both conformances, so they must agree on the edge cases too.
    @Test func aZeroLengthRequestMovesNothingAndSucceeds() throws {
        try withTemporaryDevice(blockSize: 512, blockCount: 64) { device, _ in
            var empty = [UInt8]()
            let read = try empty.withUnsafeMutableBytes {
                try device.read(into: $0, atByteOffset: 512)
            }
            #expect(read == 0)

            let written = try empty.withUnsafeBytes {
                try device.write($0, atByteOffset: 512)
            }
            #expect(written == 0)

            // The in-memory device agrees.
            let simulated = InMemoryBlockDevice(logicalBlockSize: 512, blockCount: 64)
            let simulatedRead = try empty.withUnsafeMutableBytes {
                try simulated.read(into: $0, atByteOffset: 512)
            }
            #expect(simulatedRead == 0)
        }
    }

    /// A zero-length request still has to name a legal place.
    @Test func aZeroLengthRequestAtAMisalignedOffsetIsStillRefused() throws {
        try withTemporaryDevice(blockSize: 512, blockCount: 64) { device, _ in
            var empty = [UInt8]()
            #expect(throws: DeviceIOError.misaligned(atByteOffset: 7, length: 0,
                                                      logicalBlockSize: 512)) {
                _ = try empty.withUnsafeMutableBytes {
                    try device.read(into: $0, atByteOffset: 7)
                }
            }
        }
    }

    // MARK: - Failure paths

    /// A file shorter than its declared geometry: the read runs out of data mid-request, which
    /// is the resumption path's failure exit.
    @Test func readingPastTheEndOfTheBackingStoreIsAShortTransfer() throws {
        // Declared 64 blocks, backed by only 32 blocks of file.
        try withTemporaryDevice(blockSize: 512, blockCount: 64, fileSizeBytes: 32 * 512) { device, _ in
            var buffer = [UInt8](repeating: 0, count: 4096)
            let offset: UInt64 = 30 * 512                        // 2 blocks of file remain

            #expect(throws: DeviceIOError.shortTransfer(atByteOffset: offset,
                                                         expected: 4096, actual: 1024)) {
                _ = try buffer.withUnsafeMutableBytes {
                    try device.read(into: $0, atByteOffset: offset)
                }
            }

            let failure = try #require(device.lastFailure)
            #expect(failure.operation == "read")
            #expect(failure.bytesTransferred == 1024)
            #expect(failure.errnoCode == 0, "a partial transfer is not an errno failure")
            #expect(failure.description.contains("no error reported"))
        }
    }

    /// A closed descriptor is `EBADF`. The thrown error classifies; `lastFailure` diagnoses.
    @Test func aBadDescriptorSurfacesAsAReadErrorCarryingItsErrno() throws {
        let device = try FileDescriptorBlockDevice(
            fileDescriptor: -1,
            geometry: DeviceGeometry(logicalBlockSize: 512, blockCount: 64))

        var buffer = [UInt8](repeating: 0, count: 512)
        #expect(throws: DeviceIOError.readError(atByteOffset: 0, length: 512)) {
            _ = try buffer.withUnsafeMutableBytes {
                try device.read(into: $0, atByteOffset: 0)
            }
        }

        let failure = try #require(device.lastFailure)
        #expect(failure.errnoCode == EBADF)
        #expect(failure.bytesTransferred == 0)
        #expect(failure.description.contains("errno \(EBADF)"))
    }

    @Test func aWriteToABadDescriptorSurfacesAsAWriteError() throws {
        let device = try FileDescriptorBlockDevice(
            fileDescriptor: -1,
            geometry: DeviceGeometry(logicalBlockSize: 512, blockCount: 64))

        let source = [UInt8](repeating: 0xEE, count: 512)
        #expect(throws: DeviceIOError.writeError(atByteOffset: 0, length: 512)) {
            _ = try source.withUnsafeBytes {
                try device.write($0, atByteOffset: 0)
            }
        }
        #expect(device.lastFailure?.operation == "write")
    }

    // MARK: - 64-bit offsets, through a real syscall (NFR-COMPAT-6)

    /// `disk4` is below 2³² blocks and cannot exercise this; `disk8` can but is out of scope by
    /// user decision. A sparse file can, and it costs no disk space — the offset here is 5 GiB,
    /// comfortably past the 4.295 GB that a 32-bit byte offset would wrap at.
    @Test func offsetsBeyondThirtyTwoBitsAddressCorrectly() throws {
        let blockSize: UInt32 = 512
        let fiveGiB: UInt64 = 5 * 1024 * 1024 * 1024
        let blocks = fiveGiB / UInt64(blockSize) + 16

        try withTemporaryDevice(blockSize: blockSize, blockCount: blocks) { device, fd in
            #expect(fiveGiB > UInt64(UInt32.max), "the offset must actually exceed 2^32")

            var source = pattern(512, seed: 0xC3)
            _ = try source.withUnsafeBytes { try device.write($0, atByteOffset: fiveGiB) }

            var destination = [UInt8](repeating: 0, count: 512)
            _ = try destination.withUnsafeMutableBytes {
                try device.read(into: $0, atByteOffset: fiveGiB)
            }
            #expect(destination == source)

            // Nothing landed at the wrapped 32-bit offset, which is what a truncated offset
            // would have written to.
            let wrapped = fiveGiB & 0xFFFF_FFFF
            var atWrapped = [UInt8](repeating: 0xFF, count: 512)
            _ = try atWrapped.withUnsafeMutableBytes {
                try device.read(into: $0, atByteOffset: wrapped - (wrapped % 512))
            }
            #expect(atWrapped.allSatisfy { $0 == 0 }, "a 32-bit wrap would have written here")
            _ = fd
        }
    }

    // MARK: - It must not close the descriptor

    /// Closing it would be worse than a leak: releasing an exclusive open makes DiskArbitration
    /// remount the volume ~4 ms later (measured 2026-08-01), silently undoing the user's
    /// unmount while a run is writing. The absence of a `deinit` is the guarantee; this is what
    /// would fail if one were ever added.
    @Test func theDescriptorSurvivesTheDeviceBeingDeallocated() throws {
        var template = Array((NSTemporaryDirectory() + "usbdrivetester-own-XXXXXX").utf8CString)
        let fd = template.withUnsafeMutableBufferPointer { mkstemp($0.baseAddress!) }
        try #require(fd >= 0)
        let path = String(cString: template)
        defer { close(fd); unlink(path) }
        try #require(ftruncate(fd, 64 * 512) == 0)

        do {
            let device = try FileDescriptorBlockDevice(
                fileDescriptor: fd,
                geometry: DeviceGeometry(logicalBlockSize: 512, blockCount: 64))
            var buffer = [UInt8](repeating: 0, count: 512)
            _ = try buffer.withUnsafeMutableBytes { try device.read(into: $0, atByteOffset: 0) }
        }   // device deallocated here

        // Still usable: the device borrowed the descriptor, it did not take it.
        var probe = [UInt8](repeating: 0, count: 512)
        let result = probe.withUnsafeMutableBytes { pread(fd, $0.baseAddress!, 512, 0) }
        #expect(result == 512, "the descriptor was closed by the device — it must not be")
    }

    // MARK: - Behavioural agreement with the simulated device

    /// The engine is written once and runs against both conformances, so a divergence here
    /// would mean the simulation proof of Step 8 does not describe the hardware path.
    @Test func theTwoConformancesAgreeOnASequenceOfOperations() throws {
        try withTemporaryDevice(blockSize: 512, blockCount: 64) { real, _ in
            let simulated = InMemoryBlockDevice(logicalBlockSize: 512, blockCount: 64)

            #expect(real.logicalBlockSize == simulated.logicalBlockSize)
            #expect(real.blockCount == simulated.blockCount)
            #expect(real.byteCount == simulated.byteCount)

            for block in [0, 7, 63] {
                let offset = UInt64(block) * 512
                var source = pattern(512, seed: UInt8(block))

                _ = try source.withUnsafeBytes { try real.write($0, atByteOffset: offset) }
                _ = try source.withUnsafeBytes { try simulated.write($0, atByteOffset: offset) }

                var fromReal = [UInt8](repeating: 0, count: 512)
                var fromSimulated = [UInt8](repeating: 0, count: 512)
                _ = try fromReal.withUnsafeMutableBytes { try real.read(into: $0, atByteOffset: offset) }
                _ = try fromSimulated.withUnsafeMutableBytes { try simulated.read(into: $0, atByteOffset: offset) }

                #expect(fromReal == source)
                #expect(fromReal == fromSimulated)
            }
        }
    }
}
