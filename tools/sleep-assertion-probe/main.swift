//
//  main.swift
//  sleep-assertion-probe — what `ProcessInfo.beginActivity` actually publishes, and how
//  `pmset -g assertions` reads while it is held.
//
//  ## Why this exists
//
//  Step 13 holds an idle-system-sleep assertion while a run is executing (NFR-REL-9), and **its
//  entire verification gate is read through `pmset -g assertions`.** Four things that gate depends
//  on are unmeasured, and every one of them can make it report the wrong answer about a working
//  product — or the right answer about nothing at all.
//
//  1. **Which assertion type `beginActivity` publishes.** BUILD-PLAN's gate greps for the string
//     `PreventUserIdleSystemSleep`. `NSProcessInfo`'s activity API is documented in terms of
//     *behaviour* — "the system should not idle sleep" — and nowhere in terms of the assertion it
//     creates. It is not a given that the two names match: a process on this machine publishes
//     `NoIdleSleepAssertion` for the same intent, by the `IOPMAssertionCreateWithName` route that
//     BUILD-PLAN names as the equivalent. If the string differs, the gate fails against a product
//     that is doing exactly what it should.
//
//  2. **Whether the reason string survives to `pmset`.** There are only two axes on which the
//     gate can attribute an assertion to *this app* rather than to the eleven other things holding
//     one: the pid and the name. If `beginActivity`'s `reason:` is not what `named:` shows, the
//     name axis is gone and the gate must read by pid alone.
//
//  3. **That the summary count cannot be the evidence.** Read on this machine with nothing of ours
//     loaded, 2026-09-12:
//
//         Assertion status system-wide:
//            PreventUserIdleSystemSleep     1
//            pid 702(powerd): PreventUserIdleSystemSleep named: "Powerd - Prevent sleep while
//            display is on"
//
//     `powerd` holds one of these the whole time the display is on. So the summary line already
//     reads 1 before the app exists, and if it is a system-wide *flag* rather than a count it reads
//     1 before, during and after — and a gate item read off that line passes without the product
//     being there. This probe settles whether that line moves at all.
//
//  4. **That we do not prevent display sleep.** BUILD-PLAN step 3 is explicit: *idle system* sleep
//     only, never the display, and never a block on deliberate sleep. The check is not "is
//     `PreventUserIdleDisplaySleep` zero" — another app may hold one for its own reasons — but
//     "does **our pid** publish anything besides the one assertion we asked for".
//
//  It also answers a fifth question the gate's third item needs: **what a leak looks like.** Two
//  activities begun by one process either show as two entries or as one, and ending one of two
//  either leaves the other or does not. A person asked to confirm "exactly one assertion is held"
//  has to know which of those `pmset` would show them.
//
//  ## What it does to the machine
//
//  Holds an idle-sleep assertion for a few seconds and lets it go. It opens no device, writes
//  nothing, needs no privileges, and `pmset -g assertions` is readable by any user — so unlike
//  most of this project's probes it needs neither a drive nor `sudo`.
//
//  ## Why it measures rather than asserts
//
//  The polling loops report *how long* the assertion took to become visible and to disappear,
//  rather than sleeping a fixed second and looking once. A fixed sleep that happens to be long
//  enough measures nothing and hides the day it stops being long enough; the release latency in
//  particular is a number Step 13's checklist needs, because a person who presses Pause and reads
//  `pmset` is racing exactly that interval.
//
//  Usage:
//    sleep-assertion-probe [--hold <seconds>]
//
//      --hold  pause in the held-one phase for this long, so a person can read `pmset -g
//              assertions` in another window and see what the gate is asking them to look for.
//              Default 0 — the automated path does not need it.
//

import Foundation

// MARK: - What the app will publish

/// **The same string Step 13's assertion will carry**, so what this measures is what the product
/// will show. BUILD-PLAN's step 1 states it literally, and the gate greps for it.
///
/// It deliberately does not name the drive. The assertion's name is visible system-wide to every
/// account on the machine through `pmset`, and the run's own log already names the drive by serial
/// where that belongs — in the record of the run, not in a system-wide power assertion.
let assertionReason = "USB drive retention test in progress"

let ourPID = ProcessInfo.processInfo.processIdentifier

var holdForTheHuman: TimeInterval = 0
var arguments = Array(CommandLine.arguments.dropFirst())
while let flag = arguments.first {
    arguments.removeFirst()
    switch flag {
    case "--hold":
        guard let value = arguments.first.flatMap(Double.init) else {
            FileHandle.standardError.write(Data("usage: sleep-assertion-probe [--hold <seconds>]\n".utf8))
            exit(2)
        }
        arguments.removeFirst()
        holdForTheHuman = value
    default:
        FileHandle.standardError.write(Data("unknown argument: \(flag)\n".utf8))
        exit(2)
    }
}

// MARK: - Reading pmset

/// One assertion `pmset` attributes to a process.
struct OwnedAssertion {
    let type: String
    let name: String
}

/// One reading of `pmset -g assertions`, reduced to the three things the gate cares about.
struct Snapshot {

    /// The system-wide summary line for `PreventUserIdleSystemSleep`, whatever it says.
    let systemIdleSummary: Int?

    /// The system-wide summary line for `PreventUserIdleDisplaySleep`.
    let displayIdleSummary: Int?

    /// Every assertion listed against **our** pid.
    let ours: [OwnedAssertion]

    /// The raw lines naming our pid, kept for the record: a parse is a claim about a format, and
    /// the format is the thing most likely to move under this.
    let rawOurs: [String]
}

/// Run `pmset -g assertions` and reduce it.
///
/// Absolute path, because a probe that resolves a tool through `PATH` is a probe that can be
/// answered by something else.
func readAssertions() -> Snapshot {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    task.arguments = ["-g", "assertions"]

    let out = Pipe()
    task.standardOutput = out
    task.standardError = Pipe()

    do {
        try task.run()
    } catch {
        FileHandle.standardError.write(Data("cannot run /usr/bin/pmset: \(error)\n".utf8))
        exit(3)
    }

    let data = out.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()

    let text = String(decoding: data, as: UTF8.self)

    var systemIdle: Int?
    var displayIdle: Int?
    var ours: [OwnedAssertion] = []
    var rawOurs: [String] = []

    // The pid appears as `pid 702(powerd):` — matched WITH the opening parenthesis, so 702 does
    // not also match 7020.
    let pidNeedle = "pid \(ourPID)("

    for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
        let fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)

        if fields.count == 2, let value = Int(fields[1]) {
            if fields[0] == "PreventUserIdleSystemSleep" { systemIdle = value }
            if fields[0] == "PreventUserIdleDisplaySleep" { displayIdle = value }
        }

        guard line.contains(pidNeedle) else { continue }
        rawOurs.append(line.trimmingCharacters(in: .whitespaces))

        // `   pid 41234(sleep-assertion-probe): [0x…] 00:00:03 <TYPE> named: "<NAME>"`
        //
        // The type is the last token before `named:`, and the name is what follows in quotes.
        // Written without a regex on purpose: the failure mode of a wrong regex here is a silent
        // empty result, which reads exactly like an assertion that was never published.
        guard let namedAt = line.range(of: " named: \"") else {
            ours.append(OwnedAssertion(type: "?", name: "?"))
            continue
        }
        let head = line[line.startIndex..<namedAt.lowerBound]
        let type = head.split(separator: " ").last.map(String.init) ?? "?"

        let afterQuote = line[namedAt.upperBound...]
        let name = afterQuote.firstIndex(of: "\"").map { String(afterQuote[..<$0]) } ?? "?"

        ours.append(OwnedAssertion(type: type, name: name))
    }

    return Snapshot(systemIdleSummary: systemIdle,
                    displayIdleSummary: displayIdle,
                    ours: ours,
                    rawOurs: rawOurs)
}

/// Poll until `pmset` agrees, and report how long that took.
///
/// - Returns: the first snapshot satisfying `predicate` and the seconds it took, or the last
///   snapshot read and `nil` if it never did.
func waitUntil(_ predicate: (Snapshot) -> Bool,
               timeout: TimeInterval = 5,
               poll: useconds_t = 20_000) -> (Snapshot, TimeInterval?) {
    let started = Date()
    var last = readAssertions()
    if predicate(last) { return (last, -started.timeIntervalSinceNow) }

    while -started.timeIntervalSinceNow < timeout {
        usleep(poll)
        last = readAssertions()
        if predicate(last) { return (last, -started.timeIntervalSinceNow) }
    }
    return (last, nil)
}

// MARK: - Reporting

func line(_ text: String) {
    print(text)
    fflush(stdout)
}

func report(phase: String, _ snapshot: Snapshot, latency: TimeInterval? = nil) {
    let types = snapshot.ours.map(\.type).joined(separator: ",")
    var fields = ["phase=\(phase)",
                  "ours=\(snapshot.ours.count)",
                  "system=\(snapshot.systemIdleSummary.map(String.init) ?? "?")",
                  "display=\(snapshot.displayIdleSummary.map(String.init) ?? "?")"]
    if !types.isEmpty { fields.append("types=\(types)") }
    if let latency { fields.append(String(format: "visibleAfter=%.3fs", latency)) }
    line(fields.joined(separator: " "))
    for raw in snapshot.rawOurs { line("  raw: \(raw)") }
}

line("probe: pid=\(ourPID)")
line("probe: reason=\"\(assertionReason)\"")

// MARK: - Phase 1: before anything is held

// **The instrument's own floor, printed beside the numbers it produces.** Every latency below is
// measured in whole `pmset` invocations, so a reading at or near this value means "already true on
// the first read" and says nothing about how fast the mechanism is — only that it was faster than
// one measurement. Without this line an 88 ms cost reads as an 88 ms latency, which would put a
// number on the mechanism that the mechanism never produced.
let baselineStarted = Date()
let baseline = readAssertions()
let readCost = -baselineStarted.timeIntervalSinceNow
line(String(format: "probe: pmsetReadCost=%.3fs", readCost))

report(phase: "baseline", baseline)

guard baseline.ours.isEmpty else {
    line("finding: INCONCLUSIVE — this pid already owns an assertion before the probe began")
    exit(4)
}

// MARK: - Phase 2: one activity

let first = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled],
                                                 reason: assertionReason)
let (heldOne, appeared) = waitUntil { !$0.ours.isEmpty }
report(phase: "held-one", heldOne, latency: appeared)

guard let publishedType = heldOne.ours.first?.type, appeared != nil else {
    line("finding: beginActivity published NOTHING pmset attributes to this pid within 5s")
    line("finding: the gate cannot be read by pid, and Step 13 needs the IOPMAssertion route")
    exit(5)
}

let publishedName = heldOne.ours.first?.name ?? "?"
line("finding: type=\(publishedType)")
line("finding: name=\"\(publishedName)\"")
line("finding: nameCarriesReason=\(publishedName == assertionReason ? "yes" : "no")")
line("finding: typeMatchesBuildPlan="
     + (publishedType == "PreventUserIdleSystemSleep" ? "yes" : "no"))
line("finding: displaySleepUntouched="
     + (heldOne.ours.contains { $0.type.contains("Display") } ? "no" : "yes"))

// Whether the system-wide summary line moves at all when we take one. If it does not, an item
// read off that line is being answered by `powerd`, not by us.
let summaryMoved = baseline.systemIdleSummary != heldOne.systemIdleSummary
line("finding: summaryCountDiscriminates=\(summaryMoved ? "yes" : "no")"
     + " (baseline=\(baseline.systemIdleSummary.map(String.init) ?? "?")"
     + " held=\(heldOne.systemIdleSummary.map(String.init) ?? "?"))")

if holdForTheHuman > 0 {
    line("holding for \(holdForTheHuman)s — read `/usr/bin/pmset -g assertions` now")
    Thread.sleep(forTimeInterval: holdForTheHuman)
}

// MARK: - Phase 3: a second activity from the same process
//
// What a leaked assertion would look like. If one process's two activities collapse into one
// entry, then "exactly one is held" is NOT readable from `pmset` and the gate's third item has to
// be answered another way — by the log, or by the counting double in the suite.

let second = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled],
                                                  reason: assertionReason + " (second)")
let (heldTwo, secondAppeared) = waitUntil { $0.ours.count >= 2 }
report(phase: "held-two", heldTwo, latency: secondAppeared)
line("finding: perTokenEntries=\(heldTwo.ours.count >= 2 ? "yes" : "no")"
     + " (entries=\(heldTwo.ours.count))")

// MARK: - Phase 4: end the second only

ProcessInfo.processInfo.endActivity(second)
let (afterSecond, droppedOne) = waitUntil { $0.ours.count <= max(1, heldTwo.ours.count - 1) }
report(phase: "ended-second", afterSecond, latency: droppedOne)
line("finding: survivesPartialRelease=\(afterSecond.ours.isEmpty ? "no" : "yes")")

// MARK: - Phase 5: end the first, and time the disappearance
//
// The number Step 13's checklist needs: a person who presses Pause and reads `pmset` is racing
// this interval, and an item that does not say how long to wait is an item whose answer depends
// on typing speed.

ProcessInfo.processInfo.endActivity(first)
let (released, releaseLatency) = waitUntil { $0.ours.isEmpty }
report(phase: "released", released, latency: releaseLatency)

if let releaseLatency {
    line(String(format: "finding: releaseVisibleAfter=%.3fs", releaseLatency))
} else {
    line("finding: releaseVisibleAfter=NEVER — the assertion outlived endActivity by over 5s")
    exit(6)
}

line("probe: done")
