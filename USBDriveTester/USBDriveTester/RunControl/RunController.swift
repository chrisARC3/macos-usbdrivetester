//
//  RunController.swift
//  USBDriveTester (app target — unprivileged)
//
//  Step 11, increment 5. **The only run state in the app**, and the thing that owns
//  unmount → acquire → run → release (CONSTRAINTS section 2, settled 2026-08-12).
//
//  ## What it collapses
//
//  Three sources of "is a run happening" existed before this, and the increment that deletes the
//  `Unmount All` / `Acquire` / `Release` controls is the one that collapses them:
//
//    * `AppModel.simulatedRunActive` — Step 4/5's stand-in, which blocked uninstall and froze the
//      device list;
//    * `AppModel.cycleIsRunning` — Step 9's real bounded cycle;
//    * `AppModel.helperHoldsDevice` — **deleted rather than fixed**, because it is written from
//      `checkDeviceReadiness`'s `helperHoldsThisDevice`, a *per-device* answer, and read at every
//      use site as "the helper holds *some* device". Do not reintroduce a selection-scoped flag.
//
//  One consequence is worth stating because it simplifies everything downstream: **after this
//  increment the app never holds a claim outside a run.** The claim's lifetime is exactly the run's,
//  by construction rather than by bookkeeping — which is the property `helperHoldsDevice` was
//  failing to state.
//
//  ## Where the state moves, and the two places it deliberately does not
//
//  `RunControlPolicy` owns every transition; nothing here decides one. Two orderings in this file
//  are load-bearing and neither is visible from the table:
//
//  **1. Start does not enter `starting` when the button is pressed.** It enters it when the pre-run
//  dialog is *answered*. `starting` means the drive is being prepared — its volumes coming down,
//  a claim being taken — and it reports `isRunActive`, which freezes the device list, blocks an
//  uninstall and makes ⌘Q ask first. None of that should happen because a dialog is open.
//
//  **2. Stop moves the state BEFORE it tells the sequencer.** `RunSequencer.stop()` from a paused
//  run finishes synchronously and emits `runEnded` in the same turn — and `runEnded` is *ignored*
//  from `paused` (it is legal only from `running`, `pausing` and `stopping`). Told in the other
//  order, a stop from a pause would be silently dropped and the run would never end.
//
//  ## Pause needs the daemon; stop does not. The asymmetry is deliberate
//
//  A pause can only be *settled* by the helper — it is inside a blocking privileged call and the
//  engine reads the level at its next chunk boundary. So `pausing` is entered only once the daemon
//  has acknowledged **recording** the request, and if that message never lands, no pause has been
//  requested and the state must not claim one. (That acknowledgement is emphatically *not* the
//  settle: `paused` is reachable only through `pauseSettled`, which arrives as the cycle's own reply.
//  Nothing here may show "Paused" on the strength of a `setRunControl` reply — BUILD-PLAN's risks
//  note forbids exactly that.)
//
//  A stop does not need the daemon in the same way, because half of stopping is the app's own: it
//  declines to issue the next bounded call. So a stop is applied immediately and the request goes
//  out beside it. If the request is lost, the current call still finishes and the run still ends.
//
//  ## Resume must clear the run-control level FIRST, and wait for it
//
//  `RunControlChannel` is a **process-wide slot that never clears itself**, by design — its own
//  header states the obligation: *"The app owns the state and sets `proceed` before every run and
//  on every resume."* A resume that issues the next call without doing so hands the helper a run
//  whose level still says `pause`, and it settles at its first chunk boundary — into `pauseSettled`,
//  which is ignored from `running`. Sequencer paused, machine running, nothing in flight and nothing
//  coming: a hang, not a wrong message.
//
//  It is **awaited** rather than fired and forgotten because the two messages travel on different
//  connections — `setRunControl` on the second, non-owning one and the cycle on the owning one — so
//  nothing orders them. The wait costs 0.46–0.62 ms, measured in increment 2's pre-flight. Start's
//  own clearing is a step of `DevicePreparation`, for the same reason and with the same standing as
//  the acquire.
//
//  ## The pre-run gate is RELOCATED, not re-implemented
//
//  ``startAuthorised(by:)`` keeps `runBoundedCycle(authorisedBy:)`'s shape and its `guard`, and it
//  is the reason both survive: `PreRunPrompt` has no "no dialog" case, so *the decision* cannot
//  express skipping the warnings — but a call site can always just not ask. Taking a `PreRunOutcome`
//  makes wiring Start straight to a run mean **fabricating** proof of an acknowledgement that never
//  happened, which is a deliberate act visible in a diff rather than a one-word edit. The mutation
//  is not catchable by the suite, so prevention is the only cover it has.
//
//  What changed with the relocation is *which drive the dialog names*. Until now it named
//  `AppModel.heldDevice`, set by an `Acquire` press that happened before the button was even
//  enabled. Start is now what acquires, so **nothing is held when it is pressed** and the dialog
//  names the *selected* drive — captured once, at the press, and carried through the prompt, the
//  claim, the run and the report. One source, captured once, at the point of decision: the exact
//  shape of the defect that headed every first-run report "Unidentified drive" (Step 14).
//

import Foundation
import os

private let log = Logger(subsystem: HelperIdentity.loggingSubsystem, category: "io")

/// The same subsystem, reachable from `nonisolated` code.
///
/// `HelperIdentity.loggingSubsystem` is main-actor-isolated like everything else in the app target
/// (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`), so a `static let` inside a `nonisolated` type
/// cannot reference it. A file-scope `nonisolated` binding can, which is how `PreRunWarningLog` and
/// `VolumeMounter` already do it.
private nonisolated let runLog = Logger(subsystem: HelperIdentity.loggingSubsystem, category: "io")

// MARK: - The injected sequencer

/// Whatever can issue a whole-device run.
///
/// The signature is `RunSequencer`'s exactly, so the real one conforms with an empty extension and
/// **the compiler, not a later increment, checks that the abstraction fits the thing it abstracts.**
/// Same arrangement as `RunCycleIssuing`, for the same reason.
@MainActor
protocol RunSequencing {
    @discardableResult
    func start(logicalBlockSize: UInt32,
               deviceBlockCount: UInt64,
               ioSizeBytes: Int,
               failureMode: FailureModeCode) -> Bool

    @discardableResult
    func resume() -> Bool

    @discardableResult
    func stop() -> Bool

    /// **Step 12, FR-DEV-8.** End the run because the drive has left the machine.
    @discardableResult
    func deviceLost() -> Bool
}

extension RunSequencer: RunSequencing {}

// MARK: - What a Start press produced

/// The answer to pressing Start.
///
/// Two cases and no third: a press either raises a dialog or is refused with a reason. **There is
/// deliberately no "run started" case** — a run cannot begin from a press, only from an
/// acknowledgement, and a case saying otherwise is a state this type would let a caller reach.
nonisolated enum RunStartRequest: Equatable {

    /// Put this in front of the user. Nothing has been unmounted and nothing claimed.
    case prompt(PreRunPrompt)

    /// The machine refused it (FR-CTRL-6/9), in the words the user reads. Reached only by a caller
    /// that issued the command without consulting the control that would have offered it — a menu
    /// item or a keyboard shortcut.
    case refused(reason: String)
}

/// Something the user has to be told about, headed with **what did not happen**.
///
/// An alert's title is the one line a user reliably reads. For a Start that aborted the title comes
/// from `OutcomePresentation`, which is where the app decides what a failed unmount or a refused
/// claim is called — so there is one statement of that wording rather than one per call site.
nonisolated struct RunFailureMessage: Equatable {
    let title: String
    let text: String

    /// The one-click fix offered beside Cancel, or `nil` for the ordinary single-button dialog.
    ///
    /// **Defaulted**, so the failure sites that have no remedy to offer — a pause or a resume the
    /// helper did not confirm — say nothing about one rather than each passing `nil`. Where a
    /// remedy exists it comes from ``OutcomeOperation/remedy``, which is where "which failures have
    /// a fix" is decided for the whole app.
    var remedy: RunFailureRemedy? = nil
}

// MARK: - The controller

/// Owns ``RunControlState`` and performs what each transition means.
@MainActor
@Observable
final class RunController {

    // MARK: The state

    /// Where the run is. **The** answer, for every consumer that used to have its own.
    private(set) var state: RunControlState = .idle

    /// Whether anything is happening that must freeze the device list (FR-DEV-7), block an
    /// uninstall (NFR-INST-3) and make a quit ask first.
    var isRunActive: Bool { state.isRunActive }

    /// Whether a claim is held **and the session has issued at least one call**, so the figures
    /// `runProgress` returns belong to this run rather than to the last one.
    ///
    /// Narrower than ``isRunActive`` at the front: during `starting` a drive is being unmounted
    /// and claimed and **nothing has been written**, so a panel calling itself live would be
    /// labelling an empty session. Narrower at the back too: from `finishing` the run is over and
    /// its figures belong in the report, not on a panel that would otherwise show them for ever.
    ///
    /// **`paused` is included, and was not until 2026-08-18.** It was grouped with the states
    /// that show nothing, which hid the entire measurements block the moment the user pressed
    /// Pause — reported by the human checklist as *"pause clears all test progress information
    /// from the main window"*. A paused run is not stale: the claim is held, the session is
    /// alive, and the figures are this run's. Pausing to read the numbers is one of the main
    /// reasons to pause, and it was the one moment they vanished.
    ///
    /// **This was called `isMeasuring`**, which is why `paused` looked like it belonged with the
    /// others — a paused run genuinely is not measuring. The name was answering a different
    /// question from the one its only caller asked, and the rename is the fix; including `paused`
    /// under the old name would have made the name a lie instead.
    var hasLiveSession: Bool {
        switch state {
        case .running, .pausing, .paused, .stopping: return true
        case .idle, .starting, .finishing, .finished: return false
        }
    }

    /// What the run controls look like right now.
    var controls: RunControls {
        RunControlPolicy.controls(in: state, preconditions: preconditions())
    }

    // MARK: What the last run was about

    /// The drive the most recent run was performed on, and when it was authorised.
    ///
    /// Promoted from the pending record at ``RunControlEvent/claimEstablished`` rather than at the
    /// press, so a Start that **aborted** never relabels the metrics panel with a run that did not
    /// happen. The previous run's figures are still on screen and they are still that run's.
    private(set) var lastRunDevice: ReportedDevice?
    private(set) var lastRunStartedAt: Date?

    /// The negotiated USB link speed of the drive under test, from the claim's own profile.
    private(set) var linkSpeedCode = -1

    // MARK: Injected

    private let preconditions: () -> RunPreconditions
    private let selectedDevice: () -> DiscoveredDevice?
    private let prepare: (DiscoveredDevice, @escaping (DevicePreparationOutcome) -> Void) -> Void
    private let makeSequencer: (@escaping (RunSequencerEvent) -> Void) -> RunSequencing

    /// Builds the sequence that ends a run whose drive has left (Step 12, chunk 4).
    ///
    /// A factory for the same reason ``makeSequencer`` is one: the thing it builds is created per
    /// loss and has to be reachable by a test, and the deadline inside it is unreachable by
    /// clicking.
    ///
    /// **Optional rather than defaulted to a closure**, because a default argument expression is
    /// evaluated outside the actor and this type is `@MainActor` — so `= { DeviceLossWindDown(...) }`
    /// does not compile. ``newWindDown(_:)`` is where the real one is built instead; the production
    /// caller passes nothing.
    private let makeWindDown: ((@escaping DeviceLossWindDown.End) -> DeviceLossWindDown)?
    private let setRunControl: (RunControlCode, @escaping (Result<Void, Error>) -> Void) -> Void
    private let release: (@escaping () -> Void) -> Void
    private let ioSizeBytes: () -> Int
    private let failureMode: () -> FailureModeCode

    /// The finished run's report, or `nil` for a request that never became a run — **a refused call
    /// is not a run**, and gets no report rather than a file describing a test that never touched
    /// the drive.
    private let onReport: (RunReport?) -> Void

    /// A run has genuinely begun. The previous run's report is not this run's, and leaving it on
    /// screen while a new run is in flight is the stale-pane defect Step 9 was reported for.
    private let onRunBegan: () -> Void

    /// The machine has come to rest with no claim held and nothing in flight. **This is the call
    /// boundary the quit promise is made at**, and it replaces `cycleIsRunning` going false.
    private let onRunSettled: () -> Void

    /// Something the user has to be told about — an abort, or a control request that did not reach
    /// the daemon. **Only failures ever arrive here**, which is `OutcomePresentation`'s rule made
    /// structural: successes have no message to suppress, because the run's standing surfaces (the
    /// status line, the device pane, the report) already say what happened.
    private let onFailure: (RunFailureMessage) -> Void

    /// The drive under test left the machine and the run is over: **re-run discovery** (FR-DEV-8).
    ///
    /// A closure rather than a `DeviceDiscovery` reference, and the layering is the reason.
    /// `scripts/device-probe.sh` compiles `Discovery/*.swift` plus one `Shared` file and nothing
    /// else — a build with a genuine boundary in it, which is the only kind that can fail on a
    /// layering violation. `RunControl` reaching into `Discovery` would compile fine in the app
    /// target and be wrong; what goes in `AppModel` is reachable by a test besides.
    ///
    /// **No default, where its three neighbours have one**, and the asymmetry is deliberate.
    /// `onRunBegan`, `onRunSettled` and `onFailure` default to doing nothing because doing nothing
    /// is a legitimate configuration — a test that does not care about the report is not a broken
    /// test. This is not a configuration: it is FR-DEV-8's third obligation, and a caller that
    /// omitted it would compile, run, terminate the run correctly, show the right message, and
    /// silently leave a departed drive sitting in the device list with nothing anywhere saying so.
    /// The same judgement `RunReport.init`'s `removalCallbackSaid` carries, for the same reason:
    /// the safe-looking value is the trap.
    private let onDeviceLost: () -> Void

    // MARK: Private state

    /// A Start that has been authorised but whose drive is not yet claimed.
    private struct PendingStart {
        let device: DiscoveredDevice
        /// Captured at the **press**, and the single source for the dialog's identification, the
        /// report's, and the metrics panel's.
        let identity: ReportedDevice
        var authorisedAt: Date?

        /// FR-CTRL-8's size for this run, **captured once when the gate was answered** rather than
        /// read from the dropdown each time it is wanted (increment 6).
        ///
        /// The closure used to be called twice — once for the log line at authorisation and once
        /// for `sequencer.start` when the drive came back prepared — with a multi-second unmount
        /// between them. That was harmless only while the size was a constant. With a real control
        /// it is two properties naming one fact at two instants, which is the exact shape of the
        /// defect that headed every first-run report *"Unidentified drive"*: one source, captured
        /// once, at the point of decision.
        ///
        /// `IOSizeSelection` refusing the control during `starting` is the *other* guard on this,
        /// and it is the weaker one — it depends on a table staying right, where this depends on
        /// nothing.
        var ioSizeBytes: Int = TesterProtocol.defaultIOSizeBytes
    }

    private var pending: PendingStart?
    private var sequencer: RunSequencing?

    /// The drive this run is testing, as route (b) needs to ask about it (Step 12, chunk 2).
    ///
    /// Set when the claim is established and cleared when the drive is let go, so its lifetime is
    /// exactly the claim's — which is what makes matching a disappearance on a **BSD name** sound
    /// here and nowhere that outlives the enumeration. `DeviceUnderTest`'s header states that
    /// argument in full; this property is the thing that keeps it true.
    private var deviceUnderTest: DeviceUnderTest?

    /// The sequence ending a run whose drive has gone, or `nil` when no loss is being handled.
    ///
    /// **One per loss, not one per callback.** A single unplug of an *unclaimed* drive delivers a
    /// disappearance for the whole disk and one for each slice (measured 2026-09-05), so this is
    /// what makes the second and third free. A run's drive is claimed, and under the claim the
    /// slices go *at the claim*: its unplug fires the whole disk only — eight of eight on two
    /// drives, 2026-09-09 and 2026-09-11 (`CONSTRAINTS.md` §1, *Under a claim*). So this is the
    /// bench's defence, with no hardware path in this design; it stays because it costs nothing.
    private var windDown: DeviceLossWindDown?

    /// Whether the release about to be issued can be *acknowledged*.
    ///
    /// False only after a device loss that ended on the deadline: the helper is then still inside
    /// the blocking call that went quiet, and a second message on that connection is not delivered
    /// until it returns (measured 2026-08-04). Waiting for that acknowledgement would be waiting
    /// for a message that provably cannot arrive yet — and the app would sit in `finishing` for
    /// ever, with the device list frozen and an uninstall blocked, over a drive that is not even
    /// attached. See ``releaseTheDrive()``.
    private var releaseCannotBeConfirmed = false

    /// How the removal callback's wind-down ended the run, for the **report** — `nil` on every run
    /// route (b) did not end, including a device loss that route (a)'s reply resolved first.
    ///
    /// Separate from ``releaseCannotBeConfirmed``, which answers a different question about the
    /// same event: that one is about the *connection* (can the release be waited for), this one is
    /// about the *drive* (was a chunk part-way written when it left). They happen to agree today —
    /// only `theHelperNeverAnswered` sets both — and collapsing them into one flag would be one
    /// field stating two facts, which is the shape this project has a lesson about.
    private var deviceLossEnding: DeviceLossEnding?

    init(preconditions: @escaping () -> RunPreconditions,
         selectedDevice: @escaping () -> DiscoveredDevice?,
         prepare: @escaping (DiscoveredDevice,
                             @escaping (DevicePreparationOutcome) -> Void) -> Void,
         makeSequencer: @escaping (@escaping (RunSequencerEvent) -> Void) -> RunSequencing,
         makeWindDown: ((@escaping DeviceLossWindDown.End) -> DeviceLossWindDown)? = nil,
         setRunControl: @escaping (RunControlCode,
                                   @escaping (Result<Void, Error>) -> Void) -> Void,
         release: @escaping (@escaping () -> Void) -> Void,
         ioSizeBytes: @escaping () -> Int,
         failureMode: @escaping () -> FailureModeCode,
         onReport: @escaping (RunReport?) -> Void,
         onRunBegan: @escaping () -> Void = {},
         onRunSettled: @escaping () -> Void = {},
         onFailure: @escaping (RunFailureMessage) -> Void = { _ in },
         onDeviceLost: @escaping () -> Void) {
        self.preconditions = preconditions
        self.selectedDevice = selectedDevice
        self.prepare = prepare
        self.makeSequencer = makeSequencer
        self.makeWindDown = makeWindDown
        self.setRunControl = setRunControl
        self.release = release
        self.ioSizeBytes = ioSizeBytes
        self.failureMode = failureMode
        self.onReport = onReport
        self.onRunBegan = onRunBegan
        self.onRunSettled = onRunSettled
        self.onFailure = onFailure
        self.onDeviceLost = onDeviceLost
    }

    // MARK: - Start (FR-CTRL-1)

    /// Start was pressed. **This raises the dialog and does nothing else** — nothing is unmounted,
    /// nothing is claimed, and the machine does not move.
    ///
    /// - Parameter warningsSuppressed: `AppModel.warningsSuppressed`. Suppressing the text never
    ///   suppresses the deliberate act (NFR-USE-4 as qualified 2026-08-09); only the dialog's
    ///   content changes.
    func startRequested(warningsSuppressed: Bool) -> RunStartRequest {
        switch RunControlPolicy.outcome(of: .start, in: state, preconditions: preconditions()) {
        case .refused(let reason):
            log.notice("start refused: \(reason, privacy: .public)")
            return .refused(reason: reason)
        case .to:
            break
        }

        // `hasUsableSelection` is what makes this unreachable, so it is logged rather than absorbed
        // — a precondition disagreeing with the thing it is a precondition for is a wiring defect
        // announcing itself, and this is where it would announce.
        guard let device = selectedDevice() else {
            log.error("start refused: the machine allowed it with no device selected")
            return .refused(reason: "Select a drive to test.")
        }

        let identity = ReportedDevice(device)
        pending = PendingStart(device: device, identity: identity, authorisedAt: nil)

        let prompt = PreRunPrompt.forRun(warningsSuppressed: warningsSuppressed, device: identity)
        PreRunWarningLog.promptRaised(prompt)
        return .prompt(prompt)
    }

    /// The dialog was answered. **The relocated gate** — see this file's header for why it takes an
    /// argument it barely uses, and why that has to stay.
    ///
    /// - Parameter outcome: proof that the pre-run gate ran and the user proceeded.
    func startAuthorised(by outcome: PreRunOutcome) {
        guard outcome.issuesRun else {
            // Cancelled, or a quit went pending while the sheet was up. Nothing was unmounted,
            // because nothing is unmounted until here.
            pending = nil
            return
        }

        guard var pending else {
            log.error("start authorised with no pending request — nothing to run")
            return
        }

        // Re-evaluated rather than trusted from the press. The dialog can sit unanswered for
        // minutes, and `mayIssueNewWork` can go false underneath it: the quit confirmation is
        // window-modal on the main window, so this window stays clickable beneath it.
        guard case .to(let next) = RunControlPolicy.outcome(of: .start,
                                                            in: state,
                                                            preconditions: preconditions()) else {
            self.pending = nil
            return
        }

        // Taken here, before anything is unmounted, so the report's elapsed figure covers the whole
        // operation the user waited through rather than only the privileged calls inside it.
        pending.authorisedAt = Date()
        // **The one read of the dropdown for this whole run** (FR-CTRL-8, increment 6). Everything
        // downstream — the log line below and the sequencer, several seconds of unmounting later —
        // takes it from here. See `PendingStart.ioSizeBytes`.
        pending.ioSizeBytes = ioSizeBytes()
        self.pending = pending
        apply(.start, movingTo: next)

        beginPreparation(pending)
    }

    /// Unmount → acquire → geometry, for a start whose gate has already been answered.
    ///
    /// A separate function because it was shared with Restart until 2026-08-22. It has one caller
    /// again and is kept as one: logging the intent and then preparing is a step worth a name, and
    /// inlining it would put the log line back inside a branch.
    private func beginPreparation(_ pending: PendingStart) {
        RunControlLog.runStarting(device: pending.identity,
                                  ioSizeBytes: pending.ioSizeBytes,
                                  failureMode: failureMode())

        prepare(pending.device) { [weak self] outcome in
            self?.preparationFinished(outcome)
        }
    }

    /// Stop issuing work and ask the helper to settle at its next chunk boundary.
    ///
    /// Factored out when Stop and Restart shared it. Restart is gone (2026-08-22) and this has
    /// one caller, kept because the ordering it documents — the sequencer first, then the control
    /// code — is the part worth having a name for.
    private func windDownTheRun() {
        sequencer?.stop()
        setRunControl(.stop) { result in
            guard case .success = result else {
                // Not surfaced: the run ends regardless, because no further call will be issued.
                // What is lost is only the promptness of the current call ending early.
                let detail = Self.describe(result)
                log.error("""
                          stop request did not reach the helper: \(detail, privacy: .public); the \
                          run ends at the current call's boundary instead of the next chunk's
                          """)
                return
            }
        }
    }

    /// The words the machine would show beside a dimmed control, for a command it has just refused.
    ///
    /// Reached only after `outcome(of:in:)` has already answered `.refused`; the fallback exists so
    /// this cannot trap, and says the one thing that is certainly true if it is ever reached.
    private static func refusalReason(of command: RunCommand,
                                      in state: RunControlState,
                                      preconditions: RunPreconditions) -> String {
        if case .refused(let reason) = RunControlPolicy.outcome(of: command,
                                                                in: state,
                                                                preconditions: preconditions) {
            return reason
        }
        return "The run is no longer in a state that can be stopped."
    }

    private func preparationFinished(_ outcome: DevicePreparationOutcome) {
        switch outcome {
        case .aborted(let failure):
            // The volumes are already back by the time this arrives — that is what
            // `startAborted` promises, and `DevicePreparation` is what keeps it.
            RunControlLog.startAborted(failure.reason)
            report(.startAborted)
            pending = nil
            onFailure(RunFailureMessage(title: failure.alertTitle,
                                        text: failure.message,
                                        remedy: failure.remedy))
            settledIfAtRest()

        case .ready(let geometry):
            guard let pending else {
                log.error("the drive was prepared with no pending request")
                report(.startAborted)
                return
            }

            linkSpeedCode = geometry.usbLinkSpeedCode
            lastRunDevice = pending.identity
            lastRunStartedAt = pending.authorisedAt

            // Route (b)'s subject, taken from the same identity the report and the dialog use, so
            // the three cannot disagree about which drive this run is about. Set **here** and not
            // at the press: before the claim exists there is no run for a disappearance to end,
            // and `RunControlPolicy.deviceLossWouldEndTheRun` says so for `starting` too.
            deviceUnderTest = DeviceUnderTest(pending.identity)
            if deviceUnderTest == nil {
                // Unreachable from a `DiscoveredDevice`, whose BSD name is not optional — logged
                // rather than absorbed because if it ever happens the run is one that cannot
                // recognise its own drive leaving, and the silence would be indistinguishable
                // from a removal callback that never fired.
                RunControlLog.driveCannotBeWatchedForRemoval(pending.identity)
            }

            onRunBegan()

            report(.claimEstablished)

            let sequencer = makeSequencer { [weak self] event in
                self?.sequencerReported(event)
            }
            self.sequencer = sequencer
            sequencer.start(logicalBlockSize: geometry.logicalBlockSize,
                            deviceBlockCount: geometry.deviceBlockCount,
                            // From the pending start, **not** from the dropdown. The unmount and
                            // the claim happened between the two, and the size this run was
                            // authorised at is the one it must use.
                            ioSizeBytes: pending.ioSizeBytes,
                            failureMode: failureMode())
        }
    }

    // MARK: - Pause and resume (FR-CTRL-2/3)

    /// Ask the helper to settle at its next chunk boundary.
    ///
    /// The state moves only once the daemon has acknowledged **recording** the request — see the
    /// header. The acknowledgement is not the settle, and `paused` is not reachable from here.
    func pause() {
        guard case .to = RunControlPolicy.outcome(of: .pause,
                                                  in: state,
                                                  preconditions: preconditions()) else { return }

        setRunControl(.pause) { [weak self] result in
            guard let self else { return }
            guard case .success = result else {
                // No pause has been requested, so the state must not say one has. The run carries
                // on, which is the honest outcome and the recoverable one.
                let detail = Self.describe(result)
                log.error("pause request did not reach the helper: \(detail, privacy: .public)")
                self.onFailure(RunFailureMessage(
                    title: "The run could not be paused",
                    text: "The pause request did not reach the privileged helper, so the run is "
                        + "still going. \(detail) Try again, or use Stop."))
                return
            }
            // Re-evaluated: the run can end in the 0.5 ms this took, and `pause` is refused from
            // `finishing`. Applying the command again is what makes that harmless.
            guard case .to(let next) = RunControlPolicy.outcome(
                of: .pause, in: self.state, preconditions: self.preconditions()) else { return }
            self.apply(.pause, movingTo: next)
        }
    }

    /// Continue a paused run from its resume point (FR-CTRL-3).
    ///
    /// **Clears the run-control level first, and waits for it.** See the header: without this the
    /// resumed call settles at its first chunk boundary into an event the machine ignores.
    func resume() {
        guard case .to = RunControlPolicy.outcome(of: .resume,
                                                  in: state,
                                                  preconditions: preconditions()) else { return }

        setRunControl(.proceed) { [weak self] result in
            guard let self else { return }
            guard case .success = result else {
                // Still paused, and recoverable: Resume can be pressed again, and Stop is offered
                // throughout. Issuing the call anyway is what must not happen.
                let detail = Self.describe(result)
                log.error("resume abandoned, level not cleared: \(detail, privacy: .public)")
                self.onFailure(RunFailureMessage(
                    title: "The run could not be resumed",
                    text: "The helper did not confirm the run-control signal was cleared. "
                        + "\(detail) The run is still paused and the drive is still held."))
                return
            }
            guard case .to(let next) = RunControlPolicy.outcome(
                of: .resume, in: self.state, preconditions: self.preconditions()) else { return }
            self.apply(.resume, movingTo: next)
            self.sequencer?.resume()
        }
    }

    // MARK: - Stop (FR-CTRL-4)

    /// Stop the run (FR-CTRL-4). Applied immediately — half of stopping is the app declining to
    /// issue the next bounded call, which needs no daemon.
    func stop() {
        guard case .to(let next) = RunControlPolicy.outcome(of: .stop,
                                                            in: state,
                                                            preconditions: preconditions())
        else { return }

        // **Before** the sequencer is told. From `paused` it finishes synchronously and emits
        // `runEnded` in this same turn — and `runEnded` is ignored from `paused`. Told in the other
        // order, a stop from a pause is silently dropped and the run never ends.
        apply(.stop, movingTo: next)

        windDownTheRun()
    }

    // MARK: - Device loss, route (b) (Step 12, FR-DEV-8)

    /// **A disk left the machine.** Reported for every disk, whether or not it is ours.
    ///
    /// This is route (b) — DiskArbitration's removal callback, which is the *only* thing that can
    /// see a drive leave while a run is paused, because a paused run issues no syscalls and no
    /// `errno` will ever arrive to tell the helper (chunk 2's header states the argument in full).
    ///
    /// Three guards, in this order, and each one is answering a different question:
    ///
    ///   1. **Is there a run a disappearance would end?** From the table, not decided again here —
    ///      `deviceLossWouldEndTheRun` derives it from the same rows the transition uses.
    ///   2. **Do we know which drive this run is about?** Set at the claim and cleared at the
    ///      release, which is what makes the BSD-name match in (3) sound.
    ///   3. **Was it ours?** `DeviceUnderTest` parses unit numbers rather than comparing prefixes,
    ///      because `disk70` and `disk7s1` both begin with `disk7` and only one of them is this
    ///      drive.
    ///
    /// **Called several times for one unplug of an unclaimed drive** — once for the whole disk and
    /// once per slice (measured 2026-09-05). The drive under test is claimed, and its slices go
    /// *at the claim*, so its unplug calls this once, for the whole disk (eight of eight,
    /// 2026-09-09 and 2026-09-11). Since chunk 7f only a whole-disk call gets past guard (3):
    /// a slice of the drive under test disappears because *this run claimed the drive*, and
    /// accepting one ended a healthy run ten milliseconds in (measured 2026-09-08). Everything
    /// after the guards is still idempotent by construction — the first call builds the wind-down,
    /// the rest find it already begun — and stays that way: a mutation deleting that idempotency
    /// survived the whole suite once, and one accepted event per unplug does not make it safer.
    func deviceDisappeared(_ disk: DisappearedDisk) {
        guard RunControlPolicy.deviceLossWouldEndTheRun(in: state) else { return }
        guard let deviceUnderTest else { return }
        guard deviceUnderTest.wasLost(whenDiskDisappeared: disk) else {
            // **Say so when the refusal is the interesting one.** A slice of the drive under test
            // going is this run's own claim tearing the partition scheme down; anything else is
            // another drive, and logging those would be noise.
            if deviceUnderTest.isASliceOfThisDrive(disk) {
                RunControlLog.sliceOfTheDriveUnderTestIgnored(disk, deviceUnderTest)
            }
            return
        }

        if windDown == nil {
            RunControlLog.deviceLost(deviceUnderTest, whileIn: state)
            windDown = newWindDown { [weak self] ending in
                self?.endTheRunBecauseTheDriveIsGone(ending)
            }
        }

        // **`paused` is exactly the set of states with nothing in flight.** A paused run has
        // returned from its call; `running`, `pausing` and `stopping` all have one outstanding —
        // `pausing` and `stopping` are requests the helper has been *told* about, not calls that
        // have come back. So this is a reading of the machine, not a guess about it.
        windDown?.begin(waitingForAReply: state != .paused)
    }

    /// The real wind-down, or whatever a test injected in its place.
    private func newWindDown(_ end: @escaping DeviceLossWindDown.End) -> DeviceLossWindDown {
        makeWindDown?(end) ?? DeviceLossWindDown(end: end)
    }

    /// The wind-down decided the run is over. **The only caller of the sequencer's `deviceLost`.**
    private func endTheRunBecauseTheDriveIsGone(_ ending: DeviceLossEnding) {
        // Both set before the sequencer is told, because `deviceLost()` finishes synchronously:
        // the release goes out inside that same call — the same ordering trap `stop()` documents —
        // and so does `makeReport`. A line after the call would record the ending for a report that
        // had already been built without it, which would still export and still be plausible, and
        // would simply decline to say whether a chunk was mid-write.
        releaseCannotBeConfirmed = (ending == .theHelperNeverAnswered)
        deviceLossEnding = ending

        guard sequencer?.deviceLost() == true else {
            // The run had already ended by some other route in the same turn. Nothing is owed.
            releaseCannotBeConfirmed = false
            deviceLossEnding = nil
            return
        }
    }

    // MARK: - What the sequencer reports

    private func sequencerReported(_ event: RunSequencerEvent) {
        switch event {
        case .pauseSettled(let resumeBlock):
            // **The second party of the handshake.** It arrives as the cycle's own reply carrying a
            // paused outcome and its resume point — the helper stating it settled at a chunk
            // boundary with no write in flight (NFR-REL-10). This is the only route to `paused`.
            RunControlLog.pauseSettled(atBlock: resumeBlock)
            report(.pauseSettled)

        case .runEnded(let result):
            RunControlLog.runEnded(result.outcome)

            // **Unconditional, and that is what makes route (b) free on every ordinary run.** A
            // wind-down that was never begun has nothing to stand down from; one that is waiting
            // for route (a)'s reply has just had it. Making the caller remember which it was would
            // put a branch here that only a drive being pulled ever exercises.
            //
            // It disarms a *log line*, not a double-ending — a mutation deleting it survived the
            // suite, which is how that was established. `RunSequencer.deviceLost()` already
            // refuses from `.ended`, so a late deadline could not end the run twice anyway; what
            // it could do is claim in the log that the helper never answered, three seconds after
            // it did. See `DeviceLossWindDown.standDown()`.
            windDown?.standDown()

            // **The sixth event, and the one place that reports it.** Both routes come through
            // here — route (a) as the reply's own outcome, route (b) through the wind-down — so
            // the machine's log says the same thing however the loss was found. The distinction is
            // not cosmetic: `deviceLost` is legal from `paused` and `runEnded` is not, which is the
            // row route (b) exists for.
            let theDriveWasLost = result.outcome == .deviceLost
            report(theDriveWasLost ? .deviceLost : .runEnded)
            deliverTheEndOfRun(result, theDriveWasLost: theDriveWasLost)
            releaseTheDrive(afterDeviceLoss: theDriveWasLost)
        }
    }

    /// Give the drive back.
    ///
    /// Ordinarily this waits for the helper to answer. **After a device loss that ended on the
    /// deadline it must not**, and the reason is a measured platform fact rather than caution: a
    /// second message on a connection with a blocking call in flight is not delivered until that
    /// call returns (2026-08-04, `scripts/xpc-concurrency-check.sh` — 24 pings issued during a
    /// 2,827.9 ms call were all answered *after* it). The deadline expiring means precisely that
    /// the owning connection is still blocked, so the acknowledgement being waited for cannot
    /// arrive until the thing that already failed to answer answers.
    ///
    /// The release is still **issued** in that case, and lands whenever the call finally returns.
    /// What changes is only that the machine stops waiting for it — because the alternative is
    /// sitting in `finishing` indefinitely with the device list frozen (FR-DEV-7), an uninstall
    /// blocked (NFR-INST-3) and ⌘Q asking about a run that is over, all on behalf of a drive that
    /// is not attached.
    ///
    /// **What it must not do is claim the drive was let go.** That is the half `QuitSequence` gets
    /// for free and this does not: there, terminating *is* the release (NFR-REL-5), so failing open
    /// asserts nothing untrue. Here the app stays alive, the helper may genuinely still hold the
    /// descriptor, and saying otherwise would be inventing an answer. It is recorded instead — and
    /// the recovery is real rather than theoretical, because the next `acquireDevice` is refused
    /// by the helper with its own reason if the claim is in fact still held.
    private func releaseTheDrive(afterDeviceLoss: Bool) {
        let canBeConfirmed = !releaseCannotBeConfirmed
        releaseCannotBeConfirmed = false

        if !canBeConfirmed {
            RunControlLog.releaseCannotBeConfirmed(deviceUnderTest)
        }

        release { [weak self] in
            guard let self else { return }
            guard canBeConfirmed else {
                // The blocking call returned after all and the release was answered. The machine
                // moved on when the deadline expired, so there is nothing left to do but say so:
                // this is the line that distinguishes "the claim was dropped late" from "the
                // claim is still held", and without it neither is visible afterwards.
                RunControlLog.releaseAcknowledgedLate()
                return
            }
            self.driveIsBack(afterDeviceLoss: afterDeviceLoss)
        }

        if !canBeConfirmed { driveIsBack(afterDeviceLoss: afterDeviceLoss) }
    }

    /// The drive is no longer this app's to hold, however that was established.
    ///
    /// Reported whatever the release said. The helper releases a claim when the connection that
    /// took it goes away (NFR-REL-5), so a failed release still ends with the device released —
    /// and staying in `finishing` for ever would be strictly worse than saying so and moving on.
    private func driveIsBack(afterDeviceLoss: Bool) {
        sequencer = nil
        pending = nil

        // Cleared together, and with the claim: the drive under test is the *claim's* subject, and
        // a stale one would make a disappearance long after the run look like this run's. The
        // state guard would refuse it anyway; clearing is what stops that being the only thing
        // standing between an old locator and a wrong answer.
        deviceUnderTest = nil
        windDown = nil

        // The report that needed it has already been built and handed out — `makeReport` runs
        // inside `sequencerReported`, which is upstream of every path to here.
        deviceLossEnding = nil

        report(.deviceReleased)

        // **FR-DEV-8's third obligation**, and the last of the three to be built: *re-run the
        // initial device discovery routine*.
        //
        // Here rather than at the run's end, and the difference matters. FR-DEV-7 freezes the
        // device list for the duration of a run; `DeviceDiscovery.refresh(reason:)` bypasses the
        // freeze deliberately — its own documentation names this as the caller it kept the bypass
        // for — but bypassing a freeze and waiting for it to lift are not the same act, and the
        // second is the honest one. By this line the claim is given up, the state has been told,
        // and the list is nobody's to freeze.
        //
        // **Passed down as a parameter rather than read from a field.** `deviceLossEnding` is the
        // obvious candidate and is wrong twice: it is `nil` for a route (a) loss, which is most of
        // them, and a field consulted after the run that set it is precisely the shape chunk 5's
        // surviving mutation was about. The value is threaded from `runEnded`, where it is simply
        // `result.outcome`, and no lifetime can go stale between there and here.
        //
        // Conditional, because re-enumerating after *every* run would be a behaviour change this
        // step was not asked for — and one that would fire on the path where nothing changed.
        if afterDeviceLoss { onDeviceLost() }

        settledIfAtRest()
    }

    /// The call boundary. Replaces `AppModel.cycleIsRunning` going false, and the quit's wind-down
    /// hangs off this transition.
    private func settledIfAtRest() {
        guard !state.isRunActive else { return }
        onRunSettled()
    }

    // MARK: - The report

    /// Hand the end of the run to the user, by **exactly one** of the two channels.
    ///
    /// ## Why this is a method and not two lines at the call site
    ///
    /// It used to be `onReport(makeReport(result))`, which is one line and has a hole in it.
    /// `makeReport` answers `nil` when the sequence produced no reply, and `AppModel.runProduced`
    /// reads that `nil` as *"the helper refused the call, so no run took place"* — a sentence that
    /// is true for the case it was written for and **false for a device loss**, where a run very
    /// much took place. Worse, it is the whole of what the user got: no report, no alert, one
    /// misleading log line (FR-DEV-8, chunk 6).
    ///
    /// ## Exactly one, and that is load-bearing rather than tidy
    ///
    /// `AppModel.presentedModals` flags `.runReport` and `.runFailure` independently, and
    /// `QuitPolicy.disposition(underModals:)` **refuses ⌘Q outright whenever more than one is
    /// flagged** — it cannot know which SwiftUI actually put on screen, because the second is
    /// queued invisibly (measured 2026-08-21). Raising both here would therefore kill ⌘Q on the
    /// normal path of the feature this step exists to build, which is the exact defect Step 11
    /// increment 12 was written to remove. So: a report if there is one, an alert if there is not,
    /// never both. `RunControllerDeviceLossSurfaceTests` pins it.
    ///
    /// The `nil` report is still forwarded on every **other** ending, because that is what clears
    /// `AppModel.lastRunReport` and logs the refusal — and on those endings the sentence is true.
    private func deliverTheEndOfRun(_ result: RunSequenceResult, theDriveWasLost: Bool) {
        if let report = makeReport(result) {
            onReport(report)
            return
        }

        guard theDriveWasLost else {
            onReport(nil)
            return
        }

        // No reply ever came back, so there is nothing to build a report from — and the drive is
        // gone, so there never will be. This is the only path in the app that says what happened
        // to a lost drive without a report behind it.
        RunControlLog.deviceLostWithNoReport(deviceLossEnding)
        onFailure(DeviceLossMessage.forRunWithNoReport(endedBy: deviceLossEnding))
    }

    /// Build the end-of-run report (FR-RPT-1…5).
    ///
    /// The drive comes from the identity captured at the **press**, not from a stored property read
    /// later and not from the model: `lastRunDevice` is not written until a claim exists, and a
    /// value read at the wrong instant is what headed every first-run report "Unidentified drive"
    /// (Step 14). One source, captured once, at the point the run was authorised.
    ///
    /// **The run's own ending is passed through, not re-inferred from the reply** (increment 8,
    /// FR-RPT-4). `result.outcome` is the only thing that knows the user pressed Stop: the last
    /// reply may say `pausedByUser`, or — when a stop races a call that was finishing anyway —
    /// `completed`, which is what used to make a run stopped at 2% report as a clean pass over the
    /// whole device. This method held that fact all along and threw it away.
    ///
    /// - Returns: `nil` when the request never became a run. `finalReply` is `nil` when no call ever
    ///   returned, and `RunReport.init?` refuses a mode a run may not start in — **a refused call is
    ///   not a run**, and gets no report rather than a file describing a test that never happened.
    private func makeReport(_ result: RunSequenceResult) -> RunReport? {
        guard let reply = result.finalReply, let pending else { return nil }
        return RunReport(reply: reply,
                         endedBy: result.outcome,
                         removalCallbackSaid: deviceLossEnding,
                         startBlock: result.startBlock,
                         blockCount: result.blockCount,
                         ioSizesUsed: result.ioSizesUsed,
                         device: pending.identity,
                         startedAt: pending.authorisedAt ?? Date(),
                         finishedAt: Date(),
                         usbLinkSpeedDescription: MetricsFormatting.linkSpeed(code: linkSpeedCode))
    }

    // MARK: - Plumbing

    /// Report a fact to the machine and move if it says to.
    ///
    /// An ignored event is **logged, never displayed** — it is not a decision to tell the user
    /// about, it is a fact arriving where the state says it cannot, which is how a wiring defect
    /// announces itself.
    private func report(_ event: RunControlEvent) {
        switch RunControlPolicy.outcome(of: event, in: state) {
        case .to(let next):
            log.notice("""
                       run control: \(String(describing: self.state), privacy: .public) → \
                       \(String(describing: next), privacy: .public) on \
                       \(String(describing: event), privacy: .public)
                       """)
            state = next
        case .ignored(let reason):
            log.error("run control: \(reason, privacy: .public)")
        }
    }

    /// **A command moving the machine, logged in `report(_:)`'s own shape.** Until 2026-09-11 the
    /// four command sites assigned `state` directly and only *events* were logged, so Step 12's
    /// checklist walk read `pausing → paused on pauseSettled` with no `running → pausing` before
    /// it — the helper's `run control set to pause` was the only trace of the press. Now every
    /// accepted command logs one line, and `run control: ` finds every transition whichever side
    /// moved the machine.
    ///
    /// "The Stop command" rather than "the user's Stop": Cancel and Quit issues it too.
    ///
    /// Takes the destination rather than asking the table again: every caller has just had it from
    /// ``RunControlPolicy/outcome(of:in:preconditions:)``, and a second lookup could disagree with
    /// the one the caller acted on.
    private func apply(_ command: RunCommand, movingTo next: RunControlState) {
        log.notice("""
                   run control: \(String(describing: self.state), privacy: .public) → \
                   \(String(describing: next), privacy: .public) on the \
                   \(command.label, privacy: .public) command
                   """)
        state = next
    }

    private static func describe(_ result: Result<Void, Error>) -> String {
        if case .failure(let error) = result { return error.localizedDescription }
        return ""
    }
}

// MARK: - The log

/// What the run did, for the record (NFR-OBS-1).
///
/// A `nonisolated enum` of static functions rather than calls scattered through the controller, for
/// the reason `PreRunWarningLog` and `RunReportLog` are: a log line is evidence, and evidence that
/// is written eleven different ways cannot be grepped for afterwards.
nonisolated enum RunControlLog {

    /// The run's identity and its two fixed parameters, at the moment it is authorised (NFR-OBS-1
    /// asks for start/stop and mode). The drive is named by **serial** — the axis that survives a
    /// renumbering — because this line outlives the enumeration that produced the BSD name.
    static func runStarting(device: ReportedDevice, ioSizeBytes: Int, failureMode: FailureModeCode) {
        runLog.notice("""
                      run authorised: drive serial \
                      \(device.usbSerialNumber ?? "none", privacy: .public); \
                      I/O size \(ioSizeBytes, privacy: .public) bytes; \
                      mode \(String(describing: failureMode), privacy: .public)
                      """)
    }

    /// The drive could not be prepared. **The volumes have already been put back** by the time this
    /// is written; the reason is recorded so an abort is explicable after the fact rather than
    /// looking like a run that vanished.
    static func startAborted(_ reason: String) {
        runLog.error("run aborted before any write: \(reason, privacy: .public)")
    }

    /// The helper settled at a chunk boundary with no write in flight (NFR-REL-10). Paired with the
    /// daemon's own *"run control set to pause"* line, these two timestamps are the settle latency —
    /// which is what `scripts/run-control-check.sh` measures.
    static func pauseSettled(atBlock block: UInt64) {
        runLog.notice("run paused and settled at block \(block, privacy: .public)")
    }

    /// **The drive under test left the machine** (Step 12, FR-DEV-8, route (b)).
    ///
    /// Written once per unplug rather than once per callback, because it is the first line of the
    /// account of an interrupted run and three of them would read as three losses.
    ///
    /// The drive is named by ``DeviceUnderTest/logIdentification`` — model and **serial**, with the
    /// BSD name labelled as what it was at the time. A log outlives the enumeration that produced
    /// the locator, and this project has already shipped one artefact that could not say which
    /// drive it was about (2026-08-06).
    ///
    /// The state is named too, and it is the fact that matters most here: a loss discovered while
    /// `paused` is one that **only** the removal callback could have seen, and a log that did not
    /// distinguish it could not tell route (b) working from route (a) having covered for it.
    static func deviceLost(_ device: DeviceUnderTest, whileIn state: RunControlState) {
        runLog.error("""
                     the drive under test left the machine while \
                     \(String(describing: state), privacy: .public): \
                     \(device.logIdentification, privacy: .public)
                     """)
    }

    /// A run began on a drive whose disappearance could not be recognised.
    ///
    /// Unreachable from a `DiscoveredDevice`, whose BSD name is not optional — so this is the shape
    /// of a wiring defect rather than a state, and it is logged for the reason
    /// ``RunEventOutcome/ignored`` is: route (b) going quiet is otherwise indistinguishable from a
    /// drive that was never unplugged.
    static func driveCannotBeWatchedForRemoval(_ device: ReportedDevice) {
        runLog.error("""
                     the run's drive has no BSD name, so its removal cannot be recognised: \
                     serial \(device.usbSerialNumber ?? "none", privacy: .public)
                     """)
    }

    /// The release was issued but **cannot be acknowledged**, because the helper is still inside
    /// the blocking call that went quiet (measured 2026-08-04). See `RunController.releaseTheDrive`.
    ///
    /// At error level, and deliberately: this is the one path where the app moves on without
    /// knowing whether the claim was dropped, and the next `acquireDevice` refusing is what a
    /// person would otherwise have to explain from nothing.
    static func releaseCannotBeConfirmed(_ device: DeviceUnderTest?) {
        runLog.error("""
                     release issued but not waited for — the helper has not answered the call \
                     it is inside, so this app cannot say the claim on \
                     \(device?.logIdentification ?? "the drive", privacy: .public) was dropped
                     """)
    }

    /// A slice of the drive under test disappeared and was **not** treated as device loss.
    ///
    /// ## ⚠️ This has never been observed to fire, and that is now understood rather than suspected
    ///
    /// Added 2026-09-08 at chunk 7f on the reasoning that a guard refusing in silence cannot be
    /// told apart from a callback that never fired. The reasoning was sound and **the remedy was
    /// not**: chunk 3's walk on 2026-09-09 showed this line has no reachable path on a normal run.
    ///
    /// Two independent reasons, either of which alone is sufficient:
    ///
    /// 1. The slices are torn down **by** the claim, and the claim is what tells the app which
    ///    drive is under test. They went at 13:14:58.535; `deviceUnderTest` was set at `.540` when
    ///    the claim returned `.ready`. `deviceDisappeared`'s `guard let deviceUnderTest` swallows
    ///    every one of them, five milliseconds too early, every time.
    /// 2. At the real unplug there are **no slices left to disappear** — the walk logged only
    ///    `disk7 (whole disk)`. They went 17 seconds earlier and cannot go twice.
    ///
    /// **Kept, not deleted**, because (1) is an ordering rather than a law: a future change that
    /// set `deviceUnderTest` at the press instead of at the claim would deliver these events, and
    /// this is what would make that visible rather than silent. It costs one branch.
    ///
    /// **What actually discharges the original worry** is the `discovery` category's own
    /// `a disk disappeared: diskNsM (slice)` lines, which fire at claim time and prove the
    /// DiskArbitration subscription is alive. Checklist chunk 3 reads those. Notice level, for the
    /// day it does fire.
    static func sliceOfTheDriveUnderTestIgnored(_ disk: DisappearedDisk,
                                                _ device: DeviceUnderTest) {
        runLog.notice("""
                      a slice of the drive under test disappeared and was ignored: \
                      \(disk.bsdName.rawValue, privacy: .public) — this run's own exclusive \
                      whole-disk claim is what removes it, and the drive itself is still here: \
                      \(device.logIdentification, privacy: .public)
                      """)
    }

    /// A device loss ended a run that produced **no report at all** (Step 12, chunk 6).
    ///
    /// `error` rather than `notice`, and the level is the point: this is the only ending in the app
    /// where the user is told about their drive by an alert instead of by a document, and the
    /// reason is that nothing came back to build a document from. Before chunk 6 this path logged
    /// *"the helper refused the call, so no run took place"* and showed nothing — a false sentence
    /// standing in for the message FR-DEV-8 requires.
    ///
    /// Names the ending so the log distinguishes the two ways route (b) can end a run without the
    /// report that would otherwise carry it.
    static func deviceLostWithNoReport(_ ending: DeviceLossEnding?) {
        runLog.error("""
                     device loss with no report: no reply ever came back, so there is nothing \
                     to build one from — \
                     \(ending?.description ?? "nothing recorded how it ended", privacy: .public)
                     """)
    }

    /// The release was answered after the machine had already moved on.
    ///
    /// The good ending of ``releaseCannotBeConfirmed(_:)``, and worth its own line: it is the
    /// difference between a claim that was dropped late and one that is still held, and neither is
    /// visible afterwards without it.
    static func releaseAcknowledgedLate() {
        runLog.notice("""
                      the release was acknowledged after the deadline had already ended the \
                      run; the claim was dropped
                      """)
    }

    static func runEnded(_ outcome: RunSequenceOutcome) {
        runLog.notice("run ended: \(String(describing: outcome), privacy: .public)")
    }

    /// The single Pause/Resume control issued something that is neither.
    ///
    /// `RunControlPolicy.controls` derives that control's label *and* its command from one value,
    /// which is what keeps them in step — so reaching this is a wiring defect rather than a state.
    /// Logged rather than absorbed, for the reason `RunEventOutcome.ignored` is: a fact arriving
    /// where the code says it cannot is how such a defect announces itself.
    static func unexpectedPauseCommand(_ command: RunCommand) {
        runLog.error("""
                     the pause control issued \(String(describing: command), privacy: .public), \
                     which it is never offered
                     """)
    }
}
