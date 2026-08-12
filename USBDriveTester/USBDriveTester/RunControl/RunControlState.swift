//
//  RunControlState.swift
//  USBDriveTester (app target — unprivileged)
//
//  Step 11, increment 1. The run-control state machine (FR-CTRL-1/2/3/4/5/6/9), as pure logic with
//  nothing calling it yet.
//
//  ## Why the state lives here and the enforcement does not
//
//  BUILD-PLAN Step 11's trust-boundary line is "state owned **GUI-side**, enforced **helper-side**".
//  Both halves are load-bearing and they are different jobs:
//
//    * **This file owns the state.** Which commands are legal, what each one does, and what the user
//      is told when one is refused. Nothing in it touches XPC, a device, or a view.
//    * **The helper owns the settling.** A pause is only real once the helper has stopped at a chunk
//      boundary with no write in flight (NFR-REL-10), and that is increment 2's work in `Core/`.
//
//  Written the same way as `QuitPolicy` and `MountControlPolicy`, for the reason those exist: a
//  decision that lives inline in a view is one where only the paths somebody happened to click get
//  exercised. FR-CTRL-6 asks for *legal transitions only*, which is a property of the table as a
//  whole — so the table is a value and the whole thing is pinned by a test.
//
//  ## The handshake, made unrepresentable rather than remembered
//
//  BUILD-PLAN's risks note: *"Pause acknowledgment is a two-party handshake across XPC — never show
//  'Paused' before the helper confirms, or you imply a safety guarantee you don't have."*
//
//  So ``RunControlState/paused`` is reachable **only** from ``RunControlEvent/pauseSettled``, and by
//  no command from any state. `RunControlPolicyTests.pausedIsUnreachableByAnyCommand` is what pins
//  it. This is the same move `PreRunPrompt` makes by having no `.none` case and `LoadedChunk` makes
//  by being unrepresentable when invalid: *prevent, don't detect.*
//
//  ``RunControlState/pausing`` exists for the same reason — the interval between the request and the
//  settle is a real, observable state with its own words, and collapsing it into `paused` is exactly
//  the claim the risks note forbids.
//
//  ## A call boundary is NOT a state transition
//
//  A whole-device run is a **sequence** of bounded privileged calls (scoping decision 1). A call
//  returning because it finished its slice is not an event here: the state stays `running` and the
//  sequencer issues the next one. This machine is about the *run*, not the calls — which is why
//  there is no `callCompleted` event, and why adding one would be a mistake.
//
//  ## Three decisions recorded here, because the code differs from BUILD-PLAN's state list
//
//  1. **There is no `Configured` state** (user decision 2026-08-12). BUILD-PLAN lists
//     `Idle → Configured → Running`, with FR-CTRL-7 requiring a failure mode before start — but
//     FR-FAIL-4 makes log-and-continue the *default* and Step 10's picker already ships
//     pre-selected, so a mode is always chosen and `Configured` would never be observably different
//     from `idle`. *Nothing untriggerable ships.*
//  2. **There is one terminal state, not three** (user decision 2026-08-12). BUILD-PLAN lists
//     `Stopped | Completed | Failed`. All three enable exactly the same controls and differ only by
//     an outcome `RunReport` is already authoritative for (FR-RPT-4) — and this step adds a fourth
//     member to that vocabulary ("stopped by user"). Two places holding one fact is the
//     `helperHoldsDevice` defect by another door, so ``RunControlState/finished`` is plain and the
//     outcome stays in the report.
//  3. **Restart is offered from `running` and `paused`, never from `finished`.** FR-CTRL-5 is
//     "restart a test from the beginning", which presupposes a test in progress; from a terminal
//     state "restart" and "start" are the same act, and shipping two controls that do one thing is
//     how a user learns to distrust both. See ``RunCommand/restart`` for the two obligations it
//     carries into increments 5 and 6.
//
//  `nonisolated` throughout: the app target compiles with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor,
//  which would otherwise make even these value types main-actor-isolated and their `Equatable`
//  conformance unusable from the non-isolated test target.
//

import Foundation

// MARK: - Where a run is

/// The run-control state machine's states (FR-CTRL-6).
///
/// Eight states, and each one is observably different from its neighbours — a state nobody can
/// distinguish is a state nobody has checked.
nonisolated enum RunControlState: Equatable, CaseIterable {

    /// No run has been started. The ordinary state at launch.
    case idle

    /// Start was pressed and the drive is being prepared: its volumes unmounted, then exclusive
    /// access taken (FR-SAFE-1/2/3). **Nothing has been written.**
    ///
    /// Its own state rather than a flag on `idle` because it is genuinely multi-second — the mount
    /// table's settle budget alone is twelve looks at 150 ms — and because it is the state in which
    /// an abort has to put the volumes back (BUILD-PLAN Step 11: *"a partial unmount that fails must
    /// not strand the user"*).
    case starting

    /// The run is executing: bounded privileged calls in flight, one after another.
    case running

    /// A pause has been requested and **the helper has not confirmed it yet.**
    ///
    /// The whole reason this state exists. Showing "Paused" here would claim NFR-REL-10's guarantee
    /// — settled at a chunk boundary, no write in flight — before anything had established it.
    case pausing

    /// The helper has settled at a chunk boundary with no write in flight (NFR-REL-10).
    ///
    /// The claim is **still held** through a pause (recorded default, 2026-08-12): releasing it
    /// would let macOS remount the volumes within milliseconds and force a second unmount on
    /// resume.
    case paused

    /// A stop has been requested and the helper has not settled yet (FR-CTRL-4).
    case stopping

    /// The run is over, however it ended, and the drive is being released (NFR-REL-5). macOS
    /// remounts the volumes by itself afterwards.
    case finishing

    /// Terminal. The report is on screen; the outcome lives in it (FR-RPT-4), not here — see this
    /// file's decision 2.
    case finished

    /// Whether anything is happening that must freeze the device list (FR-DEV-7), block an uninstall
    /// (NFR-INST-3) and make a quit ask first.
    ///
    /// **`paused` counts.** The claim is held, the drive's volumes are unmounted, and an interrupted
    /// run cannot be resumed (FR-FAIL-7) — so a list that rebuilt underneath it, or a ⌘Q that took
    /// it without asking, would each cost the whole run.
    ///
    /// This is what replaces `AppModel.runIsActive`'s union of the Step 4/5 stand-in toggle and
    /// `cycleIsRunning` — the single authoritative source those two were standing in for. The
    /// collapse itself is increment 5's; this is the answer it will use.
    var isRunActive: Bool {
        switch self {
        case .idle, .finished:
            return false
        case .starting, .running, .pausing, .paused, .stopping, .finishing:
            return true
        }
    }

    /// What the user is told the run is doing.
    ///
    /// A value rather than a `switch` in a view, so the words are reachable by a test — and so the
    /// two transient states say *why* they are transient. "Pausing…" on its own reads as a stall; a
    /// user who is told the drive is finishing a chunk knows both that it is working and that
    /// nothing is being left half-written.
    var statusDescription: String {
        switch self {
        case .idle:
            return "Idle"
        case .starting:
            return "Preparing the drive — unmounting its volumes and taking exclusive access. "
                 + "Nothing has been written yet."
        case .running:
            return "Running"
        case .pausing:
            return "Pausing — waiting for the current chunk to finish, so nothing is left "
                 + "half-written."
        case .paused:
            return "Paused. The drive is still held, and its volumes stay unmounted until the run "
                 + "ends."
        case .stopping:
            return "Stopping — waiting for the current chunk to finish, so nothing is left "
                 + "half-written."
        case .finishing:
            return "Finishing — releasing the drive. macOS will remount its volumes shortly."
        case .finished:
            return "Finished"
        }
    }
}

// MARK: - What the user can ask for

/// The five run controls (FR-CTRL-1/2/3/4/5).
nonisolated enum RunCommand: Equatable, CaseIterable {

    /// **FR-CTRL-1.** Start a run on the selected device. Owns the whole sequence from increment 5:
    /// unmount → acquire → run → release.
    case start

    /// **FR-CTRL-2.** Pause a running test.
    case pause

    /// **FR-CTRL-3.** Resume from the point of pause. This in-session resume is allowed; it is not
    /// FR-FAIL-7's prohibited cross-interruption resume.
    case resume

    /// **FR-CTRL-4.** Stop a running or paused test. The report's outcome vocabulary gains "stopped
    /// by user" in increment 7, when this finally gives it a trigger.
    case stop

    /// **FR-CTRL-5.** Discard progress and begin again from block 0, re-using the held claim
    /// (recorded default, 2026-08-12) — so ``RunControlState/starting`` must be idempotent about a
    /// device it already holds.
    ///
    /// - Important: two obligations this command carries out of this file, neither of which the
    ///   state machine can enforce:
    ///     * **It must raise the pre-run gate again.** NFR-USE-4 requires a deliberate act before
    ///       *any* run begins, and a restart begins one. Increment 5.
    ///     * **From `running` it must confirm first.** An interrupted run cannot be resumed
    ///       (FR-FAIL-7), so one click would discard hours of work irrecoverably. Increment 6.
    case restart

    /// The control's title, so the label shown and the command issued are one decision — the same
    /// property FR-SAFE-5 asked of the mount control, arrived at the same way.
    var label: String {
        switch self {
        case .start:   return "Start"
        case .pause:   return "Pause"
        case .resume:  return "Resume"
        case .stop:    return "Stop"
        case .restart: return "Restart"
        }
    }
}

/// What happened in the world, reported back to the machine.
///
/// Deliberately **not** a mirror of ``RunCommand``: a command is a request and an event is a fact,
/// and the gap between them is where NFR-REL-10 lives.
nonisolated enum RunControlEvent: Equatable, CaseIterable {

    /// The volumes are unmounted and exclusive access is held (FR-SAFE-1/2/3). The run may write.
    case claimEstablished

    /// The drive could not be prepared — a volume refused to unmount, or the claim was refused
    /// (FR-SAFE-4). **The abort path has already put the volumes back** by the time this arrives.
    ///
    /// Lands in `idle`, not in a terminal state: a refused call is not a run, so there is no report
    /// (CONSTRAINTS, "Metrics and reporting"). The cause is presented for the user to clear.
    case startAborted

    /// **The helper has settled at a chunk boundary with no write in flight** (NFR-REL-10).
    ///
    /// This is the second party of the handshake, and it is the only route to
    /// ``RunControlState/paused``. It arrives as the privileged call's own **reply** carrying a
    /// paused outcome and its resume point — not as the acknowledgement of the pause *request*,
    /// which says only that the helper was told.
    case pauseSettled

    /// The run is over, however it ended: every chunk processed, stopped by the user, stopped on a
    /// failure, or aborted. Which of those it was lives in the report (FR-RPT-4).
    ///
    /// - Important: legal from ``RunControlState/pausing`` and ``RunControlState/stopping`` as well
    ///   as from ``RunControlState/running``. A run can finish in the window between a request and
    ///   its settle — a pause pressed at 99.9% is the ordinary case — and a machine that could only
    ///   leave `pausing` through `pauseSettled` would wait forever for a run that had already ended.
    ///   This is the same hazard `quittingAfterTheRunHasAlreadyFinishedDoesNotWaitForever` pins on
    ///   the quit path.
    case runEnded

    /// The device has been released and its volumes will remount by themselves (NFR-REL-5).
    case deviceReleased
}

// MARK: - What the machine answers

/// The result of offering a ``RunCommand`` to the machine.
nonisolated enum RunCommandOutcome: Equatable {

    /// Legal. Move to this state.
    case to(RunControlState)

    /// Not legal here (FR-CTRL-6). `reason` is shown to the user, names the actual cause and, where
    /// there is one, the corrective step (NFR-USE-5).
    case refused(reason: String)

    /// Whether the command was accepted.
    var isAccepted: Bool { if case .to = self { return true } else { return false } }
}

/// The result of reporting a ``RunControlEvent`` to the machine.
///
/// Separate from ``RunCommandOutcome`` because the two failures mean different things: a refused
/// *command* is a decision to tell the user about, while an ignored *event* is a fact that does not
/// apply here — nothing to show, but something to log, because a fact arriving where the state says
/// it cannot is how a wiring defect announces itself.
nonisolated enum RunEventOutcome: Equatable {

    /// Move to this state.
    case to(RunControlState)

    /// Not meaningful in this state. Logged, never displayed.
    case ignored(reason: String)
}

// MARK: - What the view needs

/// Whether one control is offered, and why not when it is not.
nonisolated struct RunControlAvailability: Equatable {

    let isEnabled: Bool

    /// Why the control is disabled, or `nil` when it is enabled.
    ///
    /// Set whenever `isEnabled` is false, without exception. **Dimming is not a message** — Step 4
    /// had two disabled buttons reported as missing entirely, and a control below the fold in an
    /// unadvertised scroll region has since cost this project three more times.
    let disabledReason: String?

    static let enabled = RunControlAvailability(isEnabled: true, disabledReason: nil)

    static func disabled(_ reason: String) -> RunControlAvailability {
        RunControlAvailability(isEnabled: false, disabledReason: reason)
    }
}

/// The single Pause/Resume control, whose label and command always agree.
///
/// One control rather than two, for the reason `MountControlDirection` is one: a button reading
/// "Pause" that resumes is worse than no button, and the way to guarantee they agree is to derive
/// both from one value rather than to compute each.
nonisolated struct RunPauseControl: Equatable {

    /// The command pressing it issues — ``RunCommand/pause`` or ``RunCommand/resume``.
    let command: RunCommand

    let availability: RunControlAvailability

    var label: String { command.label }
    var isEnabled: Bool { availability.isEnabled }
    var disabledReason: String? { availability.disabledReason }
}

/// Everything a view needs to render the run controls.
nonisolated struct RunControls: Equatable {
    let start: RunControlAvailability
    let pause: RunPauseControl
    let stop: RunControlAvailability
    let restart: RunControlAvailability
}

/// The inputs to the controls that are **not** the run's own state.
///
/// Deliberately two fields and no more. Everything else that decides whether a run may proceed —
/// whether the volumes will unmount, whether the claim can be taken — is the *helper's* answer and
/// is not knowable before the attempt (see `checkDeviceReadiness`'s note: a `ready` of `true` means
/// "nothing here would refuse an acquire", never "an acquire will succeed"). Pre-screening those
/// app-side would put the "can this run start?" decision exactly where it must not live.
nonisolated struct RunPreconditions: Equatable {

    /// A device is selected and has no geometry problem (FR-DEV-3/4, `DiscoveredDevice.isSelectable`).
    let hasUsableSelection: Bool

    /// `AppModel.mayIssueNewWork` — false from the moment a quit is *pending*.
    ///
    /// **A precondition, not a hint.** The quit confirmation is window-modal on the main window, so
    /// other windows stay clickable underneath it. The sequencer must consult this before every call
    /// it issues, not once when the run starts; this field is what stops the *controls* offering a
    /// run in the meantime.
    let mayIssueNewWork: Bool

    /// The ordinary case: a usable drive selected and no quit pending.
    static let ready = RunPreconditions(hasUsableSelection: true, mayIssueNewWork: true)
}

// MARK: - The tables

/// The run-control transitions, as two truth tables and a control-availability function.
nonisolated enum RunControlPolicy {

    // MARK: Commands

    /// What a command does in a given state (FR-CTRL-6).
    ///
    /// Every `switch` is written out in full rather than falling through a `default`, so adding a
    /// state or a command is a compile error at every row that has to decide about it — which is
    /// the only mechanism that reliably survives someone else's edit.
    static func outcome(of command: RunCommand,
                        in state: RunControlState,
                        preconditions: RunPreconditions) -> RunCommandOutcome {
        switch command {
        case .start:   return start(in: state, preconditions: preconditions)
        case .pause:   return pause(in: state)
        case .resume:  return resume(in: state)
        case .stop:    return stop(in: state)
        case .restart: return restart(in: state, preconditions: preconditions)
        }
    }

    /// **FR-CTRL-1**, and **FR-CTRL-9**'s refusal: one device at a time, and the refusal is
    /// explained rather than left to the dimming.
    private static func start(in state: RunControlState,
                              preconditions: RunPreconditions) -> RunCommandOutcome {
        switch state {
        case .idle, .finished:
            return begin(preconditions: preconditions)

        case .starting:
            return .refused(reason: "The drive is already being prepared.")

        case .running, .pausing, .paused, .stopping, .finishing:
            // FR-CTRL-9. Named rather than dimmed: "why can I not start?" has one answer here and
            // the user cannot see it otherwise.
            return .refused(reason: "A run is already in progress, and only one drive is tested at "
                                  + "a time. Stop it before starting another.")
        }
    }

    /// The preconditions Start shares with Restart, checked in one place so the two cannot drift.
    ///
    /// Ordered most-specific-first: with a quit pending, selecting a usable drive would not make
    /// Start pressable, so saying so is the more useful answer.
    private static func begin(preconditions: RunPreconditions) -> RunCommandOutcome {
        guard preconditions.mayIssueNewWork else {
            return .refused(reason: "The app has been asked to quit, so no new work can be "
                                  + "started. Choose “Continue Testing” to carry on.")
        }
        guard preconditions.hasUsableSelection else {
            return .refused(reason: "Select a drive to test. A drive whose geometry this tool "
                                  + "cannot read cannot be tested.")
        }
        return .to(.starting)
    }

    /// **FR-CTRL-2** — pause only while running.
    private static func pause(in state: RunControlState) -> RunCommandOutcome {
        switch state {
        case .running:
            return .to(.pausing)

        case .pausing:
            return .refused(reason: "Already pausing — waiting for the current chunk to finish.")

        case .paused:
            return .refused(reason: "The run is already paused.")

        case .idle, .finished:
            return .refused(reason: "There is no run to pause.")

        case .starting:
            return .refused(reason: "The drive is still being prepared, and nothing has been "
                                  + "written yet. Pause becomes available once the run starts.")

        case .stopping:
            return .refused(reason: "The run is stopping.")

        case .finishing:
            return .refused(reason: "The run has ended and the drive is being released.")
        }
    }

    /// **FR-CTRL-3** — resume only from paused.
    ///
    /// Note what is refused: resuming from ``RunControlState/pausing``. The helper has not settled
    /// yet, so there is nothing to resume *from* — and accepting it would mean the machine had
    /// treated a pause as complete before the confirmation NFR-REL-10 requires.
    private static func resume(in state: RunControlState) -> RunCommandOutcome {
        switch state {
        case .paused:
            return .to(.running)

        case .pausing:
            return .refused(reason: "Still pausing — the drive has not reached a safe point yet. "
                                  + "Resume becomes available once it has.")

        case .running:
            return .refused(reason: "The run is not paused.")

        case .idle, .finished:
            return .refused(reason: "There is no paused run to resume.")

        case .starting:
            return .refused(reason: "The drive is still being prepared.")

        case .stopping:
            return .refused(reason: "The run is stopping and cannot be resumed. A stopped run "
                                  + "cannot be continued — testing this drive would have to start "
                                  + "again from the beginning.")

        case .finishing:
            return .refused(reason: "The run has ended and the drive is being released.")
        }
    }

    /// **FR-CTRL-4** — stop from running or paused.
    private static func stop(in state: RunControlState) -> RunCommandOutcome {
        switch state {
        case .running, .paused:
            return .to(.stopping)

        case .pausing:
            // Stop supersedes a pause that has not settled. The helper is told to stop instead, and
            // returns the run rather than acknowledging the pause — which is why `pauseSettled` is
            // ignored from `stopping` below.
            return .to(.stopping)

        case .stopping:
            return .refused(reason: "Already stopping — waiting for the current chunk to finish.")

        case .idle, .finished:
            return .refused(reason: "There is no run to stop.")

        case .starting:
            return .refused(reason: "The drive is still being prepared, and nothing has been "
                                  + "written yet. Stop becomes available once the run starts.")

        case .finishing:
            return .refused(reason: "The run has already ended and the drive is being released.")
        }
    }

    /// **FR-CTRL-5** — discard progress and begin again from block 0.
    ///
    /// Offered from `running` and `paused` only; see this file's decision 3 for why not from
    /// `finished`, and ``RunCommand/restart`` for the confirmation and pre-run gate it owes.
    private static func restart(in state: RunControlState,
                                preconditions: RunPreconditions) -> RunCommandOutcome {
        switch state {
        case .running, .paused:
            return begin(preconditions: preconditions)

        case .idle, .finished:
            return .refused(reason: "There is no run to restart. Use Start.")

        case .starting:
            return .refused(reason: "The drive is still being prepared.")

        case .pausing:
            return .refused(reason: "Still pausing — the drive has not reached a safe point yet.")

        case .stopping:
            return .refused(reason: "The run is stopping. Start a new run once it has.")

        case .finishing:
            return .refused(reason: "The drive is being released. Start a new run once it has.")
        }
    }

    // MARK: Events

    /// What a reported fact does in a given state.
    static func outcome(of event: RunControlEvent, in state: RunControlState) -> RunEventOutcome {
        switch event {
        case .claimEstablished:
            guard state == .starting else { return notWhileIn(state, event) }
            return .to(.running)

        case .startAborted:
            // Back to `idle`, with no report: a refused call is not a run. The volumes have already
            // been put back by the time this arrives.
            guard state == .starting else { return notWhileIn(state, event) }
            return .to(.idle)

        case .pauseSettled:
            // **The only route to `paused`.** From `stopping` it is ignored on purpose: a stop
            // supersedes an unsettled pause, so a run that stopped must not land in `paused`.
            guard state == .pausing else { return notWhileIn(state, event) }
            return .to(.paused)

        case .runEnded:
            switch state {
            case .running, .pausing, .stopping:
                return .to(.finishing)
            case .idle, .starting, .paused, .finishing, .finished:
                return notWhileIn(state, event)
            }

        case .deviceReleased:
            guard state == .finishing else { return notWhileIn(state, event) }
            return .to(.finished)
        }
    }

    /// The one wording for an event that does not apply, so every ignored row logs the same shape
    /// and a grep finds all of them.
    private static func notWhileIn(_ state: RunControlState,
                                   _ event: RunControlEvent) -> RunEventOutcome {
        .ignored(reason: "\(event) is not meaningful while \(state)")
    }

    // MARK: The controls

    /// What the run controls look like in a given state.
    ///
    /// Derived from ``outcome(of:in:preconditions:)`` rather than deciding again, so a control can
    /// never be offered for a command the table would refuse — and so a refusal's *reason* is the
    /// same words whether the user reads it beside a dimmed button or sees it after pressing one.
    /// Two statements of one rule are two things that drift.
    ///
    /// - Important: **the controls surface only part of the table, and the rest is not dead.** The
    ///   single Pause/Resume control asks for `.resume` while paused, so `pause(in: .paused)`'s
    ///   refusal — and several like it — never reach a button. They are still reachable by any
    ///   caller that issues a command without consulting the control that would have offered it,
    ///   which is what a menu item or a keyboard shortcut does. A mutation blanking one of those
    ///   reasons passed the whole suite on 2026-08-12; `everyRefusalInTheWholeTableIsASentence` now
    ///   walks the table rather than this surface.
    static func controls(in state: RunControlState,
                         preconditions: RunPreconditions) -> RunControls {

        func availability(_ command: RunCommand) -> RunControlAvailability {
            switch outcome(of: command, in: state, preconditions: preconditions) {
            case .to:
                return .enabled
            case .refused(let reason):
                return .disabled(reason)
            }
        }

        // Which of the two the single control offers. `pausing` and `stopping` keep "Pause" rather
        // than flipping to "Resume": the run has not paused yet, and a label that changed on the
        // *request* would say the drive had settled when it had not.
        let pauseCommand: RunCommand = state == .paused ? .resume : .pause

        return RunControls(start: availability(.start),
                           pause: RunPauseControl(command: pauseCommand,
                                                  availability: availability(pauseCommand)),
                           stop: availability(.stop),
                           restart: availability(.restart))
    }
}
