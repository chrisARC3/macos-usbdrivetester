//
//  main.swift
//  mount-guard-client — drives the helper's Step 6 device methods from the CLI.
//
//  ## Why this exists
//
//  Step 6's gate has to show that the helper distinguishes FR-SAFE-4's two causes, and
//  cause (b) — "unmounted, but another process holds the node" — cannot be produced from
//  the GUI: something else has to be holding the disk at the moment the acquire happens.
//  `scripts/claim-contention-test.sh` arranges that with `exclusivity-probe --hold` and
//  uses this client to ask the helper what it sees.
//
//  It also moves the *classification* half of gate items 1 and 2 off "needs a person".
//  A human reading two prose messages can confirm they differ; this asserts the cause
//  code, which is the thing the app actually branches on.
//
//  ## Signed with the real Team ID, unlike tools/negative-client
//
//  `negative-client` is adhoc-signed on purpose, to prove the helper refuses foreign
//  callers. This one must be signed as Apple Development under team 5JC55GTLZA or the
//  helper will invalidate it on its first message and every result would read as a
//  transport failure. The script signs it and then asserts the Team ID is present —
//  the inverse of the check negative-test.sh makes.
//
//  ## One process, one connection — deliberately
//
//  The helper releases a device when the connection that acquired it goes away
//  (NFR-REL-5): a GUI that crashes mid-run must not leave a claim behind. That means
//  `acquire` in one invocation and `release` in another would not work — the claim would
//  be gone before the second process started. So commands are given as a list and run in
//  sequence on a single connection.
//
//  That behaviour is itself testable here: run `acquire` alone, let the process exit, and
//  a following `check` should report the device no longer held.
//
//  Usage:
//      mount-guard-client <bsdName> <command> [<command> ...]
//
//  Commands: check | acquire | profile | release | version | hold:<seconds>
//            wait:<sentinelPath>
//            digest:<startBlock>:<blockCount>
//            digest-all:<windowBytes>:<outputPath>[:<startBlock>:<blockCount>]
//            cycle:<startBlock>:<blockCount>[:<ioSizeBytes>[:<failureModeCode>]]
//
//  `profile` was added in Step 7. It is passive — it reports what `acquire` established and
//  performs no I/O — but it requires a device to be held, so it only makes sense after
//  `acquire` **in the same invocation**, for the reason above.
//
//  ⚠️  `cycle` was added in Step 8 and is the ONLY command here that **writes to the drive**.
//  It runs the read → write-back → read-verify cycle over the given block range of the held
//  device, so it also requires `acquire` in the same invocation. The helper caps one call at
//  `TesterProtocol.maximumBytesPerCall`. Never point it at a device whose contents matter:
//  the cycle is non-destructive by design and that design is what Step 8 exists to prove, not
//  something to assume while proving it.
//
//  Output is `KEY=value` on stdout, one fact per line, prefixed with the command — meant
//  for grep, not for reading aloud.
//

import Foundation

// MARK: - Arguments

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("""
        usage: mount-guard-client <bsdName> <command> [<command> ...]
               commands: check | acquire | profile | release | version | hold:<seconds>
                         wait:<sentinelPath>
                         digest:<startBlock>:<blockCount>
                         digest-all:<windowBytes>:<outputPath>[:<start>:<count>]
                         cycle:<startBlock>:<blockCount>[:<ioSizeBytes>[:<failureModeCode>]] (WRITES)

        """.utf8))
    exit(2)
}

let bsdName = arguments[1]
let commands = Array(arguments.dropFirst(2))

// UNBUFFERED, not line-buffered. `setvbuf(_IOLBF, size: 0)` does not reliably flush per line
// when stdout is a **pipe** rather than a terminal — and this client is always piped through
// `tee` by the gate script. Measured 2026-08-02: during a ~33-minute fingerprint pass, none of
// the per-50-window progress lines reached the terminal, because ~18 lines of ~40 bytes never
// fill a 4 KB buffer. Every earlier run finished in about ten seconds, so all output arrived at
// once and the problem was invisible.
//
// This tool emits a few hundred lines over an hour. Unbuffered costs nothing and means progress
// is progress rather than a promise to tell you later.
setvbuf(stdout, nil, _IONBF, 0)
print("mount-guard-client: pid \(getpid()) on \(bsdName)")

// MARK: - Connection

let connection = NSXPCConnection(machServiceName: HelperIdentity.machServiceName,
                                 options: .privileged)
connection.remoteObjectInterface = NSXPCInterface(with: TesterControl.self)
connection.invalidationHandler = {
    FileHandle.standardError.write(Data("connection invalidated\n".utf8))
}
connection.resume()

/// Tracks whether anything failed, so the exit status is usable in a script.
var transportFailed = false

/// Run one call, blocking until it replies or the connection errors.
///
/// Blocking the main thread is safe: XPC delivers reply blocks on its own queue, not on
/// this one.
///
/// - Parameter timeout: how long to wait. 30 s suits the passive queries; `cycle` overrides it,
///   because that call performs real I/O — at the 1 GiB cap and a 200 MiB/s floor it is ~15 s,
///   and a struggling drive is exactly the case worth waiting out rather than reporting as a
///   transport failure.
func call(_ label: String,
          timeout: TimeInterval = 30,
          _ body: (TesterControl, @escaping () -> Void) -> Void) {
    let semaphore = DispatchSemaphore(value: 0)
    var settled = false

    let proxy = connection.remoteObjectProxyWithErrorHandler { error in
        // A helper too old to implement these methods lands here, as does an unreachable
        // one. Both mean "access was not granted" — there is no permissive reading.
        print("[\(label)] TRANSPORT_ERROR=\(error.localizedDescription)")
        transportFailed = true
        if !settled { settled = true; semaphore.signal() }
    }

    guard let tester = proxy as? TesterControl else {
        print("[\(label)] TRANSPORT_ERROR=proxy did not conform to TesterControl")
        transportFailed = true
        return
    }

    body(tester) {
        if !settled { settled = true; semaphore.signal() }
    }

    if semaphore.wait(timeout: .now() + timeout) != .success {
        print("[\(label)] TRANSPORT_ERROR=no reply within \(Int(timeout))s")
        transportFailed = true
    }
}

// MARK: - Commands

for command in commands {
    switch command {
    case "check":
        call("check") { tester, done in
            tester.checkDeviceReadiness(bsdName: bsdName) { ready, count, summary, held, cause, message in
                print("[check] READY=\(ready ? 1 : 0)")
                print("[check] MOUNTED_COUNT=\(count)")
                print("[check] MOUNTED=\(summary)")
                print("[check] HELD=\(held ? 1 : 0)")
                print("[check] BLOCKING_CAUSE=\(cause)")
                print("[check] MESSAGE=\(message)")
                done()
            }
        }

    case "acquire":
        call("acquire") { tester, done in
            tester.acquireDevice(bsdName: bsdName) { acquired, causeCode, message in
                print("[acquire] ACQUIRED=\(acquired ? 1 : 0)")
                print("[acquire] CAUSE=\(causeCode)")
                print("[acquire] MESSAGE=\(message)")
                done()
            }
        }

    case "profile":
        // Step 7. Passive: reports what `acquire` established, performs no I/O, opens nothing.
        // Requires a device to be held, so this only makes sense after `acquire` in the same
        // invocation — the helper releases on connection loss, so a separate process would
        // find nothing held.
        call("profile") { tester, done in
            tester.deviceProfile { available, ioctlBlockSize, ioctlBlockCount,
                                   ioKitBlockSize, ioKitBlockCount,
                                   cacheBypass, linkSpeedCode, maxByteCountRead, message in
                print("[profile] AVAILABLE=\(available ? 1 : 0)")
                print("[profile] IOCTL_BLOCK_SIZE=\(ioctlBlockSize)")
                print("[profile] IOCTL_BLOCK_COUNT=\(ioctlBlockCount)")
                print("[profile] IOCTL_BYTE_COUNT=\(UInt64(ioctlBlockSize) * ioctlBlockCount)")
                print("[profile] IOKIT_BLOCK_SIZE=\(ioKitBlockSize)")
                print("[profile] IOKIT_BLOCK_COUNT=\(ioKitBlockCount)")
                print("[profile] CACHE_BYPASS=\(cacheBypass)")
                print("[profile] LINK_SPEED_CODE=\(linkSpeedCode)")
                print("[profile] MAX_BYTE_COUNT_READ=\(maxByteCountRead)")
                print("[profile] MESSAGE=\(message)")
                done()
            }
        }

    case "release":
        call("release") { tester, done in
            tester.releaseDevice { released, message in
                print("[release] RELEASED=\(released ? 1 : 0)")
                print("[release] MESSAGE=\(message)")
                done()
            }
        }

    case "version":
        // Step 8. The gate drives a *live* daemon, and `runRetentionCycle` arrived in v6: a
        // v5 daemon would fail that call as a transport error, which reads like a broken
        // connection rather than "the installed helper is out of date".
        call("version") { tester, done in
            tester.protocolVersion { version in
                print("[version] PROTOCOL=\(version)")
                print("[version] EXPECTED=\(TesterProtocol.version)")
                done()
            }
        }

    case let waiting where waiting.hasPrefix("wait:"):
        // Step 8. Blocks until a sentinel file appears, so a *separate* process can do work
        // while this one keeps the connection — and therefore the claim — alive.
        //
        // The gate needs exactly that: both media digests must be taken inside the same claim
        // window, because releasing makes DiskArbitration remount ~4 ms later and a mounted
        // exFAT volume writes to itself. Without this, the "after" digest would differ for
        // reasons that have nothing to do with the cycle.
        //
        // A fixed `hold:` cannot do the job: a whole-device digest of a 1 TB drive takes ~35
        // minutes, and a sleep long enough to cover it would be a guess that fails silently
        // when it is short.
        let sentinel = String(waiting.dropFirst("wait:".count))
        print("[wait] PATH=\(sentinel)")
        let deadline = Date().addingTimeInterval(7_200)      // two hours: two full digest passes
        var timedOut = false
        while !FileManager.default.fileExists(atPath: sentinel) {
            if Date() > deadline { timedOut = true; break }
            Thread.sleep(forTimeInterval: 0.25)
        }
        if timedOut {
            print("[wait] TIMEOUT=1")
            transportFailed = true
        } else {
            print("[wait] DONE=1")
        }

    case let digest where digest.hasPrefix("digest-all:"):
        // Step 8. Fingerprints the WHOLE held device, one bounded call per window, writing the
        // vector to a file.
        //
        //   digest-all:<windowBytes>:<outputPath>
        //
        // The helper caps a single call at TesterProtocol.maximumBytesPerCall, so a whole
        // device is many calls — ~932 of them for a 1 TB drive at a 1 GiB window. That is the
        // point rather than a workaround: there is no cancellation until Step 11, so no single
        // privileged call may occupy the daemon for the ~35 minutes a full pass takes.
        //
        // Geometry comes from `deviceProfile`, which is the ioctl-derived authority — not from
        // `diskutil`, and not from anything this client assumed.
        let digestFields = digest.dropFirst("digest-all:".count)
            .split(separator: ":", omittingEmptySubsequences: false)
        guard digestFields.count >= 2,
              let windowBytes = UInt64(digestFields[0]), windowBytes > 0 else {
            FileHandle.standardError.write(Data("""
                bad digest-all command '\(digest)'
                usage: digest-all:<windowBytes>:<outputPath>[:<startBlock>:<blockCount>]
                       startBlock/blockCount default to the whole device; blockCount 0 means
                       "to the end".

                """.utf8))
            exit(2)
        }
        let outputPath = String(digestFields[1])
        let requestedStart = digestFields.count >= 3 ? (UInt64(digestFields[2]) ?? 0) : 0
        let requestedCount = digestFields.count >= 4 ? (UInt64(digestFields[3]) ?? 0) : 0

        var deviceBlockSize: UInt32 = 0
        var deviceBlockCount: UInt64 = 0
        call("digest") { tester, done in
            tester.deviceProfile { available, ioctlBlockSize, ioctlBlockCount, _, _, _, _, _, message in
                if available {
                    deviceBlockSize = ioctlBlockSize
                    deviceBlockCount = ioctlBlockCount
                } else {
                    print("[digest] PROFILE_UNAVAILABLE=\(message)")
                }
                done()
            }
        }

        guard deviceBlockSize > 0, deviceBlockCount > 0 else {
            print("[digest] FAILED=no geometry; a device must be acquired first")
            transportFailed = true
            break
        }

        let windowBlocks = Swift.max(UInt64(1), windowBytes / UInt64(deviceBlockSize))

        // Clamp the requested coverage to the device. A range past the end would be refused
        // per-call by the helper, which is correct but would report as a digest failure rather
        // than as a caller asking for something impossible.
        let coverStart = Swift.min(requestedStart, deviceBlockCount)
        let coverCount = requestedCount == 0
            ? deviceBlockCount - coverStart
            : Swift.min(requestedCount, deviceBlockCount - coverStart)
        let coverEnd = coverStart + coverCount

        var lines: [String] = []
        var windowIndex: UInt64 = 0
        var nextBlock = coverStart
        var digestFailed = false

        print("[digest] BLOCK_SIZE=\(deviceBlockSize)")
        print("[digest] BLOCK_COUNT=\(deviceBlockCount)")
        print("[digest] WINDOW_BLOCKS=\(windowBlocks)")
        print("[digest] COVER_START=\(coverStart)")
        print("[digest] COVER_BLOCKS=\(coverCount)")

        while nextBlock < coverEnd && !digestFailed {
            let blocks = Swift.min(windowBlocks, coverEnd - nextBlock)
            let start = nextBlock
            call("digest", timeout: 600) { tester, done in
                tester.digestRange(startBlock: start, blockCount: blocks) { ok, bytes, hex, message in
                    if ok {
                        lines.append("window \(windowIndex) \(start) \(blocks) \(hex)")
                    } else {
                        print("[digest] FAILED=\(message)")
                        digestFailed = true
                    }
                    _ = bytes
                    done()
                }
            }
            nextBlock += blocks
            windowIndex += 1
            if windowIndex % 50 == 0 {
                print("[digest] PROGRESS=\(nextBlock - coverStart)/\(coverCount) blocks")
            }
        }

        if digestFailed {
            transportFailed = true
        } else {
            do {
                try (lines.joined(separator: "\n") + "\n").write(toFile: outputPath,
                                                                 atomically: true,
                                                                 encoding: .utf8)
                print("[digest] WINDOWS=\(windowIndex)")
                print("[digest] OUTPUT=\(outputPath)")
            } catch {
                print("[digest] FAILED=could not write \(outputPath): \(error)")
                transportFailed = true
            }
        }

    case let digest where digest.hasPrefix("digest:"):
        // A single window, for diagnostics: digest:<startBlock>:<blockCount>
        let fields = digest.dropFirst("digest:".count).split(separator: ":")
        guard fields.count == 2,
              let start = UInt64(fields[0]), let blocks = UInt64(fields[1]) else {
            FileHandle.standardError.write(Data("usage: digest:<startBlock>:<blockCount>\n".utf8))
            exit(2)
        }
        call("digest", timeout: 600) { tester, done in
            tester.digestRange(startBlock: start, blockCount: blocks) { ok, bytes, hex, message in
                print("[digest] OK=\(ok ? 1 : 0)")
                print("[digest] BYTES=\(bytes)")
                print("[digest] SHA256=\(hex)")
                print("[digest] MESSAGE=\(message)")
                done()
            }
        }

    case let cycle where cycle.hasPrefix("cycle:"):
        // Step 8. THE ONLY COMMAND HERE THAT WRITES TO THE DRIVE.
        //
        //   cycle:<startBlock>:<blockCount>[:<ioSizeBytes>[:<failureModeCode>]]
        //
        // Requires `acquire` earlier in the same invocation — the helper releases on
        // connection loss, so a separate process would find nothing held.
        //
        // `failureModeCode` is a `FailureModeCode` raw value (1 = stop on first error,
        // 2 = log and continue) and defaults to FR-FAIL-4's. It is on the command line so a
        // gate can send a deliberately **invalid** code and see the helper refuse — the
        // refusal is the only part of the mode path a healthy drive can demonstrate.
        let fields = cycle.dropFirst("cycle:".count).split(separator: ":", omittingEmptySubsequences: false)
        guard fields.count >= 2,
              let startBlock = UInt64(fields[0]),
              let blockCount = UInt64(fields[1]) else {
            FileHandle.standardError.write(Data("""
                bad cycle command '\(cycle)'
                usage: cycle:<startBlock>:<blockCount>[:<ioSizeBytes>[:<failureModeCode>]]

                """.utf8))
            exit(2)
        }
        let ioSize = fields.count >= 3 ? (Int(fields[2]) ?? TesterProtocol.defaultIOSizeBytes)
                                       : TesterProtocol.defaultIOSizeBytes
        let modeCode = fields.count >= 4 ? (Int(fields[3]) ?? FailureModeCode.standard.rawValue)
                                         : FailureModeCode.standard.rawValue

        print("[cycle] START_BLOCK=\(startBlock)")
        print("[cycle] BLOCK_COUNT=\(blockCount)")
        print("[cycle] IO_SIZE=\(ioSize)")
        print("[cycle] FAILURE_MODE_REQUESTED=\(modeCode)")

        call("cycle", timeout: 300) { tester, done in
            tester.runRetentionCycle(startBlock: startBlock,
                                     blockCount: blockCount,
                                     ioSizeBytes: ioSize,
                                     failureModeCode: modeCode) {
                completed, chunks, failedRangeCount, failureSummary, cacheBypass,
                fastestBytesPerSecond, bufferBytesHeld, hostOverheadFraction,
                helperCoreFraction, failureModeUsed, failedRangesEncoded, failedBlockCount,
                readBytesPerSecond, writeBytesPerSecond, latencySamples,
                latencyMinimum, latencyMaximum, latencyP99Upper, message in

                print("[cycle] COMPLETED=\(completed ? 1 : 0)")
                print("[cycle] CHUNKS=\(chunks)")
                print("[cycle] FAILED_RANGES=\(failedRangeCount)")
                print("[cycle] FAILURE_SUMMARY=\(failureSummary)")
                print("[cycle] CACHE_BYPASS=\(cacheBypass)")
                print("[cycle] FASTEST_BYTES_PER_SECOND=\(Int(fastestBytesPerSecond.rounded()))")
                print("[cycle] BUFFER_BYTES=\(bufferBytesHeld)")
                // NFR-PERF-3 (Step 9, protocol v8). Emitted as fractions, `-1` when the helper
                // could not establish them — never 0, which means something quite different.
                print("[cycle] HOST_OVERHEAD_FRACTION=\(hostOverheadFraction)")
                print("[cycle] HELPER_CORE_FRACTION=\(helperCoreFraction)")

                // Step 10, protocol v9. `FAILURE_MODE_USED` is what the run actually ran in —
                // the only evidence available on a healthy drive that the mode reached the run
                // path at all, since there is no failure for it to act on. A gate compares it
                // against `FAILURE_MODE_REQUESTED`.
                print("[cycle] FAILURE_MODE_USED=\(failureModeUsed)")
                print("[cycle] FAILED_RANGES_ENCODED=\(failedRangesEncoded)")
                print("[cycle] FAILED_BLOCKS=\(failedBlockCount)")
                // FR-RPT-2/3. `-1` is "not measured"; a sample count of 0 makes the three
                // latency figures meaningless, because 0 ns is a legitimate reading.
                print("[cycle] READ_BYTES_PER_SECOND=\(Int(readBytesPerSecond.rounded()))")
                print("[cycle] WRITE_BYTES_PER_SECOND=\(Int(writeBytesPerSecond.rounded()))")
                print("[cycle] LATENCY_SAMPLES=\(latencySamples)")
                print("[cycle] LATENCY_MIN_NS=\(latencyMinimum)")
                print("[cycle] LATENCY_MAX_NS=\(latencyMaximum)")
                print("[cycle] LATENCY_P99_UPPER_NS=\(latencyP99Upper)")
                print("[cycle] MESSAGE=\(message)")
                done()
            }
        }

    case let held where held.hasPrefix("hold:"):
        let seconds = Double(held.dropFirst("hold:".count)) ?? 5
        print("[hold] HOLDING_FOR=\(Int(seconds))")
        Thread.sleep(forTimeInterval: seconds)
        print("[hold] DONE=1")

    default:
        FileHandle.standardError.write(Data("unknown command '\(command)'\n".utf8))
        exit(2)
    }
}

// Deliberately NOT invalidated before exit in the plain case: letting the process die
// with the connection still open is what exercises the helper's release-on-connection-loss
// path (NFR-REL-5).
exit(transportFailed ? 1 : 0)
