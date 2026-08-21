//
//  RunControlPolicyTests.swift
//  The run-control state machine (Step 11, increment 1). FR-CTRL-1/2/3/4/5/6/9, NFR-REL-10.
//
//  **Both tables are covered in full**, and there is no excuse for sampling: eight states by five
//  commands is forty rows, and eight by five events is forty more. The substance of FR-CTRL-6 is a
//  property of the table *as a whole* — "legal transitions only" is not a claim about the rows
//  somebody happened to click — so a suite that covered the interesting-looking ones would let a
//  later edit invert a corner of it silently. Same reasoning as `QuitPolicyTests` and
//  `MountControlStateTests`.
//
//  Four properties are load-bearing, and each of them looks removable:
//
//    * **`paused` is unreachable by any command.** It is reachable only from
//      `RunControlEvent.pauseSettled` — the helper confirming it settled at a chunk boundary with no
//      write in flight. If a *command* could produce it, the app would display "Paused" on the
//      request rather than on the confirmation, which is precisely the safety guarantee BUILD-PLAN's
//      risks note says must never be implied (NFR-REL-10).
//    * **A run that ends while a pause is in flight goes to `finishing`, not nowhere.** A pause
//      pressed at 99.9% is the ordinary case, and a machine that could only leave `pausing` through
//      `pauseSettled` would wait for a confirmation that is never coming. The quit path has the same
//      hazard pinned by `quittingAfterTheRunHasAlreadyFinishedDoesNotWaitForever`.
//    * **A stop supersedes an unsettled pause**, and `pauseSettled` is therefore ignored from
//      `stopping`. Without the second half, a run the user stopped could land in `paused` — holding
//      the claim, with the drive unmounted, after being told to let go.
//    * **The controls are derived from the table, not decided a second time.** A control offered for
//      a command the table refuses is a button that fails on press, which is the defect
//      `AppModel.helperHoldsDevice` was added for in Step 9 ("prose is not a precondition").
//

import Testing
import Foundation
@testable import USBDriveTester

struct RunControlPolicyTests {

    // MARK: - Helpers

    /// The state a command moves to, or `nil` when it was refused. Lets the forty-row table below
    /// be written as data rather than as forty assertions.
    private func destination(_ outcome: RunCommandOutcome) -> RunControlState? {
        if case .to(let state) = outcome { return state }
        return nil
    }

    private func destination(_ outcome: RunEventOutcome) -> RunControlState? {
        if case .to(let state) = outcome { return state }
        return nil
    }

    private func refusal(_ outcome: RunCommandOutcome) -> String? {
        if case .refused(let reason) = outcome { return reason }
        return nil
    }

    private func command(_ command: RunCommand,
                         in state: RunControlState,
                         _ preconditions: RunPreconditions = .ready) -> RunCommandOutcome {
        RunControlPolicy.outcome(of: command, in: state, preconditions: preconditions)
    }

    // MARK: - The command table, in full

    @Test func theWholeCommandTableIsPinned() {
        // nil means refused. Every one of the forty rows is here.
        let expected: [(RunControlState, RunCommand, RunControlState?)] = [
            (.idle,      .start,   .starting),
            (.idle,      .pause,   nil),
            (.idle,      .resume,  nil),
            (.idle,      .stop,    nil),
            (.idle,      .restart, nil),

            (.starting,  .start,   nil),
            (.starting,  .pause,   nil),
            (.starting,  .resume,  nil),
            (.starting,  .stop,    nil),
            (.starting,  .restart, nil),

            (.running,   .start,   nil),
            (.running,   .pause,   .pausing),
            (.running,   .resume,  nil),
            (.running,   .stop,    .stopping),
            (.running,   .restart, .restarting),

            (.pausing,   .start,   nil),
            (.pausing,   .pause,   nil),
            (.pausing,   .resume,  nil),
            (.pausing,   .stop,    .stopping),
            (.pausing,   .restart, nil),

            (.paused,    .start,   nil),
            (.paused,    .pause,   nil),
            (.paused,    .resume,  .running),
            (.paused,    .stop,    .stopping),
            (.paused,    .restart, .restarting),

            (.stopping,  .start,   nil),
            (.stopping,  .pause,   nil),
            (.stopping,  .resume,  nil),
            (.stopping,  .stop,    nil),
            (.stopping,  .restart, nil),

            // FR-CTRL-5, increment 8. Every command refuses here, Stop included — see
            // `RunControlPolicy.stop`'s note for why that is deliberate rather than an omission.
            (.restarting, .start,   nil),
            (.restarting, .pause,   nil),
            (.restarting, .resume,  nil),
            (.restarting, .stop,    nil),
            (.restarting, .restart, nil),

            (.finishing, .start,   nil),
            (.finishing, .pause,   nil),
            (.finishing, .resume,  nil),
            (.finishing, .stop,    nil),
            (.finishing, .restart, nil),

            (.finished,  .start,   .starting),
            (.finished,  .pause,   nil),
            (.finished,  .resume,  nil),
            (.finished,  .stop,    nil),
            (.finished,  .restart, nil),
        ]

        // The count is asserted so that deleting a row is a failure rather than a smaller pass —
        // "an empty result is not a finding, and neither is a number that does not move".
        #expect(expected.count == RunControlState.allCases.count * RunCommand.allCases.count)

        for (state, verb, want) in expected {
            #expect(destination(command(verb, in: state)) == want,
                    "state=\(state) command=\(verb)")
        }
    }

    /// **Every refusal in the whole table is a sentence** — not only the ones a control surfaces.
    ///
    /// This exists because a mutation found the hole rather than because anyone foresaw it (M9,
    /// 2026-08-12). `everyDisabledControlExplainsItself` below walks the *rendered controls*, and
    /// the rendered Pause control asks for `.resume` while paused — so `pause(in: .paused)`'s
    /// refusal is never surfaced through it. Blanking that one string passed all 827 tests.
    ///
    /// The row is reachable all the same: a command can be issued without consulting the control
    /// that would have offered it, which is what a menu item or a keyboard shortcut does. So the
    /// check walks the table, where every row lives, rather than the surface some of them reach.
    ///
    /// A bare `!isEmpty` would not do it — that passes the string "no". Twenty characters and a
    /// full stop is the cheapest test that a placeholder fails.
    @Test func everyRefusalInTheWholeTableIsASentence() {
        for state in RunControlState.allCases {
            for verb in RunCommand.allCases {
                for preconditions in [RunPreconditions.ready,
                                      RunPreconditions(hasUsableSelection: false,
                                                       mayIssueNewWork: false)] {
                    guard let reason = refusal(command(verb, in: state, preconditions))
                    else { continue }
                    #expect(reason.count >= 20,
                            "state=\(state) command=\(verb) reason=\(reason)")
                    #expect(reason.hasSuffix("."),
                            "state=\(state) command=\(verb) reason=\(reason)")
                }
            }
        }
    }

    // MARK: - FR-CTRL-6's four named prohibitions

    /// *"pause only while running"*.
    @Test func pauseIsAcceptedFromExactlyOneState() {
        let accepting = RunControlState.allCases.filter { command(.pause, in: $0).isAccepted }
        #expect(accepting == [.running])
    }

    /// *"resume only from paused"*. In particular **not** from `pausing`: the helper has not settled,
    /// so there is nothing to resume from, and accepting it would treat a pause as complete before
    /// the confirmation NFR-REL-10 requires.
    @Test func resumeIsAcceptedFromExactlyOneState() {
        let accepting = RunControlState.allCases.filter { command(.resume, in: $0).isAccepted }
        #expect(accepting == [.paused])
        #expect(!command(.resume, in: .pausing).isAccepted)
    }

    /// *"stop from running/paused"* — and from `pausing`, where a stop supersedes a request that has
    /// not settled.
    @Test func stopIsAcceptedOnlyWhileAnIssuedRunExists() {
        let accepting = Set(RunControlState.allCases.filter { command(.stop, in: $0).isAccepted })
        #expect(accepting == Set([.running, .pausing, .paused]))
    }

    /// *"start only from configured/idle"* — which on this machine is `idle` and the terminal state,
    /// there being no `Configured` (user decision 2026-08-12; see the source file's decision 1).
    @Test func startIsAcceptedOnlyWhenNoRunIsActive() {
        for state in RunControlState.allCases {
            #expect(command(.start, in: state).isAccepted == !state.isRunActive,
                    "state=\(state)")
        }
    }

    /// **FR-CTRL-9.** A second run cannot be started while one is in progress, and the refusal says
    /// so rather than leaving the user to infer it from a dimmed button.
    @Test func startDuringARunIsRefusedWithAReasonThatNamesTheRule() {
        for state in RunControlState.allCases where state.isRunActive {
            let reason = refusal(command(.start, in: state))
            #expect(reason != nil, "state=\(state) must refuse")
            guard let reason else { continue }
            #expect(reason.contains("one drive is tested at a time")
                    || reason.contains("already being prepared")
                    // `restarting` gets its own sentence, and that is the point of the state
                    // existing: the general FR-CTRL-9 wording ends "Stop it before starting
                    // another", which here is both wrong and impossible — a new run is already
                    // coming and Stop is refused too.
                    || reason.contains("run is restarting"),
                    "state=\(state) reason=\(reason)")
        }
    }

    // MARK: - The handshake (NFR-REL-10)

    /// **The property this whole design rests on.** No command, in any state, under any
    /// precondition, may produce `paused`. Only the helper's confirmation can.
    @Test func pausedIsUnreachableByAnyCommand() {
        let everyPrecondition = [
            RunPreconditions.ready,
            RunPreconditions(hasUsableSelection: false, mayIssueNewWork: true),
            RunPreconditions(hasUsableSelection: true, mayIssueNewWork: false),
            RunPreconditions(hasUsableSelection: false, mayIssueNewWork: false),
        ]
        for state in RunControlState.allCases {
            for verb in RunCommand.allCases {
                for preconditions in everyPrecondition {
                    #expect(destination(command(verb, in: state, preconditions)) != .paused,
                            "state=\(state) command=\(verb)")
                }
            }
        }
    }

    /// And the other half: exactly one (state, event) pair produces it.
    @Test func pauseSettledIsTheOnlyRouteToPaused() {
        var routes: [(RunControlState, RunControlEvent)] = []
        for state in RunControlState.allCases {
            for event in RunControlEvent.allCases where
                destination(RunControlPolicy.outcome(of: event, in: state)) == .paused {
                routes.append((state, event))
            }
        }
        #expect(routes.count == 1)
        #expect(routes.first?.0 == .pausing)
        #expect(routes.first?.1 == .pauseSettled)
    }

    /// A run can finish in the window between pressing Pause and the helper settling — pausing at
    /// 99.9% is the ordinary case. Without this row the machine waits for a confirmation that is
    /// never coming.
    @Test func aRunThatEndsWhilePausingDoesNotWaitForever() {
        #expect(destination(RunControlPolicy.outcome(of: .runEnded, in: .pausing)) == .finishing)
    }

    /// A stop supersedes an unsettled pause, in both directions: the command is accepted, and the
    /// pause's own confirmation is then ignored. Without the second half a stopped run could land in
    /// `paused` — still holding the claim, with the drive's volumes unmounted, after being told to
    /// let go.
    @Test func aStopSupersedesAnUnsettledPause() {
        #expect(destination(command(.stop, in: .pausing)) == .stopping)
        #expect(destination(RunControlPolicy.outcome(of: .pauseSettled, in: .stopping)) == nil)
        #expect(destination(RunControlPolicy.outcome(of: .runEnded, in: .stopping)) == .finishing)
    }

    // MARK: - The event table, in full

    @Test func theWholeEventTableIsPinned() {
        let expected: [(RunControlState, RunControlEvent, RunControlState?)] = [
            (.idle,      .claimEstablished, nil),
            (.idle,      .startAborted,     nil),
            (.idle,      .pauseSettled,     nil),
            (.idle,      .runEnded,         nil),
            (.idle,      .deviceReleased,   nil),

            (.starting,  .claimEstablished, .running),
            (.starting,  .startAborted,     .idle),
            (.starting,  .pauseSettled,     nil),
            (.starting,  .runEnded,         nil),
            (.starting,  .deviceReleased,   nil),

            (.running,   .claimEstablished, nil),
            (.running,   .startAborted,     nil),
            (.running,   .pauseSettled,     nil),
            (.running,   .runEnded,         .finishing),
            (.running,   .deviceReleased,   nil),

            (.pausing,   .claimEstablished, nil),
            (.pausing,   .startAborted,     nil),
            (.pausing,   .pauseSettled,     .paused),
            (.pausing,   .runEnded,         .finishing),
            (.pausing,   .deviceReleased,   nil),

            (.paused,    .claimEstablished, nil),
            (.paused,    .startAborted,     nil),
            (.paused,    .pauseSettled,     nil),
            (.paused,    .runEnded,         nil),
            (.paused,    .deviceReleased,   nil),

            (.stopping,  .claimEstablished, nil),
            (.stopping,  .startAborted,     nil),
            (.stopping,  .pauseSettled,     nil),
            (.stopping,  .runEnded,         .finishing),
            (.stopping,  .deviceReleased,   nil),

            // **The two rows that carry the whole of Restart.** `runEnded` is a SELF-transition —
            // the old sequence settled and the restart is not over — and `deviceReleased` is what
            // begins the new run's preparation rather than ending anything. Routing either the
            // ordinary way (to `finishing`, to `finished`) would unfreeze the device list and fire
            // a pending quit's wind-down in the middle of a restart.
            (.restarting, .claimEstablished, nil),
            (.restarting, .startAborted,     nil),
            (.restarting, .pauseSettled,     nil),
            (.restarting, .runEnded,         .restarting),
            (.restarting, .deviceReleased,   .starting),

            (.finishing, .claimEstablished, nil),
            (.finishing, .startAborted,     nil),
            (.finishing, .pauseSettled,     nil),
            (.finishing, .runEnded,         nil),
            (.finishing, .deviceReleased,   .finished),

            (.finished,  .claimEstablished, nil),
            (.finished,  .startAborted,     nil),
            (.finished,  .pauseSettled,     nil),
            (.finished,  .runEnded,         nil),
            (.finished,  .deviceReleased,   nil),
        ]

        #expect(expected.count == RunControlState.allCases.count * RunControlEvent.allCases.count)

        for (state, event, want) in expected {
            #expect(destination(RunControlPolicy.outcome(of: event, in: state)) == want,
                    "state=\(state) event=\(event)")
        }
    }

    /// A drive that could not be prepared goes back to `idle`, **not** to a terminal state: a
    /// refused call is not a run, so there is no report to show for it.
    @Test func anAbortedStartReturnsToIdleRatherThanFinishing() {
        #expect(destination(RunControlPolicy.outcome(of: .startAborted, in: .starting)) == .idle)
    }

    /// Every event that is not meaningful carries a reason naming both the event and the state, so
    /// a wiring defect is diagnosable from the log rather than invisible.
    @Test func everyIgnoredEventSaysWhatItWasAndWhereItArrived() {
        for state in RunControlState.allCases {
            for event in RunControlEvent.allCases {
                guard case .ignored(let reason) = RunControlPolicy.outcome(of: event, in: state)
                else { continue }
                #expect(reason.contains("\(event)"), "state=\(state) event=\(event)")
                #expect(reason.contains("\(state)"), "state=\(state) event=\(event)")
            }
        }
    }

    // MARK: - The preconditions

    /// The quit-pending reason wins when both preconditions fail: with a quit pending, selecting a
    /// usable drive would not make Start pressable, so naming the selection would send the user to
    /// fix the wrong thing (NFR-USE-5).
    @Test func aPendingQuitIsTheMoreSpecificRefusal() {
        let neither = RunPreconditions(hasUsableSelection: false, mayIssueNewWork: false)
        let reason = refusal(command(.start, in: .idle, neither))
        #expect(reason?.contains("quit") == true, "got \(reason ?? "nil")")
    }

    @Test func startNeedsAUsableSelection() {
        let noDrive = RunPreconditions(hasUsableSelection: false, mayIssueNewWork: true)
        #expect(!command(.start, in: .idle, noDrive).isAccepted)
        #expect(refusal(command(.start, in: .idle, noDrive))?.contains("Select a drive") == true)
    }

    /// `mayIssueNewWork` is a precondition, not a hint — and it gates **Restart** as well as Start,
    /// which is the row an edit is most likely to miss, since Restart is reached from a state where
    /// a run is already under way.
    @Test func neitherStartNorRestartIssuesWorkWhileAQuitIsPending() {
        let quitting = RunPreconditions(hasUsableSelection: true, mayIssueNewWork: false)
        #expect(!command(.start, in: .idle, quitting).isAccepted)
        #expect(!command(.restart, in: .running, quitting).isAccepted)
        #expect(!command(.restart, in: .paused, quitting).isAccepted)
    }

    /// The preconditions may only ever make the machine do **less**. A state that refuses a command
    /// with everything ready must not accept it with something missing.
    @Test func preconditionsOnlyEverRestrict() {
        for state in RunControlState.allCases {
            for verb in RunCommand.allCases where !command(verb, in: state).isAccepted {
                for preconditions in [RunPreconditions(hasUsableSelection: false,
                                                       mayIssueNewWork: true),
                                      RunPreconditions(hasUsableSelection: true,
                                                       mayIssueNewWork: false)] {
                    #expect(!command(verb, in: state, preconditions).isAccepted,
                            "state=\(state) command=\(verb)")
                }
            }
        }
    }

    // MARK: - Is a run active (FR-DEV-7, NFR-INST-3, and the quit dialog)

    /// **`paused` counts as active.** The claim is held, the volumes are unmounted, and an
    /// interrupted run cannot be resumed (FR-FAIL-7) — so a device list that rebuilt underneath it,
    /// or a ⌘Q that took it without asking, would each cost the whole run.
    @Test func everyStateBetweenStartAndFinishCountsAsActive() {
        let active = Set(RunControlState.allCases.filter(\.isRunActive))
        // `restarting` counts: the claim is held, the volumes are down, and a device list that
        // rebuilt or a ⌘Q that took the app without asking would each cost the run — which is the
        // whole of what this flag is for.
        #expect(active == Set([.starting, .running, .pausing, .paused, .stopping, .restarting,
                               .finishing]))
        #expect(!RunControlState.idle.isRunActive)
        #expect(!RunControlState.finished.isRunActive)
    }

    // MARK: - The controls

    /// **One rule, one wording.** The controls are derived from the command table, so a control can
    /// never be offered for a command the table would refuse, and the reason a user reads beside a
    /// dimmed button is the same text the table gives.
    @Test func theControlsAgreeWithTheTableTheyAreDerivedFrom() {
        for state in RunControlState.allCases {
            for preconditions in [RunPreconditions.ready,
                                  RunPreconditions(hasUsableSelection: false,
                                                   mayIssueNewWork: true),
                                  RunPreconditions(hasUsableSelection: true,
                                                   mayIssueNewWork: false)] {
                let controls = RunControlPolicy.controls(in: state, preconditions: preconditions)

                func check(_ availability: RunControlAvailability, _ verb: RunCommand) {
                    let outcome = command(verb, in: state, preconditions)
                    #expect(availability.isEnabled == outcome.isAccepted,
                            "state=\(state) command=\(verb)")
                    #expect(availability.disabledReason == refusal(outcome),
                            "state=\(state) command=\(verb)")
                }

                check(controls.start, .start)
                check(controls.stop, .stop)
                check(controls.restart, .restart)
                check(controls.pause.availability, controls.pause.command)
            }
        }
    }

    /// The single control's label and the command it issues are one value, so they cannot be shown
    /// out of step — the property FR-SAFE-5 asked of the mount control, for the same reason.
    @Test func thePauseControlOffersResumeOnlyWhilePaused() {
        for state in RunControlState.allCases {
            let control = RunControlPolicy.controls(in: state, preconditions: .ready).pause
            let expected: RunCommand = state == .paused ? .resume : .pause
            #expect(control.command == expected, "state=\(state)")
            #expect(control.label == expected.label, "state=\(state)")
        }
    }

    /// `pausing` keeps the label "Pause". Flipping it on the *request* would tell the user the drive
    /// had settled at a chunk boundary when nothing had established that.
    @Test func theLabelDoesNotFlipUntilTheHelperHasConfirmed() {
        #expect(RunControlPolicy.controls(in: .pausing, preconditions: .ready).pause.label == "Pause")
        #expect(!RunControlPolicy.controls(in: .pausing, preconditions: .ready).pause.isEnabled)
        #expect(RunControlPolicy.controls(in: .paused, preconditions: .ready).pause.label == "Resume")
        #expect(RunControlPolicy.controls(in: .paused, preconditions: .ready).pause.isEnabled)
    }

    /// **Dimming is not a message.** Every disabled control carries a reason, everywhere, and the
    /// reason is a sentence rather than a placeholder — a check that only asserted non-emptiness
    /// would pass the string "no".
    @Test func everyDisabledControlExplainsItself() {
        for state in RunControlState.allCases {
            for preconditions in [RunPreconditions.ready,
                                  RunPreconditions(hasUsableSelection: false,
                                                   mayIssueNewWork: false)] {
                let controls = RunControlPolicy.controls(in: state, preconditions: preconditions)
                for availability in [controls.start, controls.stop,
                                     controls.restart, controls.pause.availability]
                where !availability.isEnabled {
                    let reason = availability.disabledReason ?? ""
                    #expect(reason.count >= 20, "state=\(state) reason=\(reason)")
                    #expect(reason.hasSuffix("."), "state=\(state) reason=\(reason)")
                }
            }
        }
    }

    /// An enabled control never carries a disabled reason — which would render beside a live button
    /// as an explanation of why it cannot be pressed.
    @Test func anEnabledControlCarriesNoReason() {
        for state in RunControlState.allCases {
            let controls = RunControlPolicy.controls(in: state, preconditions: .ready)
            for availability in [controls.start, controls.stop,
                                 controls.restart, controls.pause.availability]
            where availability.isEnabled {
                #expect(availability.disabledReason == nil, "state=\(state)")
            }
        }
    }

    // MARK: - What the user is told

    /// Every state says something, and no two states say the same thing — a status line that could
    /// not tell `pausing` from `paused` would undo the distinction the two states exist to make.
    @Test func everyStateHasItsOwnStatusWording() {
        let descriptions = RunControlState.allCases.map(\.statusDescription)
        #expect(Set(descriptions).count == RunControlState.allCases.count)
        for description in descriptions {
            #expect(!description.isEmpty)
        }
    }

    /// The two transient states say *why* they are transient. "Pausing…" alone reads as a stall; the
    /// reason it is not one is that the drive is finishing a chunk so nothing is left half-written,
    /// which is NFR-REL-10 stated in the words a user can act on.
    @Test func theTransientStatesExplainTheWaitRatherThanJustNamingIt() {
        for state in [RunControlState.pausing, .stopping] {
            #expect(state.statusDescription.contains("chunk"), "state=\(state)")
            #expect(state.statusDescription.contains("half-written"), "state=\(state)")
        }
    }

    /// A paused run still holds the drive (recorded default, 2026-08-12), and the user is told so —
    /// otherwise a pause looks like a moment to unplug, which would lose the run (FR-FAIL-7) and,
    /// until Step 12, be reported as a drive with millions of bad blocks.
    @Test func pausedSaysTheDriveIsStillHeld() {
        #expect(RunControlState.paused.statusDescription.contains("still held"))
        #expect(RunControlState.paused.statusDescription.contains("unmounted"))
    }
}
