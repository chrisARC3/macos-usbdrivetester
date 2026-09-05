//
//  FileDescriptorBlockDevice.swift
//  Core — the real `RawBlockDevice`: block-aligned `pread`/`pwrite` over an open descriptor.
//
//  Step 7 (AI-5), BUILD-PLAN 7.4. Satisfies FR-TEST-6's I/O half and NFR-COMPAT-6 (64-bit
//  offsets and counts throughout), and is the implementation Step 8's cycle runs against on
//  hardware — the same engine, the same protocol, the other conformance being
//  `InMemoryBlockDevice`.
//
//  Pure Foundation: `pread`/`pwrite` are Darwin, not IOKit and not privileged, so this stays
//  inside Core's rule and is unit-testable with no hardware and no root (NFR-MAINT-2).
//
//  ## It does not own the descriptor, and must never close it
//
//  The descriptor belongs to the helper's `AcquiredDevice`, which opened it
//  `O_RDWR | O_EXLOCK | O_NONBLOCK` as one half of Step 6's mount guard and closes it in
//  `release()`. Closing it here would be worse than a leak: measured 2026-08-01, releasing an
//  exclusive open makes DiskArbitration re-probe the media and remount the volume ~4 ms later
//  — silently undoing the user's unmount mid-run, while a run is writing. This type borrows
//  the descriptor for the duration of the run and has no `deinit` for exactly that reason.
//
//  ## What a file-backed test proves, and what it cannot
//
//  This type works against any descriptor, so its tests run against a temporary file. That is
//  a substitute, and this project's standing lesson is that a substitute's result is never the
//  real thing's result — so the boundary is stated here rather than discovered later:
//
//  | Proven by the file-backed tests | Left to the hardware gate |
//  |---|---|
//  | The transfer loop and short-transfer resumption | That a raw device *requires* the alignment this guard enforces (`EINVAL`) |
//  | 64-bit offset arithmetic, through a real `pread` | That the USB bridge answers a 4 MiB `pread` whole |
//  | `errno` mapping onto `DeviceIOError` | That `F_NOCACHE` is in force on the descriptor |
//  | That the alignment and range guards fire before any syscall | Geometry matching `diskutil` |
//  | That `ENXIO` maps to `deviceLost` and nothing else does | That a de-enumerated device actually returns `ENXIO` |
//
//  The last row is Step 12's, and its right-hand side is the one claim here that has already
//  been observed rather than assumed: on 2026-08-06 the scratch drive left the bus mid-gate and
//  this code saw `errno 6` on every read including offset 0. One observation is not a gate, so
//  it stays on the right of the line until Step 12's hardware gate unplugs a drive on purpose.
//
//  The distinction in the alignment row is worth being exact about, because it is easy to
//  state too strongly in either direction. A regular file accepts misaligned reads perfectly
//  happily — so a test showing a misaligned request *throws* does prove this guard fired,
//  precisely because the backing file would not have objected on its own. What no file-backed
//  test can show is that the guard is **necessary**: that a raw device would have refused. The
//  guard's correctness is testable here; its necessity is a fact about hardware, and it is on
//  Step 7's gate.
//
//  ## Alignment and range are not re-derived here
//
//  Both are delegated to `RunParameterValidator`, which Step 3 wrote and which Step 7 fed with
//  ioctl geometry. A second copy of those rules living next to the syscalls is how the two
//  drift apart, and the copy that would matter is whichever one is looser.
//
//  ## Not thread-safe, deliberately
//
//  One run, one device, one task — the same contract `InMemoryBlockDevice` documents, and what
//  the one-chunk-in-flight model requires (NFR-REL-4).
//

import Foundation

/// A `RawBlockDevice` backed by an already-open file descriptor.
public final class FileDescriptorBlockDevice: RawBlockDevice {

    /// The borrowed descriptor. **Not owned**: never closed here — see the file header.
    public let fileDescriptor: Int32

    /// The device's addressable shape, established once (from the ioctls, in production).
    public let geometry: DeviceGeometry

    /// Diagnostic detail about the most recent failure.
    ///
    /// `DeviceIOError` carries what the engine needs to *classify* a chunk failure
    /// (FR-FAIL-6) and deliberately not the `errno`, which the engine has no use for. But a
    /// root daemon reporting "the read failed" and nothing else is the kind of message that
    /// sent someone to check a cable when the answer was a checkbox (NFR-INST-4). So the
    /// `errno` is kept here for the helper to log alongside the thrown error (NFR-OBS-1,
    /// NFR-USE-5) — never the data, only the addressing (NFR-SEC-6).
    public private(set) var lastFailure: IOFailureDetail?

    /// Where and how the last failure happened.
    public struct IOFailureDetail: Equatable {
        public let operation: String            // "read" or "write"
        public let byteOffset: UInt64
        public let byteLength: Int
        public let bytesTransferred: Int
        public let errnoCode: Int32

        /// Human-readable, and honest about the two cases that look alike: a partial transfer
        /// with no error is not the same failure as an outright refusal.
        public var description: String {
            if errnoCode == 0 {
                return "\(operation) of \(byteLength) bytes at offset \(byteOffset) returned "
                     + "only \(bytesTransferred) bytes with no error reported"
            }
            return "\(operation) of \(byteLength) bytes at offset \(byteOffset) failed after "
                 + "\(bytesTransferred) bytes: errno \(errnoCode) "
                 + "(\(String(cString: strerror(errnoCode))))"
        }
    }

    // MARK: RawBlockDevice

    public var logicalBlockSize: Int { Int(geometry.logicalBlockSize) }
    public var blockCount: UInt64 { geometry.blockCount }

    /// Wrap an open descriptor.
    ///
    /// - Parameters:
    ///   - fileDescriptor: an open descriptor, owned by the caller. In production this is
    ///     `AcquiredDevice.fileDescriptor`.
    ///   - geometry: the device's shape. In production the ioctl-derived, reconciled values
    ///     from `DiskIOControl.reconcile(...)` — never the caller-supplied ones.
    /// - Throws: ``RunParameterRejection`` if the geometry cannot describe a real device.
    ///   Checked once here rather than on every transfer, because geometry does not change
    ///   under a held exclusive open.
    public init(fileDescriptor: Int32, geometry: DeviceGeometry) throws {
        try RunParameterValidator.validateGeometry(geometry)
        self.fileDescriptor = fileDescriptor
        self.geometry = geometry
    }

    @discardableResult
    public func read(into buffer: UnsafeMutableRawBufferPointer,
                     atByteOffset offset: UInt64) throws -> Int {
        guard let destination = buffer.baseAddress, buffer.count > 0 else {
            // A zero-length request is legal and moves nothing — matching
            // `InMemoryBlockDevice`, so the engine behaves identically against both.
            try validateZeroLength(atByteOffset: offset)
            return 0
        }
        let count = buffer.count
        let start = try validate(offset: offset, count: count)

        var transferred = 0
        while transferred < count {
            let result = pread(fileDescriptor,
                               destination + transferred,
                               count - transferred,
                               start + off_t(transferred))
            if result < 0 {
                let code = errno
                if code == EINTR { continue }        // a signal, not a device failure
                lastFailure = IOFailureDetail(operation: Operation.read.name, byteOffset: offset,
                                              byteLength: count, bytesTransferred: transferred,
                                              errnoCode: code)
                throw Self.ioError(forErrno: code, operation: .read,
                                   atByteOffset: offset, length: count)
            }
            if result == 0 { break }                 // end of file before the request was met
            transferred += result
        }

        guard transferred == count else {
            lastFailure = IOFailureDetail(operation: "read", byteOffset: offset,
                                          byteLength: count, bytesTransferred: transferred,
                                          errnoCode: 0)
            throw DeviceIOError.shortTransfer(atByteOffset: offset,
                                              expected: count, actual: transferred)
        }
        return transferred
    }

    @discardableResult
    public func write(_ buffer: UnsafeRawBufferPointer,
                      atByteOffset offset: UInt64) throws -> Int {
        guard let source = buffer.baseAddress, buffer.count > 0 else {
            try validateZeroLength(atByteOffset: offset)
            return 0
        }
        let count = buffer.count
        let start = try validate(offset: offset, count: count)

        var transferred = 0
        while transferred < count {
            let result = pwrite(fileDescriptor,
                                source + transferred,
                                count - transferred,
                                start + off_t(transferred))
            if result < 0 {
                let code = errno
                if code == EINTR { continue }
                lastFailure = IOFailureDetail(operation: Operation.write.name, byteOffset: offset,
                                              byteLength: count, bytesTransferred: transferred,
                                              errnoCode: code)
                throw Self.ioError(forErrno: code, operation: .write,
                                   atByteOffset: offset, length: count)
            }
            if result == 0 { break }
            transferred += result
        }

        guard transferred == count else {
            lastFailure = IOFailureDetail(operation: "write", byteOffset: offset,
                                          byteLength: count, bytesTransferred: transferred,
                                          errnoCode: 0)
            throw DeviceIOError.shortTransfer(atByteOffset: offset,
                                              expected: count, actual: transferred)
        }
        return transferred
    }

    // MARK: Validation

    /// Check alignment and range, and convert the offset for `pread`/`pwrite`.
    ///
    /// Runs **before** any syscall. On a raw device the kernel would refuse a misaligned
    /// request with `EINVAL` anyway, but relying on that would mean the guard existed only on
    /// hardware — and would be untestable and absent everywhere else.
    private func validate(offset: UInt64, count: Int) throws -> off_t {
        do {
            try RunParameterValidator.validate(byteOffset: offset,
                                                byteLength: UInt64(count),
                                                geometry: geometry)
        } catch let rejection as RunParameterRejection {
            throw Self.deviceIOError(for: rejection, offset: offset, count: count,
                                     geometry: geometry)
        }

        // `pread` takes a signed offset. Every real device is far below this, but a root
        // daemon converts rather than assumes: a wrapped negative offset would address the
        // wrong end of the device.
        guard let start = off_t(exactly: offset) else {
            throw DeviceIOError.outOfRange(atByteOffset: offset, length: count,
                                           deviceByteCount: byteCount)
        }
        return start
    }

    /// A zero-length request still has to name a valid, aligned place on the device.
    private func validateZeroLength(atByteOffset offset: UInt64) throws {
        let blockSize = UInt64(geometry.logicalBlockSize)
        guard offset % blockSize == 0 else {
            throw DeviceIOError.misaligned(atByteOffset: offset, length: 0,
                                           logicalBlockSize: logicalBlockSize)
        }
        guard offset <= byteCount else {
            throw DeviceIOError.outOfRange(atByteOffset: offset, length: 0,
                                           deviceByteCount: byteCount)
        }
    }

    // MARK: Classifying a failed syscall

    /// Which call failed. Picks the error case for a failure that is **not** device loss —
    /// loss is neutral about direction, the way ``DeviceIOError/shortTransfer`` is, because a
    /// device that has left the bus has not failed a read *or* a write, it has stopped existing.
    enum Operation {
        case read, write

        /// How the operation is named in ``IOFailureDetail``, which is a log line rather than a
        /// decision. Derived rather than written out beside each call, so the enum and the
        /// string cannot say different things about the same syscall.
        var name: String {
            switch self {
            case .read:  return "read"
            case .write: return "write"
            }
        }
    }

    /// Classify a failed `pread`/`pwrite` by its `errno`.
    ///
    /// **`ENXIO` alone means the device is gone.** That is a measurement, not a reading of the
    /// manual: on 2026-08-06 the scratch drive de-enumerated part-way through
    /// `retention-cycle-check.sh` and this descriptor returned `errno 6` — `ENXIO`, *"Device not
    /// configured"* — for **every** read including the one at offset 0. A drive with a bad block
    /// does not fail at offset 0 and does not fail every subsequent request; a drive that has
    /// left the bus does both.
    ///
    /// `EIO` is deliberately **not** treated as loss, and the direction of that mistake is why
    /// it is spelled out rather than left implicit: `EIO` is what a single unreadable block
    /// returns, so treating it as loss would end a run on the first genuine bad block — turning
    /// the one thing this tool exists to find into a reason to stop looking.
    ///
    /// Every other `errno` keeps the meaning it had, `EBADF` included. A closed or invalid
    /// descriptor is *this program's* mistake rather than the device's absence, and folding it
    /// in here would report a hardware event that did not happen.
    ///
    /// Pure and static so it can be tested without a device, a descriptor or an `errno` that has
    /// to be provoked: the *mapping* is decidable here, and whether real hardware produces
    /// `ENXIO` is the hardware claim in the table above.
    static func ioError(forErrno code: Int32,
                        operation: Operation,
                        atByteOffset offset: UInt64,
                        length count: Int) -> DeviceIOError {
        if code == ENXIO {
            return .deviceLost(atByteOffset: offset, length: count)
        }
        switch operation {
        case .read:  return .readError(atByteOffset: offset, length: count)
        case .write: return .writeError(atByteOffset: offset, length: count)
        }
    }

    /// Translate the validator's vocabulary into the protocol's.
    ///
    /// The two enums exist for different audiences: `RunParameterRejection` is what a *user*
    /// is told when the GUI sends nonsense, and `DeviceIOError` is what the *engine* switches
    /// on. Mapping keeps both honest instead of widening one to serve the other.
    private static func deviceIOError(for rejection: RunParameterRejection,
                                      offset: UInt64,
                                      count: Int,
                                      geometry: DeviceGeometry) -> DeviceIOError {
        let deviceByteCount = geometry.blockCount * UInt64(geometry.logicalBlockSize)
        switch rejection {
        case .misalignedOffset, .misalignedLength:
            return .misaligned(atByteOffset: offset, length: count,
                               logicalBlockSize: Int(geometry.logicalBlockSize))
        case .offsetOutOfRange, .rangeOverflowsDevice:
            return .outOfRange(atByteOffset: offset, length: count,
                               deviceByteCount: deviceByteCount)
        case .zeroLength:
            // Unreachable: zero-length requests are handled before validation, to match
            // `InMemoryBlockDevice`. Mapped rather than trapped — a root daemon reports.
            return .outOfRange(atByteOffset: offset, length: count,
                               deviceByteCount: deviceByteCount)
        case .unsupportedBlockSize, .emptyDevice, .implausibleGeometry:
            // Also unreachable: geometry is validated once, at init. If it were somehow
            // reached, refusing the transfer is the safe direction.
            return .outOfRange(atByteOffset: offset, length: count,
                               deviceByteCount: deviceByteCount)
        }
    }
}
