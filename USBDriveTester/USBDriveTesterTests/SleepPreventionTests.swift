//
//  SleepPreventionTests.swift
//  Step 13. NFR-REL-9 — the idle-system-sleep assertion's rule, and the object that holds it.
//
//  **What this suite can and cannot establish, stated once so nobody later mistakes a green run for
//  a working assertion.** Whether the Mac actually stays awake is a system reading: only
//  `pmset -g assertions` can answer it, and only against a real process. That is Step 13's
//  verification gate. Everything here is about the *decision* — which states hold it, that the
//  decision is stated in exactly one place, and that the object holding the token cannot take two.
//
//  The one thing in this file that touches the real mechanism is
//  ``theRealPreventerTakesOneAssertionHoweverManyTimesItIsAsked``, which does publish and release a
//  genuine power assertion in the test process. That is deliberate and it is cheap: chunk 1
//  measured that a second `beginActivity` produces a second entry in `pmset` that outlives every
//  later release, so the guard against it is worth testing on the real class rather than only on a
//  double.
//

import Testing
import Foundation
@testable import USBDriveTester

// MARK: - The double, shared with the controller's own suite

/// Records what it was asked to do, and **does not re-implement the idempotence**.
///
/// That is the whole point of it. `IdleSleepPreventer` absorbs a second `begin()` on purpose; a
/// double that did the same would absorb a controller calling `begin()` twice, which is exactly the
/// defect the counting is for. So this one counts raw calls and lets the caller's mistakes through
/// where a test can see them.
///
/// Lives here rather than inside a suite because Step 13 chunk 3 injects it into
/// `RunControllerTests`'s bench.
@MainActor
final class CountingIdleSleepPrevention: IdleSleepPreventing {

    private(set) var begins = 0
    private(set) var ends = 0

    /// Whether it believes the assertion is held — mirroring the calls, not the OS.
    private(set) var isHeld = false

    /// Every call in order, so a test can assert on the *sequence* and not merely the totals. A
    /// hold/release/hold and a hold/hold/release have the same two counts.
    private(set) var calls: [String] = []

    func begin() {
        begins += 1
        isHeld = true
        calls.append("begin")
    }

    func end() {
        ends += 1
        isHeld = false
        calls.append("end")
    }
}

// MARK: - The rule

@MainActor
struct SleepPreventionPolicyTests {

    /// **The whole of the rule, in one assertion** (user decision 2026-09-12).
    ///
    /// Written as a set over `allCases` rather than as eight separate expectations, for the reason
    /// `RunControlPolicyTests` walks its tables in full: "held in exactly one state" is a property
    /// of the whole enumeration, and a suite that checked `running` alone would stay green if a
    /// ninth state — or `paused` — quietly started holding it too.
    @Test func theAssertionIsHeldInExactlyOneState() {
        let holding = Set(RunControlState.allCases.filter(RunControlPolicy.preventsIdleSleep))
        #expect(holding == [.running])
    }

    /// **NFR-REL-9's own words, as a property of the tables rather than a list of endings.**
    ///
    /// The requirement says the assertion is released when the run pauses, stops, completes or
    /// fails — and Step 12 added a fifth ending, device loss. Rather than naming those five, this
    /// walks *every* command and *every* event the machine accepts from `running` and requires that
    /// wherever they land, the assertion is not held there. A sixth ending added later is covered on
    /// the day it is added.
    @Test func everyWayOutOfRunningLandsSomewhereThatDoesNotHoldIt() {
        var exits: [RunControlState] = []

        for command in RunCommand.allCases {
            if case .to(let next) = RunControlPolicy.outcome(of: command,
                                                             in: .running,
                                                             preconditions: .ready) {
                exits.append(next)
            }
        }
        for event in RunControlEvent.allCases {
            if case .to(let next) = RunControlPolicy.outcome(of: event, in: .running) {
                exits.append(next)
            }
        }

        // A zero here would make every expectation below vacuous — the same reading a mutation
        // round gives a zero test total.
        #expect(exits.count >= 3, "no way out of running was found; the walk is broken")

        for next in exits {
            #expect(!RunControlPolicy.preventsIdleSleep(in: next),
                    "running → \(next) leaves the assertion held")
        }
    }

    /// **A paused run must not hold it, and this is the row where the obvious shortcut is wrong.**
    ///
    /// `isRunActive` is true in `paused` — the claim is held, the volumes are unmounted, a quit has
    /// to ask first — so anyone reaching for an existing predicate would reach for that one and get
    /// a run that keeps the Mac awake indefinitely while doing nothing. NFR-REL-9 names pause
    /// explicitly as a release point.
    @Test func aPausedRunIsRunActiveAndStillDoesNotHoldIt() {
        #expect(RunControlState.paused.isRunActive)
        #expect(!RunControlPolicy.preventsIdleSleep(in: .paused))
    }

    /// **The leak Step 12 handed forward, closed by where the rule sits rather than by a guard.**
    ///
    /// A run can stop in `finishing` and never reach `finished` — the release was issued and its
    /// completion never came, and `driveIsBack` is only called from inside it. Any rule that
    /// released the assertion on `finished` would hold it for ever on exactly that run, which is
    /// BUILD-PLAN's named risk and is reachable rather than theoretical. Because the rule is "held
    /// only in `running`", both states are already false and the release happened on the way out.
    ///
    /// ⚠️ **This paragraph named the wrong path until 2026-09-12.** It said `releaseCannotBeConfirmed`
    /// was the run that stops short, inherited from Step 12's handoff — and chunk 3 measured that
    /// such a run reaches `finished` synchronously, because `releaseTheDrive` calls `driveIsBack`
    /// itself when it cannot wait. `RunControllerSleepPreventionTests` pins both halves. The risk was
    /// real and its example was not; it had been reasoned from a flag's name rather than read off the
    /// code path.
    ///
    /// **What would invalidate this:** widening `preventsIdleSleep` to any state a run can stop in.
    @Test func aRunThatNeverReachesFinishedHasAlreadyReleasedIt() {
        #expect(!RunControlPolicy.preventsIdleSleep(in: .finishing))
        #expect(!RunControlPolicy.preventsIdleSleep(in: .finished))
    }

    /// The two states the documents disagreed about, pinned so the decision is visible in the suite
    /// and not only in a commit message.
    ///
    /// BUILD-PLAN says `Running`; NFR-REL-9 says "actively executing", and the helper is still
    /// finishing a chunk in both of these. The narrow reading was taken 2026-09-12 — see
    /// `RunControlPolicy.preventsIdleSleep(in:)` for the three reasons.
    @Test func theSettleAfterAPressDoesNotHoldIt() {
        #expect(!RunControlPolicy.preventsIdleSleep(in: .pausing))
        #expect(!RunControlPolicy.preventsIdleSleep(in: .stopping))
    }

    /// Nothing is held before a run and nothing after preparation begins — `starting` has written
    /// nothing, and its abort path is `DevicePreparation`'s.
    @Test func nothingIsHeldBeforeARunIsExecuting() {
        #expect(!RunControlPolicy.preventsIdleSleep(in: .idle))
        #expect(!RunControlPolicy.preventsIdleSleep(in: .starting))
    }
}

// MARK: - The object that holds the token

@MainActor
struct IdleSleepPreventerTests {

    /// **The measured reason this guard exists** (`CONSTRAINTS.md` §1, *Idle-sleep assertions*,
    /// 2026-09-12): two `beginActivity` calls from one process publish **two** assertions with two
    /// ids, and ending one leaves the other held for the life of the process. So a second `begin()`
    /// absorbed here is the difference between one entry in `pmset` and a permanent leak.
    ///
    /// `assertionsTaken` is the only way to see this from a test. From outside, one token and two
    /// tokens are indistinguishable — `isHeld` is true either way and `end()` clears the field
    /// either way — which is precisely why the counter is on the class.
    ///
    /// This test publishes a real power assertion and releases it.
    ///
    /// **What would invalidate this:** a macOS release in which `beginActivity` starts collapsing a
    /// process's activities into one assertion. The guard would then be belt-and-braces rather than
    /// load-bearing, and `scripts/sleep-assertion-check.sh` is what would notice.
    @Test func theRealPreventerTakesOneAssertionHoweverManyTimesItIsAsked() {
        let preventer = IdleSleepPreventer()
        #expect(!preventer.isHeld)
        #expect(preventer.assertionsTaken == 0)

        preventer.begin()
        preventer.begin()
        preventer.begin()

        #expect(preventer.isHeld)
        #expect(preventer.assertionsTaken == 1, "a second activity leaks an entry pmset never drops")

        preventer.end()
        #expect(!preventer.isHeld)
    }

    /// Ending when nothing is held is a no-op, and it is the **ordinary** path: the funnel calls
    /// `end()` on every transition that is not into `running`, starting with `idle → starting` on a
    /// machine that has never run. If this threw, logged, or counted, every run would carry noise
    /// before it began.
    @Test func endingWhenNothingIsHeldDoesNothing() {
        let preventer = IdleSleepPreventer()

        preventer.end()
        preventer.end()

        #expect(!preventer.isHeld)
        #expect(preventer.assertionsTaken == 0)
    }

    /// A second run may hold it again. The guard is against a *double* hold, not against re-use —
    /// a controller that started, stopped and started again would otherwise run the second time
    /// with no assertion at all, and nothing would say so.
    @Test func itCanBeHeldAgainAfterItHasBeenReleased() {
        let preventer = IdleSleepPreventer()

        preventer.begin()
        preventer.end()
        preventer.begin()

        #expect(preventer.isHeld)
        #expect(preventer.assertionsTaken == 2)

        preventer.end()
        #expect(!preventer.isHeld)
    }

    /// The string the gate reads. `pmset` shows `beginActivity`'s `reason:` verbatim as its
    /// `named:` field (measured 2026-09-12), so this literal is evidence rather than decoration —
    /// `progress/step-13-human-checklist.md` tells a person to look for exactly this text beside the
    /// app's pid, and a silent edit here would make that instruction wrong.
    @Test func theAssertionNamesItselfInTheWordsTheGateLooksFor() {
        #expect(IdleSleepPreventer.reason == "USB drive retention test in progress")
    }
}

// MARK: - The double behaves the way the controller's tests will need

@MainActor
struct CountingIdleSleepPreventionTests {

    /// **The double must NOT absorb a double `begin()`.** It exists to catch a caller that holds
    /// twice; one that quietly matched the real class's guard would report the defect as correct
    /// behaviour. Pinned, because "make the double match the real thing" is a plausible-sounding
    /// edit that would silently disarm Step 13 chunk 3's whole suite.
    @Test func theDoubleRecordsEveryCallRatherThanCorrectingTheCaller() {
        let double = CountingIdleSleepPrevention()

        double.begin()
        double.begin()
        double.end()

        #expect(double.begins == 2)
        #expect(double.ends == 1)
        #expect(double.calls == ["begin", "begin", "end"])
        #expect(!double.isHeld)
    }
}
