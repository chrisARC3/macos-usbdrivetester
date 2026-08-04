//
//  main.swift
//  media-digest — a read-only fingerprint of what is actually on a device, taken twice.
//
//  ## What this is for
//
//  Step 8's hardware gate has to show that a run of the read → write-back → read-verify cycle
//  left `disk4`'s contents unchanged. The run's own verify **cannot** establish that, and the
//  reason is worth stating precisely because it is easy to assume otherwise:
//
//  > The verify compares what was read back **at the offset the cycle intended to write**. A
//  > write that lands somewhere *else* is therefore invisible to it. `RetentionCycleTests`'
//  > `aMisdirectedWriteIsDetectedByTheSameAssertion` demonstrates the shape of that failure in
//  > simulation, where a whole-device snapshot catches what the verify does not.
//
//  On a 1 TB drive there is no snapshot to take, so this is the equivalent: a SHA-256 per 1 GiB
//  window plus one over the whole device, taken before the cycle and again after, both **inside
//  the claim window**. Per-window rather than a single scalar because it costs exactly the same
//  I/O and localises any difference to one gibibyte instead of merely proving one exists.
//
//  ## Read-only, and deliberately not exclusive
//
//  Opens `O_RDONLY` with **no** `O_EXLOCK` and unmounts nothing — the same departure from
//  `DeviceClaim`'s flags that `large-address-probe` made for `disk8`, and for the same reason:
//  the descriptor physically cannot write, and with no exclusive lock there is no release to
//  trigger DiskArbitration's remount.
//
//  This is what makes it usable *while the helper holds the device*, which is where the gate
//  needs it. Both digests must be taken inside one claim window: releasing makes
//  DiskArbitration remount ~4 ms later (measured 2026-08-01), and a mounted exFAT volume writes
//  to itself, so an "after" digest taken post-release would differ for reasons that have
//  nothing to do with the cycle.
//
//  ## `--probe` settles a fact this project has not measured
//
//  Whether a second process can open `/dev/rdiskN` `O_RDONLY` while the helper holds
//  `O_EXLOCK`. The 2026-07-30 exclusivity matrix records that two plain `O_RDWR` opens both
//  succeed and that a second `O_EXLOCK` is refused, but not that combination — and the whole
//  digest ordering above rests on it. `--probe` opens, reads one block, reports, and exits.
//
//  ## Its own canary
//
//  It takes a **path**, not a BSD name, so it runs against a regular file. That is how the
//  gate proves the digest can actually detect a change: digest a temporary file, flip one byte,
//  digest again, and the value must differ. Without that, "the digests matched" is
//  indistinguishable from a tool that prints a constant — the same defect this project has
//  caught in a probe, in a guard script, and in an FR-TEST-9 timing check.
//
//  Usage:
//      media-digest <path> [--window-bytes N] [--limit-bytes N] [--probe]
//
//  Output is `KEY=value` on stdout, one fact per line. Never any device content: a SHA-256 is
//  a fingerprint, not the data (NFR-SEC-6).
//

import Foundation
import CryptoKit

func emit(_ key: String, _ value: Any) { print("\(key)=\(value)") }
func errnoText(_ code: Int32) -> String { String(cString: strerror(code)) }

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("media-digest: \(message)\n".utf8))
    exit(1)
}

// MARK: - ioctl requests (see Core/DiskIOControl.swift for why these are re-derived)

func _IOR<T>(_ group: UnicodeScalar, _ number: UInt, _ type: T.Type) -> UInt {
    let length = UInt(MemoryLayout<T>.size) & 0x1fff
    return 0x4000_0000 | (length << 16) | (UInt(group.value) << 8) | number
}
let dkiocGetBlockSize  = _IOR("d", 24, UInt32.self)
let dkiocGetBlockCount = _IOR("d", 25, UInt64.self)

// MARK: - Arguments

var path: String?
var windowBytes: UInt64 = 1 << 30          // 1 GiB
var limitBytes: UInt64 = .max
var probeOnly = false

var index = 1
let arguments = CommandLine.arguments
while index < arguments.count {
    switch arguments[index] {
    case "--window-bytes":
        index += 1
        guard index < arguments.count, let value = UInt64(arguments[index]), value > 0 else {
            fail("--window-bytes needs a positive integer")
        }
        windowBytes = value
    case "--limit-bytes":
        index += 1
        guard index < arguments.count, let value = UInt64(arguments[index]), value > 0 else {
            fail("--limit-bytes needs a positive integer")
        }
        limitBytes = value
    case "--probe":
        probeOnly = true
    case let other where other.hasPrefix("--"):
        fail("unknown option \(other)")
    case let other:
        guard path == nil else { fail("more than one path given") }
        path = other
    }
    index += 1
}

guard let path else {
    FileHandle.standardError.write(Data("""
        usage: media-digest <path> [--window-bytes N] [--limit-bytes N] [--probe]

        """.utf8))
    exit(2)
}

setvbuf(stdout, nil, _IOLBF, 0)
emit("path", path)

// MARK: - Open, read-only, no exclusive lock, nothing unmounted

let fd = open(path, O_RDONLY)
if fd < 0 {
    let code = errno
    emit("open", "failed")
    emit("open.errno", code)
    emit("open.errnoText", errnoText(code))
    // A refusal is a *result* here, not a crash: `--probe` exists precisely to find out
    // whether this open is possible while the helper holds an exclusive lock.
    exit(1)
}
defer { close(fd) }
emit("open", "ok")

// MARK: - What was actually opened

var status = stat()
guard fstat(fd, &status) == 0 else { fail("fstat failed: errno \(errno) (\(errnoText(errno)))") }

let nodeKind: String
switch status.st_mode & S_IFMT {
case S_IFCHR: nodeKind = "character"
case S_IFBLK: nodeKind = "block"
case S_IFREG: nodeKind = "regular"
default:      nodeKind = "other"
}
emit("nodeKind", nodeKind)

// Size and alignment come from the ioctls on a device and from `stat` on a file. Raw devices
// reject misaligned offsets and lengths with EINVAL, so the read size has to be a whole
// multiple of the logical block size — which is why this is established rather than assumed.
var byteCount: UInt64 = 0
var blockSize: UInt32 = 512

if nodeKind == "character" || nodeKind == "block" {
    var blocks: UInt64 = 0
    guard ioctl(fd, dkiocGetBlockSize, &blockSize) == 0 else {
        fail("DKIOCGETBLOCKSIZE failed: errno \(errno) (\(errnoText(errno)))")
    }
    guard ioctl(fd, dkiocGetBlockCount, &blocks) == 0 else {
        fail("DKIOCGETBLOCKCOUNT failed: errno \(errno) (\(errnoText(errno)))")
    }
    byteCount = blocks * UInt64(blockSize)
    emit("geometry.blockSize", blockSize)
    emit("geometry.blockCount", blocks)
} else {
    byteCount = UInt64(max(0, status.st_size))
    blockSize = 1
}
emit("byteCount", byteCount)

let digestBytes = Swift.min(byteCount, limitBytes)
emit("digestBytes", digestBytes)

// MARK: - The buffer

// Page-aligned: raw device I/O otherwise takes a slower bounce-buffer path in the kernel.
// 4 MiB, and a whole number of logical blocks by construction.
let readSize = 4 << 20
var bufferPointer: UnsafeMutableRawPointer?
guard posix_memalign(&bufferPointer, Int(getpagesize()), readSize) == 0,
      let buffer = bufferPointer else {
    fail("could not allocate a \(readSize)-byte aligned buffer")
}
defer { free(buffer) }

// MARK: - Probe mode: does the open work at all, and can it read?

if probeOnly {
    let probeSize = Int(blockSize)
    let transferred = pread(fd, buffer, probeSize, 0)
    if transferred < 0 {
        let code = errno
        emit("probeRead", "failed")
        emit("probeRead.errno", code)
        emit("probeRead.errnoText", errnoText(code))
        exit(1)
    }
    emit("probeRead", "ok")
    emit("probeRead.bytes", transferred)
    exit(0)
}

// MARK: - Digest

let started = Date()
var whole = SHA256()
var window = SHA256()
var windowIndex: UInt64 = 0
var windowStart: UInt64 = 0
var offset: UInt64 = 0

func finishWindow(endingAt end: UInt64) {
    let digest = window.finalize().compactMap { String(format: "%02x", $0) }.joined()
    emit("window.\(windowIndex)", "\(windowStart) \(end - windowStart) \(digest)")
    windowIndex += 1
    windowStart = end
    window = SHA256()
}

while offset < digestBytes {
    let remaining = digestBytes - offset
    // Never read past the end, and never straddle a window boundary — a window's digest has to
    // cover exactly its own bytes or the "which gibibyte changed" answer is off by a chunk.
    let toWindowEnd = (windowStart + windowBytes) - offset
    var want = UInt64(readSize)
    want = Swift.min(want, remaining)
    want = Swift.min(want, toWindowEnd)

    // Raw devices refuse misaligned lengths (EINVAL), except for the final short read at the
    // very end of the device, which is a whole number of blocks by construction.
    let transferred = pread(fd, buffer, Int(want), off_t(offset))
    if transferred < 0 {
        let code = errno
        emit("read.failed.offset", offset)
        emit("read.failed.length", want)
        emit("read.failed.errno", code)
        emit("read.failed.errnoText", errnoText(code))
        fail("read failed at offset \(offset)")
    }
    if transferred == 0 {
        emit("read.shortAtOffset", offset)
        break
    }

    let slice = UnsafeRawBufferPointer(start: buffer, count: transferred)
    whole.update(bufferPointer: slice)
    window.update(bufferPointer: slice)

    offset += UInt64(transferred)
    if offset == windowStart + windowBytes { finishWindow(endingAt: offset) }
}

if offset > windowStart { finishWindow(endingAt: offset) }

let wholeDigest = whole.finalize().compactMap { String(format: "%02x", $0) }.joined()
emit("windows", windowIndex)
emit("whole", "\(offset) \(wholeDigest)")
emit("elapsedSeconds", String(format: "%.1f", Date().timeIntervalSince(started)))
