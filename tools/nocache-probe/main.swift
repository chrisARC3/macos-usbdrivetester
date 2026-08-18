//
//  main.swift
//  nocache-probe — measures whether F_NOCACHE actually changes anything on a raw device.
//
//  ## Why this exists
//
//  FR-TEST-9 (added 2026-08-02) requires the tool to verify at run start that its reads are
//  not being served from the host buffer cache. The plan is to read one chunk twice and
//  compare the durations: if the second read is dramatically faster, it came from RAM.
//
//  That plan rests on two things nobody has measured:
//
//    1. **That the comparison can discriminate at all.** `/dev/rdiskN` is the *character*
//       device and is inherently unbuffered — which is exactly why FR-TEST-6 specifies it
//       over `/dev/diskN`. `F_NOCACHE` / `F_GLOBAL_NOCACHE` may therefore be belt-and-braces
//       on a path that was never cached, in which case the two timings match whether or not
//       the `fcntl` calls did anything, and the check passes vacuously. A check that cannot
//       fail is the precise defect shape FR-TEST-9 exists to catch, so this has to be
//       settled before the classifier is written, not after.
//    2. **What "similar" and "much faster" mean in nanoseconds on this hardware.** The
//       classifier's thresholds must be measured, not invented. This project's standing
//       lesson is that a substitute's result is never the real thing's result; a threshold
//       derived from arithmetic about USB bandwidth is a substitute.
//
//  So this probe runs the same measurement twice — once before the flags are set, once
//  after — and prints both. The difference between the two columns *is* the answer to (1),
//  and the numbers are the answer to (2).
//
//  ## It never writes. Not once, not optionally.
//
//  There is no write path in this file: no `pwrite`, no `write`, no `O_TRUNC`. Step 7's
//  hardware work is entirely read-only by design, because NFR-REL-1 puts the simulation
//  proof of non-destructiveness ahead of the first byte written to real media, and that
//  proof is Step 8's gate.
//
//  ## One descriptor for the whole run, and why that is not just tidiness
//
//  The obvious structure — open, measure, close; open, set flags, measure, close — is
//  **wrong on this platform**. Measured 2026-08-01: releasing an exclusive open on a raw
//  node makes DiskArbitration re-probe the media (~4 ms) and remount the volume (~230 ms).
//  A second open racing that sequence can fail `EBUSY` for reasons that have nothing to do
//  with what is being measured, and the failure would look like a caching result.
//
//  So the node is opened **once**, both phases run on that descriptor, and it is closed
//  once at the end. This also matches what `DeviceClaim.acquire(_:)` does — one descriptor,
//  flags set on it — which is the path the FR-TEST-9 check will actually run on.
//
//  ## Phase order is not arbitrary
//
//  The un-flagged phase runs FIRST, because `F_NOCACHE` cannot be turned back off: there is
//  no `F_GETNOCACHE` to read it back and no documented way to clear it. "Off" can therefore
//  only mean "not yet set on this descriptor", which is only available before the `fcntl`.
//  `F_GLOBAL_NOCACHE` compounds this — it sets its flag on the *vnode*, so it can outlive
//  the descriptor and even the process that set it.
//
//  The two phases read *different* regions, far apart. Re-using one region would let the
//  first phase warm the cache for the second, so the second phase's "cold" read would not be
//  cold — and since the buffer cache is per-vnode rather than per-descriptor, sharing one
//  descriptor does not change that.
//
//  Both regions sit mid-device. Block 0 is the GPT and partition table — the region the OS
//  has most recently touched, and therefore the worst possible choice for a cold read.
//
//  ## Flags match the helper's, deliberately
//
//  The node is opened `O_RDWR | O_EXLOCK | O_NONBLOCK` — byte-for-byte what
//  `DeviceClaim.acquire(_:)` uses. Opening `O_RDONLY` would be easier (it succeeds even
//  while volumes are mounted, measured 2026-08-01) and would measure a path the helper never
//  takes. Three successive versions of the Full Disk Access probe were wrong for exactly
//  that reason, so the flags are not negotiable here.
//
//  Two consequences, both handled by `scripts/nocache-calibration.sh` rather than here:
//  `open(rdiskN, O_RDWR)` fails `EBUSY` while any volume is mounted, so the caller unmounts
//  first; and the single close at the end will make macOS remount, so the caller restores
//  and reports the drive's state.
//
//  Run under `sudo` from a real Terminal. Root alone is not sufficient for the raw open
//  (NFR-INST-4) — but a `sudo` process inherits Terminal's own TCC grant, which is what
//  stands in here for the helper's Full Disk Access.
//
//  ## It also confirms the ioctl constants on real hardware
//
//  A side benefit worth having deliberately: `DKIOCGETBLOCKSIZE` and `DKIOCGETBLOCKCOUNT`
//  are not importable into Swift (the SDK reports `macro unavailable: structure not
//  supported`), so they are re-derived below. The derivation was checked against
//  `<sys/disk.h>` by compiling C — but that proves the *number*, not that the ioctl answers
//  correctly through a real USB bridge. This probe prints the geometry it reads, so the
//  calling script can diff it against `diskutil info` before any of this is wired into a
//  root daemon.
//
//  Usage:
//      sudo nocache-probe <bsdName> [ioSizeMiB] [readsPerPhase]
//
//  Output is `KEY=value` on stdout, one fact per line — meant for grep, not for reading
//  aloud.
//

import Foundation

// MARK: - ioctl request numbers

/// `_IOR(group, number, type)` from `<sys/ioccom.h>`, re-derived.
///
/// Required because `DKIOCGETBLOCKSIZE` and friends are `_IOR(…)` macros, which the Swift
/// importer refuses with `macro unavailable: structure not supported`. Plain integer
/// `#define`s such as `F_NOCACHE` import normally; these do not.
///
/// Verified 2026-08-02 against the macOS 26.5 SDK by compiling `<sys/disk.h>` in C and
/// comparing: `DKIOCGETBLOCKSIZE == 0x40046418`, `DKIOCGETBLOCKCOUNT == 0x40086419`,
/// `DKIOCGETPHYSICALBLOCKSIZE == 0x4004644d`, `DKIOCGETMAXBYTECOUNTREAD == 0x40086446`.
func _IOR<T>(_ group: UnicodeScalar, _ number: UInt, _ type: T.Type) -> UInt {
    let length = UInt(MemoryLayout<T>.size) & 0x1fff       // IOCPARM_MASK
    return 0x4000_0000                                     // IOC_OUT
         | (length << 16)
         | (UInt(group.value) << 8)
         | number
}

let dkiocGetBlockSize         = _IOR("d", 24, UInt32.self)
let dkiocGetBlockCount        = _IOR("d", 25, UInt64.self)
let dkiocGetPhysicalBlockSize = _IOR("d", 77, UInt32.self)
let dkiocGetMaxByteCountRead  = _IOR("d", 70, UInt64.self)

// MARK: - Output

func emit(_ key: String, _ value: Any) {
    print("\(key)=\(value)")
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("nocache-probe: \(message)\n".utf8))
    exit(1)
}

func errnoText(_ code: Int32) -> String { String(cString: strerror(code)) }

// MARK: - Arguments

let arguments = CommandLine.arguments
guard arguments.count >= 2, arguments.count <= 4 else {
    FileHandle.standardError.write(Data("""
        usage: sudo nocache-probe <bsdName> [ioSizeMiB] [readsPerPhase]
               bsdName        canonical whole-disk name, e.g. diskN — resolved from a SERIAL
                              by scripts/lib/device-identity.sh, not typed
               ioSizeMiB      1, 2, 4 or 8 (default 4) — the FR-CTRL-8 choices
               readsPerPhase  reads of the same region per phase (default 4, minimum 2)

        """.utf8))
    exit(2)
}

let bsdName = arguments[1]

// Canonical whole-disk names only. This mirrors `WholeDiskName(validating:)` in Core, which
// cannot be imported here: this tool is compiled standalone by swiftc, outside the Xcode
// project. Duplicated on purpose rather than relaxed — a probe that accepted a slice name or a
// path would open something other than the whole disk it claims to.
guard bsdName.hasPrefix("disk") else {
    fail("\"\(bsdName)\" is not a whole-disk BSD name (expected e.g. diskN)")
}
let unitDigits = bsdName.dropFirst("disk".count)
guard !unitDigits.isEmpty,
      unitDigits.allSatisfy({ $0 >= "0" && $0 <= "9" }),
      let unitNumber = UInt32(unitDigits),
      "disk\(unitNumber)" == bsdName else {
    fail("\"\(bsdName)\" is not a canonical whole-disk name — not a slice (diskNsM), "
       + "not a raw node (rdiskN), and not a path")
}

let ioSizeMiB = arguments.count >= 3 ? Int(arguments[2]) ?? 4 : 4
guard [1, 2, 4, 8].contains(ioSizeMiB) else {
    fail("ioSizeMiB must be 1, 2, 4 or 8 (the FR-CTRL-8 choices); got \(ioSizeMiB)")
}
let ioSize = ioSizeMiB << 20

let readsPerPhase = arguments.count >= 4 ? Int(arguments[3]) ?? 4 : 4
guard readsPerPhase >= 2 else {
    fail("readsPerPhase must be at least 2 — one cold read and one re-read is the "
       + "whole measurement")
}

guard getuid() == 0 else {
    fail("must run as root: sudo nocache-probe \(bsdName). The raw open needs it, and a "
       + "sudo process inherits Terminal's TCC grant, which is what stands in for the "
       + "helper's Full Disk Access here.")
}

let rawPath = "/dev/r\(bsdName)"

setvbuf(stdout, nil, _IOLBF, 0)
emit("probe.pid", getpid())
emit("probe.device", bsdName)
emit("probe.rawPath", rawPath)
emit("probe.ioSizeBytes", ioSize)
emit("probe.readsPerPhase", readsPerPhase)
emit("probe.pageSize", getpagesize())

// MARK: - Timing

/// Monotonic, not subject to wall-clock adjustment, and raw so NTP slewing cannot stretch a
/// measurement mid-read.
func nowNanos() -> UInt64 { clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) }

// MARK: - The single descriptor

// Opened once for the whole probe. See the header: open/close/open would race
// DiskArbitration's remount and could fail EBUSY for reasons unrelated to caching.
let fd = open(rawPath, O_RDWR | O_EXLOCK | O_NONBLOCK)
guard fd >= 0 else {
    let code = errno
    emit("open", "FAILED")
    emit("open.errno", code)
    emit("open.errnoText", errnoText(code))
    switch code {
    case EBUSY:
        emit("open.diagnosis",
             "EBUSY — a volume is still mounted, or another process holds the node. The "
           + "mount guard is kernel-enforced; unmount the disk first.")
    case EPERM:
        emit("open.diagnosis",
             "EPERM — TCC refused the exclusive open. Run this from a real Terminal under "
           + "sudo so the process inherits Terminal's Full Disk Access grant. Root alone "
           + "is not sufficient (NFR-INST-4).")
    default:
        emit("open.diagnosis", "the raw node could not be opened exclusively")
    }
    fail("could not open \(rawPath) exclusively (errno \(code), \(errnoText(code)))")
}
emit("open", "ok")
emit("open.flags", "O_RDWR | O_EXLOCK | O_NONBLOCK")

// MARK: - Geometry

var logicalBlockSize: UInt32 = 0
var blockCount: UInt64 = 0
var physicalBlockSize: UInt32 = 0
var maxByteCountRead: UInt64 = 0

let blockSizeRC  = ioctl(fd, dkiocGetBlockSize, &logicalBlockSize)
let blockCountRC = ioctl(fd, dkiocGetBlockCount, &blockCount)
let physicalRC   = ioctl(fd, dkiocGetPhysicalBlockSize, &physicalBlockSize)
let maxReadRC    = ioctl(fd, dkiocGetMaxByteCountRead, &maxByteCountRead)

emit("geometry.DKIOCGETBLOCKSIZE.request", "0x" + String(dkiocGetBlockSize, radix: 16))
emit("geometry.DKIOCGETBLOCKCOUNT.request", "0x" + String(dkiocGetBlockCount, radix: 16))
emit("geometry.blockSize.rc", blockSizeRC)
emit("geometry.blockCount.rc", blockCountRC)
emit("geometry.logicalBlockSize", logicalBlockSize)
emit("geometry.blockCount", blockCount)
emit("geometry.physicalBlockSize.rc", physicalRC)
emit("geometry.physicalBlockSize", physicalBlockSize)
emit("geometry.maxByteCountRead.rc", maxReadRC)
emit("geometry.maxByteCountRead", maxByteCountRead)

guard blockSizeRC == 0, blockCountRC == 0, logicalBlockSize > 0, blockCount > 0 else {
    close(fd)
    fail("geometry ioctls did not return usable values — cannot choose a read offset")
}

let byteCount = blockCount * UInt64(logicalBlockSize)
emit("geometry.byteCount", byteCount)
emit("geometry.exceeds32BitBlockCount", blockCount > UInt64(UInt32.max))

// A bridge whose maximum read is smaller than the I/O size would make `pread` come back
// short — the case `DeviceIOError.shortTransfer` has been reserved for since Step 2, and a
// finding for Step 8 if it is true here.
if maxReadRC == 0, maxByteCountRead > 0, maxByteCountRead < UInt64(ioSize) {
    emit("geometry.maxByteCountRead.warning",
         "the device reports a maximum read of \(maxByteCountRead) bytes, which is SMALLER "
       + "than the \(ioSize)-byte I/O size — expect short transfers")
}

guard byteCount > UInt64(ioSize) * 4 else {
    close(fd)
    fail("device is too small for this measurement at \(ioSizeMiB) MiB I/O")
}

// Two regions, far apart and mid-device, each aligned down to a block boundary.
//
// Different regions because one phase must not warm the cache for the other — the buffer
// cache is per-vnode, so sharing one descriptor does not change that. Mid-device because
// block 0 is the GPT and partition table, the most recently touched region on the disk and
// so the worst available choice for a read that is supposed to be cold.
func alignedOffset(fraction: Double) -> UInt64 {
    let raw = UInt64(Double(byteCount) * fraction)
    return raw - (raw % UInt64(logicalBlockSize))
}
let offsetUnflagged = alignedOffset(fraction: 0.40)
let offsetFlagged   = alignedOffset(fraction: 0.60)

emit("offset.unflagged", offsetUnflagged)
emit("offset.flagged", offsetFlagged)

// MARK: - Buffer

var rawBuffer: UnsafeMutableRawPointer?
let alignment = Int(getpagesize())
guard posix_memalign(&rawBuffer, alignment, ioSize) == 0, let buffer = rawBuffer else {
    close(fd)
    fail("could not allocate a \(ioSize)-byte page-aligned buffer")
}
emit("buffer.alignedTo", alignment)
emit("buffer.address.isPageAligned", UInt(bitPattern: buffer) % UInt(alignment) == 0)

// MARK: - Reading

/// Read exactly `count` bytes at `offset`, looping over short transfers.
///
/// The loop is not defensive padding: a USB bridge advertising a maximum byte count below
/// `ioSize` is a real possibility (`DKIOCGETMAXBYTECOUNTREAD` is reported above for exactly
/// this reason). If this loop ever iterates more than once, that is a finding for Step 8, so
/// the extra iterations are counted and reported rather than silently absorbed.
func readFully(into destination: UnsafeMutableRawPointer,
               count: Int,
               atOffset offset: UInt64) -> (bytes: Int, iterations: Int, failure: Int32) {
    var transferred = 0
    var iterations = 0
    while transferred < count {
        iterations += 1
        let n = pread(fd, destination + transferred, count - transferred,
                      off_t(offset) + off_t(transferred))
        if n < 0 { return (transferred, iterations, errno) }
        if n == 0 { break }                                  // unexpected EOF
        transferred += n
    }
    return (transferred, iterations, 0)
}

struct PhaseResult {
    let durationsNanos: [UInt64]
    let extraIterations: Int
}

/// Read one region `readsPerPhase` times on the shared descriptor, timing each.
func measure(label: String, byteOffset: UInt64) -> PhaseResult? {
    var durations: [UInt64] = []
    var extraIterations = 0

    for index in 0 ..< readsPerPhase {
        let started = nowNanos()
        let (bytes, iterations, failure) = readFully(into: buffer, count: ioSize,
                                                     atOffset: byteOffset)
        let elapsed = nowNanos() - started

        guard failure == 0 else {
            emit("\(label).read\(index).errno", failure)
            emit("\(label).read\(index).errnoText", errnoText(failure))
            if failure == EINVAL {
                emit("\(label).read\(index).diagnosis",
                     "EINVAL — the raw device rejected the offset or length as misaligned")
            }
            return nil
        }
        guard bytes == ioSize else {
            emit("\(label).read\(index).shortTransfer", "\(bytes) of \(ioSize) bytes")
            return nil
        }
        if iterations > 1 { extraIterations += iterations - 1 }

        durations.append(elapsed)
        emit("\(label).read\(index).nanos", elapsed)
        emit("\(label).read\(index).microseconds", elapsed / 1_000)
        let mbPerSecond = Double(ioSize) / (Double(elapsed) / 1_000_000_000) / 1_000_000
        emit("\(label).read\(index).MBps", String(format: "%.1f", mbPerSecond))
    }

    return PhaseResult(durationsNanos: durations, extraIterations: extraIterations)
}

// MARK: - The measurement

// Un-flagged FIRST, and it has to be: F_NOCACHE cannot be turned back off, so "off" is only
// available before the fcntl. See the header.
print("---")
emit("unflagged.F_NOCACHE", "not set")
emit("unflagged.F_GLOBAL_NOCACHE", "not set")
let unflagged = measure(label: "unflagged", byteOffset: offsetUnflagged)

print("---")
let nocacheRC = fcntl(fd, F_NOCACHE, 1)
let nocacheErrno = errno
let globalRC = fcntl(fd, F_GLOBAL_NOCACHE, 1)
let globalErrno = errno
emit("flagged.F_NOCACHE.rc", nocacheRC)
if nocacheRC != 0 { emit("flagged.F_NOCACHE.errno", nocacheErrno) }
emit("flagged.F_GLOBAL_NOCACHE.rc", globalRC)
if globalRC != 0 { emit("flagged.F_GLOBAL_NOCACHE.errno", globalErrno) }
emit("flagged.note",
     "a return of 0 proves the syscall was accepted, not that caching was suppressed — "
   + "fcntl(F_NOCACHE) returns 0 on /dev/null (measured 2026-08-02)")

let flagged = measure(label: "flagged", byteOffset: offsetFlagged)

// The single close. macOS will remount the volumes shortly after this point.
free(buffer)
close(fd)
emit("closed", "yes — expect DiskArbitration to re-probe within ~5 ms and remount within ~250 ms")

// MARK: - Verdict

print("---")

guard let unflagged, let flagged,
      unflagged.durationsNanos.count >= 2, flagged.durationsNanos.count >= 2 else {
    emit("verdict", "INCOMPLETE")
    emit("verdict.detail", "one or both phases did not complete; see the errno lines above")
    exit(1)
}

/// Ratio of the first (cold) read to the fastest subsequent read.
///
/// The *fastest* re-read rather than the mean, because the question is whether the cache can
/// serve this read at all — one cache hit is enough to make a verify vacuous, and averaging
/// would dilute exactly the signal being looked for.
func rereadSpeedup(_ durations: [UInt64]) -> Double {
    let first = Double(durations[0])
    let fastestRest = Double(durations.dropFirst().min() ?? durations[0])
    guard fastestRest > 0 else { return .infinity }
    return first / fastestRest
}

let unflaggedSpeedup = rereadSpeedup(unflagged.durationsNanos)
let flaggedSpeedup   = rereadSpeedup(flagged.durationsNanos)

emit("unflagged.rereadSpeedup", String(format: "%.2f", unflaggedSpeedup))
emit("flagged.rereadSpeedup", String(format: "%.2f", flaggedSpeedup))
emit("unflagged.extraIterations", unflagged.extraIterations)
emit("flagged.extraIterations", flagged.extraIterations)
emit("discrimination.speedupDelta", String(format: "%.2f", unflaggedSpeedup - flaggedSpeedup))

// No threshold is applied here, on purpose. This probe reports; it does not classify. The
// classifier's thresholds are supposed to come FROM these numbers, so baking one in here
// would make the measurement circular.
print("""
      ---
      READ THIS BEFORE TRUSTING THE NUMBERS ABOVE.

      The question is NOT "is the re-read faster". It is "does setting F_NOCACHE change
      whether the re-read is faster".

        * unflagged.rereadSpeedup LARGE and flagged.rereadSpeedup ~1.0
          -> the flags work and re-read timing discriminates. FR-TEST-9's check is real,
             and its thresholds come from these two numbers.

        * BOTH ~1.0
          -> /dev/r\(bsdName) was never cached in the first place, and re-read timing
             CANNOT discriminate. FR-TEST-9's check would pass regardless of whether the
             flags were set — a check that cannot fail. Record that as the finding; do not
             ship a check reporting `bypassed` on this evidence.

        * BOTH LARGE
          -> something is caching despite F_NOCACHE. That is the condition FR-TEST-9 was
             written for, and it would make Step 8's verify vacuous.

      Nothing was written to \(bsdName). Expect macOS to have remounted its volumes.
      """)
