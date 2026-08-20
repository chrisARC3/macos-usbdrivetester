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
}

extension RunSequencer: RunSequencing {}

// MARK: - What a Start press produced

/// The answer to pressing Start (or, from increment 7, Restart).
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

    init(preconditions: @escaping () -> RunPreconditions,
         selectedDevice: @escaping () -> DiscoveredDevice?,
         prepare: @escaping (DiscoveredDevice,
                             @escaping (DevicePreparationOutcome) -> Void) -> Void,
         makeSequencer: @escaping (@escaping (RunSequencerEvent) -> Void) -> RunSequencing,
         setRunControl: @escaping (RunControlCode,
                                   @escaping (Result<Void, Error>) -> Void) -> Void,
         release: @escaping (@escaping () -> Void) -> Void,
         ioSizeBytes: @escaping () -> Int,
         failureMode: @escaping () -> FailureModeCode,
         onReport: @escaping (RunReport?) -> Void,
         onRunBegan: @escaping () -> Void = {},
         onRunSettled: @escaping () -> Void = {},
         onFailure: @escaping (RunFailureMessage) -> Void = { _ in }) {
        self.preconditions = preconditions
        self.selectedDevice = selectedDevice
        self.prepare = prepare
        self.makeSequencer = makeSequencer
        self.setRunControl = setRunControl
        self.release = release
        self.ioSizeBytes = ioSizeBytes
        self.failureMode = failureMode
        self.onReport = onReport
        self.onRunBegan = onRunBegan
        self.onRunSettled = onRunSettled
        self.onFailure = onFailure
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
        state = next

        RunControlLog.runStarting(device: pending.identity,
                                  ioSizeBytes: pending.ioSizeBytes,
                                  failureMode: failureMode())

        prepare(pending.device) { [weak self] outcome in
            self?.preparationFinished(outcome)
        }
    }

    private func preparationFinished(_ outcome: DevicePreparationOutcome) {
        switch outcome {
        case .aborted(let failure):
            // The volumes are already back by the time this arrives — that is what
            // `startAborted` promises, and `DevicePreparation` is what keeps it.
            RunControlLog.startAborted(failure.reason)
            report(.startAborted)
            pending = nil
            onFailure(RunFailureMessage(title: failure.alertTitle, text: failure.message))
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
            self.state = next
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
            self.state = next
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
        state = next

        sequencer?.stop()
        setRunControl(.stop) { result in
            guard case .success = result else {
                // Not surfaced: the run stops regardless, because no further call will be issued.
                // What is lost is only the *promptness* of the current call ending early.
                let detail = Self.describe(result)
                // `OSLogMessage` is expressible by a string *literal* and cannot be built with `+`
                // — the same trap as `#expect`'s `Comment` argument. Continuations, not
                // concatenation.
                log.error("""
                          stop request did not reach the helper: \(detail, privacy: .public); the \
                          run ends at the current call's boundary instead of the next chunk's
                          """)
                return
            }
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
            report(.runEnded)
            onReport(makeReport(result))
            releaseTheDrive()
        }
    }

    private func releaseTheDrive() {
        release { [weak self] in
            guard let self else { return }
            // Reported whatever the release said. The helper releases a claim when the connection
            // that took it goes away (NFR-REL-5), so a failed release still ends with the device
            // released — and staying in `finishing` for ever would be strictly worse than saying
            // so and moving on.
            self.sequencer = nil
            self.pending = nil
            self.report(.deviceReleased)
            self.settledIfAtRest()
        }
    }

    /// The call boundary. Replaces `AppModel.cycleIsRunning` going false, and the quit's wind-down
    /// hangs off this transition.
    private func settledIfAtRest() {
        guard !state.isRunActive else { return }
        onRunSettled()
    }

    // MARK: - The report

    /// Build the end-of-run report (FR-RPT-1…5).
    ///
    /// The drive comes from the identity captured at the **press**, not from a stored property read
    /// later and not from the model: `lastRunDevice` is not written until a claim exists, and a
    /// value read at the wrong instant is what headed every first-run report "Unidentified drive"
    /// (Step 14). One source, captured once, at the point the run was authorised.
    ///
    /// - Returns: `nil` when the request never became a run. `finalReply` is `nil` when no call ever
    ///   returned, and `RunReport.init?` refuses a mode a run may not start in — **a refused call is
    ///   not a run**, and gets no report rather than a file describing a test that never happened.
    private func makeReport(_ result: RunSequenceResult) -> RunReport? {
        guard let reply = result.finalReply, let pending else { return nil }
        return RunReport(reply: reply,
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
