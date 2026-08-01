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

/// Wraps a view needing a `Binding` so it can be rendered standalone.
private struct DiagnosticsHost: View {
    @State private var simulatedRunActive = false
    var body: some View {
        HelperDiagnosticsView(simulatedRunActive: $simulatedRunActive,
                              helper: HelperConnection())
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

// Not `@MainActor`: top-level code in main.swift is nonisolated even under
// -default-isolation MainActor, so annotating this makes it uncallable from here.
func makeRootView(_ name: String) -> NSView {
    switch name {
    case "diagnostics":
        return NSHostingView(rootView: DiagnosticsHost())
    case "empty":
        return NSHostingView(rootView: EmptyDeviceListHost())
    case "devices":
        // From Step 6 the device view talks to the helper for the readiness banner.
        // There is no daemon to reach from here, so the banner renders its "could not
        // ask the helper" state — which is itself worth seeing laid out, since it is
        // what a user with no helper installed gets.
        return NSHostingView(rootView: DeviceListView(discovery: DeviceDiscovery(),
                                                      helper: HelperConnection()))
    case "content":
        return NSHostingView(rootView: ContentView())
    default:
        FileHandle.standardError.write(Data("""
            ui-probe: unknown view '\(name)'; expected content, devices, diagnostics or empty\n
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
