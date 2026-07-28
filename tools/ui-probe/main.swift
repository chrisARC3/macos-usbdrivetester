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
//      ui-probe <output.png> [width] [height]
//
//  ImageRenderer is deliberately NOT used: macOS's grouped Form style is AppKit-backed
//  and renders blank through it. A real hosting window is required.
//

import SwiftUI
import AppKit

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "ui-probe.png"
let width = CommandLine.arguments.count > 2 ? (Double(CommandLine.arguments[2]) ?? 600) : 600
let height = CommandLine.arguments.count > 3 ? (Double(CommandLine.arguments[3]) ?? 1000) : 1000

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                      styleMask: [.titled], backing: .buffered, defer: false)
window.contentView = NSHostingView(rootView: ContentView())

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
