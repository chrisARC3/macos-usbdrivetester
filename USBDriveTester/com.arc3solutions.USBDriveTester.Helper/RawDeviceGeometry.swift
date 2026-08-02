//
//  RawDeviceGeometry.swift
//  com.arc3solutions.USBDriveTester.Helper (privileged)
//
//  Step 7 (AI-5): the syscalls. `fcntl` for uncached I/O (FR-TEST-6), the `DKIOC*` ioctls for
//  geometry (FR-DEV-5, NFR-COMPAT-5/6), and `fstat` for the one structural fact FR-TEST-9's
//  check rests on.
//
//  Everything here is the *doing*. The *deciding* is in Core — `DiskIOControl` owns the
//  request numbers and the reconciliation policy, `CacheBypassCheck` owns the classification —
//  and both are pure and exhaustively unit-tested with no hardware. This is the same split as
//  `DeviceClaim` against `DeviceAccessPrecondition`, and it exists for the same reason: it
//  keeps the hardware-dependent part of the gate down to one script.
//
//  ## Everything here applies to the descriptor Step 6 already holds
//
//  Nothing in this file opens anything. `AcquiredDevice.fileDescriptor` was opened
//  `O_RDWR | O_EXLOCK | O_NONBLOCK` as one half of the mount guard, and BUILD-PLAN Step 7.1
//  was amended on 2026-08-02 to say so: an independent open here would have to be closed, and
//  measured 2026-08-01, releasing an exclusive open makes DiskArbitration re-probe the media
//  and remount the volume ~4 ms later — silently undoing the user's unmount.
//
//  ## What the ioctls returned on real hardware (2026-08-02, `disk4`)
//
//      geometry.logicalBlockSize   = 512
//      geometry.blockCount         = 1953525168
//      geometry.physicalBlockSize  = 512          (so not a 512e drive)
//      geometry.maxByteCountRead   = 1048576      (1 MiB — see below)
//
//  matching `diskutil info` exactly. Established by `scripts/nocache-calibration.sh` before
//  any of it was wired into this daemon.
//

import Foundation
import os

private let log = Logger(subsystem: HelperIdentity.loggingSubsystem, category: "io")

/// Performs the descriptor-level configuration and interrogation a run needs.
enum RawDeviceGeometry {

    // MARK: - Uncached I/O (FR-TEST-6) and the node's kind (FR-TEST-9)

    /// Put the descriptor into uncached mode and record what kind of node it actually is.
    ///
    /// Both `fcntl` results are kept rather than checked and discarded, because a zero return
    /// proves less than it appears to: measured 2026-08-02, `fcntl(fd, F_NOCACHE, 1)` returns
    /// **0 on `/dev/null`**. The classification of what those results mean is
    /// `CacheBypassCheck`'s, not this file's.
    ///
    /// The `fstat` is the part that carries weight. `/dev/rdiskN` is a **character** device
    /// (`crw-`, mode `0o20640` measured) and `/dev/diskN` is a **block** device (`brw-`, mode
    /// `0o60640`); the unified buffer cache belongs to the block node. Asking the descriptor
    /// what it *is* catches the one failure that can realistically occur — opening the buffered
    /// node by mistake — which no amount of read timing can detect, because the raw path is
    /// never cached and so looks identical either way.
    static func configureUncachedIO(fileDescriptor fd: Int32,
                                    devicePath: String) -> UncachedIOConfiguration {

        let noCache = fcntl(fd, F_NOCACHE, 1)
        let noCacheErrno = errno
        let globalNoCache = fcntl(fd, F_GLOBAL_NOCACHE, 1)
        let globalNoCacheErrno = errno

        if noCache != 0 {
            log.error("""
                      F_NOCACHE failed on \(devicePath, privacy: .public): \
                      errno \(noCacheErrno, privacy: .public)
                      """)
        }
        if globalNoCache != 0 {
            log.error("""
                      F_GLOBAL_NOCACHE failed on \(devicePath, privacy: .public): \
                      errno \(globalNoCacheErrno, privacy: .public)
                      """)
        }

        var status = stat()
        let nodeKind: DeviceNodeKind
        if fstat(fd, &status) == 0 {
            nodeKind = DeviceNodeKind.from(statMode: status.st_mode)
        } else {
            // Cannot establish what was opened. Reported as `.other`, which
            // `CacheBypassCheck` classifies as inconclusive — never as bypassed.
            let code = errno
            log.error("""
                      fstat failed on \(devicePath, privacy: .public): \
                      errno \(code, privacy: .public); the node's kind is unknown
                      """)
            nodeKind = .other(mode: 0)
        }

        return UncachedIOConfiguration(devicePath: devicePath,
                                       nodeKind: nodeKind,
                                       noCacheResult: noCache,
                                       globalNoCacheResult: globalNoCache)
    }

    // MARK: - Geometry (FR-DEV-5, NFR-COMPAT-5/6)

    /// What the device says about its own shape.
    struct RawGeometry {
        let logicalBlockSize: UInt32
        let blockCount: UInt64
        /// Logged, never branched on — correctness depends only on the logical size.
        let physicalBlockSize: UInt32?
        /// Diagnostic. See the note on the reading below.
        let maximumByteCountRead: UInt64?
    }

    /// Issue the geometry ioctls on the held descriptor.
    ///
    /// The two required ones are fatal if they fail: a run that does not know the size of the
    /// device cannot address it safely, so this refuses rather than falling back to IOKit's
    /// provisional numbers. The two diagnostic ones are best-effort.
    static func readGeometry(fileDescriptor fd: Int32) -> Result<RawGeometry, GeometryRefusal> {

        var logicalBlockSize: UInt32 = 0
        guard ioctl(fd, DiskIOControl.getBlockSize, &logicalBlockSize) == 0 else {
            return .failure(.ioctlFailed(request: "DKIOCGETBLOCKSIZE", errnoCode: errno))
        }

        var blockCount: UInt64 = 0
        guard ioctl(fd, DiskIOControl.getBlockCount, &blockCount) == 0 else {
            return .failure(.ioctlFailed(request: "DKIOCGETBLOCKCOUNT", errnoCode: errno))
        }

        var physicalBlockSize: UInt32 = 0
        let physicalOK = ioctl(fd, DiskIOControl.getPhysicalBlockSize, &physicalBlockSize) == 0

        // Measured 2026-08-02: `disk4` reports 1 MiB here, *smaller* than the 4 MiB and 8 MiB
        // I/O sizes — and `pread` still returned both whole in a single call, because the
        // kernel splits the transfer internally. So this value does NOT predict a short
        // transfer and must not be used to size anything. It is read because if a short
        // transfer ever does occur, this is the first number anyone will want.
        var maximumByteCountRead: UInt64 = 0
        let maxReadOK = ioctl(fd, DiskIOControl.getMaxByteCountRead, &maximumByteCountRead) == 0

        return .success(RawGeometry(logicalBlockSize: logicalBlockSize,
                                    blockCount: blockCount,
                                    physicalBlockSize: physicalOK ? physicalBlockSize : nil,
                                    maximumByteCountRead: maxReadOK ? maximumByteCountRead : nil))
    }

    /// Read the geometry and reconcile it against the helper's own IOKit reading.
    ///
    /// The ioctl values win (BUILD-PLAN 7.3, amended 2026-08-02 to make clear the comparison is
    /// against the **helper's** registry read and not the app's), but they must still be
    /// plausible: "trust the ioctl" means "prefer it over IOKit", never "accept anything it
    /// says". Some USB bridges report impossible values and the tool rejects them.
    static func establishGeometry(fileDescriptor fd: Int32,
                                  ioKit: EligibleDevice,
                                  devicePath: String)
        -> Result<(reconciliation: GeometryReconciliation, raw: RawGeometry), GeometryRefusal> {

        let raw: RawGeometry
        switch readGeometry(fileDescriptor: fd) {
        case .success(let value):
            raw = value
        case .failure(let refusal):
            return .failure(refusal)
        }

        do {
            let reconciliation = try DiskIOControl.reconcile(
                ioctlBlockSize: raw.logicalBlockSize,
                ioctlBlockCount: raw.blockCount,
                ioKitSizeBytes: ioKit.sizeBytes,
                ioKitBlockSize: ioKit.logicalBlockSize)

            // Both figures every time, agreement or not: a line that appears only on
            // disagreement cannot be used to confirm agreement happened (NFR-OBS-1).
            if reconciliation.agrees {
                log.notice("""
                           \(devicePath, privacy: .public) \
                           \(reconciliation.logDescription, privacy: .public)
                           """)
            } else {
                log.error("""
                           \(devicePath, privacy: .public) \
                           \(reconciliation.logDescription, privacy: .public) — proceeding on \
                           the ioctl values, which are what the kernel enforces on every \
                           transfer
                           """)
            }

            if let physical = raw.physicalBlockSize, physical != raw.logicalBlockSize {
                log.notice("""
                           \(devicePath, privacy: .public) reports a physical block size of \
                           \(physical, privacy: .public) bytes against a logical \
                           \(raw.logicalBlockSize, privacy: .public) — writes not aligned to \
                           the physical size cost a read-modify-write inside the drive
                           """)
            }
            if let maximumRead = raw.maximumByteCountRead {
                log.info("""
                         \(devicePath, privacy: .public) advertises a maximum read of \
                         \(maximumRead, privacy: .public) bytes (diagnostic only — the kernel \
                         splits larger transfers)
                         """)
            }

            return .success((reconciliation, raw))

        } catch let refusal as GeometryRefusal {
            log.error("""
                      \(devicePath, privacy: .public) geometry REFUSED: \
                      \(refusal.description, privacy: .public)
                      """)
            return .failure(refusal)
        } catch {
            return .failure(.implausible(.emptyDevice))     // unreachable; fails closed
        }
    }
}
