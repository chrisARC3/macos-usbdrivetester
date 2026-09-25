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
//      ui-probe <output.png> [width] [height] [view] [light|dark] [drives]
//      ui-probe --limits [view] [width] [drives]
//
//  `view` selects what to render — `content` (the whole window, the default) or a named
//  sub-view. Added in Step 5: once a view is behind a disclosure or a tab, rendering
//  only the composition root cannot show it, and "it compiled" is not evidence that a
//  Form nested inside a DisclosureGroup inside a VStack lays out at a sane height.
//  Steps 9, 11 and 14 add more such views.
//
//  `drives` is how many drives the fixture presents (default 1), added in Step 11
//  increment 7. It is not decoration: `DeviceListView.listHeight` grows with the count
//  to a 260 pt cap, and it moved the whole window's minimum height by **168 pt** between
//  one drive and six. Until this axis existed, no render had ever shown this app with
//  more than one drive attached — so the capped list, which is what a person with a hub
//  full of drives sees, had never been looked at once.
//
//  ## `--limits` — what the window can actually be resized to
//
//  A render answers "does this look right at this size". It cannot answer "what sizes is
//  this window willing to be", and that is the question behind whether the app fits a
//  13.3-inch Mac. `--limits` asks the real view hierarchy instead: it sets
//  `NSHostingView.sizingOptions` so the view propagates its SwiftUI minimum and maximum
//  up to the window, exactly as a `Window` scene does, and prints them.
//
//  It answers three things a render cannot:
//
//    * the **enforced minimum** — how small a user can drag the window, which is what has
//      to fit inside `NSScreen.visibleFrame` on the smallest supported Mac;
//    * the **maximum**, which is `inf` here and is why the window opened at screen height
//      for as long as the scene declared no `.defaultSize`. It is also what `render-ui.sh`
//      is describing when it says the height argument behaves as "a floor, not a ceiling";
//    * the **intrinsic** size, which is what a scene with no declared size opens at.
//
//  **And it says when it could not answer** (2026-09-19). The enforced minimum is *measured*, not
//  declared, because the declaration is short — `content-starting` declares 524 pt and needs 570
//  with one drive and 581 with six, measured on macOS 27 — and that
//  measurement has now failed once: on macOS 27 both of its mechanisms broke at the same time and
//  it returned 1 pt for every state, which the gate printed as *"every state fits"* for nineteen
//  days. It now prints `min=<w>xunmeasured` with `measurement=UNMEASURABLE(<why>)` and exits 3
//  rather than produce a number it cannot stand behind. See `measuredMinimumHeight`.
//
//  `scripts/window-fit-check.sh` is the gate built on this. Prefer it to calling `--limits`
//  by hand — it carries the screen budget, and a number without a budget beside it is
//  just a number.
//
//  ImageRenderer is deliberately NOT used: macOS's grouped Form style is AppKit-backed
//  and renders blank through it. A real hosting window is required.
//

import SwiftUI
import AppKit

/// `--limits` reports the window size limits instead of capturing a PNG. Its argument order is
/// its own — `--limits [view] [width] [drives]` — because the render arguments it does not use
/// (output path, height, appearance) would be noise a caller had to supply anyway.
let wantsLimits = CommandLine.arguments.count > 1 && CommandLine.arguments[1] == "--limits"

let outputPath = wantsLimits
    ? "/dev/null"
    : (CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "ui-probe.png")

/// In limits mode the width still matters and the height does not: heights are what is being
/// measured, but the required height depends on how the sentences wrap, and **that depends on the
/// width**. Measured 2026-08-19: `content-starting` needs 629 pt at 640 pt wide and 92 pt less at
/// 700, because three disabled-reason sentences each gain a line. A limits number quoted without
/// its width is not a fact.
let width = wantsLimits
    ? (CommandLine.arguments.count > 3 ? (Double(CommandLine.arguments[3]) ?? 640) : 640)
    : (CommandLine.arguments.count > 2 ? (Double(CommandLine.arguments[2]) ?? 600) : 600)

let height = CommandLine.arguments.count > 3 && !wantsLimits
    ? (Double(CommandLine.arguments[3]) ?? 1000)
    : 1000

let viewName = wantsLimits
    ? (CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "content")
    : (CommandLine.arguments.count > 4 ? CommandLine.arguments[4] : "content")

/// How many drives the fixture presents. See the header — this axis moved the window's minimum
/// height by 168 pt and had never been rendered.
let driveCount = max(1, Int(CommandLine.arguments.count > (wantsLimits ? 4 : 6)
                            ? CommandLine.arguments[wantsLimits ? 4 : 6]
                            : "1") ?? 1)

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
/// there is no longer a control here whose enabled state they decide. Increment 6 took the
/// failure-mode picker to the main window, so `initialFailureMode` went the same way; the render
/// that shows the other mode selected is now `content-stop-on-error`.
///
/// What is left worth rendering is the way back from a suppressed warning, and the run-active
/// state, where uninstall is refused.
private struct DiagnosticsHost: View {

    /// `true` renders the uninstall refusal — the state a user meets while a run is going, and one
    /// that is otherwise reachable only by starting a real run.
    var runIsActive = false

    /// Step 14's suppression flag. **Local `@State`, never the real store** — a render must not
    /// read or write the machine's actual preferences, and `diagnostics-warnings-suppressed`
    /// renders the restored-state control, which is otherwise reachable only by ticking a box in a
    /// sheet this probe cannot present.
    @State private var warningsSuppressed: Bool

    init(runIsActive: Bool = false, warningsSuppressed: Bool = false) {
        self.runIsActive = runIsActive
        _warningsSuppressed = State(initialValue: warningsSuppressed)
    }

    /// Constructed here rather than taken from an `AppModel`, and it reads this machine's real
    /// `SMAppService.status` — which is why these renders show `notFound`. That was already true
    /// before increment 9 moved the registration onto `AppModel`: this view owned a `@State` one and
    /// it read the same thing. **The launch gate does not appear in any render**, because its
    /// trigger is at `ContentView`'s call site in `USBDriveTesterApp.swift`, which this probe does
    /// not compile.
    @State private var registration = HelperRegistration()

    var body: some View {
        HelperDiagnosticsView(helper: HelperConnection(),
                              registration: registration,
                              runIsActive: runIsActive,
                              warningsSuppressed: $warningsSuppressed)
            .frame(minWidth: 560, minHeight: 480)
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
                             // **Never the real store.** A render must not read or write the
                             // machine's preferences: ambient machine state leaking into an
                             // offscreen render has cost this project twice — the 2026-08-10
                             // appearance bug, and a progress bar that measured two different
                             // fills on one day with nothing in the diff touching it.
                             ioSizeStore: InMemoryIOSize(),
                             deviceSource: FixedDeviceSource(devices: DeviceFixture.fleet(of: driveCount)))
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
            ioSizeBytes: { model.ioSizeBytes },
            failureMode: { model.failureMode },
            onReport: { _ in },
            // Required rather than defaulted (Step 12 chunk 6), which is how the app build's
            // three call sites and these two were found. A render harness re-running discovery
            // would rebuild the device list underneath the layout being captured.
            onDeviceLost: {})
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
    func deviceLost() -> Bool { true }
}

/// A device source that reports a fixed list, so a render does not depend on what is plugged in.
private final class FixedDeviceSource: DeviceSource {
    private let devices: [DiscoveredDevice]
    init(devices: [DiscoveredDevice]) { self.devices = devices }
    func enumerateDevices() -> [DiscoveredDevice] { devices }
    func startObserving(onChange: @escaping () -> Void,
                        onDiskDisappeared: @escaping (DisappearedDisk) -> Void) {}
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
        usbSerialNumber: "00000S7CLNJ0WC02266P",
        usbLinkSpeedCode: 4)                    // 10 Gb/s, the scratch device's negotiated link

    /// `count` drives, so the device list's height cap can be **rendered** rather than reasoned
    /// about.
    ///
    /// `DeviceListView.listHeight` is `min(max(count * rowHeight + 16, rowHeight * 2), 260)`, so
    /// the count is load-bearing for layout in a way nothing else here is: it moved the whole
    /// window's minimum height by 168 pt between one drive and six, and saturates at six. Before
    /// this existed, every render this project has ever taken showed exactly one drive.
    ///
    /// ``evo`` is always first, so a render at the default count of 1 is byte-for-byte the render
    /// it was before this axis was added, and the selected device is the same drive in every case.
    /// The copies differ in the three fields that have to be distinct — the registry ID is the
    /// list's identity, and the BSD name and serial are both shown in the row.
    static func fleet(of count: Int) -> [DiscoveredDevice] {
        guard count > 1 else { return [evo] }
        return [evo] + (1..<count).map { i in
            DiscoveredDevice(registryEntryID: evo.registryEntryID + UInt64(i),
                             bsdName: BSDDeviceName("disk\(8 + i)"),
                             vendorName: evo.vendorName,
                             productName: evo.productName,
                             mediumType: evo.mediumType,
                             sizeBytes: evo.sizeBytes,
                             logicalBlockSize: evo.logicalBlockSize,
                             mountedVolumeNames: evo.mountedVolumeNames,
                             mountedVolumeBSDNames: evo.mountedVolumeBSDNames,
                             usbSerialNumber: "00000S7CLNJ0WC0226\(i)P",
                             usbLinkSpeedCode: evo.usbLinkSpeedCode)
        }
    }
}

/// `ContentView` with the run controls in a given state.
///
/// Rendered per state because the controls, their disabled reasons and the status line all change
/// together — and because this is where the "is anything below the fold?" question is answered.
private struct RunStateHost: View {
    enum Stage {
        case idle, starting, running, paused, finished, stopOnFirstError, noSelection, quitPending
        case selectionBelowFold
    }
    let stage: Stage

    /// Replaced by `configure()` on appear. Constructed with throwaway stores all the same: a
    /// bare `AppModel()` reads the real `UserDefaults`, and a render must not.
    @State private var model = AppModel(suppressionStore: InMemoryPreRunWarningSuppression(),
                                        ioSizeStore: InMemoryIOSize())

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
        case .finished:
            // FR-CTRL-8's other live window: "before a run starts and while a run is **stopped**".
            // The one terminal state, and until increment 6 nothing rendered it on its own — the
            // only render that reached it had a quit pending on top, where Start's refusal is the
            // quit's rather than anything about the run.
            ProbeRun.start(live)
            ProbeRun.finish(live)
        case .stopOnFirstError:
            // FR-FAIL-2 selected, at the control's new home. Replaces `diagnostics-stop-on-error`,
            // whose panel no longer has the picker in it. Worth its own render for the reason that
            // one was: what changes with the selection is not which item is chosen, it is the line
            // underneath saying everything past the first failure is left **untested**.
            live.failureMode = .stopOnFirstError
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
        case .selectionBelowFold:
            // The **last** drive selected rather than the first, and the only render in this
            // project where the selection is not on row 1.
            //
            // `DeviceFixture.fleet(of:)` puts `evo` first and the store selects the first usable
            // drive, so every render ever taken here has had its selection at the top of the list
            // — visible at any pane height, and therefore structurally blind to the defect fixed
            // on 2026-08-20: a list shrunk to `deviceListFloor` shows whichever row its scroll
            // offset lands on, which need not be the chosen drive.
            //
            // Meaningless at the default of one drive, deliberately rather than by oversight. A
            // render of this view is worth looking at only with `drives` well above 1 and a height
            // near the window's minimum; at any comfortable height the whole list fits and there
            // is nothing for the scroll to do.
            if let last = live.discovery.devices.last {
                live.discovery.select(last.registryEntryID)
            }
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
            ioSizeBytes: { model.ioSizeBytes },
            failureMode: { model.failureMode },
            onReport: { _ in },
            // Required rather than defaulted (Step 12 chunk 6), which is how the app build's
            // three call sites and these two were found. A render harness re-running discovery
            // would rebuild the device list underneath the layout being captured.
            onDeviceLost: {})
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
    func startObserving(onChange: @escaping () -> Void,
                        onDiskDisappeared: @escaping (DisappearedDisk) -> Void) {}
    func stopObserving() {}
}

/// `DeviceListView` with an empty device list, started so the store settles into its
/// no-devices state.
private struct EmptyDeviceListHost: View {
    @State private var discovery = DeviceDiscovery(source: EmptyDeviceSource())
    var body: some View {
        DeviceListView(discovery: discovery)
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
        DeviceListView(discovery: discovery)
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
                //
                // **That gap is visible again from increment 11**, in the row that states it
                // honestly. The coverage value is still supplied because the snapshot carries it
                // and the ETA is computed from the same quantity; it is on no screen.
                //
                // **This is the one fixture given a divergence a reader can SEE, and the choice is
                // deliberate.** Nothing drives a SwiftUI binding in a test, so a render is the only
                // cover the row wiring has, and it can only discriminate if the three figures are
                // visibly different. This models a drive returning bad data on about a fifth of
                // its chunks: those chunks were written, so Write does not notice them, and were
                // not confirmed, so this rate does. `chunksFailed` stays 3 because a verify
                // mismatch is not a phase failure and is counted separately.
                //
                // **v14 values, and Write is deliberately ABOVE Read.** These are the 4 TB T5 EVO's
                // real phase rates — the drive writes faster than it reads, which the wall-clock
                // pair hid behind an exact 2:1 that came from the cycle's shape rather than the
                // hardware. A render is the only place anyone will see that inversion before it
                // reaches a user, so the fixture has to carry it.
                //
                // **The clean case is on no render, and does not need to be.** `metrics-finished`
                // below carries clean figures but renders the placeholder — that is the whole
                // point of that case — so its numbers never reach a pixel. A comment here claimed
                // otherwise until 2026-09-03. What a render can show is that the row is wired to
                // its own field and sits well below its neighbours, and clean or divergent look
                // the same in kind: 130 against 376/419 is no more reassuring than 105 is. The
                // difference between them is arithmetic, and the arithmetic is unit-tested.
                deviceReadBytesPerSecond: 375_800_000,
                writeBytesPerSecond: 418_900_000,
                coverageBytesPerSecond: 122_400_000,
                completedBytesPerSecond: 105_000_000,
                estimatedRemainingSeconds: 10_620,
                readLatencySampleCount: 101_004,
                readLatencyMinimumNanoseconds: 8_100_000,
                readLatencyMaximumNanoseconds: 214_600_000,
                readLatencyP99UpperBoundNanoseconds: 19_922_944,
                chunksFailed: 3),
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
                deviceReadBytesPerSecond: -1,       // the wire's "not measured yet"
                writeBytesPerSecond: -1,
                coverageBytesPerSecond: -1,
                completedBytesPerSecond: -1,            // the wire's "not measured yet"
                estimatedRemainingSeconds: -1,
                readLatencySampleCount: 0,
                readLatencyMinimumNanoseconds: 0,
                readLatencyMaximumNanoseconds: 0,
                readLatencyP99UpperBoundNanoseconds: 0,
                chunksFailed: 0),
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
                deviceReadBytesPerSecond: 375_800_000,
                writeBytesPerSecond: 418_900_000,
                coverageBytesPerSecond: 122_400_000,
                // Nothing failed here, so this is the clean case: 129.7 is exactly what
                // `1/c = 2/r + 1/w` gives for 375.8 and 418.9, and it equalled Write until v14.
                //
                // **These figures are never rendered.** This case exists to prove the panel shows
                // the placeholder after a run ends *even when the snapshot is fully populated* —
                // a populated snapshot that renders nothing is the assertion. They are kept
                // consistent with v14 anyway, because a fixture carrying refuted numbers is a
                // fixture that will mislead the next person to read it for the values.
                completedBytesPerSecond: 129_700_000,
                estimatedRemainingSeconds: 0,
                readLatencySampleCount: 256,
                readLatencyMinimumNanoseconds: 1_100_000,
                readLatencyMaximumNanoseconds: 9_900_000,
                readLatencyP99UpperBoundNanoseconds: 2_195_000,
                chunksFailed: 0),
            isRunning: false,                  // …but no run is under way
            startedAt: Date(timeIntervalSince1970: 1_785_940_728),
            deviceName: "disk8",
            deviceSerial: "12345686DAA9")
            .padding()
    }
}

// MARK: - Step 10's run report

/// The report's content, in each state worth looking at.
///
/// **The claim that stood here was wrong, and it decided a design.** It read: *this is why the
/// report is a `Window` and not a sheet — a sheet gets its own window and `render-ui.sh` cannot
/// capture it.* This host renders `RunReportView` **directly**. The scene is not involved and never
/// was; `window-fit-check.sh` goes as far as excluding `USBDriveTesterApp.swift` by name from the
/// sources it compiles. The report became a sheet in increment 8 and every case below renders
/// exactly as it did before.
///
/// What a sheet genuinely costs is *in-place* capture — the report as it sits on its parent, at the
/// size that parent gives it — which is the same limit `PreRunPromptHost` records further down.
/// These renders answer how the report lays out at a given size; that it presents at all, and at
/// what size, is a person's check.
///
/// Export and Done are wired to no-ops: `NSSavePanel.runModal()` in a probe would hang waiting for
/// a click that is never coming, and there is no sheet here to dismiss.
private struct RunReportHost: View {

    let report: RunReport?

    var body: some View {
        RunReportView(report: report, exportAction: { _ in }, onDone: {})
            // **An exact frame, because that is how the app presents it.** `ContentView` hands the
            // sheet the main window's content area less a margin, so the report is always laid out
            // at a size imposed on it. A render that let it grow to its own ideal height would be a
            // picture of something no user can see.
            //
            // It also restores what this probe did before increment 8, and why is worth recording:
            // the view used to carry `.frame(minWidth: 620, minHeight: 560)`, and **that modifier
            // was what kept this window at the size it was asked for**. With it removed,
            // `render-ui.sh … 700 1100 report` produced a 700x5167 image — measured both ways on
            // 2026-08-21. A floor was quietly doing a second job, which is this project's recurring
            // shape: a modifier believed to do one thing and never checked for the rest.
            //
            // (2026-09-24: "always laid out at a size imposed on it" was true; "the window's content
            // area less a margin" was not, on the Xcode 27 build below about 600 pt. `ContentView`
            // measures the content, the window could be dragged shorter than it, and the sheet came
            // out taller than the window — Step 11 chunk 11 item 6. So a render here was not what a
            // user saw at those heights. It is again, since the window cannot be dragged shorter
            // than its content any more.)
            .frame(width: width, height: height)
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
                       endedBy: RunSequenceOutcome? = nil,
                       // Which of route (b)'s two ways ended the run, for the renders that need a
                       // device loss the helper's own reply never accounted for. `nil` is route
                       // (a) — the common case, and the only one with a block and a phase.
                       removalCallbackSaid: DeviceLossEnding? = nil,
                       lossPhase: DeviceLossPhaseCode = .writingBack,
                       rangeCount: Int = 0,
                       encoded: String = "",
                       blocks: UInt64 = 0,
                       mode: Int = 2,
                       bypass: Int = 1,
                       // **`R-W-R-C speed`, defaulted to the CLEAN value and parameterised so the
                       // failure variants can lower it.** 129.7 is exactly what
                       // `1/c = 2/r + 1/w` gives for this fixture's 375.8 and 418.9, so the
                       // default render's figure agrees with its own headline.
                       //
                       // It was a hardcoded 112 for about an hour on 2026-09-03, which rendered a
                       // report saying "every comparison matched" above a rate that can only fall
                       // below the identity when comparisons did not. Caught by reading the
                       // rendered sheet rather than the source — the same way the increment-10
                       // mislabel was, and the reason renders are read at all.
                       completedRate: Double = 129_700_000,
                       device: ReportedDevice = RunReportHost.device) -> RunReport {
        // **How the RUN ended, which from increment 8 is what decides the outcome** (FR-RPT-4).
        // Optional here, unlike on `RunReport.init?` where it is required with no default: this is
        // a fixture factory, and every case below states its own ending or takes the one implied
        // by `didComplete`. What the "no default" rule is defending — a *production* call site
        // silently producing a plausible wrong sentence — has no analogue in a probe whose whole
        // output is looked at by a person.
        let ending = endedBy ?? (didComplete ? .completed : .stoppedOnFailure)

        // **v10 replaced `didComplete` with an outcome code** (Step 11 increment 2) — FR-CTRL-2/4
        // give a run four endings, so a boolean beside a separate "why" would be two statements of
        // one fact. `didComplete` survives as a derived property, which is why `RunReport` needed
        // no change; this call site did, and had not been touched since.
        //
        // Derived from `ending` rather than taken separately, so the reply and the run agree by
        // construction: a fixture whose last call says "completed" while the run says "stopped by
        // the user" is reachable in reality (a stop racing a finishing call) but is a *different*
        // case from this one, and it belongs in a test rather than in a render.
        let replyCode: RunOutcomeCode
        switch ending {
        case .completed:        replyCode = .completed
        case .stoppedOnFailure: replyCode = .stoppedOnFailure
        case .stoppedByUser:    replyCode = .stoppedByUser
        case .haltedForQuit:    replyCode = .completed
        case .callFailed:       replyCode = .unrecognised
        case .deviceLost:       replyCode = .deviceLost
        }

        // v15. Route (a) sends a phase; every other ending sends `unrecognised`, which is what
        // the helper sends. **A device loss route (b) ended sends nothing either** — there was no
        // reply — which is why `removalCallbackSaid` suppresses it here rather than only being
        // passed through: a fixture that sent a phase *and* a removal-callback ending would render
        // a combination the product cannot produce.
        let routeASpoke = ending == .deviceLost && removalCallbackSaid == nil
        let phaseSent: DeviceLossPhaseCode = routeASpoke ? lossPhase : .unrecognised

        // Where route (a) spoke, the reply carries the block the run died at — and a realistic
        // one, because this figure is rendered inside a sentence and `block 0` reads as a
        // placeholder rather than as a reading.
        let replyCodeSent = routeASpoke ? replyCode : (ending == .deviceLost ? .completed : replyCode)

        let reply = RunCycleOutcome(runOutcomeCode: replyCodeSent.rawValue,
                                    interruptedAtBlock: routeASpoke ? 1_048_576 : 0,
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
                                    // v14 phase rates, the 4 TB T5 EVO's real ones. Write above
                                    // Read is correct for that drive and is the change most
                                    // visible on this sheet.
                                    deviceReadBytesPerSecond: 375_800_000,
                                    writeBytesPerSecond: 418_900_000,
                                    coverageBytesPerSecond: 122_400_000,
                                    completedBytesPerSecond: completedRate,
                                    readLatencySampleCount: 256,
                                    readLatencyMinimumNanoseconds: 1_100_000,
                                    readLatencyMaximumNanoseconds: 9_900_000,
                                    readLatencyP99UpperBoundNanoseconds: 2_195_000,
                                    message: "",
                                    deviceLossPhaseCode: phaseSent.rawValue)
        return RunReport(reply: reply,
                         endedBy: ending,
                         removalCallbackSaid: removalCallbackSaid,
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
/// cannot produce. Every USB drive attached here has at least one mounted volume, so the pane's
/// `"None mounted"` branch had never appeared in any render.
///
/// **Its original job is finished and it has a new one.** It was built to prove the standing
/// backup advice had stopped being conditional on `mountedVolumesDescription != nil`; that advice
/// was deleted on 2026-08-23. What it still renders is `"None mounted"` itself — and, since the
/// same date, the only fixture drive whose `Device Speed` is unreadable. It is the one device this
/// harness *selects* with `usbLinkSpeedCode == -1`, which makes `devices-unmounted` the only
/// render where the link-speed row's unknown sentinel is visible at all.
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
                          usbSerialNumber: "00000000NT17XBRA",
                          // The only fixture drive whose Device Speed is unreadable. See above.
                          usbLinkSpeedCode: -1)]
    }
    func startObserving(onChange: @escaping () -> Void,
                        onDiskDisappeared: @escaping (DisappearedDisk) -> Void) {}
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
                             usbSerialNumber: "12345686DAA9",
                             usbLinkSpeedCode: 4),
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
                             usbSerialNumber: "FIXTURE-BLOCKSIZE",
                             usbLinkSpeedCode: 2),
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
                             usbSerialNumber: "FIXTURE-NOCAPACITY",
                             usbLinkSpeedCode: -1),
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
                             usbSerialNumber: "FIXTURE-UNALIGNED",
                             usbLinkSpeedCode: 5),
        ]
    }
    func startObserving(onChange: @escaping () -> Void,
                        onDiskDisappeared: @escaping (DisappearedDisk) -> Void) {}
    func stopObserving() {}
}

/// `DeviceListView` showing usable and unusable drives together (NFR-USE-8).
private struct UnusableDeviceListHost: View {
    @State private var discovery = DeviceDiscovery(source: UnusableDeviceSource())
    var body: some View {
        DeviceListView(discovery: discovery)
            .onAppear { discovery.start() }
    }
}

/// `DeviceListView` showing a drive with nothing mounted.
private struct UnmountedDeviceListHost: View {
    @State private var discovery = DeviceDiscovery(source: UnmountedDeviceSource())
    var body: some View {
        DeviceListView(discovery: discovery)
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

/// Step 11 increment 9's launch-time helper gate.
///
/// A **sheet**, so it gets its own window and can never be captured in place — which is exactly why
/// `HelperGateSheet` is a standalone `View` taking plain values, the same shape `PreRunPromptSheet`
/// was built in and for the same reason: *a correct value that nobody can observe is
/// indistinguishable from a wrong one.*
///
/// What a person still has to confirm is that the sheet **presents at all**. That is mutation M4,
/// declared a survivor in advance — the trigger lives at `ContentView`'s call site in
/// `USBDriveTesterApp.swift`, which this probe does not compile, and no automated harness anywhere
/// can reach it. Everything about how it lays out is checkable from these renders.
///
/// `perform:` does nothing here. A render must not register a daemon, open System Settings or
/// terminate the process.
private struct HelperGateHost: View {

    let availability: HelperAvailability

    /// Defaults to idle, so the five state cases are unchanged by the busy case existing.
    var actionInFlight: HelperGateAction?

    var body: some View {
        HelperGateSheet(availability: availability,
                        actionInFlight: actionInFlight,
                        perform: { _ in })
    }
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
        // **This render no longer touches the helper at all** (Step 11 increment 10). It used to
        // note that the readiness banner would show its "could not ask the helper" state here,
        // since there is no daemon to reach from a probe. The banner is deleted and `DeviceListView`
        // no longer takes a connection, so what is rendered is now exactly what a user sees — where
        // before, one region of this capture was showing a state peculiar to being offscreen.
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
        // Increment 6's one render where the two pre-run controls disagree: the I/O-size dropdown
        // is live here and the failure-mode picker is not, and both disabled reasons have to make
        // that legible rather than arbitrary.
        return NSHostingView(rootView: RunStateHost(stage: .paused))
    case "content-finished":
        return NSHostingView(rootView: RunStateHost(stage: .finished))
    case "content-stop-on-error":
        return NSHostingView(rootView: RunStateHost(stage: .stopOnFirstError))
    case "content-no-selection":
        return NSHostingView(rootView: RunStateHost(stage: .noSelection))
    case "content-quit-pending":
        return NSHostingView(rootView: RunStateHost(stage: .quitPending))
    case "content-selection-below-fold":
        return NSHostingView(rootView: RunStateHost(stage: .selectionBelowFold))

    // Step 10. Every state the report window can be in.
    case "report":
        return NSHostingView(rootView: RunReportHost(report: RunReportHost.report()))
    case "report-failures":
        return NSHostingView(rootView: RunReportHost(
            report: RunReportHost.report(rangeCount: 2,
                                         encoded: "200:2:3;5000:4:1",
                                         blocks: 6,
                                         // Below the clean 129.7, matching the failures this
                                         // variant reports. The divergence and the failed-range
                                         // table have to agree, or the sheet argues with itself.
                                         completedRate: 104_000_000)))
    case "report-stopped":
        return NSHostingView(rootView: RunReportHost(
            report: RunReportHost.report(didComplete: false, rangeCount: 1,
                                         encoded: "200:2:3", blocks: 2, mode: 1)))
    case "report-stopped-by-user":
        // FR-RPT-4's fourth outcome, which had no trigger until increment 8 gave it one.
        //
        // **With a failed range in it, deliberately.** A user can stop a run that has already
        // logged bad blocks, so `RunReportOutcome.foundFailures` says nothing either way for this
        // case and the failed-range table is the only thing that does. A fixture with no failures
        // would render a page on which that distinction cannot be seen at all — and this is the
        // one outcome where "the headline does not mention failures" and "there were none" are
        // different statements.
        return NSHostingView(rootView: RunReportHost(
            report: RunReportHost.report(didComplete: false, endedBy: .stoppedByUser,
                                         rangeCount: 1, encoded: "200:2:3", blocks: 2)))
    case "report-device-lost":
        // Step 12, FR-DEV-8, route (a): the helper's reply named the block and the phase, and the
        // phase is `writingBack` — the one case with a real hazard in it, and therefore the one
        // whose wording most needs looking at rather than reading in a test.
        //
        // **With a failed range**, for `report-stopped-by-user`'s reason: a drive can log bad
        // blocks and then leave, `foundFailures` is false for this outcome too, and the table is
        // the only thing that says so.
        return NSHostingView(rootView: RunReportHost(
            report: RunReportHost.report(didComplete: false, endedBy: .deviceLost,
                                         rangeCount: 1, encoded: "200:2:3", blocks: 2)))
    case "report-device-lost-paused":
        // Route (b), way 1. The run was paused, so nothing was in flight and nothing was left
        // half-written — the one device-loss render that is allowed to be reassuring, and the
        // reason the account is three cases rather than one hedged sentence.
        return NSHostingView(rootView: RunReportHost(
            report: RunReportHost.report(didComplete: false, endedBy: .deviceLost,
                                         removalCallbackSaid: .nothingWasInFlight)))
    case "report-device-lost-silent":
        // Route (b), way 3. A call was in flight and the helper never answered it, so there is no
        // block, no phase, and no ruling a write-back out. The render to compare against the two
        // above: the same headline, three different accounts under it.
        return NSHostingView(rootView: RunReportHost(
            report: RunReportHost.report(didComplete: false, endedBy: .deviceLost,
                                         removalCallbackSaid: .theHelperNeverAnswered)))
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

    // Step 11 increment 9. The launch-time helper gate, in each of its five non-available states.
    //
    // **One render per state rather than one for the family**, which is a departure from the
    // increment's written plan and was approved on 2026-08-27. The states differ in message length,
    // in **button count** (`notFound` has one; the rest have two) and in which remedy is the
    // emphasised control — and `unreachable` is the only surface in this app carrying a string whose
    // length the app does not choose, since it is a transport error's `localizedDescription`. The
    // precedent is the `warnings*` family: four renders over a two-case type, because *a state
    // nobody can observe is a state nobody has checked*.
    //
    // Four of these five cannot be produced on this machine without breaking something on purpose.
    // That is what the renders are for.
    case "helper-gate-not-found":
        // The one Quit-only state: a single button, and the shortest possible footer.
        return NSHostingView(rootView: HelperGateHost(availability: .notFound))
    case "helper-gate-not-registered":
        return NSHostingView(rootView: HelperGateHost(availability: .notRegistered))
    case "helper-gate-requires-approval":
        return NSHostingView(rootView: HelperGateHost(availability: .requiresApproval))
    case "helper-gate-unreachable":
        // The longest text the gate can show, and the only one this app does not author: the
        // detail is whatever XPC's error handler produced. Rendered with a real one.
        return NSHostingView(rootView: HelperGateHost(
            availability: .unreachable(detail: "The connection to service named "
                                             + "com.arc3solutions.USBDriveTester.Helper was "
                                             + "invalidated: failed at lookup with error "
                                             + "159 - Sandbox restriction.")))
    case "helper-gate-version-mismatch":
        // A daemon one version behind, which is what an app update over a running helper produces.
        return NSHostingView(rootView: HelperGateHost(
            availability: .versionMismatch(helper: TesterProtocol.version - 1,
                                           app: TesterProtocol.version)))
    case "helper-gate-busy":
        // A remedy in flight: the remedies disabled, a spinner and a label, **Quit still live**.
        // Rendered on `versionMismatch` because that is the slow one — 719 ms end to end, measured
        // 2026-09-01 — and the only state whose label reads "Replacing". The user asked for this
        // after noticing the gate would accept a second press while the first was still running;
        // a cursor change, which was the other candidate, could not be rendered here at all.
        return NSHostingView(rootView: HelperGateHost(
            availability: .versionMismatch(helper: TesterProtocol.version - 1,
                                           app: TesterProtocol.version),
            actionInFlight: .registerHelper))

    // Step 14. The pre-run dialog, in each of its forms.
    case "warnings":
        return NSHostingView(rootView: PreRunPromptHost(
            prompt: .fullWarnings(PreRunPromptHost.defaultSelectedDevice)))
    case "warnings-ticked":
        // The suppression checkbox in its ticked state, which is otherwise never rendered — and
        // which is the state that changes what the *next* run shows.
        return NSHostingView(rootView: PreRunPromptHost(
            prompt: .fullWarnings(PreRunPromptHost.defaultSelectedDevice),
            suppress: true))
    case "warnings-confirm":
        // What a user sees after suppressing. This render is the one that matters most: it is the
        // whole of what stands between a click and a write for anyone who ticked the box.
        return NSHostingView(rootView: PreRunPromptHost(
            prompt: .briefConfirmation(PreRunPromptHost.defaultSelectedDevice)))
    case "warnings-unidentified":
        return NSHostingView(rootView: PreRunPromptHost(
            prompt: .briefConfirmation(PreRunPromptHost.unidentifiedDevice)))

    default:
        // **This list is hand-maintained and had drifted from the switch above — for the third
        // time in this project, and the first time inside the probe itself.** CONSTRAINTS records
        // `render-ui.sh`'s header list drifting twice (2026-08-11 and again in increment 6) and
        // names the probe as the authority that settles it. The authority's own error message was
        // meanwhile missing `content-selection-below-fold` and `devices-unusable`, so a typo in
        // either name was answered by a message implying the view had never existed.
        //
        // Restored in increment 8, in the switch's own order so the two can be read side by side.
        // If you add a case above, add it here: the compiler cannot, because a `default` accepts
        // everything by definition.
        FileHandle.standardError.write(Data("""
            ui-probe: unknown view '\(name)'; expected diagnostics, diagnostics-run-active, \
            diagnostics-warnings-suppressed, content-quitting, \
            metrics, metrics-finished, metrics-idle, \
            empty, devices, devices-unmounted, devices-unusable, \
            content, content-starting, content-running, content-paused, content-finished, \
            content-stop-on-error, content-no-selection, content-quit-pending, \
            content-selection-below-fold, \
            report, report-failures, report-stopped, report-stopped-by-user, \
            report-device-lost, report-device-lost-paused, report-device-lost-silent, \
            report-qualified, report-unidentified, report-empty, \
            helper-gate-not-found, helper-gate-not-registered, helper-gate-requires-approval, \
            helper-gate-unreachable, helper-gate-version-mismatch, helper-gate-busy, \
            warnings, warnings-ticked, warnings-confirm or warnings-unidentified\n
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

/// What `measuredMinimumHeight` found, or why it found nothing.
///
/// **A measurement that cannot say it failed is worse than no measurement.** Until 2026-09-19 this
/// function returned a bare `CGFloat`, and when both of its mechanisms broke on macOS 27 it
/// returned `1` for every state — a number the gate then quietly discarded in favour of the
/// declared minimum, printing *"every state fits"* off a worst case of 556 pt where the real figure
/// was 613 (614 since 2026-09-24, when `WindowMetrics.deviceListFloor` went to 104). The failure was
/// invisible because the type had no way to be.
enum MeasuredMinimum {
    case measured(CGFloat)
    /// The reason, worded for a gate to print verbatim.
    case unmeasurable(String)
}

/// The smallest content height at which SwiftUI's laid-out content still fits the space it is
/// given — the number a user finds by dragging the window's edge up until it stops.
///
/// - Parameters:
///   - ceiling: a height known to be comfortable. Doubled if it turns out not to be, so a view
///     that needs more than its unconstrained intrinsic height cannot silently peg the search.
///
/// ## How "does it fit" is decided
///
/// When SwiftUI's content cannot compress into the height the hosting view was handed, the child
/// carrying that content is **taller than the hosting view's bounds**, and the excess is what gets
/// clipped on screen. Comparing the two is the question the eye asks of a render, asked
/// arithmetically.
///
/// **The child is the TALLEST of them, not the first (corrected 2026-09-19).** On macOS 26 an
/// `NSHostingView` had a single subview and `subviews.first` was the content. On macOS 27 it has
/// eleven for `content-starting`, measured: two 24 pt `KeyViewProxy`, five 24 pt `_FocusRingView`,
/// three `AppKitPlatformViewHost<…>` wrapping this app's own representables, and a
/// `PlatformContainer` holding the flexible pane. `subviews.first` was a 24 pt focus proxy, so the
/// answer became "24 pt is enough for the whole window" — and, with the clamp below, `1`.
///
/// Taking the maximum cannot under-report: any child taller than the hosting view is content being
/// clipped, whichever child it is. It can over-report by the height of those proxies, so a view
/// whose true minimum is under 24 pt reads as 24 — `report` did exactly that on macOS 26, against a
/// declared 560, and the `max` with the declared number is what makes it harmless.
///
/// ## Why the advertised minimum has to be cleared first — and why clearing it is not enough
///
/// `contentMinSize` is exactly what is under suspicion, and while it stands the window refuses to
/// go below it — the search would bottom out at the wrong answer and confirm it. Measured: asking
/// for 420 pt with the advertised minimum in place returns 485 and overflow, which reads as
/// "485 does not fit" without ever testing anything smaller.
///
/// **On macOS 27, clearing it does not hold: `sizingOptions` contains `.minSize`, and the hosting
/// view re-imposes the minimum on the next layout pass** — asked for 1 pt, the window came back
/// 524 (measured 2026-09-19, and the cause tested rather than inferred: dropping `.minSize` for
/// the search makes the window take every height it is asked for, 1 pt included). So the search
/// drops `.minSize` first. `.maxSize` and `.intrinsicContentSize` stay: the maximum and the
/// intrinsic size have already been read by the caller, and neither constrains a shrink.
///
/// The declared minimum is read by the caller **before** this runs, so dropping the option cannot
/// change the number this is compared against.
///
/// ## And the search says when it was lied to
///
/// Every probe of a height checks that the window actually took it. A window that refuses to
/// shrink makes every answer below the clamp a fiction, so the first refusal ends the measurement
/// with `.unmeasurable` rather than a number. That is the check that would have caught the macOS 27
/// breakage on the day the SDK changed instead of nineteen days later.
///
/// Nothing is restored afterwards. `--limits` exits at the end of this pass, and a mode that
/// captures nothing has no state worth putting back.
func measuredMinimumHeight(window: NSWindow,
                           rootView: NSView,
                           width: CGFloat,
                           ceiling: CGFloat) -> MeasuredMinimum {
    if let hosting = rootView as? any SizingOptionsSettable {
        hosting.sizingOptions = [.maxSize, .intrinsicContentSize]
    }
    window.contentMinSize = NSSize(width: 1, height: 1)
    window.minSize = NSSize(width: 1, height: 1)

    /// The first height the window refused to shrink to, if it refused one.
    var refused: (asked: CGFloat, got: CGFloat)?

    func overflows(at height: CGFloat) -> Bool {
        window.setContentSize(NSSize(width: width, height: height))
        window.layoutIfNeeded()
        rootView.layoutSubtreeIfNeeded()
        // Only a refusal to SHRINK invalidates the search. A refusal to grow is what the ceiling
        // guard below reports, and an offscreen window asked for sixteen times a screen height may
        // legitimately not get it.
        if rootView.bounds.height > height + 0.5, refused == nil {
            refused = (height, rootView.bounds.height)
        }
        let laidOut = rootView.subviews.map(\.frame.height).max() ?? 0
        // Half a point of slack: these are CGFloats off a layout pass, and an exact `>` would turn
        // a rounding artefact into a one-point difference in the answer.
        return laidOut > rootView.bounds.height + 0.5
    }

    func verdict(_ height: CGFloat) -> MeasuredMinimum {
        if let refused {
            return .unmeasurable("""
                the window would not shrink to the height it was asked for — asked \(Int(refused.asked)) pt, \
                got \(Int(refused.got)) pt, so every height below that was never tested
                """)
        }
        return .measured(height)
    }

    var high = ceiling
    var guardCount = 0
    while overflows(at: high) && guardCount < 4 {
        high *= 2
        guardCount += 1
    }
    // A view that will not fit at sixteen times a comfortable height is broken in a way this
    // function cannot describe. Report the ceiling rather than loop, and let the number be absurd
    // enough to be noticed.
    guard !overflows(at: high) else { return verdict(high) }

    var low: CGFloat = 1
    guard overflows(at: low) else { return verdict(low) }

    while high - low > 1 {
        let mid = ((low + high) / 2).rounded()
        if overflows(at: mid) { low = mid } else { high = mid }
    }
    return verdict(high)
}

/// Reaches `NSHostingView.sizingOptions` without naming the generic's `Content` parameter.
///
/// `makeRootView` is typed `NSView` — it returns a different `NSHostingView<…>` per case, so there
/// is no single concrete type to cast to. A protocol the generic conforms to is the way in.
protocol SizingOptionsSettable: AnyObject {
    var sizingOptions: NSHostingSizingOptions { get set }
}
extension NSHostingView: SizingOptionsSettable {}

// **This is what makes `--limits` measure the shipped behaviour rather than an approximation.**
// Without `sizingOptions`, an `NSHostingView` keeps its SwiftUI size constraints to itself and the
// window's `contentMinSize` stays at AppKit's default — so the numbers printed below would be the
// window's own, not the view's, and would agree with the app only by accident. Setting it makes
// the view propagate its minimum and maximum upward, which is what a `Window` scene arranges.
//
// Only in limits mode: a render wants the window at the size it was asked for, and propagating a
// minimum would let the content refuse to be rendered small.
if wantsLimits, let hosting = rootView as? any SizingOptionsSettable {
    hosting.sizingOptions = [.minSize, .maxSize, .intrinsicContentSize]
}

window.contentView = rootView

// Ordered front so SwiftUI lays out and draws, but positioned far offscreen so it
// never appears in front of whatever the user is doing.
window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
window.makeKeyAndOrderFront(nil)

// Give SwiftUI a beat to lay out and draw before capturing.
DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
    if wantsLimits {
        // `inf` rather than a ten-digit number: the maximum being unbounded is a *fact about the
        // design* — it is why the window opened at screen height for as long as the scene declared
        // no `.defaultSize` — and printing `10000000` invites it to be read as a large limit that
        // somebody chose.
        func pt(_ value: CGFloat) -> String {
            value > 100_000 ? "inf" : String(Int(value.rounded()))
        }
        let advertised = window.contentMinSize
        let maximum = window.contentMaxSize
        let intrinsic = rootView.intrinsicContentSize

        // ## The advertised minimum is not the enforced one, and the gap was 58 pt
        //
        // `window.contentMinSize` is what SwiftUI *declares*, and it is computed from the
        // `.frame(minHeight:)` each pane asks for. **The `List` in `DeviceListView` does not
        // honour the one it is given.** `deviceListFloor` declares 46 pt — one row — and the
        // AppKit table backing that pane will not lay out below about 104 whatever it is told.
        //
        // So the declared total came out 58 pt short of any height the content can actually
        // occupy: `--limits` reported 485 for `content` where the shipped app clamps at 543, and
        // the difference is exactly the 58 pt the list refuses to give up. It was found by
        // resizing the real window with accessibility scripting on 2026-08-20 and confirmed by
        // raising `deviceListFloor` to 104, which moves the advertised number to 543 on the nose.
        //
        // (2026-09-24: `deviceListFloor` IS 104 now, so the two numbers agree in every `content-*`
        // state, and this note is the account of 2026-08-20. The measurement stays: it is what
        // `window-fit-check.sh`'s third check holds the declaration to.)
        //
        // A render at the advertised number **clips**, which is what makes this the gate's
        // problem rather than a curiosity: `window-fit-check.sh` was answering "does it fit"
        // with a height at which it demonstrably does not.
        //
        // ## So measure the layout instead of the declaration
        //
        // `measuredMinimumHeight` drives the window down and asks, at each height, whether
        // SwiftUI's laid-out content is taller than the space it was given. The smallest height
        // where it is not is the honest minimum, and it agrees with the shipped app exactly.
        //
        // This is the project's own rule applied to its own instrument: verify the postcondition,
        // not the return value. A floor a control ignores is a request that was accepted and had
        // no effect, and nothing announced it.
        // ## Neither number alone, and the two fail in opposite directions
        //
        // The declared minimum can be **too small** — a pane whose control ignores the floor it
        // was given, which is this whole note's subject. It is never too large: SwiftUI does not
        // invent constraints nobody asked for.
        //
        // The measured one can also be too small, for an unrelated reason: it only sees content
        // that overflows the hosting view, and a view that is *entirely* a scroll region never
        // does. Measured 2026-08-20 — `report` bottoms out at 24 pt against a declared 560, and
        // `devices` at 1 pt against 210, because in both the whole body is inside a `ScrollView`
        // that clips internally and never reports a size it could not honour.
        //
        // So the enforced minimum is **at least both**, and neither can overstate it. Taking the
        // larger is right for the same reason on both sides rather than by luck.
        let measurement = measuredMinimumHeight(window: window,
                                                rootView: rootView,
                                                width: width,
                                                ceiling: max(intrinsic.height, 1_200))

        // The enforced minimum is the larger of the two numbers, so there is no enforced minimum to
        // print when one of them is missing. It prints `unmeasured` rather than falling back to the
        // declaration, because a gate reading this line must not be able to mistake the one for the
        // other — which is exactly what happened on 2026-09-19, silently, for nineteen days.
        let enforcedText: String
        let overflowText: String
        var measurementNote = ""
        switch measurement {
        case .measured(let measured):
            enforcedText = pt(max(advertised.height, measured))
            overflowText = pt(measured)
        case .unmeasurable(let why):
            enforcedText = "unmeasured"
            overflowText = "unmeasured"
            measurementNote = " measurement=UNMEASURABLE(\(why.replacingOccurrences(of: "\n", with: " ")))"
        }

        print("""
              ui-probe: limits view=\(viewName) drives=\(driveCount) atWidth=\(Int(width)) \
              min=\(pt(advertised.width))x\(enforcedText) \
              declared=\(pt(advertised.width))x\(pt(advertised.height)) \
              overflowAt=\(overflowText) \
              max=\(pt(maximum.width))x\(pt(maximum.height)) \
              intrinsic=\(pt(intrinsic.width))x\(pt(intrinsic.height)) \
              appearance=\(appearanceName)\(measurementNote)
              """)
        // A failed measurement is a failed run, so a hand call cannot read as a success. The gate
        // reads the line either way — it captures output with `|| true` for exactly this reason.
        exit(measurementNote.isEmpty ? 0 : 3)
    }

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
