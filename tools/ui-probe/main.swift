//
//  main.swift
//  ui-probe — render the app's SwiftUI view offscreen and capture it to a PNG.
//
//  Why this exists
//  ---------------
//  Most of this project's remaining work is GUI (device list in Step 5, metrics in
//  Step 9, run controls in Step 11, the mandatory warnings in Step 14). A macOS app
//  window cannot be screenshotted without an interactive session, so layout defects
//  were only discoverable by asking the user to look — which is slow, and catches only
//  what a person happens to notice.
//
//  This compiles the app's real view sources (not a copy of them) into an offscreen
//  NSHostingView and captures the result, so layout can be inspected directly. It was
//  written after a Step 4 report that a button was "not visible": the button turned
//  out to be present but rendered as a faint, low-contrast pill once disabled — which
//  a render made obvious and which reasoning about the code did not.
//
//  Scope: this is a LAYOUT probe, not a functional test. The view constructs its own
//  state here, so registration will typically read `.notFound` — this is not the
//  signed, installed app bundle and cannot talk to a real daemon.
//
//  Usage (via scripts/render-ui.sh):
//      ui-probe <output.png> [width] [height] [view]
//
//  `view` selects what to render — `content` (the whole window, the default) or a named
//  sub-view. Added in Step 5: once a view is behind a disclosure or a tab, rendering
//  only the composition root cannot show it, and "it compiled" is not evidence that a
//  Form nested inside a DisclosureGroup inside a VStack lays out at a sane height.
//  Steps 9, 11 and 14 add more such views.
//
//  ImageRenderer is deliberately NOT used: macOS's grouped Form style is AppKit-backed
//  and renders blank through it. A real hosting window is required.
//

import SwiftUI
import AppKit

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "ui-probe.png"
let width = CommandLine.arguments.count > 2 ? (Double(CommandLine.arguments[2]) ?? 600) : 600
let height = CommandLine.arguments.count > 3 ? (Double(CommandLine.arguments[3]) ?? 1000) : 1000
let viewName = CommandLine.arguments.count > 4 ? CommandLine.arguments[4] : "content"

/// `light` (the default) or `dark`. **Not** "whatever the machine is set to" — see the pinning
/// note below the scene switch, which is where the reason lives.
///
/// An unrecognised value is refused rather than defaulted, for the same reason `FailureModeCode`
/// refuses one: silently resolving an input nobody recognised to the default answers a question
/// that was not asked, and here it would answer it in a render somebody then reasons from.
let appearanceName = CommandLine.arguments.count > 5 ? CommandLine.arguments[5] : "light"

// An opt-in "activate the app and put the window on screen" mode was written here on 2026-08-05,
// on the theory that a parked `.accessory` window could never show emphasized selection. The
// diagnostic line added alongside it refuted that in one run — the default mode already reports
// `appActive=true windowKey=true` — so the mode was never needed and has been removed rather than
// left in as an untested path in a tool whose only value is being trustworthy. The diagnostic
// stayed; it is what settled the question.

/// Wraps a view needing a `Binding` so it can be rendered standalone.
///
/// Step 11 increment 5 took the bounded-cycle control, the run-state stand-in and the pre-run
/// dialog out of this panel, so the `deviceIsHeld` and `mayIssueNewWork` axes went with them —
/// there is no longer a control here whose enabled state they decide. What is left that is worth
/// rendering is the failure-mode picker (whose explanatory line changes with the selection), the
/// way back from a suppressed warning, and the run-active state, where uninstall is refused.
private struct DiagnosticsHost: View {

    /// `true` renders the uninstall refusal and the disabled mode picker — the state a user meets
    /// while a run is going, and one that is otherwise reachable only by starting a real run.
    var runIsActive = false

    /// Step 10's mode picker (FR-FAIL-1). Rendered in FR-FAIL-4's default position; the
    /// `diagnostics-stop-on-error` view is the same panel with the other one selected, because the
    /// explanatory line underneath changes with it and that line is the whole point of the
    /// control being a radio group rather than a checkbox.
    @State private var failureMode: FailureModeCode = .standard

    /// Applied on appear, because `@State` cannot be initialised from another stored property.
    var initialFailureMode: FailureModeCode = .standard

    /// Step 14's suppression flag. **Local `@State`, never the real store** — a render must not
    /// read or write the machine's actual preferences, and `diagnostics-warnings-suppressed`
    /// renders the restored-state control, which is otherwise reachable only by ticking a box in a
    /// sheet this probe cannot present.
    @State private var warningsSuppressed: Bool

    init(runIsActive: Bool = false,
         initialFailureMode: FailureModeCode = .standard,
         warningsSuppressed: Bool = false) {
        self.runIsActive = runIsActive
        self.initialFailureMode = initialFailureMode
        _warningsSuppressed = State(initialValue: warningsSuppressed)
    }

    var body: some View {
        HelperDiagnosticsView(helper: HelperConnection(),
                              runIsActive: runIsActive,
                              failureMode: $failureMode,
                              warningsSuppressed: $warningsSuppressed)
            .frame(minWidth: 560, minHeight: 480)
            .onAppear { failureMode = initialFailureMode }
    }
}

/// A run driven far enough to render, with no drive touched and no helper involved.
///
/// Every operation `RunController` performs is injected, so the probe reaches `running`, `paused`
/// and `starting` through the **same transitions the app takes** rather than by assigning a state.
/// That distinction is the same one `DeviceListHost` records: a render that poses as a state is
/// indistinguishable from a render of it, right up until the pose is wrong.
private enum ProbeRun {

    /// The 4 TB T5 EVO fixture — three mounted volumes, so the identity block above the run
    /// controls is as tall as it gets on this machine. That matters for the fold.
    static let device = DeviceFixture.evo

    static func model() -> AppModel {
        let model = AppModel(suppressionStore: InMemoryPreRunWarningSuppression(),
                             deviceSource: FixedDeviceSource(devices: [device]))
        model.discovery.start()
        model.runControl = RunController(
            preconditions: { RunPreconditions(hasUsableSelection: true,
                                              mayIssueNewWork: model.mayIssueNewWork) },
            selectedDevice: { model.discovery.selectedDevice },
            prepare: { _, done in
                done(.ready(PreparedDeviceGeometry(logicalBlockSize: 512,
                                                   deviceBlockCount: 7_814_037_168,
                                                   usbLinkSpeedCode: 4)))
            },
            makeSequencer: { emit in ProbeSequencer(emit: emit) },
            setRunControl: { _, done in done(.success(())) },
            release: { done in done() },
            ioSizeBytes: { TesterProtocol.defaultIOSizeBytes },
            failureMode: { .standard },
            onReport: { _ in })
        return model
    }

    /// Press Start and answer the dialog — the two steps the UI takes.
    static func start(_ model: AppModel) {
        _ = model.runControl?.startRequested(warningsSuppressed: false)
        model.runControl?.startAuthorised(
            by: PreRunOutcome(issuesRun: true, persistsSuppression: false))
    }

    /// …and on to `paused`, which needs the helper's settle and not merely the request.
    static func pause(_ model: AppModel) {
        model.runControl?.pause()
        ProbeSequencer.live?.emit(.pauseSettled(resumeBlock: 8_192))
    }

    /// The run came back, so the machine settles through `finishing` to `finished`.
    static func finish(_ model: AppModel) {
        ProbeSequencer.live?.emit(.runEnded(RunSequenceResult(outcome: .completed,
                                                              finalReply: nil,
                                                              ioSizesUsed: [],
                                                              startBlock: 0,
                                                              blockCount: 7_814_037_168)))
    }
}

/// A sequencer that issues nothing and reports nothing until the probe says so.
private final class ProbeSequencer: RunSequencing {
    static var live: ProbeSequencer?
    let emit: (RunSequencerEvent) -> Void
    init(emit: @escaping (RunSequencerEvent) -> Void) {
        self.emit = emit
        ProbeSequencer.live = self
    }
    func start(logicalBlockSize: UInt32, deviceBlockCount: UInt64,
               ioSizeBytes: Int, failureMode: FailureModeCode) -> Bool { true }
    func resume() -> Bool { true }
    func stop() -> Bool { true }
}

/// A device source that reports a fixed list, so a render does not depend on what is plugged in.
private final class FixedDeviceSource: DeviceSource {
    private let devices: [DiscoveredDevice]
    init(devices: [DiscoveredDevice]) { self.devices = devices }
    func enumerateDevices() -> [DiscoveredDevice] { devices }
    func startObserving(onChange: @escaping () -> Void) {}
    func stopObserving() {}
}

/// The fixture drive, as IOKit reports it.
private enum DeviceFixture {
    static let evo = DiscoveredDevice(
        registryEntryID: 0x8000,
        bsdName: BSDDeviceName("disk8"),
        vendorName: "Samsung",
        productName: "PSSD T5 EVO",
        mediumType: "Solid State",
        sizeBytes: 4_000_787_030_016,
        logicalBlockSize: 512,
        mountedVolumeNames: ["Vol_ExFAT", "Vol_APFS", "Vol_HFS"],
        mountedVolumeBSDNames: ["disk8s2", "disk9s1", "disk8s4"],
        usbSerialNumber: "00000S7CLNJ0WC02266P")
}

/// `ContentView` with the run controls in a given state.
///
/// Rendered per state because the controls, their disabled reasons and the status line all change
/// together — and because this is where the "is anything below the fold?" question is answered.
private struct RunStateHost: View {
    enum Stage { case idle, starting, running, paused, noSelection, quitPending }
    let stage: Stage
    @State private var model = AppModel()

    var body: some View {
        ContentView().environment(model)
            .onAppear { configure() }
    }

    private func configure() {
        let live = ProbeRun.model()
        live.terminateAction = {}
        switch stage {
        case .idle:
            break
        case .starting:
            // The preparation is held open, so the drive is being unmounted for as long as the
            // render lasts — the multi-second state a person would otherwise have to catch.
            live.runControl = heldPreparationController(live)
            ProbeRun.start(live)
        case .running:
            ProbeRun.start(live)
        case .paused:
            ProbeRun.start(live)
            ProbeRun.pause(live)
        case .noSelection:
            live.discovery.deselect()
        case .quitPending:
            // **With no run in progress**, deliberately. During a run FR-CTRL-9's refusal is the
            // more specific one and correctly wins, so the quit-pending sentence is never the one
            // shown — a render of that state is indistinguishable from `content-running`. What is
            // worth looking at is the state where the quit *is* the reason: the confirmation is up
            // (in its own window, which this probe cannot capture) and Start is refused because of
            // it. That refusal is the only thing on screen explaining why nothing can be started.
            ProbeRun.start(live)
            _ = live.quitRequested()
            ProbeRun.finish(live)
        }
        model = live
    }

    /// A controller whose preparation never answers, so the machine stays in `starting`.
    private func heldPreparationController(_ model: AppModel) -> RunController {
        RunController(
            preconditions: { RunPreconditions(hasUsableSelection: true, mayIssueNewWork: true) },
            selectedDevice: { model.discovery.selectedDevice },
            prepare: { _, _ in },
            makeSequencer: { emit in ProbeSequencer(emit: emit) },
            setRunControl: { _, done in done(.success(())) },
            release: { done in done() },
            ioSizeBytes: { TesterProtocol.defaultIOSizeBytes },
            failureMode: { .standard },
            onReport: { _ in })
    }
}

/// `ContentView` with the app winding down toward a quit (user decision 2026-08-05).
///
/// The banner it renders is otherwise unreachable by any means that leaves something to look at:
/// getting there in the real app means choosing "Cancel and Quit", and a second or so later the
/// app is gone. `AppModel.terminateAction` is injected here for exactly that reason — the probe
/// asks for the state without asking for the process to end.
///
/// What this render **cannot** show is the confirmation itself: a SwiftUI `alert` is presented in
/// its own window, and this probe captures the content view of one offscreen window. The dialog
/// stays a thing a person has to look at.
private struct QuittingContentHost: View {
    @State private var model = QuittingContentHost.windingDownModel()
    var body: some View {
        ContentView().environment(model)
    }

    /// Driven through the real sequence rather than assigned: start a run, ask, confirm, and leave
    /// the run still coming back so the model waits at exactly the point the banner describes.
    /// Reaching a state by the route the user takes is the difference between rendering the app and
    /// rendering a pose.
    private static func windingDownModel() -> AppModel {
        let model = ProbeRun.model()
        model.terminateAction = {}        // belt and braces: a render must never quit the probe
        ProbeRun.start(model)             // → running, with a call outstanding
        _ = model.quitRequested()         // → the confirmation
        model.cancelAndQuit()             // → winding down, waiting for the run to settle
        return model
    }
}

/// A device source that reports nothing, so the "no drives connected" state can be
/// rendered on a machine that has drives connected.
///
/// Added for Step 6. FR-SAFE-5 specifies the mount control's **no-selection** state —
/// disabled, labelled "Unmount All" — and that state is only reachable when no USB drive
/// is present at all, because the list's selection binding deliberately discards `nil`
/// (a blank-space click is a no-op, per Step 5). Verifying it on this machine would mean
/// unplugging every USB device, one of which holds the source tree. This renders it
/// instead.
private final class EmptyDeviceSource: DeviceSource {
    func enumerateDevices() -> [DiscoveredDevice] { [] }
    func startObserving(onChange: @escaping () -> Void) {}
    func stopObserving() {}
}

/// `DeviceListView` with an empty device list, started so the store settles into its
/// no-devices state.
private struct EmptyDeviceListHost: View {
    @State private var discovery = DeviceDiscovery(source: EmptyDeviceSource())
    var body: some View {
        DeviceListView(discovery: discovery, helper: HelperConnection())
            .onAppear { discovery.start() }
    }
}

/// `DeviceListView` over the **real** IOKit enumerator, started.
///
/// ## Why this host exists rather than a bare `DeviceListView(...)`
///
/// Found 2026-08-05: the `devices` case used to construct `DeviceDiscovery()` inline and
/// **never call `start()`** — and `DeviceListView` does not start the store itself, because in
/// the real app that is `ContentView`'s job. So the store stayed empty no matter what was
/// plugged in, and this view rendered the *no-devices* state forever: byte-for-byte the thing
/// `empty` exists to render, under a name promising the opposite.
///
/// Nothing failed. A render that shows "No USB drives connected" on a machine with three drives
/// attached looks exactly like a correct render of a machine with none — the same shape as the
/// probe printing "0.0 ms" for a reply that never arrived, and as a gate reporting a clean pass
/// over a region of zeros. Two named views must not be able to collapse into one.
///
/// ## The selected row's highlight, and a claim I made and measurement refuted
///
/// I first wrote here that this probe *cannot* decide the selection-highlight question — that as
/// an `.accessory` app with a parked offscreen window it would draw inactive grey chrome
/// regardless of focus. **That was reasoning, and it was wrong.** The probe now reports the three
/// facts directly, and in the default mode it prints `appActive=true windowKey=true`: both halves
/// of "emphasized" are already satisfied, so grey versus blue here turns purely on first
/// responder — which is exactly the thing under investigation.
///
/// It is left recorded because the wrong version was the more plausible one, and had it stood it
/// would have sent every check of this behaviour to a human for no reason.
///
/// ## What it still cannot decide
///
/// **Whether a focus fix that works here works in the app.** This probe hosts views in a raw
/// `NSWindow` + `NSHostingView`; there is no SwiftUI `Scene`. Modifiers whose contract is written
/// in terms of a scene or window appearing — `defaultFocus(_:_:)` most of all — have no scene to
/// attach to here, so a null result in the probe does not by itself convict them in the real app.
/// First responder is the common ground: if a mechanism moves it here, it is doing the AppKit
/// thing the appearance depends on.
private struct DeviceListHost: View {
    @State private var discovery = DeviceDiscovery()
    var body: some View {
        DeviceListView(discovery: discovery, helper: HelperConnection())
            .onAppear { discovery.start() }
    }
}

/// `RunMetricsView` driven from a **fixture**, not from a daemon.
///
/// Added for Step 9. The live panel polls a helper once a second, and there is no daemon to reach
/// from here — so rendering `LiveRunMetricsPanel` would only ever show the "no run has been
/// started" state. `RunMetricsView` is deliberately a pure function of a snapshot precisely so
/// this is possible: the figures below are the scratch device's real ones from Step 8's hardware gate, part
/// way through a run, so the layout is checked against numbers of the width it will really have.
private struct MetricsHost: View {
    var body: some View {
        RunMetricsView(
            snapshot: RunProgressSnapshot(
                available: true,
                fractionComplete: 0.4237,
                currentBlock: 1_953_525_168 / 2,
                // Measured figures, not invented ones: the 4 TB T5 EVO covers ~122.4 MB/s, and
                // because every byte is read twice and written once that is ~244.8 read and
                // ~122.4 write. Write sits a hair under covering, which is what this fixture's
                // own three failed chunks would really do.
                sustainedReadBytesPerSecond: 244_800_000,
                sustainedWriteBytesPerSecond: 122_398_000,
                coverageBytesPerSecond: 122_400_000,
                estimatedRemainingSeconds: 10_620,
                readLatencySampleCount: 101_004,
                readLatencyMinimumNanoseconds: 8_100_000,
                readLatencyMaximumNanoseconds: 214_600_000,
                readLatencyP99UpperBoundNanoseconds: 19_922_944,
                chunksFailed: 3),
            linkSpeedCode: 4,                       // 10 Gb/s, the scratch device's negotiated link
            isRunning: true,
            startedAt: Date(timeIntervalSince1970: 1_785_940_728),
            // A BSD name is a locator, and this one is deliberately not the drive's current
            // name: the serial beside it is the identity, and the panel shows both.
            deviceName: "disk8",
            deviceSerial: "12345686DAA9")   // the scratch device's real USB serial
            .padding()
    }
}

/// The same view with nothing measured yet — the state a user sees for the first second of a
/// run, and the one where a sentinel leaking through would print "-1.0 MB/s" or "0 MB/s".
private struct MetricsIdleHost: View {
    var body: some View {
        RunMetricsView(
            snapshot: RunProgressSnapshot(
                available: true,
                fractionComplete: 0,
                currentBlock: 0,
                sustainedReadBytesPerSecond: -1,    // the wire's "not measured yet"
                sustainedWriteBytesPerSecond: -1,
                coverageBytesPerSecond: -1,
                estimatedRemainingSeconds: -1,
                readLatencySampleCount: 0,
                readLatencyMinimumNanoseconds: 0,
                readLatencyMaximumNanoseconds: 0,
                readLatencyP99UpperBoundNanoseconds: 0,
                chunksFailed: 0),
            linkSpeedCode: -1,
            // Deliberately named here too: this render's job is to prove that nothing measured
            // prints as a digit, and the heading is one more place a value could leak into.
            isRunning: true,
            startedAt: Date(timeIntervalSince1970: 1_785_940_728),
            deviceName: "disk8",
            // Deliberately serial-less: this render is the one that must show the warning, and a
            // drive that reports no serial is a state no drive on this machine can produce.
            deviceSerial: nil)
            .padding()
    }
}

/// The panel **after** a run has finished — the state Step 10 changed.
///
/// `runProgress` keeps returning the finished run's figures until the next run replaces them, so
/// the snapshot here is fully populated and `isRunning` is `false`. Before 2026-08-06 that was
/// the "Last run" pane, showing a complete set of measurements indefinitely. It must now show the
/// placeholder instead, and that placeholder must say **where the result went** — a panel that
/// only said "nothing is under way" would read as the run's result having been lost.
///
/// This render exists because a populated snapshot plus `isRunning: false` is precisely the
/// combination the change turns on, and no other view exercises it.
private struct MetricsFinishedHost: View {
    var body: some View {
        RunMetricsView(
            snapshot: RunProgressSnapshot(
                available: true,               // the helper still holds the finished run's figures
                fractionComplete: 1,
                currentBlock: 2_097_152,
                sustainedReadBytesPerSecond: 244_800_000,
                sustainedWriteBytesPerSecond: 122_400_000,
                coverageBytesPerSecond: 122_400_000,
                estimatedRemainingSeconds: 0,
                readLatencySampleCount: 256,
                readLatencyMinimumNanoseconds: 1_100_000,
                readLatencyMaximumNanoseconds: 9_900_000,
                readLatencyP99UpperBoundNanoseconds: 2_195_000,
                chunksFailed: 0),
            linkSpeedCode: -1,
            isRunning: false,                  // …but no run is under way
            startedAt: Date(timeIntervalSince1970: 1_785_940_728),
            deviceName: "disk8",
            deviceSerial: "12345686DAA9")
            .padding()
    }
}

// MARK: - Step 10's run report

/// The report window's content, in each state worth looking at.
///
/// **This is why the report is a `Window` and not a sheet.** A sheet gets its own window and
/// `render-ui.sh` cannot capture it — the quit confirmation, added in Step 9, has needed a person
/// at the keyboard ever since for exactly that reason. Three of this project's defects were found
/// by looking at a render and none of them by an assertion, so a surface that cannot be rendered
/// gives up the check that has worked best.
///
/// The export button is wired to a no-op here: `NSSavePanel.runModal()` in a probe would hang
/// waiting for a click that is never coming.
private struct RunReportHost: View {

    let report: RunReport?

    var body: some View {
        RunReportView(report: report, exportAction: { _ in })
    }

    /// The scratch device, so the figures on screen are the ones a real run produces.
    static let device = ReportedDevice(modelDescription: "Samsung Portable SSD T5",
                                       usbSerialNumber: "12345686DAA9",
                                       bsdNameAtRunTime: "disk8",
                                       capacityBytes: 1_000_204_886_016,
                                       logicalBlockSize: 512)

    /// A drive that reported no usable serial — a state no drive on this machine can produce,
    /// and the one where the report has to admit it cannot identify what it tested.
    static let unidentifiedDevice = ReportedDevice(modelDescription: "Generic USB 3.0 Enclosure",
                                                  usbSerialNumber: nil,
                                                  bsdNameAtRunTime: "disk8",
                                                  capacityBytes: 500_107_862_016,
                                                  logicalBlockSize: 512)

    static func report(didComplete: Bool = true,
                       rangeCount: Int = 0,
                       encoded: String = "",
                       blocks: UInt64 = 0,
                       mode: Int = 2,
                       bypass: Int = 1,
                       device: ReportedDevice = RunReportHost.device) -> RunReport {
        // **v10 replaced `didComplete` with an outcome code** (Step 11 increment 2) — FR-CTRL-2/4
        // give a run four endings, so a boolean beside a separate "why" would be two statements of
        // one fact. `didComplete` survives as a derived property, which is why `RunReport` needed
        // no change; this call site did, and had not been touched since.
        let reply = RunCycleOutcome(runOutcomeCode: (didComplete ? RunOutcomeCode.completed
                                                                 : .stoppedOnFailure).rawValue,
                                    interruptedAtBlock: 0,
                                    chunksProcessed: didComplete ? 256 : 2,
                                    failedRangeCount: rangeCount,
                                    failureSummary: "",
                                    cacheBypassCode: bypass,
                                    bufferBytesHeld: 8 << 20,
                                    hostOverheadFraction: 0.0255,
                                    helperCoreFraction: 0.0422,
                                    failureModeUsedCode: mode,
                                    failedRangesEncoded: encoded,
                                    failedBlockCount: blocks,
                                    sustainedReadBytesPerSecond: 244_800_000,
                                    sustainedWriteBytesPerSecond: 122_400_000,
                                    coverageBytesPerSecond: 122_400_000,
                                    readLatencySampleCount: 256,
                                    readLatencyMinimumNanoseconds: 1_100_000,
                                    readLatencyMaximumNanoseconds: 9_900_000,
                                    readLatencyP99UpperBoundNanoseconds: 2_195_000,
                                    message: "")
        return RunReport(reply: reply,
                         startBlock: 0,
                         blockCount: 2_097_152,
                         ioSizesUsed: [4 << 20],
                         device: device,
                         startedAt: Date(timeIntervalSince1970: 1_785_940_728),
                         finishedAt: Date(timeIntervalSince1970: 1_785_940_735),
                         usbLinkSpeedDescription: "10 Gb/s (USB 3.1 Gen 2)")!
    }
}

/// A device source reporting one drive with **no mounted volumes**.
///
/// Added 2026-08-10, for the same reason `EmptyDeviceSource` exists: to render a state this machine
/// cannot produce. Every USB drive attached here has at least one mounted volume, so when the
/// standing backup advice stopped being conditional on `mountedVolumesDescription != nil` (user
/// decision, same date) there was **no way to see the change had taken effect** — and a behaviour
/// nobody can observe is one nobody has checked. Reintroducing the condition would have looked
/// identical from every render and every test.
private final class UnmountedDeviceSource: DeviceSource {
    func enumerateDevices() -> [DiscoveredDevice] {
        [DiscoveredDevice(registryEntryID: 4_294_967_296,
                          bsdName: BSDDeviceName("disk4"),
                          vendorName: "Seagate",
                          productName: "Expansion HDD",
                          mediumType: nil,
                          sizeBytes: 22_000_969_973_248,
                          logicalBlockSize: 512,
                          mountedVolumeNames: [],
                          mountedVolumeBSDNames: [],
                          usbSerialNumber: "00000000NT17XBRA")]
    }
    func startObserving(onChange: @escaping () -> Void) {}
    func stopObserving() {}
}

/// A device source reporting one usable drive and **one per geometry problem**.
///
/// Added 2026-08-11 by Step 14's accessibility audit, which could not otherwise look at the row a
/// user meets exactly when something is already wrong with their hardware. `isSelectable` is false
/// only when `geometryProblem != nil`, and no drive on this machine has one — so the unusable row's
/// distinct icon, its dimmed tint and its "Unusable" badge had **never been rendered in either
/// appearance**, and could not be. The same argument as `EmptyDeviceSource` and
/// `UnmountedDeviceSource`: a state this machine cannot produce is still a state that ships.
///
/// A usable drive is listed **first**, deliberately, for two reasons. FR-DEV-3 default-selects the
/// first usable device, so this keeps the selection where a real machine would put it rather than
/// rendering an edge case of the selection policy at the same time. And the audit's actual question
/// is comparative — *can these two rows be told apart with no colour at all* — which needs both
/// rows in one image.
///
/// All three causes are present because they take different paths through `geometryProblem` and
/// each produces its own description; one of them would leave the other two unrendered.
private final class UnusableDeviceSource: DeviceSource {
    func enumerateDevices() -> [DiscoveredDevice] {
        [
            // Usable, for contrast. The scratch device's real shape.
            DiscoveredDevice(registryEntryID: 4_294_967_301,
                             bsdName: BSDDeviceName("disk10"),
                             vendorName: "Samsung",
                             productName: "Portable SSD T5",
                             mediumType: "Solid State",
                             sizeBytes: 1_000_204_886_016,
                             logicalBlockSize: 512,
                             mountedVolumeNames: ["Test_Drive"],
                             mountedVolumeBSDNames: ["disk10s1"],
                             usbSerialNumber: "12345686DAA9"),
            // `.unsupportedBlockSize` — 520-byte sectors, which some enclosures still report.
            DiscoveredDevice(registryEntryID: 4_294_967_302,
                             bsdName: BSDDeviceName("disk11"),
                             vendorName: "Generic",
                             productName: "USB Bridge",
                             mediumType: "Rotational",
                             sizeBytes: 500_107_862_016,
                             logicalBlockSize: 520,
                             mountedVolumeNames: [],
                             mountedVolumeBSDNames: [],
                             usbSerialNumber: "FIXTURE-BLOCKSIZE"),
            // `.noCapacity` — a bridge that enumerates with no medium behind it.
            DiscoveredDevice(registryEntryID: 4_294_967_303,
                             bsdName: BSDDeviceName("disk12"),
                             vendorName: "Generic",
                             productName: "Card Reader",
                             mediumType: nil,
                             sizeBytes: 0,
                             logicalBlockSize: 512,
                             mountedVolumeNames: [],
                             mountedVolumeBSDNames: [],
                             usbSerialNumber: "FIXTURE-NOCAPACITY"),
            // `.sizeNotBlockAligned` — a capacity that is not a whole number of blocks.
            DiscoveredDevice(registryEntryID: 4_294_967_304,
                             bsdName: BSDDeviceName("disk13"),
                             vendorName: "Generic",
                             productName: "Flash Drive",
                             mediumType: "Solid State",
                             sizeBytes: 64_000_000_001,
                             logicalBlockSize: 512,
                             mountedVolumeNames: [],
                             mountedVolumeBSDNames: [],
                             usbSerialNumber: "FIXTURE-UNALIGNED"),
        ]
    }
    func startObserving(onChange: @escaping () -> Void) {}
    func stopObserving() {}
}

/// `DeviceListView` showing usable and unusable drives together (NFR-USE-8).
private struct UnusableDeviceListHost: View {
    @State private var discovery = DeviceDiscovery(source: UnusableDeviceSource())
    var body: some View {
        DeviceListView(discovery: discovery, helper: HelperConnection())
            .onAppear { discovery.start() }
    }
}

/// `DeviceListView` showing a drive with nothing mounted.
private struct UnmountedDeviceListHost: View {
    @State private var discovery = DeviceDiscovery(source: UnmountedDeviceSource())
    var body: some View {
        DeviceListView(discovery: discovery, helper: HelperConnection())
            .onAppear { discovery.start() }
    }
}

/// Step 14's pre-run dialog.
///
/// A sheet gets its own window, so `render-ui.sh` can never capture this one *in place* — which is
/// exactly why it is a standalone `View` and gets rendered here on its own. What a person still has
/// to confirm is that the sheet presents at all; everything about how it lays out is checkable from
/// these renders, and they were taken before anything could present it.
private struct PreRunPromptHost: View {

    let prompt: PreRunPrompt

    /// Real `@State`, not a constant binding — otherwise the checkbox renders permanently unticked
    /// and the ticked state could never be looked at.
    @State private var suppress: Bool

    init(prompt: PreRunPrompt, suppress: Bool = false) {
        self.prompt = prompt
        _suppress = State(initialValue: suppress)
    }

    var body: some View {
        PreRunPromptSheet(prompt: prompt,
                          suppressFutureWarnings: $suppress,
                          onProceed: {}, onCancel: {})
    }

    /// The drive FR-DEV-3 default-selects on this machine — 22 TB with a live Time Machine on it.
    /// The renders are of the drive this step exists to keep from being written to by accident.
    static let defaultSelectedDevice = ReportedDevice(
        modelDescription: "Seagate Expansion HDD",
        usbSerialNumber: "00000000NT17XBRA",
        bsdNameAtRunTime: "disk4",
        capacityBytes: 22_000_969_973_248,
        logicalBlockSize: 512)

    /// A drive that reported no usable serial: the confirmation is then the only identification the
    /// user gets, and it has to admit it cannot tell this drive from an identical one.
    static let unidentifiedDevice = ReportedDevice(
        modelDescription: "Generic USB 3.0 Enclosure",
        usbSerialNumber: nil,
        bsdNameAtRunTime: "disk4",
        capacityBytes: 500_107_862_016,
        logicalBlockSize: 512)
}

// Not `@MainActor`: top-level code in main.swift is nonisolated even under
// -default-isolation MainActor, so annotating this makes it uncallable from here.
func makeRootView(_ name: String) -> NSView {
    switch name {
    case "diagnostics":
        return NSHostingView(rootView: DiagnosticsHost())
    case "diagnostics-run-active":
        // Uninstall refused and the mode picker frozen. Replaces `diagnostics-held`, whose axis
        // went with the bounded-cycle control in increment 5.
        return NSHostingView(rootView: DiagnosticsHost(runIsActive: true))
    case "diagnostics-stop-on-error":
        // The same panel with FR-FAIL-2 selected. Worth its own render because the explanatory
        // line under the picker changes with the selection — it is what tells a user that everything past
        // the first failure is left **untested**, which is not the same as passed — and a control
        // whose only visible difference is which radio is filled would not need one.
        return NSHostingView(rootView: DiagnosticsHost(initialFailureMode: .stopOnFirstError))
    case "diagnostics-warnings-suppressed":
        // The "Show pre-run warnings again" control with something to restore. Reaching this state
        // through the UI means ticking a checkbox in a sheet, and a sheet cannot be rendered — so
        // without this case the enabled half of the control could never be looked at.
        return NSHostingView(rootView: DiagnosticsHost(warningsSuppressed: true))
    case "content-quitting":
        return NSHostingView(rootView: QuittingContentHost())
    case "metrics":
        return NSHostingView(rootView: MetricsHost())
    case "metrics-finished":
        return NSHostingView(rootView: MetricsFinishedHost())
    case "metrics-idle":
        return NSHostingView(rootView: MetricsIdleHost())
    case "empty":
        return NSHostingView(rootView: EmptyDeviceListHost())
    case "devices":
        // From Step 6 the device view talks to the helper for the readiness banner.
        // There is no daemon to reach from here, so the banner renders its "could not
        // ask the helper" state — which is itself worth seeing laid out, since it is
        // what a user with no helper installed gets.
        //
        // `DeviceListHost` rather than a bare `DeviceListView`, because the store has to be
        // started or this renders the no-devices state forever. See the note on the type.
        return NSHostingView(rootView: DeviceListHost())
    case "content":
        return NSHostingView(rootView: RunStateHost(stage: .idle))

    // Step 11 increment 5. The run controls in every state they can be in, because the controls,
    // their disabled reasons and the status line all change together — and because this is the
    // render that answers "is anything below the fold?" for the controls that replaced the ones
    // a user could not reach at the window's own minimum height.
    case "content-starting":
        return NSHostingView(rootView: RunStateHost(stage: .starting))
    case "content-running":
        return NSHostingView(rootView: RunStateHost(stage: .running))
    case "content-paused":
        return NSHostingView(rootView: RunStateHost(stage: .paused))
    case "content-no-selection":
        return NSHostingView(rootView: RunStateHost(stage: .noSelection))
    case "content-quit-pending":
        return NSHostingView(rootView: RunStateHost(stage: .quitPending))

    // Step 10. Every state the report window can be in.
    case "report":
        return NSHostingView(rootView: RunReportHost(report: RunReportHost.report()))
    case "report-failures":
        return NSHostingView(rootView: RunReportHost(
            report: RunReportHost.report(rangeCount: 2,
                                         encoded: "200:2:3;5000:4:1",
                                         blocks: 6)))
    case "report-stopped":
        return NSHostingView(rootView: RunReportHost(
            report: RunReportHost.report(didComplete: false, rangeCount: 1,
                                         encoded: "200:2:3", blocks: 2, mode: 1)))
    case "report-qualified":
        // FR-TEST-9's verdict is not `bypassed`. The one render that has to show the
        // qualification **in the headline** — where a reader skimming for the verdict meets it —
        // rather than only in the body below.
        return NSHostingView(rootView: RunReportHost(
            report: RunReportHost.report(bypass: 2)))
    case "report-unidentified":
        // A drive that reported no usable serial: the report must say its results cannot be told
        // apart from an identical model's.
        return NSHostingView(rootView: RunReportHost(
            report: RunReportHost.report(device: RunReportHost.unidentifiedDevice)))
    case "report-empty":
        // Reachable from the Window menu before any run has finished. "Empty" and "broken" look
        // identical unless one of them says which it is.
        return NSHostingView(rootView: RunReportHost(report: nil))

    case "devices-unmounted":
        // The standing backup advice must appear on a drive with **nothing mounted** — it stopped
        // being conditional on 2026-08-10 and no drive on this machine can show that.
        return NSHostingView(rootView: UnmountedDeviceListHost())
    case "devices-unusable":
        return NSHostingView(rootView: UnusableDeviceListHost())

    // Step 14. The pre-run dialog, in each of its forms.
    case "warnings":
        return NSHostingView(rootView: PreRunPromptHost(
            prompt: .fullWarnings(PreRunPromptHost.defaultSelectedDevice)))
    case "warnings-ticked":
        // The suppression checkbox in its ticked state, which is otherwise never rendered — and
        // which is the state that changes what the *next* run shows.
        return NSHostingView(rootView: PreRunPromptHost(
            prompt: .fullWarnings(PreRunPromptHost.defaultSelectedDevice), suppress: true))
    case "warnings-confirm":
        // What a user sees after suppressing. This render is the one that matters most: it is the
        // whole of what stands between a click and a write for anyone who ticked the box.
        return NSHostingView(rootView: PreRunPromptHost(
            prompt: .briefConfirmation(PreRunPromptHost.defaultSelectedDevice)))
    case "warnings-unidentified":
        return NSHostingView(rootView: PreRunPromptHost(
            prompt: .briefConfirmation(PreRunPromptHost.unidentifiedDevice)))

    default:
        FileHandle.standardError.write(Data("""
            ui-probe: unknown view '\(name)'; expected content, content-quitting, \
            content-starting, content-running, content-paused, content-no-selection, \
            content-quit-pending, devices, \
            diagnostics, diagnostics-run-active, diagnostics-stop-on-error, \
            empty, metrics, metrics-finished, metrics-idle, \
            report, report-empty, report-failures, report-qualified, report-stopped, \
            report-unidentified, devices-unmounted, diagnostics-warnings-suppressed, warnings, \
            warnings-ticked, warnings-confirm or \
            warnings-unidentified\n
            """.utf8))
        exit(2)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                      styleMask: [.titled], backing: .buffered, defer: false)

// **The appearance is pinned, and this is a bug fix, not a preference (2026-08-10).**
//
// Without it the window inherits whatever the machine is set to right now, and on 2026-08-10 that
// changed mid-session from light to dark — after which `content` and `devices` rendered as a device
// list and **nothing else**: no header, no selected-device pane, no metrics panel. The elements
// were laid out and drawing; they were simply invisible against the ground. Isolated rather than
// assumed: reverting the day's edits changed nothing and it reproduced identically at a clean
// `HEAD`, on the commit that had rendered correctly the same morning. Forcing an appearance
// restored the whole window.
//
// **That made the instrument report fewer elements than exist, silently, depending on ambient
// machine state** — which is this project's own "an empty result is not a finding", arriving in the
// one tool whose entire job is to be trustworthy about what is on screen. It cost a wrong
// conclusion before it was caught. Every historical render was taken in light appearance, so no
// prior finding is affected.
//
// Pinning also makes renders **comparable across sessions**, which matters for a tool used to
// compare before and after. Dark is reachable on purpose via the argument rather than by accident
// via the clock — NFR-USE-8 asks about contrast, so it is a surface worth being able to look at.
// Set on **both** the application and the window. Whether pinning both is strictly required was
// never isolated — the dark render stayed broken through this change for a reason that turned out
// to be elsewhere entirely (the missing bitmap background, below), so this pair was never the
// variable it was thought to be. Both are set because both should be: an instrument that leaves
// half its appearance to the ambient machine is the defect this whole block exists to remove.
switch appearanceName {
case "light":
    app.appearance = NSAppearance(named: .aqua)
    window.appearance = NSAppearance(named: .aqua)
case "dark":
    app.appearance = NSAppearance(named: .darkAqua)
    window.appearance = NSAppearance(named: .darkAqua)
default:
    FileHandle.standardError.write(Data("""
        ui-probe: unknown appearance '\(appearanceName)'; expected light or dark\n
        """.utf8))
    exit(2)
}

let rootView = makeRootView(viewName)

// **The capture needs an opaque background of its own, and that is the dark-mode bug.**
//
// `cacheDisplay(in:to:)` below renders the **content view's** drawing. It does not draw the
// window's background — that belongs to the window, which is not in the capture. So every region
// where SwiftUI draws no background lands in the PNG **transparent**.
//
// In light appearance that was invisible luck: the text is black, transparency composites pale in
// every viewer, and the render looked right. In dark appearance the text is white, so the header,
// the selected-device detail and the mount controls became white-on-nothing and **disappeared** —
// while the `List`, which draws its own opaque background, kept rendering. That is why the missing
// regions were exactly the ones with no background of their own, and why pinning
// `NSApp.appearance`, `window.appearance` and this view's `appearance` all changed nothing: the
// appearance was already correct. **Nothing was ever wrong with the colours. The background was
// missing from the bitmap.**
//
// Resolved inside the pinned appearance rather than read straight off: `windowBackgroundColor` is
// dynamic, and reading its `cgColor` outside a drawing context resolves it against whatever is
// current instead of what this render asked for — which is the same class of mistake as the
// ambient-appearance bug this is fixing.
rootView.wantsLayer = true
if let appearance = window.appearance {
    appearance.performAsCurrentDrawingAppearance {
        rootView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
}

window.contentView = rootView

// Ordered front so SwiftUI lays out and draws, but positioned far offscreen so it
// never appears in front of whatever the user is doing.
window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
window.makeKeyAndOrderFront(nil)

// Give SwiftUI a beat to lay out and draw before capturing.
DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
    guard let content = window.contentView,
          let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
        FileHandle.standardError.write(Data("ui-probe: capture failed\n".utf8))
        exit(1)
    }
    content.cacheDisplay(in: content.bounds, to: rep)

    guard let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("ui-probe: PNG encoding failed\n".utf8))
        exit(1)
    }

    // The three facts emphasized selection actually depends on, reported as facts rather than
    // inferred from a colour in the image. A grey highlight has at least three causes — inactive
    // app, non-key window, wrong first responder — and they are indistinguishable by eye while
    // being entirely distinguishable here.
    //
    // `firstResponder` is the one that matters for the focus question: SwiftUI's `@FocusState`
    // is not AppKit's first responder, and the whole point of asking is to find out whether
    // setting the former moved the latter onto the list's backing NSTableView.
    let responder = window.firstResponder.map { String(describing: type(of: $0)) } ?? "none"
    // `appearance` is on this line because it is the render's provenance, and a render whose
    // provenance is not recorded is exactly what went wrong on 2026-08-10: two PNGs of the same
    // view, taken hours apart, disagreed about how much of the window existed, and nothing in
    // either output said why. An instrument's report has to carry the conditions it was taken
    // under, or comparing two of them compares more than the thing being measured.
    print("""
          ui-probe: appActive=\(app.isActive) windowKey=\(window.isKeyWindow) \
          firstResponder=\(responder) appearance=\(appearanceName)
          """)

    do {
        try png.write(to: URL(fileURLWithPath: outputPath))
        print("ui-probe: wrote \(outputPath) — \(Int(width))x\(Int(height)) pt")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("ui-probe: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

app.run()
