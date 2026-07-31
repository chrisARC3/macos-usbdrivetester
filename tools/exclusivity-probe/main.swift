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
    // Balances the passRetained in `claim(_:timeout:)`.
    let outcome = Unmanaged<ClaimOutcome>.fromOpaque(context!).takeRetainedValue()
    if let dissenter {
        let status = DADissenterGetStatus(dissenter)
        outcome.message = "REFUSED (dissenter status 0x\(String(UInt32(bitPattern: status), radix: 16)))"
    } else {
        outcome.message = "GRANTED"
    }
    outcome.semaphore.signal()
}

/// Claim the disk, returning a human-readable outcome.
///
/// The context is **retained**, and the callback releases it. The first version passed
/// it unretained, so when the timeout below expired and the local deallocated, a late
/// callback dereferenced freed memory — that was the segfault. On a genuine timeout this
/// leaks one small object, which is the right trade in a probe: a leak is measurable, a
/// use-after-free corrupts the very measurement it crashes in the middle of.
func claim(_ disk: DADisk, timeout: TimeInterval = 6) -> String {
    let outcome = ClaimOutcome()
    DADiskClaim(disk, DADiskClaimOptions(kDADiskClaimOptionDefault),
                nil, nil, claimCallback, Unmanaged.passRetained(outcome).toOpaque())
    guard outcome.semaphore.wait(timeout: .now() + timeout) == .success else {
        // Not necessarily an error. A claim that is neither granted nor dissented is
        // *pending* — which is what a claim contended by another holder looks like.
        return "PENDING — no callback within \(Int(timeout))s (nobody dissented, "
             + "but it was not granted either)"
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

    let mountsBefore = mountedVolumes()
    line("mounted volumes", mountsBefore.isEmpty
         ? "none"
         : mountsBefore.map(\.from).joined(separator: ", ") + "  <- will block the open")

    guard let (session, disk) = makeSession() else {
        print("  DASessionCreate/DADiskCreateFromBSDName failed")
        exit(1)
    }

    // Claim first, and keep it: releasing the claim is what let macOS silently remount
    // the volume between phases on the previous run, which invalidated this whole phase.
    line("claim", claim(disk))

    // O_EXLOCK, not a plain O_RDWR open. Phase 2 established that a plain open excludes
    // nobody, so a holder using one would not be holding anything and the contention
    // this phase exists to measure would not exist.
    let fd = open(rawPath, O_RDWR | O_EXLOCK | O_NONBLOCK)
    if fd < 0 {
        line("open O_RDWR|O_EXLOCK", errnoText(errno))
        print("NOT-HOLDING")     // the parent script must not proceed as if we were
        DADiskUnclaim(disk)
        _ = session
        exit(1)
    }
    line("open O_RDWR|O_EXLOCK", "SUCCEEDED (fd \(fd)) — exclusive lock held")

    print("HOLDING")             // the parent script waits for this line
    Thread.sleep(forTimeInterval: seconds)

    close(fd)
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

// --- Classification, measured FIRST --------------------------------------------------
//
// This ran at the *end* on the previous version and reported "held by another process"
// in a phase where nothing else held the disk. It was measuring the battery's own
// leftovers: a pending claim from this process's second session, and a DADiskUnclaim
// that does not appear to settle synchronously. Running it before anything else is
// touched is the only way it describes the system rather than the probe.

print("\nFR-SAFE-4 classification (measured before this probe touches anything):")
print("  volumes mounted:        \(anyMounted ? "YES" : "no")")
let classifyFD = open(rawPath, O_RDWR | O_EXLOCK | O_NONBLOCK)
let classifyErrno = errno
if classifyFD >= 0 {
    print("  O_EXLOCK acquirable:    YES")
    close(classifyFD)
} else {
    print("  O_EXLOCK acquirable:    no (errno \(classifyErrno))")
}

switch (anyMounted, classifyFD >= 0) {
case (true, _):
    print("  => cause (a): volumes are mounted. Refuse and name them.")
case (false, false):
    print("  => cause (b): unmounted, but the node is held by another process.")
case (false, true):
    print("  => neither: the device is available and can be acquired.")
}

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

print("\nDone. Nothing was written to the device.")
print("(The classification above was measured before these tests ran; anything this")
print(" probe leaves claimed or locked cannot have influenced it.)")
