//
//  AppModelReportTests.swift
//  What a finished run does to the report, and who may raise it (Step 11 increment 8).
//
//  ## Why these decisions moved into `AppModel` to be tested at all
//
//  They used to live in two closures inside `RunControllerWiring.live` — the file that needs a
//  privileged helper and a drive to construct — so **nothing in the suite could reach them**. What
//  was decided there is not incidental: that a refused call raises nothing, and that a beginning
//  run discards the previous run's report. Both are now one call each from the wiring into methods
//  on the model, which is what makes this file possible.
//
//  ## The trap this file exists to pin
//
//  The report became a **sheet on the main window** in increment 8, and the menu item that raises
//  it is disabled during a run (user decisions 2026-08-19 and 2026-08-21). It would be natural to
//  answer *"may the report be raised?"* once and use that answer everywhere.
//
//  **It would suppress every report this app produces.** The report a finished run makes is raised
//  from `finishing` — a state that is still run-active, because the drive has not been released
//  yet. So at the exact instant the report appears, the menu rule says no. `theReportAppearsFrom`
//  `AStateTheMenuItemIsDisabledIn` is that assertion, and it is the same shape as the ⌘Q defect
//  chunk 6 found: one flag answering two questions.
//
//  Nothing here touches XPC or a drive. The run is stubbed end to end, in the same way
//  `AppModelQuitTests` stubs it — a real `RunController` driven through the two steps the UI takes,
//  so the states these properties are read in are states the machine actually reached.
//

import Testing
import Foundation
// `MemberImportVisibility`: `NSApplication` is AppKit's and a transitive import is not enough.
import AppKit
@testable import USBDriveTester

@MainActor
struct AppModelReportTests {

    // MARK: - Fixtures

    private enum Fixture {

        static let device = ReportedDevice(modelDescription: "Samsung Portable SSD T5",
                                           usbSerialNumber: "12345686DAA9",
                                           bsdNameAtRunTime: "disk8",
                                           capacityBytes: 1_000_204_886_016,
                                           logicalBlockSize: 512)

        /// A finished 1 GiB run with nothing wrong. Only the fields these tests read are
        /// interesting; the rest are a plausible run so the report builds.
        static func report() -> RunReport {
            let reply = RunCycleOutcome(runOutcomeCode: RunOutcomeCode.completed.rawValue,
                                        interruptedAtBlock: 0,
                                        chunksProcessed: 256,
                                        failedRangeCount: 0,
                                        failureSummary: "",
                                        cacheBypassCode: 1,
                                        bufferBytesHeld: 8 << 20,
                                        hostOverheadFraction: 0.0255,
                                        helperCoreFraction: 0.0422,
                                        failureModeUsedCode: 2,
                                        failedRangesEncoded: "",
                                        failedBlockCount: 0,
                                        deviceReadBytesPerSecond: 517_000_000,
                                        writeBytesPerSecond: 491_000_000,
                                        coverageBytesPerSecond: 245_000_000,
                                        completedBytesPerSecond: 238_000_000,
                                        readLatencySampleCount: 256,
                                        readLatencyMinimumNanoseconds: 1_100_000,
                                        readLatencyMaximumNanoseconds: 9_900_000,
                                        readLatencyP99UpperBoundNanoseconds: 2_195_000,
                                        message: "Cycle completed",
                                        deviceLossPhaseCode: DeviceLossPhaseCode.unrecognised.rawValue)
            // Force-unwrapped deliberately: `init?` returns nil only for a mode that is not
            // runnable, and a fixture that silently became nil would make every test below vacuous.
            return RunReport(reply: reply,
                             endedBy: .completed,
                             startBlock: 0,
                             blockCount: 2_097_152,
                             ioSizesUsed: [4 << 20],
                             device: device,
                             startedAt: Date(timeIntervalSince1970: 1_785_000_000),
                             finishedAt: Date(timeIntervalSince1970: 1_785_000_007))!
        }
    }

    // MARK: - The bench

    /// A sequencer that reports back only when the test says so.
    ///
    /// `@MainActor` explicitly: a nested type does **not** inherit its enclosing suite's isolation.
    @MainActor
    private final class StubSequencer: RunSequencing {
        let emit: (RunSequencerEvent) -> Void

        init(emit: @escaping (RunSequencerEvent) -> Void) { self.emit = emit }

        func start(logicalBlockSize: UInt32, deviceBlockCount: UInt64,
                   ioSizeBytes: Int, failureMode: FailureModeCode) -> Bool { true }

        func resume() -> Bool { true }
        func stop() -> Bool { true }
    }

    /// Records the order in which injected closures ran. A class rather than a captured array so
    /// the closures can append without the escaping-capture dance, and so the assertion reads as a
    /// sequence — which is what the quit fix is.
    @MainActor
    private final class Recorder {
        private(set) var steps: [String] = []
        func append(_ step: String) { steps.append(step) }
    }

    /// A model whose run is stubbed end to end, wired the way `RunControllerWiring` wires the real
    /// one: `onReport` and `onRunBegan` are **one call each** into the model.
    ///
    /// The wiring's own two lines are not under test — that file needs a helper and a drive — so
    /// this bench mirrors them. What it therefore cannot catch is somebody unwiring `live`; that is
    /// recorded in the checklist's no-cover list, with chunk 11 as the check.
    @MainActor
    private final class Bench {
        let model: AppModel
        private(set) var sequencer: StubSequencer?

        /// What the menu rule said at the instant the report was produced. `nil` until a run ends.
        private(set) var mayRaiseWhenTheReportArrived: Bool?

        init(reportFromTheRun: RunReport? = Fixture.report()) {
            model = AppModel(suppressionStore: InMemoryPreRunWarningSuppression(),
                             deviceSource: StubDeviceSource(devices: [DeviceFixtures.testDrive]))
            model.terminateAction = {}
            model.discovery.start()

            model.runControl = RunController(
                preconditions: { [model] in
                    RunPreconditions(hasUsableSelection: true,
                                     mayIssueNewWork: model.mayIssueNewWork)
                },
                selectedDevice: { [model] in model.discovery.selectedDevice },
                prepare: { _, done in
                    done(.ready(PreparedDeviceGeometry(logicalBlockSize: 512,
                                                       deviceBlockCount: 1_024,
                                                       usbLinkSpeedCode: -1)))
                },
                makeSequencer: { [weak self] emit in
                    let stub = StubSequencer(emit: emit)
                    self?.sequencer = stub
                    return stub
                },
                setRunControl: { _, done in done(.success(())) },
                release: { done in done() },
                ioSizeBytes: { 1 << 22 },
                failureMode: { .logAndContinue },
                // The controller's own report is discarded: what these tests need is a report of a
                // known shape, produced at the moment the real one would be. Read the rule
                // **before** handing it over, since that is the instant in question.
                onReport: { [weak self] _ in
                    guard let self else { return }
                    mayRaiseWhenTheReportArrived = model.reportMayBeRaisedFromMenu
                    model.runProduced(reportFromTheRun)
                },
                onRunBegan: { [model] in model.runBegan() },
                onRunSettled: { [model] in model.runSettled() })
        }

        /// Drive a run to `running`, through the same two steps the UI takes.
        func startARun() {
            _ = model.runControl?.startRequested(warningsSuppressed: false)
            model.runControl?.startAuthorised(
                by: PreRunOutcome(issuesRun: true, persistsSuppression: false))
        }

        /// The run came back.
        func endTheRun() {
            sequencer?.emit(.runEnded(RunSequenceResult(outcome: .completed,
                                                        finalReply: nil,
                                                        ioSizesUsed: [],
                                                        startBlock: 0,
                                                        blockCount: 1_024)))
        }
    }

    // MARK: - What a finished run does to the report

    @Test func aFinishedRunReplacesTheReportAndPutsItOnScreen() {
        let bench = Bench()
        #expect(bench.model.lastRunReport == nil, "nothing has run yet")
        #expect(!bench.model.reportIsPresented)

        bench.model.runProduced(Fixture.report())

        #expect(bench.model.lastRunReport != nil)
        #expect(bench.model.reportIsPresented)
    }

    /// **A refused call is not a run.** It gets no report, and — the part worth pinning — it raises
    /// nothing: a sheet reading "No run has finished yet" immediately after pressing Start would be
    /// worse than no sheet at all.
    ///
    /// This decision was made in Step 10 and lived in a closure nothing could call until now.
    @Test func aRefusedCallProducesNoReportAndRaisesNothing() {
        let bench = Bench()

        bench.model.runProduced(nil)

        #expect(bench.model.lastRunReport == nil)
        #expect(!bench.model.reportIsPresented, "the empty state must not be raised by a refusal")
    }

    /// A refusal *after* a run also clears the report it replaced. The report on screen must be the
    /// most recent attempt's, and "the last one that worked" is a history — which FR-RPT forbids.
    @Test func aRefusedCallDoesNotLeaveThePreviousRunsReportBehind() {
        let bench = Bench()
        bench.model.runProduced(Fixture.report())

        bench.model.runProduced(nil)

        #expect(bench.model.lastRunReport == nil)
    }

    @Test func aBeginningRunDiscardsThePreviousRunsReport() {
        let bench = Bench()
        bench.model.runProduced(Fixture.report())

        bench.model.runBegan()

        #expect(bench.model.lastRunReport == nil, "the previous run's report is not this run's")
    }

    /// Dismissing the sheet does not throw the report away, which is what makes ⇧⌘R able to bring
    /// the same report back. Only a new run discards it.
    @Test func dismissingTheReportKeepsIt() {
        let bench = Bench()
        bench.model.runProduced(Fixture.report())

        bench.model.reportIsPresented = false

        #expect(bench.model.lastRunReport != nil)
        #expect(bench.model.reportMayBeRaisedFromMenu, "…and it can be raised again")
    }

    // MARK: - Who may raise it

    @Test func theMenuMayRaiseTheReportWhenNothingIsRunning() {
        let bench = Bench()
        #expect(bench.model.reportMayBeRaisedFromMenu)
    }

    @Test func theMenuMayNotRaiseTheReportDuringARun() {
        let bench = Bench()
        bench.startARun()

        #expect(bench.model.runIsActive)
        #expect(!bench.model.reportMayBeRaisedFromMenu)
    }

    @Test func theMenuMayRaiseTheReportAgainOnceTheRunHasEnded() {
        let bench = Bench()
        bench.startARun()
        bench.endTheRun()

        #expect(!bench.model.runIsActive)
        #expect(bench.model.reportMayBeRaisedFromMenu)
    }

    // MARK: - The dialog, found at the keyboard on 2026-08-21

    /// **A window-modal sheet does not swallow menu commands.** Chunk 11.11 pressed ⇧⌘R with the
    /// pre-run dialog open: the command ran, SwiftUI queued a second sheet because one window
    /// cannot show two, and the report appeared **by itself** the moment the dialog was cancelled.
    ///
    /// The fact that a dialog is up therefore had to leave `RunControlsView`'s `@State` and become
    /// the model's, since the menu item lives in a `commands` builder with no environment to read.
    @Test func theMenuMayNotRaiseTheReportWhileAPreRunDialogIsUp() {
        let bench = Bench()
        bench.model.pendingPrompt = PreRunPrompt.forRun(warningsSuppressed: false,
                                                        device: Fixture.device)

        #expect(!bench.model.reportMayBeRaisedFromMenu)
    }

    /// **And while the launch-time helper gate is up** (increment 9).
    ///
    /// The same defect in a new place rather than a new one. At launch `runIsActive` is false and
    /// `pendingPrompt` is nil, so ⇧⌘R is **enabled** — and the gate no more swallows menu commands
    /// than the pre-run dialog does. Without this clause the empty report queues behind the gate and
    /// presents itself the instant the gate is answered.
    ///
    /// Owed whether the gate is a sheet or an alert: both are window-modal, and what 11.11
    /// established is about menu commands, not about which kind of modal is up.
    @Test func theMenuMayNotRaiseTheReportWhileTheHelperGateIsUp() {
        let bench = Bench()
        #expect(bench.model.reportMayBeRaisedFromMenu, "…before the gate")

        bench.model.setHelperAvailability(.notRegistered)

        #expect(!bench.model.reportMayBeRaisedFromMenu)
    }

    /// And it comes back once the helper is usable — the check answering **both ways**, which is
    /// what separates "the gate refuses it" from "something refuses it".
    @Test func theMenuMayRaiseTheReportOnceTheHelperIsAvailable() {
        let bench = Bench()
        bench.model.setHelperAvailability(.requiresApproval)
        #expect(!bench.model.reportMayBeRaisedFromMenu)

        bench.model.setHelperAvailability(.available)

        #expect(bench.model.reportMayBeRaisedFromMenu)
    }

    /// **The gate's Quit ends the sheet BEFORE it terminates, and the order is the fix.**
    ///
    /// `NSApp.terminate(_:)` is a silent no-op while a sheet is attached — AppKit refuses it before
    /// `applicationShouldTerminate` is consulted — so the button was dead when it was pressed at the
    /// keyboard on 2026-08-27. Asserting only that both closures ran would pass with the two lines
    /// swapped, which is exactly the defect; so this asserts the sequence.
    @Test func quittingFromTheGateEndsTheSheetBeforeTerminating() {
        let bench = Bench()
        let order = Recorder()
        bench.model.scheduleOnNextTurn = { $0() }
        bench.model.dismissAttachedSheets = { order.append("sheet") }
        bench.model.terminateAction = { order.append("terminate") }
        bench.model.setHelperAvailability(.requiresApproval)

        bench.model.performHelperGateAction(.quit)

        #expect(order.steps == ["sheet", "terminate"])
    }

    /// **The sheet must be gone from SwiftUI's point of view before the app tries to go.**
    ///
    /// This is the assertion the first two fixes would have failed. Both ended the *AppKit* sheet
    /// and left `helperGateIsPresented` true, so SwiftUI kept the sheet attached and
    /// `NSApp.terminate(_:)` was refused before `applicationShouldTerminate` was ever consulted —
    /// measured in the shipped app, twice. The availability is deliberately left untouched: the app
    /// is quitting, not becoming healthy, and saying otherwise would be a lie on the way out.
    @Test func quittingFromTheGateTakesTheSheetDownThroughSwiftUI() {
        let bench = Bench()
        bench.model.scheduleOnNextTurn = { $0() }
        bench.model.terminateAction = {}
        bench.model.setHelperAvailability(.requiresApproval)
        #expect(bench.model.helperGateIsPresented)

        bench.model.performHelperGateAction(.quit)

        #expect(!bench.model.helperGateIsPresented)
        #expect(bench.model.helperAvailability == .requiresApproval)
    }

    /// **A remedy marks itself in flight, and the arriving diagnosis clears it.**
    ///
    /// The clear happens in `setHelperAvailability(_:)` — the single writer — rather than at each
    /// remedy's call site, so a remedy that forgets cannot leave the gate stuck busy. `retry` is
    /// used because it is the one remedy a test may drive without touching machine state.
    @Test func aRemedyIsInFlightUntilTheDiagnosisArrives() {
        let bench = Bench()
        bench.model.setHelperAvailability(.requiresApproval)
        #expect(bench.model.helperGateActionInFlight == nil)

        bench.model.performHelperGateAction(.retry)
        // `retry` re-diagnoses, and on this machine the answer arrives before the call returns, so
        // what is asserted is the *end* state: whatever happened, nothing is left in flight.
        bench.model.setHelperAvailability(.requiresApproval)

        #expect(bench.model.helperGateActionInFlight == nil)
    }

    /// **Quit never marks itself in flight.** It is not a remedy, and a Quit that set the busy state
    /// would disable the only control left — the one the user just pressed to leave.
    @Test func quitDoesNotMarkTheGateBusy() {
        let bench = Bench()
        bench.model.scheduleOnNextTurn = { $0() }
        bench.model.terminateAction = {}
        bench.model.setHelperAvailability(.notRegistered)

        bench.model.performHelperGateAction(.quit)

        #expect(bench.model.helperGateActionInFlight == nil)
    }

    /// And a remedy leaves the gate up. Only the quit takes it down; a remedy that dropped the sheet
    /// would leave the app ungated with the helper still unusable.
    @Test func aRemedyLeavesTheGatePresented() {
        let bench = Bench()
        bench.model.setHelperAvailability(.requiresApproval)

        bench.model.performHelperGateAction(.retry)

        #expect(bench.model.helperGateIsPresented)
    }

    /// And a remedy does not tear the gate down. Each one re-diagnoses and the modal follows the
    /// state; a remedy that also ended the sheet would flash the main window between steps, and on
    /// a state that does not clear it would leave the app ungated with the helper still unusable.
    ///
    /// **Only `retry` is driven here, and the reason is a defect this test had when first written.**
    /// The first version walked `[.registerHelper, .openLoginItems, .retry]`, went green, and had
    /// **really registered the daemon and really opened System Settings** — visible on the log as
    /// `register() succeeded` and `opening System Settings > Login Items & Extensions`. A unit test
    /// that changes machine state is not a unit test, and that one would have done it on every run
    /// of `test.sh` from then on. `HelperRegistration` is constructed inside `AppModel` rather than
    /// injected, so those two cases cannot be driven without the real side effect; `retry` reaches
    /// the same line under test and only *reads*. The two undriveable cases are in the checklist's
    /// no-cover list.
    @Test func aRemedyDoesNotEndTheSheet() {
        let bench = Bench()
        let order = Recorder()
        bench.model.dismissAttachedSheets = { order.append("sheet") }
        bench.model.setHelperAvailability(.requiresApproval)

        bench.model.performHelperGateAction(.retry)

        #expect(order.steps.isEmpty, "steps=\(order.steps)")
    }

    /// Every non-available state closes the menu item, not just the one a test happened to pick.
    /// A rule written against a single case is a rule that a later case can walk past.
    @Test func noGatedStateLetsTheReportBeRaised() {
        for availability: HelperAvailability in [.notFound, .notRegistered, .requiresApproval,
                                                 .unreachable(detail: "no reply"),
                                                 .versionMismatch(helper: 11, app: 12)] {
            let bench = Bench()
            bench.model.setHelperAvailability(availability)
            #expect(!bench.model.reportMayBeRaisedFromMenu, "case=\(availability.routeName)")
        }
    }

    /// And the raise itself refuses, not only the menu item's appearance. The rule is enforced in
    /// the model because a rule living in a `.disabled` modifier is one **no test can see** —
    /// mutation R12 deleted exactly that and passed the whole suite.
    @Test func aQueuedRaiseIsRefusedRatherThanDeferred() {
        let bench = Bench()
        bench.model.pendingPrompt = PreRunPrompt.forRun(warningsSuppressed: false,
                                                        device: Fixture.device)

        bench.model.reportRequestedFromMenu()

        #expect(!bench.model.reportIsPresented,
                "a refused raise must not arrive later, which is the defect itself")
    }

    /// …and answering the dialog gives it back, so the refusal is a gate rather than a latch.
    @Test func theMenuMayRaiseTheReportOnceTheDialogIsAnswered() {
        let bench = Bench()
        bench.model.pendingPrompt = PreRunPrompt.forRun(warningsSuppressed: false,
                                                        device: Fixture.device)

        bench.model.pendingPrompt = nil
        bench.model.reportRequestedFromMenu()

        #expect(bench.model.reportIsPresented)
    }

    @Test func theMenuRaiseAlsoRefusesDuringARun() {
        let bench = Bench()
        bench.startARun()

        bench.model.reportRequestedFromMenu()

        #expect(!bench.model.reportIsPresented)
    }

    @Test func theMenuRaiseWorksWhenNothingIsInTheWay() {
        let bench = Bench()

        bench.model.reportRequestedFromMenu()

        #expect(bench.model.reportIsPresented)
    }

    /// **The trap.** The report is produced from `finishing`, where the drive has not been released
    /// and the run is still active — so the menu rule says *no* at the exact instant the report
    /// must appear.
    ///
    /// Answering both questions with one property would therefore suppress every report the app
    /// produces, and it would look like a run that finished and said nothing. This asserts the two
    /// disagree in the one state where they must, which is the same check
    /// `askingWhetherToQuitDoesNotItselfEndTheRun` makes for ⌘Q.
    @Test func theReportAppearsFromAStateTheMenuItemIsDisabledIn() {
        let bench = Bench()
        bench.startARun()

        bench.endTheRun()

        #expect(bench.mayRaiseWhenTheReportArrived == false,
                "the report is produced while the run is still active")
        #expect(bench.model.reportIsPresented, "…and it is raised anyway")
        #expect(bench.model.lastRunReport != nil)
    }

    /// The other half: a run that produces **no** report raises nothing, all the way through the
    /// real controller rather than by calling the model directly.
    @Test func aRunThatProducesNoReportRaisesNothing() {
        let bench = Bench(reportFromTheRun: nil)
        bench.startARun()

        bench.endTheRun()

        #expect(!bench.model.reportIsPresented)
        #expect(bench.model.lastRunReport == nil)
    }

    /// Starting a run through the machine clears the report the previous one left, which is the
    /// wiring `onRunBegan` exists for. Driven end to end because the closure is what is under test,
    /// not the method it calls.
    @Test func startingARunClearsTheReportOnTheWayIn() {
        let bench = Bench()
        bench.model.runProduced(Fixture.report())

        bench.startARun()

        #expect(bench.model.lastRunReport == nil)
    }
}
