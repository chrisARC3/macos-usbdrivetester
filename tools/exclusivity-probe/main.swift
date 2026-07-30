//
//  main.swift
//  exclusivity-probe — establish what "exclusive whole-disk access" actually means
//  on this OS, before Step 6 is designed around an assumption about it.
//
//  ## Why this exists
//
//  FR-SAFE-3 requires exclusive whole-disk access, and FR-SAFE-4(b) requires the tool to
//  distinguish "volumes unmounted but the node is claimed by another process" from
//  "volumes still mounted". Which mechanism actually provides that exclusivity decides
//  the acquire path — and whether the second case is detectable at all.
//
//  ## Safety
//
//  **This probe never writes.** It opens, locks, claims, then closes and releases.
//  `O_RDWR` appears only because opening for write is what the real code will do and its
//  failure mode is the thing being measured. No `write`, `pwrite`, `ftruncate`, or
//  state-changing ioctl appears anywhere in this file.
//
//  Requires root, because /dev/rdiskN is root:operator.
//
//  Usage:
//      exclusivity-probe <disk4>                 run the measurement battery
//      exclusivity-probe <disk4> --hold <secs>   claim + open and hold, so another
//                                                process can measure what it sees
//
//  ## Lessons from the first version, which produced a wrong answer
//
//  1. It printed "open IS exclusive" when a second open failed — but in the mounted
//     phase *both* opens fail with EBUSY because a volume is mounted, which says nothing
//     about mutual exclusion. A verdict is now printed only when the first open
//     succeeded, so the conclusion cannot outrun the evidence.
//  2. It set the DiskArbitration session's queue to `main` and then pumped the main run
//     loop while waiting on a semaphore, and the second claim's callback never arrived.
//     Callbacks now go to a background queue and the main thread simply waits.
//  3. It tested a second claim from a second session in the *same process*. FR-SAFE-4(b)
//     is about another **process**, which is what `--hold` now provides.
//

import Foundation
import DiskArbitration

// MARK: - Arguments

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: exclusivity-probe <disk4> [--hold <secs>]\n".utf8))
    exit(2)
}
let bsdName = arguments[1]
let rawPath = "/dev/r\(bsdName)"

var holdSeconds: Double?
if let index = arguments.firstIndex(of: "--hold"), index + 1 < arguments.count {
    holdSeconds = Double(arguments[index + 1]) ?? 10
}

setvbuf(stdout, nil, _IOLBF, 0)

// MARK: - Helpers

func line(_ label: String, _ detail: String) {
    print("  \(label.padding(toLength: 44, withPad: " ", startingAt: 0))\(detail)")
}

func errnoText(_ code: Int32) -> String {
    "failed — errno \(code) (\(String(cString: strerror(code))))"
}

/// Mounted volumes on this disk, by device node.
func mountedVolumes() -> [(from: String, on: String)] {
    let count = getfsstat(nil, 0, MNT_NOWAIT)
    guard count > 0 else { return [] }
    var stats = Array(repeating: statfs(), count: Int(count))
    let written = getfsstat(&stats, Int32(MemoryLayout<statfs>.stride * Int(count)), MNT_NOWAIT)
    guard written > 0 else { return [] }

    func text<T>(_ tuple: T) -> String {
        withUnsafePointer(to: tuple) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) {
                String(cString: $0)
            }
        }
    }
    return stats.prefix(Int(written)).compactMap { entry in
        let from = text(entry.f_mntfromname)
        guard from.hasPrefix("/dev/\(bsdName)") else { return nil }
        return (from: from, on: text(entry.f_mntonname))
    }
}

// MARK: - DiskArbitration

/// Callbacks are delivered here, never on main, so the main thread can simply wait on a
/// semaphore. The first version pumped the main run loop instead and lost a callback.
let daQueue = DispatchQueue(label: "exclusivity-probe.da")

final class ClaimOutcome: @unchecked Sendable {
    let semaphore = DispatchSemaphore(value: 0)
    var message = ""
}

let claimCallback: DADiskClaimCallback = { _, dissenter, context in
    let outcome = Unmanaged<ClaimOutcome>.fromOpaque(context!).takeUnretainedValue()
    if let dissenter {
        let status = DADissenterGetStatus(dissenter)
        outcome.message = "REFUSED (dissenter status 0x\(String(UInt32(bitPattern: status), radix: 16)))"
    } else {
        outcome.message = "GRANTED"
    }
    outcome.semaphore.signal()
}

/// Claim the disk, returning a human-readable outcome.
func claim(_ disk: DADisk, timeout: TimeInterval = 6) -> String {
    let outcome = ClaimOutcome()
    DADiskClaim(disk, DADiskClaimOptions(kDADiskClaimOptionDefault),
                nil, nil, claimCallback, Unmanaged.passUnretained(outcome).toOpaque())
    guard outcome.semaphore.wait(timeout: .now() + timeout) == .success else {
        return "no callback within \(Int(timeout))s"
    }
    return outcome.message
}

func makeSession() -> (DASession, DADisk)? {
    guard let session = DASessionCreate(kCFAllocatorDefault),
          let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, bsdName) else {
        return nil
    }
    DASessionSetDispatchQueue(session, daQueue)
    return (session, disk)
}

// MARK: - Hold mode (a genuinely separate claimant)

if let seconds = holdSeconds {
    print("exclusivity-probe HOLD on \(rawPath) for \(Int(seconds))s  (pid \(getpid()), uid \(getuid()))")

    guard let (session, disk) = makeSession() else {
        print("  DASessionCreate/DADiskCreateFromBSDName failed")
        exit(1)
    }
    line("claim", claim(disk))

    let fd = open(rawPath, O_RDWR)
    line("open O_RDWR", fd < 0 ? errnoText(errno) : "SUCCEEDED (fd \(fd))")

    print("HOLDING")            // the parent script waits for this line
    Thread.sleep(forTimeInterval: seconds)

    if fd >= 0 { close(fd) }
    DADiskUnclaim(disk)
    _ = session
    print("released")
    exit(0)
}

// MARK: - Measurement battery

print("exclusivity-probe on \(rawPath)  (pid \(getpid()), uid \(getuid()))")
print(String(repeating: "=", count: 78))

let mounts = mountedVolumes()
print("\nMounted volumes on \(bsdName):")
if mounts.isEmpty {
    print("  (none)")
} else {
    for mount in mounts { print("  \(mount.from) -> \(mount.on)") }
}
let anyMounted = !mounts.isEmpty

// --- 1 & 2: plain O_RDWR opens -------------------------------------------------------

print("\n1. open(\(rawPath), O_RDWR)")
let firstFD = open(rawPath, O_RDWR)
let firstErrno = errno
line("first open", firstFD < 0 ? errnoText(firstErrno) : "SUCCEEDED (fd \(firstFD))")

print("\n2. second, independent open(\(rawPath), O_RDWR), first still held")
if firstFD < 0 {
    // The critical fix: with the first open already failed, a second failure says
    // nothing about mutual exclusion. Refuse to draw the conclusion.
    line("second open", "not attempted — the first open failed, so this")
    line("", "would measure nothing about exclusivity")
} else {
    let secondFD = open(rawPath, O_RDWR)
    if secondFD < 0 {
        line("second open", errnoText(errno))
        line("VERDICT", "a plain O_RDWR open IS mutually exclusive")
    } else {
        line("second open", "SUCCEEDED (fd \(secondFD))")
        line("VERDICT", "a plain O_RDWR open is NOT exclusive on its own")
        close(secondFD)
    }
}
if firstFD >= 0 { close(firstFD) }

// --- 3: O_EXLOCK ---------------------------------------------------------------------

print("\n3. open(\(rawPath), O_RDWR | O_EXLOCK | O_NONBLOCK)")
let lockFD = open(rawPath, O_RDWR | O_EXLOCK | O_NONBLOCK)
if lockFD < 0 {
    line("exclusive-lock open", errnoText(errno))
    if anyMounted {
        line("", "(expected while a volume is mounted)")
    }
} else {
    line("exclusive-lock open", "SUCCEEDED (fd \(lockFD))")
    let contendFD = open(rawPath, O_RDWR | O_EXLOCK | O_NONBLOCK)
    if contendFD < 0 {
        line("second exclusive-lock open", errnoText(errno))
        line("VERDICT", "O_EXLOCK excludes a second locker")
    } else {
        line("second exclusive-lock open", "SUCCEEDED")
        line("VERDICT", "O_EXLOCK does NOT exclude")
        close(contendFD)
    }
    close(lockFD)
}

// --- 4: DADiskClaim ------------------------------------------------------------------

print("\n4. DADiskClaim")
guard let (session, disk) = makeSession() else {
    line("DASessionCreate", "failed")
    exit(1)
}
line("first claim (this process)", claim(disk))

if let (otherSession, otherDisk) = makeSession() {
    line("second claim (same process, new session)", claim(otherDisk))
    DADiskUnclaim(otherDisk)
    _ = otherSession
}

DADiskUnclaim(disk)
line("released", "unclaimed")

// --- Summary -------------------------------------------------------------------------

print("\nSummary for this phase:")
print("  volumes mounted: \(anyMounted ? "YES — exclusivity results below are not meaningful" : "no")")
print("  O_RDWR open:     \(firstFD < 0 ? "refused (errno \(firstErrno))" : "granted")")
print("\nDone. Nothing was written to the device.")
