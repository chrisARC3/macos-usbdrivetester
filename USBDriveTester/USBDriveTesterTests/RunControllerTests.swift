//
//  RunControllerTests.swift
//  Start owning unmount → acquire → run → release (Step 11, increment 5).
//  FR-CTRL-1/2/3/4/6/9, FR-WARN-1/2/3, NFR-USE-4, NFR-REL-10.
//
//  `DevicePreparationTests` pins what happens to the *drive*; this pins what happens to the
//  **state**, and the two orderings that no truth table can express.
//
//  Five properties are load-bearing here, and four of them look like formalities:
//
//    * **Pressing Start raises a dialog and does nothing else.** Nothing is unmounted, nothing is
//      claimed, and the machine does not move — because `starting` reports `isRunActive`, which
//      freezes the device list, blocks an uninstall and makes ⌘Q ask. A dialog being open is not
//      any of those things. It also means **Cancel unmounts nothing**, which is new: the gate now
//      sits *before* the unmount, so a wiring that unmounted first would leave a drive changed by a
//      dialog the user backed out of.
//    * **Stop moves the state BEFORE it tells the sequencer.** From a paused run the sequencer
//      finishes synchronously and emits `runEnded` in the same turn — and `runEnded` is *ignored*
//      from `paused`. Told in the other order the run never ends, and nothing else in the suite
//      would show it.
//    * **Resume clears the run-control level first, and waits.** `RunControlChannel` is a
//      process-wide slot that never clears itself; a resumed call issued before it is cleared
//      settles at its first chunk boundary into an event the machine ignores. That is a hang.
//    * **Nothing reaches `paused` on the strength of a `setRunControl` acknowledgement.** The
//      daemon recording a request and the run having acted on it are different facts, and only the
//      second is NFR-REL-10's guarantee.
//    * **The report names the drive captured at the press.** Not a property read later, not the
//      model: a value read at the wrong instant is what headed every first-run report
//      "Unidentified drive".
//

import Testing
import Foundation
@testable import USBDriveTester

// MARK: - Fixtures

private struct FakeError: Error, LocalizedError {
    var errorDescription: String? { "the helper connection dropped" }
}

/// The 4 TB T5 EVO fixture — three mounted volumes, one of them on a synthesized APFS disk.
private let fixtureDrive = DeviceFixtures.device(id: 0x8000,
                                                 bsdName: "disk8",
                                                 product: "PSSD T5 EVO",
                                                 sizeBytes: 4_000_787_030_016,
                                                 mountedVolumeNames: ["Vol_ExFAT", "Vol_APFS",
                                                                      "Vol_HFS"],
                                                 mountedVolumeBSDNames: ["disk8s2", "disk9s1",
                                                                         "disk8s4"],
                                                 usbSerialNumber: "00000S7CLNJ0WC02266P")

private let preparedGeometry = PreparedDeviceGeometry(logicalBlockSize: 512,
                                                      deviceBlockCount: 7_814_037_168,
                                                      usbLinkSpeedCode: 5)

/// One cycle reply, with everything the controller does not read defaulted.
private func reply(_ outcome: RunOutcomeCode = .completed,
                   chunksProcessed: UInt64 = 4,
                   mode: FailureModeCode = .logAndContinue) -> RunCycleOutcome {
    RunCycleOutcome(runOutcomeCode: outcome.rawValue,
                    interruptedAtBlock: 0,
                    chunksProcessed: chunksProcessed,
                    failedRangeCount: 0,
                    failureSummary: "",
                    cacheBypassCode: CacheBypassOutcome.bypassed.rawValue,
                    bufferBytesHeld: 0,
                    hostOverheadFraction: -1,
                    helperCoreFraction: -1,
                    failureModeUsedCode: mode.rawValue,
                    failedRangesEncoded: "",
                    failedBlockCount: 0,
                    deviceReadBytesPerSecond: -1,
                    writeBytesPerSecond: -1,
                    coverageBytesPerSecond: -1,
                    completedBytesPerSecond: -1,
                    readLatencySampleCount: 0,
                    readLatencyMinimumNanoseconds: 0,
                    readLatencyMaximumNanoseconds: 0,
                    readLatencyP99UpperBoundNanoseconds: 0,
                    message: "",
                    deviceLossPhaseCode: DeviceLossPhaseCode.unrecognised.rawValue)
}

private func result(_ outcome: RunSequenceOutcome = .completed,
                    finalReply: RunCycleOutcome? = reply()) -> RunSequenceResult {
    RunSequenceResult(outcome: outcome,
                      finalReply: finalReply,
                      ioSizesUsed: [1 << 22],
                      startBlock: 0,
                      blockCount: 7_814_037_168)
}

/// Records every request and lets the test decide when — and whether — the run reports back.
@MainActor
private final class StubSequencer: RunSequencing {

    struct Started: Equatable {
        let logicalBlockSize: UInt32
        let deviceBlockCount: UInt64
        let ioSizeBytes: Int
        let failureMode: FailureModeCode
    }

    let emit: (RunSequencerEvent) -> Void

    /// Writes into the bench's step log, so an *ordering* between a sequencer call and a
    /// `setRunControl` is assertable. Both happening is not the property; the order is.
    let record: (String) -> Void

    private(set) var started: [Started] = []
    private(set) var resumes = 0
    private(set) var stops = 0
    private(set) var deviceLosses = 0

    /// Whether a run is still there to end. The real sequencer answers `false` from `.ended`,
    /// which is what makes the second and third disappearance callbacks of one unplug free.
    var runIsStillGoing = true

    /// The reply a device-loss ending carries. `nil` models route (b) with no reply ever received
    /// — a run lost while paused, or one whose helper never answered.
    var deviceLossReply: RunCycleOutcome? = reply(.deviceLost)

    /// What `stop()` does. The **real** sequencer, stopped while paused, finishes synchronously and
    /// emits `runEnded` inside the `stop()` call — which is what makes the state-before-sequencer
    /// ordering load-bearing rather than stylistic.
    var stopEndsTheRunSynchronously = false

    init(emit: @escaping (RunSequencerEvent) -> Void, record: @escaping (String) -> Void) {
        self.emit = emit
        self.record = record
    }

    func start(logicalBlockSize: UInt32,
               deviceBlockCount: UInt64,
               ioSizeBytes: Int,
               failureMode: FailureModeCode) -> Bool {
        record("sequencer.start")
        started.append(Started(logicalBlockSize: logicalBlockSize,
                               deviceBlockCount: deviceBlockCount,
                               ioSizeBytes: ioSizeBytes,
                               failureMode: failureMode))
        return true
    }

    func resume() -> Bool {
        record("sequencer.resume")
        resumes += 1
        return true
    }

    func stop() -> Bool {
        record("sequencer.stop")
        stops += 1
        if stopEndsTheRunSynchronously { emit(.runEnded(result(.stoppedByUser))) }
        return true
    }

    /// The **real** sequencer ends the run inside this call, from either phase — so the stub does
    /// too. Chunk 4's ordering depends on it exactly as `stop()`'s does: `releaseCannotBeConfirmed`
    /// is set before this is called because the release goes out in the same turn.
    func deviceLost() -> Bool {
        record("sequencer.deviceLost")
        deviceLosses += 1
        guard runIsStillGoing else { return false }
        runIsStillGoing = false
        emit(.runEnded(result(.deviceLost, finalReply: deviceLossReply)))
        return true
    }
}

/// Everything the controller talks to, scripted and recorded.
@MainActor
private final class Bench {

    // Scripted.
    var selection: DiscoveredDevice? = fixtureDrive
    var mayIssueNewWork = true
    var preparationOutcome: DevicePreparationOutcome = .ready(preparedGeometry)
    var runControlResult: Result<Void, Error> = .success(())
    var ioSize = 1 << 22
    var mode: FailureModeCode = .logAndContinue

    /// Held instead of answered, so a test can observe the state *while* the drive is being
    /// prepared — which is the whole of `starting`.
    var holdPreparation = false
    private var pendingPreparation: ((DevicePreparationOutcome) -> Void)?

    /// The same, for the release at the end of a run — which is the whole of `finishing`. Without
    /// it that state cannot be sat in, and a walk over "every state" would have to skip one and
    /// call itself complete.
    var holdRelease = false
    private var pendingRelease: (() -> Void)?

    // Recorded.
    private(set) var steps: [String] = []
    private(set) var prepared: [String] = []
    private(set) var runControlCodes: [RunControlCode] = []
    private(set) var releases = 0
    private(set) var reports: [RunReport?] = []
    private(set) var runBegans = 0
    private(set) var settles = 0
    private(set) var failures: [RunFailureMessage] = []
    private(set) var sequencer: StubSequencer?

    /// The wind-down the controller built for a device loss, and the deadline it armed.
    ///
    /// The deadline is **held rather than run**, exactly as `QuitSequenceTests` holds the quit's:
    /// a test that waits three seconds for a timeout is slow now and flaky later, and this one is
    /// unreachable by clicking in any case — it needs a drive pulled at the moment a privileged
    /// call wedges.
    private(set) var windDowns = 0
    private(set) var windDownDeadlineSeconds: TimeInterval?

    /// **Every** wind-down built, in order, held so a test can ask whether each was **disarmed**.
    ///
    /// A list rather than one, and that is not thoroughness: holding only the latest is where a
    /// build-one-per-callback defect hides. One unplug delivers three callbacks, so a controller
    /// that built three sequences would leave two of them armed with nothing tracking them, and an
    /// assertion on the last would pass.
    ///
    /// The controller drops its own reference when the drive goes back, so this is also the only
    /// way to see a sequence that outlived the run it was guarding — the case that matters, since
    /// a deadline still armed after route (a) resolved the loss writes an error-level line
    /// accusing the helper of never answering.
    private(set) var windDownsBuilt: [DeviceLossWindDown] = []

    private var fireWindDownDeadline: (@MainActor () -> Void)?

    private(set) lazy var controller: RunController = RunController(
        preconditions: {
            RunPreconditions(hasUsableSelection: self.selection?.isSelectable ?? false,
                             mayIssueNewWork: self.mayIssueNewWork)
        },
        selectedDevice: { self.selection },
        prepare: { device, done in
            self.steps.append("prepare")
            self.prepared.append(device.bsdName.rawValue)
            if self.holdPreparation {
                self.pendingPreparation = done
            } else {
                done(self.preparationOutcome)
            }
        },
        makeSequencer: { emit in
            self.steps.append("makeSequencer")
            let stub = StubSequencer(emit: emit, record: { self.steps.append($0) })
            self.sequencer = stub
            return stub
        },
        makeWindDown: { end in
            self.steps.append("makeWindDown")
            self.windDowns += 1
            let windDown = DeviceLossWindDown(deadlineSeconds: 3,
                                              schedule: { seconds, work in
                                                  self.windDownDeadlineSeconds = seconds
                                                  self.fireWindDownDeadline = work
                                              },
                                              end: end)
            self.windDownsBuilt.append(windDown)
            return windDown
        },
        setRunControl: { code, done in
            self.steps.append("setRunControl(\(code))")
            self.runControlCodes.append(code)
            done(self.runControlResult)
        },
        release: { done in
            self.steps.append("release")
            self.releases += 1
            if self.holdRelease { self.pendingRelease = done } else { done() }
        },
        ioSizeBytes: { self.ioSize },
        failureMode: { self.mode },
        onReport: { self.reports.append($0) },
        onRunBegan: { self.runBegans += 1 },
        onRunSettled: {
            self.steps.append("settled")
            self.settles += 1
        },
        onFailure: { self.failures.append($0) })

    /// Emit an event from the run's sequencer.
    ///
    /// A method rather than `sequencer?.emit(…)` at the call sites: optional chaining
    /// **silently does nothing** when no sequencer exists, which turns "the drive was never
    /// prepared" into a puzzling assertion failure several lines later instead of into the
    /// one-line explanation it is.
    func emit(_ event: RunSequencerEvent) {
        guard let sequencer else {
            Issue.record("no sequencer exists to emit \(event) from; steps: \(steps)")
            return
        }
        sequencer.emit(event)
    }

    /// Finish a preparation that was being held.
    func finishPreparation(_ outcome: DevicePreparationOutcome? = nil) {
        let done = pendingPreparation
        pendingPreparation = nil
        done?(outcome ?? preparationOutcome)
    }

    /// Finish a release that was being held.
    func finishRelease() {
        let done = pendingRelease
        pendingRelease = nil
        done?()
    }

    /// Whether every wind-down this run built has been disarmed.
    var everyWindDownIsFinished: Bool { windDownsBuilt.allSatisfy(\.isFinished) }

    /// Fire the wind-down's deadline by hand.
    ///
    /// - Returns: whether one was armed. A caller must treat `false` as a failure: a deadline that
    ///   was never scheduled and a deadline that fired and did nothing look identical from the
    ///   assertions, which is the empty-result-read-as-a-finding trap in miniature.
    @discardableResult
    func expireWindDownDeadline() -> Bool {
        guard let fire = fireWindDownDeadline else { return false }
        fireWindDownDeadline = nil
        fire()
        return true
    }

    /// The 1 TB scratch T5 leaving the machine — the whole disk, as DiskArbitration reports it.
    static func unplugged(_ bsdName: String, isWholeDisk: Bool = true) -> DisappearedDisk {
        DisappearedDisk(bsdName: BSDDeviceName(bsdName), isWholeDisk: isWholeDisk)
    }

    /// Drive the machine to `target` **through the transitions the app takes**, never by assigning.
    ///
    /// A test that posed as a state would be indistinguishable from one that reached it, right up
    /// until the pose was wrong — the same reasoning `tools/ui-probe` records for its render hosts.
    ///
    /// - Returns: `true` if the machine is now in `target`. A caller must treat `false` as a
    ///   failure rather than as a state to skip: a walk that quietly covered seven of eight rows
    ///   is the number-that-did-not-move trap wearing a green hat.
    @discardableResult
    func driveTo(_ target: RunControlState) -> Bool {
        switch target {
        case .idle:
            break
        case .starting:
            holdPreparation = true
            startAndProceed()
        case .running:
            startAndProceed()
        case .pausing:
            startAndProceed()
            controller.pause()
        case .paused:
            runToPaused()
        case .stopping:
            startAndProceed()
            controller.stop()
        case .finishing:
            // The release is held open, so the machine sits between the run ending and the drive
            // being let go.
            holdRelease = true
            startAndProceed()
            emit(.runEnded(Bench.completedRun))
        case .finished:
            startAndProceed()
            emit(.runEnded(Bench.completedRun))
        }
        return controller.state == target
    }

    /// A run that finished cleanly, for the walks above.
    static let completedRun = RunSequenceResult(outcome: .completed,
                                                finalReply: nil,
                                                ioSizesUsed: [1 << 22],
                                                startBlock: 0,
                                                blockCount: 7_814_037_168)

    /// Press Start and answer the dialog with Proceed — the ordinary path to a running run.
    @discardableResult
    func startAndProceed() -> RunStartRequest {
        let request = controller.startRequested(warningsSuppressed: false)
        controller.startAuthorised(by: PreRunOutcome(issuesRun: true, persistsSuppression: false))
        return request
    }

    /// Drive a run all the way to `paused`.
    ///
    /// **The `pause()` in the middle is not optional**, and leaving it out is a mistake that hides
    /// itself: `pauseSettled` is legal only from `pausing`, so without it the event is ignored, the
    /// state stays `running`, and every test built on this helper quietly exercises a *running* run
    /// while claiming to exercise a paused one. That is what happened when this was first written —
    /// `stoppingAPausedRunMovesTheStateBeforeTellingTheSequencer` passed without ever reaching
    /// `paused`.
    func runToPaused() {
        startAndProceed()
        controller.pause()                                   // → .pausing (the daemon is told)
        emit(.pauseSettled(resumeBlock: 8_192))              // → .paused (the run has settled)
    }
}

// MARK: - The I/O size, captured once (Step 11, increment 6)

@MainActor
struct RunControllerIOSizeTests {

    /// **The size is read when the gate is answered, not when the drive comes back prepared.**
    ///
    /// The two moments are separated by the whole unmount-and-claim sequence — the mount table's
    /// settle budget alone is twelve looks at 150 ms — and until increment 6 the controller called
    /// the `ioSizeBytes` closure at *both*. That was harmless only while the closure returned a
    /// constant. With a live dropdown behind it, it is two properties naming one fact at two
    /// instants: the exact shape of the defect that headed every first-run report *"Unidentified
    /// drive"*.
    ///
    /// `IOSizeSelection` refusing the control during `starting` is the other guard on this, and it
    /// is the weaker one — it depends on a table staying right, where this depends on nothing.
    @Test func theSizeIsCapturedWhenTheGateIsAnsweredAndNotWhenTheDriveIsReady() {
        let bench = Bench()
        bench.ioSize = 1 << 20
        bench.holdPreparation = true
        bench.startAndProceed()

        // The dropdown moves while the drive is being prepared — which the control forbids, but a
        // guard that depends on a control is not a guard.
        bench.ioSize = 8 << 20
        bench.finishPreparation()

        #expect(bench.sequencer?.started.first?.ioSizeBytes == 1 << 20,
                "the run must use the size it was authorised at")
    }

    /// The ordinary path still reads the dropdown — a capture that always returned the default
    /// would pass the test above and break the feature.
    @Test func aRunUsesWhicheverSizeWasSelectedWhenItStarted() {
        for size in TesterProtocol.permittedIOSizes {
            let bench = Bench()
            bench.ioSize = size
            bench.startAndProceed()
            #expect(bench.sequencer?.started.first?.ioSizeBytes == size)
        }
    }

    /// FR-CTRL-8: *"a run uses exactly one I/O size for its whole life"*. One call to the
    /// sequencer, one size, and nothing re-reads it afterwards.
    @Test func aRunIsStartedWithOneSizeAndOnlyOne() {
        let bench = Bench()
        bench.ioSize = 2 << 20
        bench.startAndProceed()
        bench.ioSize = 8 << 20
        bench.controller.pause()
        bench.emit(.pauseSettled(resumeBlock: 8_192))
        bench.controller.resume()

        #expect(bench.sequencer?.started.map(\.ioSizeBytes) == [2 << 20],
                "a resume must not re-read the dropdown")
    }
}

// MARK: - The relocated gate

@MainActor
struct RunControllerStartGateTests {

    /// **Nothing but a dialog.** The machine does not move, nothing is unmounted and nothing is
    /// claimed — which is what makes Cancel free of consequences.
    @Test func pressingStartRaisesADialogAndDoesNothingElse() {
        let bench = Bench()
        let request = bench.controller.startRequested(warningsSuppressed: false)

        guard case .prompt = request else {
            Issue.record("expected a prompt, got \(request)")
            return
        }
        #expect(bench.controller.state == .idle)
        #expect(bench.steps.isEmpty, "no preparation, no sequencer, no run-control traffic")
    }

    /// The dialog names the **selected** drive now, not a held one — Start is what acquires, so
    /// nothing is held when it is pressed. By model and USB serial: the axis that survives a
    /// renumbering.
    @Test func theDialogNamesTheSelectedDriveByModelAndSerial() {
        let bench = Bench()
        guard case .prompt(let prompt) = bench.controller.startRequested(warningsSuppressed: false)
        else {
            Issue.record("expected a prompt")
            return
        }

        #expect(prompt.device.usbSerialNumber == "00000S7CLNJ0WC02266P")
        #expect(prompt.device.modelDescription.contains("T5 EVO"))
        #expect(prompt == .fullWarnings(prompt.device))
    }

    /// NFR-USE-4 as qualified 2026-08-09: the **text** is suppressible, the deliberate act is not.
    @Test func suppressedWarningsStillRaiseAConfirmationNamingTheDrive() {
        let bench = Bench()
        guard case .prompt(let prompt) = bench.controller.startRequested(warningsSuppressed: true)
        else {
            Issue.record("expected a prompt")
            return
        }

        #expect(prompt == .briefConfirmation(prompt.device))
        #expect(prompt.device.usbSerialNumber == "00000S7CLNJ0WC02266P")
    }

    /// **New in this increment, and it is human-checklist item 2's unit half.** The gate sits before
    /// the unmount now, so backing out of the dialog must leave the drive exactly as it was.
    @Test func cancellingIssuesNoRunAndUnmountsNothing() {
        let bench = Bench()
        _ = bench.controller.startRequested(warningsSuppressed: false)
        bench.controller.startAuthorised(
            by: PreRunOutcome(issuesRun: false, persistsSuppression: false))

        #expect(bench.controller.state == .idle)
        #expect(bench.steps.isEmpty)
        #expect(bench.reports.isEmpty, "a request that never became a run gets no report")
    }

    /// The `guard outcome.issuesRun` half of the relocated gate. A fabricated outcome claiming an
    /// acknowledgement that never happened still issues nothing.
    @Test func anOutcomeThatDoesNotIssueARunIssuesNothingEvenWhenFabricated() {
        let bench = Bench()
        bench.controller.startAuthorised(
            by: PreRunOutcome(issuesRun: false, persistsSuppression: true))

        #expect(bench.controller.state == .idle)
        #expect(bench.steps.isEmpty)
    }

    /// **Human-checklist item 7's unit half.** The quit confirmation is window-modal on the main
    /// window, so a quit can go pending while the sheet is up — and a press that cannot start a run
    /// is not a run that started.
    @Test func aQuitGoingPendingWhileTheDialogIsOpenIssuesNothing() {
        let bench = Bench()
        _ = bench.controller.startRequested(warningsSuppressed: false)
        bench.mayIssueNewWork = false
        bench.controller.startAuthorised(
            by: PreRunOutcome(issuesRun: true, persistsSuppression: false))

        #expect(bench.controller.state == .idle, "re-evaluated at the answer, not at the press")
        #expect(bench.steps.isEmpty)
    }

    @Test func startIsRefusedWithItsReasonWhenAQuitIsAlreadyPending() {
        let bench = Bench()
        bench.mayIssueNewWork = false

        guard case .refused(let reason) = bench.controller.startRequested(warningsSuppressed: false)
        else {
            Issue.record("expected a refusal")
            return
        }
        #expect(reason.contains("asked to quit"))
    }

    /// FR-CTRL-9 — one drive at a time, and the refusal is named rather than left to the dimming.
    @Test func startIsRefusedWhileARunIsAlreadyInProgress() {
        let bench = Bench()
        bench.startAndProceed()
        #expect(bench.controller.state == .running)

        guard case .refused(let reason) = bench.controller.startRequested(warningsSuppressed: false)
        else {
            Issue.record("expected a refusal")
            return
        }
        #expect(reason.contains("already in progress"))
        #expect(bench.prepared.count == 1, "and no second preparation was begun")
    }

    /// **The run happens to the drive the dialog named**, not to whatever is selected by the time
    /// the dialog is answered. The whole acknowledgement is about a specific drive, identified by
    /// model and USB serial; running against a different one would make the confirmation a
    /// statement about something else entirely.
    ///
    /// (Whether that drive is *still* the selection is `DevicePreparation`'s question, answered
    /// immediately before the unmount — this is only about which drive is handed to it.)
    @Test func theRunUsesTheDriveTheDialogNamedEvenIfTheSelectionChanged() {
        let bench = Bench()
        _ = bench.controller.startRequested(warningsSuppressed: false)

        bench.selection = DeviceFixtures.testDrive          // a different drive, mid-dialog
        bench.controller.startAuthorised(
            by: PreRunOutcome(issuesRun: true, persistsSuppression: false))

        #expect(bench.prepared == ["disk8"], "the drive the dialog named, not the new selection")
        bench.emit(.runEnded(result()))
        #expect((bench.reports.first ?? nil)?.device.usbSerialNumber == "00000S7CLNJ0WC02266P")
    }

    @Test func startIsRefusedWithNoUsableSelection() {
        let bench = Bench()
        bench.selection = nil

        guard case .refused(let reason) = bench.controller.startRequested(warningsSuppressed: false)
        else {
            Issue.record("expected a refusal")
            return
        }
        #expect(reason.contains("Select a drive"))
    }
}

// MARK: - The walk from idle to finished

@MainActor
struct RunControllerStateWalkTests {

    /// `starting` is entered when the dialog is **answered**, and it lasts as long as the drive is
    /// being prepared — genuinely multi-second, since the mount table's settle budget alone is
    /// twelve looks at 150 ms.
    @Test func authorisingEntersStartingAndPreparesTheSelectedDrive() {
        let bench = Bench()
        bench.holdPreparation = true
        bench.startAndProceed()

        #expect(bench.controller.state == .starting)
        #expect(bench.prepared == ["disk8"])
        #expect(bench.controller.isRunActive, "the list freezes and ⌘Q asks from here")
        #expect(bench.controller.hasLiveSession == false, "nothing has been written yet")
    }

    @Test func aPreparedDriveEntersRunningAndStartsTheSequencerOnTheClaimsGeometry() {
        let bench = Bench()
        bench.startAndProceed()

        #expect(bench.controller.state == .running)
        #expect(bench.sequencer?.started == [StubSequencer.Started(logicalBlockSize: 512,
                                                                   deviceBlockCount: 7_814_037_168,
                                                                   ioSizeBytes: 1 << 22,
                                                                   failureMode: .logAndContinue)])
        #expect(bench.controller.hasLiveSession)
        #expect(bench.runBegans == 1, "the previous run's report is not this run's")
    }

    /// **A paused run still has a live session, and the panel must still show its figures.**
    ///
    /// Found by the human checklist on 2026-08-18, not by this suite: pressing Pause blanked the
    /// entire measurements block, because `paused` was grouped with the states that have nothing
    /// to show. It is not one of them — the claim is held and the figures are this run's — and
    /// reading the numbers is one of the main reasons to pause.
    ///
    /// Every state is asserted rather than just the one that broke, so the next person to add a
    /// state has to decide which side it falls on instead of inheriting a default.
    @Test func everyStateAgreesOnWhetherThePanelHasSomethingToShow() {
        let bench = Bench()
        bench.runToPaused()          // start → proceed → pause → pauseSettled
        #expect(bench.controller.state == .paused)
        #expect(bench.controller.hasLiveSession,
                "PAUSED: the claim is held and the figures are this run's — this is the one that blanked the panel")

        bench.controller.resume()
        #expect(bench.controller.state == .running, "resume must actually resume")
        #expect(bench.controller.hasLiveSession, "running")

        bench.controller.stop()
        #expect(bench.controller.hasLiveSession, "stopping: still holding, still this run's")
    }

    /// **Every one of the eight states is reachable by real transitions.**
    ///
    /// *A state nobody can observe is a state nobody has checked* (CONSTRAINTS section 2), and this
    /// step has already had one row go quietly unproducible: increment 5 made "a quit pending while
    /// the pre-run dialog is open" unreachable, and the checklist item guarding it had to be
    /// retired rather than run. That was found by a person at a keyboard. This finds the next one.
    ///
    /// It also earns `Bench.driveTo`, which drives the machine through the transitions the app
    /// takes rather than assigning a state — the difference between testing the machine and
    /// testing a pose.
    @Test func everyStateIsReachableByRealTransitions() {
        for state in RunControlState.allCases {
            let bench = Bench()
            #expect(bench.driveTo(state), "the machine cannot reach \(state)")
        }
    }

    /// A refused call is not a run: back to `idle`, **no report**, and the cause put in front of the
    /// user. The volumes are already back by the time this arrives — that is what `startAborted`
    /// promises and what `DevicePreparation` keeps.
    @Test func anAbortReturnsToIdleWithNoReportAndSurfacesTheCause() {
        let bench = Bench()
        bench.preparationOutcome = .aborted(
            DevicePreparationFailure(reason: "Could not unmount Vol_HFS: the disk is in use.",
                                     restore: .succeeded("remounted"),
                                     operation: .unmount))
        bench.startAndProceed()

        #expect(bench.controller.state == .idle)
        #expect(bench.reports.isEmpty)
        #expect(bench.failures.count == 1)
        #expect(bench.failures.first?.text.contains("Vol_HFS") == true)
        #expect(bench.failures.first?.title == "The drive could not be unmounted",
                "headed with what did not happen, from OutcomePresentation")
        #expect(bench.releases == 0, "no claim was established, so none is released here")
        #expect(bench.failures.first?.remedy == nil,
                "an unmount refusal has no one-click fix, and must not offer a button to nowhere")
    }

    /// **The remedy survives the trip from the preparation to the dialog** (increment 10). The
    /// failure names the operation, `OutcomeOperation` decides which operations have a fix, and
    /// this is the one seam between them — a `RunFailureMessage` built without the remedy is a
    /// one-button dialog for a problem the app knows how to fix.
    @Test func aFullDiskAccessAbortCarriesItsRemedyToTheDialog() {
        let bench = Bench()
        bench.preparationOutcome = .aborted(
            DevicePreparationFailure(reason: "This app needs Full Disk Access before it can test "
                                           + "a drive.",
                                     restore: nil,
                                     operation: .fullDiskAccess))
        bench.startAndProceed()

        #expect(bench.controller.state == .idle)
        #expect(bench.reports.isEmpty)
        #expect(bench.failures.count == 1)
        #expect(bench.failures.first?.title == "Full Disk Access has not been granted")
        #expect(bench.failures.first?.remedy == .openFullDiskAccessSettings)
        #expect(bench.releases == 0)
    }

    @Test func theRunEndsThroughFinishingAndReleaseToFinished() {
        let bench = Bench()
        bench.startAndProceed()
        bench.emit(.runEnded(result()))

        #expect(bench.controller.state == .finished)
        #expect(bench.releases == 1)
        #expect(bench.controller.isRunActive == false)
    }

    /// An aborted Start must not relabel the metrics panel: the previous run's figures are still on
    /// screen and they are still that run's.
    @Test func anAbortedStartDoesNotRelabelTheMetricsPanel() {
        let bench = Bench()
        bench.startAndProceed()
        bench.emit(.runEnded(result()))
        let afterAGoodRun = bench.controller.lastRunDevice
        let startedAt = bench.controller.lastRunStartedAt
        #expect(afterAGoodRun?.usbSerialNumber == "00000S7CLNJ0WC02266P")

        // **A DIFFERENT drive, and that is the assertion.** Written against the same drive twice
        // this test agreed with any change: relabelling wrote back an identical value and a
        // mutation that promoted the label at the press survived the whole suite.
        bench.selection = DeviceFixtures.testDrive
        bench.preparationOutcome = .aborted(
            DevicePreparationFailure(reason: "refused", restore: nil))
        bench.startAndProceed()

        #expect(bench.controller.lastRunDevice == afterAGoodRun)
        #expect(bench.controller.lastRunDevice?.usbSerialNumber == "00000S7CLNJ0WC02266P",
                "the panel still names the drive that actually ran")
        #expect(bench.controller.lastRunStartedAt == startedAt)
    }
}

// MARK: - Pause, and what may not be claimed

@MainActor
struct RunControllerPauseTests {

    /// **NFR-REL-10's headline property.** A `setRunControl` reply says only that the helper was
    /// *told*. Showing "Paused" on it would claim a guarantee — settled at a chunk boundary, no
    /// write in flight — that nothing has established.
    @Test func nothingReachesPausedOnTheStrengthOfTheAcknowledgement() {
        let bench = Bench()
        bench.startAndProceed()
        bench.controller.pause()

        #expect(bench.runControlCodes == [.pause])
        #expect(bench.controller.state == .pausing, "told, not settled")
        #expect(bench.controller.state != .paused)
    }

    /// …and the settle is what gets there. It arrives as the cycle's own reply, not as the
    /// acknowledgement of the request.
    @Test func onlyTheSettleReachesPaused() {
        let bench = Bench()
        bench.startAndProceed()
        bench.controller.pause()
        bench.emit(.pauseSettled(resumeBlock: 8_192))

        #expect(bench.controller.state == .paused)
    }

    /// If the request never lands, **no pause has been requested** — so the state must not say one
    /// has, and the run carries on. Recoverable: Pause can be pressed again, and Stop is offered.
    @Test func aPauseRequestThatNeverReachedTheHelperLeavesTheRunRunning() {
        let bench = Bench()
        bench.startAndProceed()
        bench.runControlResult = .failure(FakeError())
        bench.controller.pause()

        #expect(bench.controller.state == .running)
        #expect(bench.failures.count == 1)
        #expect(bench.failures.first?.text.contains("still going") == true)
        #expect(bench.failures.first?.title == "The run could not be paused")
    }

    /// A run can end in the fraction of a millisecond the acknowledgement takes, and `pause` is
    /// refused from `finishing`. Re-applying the command at the acknowledgement is what makes that
    /// harmless rather than a state the machine cannot leave.
    @Test func aPauseThatRacesTheEndOfTheRunDoesNotDragItBack() {
        let bench = Bench()
        bench.startAndProceed()
        bench.emit(.runEnded(result()))
        #expect(bench.controller.state == .finished)

        bench.controller.pause()
        #expect(bench.controller.state == .finished)
        #expect(bench.runControlCodes.isEmpty, "refused before any message went out")
    }
}

// MARK: - Resume, and the level that must be cleared first

@MainActor
struct RunControllerResumeTests {

    /// **The hang guard, at the resume end.** `RunControlChannel` is a process-wide slot that never
    /// clears itself: a call issued while the level still says `pause` settles at its first chunk
    /// boundary, emits `pauseSettled` into a machine that is in `running`, and that event is
    /// ignored. Sequencer paused, machine running, nothing coming.
    @Test func resumingClearsTheRunControlLevelBeforeIssuingTheNextCall() {
        let bench = Bench()
        bench.runToPaused()
        bench.controller.resume()

        #expect(bench.controller.state == .running)
        #expect(bench.sequencer?.resumes == 1)
        #expect(bench.runControlCodes.last == .proceed)

        // **The order is the assertion.** Both happening is not the property — a resume that
        // cleared the level *after* issuing the call would satisfy every other check here and still
        // hand the helper a run whose level says `pause`.
        guard let cleared = bench.steps.firstIndex(of: "setRunControl(proceed)"),
              let resumed = bench.steps.firstIndex(of: "sequencer.resume") else {
            Issue.record("expected both a cleared level and a resumed sequencer: \(bench.steps)")
            return
        }
        #expect(cleared < resumed)
    }

    /// …and it is **awaited**. The two messages travel on different connections, so nothing orders
    /// them: a resume that could not clear the level must not issue the call at all.
    @Test func aResumeIsAbandonedWhenTheLevelCannotBeCleared() {
        let bench = Bench()
        bench.runToPaused()
        bench.runControlResult = .failure(FakeError())
        bench.controller.resume()

        #expect(bench.controller.state == .paused, "still paused, and still recoverable")
        #expect(bench.sequencer?.resumes == 0, "no call was issued against a stale level")
        #expect(bench.failures.first?.text.contains("still paused") == true)
        #expect(bench.failures.first?.title == "The run could not be resumed")
    }

    @Test func resumingIsRefusedWhenNothingIsPaused() {
        let bench = Bench()
        bench.startAndProceed()
        bench.controller.resume()

        #expect(bench.controller.state == .running)
        #expect(bench.runControlCodes.isEmpty)
        #expect(bench.sequencer?.resumes == 0)
    }
}

// MARK: - Stop, and the ordering that makes it work at all

@MainActor
struct RunControllerStopTests {

    /// **The ordering trap.** `RunSequencer.stop()` from a paused run finishes synchronously and
    /// emits `runEnded` inside the call — and `runEnded` is *ignored* from `paused`, being legal
    /// only from `running`, `pausing` and `stopping`. Tell the sequencer before moving the state and
    /// the event is silently dropped: the run never ends, the drive is never released, and the
    /// volumes never come back.
    @Test func stoppingAPausedRunMovesTheStateBeforeTellingTheSequencer() {
        let bench = Bench()
        bench.runToPaused()
        bench.sequencer?.stopEndsTheRunSynchronously = true

        bench.controller.stop()

        #expect(bench.controller.state == .finished, "the synchronous runEnded was not dropped")
        #expect(bench.releases == 1)
    }

    /// Half of stopping is the app's own — it declines to issue the next bounded call — so it is
    /// applied immediately rather than waiting on the daemon, which is the asymmetry with pause.
    @Test func stoppingARunningRunTellsBothTheSequencerAndTheHelper() {
        let bench = Bench()
        bench.startAndProceed()
        bench.controller.stop()

        #expect(bench.controller.state == .stopping)
        #expect(bench.sequencer?.stops == 1)
        #expect(bench.runControlCodes == [.stop])
    }

    /// A lost stop request costs promptness, not correctness: no further call is issued whatever
    /// happens, so the run still ends — at the current call's boundary instead of the next chunk's.
    @Test func aStopRequestThatNeverReachedTheHelperStillEndsTheRun() {
        let bench = Bench()
        bench.startAndProceed()
        bench.runControlResult = .failure(FakeError())
        bench.controller.stop()

        #expect(bench.controller.state == .stopping)
        #expect(bench.sequencer?.stops == 1)
        #expect(bench.failures.isEmpty, "not surfaced — the run stops regardless")

        bench.emit(.runEnded(result(.stoppedByUser)))
        #expect(bench.controller.state == .finished)
    }

    /// A stop supersedes a pause that has not settled, and `pauseSettled` is then ignored — so a
    /// run that stopped must never land in `paused`.
    @Test func stoppingSupersedesAnUnsettledPause() {
        let bench = Bench()
        bench.startAndProceed()
        bench.controller.pause()
        bench.controller.stop()
        #expect(bench.controller.state == .stopping)

        bench.emit(.pauseSettled(resumeBlock: 8_192))
        #expect(bench.controller.state == .stopping, "a stopped run does not become a paused one")
    }

    @Test func stoppingIsRefusedWhenThereIsNoRun() {
        let bench = Bench()
        bench.controller.stop()

        #expect(bench.controller.state == .idle)
        #expect(bench.runControlCodes.isEmpty)
    }
}

// MARK: - The call boundary, and the report

@MainActor
struct RunControllerSettleAndReportTests {

    /// **The call boundary the quit promise is made at**, replacing `cycleIsRunning` going false.
    /// It is *after* the release, not before: the drive is released and its volumes are coming back
    /// before the app is allowed to go.
    @Test func theRunIsSettledOnlyOnceTheDriveHasBeenReleased() {
        let bench = Bench()
        bench.startAndProceed()
        #expect(bench.settles == 0)

        bench.emit(.runEnded(result()))

        #expect(bench.settles == 1)
        #expect(bench.controller.state == .finished)

        // **The order is the property**, and it needs the settle in the step log to be expressible
        // at all. This assertion previously read `firstIndex(of: "release")! < steps.count`, which
        // is true whenever the index exists — so it checked nothing, and force-unwrapped a `nil`
        // into a SIGTRAP that took the whole runner down and destroyed the evidence of why the
        // expectation above it had failed. A test may fail; it may not crash the process.
        guard let released = bench.steps.firstIndex(of: "release"),
              let settled = bench.steps.firstIndex(of: "settled") else {
            Issue.record("expected both a release and a settle, got: \(bench.steps)")
            return
        }
        #expect(released < settled, "the drive goes back before the app is allowed to go")
    }

    /// An abort settles too. Without this a quit issued while the drive was being prepared would
    /// wait for a boundary that never arrives — the same hazard
    /// `quittingAfterTheRunHasAlreadyFinishedDoesNotWaitForever` pins on the other side.
    @Test func anAbortedStartAlsoSettles() {
        let bench = Bench()
        bench.preparationOutcome = .aborted(
            DevicePreparationFailure(reason: "refused", restore: nil))
        bench.startAndProceed()

        #expect(bench.settles == 1)
        #expect(bench.controller.state == .idle)
    }

    /// The drive is the one captured at the **press** — the same value the dialog named. Read later,
    /// or through the model, is what produced reports headed "Unidentified drive" on every first run
    /// after a launch.
    @Test func theReportNamesTheDriveCapturedAtThePress() {
        let bench = Bench()
        bench.startAndProceed()
        bench.emit(.runEnded(result()))

        let report = bench.reports.first ?? nil
        #expect(report?.device.usbSerialNumber == "00000S7CLNJ0WC02266P")
        #expect(report?.device.capacityBytes == 4_000_787_030_016)
    }

    /// FR-TEST-4: runs cover the whole device and always start at block 0, and the report states it
    /// rather than assuming it.
    @Test func theReportCoversTheWholeDeviceFromBlockZero() {
        let bench = Bench()
        bench.startAndProceed()
        bench.emit(.runEnded(result()))

        let report = bench.reports.first ?? nil
        #expect(report?.startBlock == 0)
        #expect(report?.blockCount == 7_814_037_168)
    }

    /// **FR-RPT-4, increment 8: the seam.** `RunReportOutcome.forRun` is unit-tested to death, and
    /// none of that is worth anything unless the controller actually hands it the run's own ending.
    ///
    /// It held that ending all along — `makeReport` takes the whole `RunSequenceResult` — and threw
    /// it away, rebuilding the outcome from the last reply instead. So this test is written against
    /// the reply that made that wrong: **the call came back `completed`**, because the user pressed
    /// Stop while it was already finishing and the sequencer then declined to issue the next one.
    /// Everything downstream is correct and the report still read "Completed — no
    /// currently-unreadable blocks were found" over `blockCount` of the whole 4 TB device.
    @Test func theReportsOutcomeComesFromTheRunAndNotFromItsLastReply() {
        let bench = Bench()
        bench.startAndProceed()
        bench.emit(.runEnded(result(.stoppedByUser, finalReply: reply(.completed))))

        let report = bench.reports.first ?? nil
        #expect(report?.outcome == .stoppedByUser)
        #expect(report?.outcome != .completedClean, "a stopped run reported as a clean pass")
    }

    /// The other half, so the test above cannot be satisfied by never saying "completed": a run
    /// that really did complete still reports as one, through the same seam.
    @Test func aRunThatCompletedStillReportsAsCompleted() {
        let bench = Bench()
        bench.startAndProceed()
        bench.emit(.runEnded(result(.completed, finalReply: reply(.completed))))

        #expect((bench.reports.first ?? nil)?.outcome == .completedClean)
    }

    /// **A refused call is not a run.** No reply ever came back, so there are no figures — which is
    /// a run that produced none, not a run whose figures are zero.
    @Test func aRunThatNeverGotAReplyProducesNoReport() {
        let bench = Bench()
        bench.startAndProceed()
        bench.emit(.runEnded(result(.callFailed(reason: "refused"),
                                               finalReply: nil)))

        #expect(bench.reports == [RunReport?.none], "reported, and reported as nothing")
        #expect(bench.controller.state == .finished)
        #expect(bench.releases == 1, "the claim still goes back")
    }

    /// The link speed comes from the claim's own profile, read once at the point it is already
    /// known rather than asked for again later.
    @Test func theLinkSpeedComesFromTheClaimsOwnProfile() {
        let bench = Bench()
        bench.startAndProceed()

        #expect(bench.controller.linkSpeedCode == 5)
    }
}

// MARK: - Device loss, route (b) (Step 12, chunk 4, FR-DEV-8)

/// **What a drive leaving the machine does to a run**, from the removal callback inwards.
///
/// `DeviceLossWindDownTests` pins the three-ways-in sequence in isolation and
/// `RunControlPolicyTests` pins the sixth event's rows. What is left here is the wiring those two
/// cannot see between them, and three of its properties are load-bearing:
///
///   * **A paused run ends.** Route (a) is structurally blind to it — a paused run issues no
///     syscalls, so no `errno` can arrive — and `runEnded` is *ignored* from `paused`. This is the
///     one path where nothing else in the app can end the run.
///   * **One unplug is one wind-down**, though it arrives as one callback per slice plus one for
///     the whole disk.
///   * **After the deadline the release is not waited for.** The deadline expiring *means* the
///     helper is still inside the blocking call, and a second message on that connection is not
///     delivered until it returns (measured 2026-08-04) — so waiting would be waiting for a message
///     that provably cannot arrive, with the device list frozen the whole time.
@MainActor
struct RunControllerDeviceLossTests {

    /// The fixture drive is `disk8`; these are the disks that leave when it is pulled.
    private static let wholeDisk = Bench.unplugged("disk8")
    private static let slice = Bench.unplugged("disk8s2", isWholeDisk: false)

    // MARK: The paused run — the case route (b) exists for

    /// **Nothing else in the app can end this run.** The claim is held, the volumes are unmounted,
    /// and no reply is coming — so without route (b) the app would sit paused indefinitely on a
    /// drive that is not attached.
    @Test func aDriveLeavingAPausedRunEndsItAndGivesTheClaimBack() {
        let bench = Bench()
        #expect(bench.driveTo(.paused))

        bench.controller.deviceDisappeared(Self.wholeDisk)

        #expect(bench.controller.state == .finished)
        #expect(bench.releases == 1)
        #expect(bench.reports.count == 1, "a run that wrote to the drive gets a report")
        #expect(bench.settles == 1)
    }

    /// And it ends **as a device loss**, not as the user stopping. Nobody pressed anything, and the
    /// report's outcome and FR-DEV-8's next steps both hang off the difference.
    @Test func aPausedRunLostToAnUnplugIsNotAUserStop() {
        let bench = Bench()
        #expect(bench.driveTo(.paused))

        bench.controller.deviceDisappeared(Self.wholeDisk)

        #expect(bench.sequencer?.deviceLosses == 1)
        #expect(bench.sequencer?.stops == 0, "nothing here is a stop")
    }

    /// **Nothing is waited for**, because nothing is coming: a paused run has returned from its
    /// call. Arming a three-second deadline here would be three seconds of the app still claiming
    /// to hold a drive that has gone.
    @Test func aPausedRunWaitsForNoReplyBecauseNoneIsComing() {
        let bench = Bench()
        #expect(bench.driveTo(.paused))

        bench.controller.deviceDisappeared(Self.wholeDisk)

        #expect(bench.windDownDeadlineSeconds == nil)
    }

    // MARK: Whose drive was it

    /// A drive that has nothing to do with this run leaves the machine all the time.
    @Test func anotherDriveLeavingChangesNothing() {
        let bench = Bench()
        #expect(bench.driveTo(.running))

        bench.controller.deviceDisappeared(Bench.unplugged("disk4"))

        #expect(bench.controller.state == .running)
        #expect(bench.windDowns == 0)
    }

    /// **The prefix trap.** `disk80` begins with `disk8` and is a different drive; the unit number
    /// is parsed rather than the string compared. `DeviceUnderTestTests` pins the predicate itself
    /// — this pins that the controller is asking it rather than doing its own matching.
    @Test func aDriveWhoseNameMerelyStartsWithOursIsNotOurs() {
        let bench = Bench()
        #expect(bench.driveTo(.running))

        bench.controller.deviceDisappeared(Bench.unplugged("disk80"))

        #expect(bench.controller.state == .running)
        #expect(bench.windDowns == 0)
    }

    /// A slice of the drive under test counts. The drive is unmounted and exclusively claimed, so
    /// nothing can be repartitioning it — a slice of it vanishing can only mean the drive vanished.
    @Test func aSliceOfTheDriveUnderTestCounts() {
        let bench = Bench()
        #expect(bench.driveTo(.paused))

        bench.controller.deviceDisappeared(Self.slice)

        #expect(bench.controller.state == .finished)
    }

    /// The fixture's APFS volume lives on a **synthesized** disk — `disk9s1`, on a `disk9` that is
    /// not part of `disk8`'s numbering. It does not match, and that is correct rather than a gap:
    /// the whole disk's own disappearance always fires too (measured 2026-09-05, fact 1), so the
    /// loss is seen by the event that names the drive rather than by one that names a container.
    @Test func aSynthesizedContainerIsNotTheDriveUnderTest() {
        let bench = Bench()
        #expect(bench.driveTo(.running))

        bench.controller.deviceDisappeared(Bench.unplugged("disk9"))

        #expect(bench.controller.state == .running)
        #expect(bench.windDowns == 0, "a wind-down armed here would end the run three seconds later")
    }

    // MARK: One unplug, several callbacks

    /// **Three callbacks, one wind-down, one run ending.** A two-partition drive produces a
    /// disappearance for the whole disk and one per slice (measured 2026-09-05).
    @Test func threeCallbacksFromOneUnplugEndOneRun() {
        let bench = Bench()
        #expect(bench.driveTo(.paused))

        bench.controller.deviceDisappeared(Self.wholeDisk)
        bench.controller.deviceDisappeared(Self.slice)
        bench.controller.deviceDisappeared(Bench.unplugged("disk8s4", isWholeDisk: false))

        #expect(bench.windDowns == 1)
        #expect(bench.sequencer?.deviceLosses == 1)
        #expect(bench.reports.count == 1)
        #expect(bench.releases == 1)
        #expect(bench.controller.state == .finished)
    }

    /// **The same unplug, seen by a run that is still going** — and the case the paused walk above
    /// cannot cover, because there the first callback ends the run and the state guard absorbs the
    /// rest. Here all three arrive within milliseconds of each other while nothing has changed yet,
    /// which is what a real drive being pulled mid-run looks like.
    ///
    /// A wind-down built per callback would arm three deadlines. Two of them would outlive the run
    /// with nothing holding them, firing three seconds later to accuse the helper of never
    /// answering a call it had already answered — and `standDown()` reaches only the one the
    /// controller still points at. A mutation building one per callback survived the whole suite
    /// until this existed.
    @Test func threeCallbacksFromOneUnplugArmOneDeadline() {
        let bench = Bench()
        #expect(bench.driveTo(.running))

        bench.controller.deviceDisappeared(Self.wholeDisk)
        bench.controller.deviceDisappeared(Self.slice)
        bench.controller.deviceDisappeared(Bench.unplugged("disk8s4", isWholeDisk: false))

        #expect(bench.windDowns == 1)
        #expect(bench.controller.state == .running, "still waiting for the reply")

        // And route (a) then disarms everything that was built, not merely the latest.
        bench.emit(.runEnded(result(.deviceLost, finalReply: reply(.deviceLost))))
        #expect(bench.everyWindDownIsFinished)
        #expect(bench.reports.count == 1)
    }

    // MARK: A call in flight — waiting for route (a)

    /// **The reply is worth waiting for**, and that is the whole reason the deadline exists rather
    /// than acting on the callback at once: route (a) carries the block and the phase, and route
    /// (b) cannot know either. On an ordinary unplug the reply is milliseconds behind.
    @Test func aRunningRunWaitsForTheHelpersReplyBeforeEndingItself() {
        let bench = Bench()
        #expect(bench.driveTo(.running))

        bench.controller.deviceDisappeared(Self.wholeDisk)

        #expect(bench.controller.state == .running, "the run has not ended yet")
        #expect(bench.windDownDeadlineSeconds == 3)
        #expect(bench.sequencer?.deviceLosses == 0)
    }

    /// Route (a) arrives during the wait: the sequencer ends the run by itself, carrying what it
    /// knows, and the wind-down must never end anything afterwards.
    @Test func theHelpersReplyEndsTheRunAndStandsTheWindDownDown() {
        let bench = Bench()
        #expect(bench.driveTo(.running))
        bench.controller.deviceDisappeared(Self.wholeDisk)

        bench.emit(.runEnded(result(.deviceLost, finalReply: reply(.deviceLost))))

        #expect(bench.controller.state == .finished)
        #expect(bench.reports.count == 1)
        #expect(bench.sequencer?.deviceLosses == 0, "route (a) ended it; route (b) must not again")

        // **The wind-down is disarmed**, and that is the assertion rather than a consequence of it.
        // A mutation deleting `standDown()` survived every behavioural check here, because the
        // sequencer refuses a second ending on its own and the controller drops its references at
        // the release — so nothing downstream moves. What a still-armed deadline produces is a log
        // line three seconds later saying the helper never answered, on the one path where someone
        // is reading the log to find out what happened to their drive.
        #expect(bench.everyWindDownIsFinished, "the deadline is still armed")

        // And it fires harmlessly, which is the ordinary ending: the timer outlives its subject.
        #expect(bench.expireWindDownDeadline(), "a deadline was armed")
        #expect(bench.reports.count == 1, "the run ended twice")
        #expect(bench.releases == 1)
    }

    /// The same disarming, with the release **held open** — so the controller still holds its
    /// sequencer and its wind-down when the deadline would fire. Without `standDown()` this is the
    /// window in which a late deadline reaches a live sequencer, and it is the one a slow release
    /// puts a real run in.
    @Test func theWindDownIsDisarmedBeforeTheDriveEvenGoesBack() {
        let bench = Bench()
        bench.holdRelease = true
        #expect(bench.driveTo(.running))
        bench.controller.deviceDisappeared(Self.wholeDisk)

        bench.emit(.runEnded(result(.deviceLost, finalReply: reply(.deviceLost))))

        #expect(bench.controller.state == .finishing, "the drive has not gone back yet")
        #expect(bench.everyWindDownIsFinished)

        #expect(bench.expireWindDownDeadline())
        #expect(bench.reports.count == 1)
        #expect(bench.sequencer?.deviceLosses == 0)
    }

    /// **Both routes report the same event**, so the machine's log says the same thing however the
    /// loss was found. Route (a) with no wind-down at all is the ordinary case — the drive is
    /// pulled, the helper's `ENXIO` beats DiskArbitration, and nothing ever calls
    /// `deviceDisappeared`.
    @Test func aDeviceLossFoundByTheHelperAloneEndsTheRunToo() {
        let bench = Bench()
        #expect(bench.driveTo(.running))

        bench.emit(.runEnded(result(.deviceLost, finalReply: reply(.deviceLost))))

        #expect(bench.controller.state == .finished)
        #expect(bench.windDowns == 0, "no removal callback ever arrived")
        #expect(bench.reports.count == 1)
    }

    // MARK: The deadline, which does not fail open

    /// **The case no amount of clicking can produce**: the drive is gone and the helper never
    /// answers the call it is inside. Failing open — leaving the run going because nothing
    /// confirmed the loss — would leave the app holding a claim on a drive DiskArbitration has
    /// already said is not there.
    @Test func aSilentHelperStillEndsTheRun() {
        let bench = Bench()
        #expect(bench.driveTo(.running))
        bench.controller.deviceDisappeared(Self.wholeDisk)

        #expect(bench.expireWindDownDeadline())

        #expect(bench.controller.state == .finished)
        #expect(bench.sequencer?.deviceLosses == 1)
        #expect(bench.reports.count == 1)
    }

    /// **And the release is not waited for.** The deadline expiring *means* the owning connection
    /// is still blocked by the call that went quiet, and a second message on it is not delivered
    /// until that call returns (measured 2026-08-04) — so the acknowledgement being waited for
    /// cannot arrive. Waiting would leave the app in `finishing` indefinitely, with the device list
    /// frozen and an uninstall blocked, over a drive that is not attached.
    @Test func theReleaseIsNotWaitedForAfterTheDeadline() {
        let bench = Bench()
        bench.holdRelease = true
        #expect(bench.driveTo(.running))
        bench.controller.deviceDisappeared(Self.wholeDisk)

        #expect(bench.expireWindDownDeadline())

        #expect(bench.releases == 1, "the release is still issued")
        #expect(bench.controller.state == .finished, "and not waited for")
        #expect(bench.settles == 1)
    }

    /// The release answering afterwards changes nothing. The machine moved on when the deadline
    /// expired; a second pass through the wind-up would report the run again.
    @Test func aLateReleaseAcknowledgementIsNotASecondEnding() {
        let bench = Bench()
        bench.holdRelease = true
        #expect(bench.driveTo(.running))
        bench.controller.deviceDisappeared(Self.wholeDisk)
        #expect(bench.expireWindDownDeadline())

        bench.finishRelease()

        #expect(bench.controller.state == .finished)
        #expect(bench.reports.count == 1)
        #expect(bench.settles == 1)
    }

    /// **The waiting is specific to the deadline**, and this is what says so: a device loss the
    /// helper *did* answer leaves the connection free, so the release is waited for exactly as it
    /// is on every other ending. Without this the two paths would be indistinguishable and the
    /// no-wait could quietly become the rule.
    @Test func aDeviceLossTheHelperAnsweredStillWaitsForTheRelease() {
        let bench = Bench()
        bench.holdRelease = true
        #expect(bench.driveTo(.running))

        bench.emit(.runEnded(result(.deviceLost, finalReply: reply(.deviceLost))))

        #expect(bench.controller.state == .finishing, "the drive has not been given back yet")

        bench.finishRelease()
        #expect(bench.controller.state == .finished)
    }

    /// And so does an ordinary run. The no-wait must not leak into the path every run takes.
    @Test func anOrdinaryRunStillWaitsForTheRelease() {
        let bench = Bench()
        bench.holdRelease = true
        #expect(bench.driveTo(.finishing))

        #expect(bench.controller.state == .finishing)
        bench.finishRelease()
        #expect(bench.controller.state == .finished)
    }

    // MARK: When there is nothing to lose

    /// No run, no drive under test, nothing to end.
    @Test func aDisappearanceWithNoRunDoesNothing() {
        let bench = Bench()

        bench.controller.deviceDisappeared(Self.wholeDisk)

        #expect(bench.controller.state == .idle)
        #expect(bench.windDowns == 0)
    }

    /// **During preparation the abort path owns it.** Nothing has been written, and `startAborted`
    /// promises the volumes are back before it fires — a promise this route cannot keep.
    @Test func aDisappearanceDuringPreparationIsLeftToTheAbort() {
        let bench = Bench()
        #expect(bench.driveTo(.starting))

        bench.controller.deviceDisappeared(Self.wholeDisk)

        #expect(bench.controller.state == .starting)
        #expect(bench.windDowns == 0)
    }

    /// **After the run, the drive under test is cleared with the claim.** The state guard would
    /// refuse a late disappearance anyway; clearing is what stops that being the only thing
    /// standing between a stale locator and a wrong answer — a BSD name is only an identity for as
    /// long as the enumeration that assigned it lasts.
    @Test func aDisappearanceAfterTheRunHasEndedDoesNothing() {
        let bench = Bench()
        #expect(bench.driveTo(.finished))

        bench.controller.deviceDisappeared(Self.wholeDisk)

        #expect(bench.controller.state == .finished)
        #expect(bench.windDowns == 0)
        #expect(bench.reports.count == 1, "no second report")
    }

    /// A drive pulled while the claim is going back does not re-decide a run whose outcome was
    /// already settled. This is also where the second and third callbacks of an unplug land when
    /// the first ended the run — see `threeCallbacksFromOneUnplugEndOneRun` for the other half.
    @Test func aDisappearanceWhileTheDriveIsBeingReleasedChangesNothing() {
        let bench = Bench()
        bench.holdRelease = true
        #expect(bench.driveTo(.finishing))

        bench.controller.deviceDisappeared(Self.wholeDisk)

        #expect(bench.controller.state == .finishing)
        #expect(bench.windDowns == 0)

        bench.finishRelease()
        #expect(bench.controller.state == .finished)
        #expect(bench.reports.count == 1)
    }

    // MARK: A lost run is over

    /// A drive that has gone cannot be resumed from, and FR-FAIL-7 forbids continuing across an
    /// interruption in any case. The controls say so because the state does.
    @Test func aRunLostToAnUnplugOffersNoResume() {
        let bench = Bench()
        #expect(bench.driveTo(.paused))

        bench.controller.deviceDisappeared(Self.wholeDisk)

        #expect(!bench.controller.isRunActive)
        #expect(!bench.controller.controls.pause.isEnabled)
        #expect(!bench.controller.controls.stop.isEnabled)
        #expect(bench.controller.controls.start.isEnabled, "a new run may be started")
    }
}
