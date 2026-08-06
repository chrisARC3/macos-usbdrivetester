//
//  QuitSequenceTests.swift
//  The last few hundred milliseconds of "Cancel and Quit" (user decision 2026-08-05).
//
//  `QuitSequence` has two ways in and one way out — the helper acknowledges the release, or it
//  never does — and the properties worth testing are the ones that only show up when those two
//  race:
//
//    * termination happens **exactly once**, whichever arrives first, and whatever arrives after;
//    * termination **always** happens, including when the helper accepts the message and goes
//      quiet, which is the case no amount of clicking can produce.
//
//  Both of the closures are injected, so none of this needs a daemon, a drive, or a `sleep`.
//  The deadline in particular is driven by hand: a test that waits five seconds for a timeout is
//  a test that is slow now and flaky later.
//

import Testing
import Foundation
@testable import USBDriveTester

@MainActor
struct QuitSequenceTests {

    /// Counts terminations and captures the scheduled deadline so the test can fire it.
    private final class Harness {
        var terminations = 0
        var scheduledSeconds: TimeInterval?
        var fireDeadline: (@MainActor () -> Void)?
        var releaseIssued = 0
        var completeRelease: (() -> Void)?
        /// Whether the deadline had already been armed at the moment the release was issued.
        var deadlineWasArmedBeforeRelease: Bool?
    }

    private func makeSequence(holdsDevice: Bool = true,
                              harness: Harness) -> QuitSequence {
        let release: QuitSequence.Release? = holdsDevice
            ? { done in
                harness.releaseIssued += 1
                harness.deadlineWasArmedBeforeRelease = harness.fireDeadline != nil
                harness.completeRelease = done
              }
            : nil

        return QuitSequence(release: release,
                            deadlineSeconds: 5,
                            schedule: { seconds, work in
                                harness.scheduledSeconds = seconds
                                harness.fireDeadline = work
                            },
                            terminate: { harness.terminations += 1 })
    }

    // MARK: - The ordinary path

    @Test func releasingThenTerminating() {
        let harness = Harness()
        let sequence = makeSequence(harness: harness)

        sequence.begin()
        #expect(harness.releaseIssued == 1)
        #expect(harness.terminations == 0, "the app must not quit before the device is released")

        harness.completeRelease?()
        #expect(harness.terminations == 1)
        #expect(sequence.isFinished)
    }

    /// Nothing held means nothing to release and nothing to wait for.
    @Test func nothingHeldQuitsStraightAway() {
        let harness = Harness()
        let sequence = makeSequence(holdsDevice: false, harness: harness)

        sequence.begin()
        #expect(harness.releaseIssued == 0)
        #expect(harness.terminations == 1)
        #expect(sequence.isFinished)
    }

    // MARK: - The helper that never answers

    /// The case that cannot be produced by clicking: the daemon accepts the release and goes
    /// quiet. Quitting must not be blockable by a wedged privileged process.
    @Test func aSilentHelperStillLetsTheAppQuit() {
        let harness = Harness()
        let sequence = makeSequence(harness: harness)

        sequence.begin()
        #expect(harness.terminations == 0)

        harness.fireDeadline?()
        #expect(harness.terminations == 1)
        #expect(sequence.isFinished)
    }

    @Test func theDeadlineIsTheOneItWasGiven() {
        let harness = Harness()
        makeSequence(harness: harness).begin()
        #expect(harness.scheduledSeconds == 5)
    }

    /// Armed *before* the release goes out. A release that failed synchronously and never called
    /// back would otherwise leave nothing scheduled at all — the hang this deadline exists to
    /// prevent, reintroduced by the order of two lines.
    @Test func theDeadlineIsArmedBeforeTheReleaseIsIssued() {
        let harness = Harness()
        makeSequence(harness: harness).begin()
        #expect(harness.deadlineWasArmedBeforeRelease == true)
    }

    // MARK: - Exactly once

    /// A second `terminate()` arrives during AppKit's own teardown, so "it would just quit twice"
    /// is not a harmless reading.
    @Test func aLateAcknowledgementAfterTheDeadlineDoesNotTerminateAgain() {
        let harness = Harness()
        let sequence = makeSequence(harness: harness)

        sequence.begin()
        harness.fireDeadline?()
        harness.completeRelease?()

        #expect(harness.terminations == 1)
        #expect(sequence.isFinished)
    }

    @Test func aDeadlineAfterTheAcknowledgementDoesNotTerminateAgain() {
        let harness = Harness()
        let sequence = makeSequence(harness: harness)

        sequence.begin()
        harness.completeRelease?()
        harness.fireDeadline?()

        #expect(harness.terminations == 1)
    }

    @Test func beginningTwiceReleasesOnceAndQuitsOnce() {
        let harness = Harness()
        let sequence = makeSequence(harness: harness)

        sequence.begin()
        sequence.begin()
        #expect(harness.releaseIssued == 1)

        harness.completeRelease?()
        harness.completeRelease?()
        #expect(harness.terminations == 1)
    }
}
