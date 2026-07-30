//
//  main.swift
//  exclusivity-probe — establish what "exclusive whole-disk access" actually means
//  on this OS, before Step 6 is designed around an assumption about it.
//
//  ## Why this exists
//
//  FR-SAFE-3 requires exclusive whole-disk access, and FR-SAFE-4(b) requires the tool
//  to distinguish "volumes unmounted but the node is claimed by another process" from
//  "volumes still mounted". Both depend on behaviour that is easy to assume and easy to
//  get wrong:
//
//    * Does opening /dev/rdiskN O_RDWR fail while a volume is mounted?
//    * Once unmounted, does it succeed?
//    * Do TWO processes both get an O_RDWR handle? If they do, then `open` alone cannot
//      detect FR-SAFE-4(b) and the exclusivity has to come from somewhere else.
//    * Does O_EXLOCK work on a raw disk device?
//    * Does DADiskClaim actually refuse a second claimant?
//
//  Step 5 produced one defect, and it came from exactly this class of thing — assuming
//  how a system service behaves instead of measuring it. This is the measurement.
//
//  ## Safety
//
//  **This probe never writes.** It opens, inspects, locks, claims, then closes and
//  releases. `O_RDWR` appears only because opening for write is what the real code will
//  do and its failure mode is the thing being measured — no `write`, `pwrite`, `ftruncate`
//  or ioctl that alters state is issued anywhere in this file.
//
//  Requires root, because /dev/rdiskN is root:operator.
//
//  Usage:  sudo exclusivity-probe disk4
//

import Foundation
import DiskArbitration

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: exclusivity-probe <disk4>\n".utf8))
    exit(2)
}
let bsdName = arguments[1]
let rawPath = "/dev/r\(bsdName)"

func result(_ label: String, _ detail: String) {
    print("  \(label.padding(toLength: 46, withPad: " ", startingAt: 0))\(detail)")
}

func describeErrno(_ code: Int32) -> String {
    "failed — errno \(code) (\(String(cString: strerror(code))))"
}

print("exclusivity-probe on \(rawPath)  (uid \(getuid()))")
print(String(repeating: "=", count: 78))

// MARK: - What is mounted right now

print("\nMounted volumes on \(bsdName):")
var foundMount = false
let count = getfsstat(nil, 0, MNT_NOWAIT)
if count > 0 {
    var stats = Array(repeating: statfs(), count: Int(count))
    let written = getfsstat(&stats, Int32(MemoryLayout<statfs>.stride * Int(count)), MNT_NOWAIT)
    for entry in stats.prefix(Int(max(written, 0))) {
        let from = withUnsafePointer(to: entry.f_mntfromname) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<(CChar)>.size * 1024) {
                String(cString: $0)
            }
        }
        let on = withUnsafePointer(to: entry.f_mntonname) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<(CChar)>.size * 1024) {
                String(cString: $0)
            }
        }
        if from.hasPrefix("/dev/\(bsdName)") {
            print("  \(from) -> \(on)")
            foundMount = true
        }
    }
}
if !foundMount { print("  (none — the disk has no mounted volumes)") }

// MARK: - 1. open O_RDWR

print("\n1. open(\(rawPath), O_RDWR)")
let firstFD = open(rawPath, O_RDWR)
if firstFD < 0 {
    result("first open", describeErrno(errno))
} else {
    result("first open", "SUCCEEDED (fd \(firstFD))")
}

// MARK: - 2. a second, independent O_RDWR handle
//
// The load-bearing question. If this also succeeds, `open` does not give exclusivity
// and cannot be what FR-SAFE-4(b) detects.

print("\n2. second, independent open(\(rawPath), O_RDWR)")
let secondFD = open(rawPath, O_RDWR)
if secondFD < 0 {
    result("second open", describeErrno(errno) + "  <- open IS exclusive")
} else {
    result("second open", "SUCCEEDED (fd \(secondFD))  <- open is NOT exclusive on its own")
    close(secondFD)
}

// MARK: - 3. O_EXLOCK

print("\n3. open(\(rawPath), O_RDWR | O_EXLOCK | O_NONBLOCK)")
if firstFD >= 0 {
    result("while our own fd is open", "skipped (would test our own lock)")
}
let lockFD = open(rawPath, O_RDWR | O_EXLOCK | O_NONBLOCK)
if lockFD < 0 {
    result("exclusive-lock open", describeErrno(errno))
} else {
    result("exclusive-lock open", "SUCCEEDED (fd \(lockFD))")
    let contendFD = open(rawPath, O_RDWR | O_EXLOCK | O_NONBLOCK)
    if contendFD < 0 {
        result("second exclusive-lock open", describeErrno(errno) + "  <- O_EXLOCK works here")
    } else {
        result("second exclusive-lock open", "SUCCEEDED  <- O_EXLOCK does NOT exclude")
        close(contendFD)
    }
    close(lockFD)
}

if firstFD >= 0 { close(firstFD) }

// MARK: - 4. DADiskClaim

print("\n4. DADiskClaim")
guard let session = DASessionCreate(kCFAllocatorDefault) else {
    result("DASessionCreate", "failed")
    exit(1)
}
DASessionSetDispatchQueue(session, DispatchQueue.main)

guard let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, bsdName) else {
    result("DADiskCreateFromBSDName", "failed")
    exit(1)
}

final class ClaimOutcome: @unchecked Sendable {
    let semaphore = DispatchSemaphore(value: 0)
    var message = "no callback"
}
let firstClaim = ClaimOutcome()

let claimCallback: DADiskClaimCallback = { _, dissenter, context in
    let outcome = Unmanaged<ClaimOutcome>.fromOpaque(context!).takeUnretainedValue()
    if let dissenter {
        let status = DADissenterGetStatus(dissenter)
        outcome.message = "REFUSED (dissenter status 0x\(String(status, radix: 16)))"
    } else {
        outcome.message = "GRANTED"
    }
    outcome.semaphore.signal()
}

DADiskClaim(disk, DADiskClaimOptions(kDADiskClaimOptionDefault),
            nil, nil, claimCallback, Unmanaged.passUnretained(firstClaim).toOpaque())

// Pump the main queue while waiting, since DA delivers there.
let deadline = Date().addingTimeInterval(5)
while firstClaim.semaphore.wait(timeout: .now() + 0.05) == .timedOut, Date() < deadline {
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}
result("first claim", firstClaim.message)

// A second session is a genuinely separate claimant, which is what a competing
// process would look like.
if let otherSession = DASessionCreate(kCFAllocatorDefault),
   let otherDisk = DADiskCreateFromBSDName(kCFAllocatorDefault, otherSession, bsdName) {
    DASessionSetDispatchQueue(otherSession, DispatchQueue.main)
    let secondClaim = ClaimOutcome()
    DADiskClaim(otherDisk, DADiskClaimOptions(kDADiskClaimOptionDefault),
                nil, nil, claimCallback, Unmanaged.passUnretained(secondClaim).toOpaque())
    let deadline2 = Date().addingTimeInterval(5)
    while secondClaim.semaphore.wait(timeout: .now() + 0.05) == .timedOut, Date() < deadline2 {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    result("second claim (separate session)", secondClaim.message)
    DADiskUnclaim(otherDisk)
}

DADiskUnclaim(disk)
result("released", "both claims unclaimed")

print("\nDone. Nothing was written to the device.")
