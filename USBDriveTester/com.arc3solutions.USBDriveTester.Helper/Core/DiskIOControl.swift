//
//  DiskIOControl.swift
//  Core — the `ioctl` request numbers, and the policy for reconciling two geometries.
//
//  Step 7 (AI-5). Satisfies the addressing half of FR-DEV-5 and NFR-COMPAT-5/6.
//
//  Everything here is pure — Foundation only, no `ioctl(2)`, no file descriptor, no
//  privilege — so the constants and the reconciliation rules are unit-testable with no
//  hardware and no root (NFR-MAINT-2). The syscalls that *use* these constants live in the
//  helper's `RawDeviceGeometry.swift`. That is the same split as
//  `DeviceAccessPrecondition` (pure decision) against `DeviceClaim` (impure doing), and it
//  exists for the same reason: it keeps the hardware-dependent part of the gate small.
//
//  ## Why the request numbers are written out by hand
//
//  Because they cannot be imported. Measured 2026-08-02 against the macOS 26.5 SDK:
//
//      error: cannot find 'DKIOCGETBLOCKSIZE' in scope
//      note: macro 'DKIOCGETBLOCKSIZE' unavailable: structure not supported
//
//  `DKIOCGETBLOCKSIZE` and friends are `_IOR(…)` macros, and the Swift importer does not
//  bring those through. (Plain integer `#define`s such as `F_NOCACHE` import normally, which
//  is why those are used directly and are not restated here.) This is the same class of
//  problem as the IOKit registry-key `#define`s that `DeviceClaim.swift` spells out.
//
//  ## Why they are *derived* here rather than pasted as literals
//
//  A pasted literal is a number nobody can check. A derivation can be read against
//  `<sys/ioccom.h>` and disagreed with. Both are asserted in the tests, so a mistake in
//  either fails rather than ships.
//
//  ## The verification chain behind these four numbers
//
//  Three independent steps, because this project's standing lesson is that a substitute's
//  result is never the real thing's result:
//
//    1. **Derivation vs. the SDK.** `_IOR` re-implemented in Swift, then `<sys/disk.h>`
//       compiled in C and the macro values printed. They matched: `0x40046418`,
//       `0x40086419`, `0x4004644d`, `0x40086446` (2026-08-02).
//    2. **The number vs. a real device.** `scripts/nocache-calibration.sh disk4` issued the
//       first two against a Samsung T5 through a real USB bridge and got
//       `logicalBlockSize=512`, `blockCount=1953525168`, `byteCount=1000204886016` —
//       matching `diskutil info` exactly, and matching the IOKit values Step 6 already
//       logged (2026-08-02). A correct constant that a bridge answers wrongly would have
//       shown here; it did not.
//    3. **Regression.** `DiskIOControlTests` pins the derivation against those literals, so
//       a later edit to `_IOR` cannot silently change what gets sent to a root daemon.
//

import Foundation

// MARK: - ioctl request numbers

/// The disk `ioctl` requests this tool issues, and nothing else.
///
/// Deliberately a closed list. A root daemon should be able to send only the requests it has
/// a stated reason to send, and every one of these four has one recorded below.
public enum DiskIOControl {

    /// `_IOR(group, number, type)` from `<sys/ioccom.h>`.
    ///
    /// ```c
    /// #define IOCPARM_MASK 0x1fff
    /// #define IOC_OUT      0x40000000
    /// #define _IOC(inout,group,num,len)  (inout | ((len & IOCPARM_MASK) << 16) \
    ///                                          | ((group) << 8) | (num))
    /// #define _IOR(g,n,t)  _IOC(IOC_OUT, (g), (n), sizeof(t))
    /// ```
    ///
    /// `IOC_OUT` alone (not `IOC_INOUT`) because every request here only *reads* from the
    /// driver — the caller supplies a buffer and the kernel fills it.
    ///
    /// - Parameter type: the type whose `sizeof` is encoded in the request. Getting this
    ///   wrong is the interesting failure: the length is part of the request number, so a
    ///   `UInt32` where the kernel expects a `UInt64` does not truncate the answer, it
    ///   produces a request the driver does not recognise at all.
    static func request<T>(readingOut group: UnicodeScalar,
                           _ number: UInt,
                           as type: T.Type) -> UInt {
        let length = UInt(MemoryLayout<T>.size) & 0x1fff        // IOCPARM_MASK
        return 0x4000_0000                                      // IOC_OUT
             | (length << 16)
             | (UInt(group.value) << 8)
             | number
    }

    /// `DKIOCGETBLOCKSIZE` — logical block size, `UInt32`. Expected 512 or 4096
    /// (NFR-COMPAT-5). **The authority on alignment**: this is the unit the kernel enforces
    /// `pread`/`pwrite` alignment against, and misaligned I/O is refused with `EINVAL`.
    public static let getBlockSize = request(readingOut: "d", 24, as: UInt32.self)

    /// `DKIOCGETBLOCKCOUNT` — total addressable logical blocks, `UInt64` (NFR-COMPAT-6).
    ///
    /// 64-bit and not negotiable: `disk8` here is 42,970,644,479 blocks, ten times past
    /// 2³². A bridge truncating this to 32 bits would make the tool test the first 2 TiB of
    /// a larger drive and report a clean pass, with nothing to indicate it.
    public static let getBlockCount = request(readingOut: "d", 25, as: UInt64.self)

    /// `DKIOCGETPHYSICALBLOCKSIZE` — the media's real write unit, `UInt32`.
    ///
    /// **Logged, never branched on.** Correctness depends solely on the *logical* size
    /// above; the physical size affects performance only. On a 512e drive (logical 512,
    /// physical 4096) a write not aligned to 4096 forces a read-modify-write inside the
    /// drive, which is worth being able to see when a throughput figure looks wrong in
    /// Step 9 — and is worth nothing as an input to a decision. `disk4` reports 512, so it
    /// is not 512e (measured 2026-08-02).
    public static let getPhysicalBlockSize = request(readingOut: "d", 77, as: UInt32.self)

    /// `DKIOCGETMAXBYTECOUNTREAD` — the largest read the device advertises, `UInt64`.
    ///
    /// Diagnostic. `disk4` reports 1 MiB, *smaller* than every I/O size FR-CTRL-8 offers
    /// except the smallest — and yet `pread` returned a full 4 MiB, and a full 8 MiB, in a
    /// single call (measured 2026-08-02, `extraIterations=0` in both runs). The kernel
    /// splits the transfer internally. So this value does **not** predict a short transfer
    /// and must not be used to size anything; it is recorded because if a short transfer
    /// ever does occur, this is the first number anyone will want.
    public static let getMaxByteCountRead = request(readingOut: "d", 70, as: UInt64.self)

    /// `DKIOCGETMAXBYTECOUNTWRITE` — the largest write the device advertises, `UInt64`.
    ///
    /// Diagnostic, added in Step 8 (D7, 2026-08-02) as the sibling of the read constant above,
    /// and for the same reason turned around. Step 7 established that `disk4` advertises a
    /// 1 MiB maximum **read** and still answers a 4 MiB *and* an 8 MiB `pread` in a single
    /// call, because the kernel splits transfers internally — so the advertised maximum does
    /// not predict a short transfer and must not be used to size anything.
    ///
    /// The **write** side has never been measured, on any device, and
    /// `DeviceIOError.shortTransfer` has never fired on a write in any test. Step 8 is the
    /// first code that writes at all. If a real write ever does come back short, this is the
    /// first number anyone will want, and it costs one ioctl at acquire to have it.
    public static let getMaxByteCountWrite = request(readingOut: "d", 71, as: UInt64.self)
}

// MARK: - Two geometries, one authority

/// Where a geometry came from.
///
/// Worth naming rather than tracking with a `Bool`, because the whole point of the
/// reconciliation is that the two sources are *not* interchangeable and one of them wins.
public enum GeometrySource: String, Equatable, CustomStringConvertible {

    /// `DKIOCGETBLOCKSIZE` / `DKIOCGETBLOCKCOUNT` on the held descriptor. **The authority**
    /// (BUILD-PLAN Step 7.3).
    case ioctl

    /// The helper's own IOKit registry read (`EligibleDevice`), taken at acquire time and
    /// explicitly provisional.
    ///
    /// Note *whose* IOKit read: the **helper's**, never the app's. Step 6 gave the helper an
    /// independent registry read specifically so a root daemon need not take the GUI's word
    /// about the device it is about to write to (NFR-REL-7). BUILD-PLAN 7.3 originally said
    /// to reconcile against "the values discovered in Step 5" — app-side — and was amended
    /// on 2026-08-02, because reconciling against those would re-cross the trust boundary
    /// Step 6 closed.
    case ioKit

    public var description: String { rawValue }
}

/// The result of comparing the two geometries: which one is authoritative, and whether they
/// agreed.
public struct GeometryReconciliation: Equatable {

    /// The geometry everything downstream uses. Always the `ioctl` one.
    public let authoritative: DeviceGeometry

    /// What the ioctls reported.
    public let ioctl: DeviceGeometry

    /// What IOKit reported, or `nil` when IOKit's numbers were unusable. Recorded for
    /// comparison and for the log; never used as the authority.
    public let ioKit: DeviceGeometry?

    /// `nil` when the two agree (or IOKit had nothing to say); otherwise a description of
    /// exactly how they differ, ready to log.
    public let disagreement: String?

    public var agrees: Bool { disagreement == nil }

    public init(authoritative: DeviceGeometry,
                ioctl: DeviceGeometry,
                ioKit: DeviceGeometry?,
                disagreement: String?) {
        self.authoritative = authoritative
        self.ioctl = ioctl
        self.ioKit = ioKit
        self.disagreement = disagreement
    }

    /// One line naming both sources and their numbers, for `os_log` (NFR-OBS-1).
    ///
    /// Both are always printed, agreement or not. A line that appears only on disagreement
    /// is a line nobody can use to confirm agreement actually happened.
    public var logDescription: String {
        var text = "geometry: ioctl reports \(ioctl.blockCount) blocks of "
                 + "\(ioctl.logicalBlockSize) bytes"
        if let ioKit {
            text += "; IOKit reported \(ioKit.blockCount) blocks of "
                  + "\(ioKit.logicalBlockSize) bytes"
        } else {
            text += "; IOKit reported no usable geometry"
        }
        text += agrees ? " — they agree" : " — THEY DISAGREE: \(disagreement ?? "")"
        return text
    }
}

/// Why geometry could not be established at all.
public enum GeometryRefusal: Error, Equatable, CustomStringConvertible {

    /// An `ioctl` returned non-zero. Named individually, because "the geometry call failed"
    /// is not something anyone can act on.
    case ioctlFailed(request: String, errnoCode: Int32)

    /// The ioctls succeeded but reported something that cannot describe a real device.
    ///
    /// Wraps the existing rejection rather than restating it, so the rule that rejects an
    /// unsupported block size is the same rule wherever geometry arrives from.
    case implausible(RunParameterRejection)

    public var description: String {
        switch self {
        case .ioctlFailed(let request, let code):
            return "The device did not answer \(request) (errno \(code), "
                 + "\(String(cString: strerror(code)))). Its geometry could not be "
                 + "established, so no run can start — a test that does not know the size "
                 + "of the device cannot address it safely."
        case .implausible(let rejection):
            return "The device reported geometry this tool will not accept: "
                 + "\(rejection.description) Some USB bridges report impossible values; "
                 + "the tool rejects them rather than working around them."
        }
    }
}

public extension DiskIOControl {

    /// Decide the device's true geometry from the two available sources.
    ///
    /// **The ioctl values win, always** (BUILD-PLAN Step 7.3). They come from the device
    /// through the descriptor the run will actually use, whereas IOKit's are a registry
    /// reading taken earlier and marked provisional at the point it was taken.
    ///
    /// A disagreement is **reported, not fatal**, and that asymmetry is deliberate. The
    /// ioctl block count is the bound the *kernel itself* enforces on `pread`/`pwrite`, so
    /// preferring it cannot produce an out-of-bounds access however wrong IOKit is: the
    /// worst case is testing a different extent than expected, which is visible in the
    /// report. Refusing the run instead would turn a logged curiosity into an outage, and
    /// there is no evidence yet that the two ever differ. What must not happen is the
    /// disagreement being absorbed silently — hence `disagreement` on the result and both
    /// figures in ``GeometryReconciliation/logDescription``.
    ///
    /// - Parameters:
    ///   - ioctlBlockSize: `DKIOCGETBLOCKSIZE`.
    ///   - ioctlBlockCount: `DKIOCGETBLOCKCOUNT`.
    ///   - ioKitSizeBytes: `EligibleDevice.sizeBytes`, or `nil` if it was not obtained.
    ///   - ioKitBlockSize: `EligibleDevice.logicalBlockSize`, or `nil`.
    /// - Throws: ``GeometryRefusal/implausible(_:)`` if the ioctl geometry cannot describe a
    ///   real device.
    static func reconcile(ioctlBlockSize: UInt32,
                          ioctlBlockCount: UInt64,
                          ioKitSizeBytes: UInt64?,
                          ioKitBlockSize: UInt32?) throws -> GeometryReconciliation {

        let ioctl = DeviceGeometry(logicalBlockSize: ioctlBlockSize,
                                   blockCount: ioctlBlockCount)

        // The authority still has to be plausible. "Trust the ioctl" means "prefer it over
        // IOKit", not "accept anything it says" — BUILD-PLAN Step 7's risks are explicit
        // that impossible values are rejected.
        do {
            try RunParameterValidator.validateGeometry(ioctl)
        } catch let rejection as RunParameterRejection {
            throw GeometryRefusal.implausible(rejection)
        }

        // IOKit reports a byte size, not a block count, so its block count is implied. A
        // size that is not a whole number of blocks is itself worth reporting.
        var ioKit: DeviceGeometry?
        var notes: [String] = []

        if let ioKitSizeBytes, let ioKitBlockSize, ioKitBlockSize > 0 {
            let impliedBlocks = ioKitSizeBytes / UInt64(ioKitBlockSize)
            ioKit = DeviceGeometry(logicalBlockSize: ioKitBlockSize, blockCount: impliedBlocks)

            if ioKitSizeBytes % UInt64(ioKitBlockSize) != 0 {
                notes.append("IOKit's size \(ioKitSizeBytes) is not a whole number of "
                           + "\(ioKitBlockSize)-byte blocks")
            }
            if ioKitBlockSize != ioctlBlockSize {
                notes.append("block size: ioctl \(ioctlBlockSize) vs IOKit \(ioKitBlockSize)")
            }
            if impliedBlocks != ioctlBlockCount {
                notes.append("block count: ioctl \(ioctlBlockCount) vs IOKit \(impliedBlocks)")
            }
        }

        return GeometryReconciliation(authoritative: ioctl,
                                      ioctl: ioctl,
                                      ioKit: ioKit,
                                      disagreement: notes.isEmpty
                                          ? nil
                                          : notes.joined(separator: "; "))
    }
}
