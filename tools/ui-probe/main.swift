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

// An opt-in "activate the app and put the window on screen" mode was written here on 2026-08-05,
// on the theory that a parked `.accessory` window could never show emphasized selection. The
// diagnostic line added alongside it refuted that in one run — the default mode already reports
// `appActive=true windowKey=true` — so the mode was never needed and has been removed rather than
// left in as an untested path in a tool whose only value is being trustworthy. The diagnostic
// stayed; it is what settled the question.

/// Wraps a view needing a `Binding` so it can be rendered standalone.
private struct DiagnosticsHost: View {
    /// Rendered both ways: `held` shows the bounded-cycle control live, `false` shows the
    /// disabled state and its corrective instruction — which is the state a user actually meets
    /// first, and the one that was reported as "the button does nothing".
    let deviceIsHeld: Bool
    /// `false` renders the quit-pending refusal. Rendered because that state is only reachable in
    /// the real app by starting a run and then asking to quit — and the corrective note is the
    /// whole reason the disabled button is not simply a dead control.
    var mayIssueNewWork = true
    @State private var simulatedRunActive = false
    // Step 9's bounded-cycle scaffolding reports run state and the negotiated link speed up to
    // `ContentView`, so rendering this view standalone needs somewhere for them to go.
    @State private var cycleIsRunning = false
    @State private var linkSpeedCode = -1
    var body: some View {
        HelperDiagnosticsView(simulatedRunActive: $simulatedRunActive,
                              helper: HelperConnection(),
                              cycleIsRunning: $cycleIsRunning,
                              linkSpeedCode: $linkSpeedCode,
                              deviceIsHeld: deviceIsHeld,
                              mayIssueNewWork: mayIssueNewWork)
            .frame(minWidth: 560, minHeight: 480)
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

    /// Driven through the real sequence rather than assigned: ask, confirm, and leave a cycle in
    /// flight so the model waits at exactly the point the banner describes. Reaching a state by
    /// the route the user takes is the difference between rendering the app and rendering a pose.
    private static func windingDownModel() -> AppModel {
        let model = AppModel()
        model.terminateAction = {}        // belt and braces: a render must never quit the probe
        model.cycleIsRunning = true       // a privileged call in flight, so the boundary is ahead
        _ = model.quitRequested()         // → the confirmation
        model.cancelAndQuit()             // → winding down, waiting for that call to return
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
            .environment(AppModel())
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
            .environment(AppModel())
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
                readBytesPerSecond: 492_870_060,
                writeBytesPerSecond: 431_240_000,
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
                readBytesPerSecond: -1,             // the wire's "not measured yet"
                writeBytesPerSecond: -1,
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

// Not `@MainActor`: top-level code in main.swift is nonisolated even under
// -default-isolation MainActor, so annotating this makes it uncallable from here.
func makeRootView(_ name: String) -> NSView {
    switch name {
    case "diagnostics":
        return NSHostingView(rootView: DiagnosticsHost(deviceIsHeld: false))
    case "diagnostics-held":
        return NSHostingView(rootView: DiagnosticsHost(deviceIsHeld: true))
    case "diagnostics-quitting":
        // A device is held, so nothing else would disable the control: what this render checks is
        // that the quit-pending refusal is the reason shown, and that it reads as one.
        return NSHostingView(rootView: DiagnosticsHost(deviceIsHeld: true,
                                                       mayIssueNewWork: false))
    case "content-quitting":
        return NSHostingView(rootView: QuittingContentHost())
    case "metrics":
        return NSHostingView(rootView: MetricsHost())
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
        return NSHostingView(rootView: ContentView().environment(AppModel()))
    default:
        FileHandle.standardError.write(Data("""
            ui-probe: unknown view '\(name)'; expected content, content-quitting, devices, \
            diagnostics, diagnostics-held, diagnostics-quitting, empty, metrics or metrics-idle\n
            """.utf8))
        exit(2)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                      styleMask: [.titled], backing: .buffered, defer: false)
window.contentView = makeRootView(viewName)

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
    print("""
          ui-probe: appActive=\(app.isActive) windowKey=\(window.isKeyWindow) \
          firstResponder=\(responder)
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
