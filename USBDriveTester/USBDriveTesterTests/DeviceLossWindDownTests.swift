//
//  DeviceLossWindDownTests.swift
//  Step 12, chunk 4. **Three ways in, one way out** (FR-DEV-8).
//
//  `QuitSequenceTests` covers the two-entrance version of this shape and says why it is a type at
//  all: two entrances racing towards one irreversible act is how double-fires get written. This
//  adds a third entrance and one property that quit path does not have — **the deadline does not
//  fail open.**
//
//  That distinction is the whole reason these are separate types rather than one parameterised one:
//
//    * `QuitSequence`'s deadline terminates the app anyway, and the argument is that process death
//      *is* the fallback release (NFR-REL-5), so failing open asserts nothing untrue.
//    * Nothing of that carries over here. The app stays alive, and treating silence as "never mind"
//      would leave a paused run holding an exclusive claim on a drive DiskArbitration has already
//      said is gone. **Silence is not evidence the drive came back.**
//
//  The deadline is driven by hand, so none of this needs three seconds of real time — and it could
//  not be reached by clicking in any case: it needs a drive pulled at the moment a privileged call
//  wedges.
//

import Testing
import Foundation
@testable import USBDriveTester

@MainActor
struct DeviceLossWindDownTests {

    /// Counts endings and captures the scheduled deadline so the test can fire it.
    private final class Harness {
        var endings: [DeviceLossEnding] = []
        var scheduledSeconds: TimeInterval?
        var fireDeadline: (@MainActor () -> Void)?
    }

    private func makeWindDown(deadlineSeconds: TimeInterval = 3,
                              harness: Harness) -> DeviceLossWindDown {
        DeviceLossWindDown(deadlineSeconds: deadlineSeconds,
                           schedule: { seconds, work in
                               harness.scheduledSeconds = seconds
                               harness.fireDeadline = work
                           },
                           end: { harness.endings.append($0) })
    }

    // MARK: - Way in 1: nothing was in flight

    /// **The case route (b) exists for.** A paused run has returned from its call and issues no
    /// syscalls, so no reply is coming — not "has not come yet" but *cannot come*. Waiting would be
    /// waiting for a message that provably will not arrive, and the three seconds would be three
    /// seconds of a paused run still claiming to hold a drive that is not attached.
    @Test func aPausedRunEndsWithoutWaitingForAnything() {
        let harness = Harness()
        let windDown = makeWindDown(harness: harness)

        windDown.begin(waitingForAReply: false)

        #expect(harness.endings == [.nothingWasInFlight])
        #expect(harness.scheduledSeconds == nil, "nothing should be waited for")
        #expect(windDown.isFinished)
    }

    // MARK: - Way in 2: route (a) got there first

    /// With a call in flight the reply is usually milliseconds behind the removal callback, and it
    /// carries **the block and the phase** — which route (b) has no way to know. Ending the run the
    /// instant DiskArbitration speaks would throw that away on every ordinary unplug.
    @Test func aCallInFlightIsGivenTimeToComeBack() {
        let harness = Harness()
        let windDown = makeWindDown(harness: harness)

        windDown.begin(waitingForAReply: true)

        #expect(harness.endings.isEmpty, "the reply is still owed")
        #expect(harness.scheduledSeconds == 3)
        #expect(!windDown.isFinished)
    }

    /// Route (a) landed: the sequencer ended the run by itself, so this must never end it again.
    @Test func standingDownMeansTheDeadlineDoesNothing() {
        let harness = Harness()
        let windDown = makeWindDown(harness: harness)

        windDown.begin(waitingForAReply: true)
        windDown.standDown()
        #expect(windDown.isFinished)

        harness.fireDeadline?()
        #expect(harness.endings.isEmpty, "the run had already ended; ending it again is the defect")
    }

    /// Standing down before anything began is the ordinary case, not an edge one: **every** run end
    /// calls it, so that the controller has no branch only a pulled drive exercises.
    @Test func standingDownWithNothingBegunIsHarmless() {
        let harness = Harness()
        let windDown = makeWindDown(harness: harness)

        windDown.standDown()
        #expect(harness.endings.isEmpty)
        #expect(windDown.isFinished)
    }

    /// And once it has stood down, a late disappearance cannot restart it. Written for an unplug's
    /// slice callbacks trailing its whole-disk one, which is an *unclaimed* drive's shape (measured
    /// 2026-09-05). Under a run's claim the unplug is the whole disk alone — eight of eight,
    /// 2026-09-09 and 2026-09-11 — so this is the bench's defence now rather than the drive's.
    @Test func aLateDisappearanceCannotRestartAFinishedSequence() {
        let harness = Harness()
        let windDown = makeWindDown(harness: harness)

        windDown.standDown()
        windDown.begin(waitingForAReply: false)

        #expect(harness.endings.isEmpty)
        #expect(harness.scheduledSeconds == nil)
    }

    // MARK: - Way in 3: the deadline, which does not fail open

    /// **The property this type exists for.** The helper accepted the call and went quiet; nothing
    /// else in the app will ever notice, because a paused-or-blocked run produces no further
    /// events. Failing open — shrugging and leaving the run going — would leave the app believing
    /// it still has a drive that is not attached.
    @Test func aSilentHelperStillEndsTheRun() {
        let harness = Harness()
        let windDown = makeWindDown(harness: harness)

        windDown.begin(waitingForAReply: true)
        #expect(harness.endings.isEmpty)

        harness.fireDeadline?()

        #expect(harness.endings == [.theHelperNeverAnswered])
        #expect(windDown.isFinished)
    }

    /// The two endings are **not** interchangeable, and the caller branches on the difference: a
    /// deadline expiring means the owning connection is still blocked by the call that went quiet,
    /// so the release that follows cannot be acknowledged either (measured 2026-08-04). Reporting
    /// the wrong one would make `RunController` wait for a message that cannot arrive.
    @Test func theEndingSaysWhetherTheHelperIsStillBlocked() {
        #expect(DeviceLossEnding.nothingWasInFlight != DeviceLossEnding.theHelperNeverAnswered)

        for ending in [DeviceLossEnding.nothingWasInFlight, .theHelperNeverAnswered] {
            #expect(!ending.description.isEmpty)
        }
        #expect(DeviceLossEnding.nothingWasInFlight.description
                    != DeviceLossEnding.theHelperNeverAnswered.description)
    }

    // MARK: - One way out

    /// **Idempotence — load-bearing when written, belt-and-braces now.** One unplug of an
    /// *unclaimed* drive produces a disappearance for the whole disk *and* one per slice — three
    /// callbacks for a two-partition drive, measured 2026-09-05 — and all three once reached
    /// `begin`. Since chunk 7f the controller passes on whole-disk calls only, and under a run's
    /// claim the unplug is the whole disk alone (eight of eight, 2026-09-09 and 2026-09-11). The
    /// name keeps the old premise; what the test pins — one deadline however many calls — stands.
    @Test func threeCallbacksFromOneUnplugArmOneDeadline() {
        let harness = Harness()
        let windDown = makeWindDown(harness: harness)

        windDown.begin(waitingForAReply: true)
        harness.scheduledSeconds = nil          // so a second arming would be visible
        windDown.begin(waitingForAReply: true)
        windDown.begin(waitingForAReply: true)

        #expect(harness.scheduledSeconds == nil, "the deadline was armed more than once")

        harness.fireDeadline?()
        #expect(harness.endings == [.theHelperNeverAnswered])
    }

    /// The repeats cannot change the *kind* of wait either: whatever calls `begin` again, the first
    /// call decides. *(Until 2026-09-11 this said a whole-disk callback and a slice callback "say
    /// the same thing about one drive". Chunk 7f found the opposite on 2026-09-08 — a slice of the
    /// drive under test goes because the run claimed it — and no slice call reaches `begin` now.)*
    @Test func aRepeatCannotTurnAWaitIntoAnImmediateEnding() {
        let harness = Harness()
        let windDown = makeWindDown(harness: harness)

        windDown.begin(waitingForAReply: true)
        windDown.begin(waitingForAReply: false)

        #expect(harness.endings.isEmpty, "the second callback must not shortcut the first's wait")
        #expect(!windDown.isFinished)
    }

    /// A deadline that fires twice — one scheduled per `begin`, if `begin` were not idempotent —
    /// must still end the run once.
    @Test func theDeadlineFiringTwiceEndsTheRunOnce() {
        let harness = Harness()
        let windDown = makeWindDown(harness: harness)

        windDown.begin(waitingForAReply: true)
        harness.fireDeadline?()
        harness.fireDeadline?()

        #expect(harness.endings == [.theHelperNeverAnswered])
    }

    /// And the reply arriving after the deadline has already ended the run changes nothing. This is
    /// the race the type exists for, run in the order that produces a double-fire.
    @Test func aReplyArrivingAfterTheDeadlineEndsNothingASecondTime() {
        let harness = Harness()
        let windDown = makeWindDown(harness: harness)

        windDown.begin(waitingForAReply: true)
        harness.fireDeadline?()
        windDown.standDown()

        #expect(harness.endings == [.theHelperNeverAnswered])
    }

    /// The deadline is the one the controller was built with, not a constant this type invented —
    /// so a test that drives it by hand is driving the real interval.
    @Test func theDeadlineIsTheOneItWasGiven() {
        let harness = Harness()
        let windDown = makeWindDown(deadlineSeconds: 12, harness: harness)

        windDown.begin(waitingForAReply: true)

        #expect(harness.scheduledSeconds == 12)
    }

    /// The default is stated once and is what the app ships with.
    @Test func theDefaultDeadlineIsThreeSeconds() {
        #expect(DeviceLossWindDown.defaultDeadlineSeconds == 3)
    }
}
