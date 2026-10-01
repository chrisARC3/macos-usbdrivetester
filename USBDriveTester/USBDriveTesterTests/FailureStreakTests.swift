//
//  FailureStreakTests.swift
//  USBDriveTesterTests
//
//  The rule `HelperConnection` applies to the progress poll's failures (*Owed* (h), Step 15
//  chunk 3): the first line of each kind in a streak logged, the repeats held back and counted,
//  and one notice when the poll answers again. What these cannot reach is the wiring — that
//  `HelperConnection` feeds the streak from the right handlers — which needs a helper to fail.
//

import Testing
import Foundation
@testable import USBDriveTester

struct FailureStreakTests {

    private enum Kind: Hashable { case invalidated, transport }

    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func theFirstFailureOfAStreakIsLogged() {
        var streak = FailureStreak<Kind>()
        #expect(!streak.isActive)
        let logged = streak.failed(.transport, at: t0)
        #expect(logged)
        #expect(streak.isActive)
    }

    /// One failed poll produces two lines of different kinds, in an order XPC does not promise;
    /// both are logged, as they were before the rule existed.
    @Test func theFirstOfEachKindIsLoggedWhateverTheOrder() {
        var streak = FailureStreak<Kind>()
        let invalidatedFirst = streak.failed(.invalidated, at: t0)
        let transportSecond = streak.failed(.transport, at: t0)
        #expect(invalidatedFirst && transportSecond)

        var reversed = FailureStreak<Kind>()
        let transportFirst = reversed.failed(.transport, at: t0)
        let invalidatedSecond = reversed.failed(.invalidated, at: t0)
        #expect(transportFirst && invalidatedSecond)
    }

    @Test func repeatsAreHeldBackAndCounted() {
        var streak = FailureStreak<Kind>()
        _ = streak.failed(.invalidated, at: t0)
        _ = streak.failed(.transport, at: t0)
        for second in 1...10 {
            let now = t0.addingTimeInterval(TimeInterval(second))
            let invalidated = streak.failed(.invalidated, at: now)
            let transport = streak.failed(.transport, at: now)
            #expect(!invalidated && !transport)
        }
        #expect(streak.heldBack == 20)
    }

    /// The measured case of 2026-09-25: 11 of each in ten seconds becomes two lines and a notice.
    @Test func recoveryIsReportedOnceWithTheCountAndTheDuration() {
        var streak = FailureStreak<Kind>()
        for second in 0...10 {
            let now = t0.addingTimeInterval(TimeInterval(second))
            _ = streak.failed(.invalidated, at: now)
            _ = streak.failed(.transport, at: now)
        }

        let recovery = streak.answered(at: t0.addingTimeInterval(11.5))
        #expect(recovery == FailureStreak<Kind>.Recovery(heldBack: 20, seconds: 11.5))
        #expect(!streak.isActive)
        let again = streak.answered(at: t0.addingTimeInterval(12.5))
        #expect(again == nil, "reported once")
    }

    @Test func aSuccessWithNoStreakLogsNothing() {
        var streak = FailureStreak<Kind>()
        let recovery = streak.answered(at: t0)
        #expect(recovery == nil)
        #expect(!streak.isActive)
    }

    /// A single failure then an answer is still a streak that ended: the notice says so, with
    /// nothing held back, so the log shows the poll came back.
    @Test func aStreakOfOneStillReportsItsRecovery() {
        var streak = FailureStreak<Kind>()
        _ = streak.failed(.transport, at: t0)
        let recovery = streak.answered(at: t0.addingTimeInterval(1))
        #expect(recovery == FailureStreak<Kind>.Recovery(heldBack: 0, seconds: 1))
    }

    @Test func aSecondStreakLogsItsOwnFirstFailures() {
        var streak = FailureStreak<Kind>()
        _ = streak.failed(.invalidated, at: t0)
        _ = streak.failed(.transport, at: t0)
        _ = streak.failed(.transport, at: t0.addingTimeInterval(1))
        _ = streak.answered(at: t0.addingTimeInterval(2))

        let later = t0.addingTimeInterval(60)
        let invalidated = streak.failed(.invalidated, at: later)
        let transport = streak.failed(.transport, at: later)
        #expect(invalidated && transport)
        #expect(streak.heldBack == 0, "the first streak's count does not carry over")
        let recovery = streak.answered(at: later.addingTimeInterval(3))
        #expect(recovery == FailureStreak<Kind>.Recovery(heldBack: 0, seconds: 3),
                "timed from the second streak's first failure")
    }
}
