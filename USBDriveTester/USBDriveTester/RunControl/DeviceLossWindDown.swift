//
//  DeviceLossWindDown.swift
//  USBDriveTester (app target — unprivileged)
//
//  Step 12, chunk 4. **The drive went away: end the run, once.**
//
//  ## Two routes find the same fact, and only one of them may end the run
//
//  Device loss is detected twice over, because neither route can see the whole picture:
//
//    * **Route (a)** — the helper's own `pread`/`pwrite` answers `ENXIO`, the engine ends the run
//      where it found out, and the reply comes back as `RunOutcomeCode.deviceLost` carrying **the
//      block and the phase** (protocol v15, chunk 3). Blind while a run is paused: a paused run
//      issues no syscalls, so no `errno` can arrive.
//    * **Route (b)** — DiskArbitration's removal callback names the disk that left, and
//      `DeviceUnderTest.wasLost(whenDiskDisappeared:)` says whether it was ours (chunk 2). Blind to
//      nothing, but it knows only *that* the drive went, never where the run had got to.
//
//  So the two are not a primary and a backup. Route (b) is the only thing that can see a loss
//  during a pause, and route (a) is the only thing that can say anything useful about *when*. This
//  type is what stops them ending one run twice, and what stops route (b) throwing away route (a)'s
//  detail in the overwhelmingly common case where the reply is milliseconds behind the callback.
//
//  ## Three ways in, one way out
//
//  `QuitSequence`'s shape with one more entrance — and it is a type for the same reason that one is:
//  two entrances racing towards one irreversible act is how double-fires are written, and pulling
//  the race out of the controller is what makes it reachable by a test at all.
//
//    1. **Nothing was in flight.** The run is paused, so no reply is coming — not "has not come
//       yet", but *cannot*, because a paused run makes no syscalls. Waiting would be waiting for a
//       message that provably will not arrive, so the run ends at once.
//    2. **The run ended by itself.** Route (a)'s reply landed and the sequencer finished on its
//       own. This sequence stands down permanently and must never end anything.
//    3. **The deadline.** Route (b) fired, a call was in flight, and the reply never came.
//
//  The way out — ``End`` — runs at most once, and never at all after way 2.
//
//  ## The deadline does NOT fail open, and `QuitSequence`'s argument is why
//
//  `QuitSequence`'s deadline terminates the app anyway, on an argument its header states plainly:
//  *the helper releases a claim when the connection that took it goes away (NFR-REL-5), so
//  terminating without an acknowledgement still ends with the device released.* Failing open is
//  safe there because **process death is itself the fallback**.
//
//  Nothing of that carries over. The app is not dying here; it is trying to finish a run and give a
//  drive back while staying alive. Treating silence as "never mind, carry on" would leave a run
//  believing it still has a drive that DiskArbitration has already said is gone — and a paused one
//  would sit there holding an exclusive claim indefinitely, which is the exact failure FR-DEV-8
//  exists to prevent. **Silence is not evidence the drive came back**, so the deadline fails
//  *closed*: it ends the run.
//
//  What it must not then do is claim more than it knows, and that is the caller's half. The
//  deadline expiring means the helper has gone quiet **inside the owning connection's blocking
//  call** — and a second message on a connection with a blocking call in flight is not delivered
//  until that call returns (measured 2026-08-04, `scripts/xpc-concurrency-check.sh`; 24 pings
//  during a 2,827.9 ms call were all answered after it). So the release that follows cannot be
//  acknowledged either, and ``DeviceLossEnding`` is what tells `RunController` to stop waiting for
//  an answer that provably cannot arrive yet, rather than to invent one.
//
//  ## Why the clock is injected
//
//  Same reason `QuitSequence`'s is: a test that sleeps for a deadline is slow now and flaky later.
//  The deadline path here is also unreachable by clicking — it needs a drive pulled at the moment a
//  privileged call wedges — so driving it by hand is the only cover it can have before chunk 7 puts
//  a person and a real drive in front of it.
//

import Foundation
import os

private nonisolated let lossLog = Logger(subsystem: HelperIdentity.loggingSubsystem,
                                         category: "io")

/// Which of the two closing ways in ended the run — and therefore whether the helper is still
/// inside a blocking call.
nonisolated enum DeviceLossEnding: Equatable {

    /// Way 1. Nothing was in flight when the drive left, so the run ended immediately. The owning
    /// connection is free and the release that follows can be waited for normally.
    case nothingWasInFlight

    /// Way 3. A call was in flight and its reply never came. **The owning connection is still
    /// blocked by it**, so the release cannot be delivered — let alone acknowledged — until it
    /// returns. See the file header.
    case theHelperNeverAnswered

    /// What the log says happened, and what chunk 6 has to turn into a sentence.
    var description: String {
        switch self {
        case .nothingWasInFlight:    return "the run was paused, so no reply was coming"
        case .theHelperNeverAnswered: return "the helper never answered the call that was in flight"
        }
    }
}

/// Ends a run whose drive has left the machine — exactly once.
@MainActor
final class DeviceLossWindDown {

    /// End the run. Called at most once, and never after ``standDown()``.
    typealias End = (DeviceLossEnding) -> Void

    /// Runs `work` after `seconds`. Injected so tests need no real time — see the header.
    typealias Schedule = (_ seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) -> Void

    /// How long route (a)'s reply is given to confirm what route (b) already saw.
    ///
    /// Three seconds, and the figure is chosen to be *uncontroversially* generous rather than
    /// tuned: once the engine classifies `ENXIO` it ends the run at that chunk and returns — it
    /// does not finish the slice — so the reply owes only the current chunk's remaining I/O, which
    /// chunk 0 measured at a floor of ~3.5 ms for the settle it is the sibling of. Three orders of
    /// magnitude of headroom is what makes it safe to say that a deadline firing means something
    /// is genuinely wrong rather than merely slow.
    ///
    /// **No real measurement stands behind it yet**, and that is stated rather than implied: only
    /// chunk 7's hardware gate — a person pulling a real drive out of a real port — can say what
    /// the interval between the removal callback and the `ENXIO` reply actually is.
    /// `nonisolated` so it can be read from `init`'s own default argument, which is evaluated
    /// outside the actor — the whole app target is `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
    /// so without this a constant would be main-actor-isolated like everything else.
    nonisolated static let defaultDeadlineSeconds: TimeInterval = 3

    private let end: End
    private let schedule: Schedule
    private let deadlineSeconds: TimeInterval

    private var hasBegun = false
    private var hasFinished = false

    /// - Parameters:
    ///   - deadlineSeconds: how long route (a)'s reply is waited for.
    ///   - schedule: how to run something later. Defaults to the main queue — the main *queue* and
    ///     not a run-loop `Timer`, because a default-mode timer is starved by AppKit's own nested
    ///     run loops (measured 2026-08-05) and this deadline exists precisely for the case where
    ///     something has already gone wrong.
    ///   - end: what ending the run means. Injected so this class never mentions a sequencer.
    init(deadlineSeconds: TimeInterval = DeviceLossWindDown.defaultDeadlineSeconds,
         schedule: @escaping Schedule = { seconds, work in
             DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                 MainActor.assumeIsolated { work() }
             }
         },
         end: @escaping End) {
        self.deadlineSeconds = deadlineSeconds
        self.schedule = schedule
        self.end = end
    }

    /// The drive under test has gone.
    ///
    /// **Idempotent, and that is load-bearing rather than tidy.** One unplug produces a
    /// disappearance for the whole disk *and* one for each of its slices — measured 2026-09-05,
    /// three callbacks for a two-partition drive — so this is called several times for one event.
    /// The second and third do nothing.
    ///
    /// - Parameter waitingForAReply: whether a privileged call is in flight. `false` means the run
    ///   is paused and the run ends here (way 1); `true` arms the deadline and waits for route (a)
    ///   to confirm with the block and the phase this route cannot supply.
    func begin(waitingForAReply: Bool) {
        guard !hasBegun else { return }
        hasBegun = true

        guard waitingForAReply else {
            lossLog.notice("device loss: nothing was in flight, ending the run now")
            finish(.nothingWasInFlight)
            return
        }

        lossLog.notice("""
                       device loss: a call is in flight; waiting up to \
                       \(self.deadlineSeconds, privacy: .public)s for the helper's reply
                       """)
        schedule(deadlineSeconds) { [weak self] in
            self?.deadlineExpired()
        }
    }

    /// **Route (a) got there first**: the run ended by itself, carrying the block and the phase.
    ///
    /// Permanent — a deadline that fires afterwards finds the sequence finished and does nothing.
    ///
    /// **What that is worth is the log, not the correctness**, and the distinction was established
    /// by a mutation that survived: deleting the call breaks no behaviour, because the sequencer's
    /// own `.ended` phase already refuses a second ending and `RunController` drops its references
    /// when the drive goes back. What deleting it *does* produce is an error-level line reading
    /// "no reply after 3s — ending the run on the removal callback alone", written three seconds
    /// after a run that route (a) resolved cleanly. That is false evidence about the helper, on
    /// the one path where a person is already reading the log to find out what happened to their
    /// drive — and this project's rule when an instrument and the product disagree is to assume
    /// the instrument.
    ///
    /// Safe to call when nothing was ever begun, and called that way on every ordinary run end —
    /// which is deliberate: a caller that had to remember whether a wind-down existed would be a
    /// caller with a branch that is only ever exercised by a drive being pulled.
    func standDown() {
        guard !hasFinished else { return }
        hasFinished = true
    }

    /// Whether the sequence is over — by ending the run or by standing down. Exposed for tests.
    var isFinished: Bool { hasFinished }

    private func deadlineExpired() {
        guard !hasFinished else {
            lossLog.notice("device loss: the deadline expired, but the run had already ended")
            return
        }
        lossLog.error("""
                      device loss: no reply after \(self.deadlineSeconds, privacy: .public)s — \
                      ending the run on the removal callback alone
                      """)
        finish(.theHelperNeverAnswered)
    }

    private func finish(_ ending: DeviceLossEnding) {
        guard !hasFinished else { return }
        hasFinished = true
        end(ending)
    }
}
