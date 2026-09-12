//
//  SleepPrevention.swift
//  USBDriveTester (app target — unprivileged)
//
//  Step 13. The idle-system-sleep assertion NFR-REL-9 asks for, as a thing that can be held and let
//  go — and nothing else. **What decides whether it should be held is
//  `RunControlPolicy.preventsIdleSleep(in:)`**, and what calls it is the controller's one state
//  funnel. Three files, one rule each, and none of them repeats another's.
//
//  ## Why a protocol
//
//  Because the fact this produces is a **system reading**, and no unit test can see it. `pmset -g
//  assertions` is the only instrument that can say whether an assertion is really held, and it
//  needs a process, a real `beginActivity`, and a person or a script to read it — which is Step
//  13's verification gate, not its suite.
//
//  So the split is deliberate: the suite covers the **decision** (was it asked for, exactly once,
//  on exactly these transitions) through a counting double, and the hardware gate covers the
//  **effect**. Neither can do the other's job, and a test that tried to would be asserting on
//  `ProcessInfo`.
//
//  ## Why the token lives here and not in the controller
//
//  `beginActivity` hands back an opaque `NSObjectProtocol` with no description of what it is — nothing
//  to log, nothing to compare, nothing a report could carry. A controller holding one would own a
//  value it cannot describe, and **its `nil`-ness would become a second place recording "is the
//  assertion held"** beside the state machine that already decides it. Two places holding one fact
//  is `AppModel.helperHoldsDevice` by another door (`CONSTRAINTS.md` §3).
//
//  Here, the token's lifetime *is* the assertion's, the object is the only thing that knows it, and
//  the controller asks for an outcome rather than managing a handle.
//
//  ## Idempotence is not tidiness here — it is measured
//
//  Chunk 1 measured what a second `beginActivity` does (`CONSTRAINTS.md` §1, *Idle-sleep
//  assertions*, 2026-09-12): **two activities from one process publish two separate assertions with
//  two ids**, and ending one leaves the other held. So a double `begin()` is not absorbed by the
//  OS — it leaks an entry that survives every subsequent release, and `pmset` shows it. The guard
//  in ``IdleSleepPreventer/begin()`` is what makes Step 13's third gate item ("exactly one at a
//  time") a property of this file rather than a hope about call sites.
//
//  It is the same shape as `DeviceLossWindDown.begin`'s `guard !hasBegun`, and for the same reason:
//  the caller is a funnel that runs on *every* transition, so the cheapest place to be safe is at
//  the bottom.
//
//  ## What the log says, and what says why
//
//  These lines carry no state name on purpose — this object does not know about states, and a log
//  line that guessed at one could disagree with the machine. The `run control: A → B` line
//  immediately above it in the log is what says why the assertion moved, which is the pairing Step
//  12 built the command-side logging for.
//

import Foundation
import os

private nonisolated let sleepLog = Logger(subsystem: HelperIdentity.loggingSubsystem,
                                          category: "io")

/// Something that can keep the Mac from idle-sleeping while a run is executing.
///
/// Named for what it does rather than for how it does it, so the one implementation that talks to
/// `ProcessInfo` and the one that counts calls in the suite are interchangeable at the seam —
/// `RunSequencing` / `RunSequencer` is the same pairing.
@MainActor
protocol IdleSleepPreventing: AnyObject {

    /// Hold the assertion. **Calling this while it is already held must not take a second one.**
    func begin()

    /// Let it go. A no-op when nothing is held — the funnel that calls this runs on every
    /// transition, so "not held" is the ordinary case rather than an error.
    func end()
}

/// The real one: an `NSProcessInfo` activity with idle system sleep disabled.
///
/// `ProcessInfo.beginActivity` rather than `IOPMAssertionCreateWithName`, which ADR-001 specifies
/// and BUILD-PLAN repeats. Chunk 1 measured that the two routes reach the same place — this one
/// publishes exactly one `PreventUserIdleSystemSleep`, attributed to the pid, with ``reason`` as
/// its `named:` field, and touches neither display sleep nor deliberate sleep.
@MainActor
final class IdleSleepPreventer: IdleSleepPreventing {

    /// **The string `pmset -g assertions` will show**, and therefore evidence: Step 13's gate reads
    /// the `Listed by owning process:` section and matches on the pid *and* this text.
    ///
    /// It deliberately does not name the drive. A power assertion's name is visible system-wide to
    /// every account on the machine, and the run's log already names the drive by serial where that
    /// belongs — in the record of the run.
    static let reason = "USB drive retention test in progress"

    /// The activity token, whose lifetime is the assertion's. `nil` means nothing is held, and it
    /// is the only place that fact is recorded.
    private var token: (any NSObjectProtocol)?

    /// How many assertions this object has actually taken.
    ///
    /// A **count**, and it is the only way the guard in ``begin()`` can be checked at all: from
    /// outside, one token and two tokens look identical — `isHeld` is true either way and `end()`
    /// clears the field either way. The difference is visible in exactly two places, `pmset` and
    /// this counter, and only one of them is reachable from a test. Same argument as the bench's
    /// `windDowns` count, which exists because a `Bool` is green for one wind-down and green for
    /// three.
    private(set) var assertionsTaken = 0

    /// Whether the assertion is held right now.
    var isHeld: Bool { token != nil }

    init() {}

    func begin() {
        guard token == nil else {
            // **A wiring defect, not a state.** The funnel only reaches here on a transition *into*
            // `running`, and no row of the table moves `running → running`. Logged at error level
            // for the reason `RunEventOutcome.ignored` is: a fact arriving where the code says it
            // cannot is how such a defect announces itself — and this particular one would be
            // otherwise invisible until somebody read `pmset` and found two entries.
            sleepLog.error("""
                           sleep prevention: asked to hold the assertion while one is already \
                           held; ignoring, because a second one would leak
                           """)
            return
        }

        token = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled],
                                                     reason: Self.reason)
        assertionsTaken += 1
        sleepLog.notice("""
                        sleep prevention: holding an idle-system-sleep assertion for the run \
                        (\(Self.reason, privacy: .public))
                        """)
    }

    func end() {
        // Silent when nothing is held, and that is the common path rather than an oversight: the
        // funnel calls this on every transition that is not into `running`, which includes every
        // transition of a machine that has never run. A line here would be noise on `idle →
        // starting` and would bury the one that matters.
        guard let token else { return }

        ProcessInfo.processInfo.endActivity(token)
        self.token = nil
        sleepLog.notice("sleep prevention: released the idle-system-sleep assertion")
    }
}
