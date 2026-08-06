//
//  main.swift
//  large-address-probe — proves a device can be addressed above the 32-bit block boundary.
//
//  ## The question, precisely
//
//  NFR-COMPAT-6 requires 64-bit block offsets and counts "with no capacity-related limits
//  short of the device's own". Step 7's gate could not discharge it: the scratch device is 1,953,525,168
//  blocks, *below* 2³², so a USB bridge that truncated its block count to 32 bits would be
//  indistinguishable there from a correct one — and the failure mode is silent. The tool would
//  test the first portion of a larger drive and report a clean pass.
//
//  The Seagate is 42,970,644,479 blocks, ten times past the boundary. A 32-bit truncation would
//  report **20,971,519 blocks — 10.7 GB instead of 22 TB**, which is the specific wrong answer
//  this probe exists to rule out.
//
//  ## OPENED READ-ONLY. This is a deliberate departure from the helper's flags.
//
//  `DeviceClaim` opens `O_RDWR | O_EXLOCK | O_NONBLOCK`, and every other probe in this project
//  matches that on purpose. **This one does not**, because the drive it targets is not the
//  designated scratch device — the Seagate carries a live filesystem — and the departure buys three
//  guarantees that matter more here than flag fidelity:
//
//    1. `O_RDONLY` means the descriptor **physically cannot write**. A bug in this file cannot
//       damage the drive; the kernel refuses with `EBADF`.
//    2. No `O_EXLOCK` means **nothing has to be unmounted**. Measured 2026-08-01: `O_RDONLY`
//       on a raw node succeeds while volumes are mounted, whereas `O_RDWR` fails `EBUSY`.
//    3. No exclusive lock means no lock to release, so the DiskArbitration re-probe-and-remount
//       that follows releasing one (measured ~4 ms) never happens.
//
//  The fidelity cost is acceptable because of *what* is being asked. Whether the ioctls report
//  a 64-bit block count, and whether `pread` reaches a block above 2³², are properties of the
//  device, the bridge and the kernel — not of the open mode. Alignment and exclusivity
//  semantics were established separately and are not under test here.
//
//  ## It never writes
//
//  No `pwrite`, no `write` to the device, no `O_TRUNC`, no `O_CREAT`. `scripts/large-address-check.sh`
//  asserts that against this source, with comments stripped, before it will run the binary.
//
//  ## What it checks
//
//  1. **The block count is 64-bit.** Above 2³², and not equal to its own 32-bit truncation.
//  2. **Reads succeed across the boundary** — at block 0, at the last 32-bit-addressable block,
//     at the first block that needs more than 32 bits, and at the very last block.
//  3. **A read one block past the end FAILS.** This is the decisive one: if addressing wrapped
//     or the size were truncated, that read would land on a valid low block and succeed.
//     Succeeding at the last block and failing one past it brackets the device exactly, which
//     is only possible if 64-bit addressing holds end to end.
//  4. **The last block is not an alias of its 32-bit-wrapped twin**, as a direct check for
//     silent wrapping.
//
//  Device contents are never printed or logged — only whether two blocks matched and whether a
//  block was all zeroes (NFR-SEC-6).
//
//  Usage:
//      sudo large-address-probe <bsdName>
//

import Foundation

func emit(_ key: String, _ value: Any) { print("\(key)=\(value)") }
func errnoText(_ code: Int32) -> String { String(cString: strerror(code)) }

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("large-address-probe: \(message)\n".utf8))
    exit(1)
}

// MARK: - ioctl requests (see Core/DiskIOControl.swift for why these are re-derived)

func _IOR<T>(_ group: UnicodeScalar, _ number: UInt, _ type: T.Type) -> UInt {
    let length = UInt(MemoryLayout<T>.size) & 0x1fff
    return 0x4000_0000 | (length << 16) | (UInt(group.value) << 8) | number
}
let dkiocGetBlockSize  = _IOR("d", 24, UInt32.self)     // 0x40046418
let dkiocGetBlockCount = _IOR("d", 25, UInt64.self)     // 0x40086419

// MARK: - Arguments

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: sudo large-address-probe <bsdName>\n".utf8))
    exit(2)
}
let bsdName = arguments[1]

guard bsdName.hasPrefix("disk") else { fail("\"\(bsdName)\" is not a whole-disk BSD name") }
let digits = bsdName.dropFirst(4)
guard !digits.isEmpty, digits.allSatisfy({ $0 >= "0" && $0 <= "9" }),
      let unit = UInt32(digits), "disk\(unit)" == bsdName else {
    fail("\"\(bsdName)\" is not a canonical whole-disk name")
}
guard getuid() == 0 else { fail("must run as root: sudo large-address-probe \(bsdName)") }

let rawPath = "/dev/r\(bsdName)"
setvbuf(stdout, nil, _IOLBF, 0)

emit("probe.device", bsdName)
emit("probe.rawPath", rawPath)
emit("probe.openFlags", "O_RDONLY (read-only by construction; nothing is unmounted)")

// MARK: - Open, read-only

let fd = open(rawPath, O_RDONLY)
guard fd >= 0 else {
    let code = errno
    emit("open", "FAILED")
    emit("open.errno", code)
    emit("open.errnoText", errnoText(code))
    fail("could not open \(rawPath) read-only (errno \(code), \(errnoText(code)))")
}
defer { close(fd) }
emit("open", "ok")

// MARK: - Geometry

var blockSize: UInt32 = 0
var blockCount: UInt64 = 0
guard ioctl(fd, dkiocGetBlockSize, &blockSize) == 0 else {
    fail("DKIOCGETBLOCKSIZE failed: errno \(errno) (\(errnoText(errno)))")
}
guard ioctl(fd, dkiocGetBlockCount, &blockCount) == 0 else {
    fail("DKIOCGETBLOCKCOUNT failed: errno \(errno) (\(errnoText(errno)))")
}

let byteCount = blockCount * UInt64(blockSize)
let truncated = blockCount & 0xFFFF_FFFF

emit("geometry.logicalBlockSize", blockSize)
emit("geometry.blockCount", blockCount)
emit("geometry.byteCount", byteCount)
emit("geometry.exceeds32Bit", blockCount > UInt64(UInt32.max))
emit("geometry.ifTruncatedTo32Bit", truncated)
emit("geometry.ifTruncatedCapacityBytes", truncated * UInt64(blockSize))

guard blockCount > UInt64(UInt32.max) else {
    emit("verdict", "NOT_APPLICABLE")
    emit("verdict.detail",
         "\(bsdName) is \(blockCount) blocks, at or below 2^32 — it cannot test this boundary")
    exit(2)
}

// MARK: - Buffer

var raw: UnsafeMutableRawPointer?
let alignment = Int(getpagesize())
guard posix_memalign(&raw, alignment, Int(blockSize)) == 0, let buffer = raw else {
    fail("could not allocate an aligned \(blockSize)-byte buffer")
}
defer { free(buffer) }

var comparison: UnsafeMutableRawPointer?
guard posix_memalign(&comparison, alignment, Int(blockSize)) == 0, let compareBuffer = comparison else {
    fail("could not allocate the comparison buffer")
}
defer { free(compareBuffer) }

/// Read one block. Returns bytes transferred, or a negative errno.
func readBlock(_ block: UInt64, into destination: UnsafeMutableRawPointer) -> (bytes: Int, code: Int32) {
    let offset = block * UInt64(blockSize)
    guard let start = off_t(exactly: offset) else { return (0, EOVERFLOW) }
    let result = pread(fd, destination, Int(blockSize), start)
    return result < 0 ? (0, errno) : (result, 0)
}

func isAllZero(_ pointer: UnsafeMutableRawPointer) -> Bool {
    let bytes = UnsafeRawBufferPointer(start: pointer, count: Int(blockSize))
    return bytes.allSatisfy { $0 == 0 }
}

// MARK: - Reads across the boundary

let boundary = UInt64(UInt32.max) + 1            // 4,294,967,296
let lastBlock = blockCount - 1

let probes: [(label: String, block: UInt64)] = [
    ("block0",              0),
    ("last32BitBlock",      boundary - 1),
    ("firstBlockPast32Bit", boundary),
    ("wellPast32Bit",       boundary + 1_000_000),
    ("lastBlock",           lastBlock),
]

var failures = 0

for probe in probes {
    let byteOffset = probe.block * UInt64(blockSize)
    let (bytes, code) = readBlock(probe.block, into: buffer)
    emit("\(probe.label).block", probe.block)
    emit("\(probe.label).byteOffset", byteOffset)
    if code != 0 {
        emit("\(probe.label).result", "FAILED")
        emit("\(probe.label).errno", code)
        emit("\(probe.label).errnoText", errnoText(code))
        failures += 1
    } else if bytes != Int(blockSize) {
        emit("\(probe.label).result", "SHORT (\(bytes) of \(blockSize) bytes)")
        failures += 1
    } else {
        emit("\(probe.label).result", "ok")
        emit("\(probe.label).allZero", isAllZero(buffer))
    }
}

// MARK: - The decisive check: one block past the end must FAIL

let pastEnd = blockCount
let (pastBytes, pastCode) = readBlock(pastEnd, into: buffer)
emit("pastEnd.block", pastEnd)
emit("pastEnd.byteOffset", pastEnd * UInt64(blockSize))
if pastCode != 0 {
    emit("pastEnd.result", "correctly refused")
    emit("pastEnd.errno", pastCode)
    emit("pastEnd.errnoText", errnoText(pastCode))
} else if pastBytes == 0 {
    emit("pastEnd.result", "correctly refused (0 bytes returned)")
} else {
    emit("pastEnd.result", "RETURNED \(pastBytes) BYTES — the device addressed past its own end")
    failures += 1
}

// MARK: - Aliasing: the last block must not be its 32-bit-wrapped twin

let wrappedTwin = lastBlock & 0xFFFF_FFFF
emit("aliasing.lastBlock", lastBlock)
emit("aliasing.wrappedTwin", wrappedTwin)

let (lastBytes, lastCode) = readBlock(lastBlock, into: buffer)
let (twinBytes, twinCode) = readBlock(wrappedTwin, into: compareBuffer)

if lastCode == 0, twinCode == 0, lastBytes == Int(blockSize), twinBytes == Int(blockSize) {
    let identical = memcmp(buffer, compareBuffer, Int(blockSize)) == 0
    let bothZero = isAllZero(buffer) && isAllZero(compareBuffer)
    emit("aliasing.identical", identical)
    emit("aliasing.bothAllZero", bothZero)
    if identical && !bothZero {
        emit("aliasing.result", "SUSPICIOUS — the last block matches its 32-bit-wrapped twin")
        failures += 1
    } else if identical && bothZero {
        emit("aliasing.result",
             "inconclusive — both blocks are all zeroes, so a match proves nothing either way")
    } else {
        emit("aliasing.result", "distinct — no 32-bit wrapping")
    }
} else {
    emit("aliasing.result", "could not read both blocks; see errno lines above")
    failures += 1
}

// MARK: - Verdict

emit("failures", failures)
if failures == 0 {
    emit("verdict", "PASS")
    emit("verdict.detail",
         "\(bsdName) reports \(blockCount) blocks (>2^32), reads succeed at and beyond the "
       + "boundary and at the last block, and a read one block past the end is refused — "
       + "64-bit addressing holds end to end. NFR-COMPAT-6 has hardware evidence.")
} else {
    emit("verdict", "FAIL")
    emit("verdict.detail", "\(failures) check(s) failed; see above")
}

print("""
      ---
      Nothing was written to \(bsdName). The descriptor was opened O_RDONLY, so writing was
      not possible, and no volume was unmounted.
      """)

exit(failures == 0 ? 0 : 1)
