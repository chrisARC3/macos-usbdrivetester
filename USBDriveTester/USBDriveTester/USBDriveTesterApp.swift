//
//  USBDriveTesterApp.swift
//  USBDriveTester
//
//  Created by Christopher Karr on 6/26/26.
//
//  Two scenes as of Step 9. The diagnostics panel moved out of the main window because the
//  window's vertical space requirements had become excessive (user decision 2026-08-04) — the
//  device list, the selected-device detail, the mount controls, the metrics panel and a
//  four-section diagnostics form do not belong in one column.
//
//  ## Why a separate window and not a sheet
//
//  A sheet is modal, and the control that **starts** a run lives in diagnostics while the metrics
//  panel that displays it lives in the main window. A modal would therefore cover the one thing
//  worth watching, for the whole of the run it just started. A separate window can sit beside the
//  main one.
//
//  ## Why both scenes share one `AppModel`
//
//  The helper releases a device claim when the connection that acquired it goes away
//  (NFR-REL-5). Two scenes each building their own `HelperConnection` would be two owners, and
//  closing the diagnostics window could drop a claim out from under a run in the main window. One
//  model, injected into both. See `AppModel`.
//
//  ## Why the main scene is a `Window` and not a `WindowGroup` (2026-08-05)
//
//  A `WindowGroup` gives macOS **File ▸ New Window (⌘N)**, and a second main window would build a
//  second `DeviceDiscovery` with its own selection while both shared one `HelperConnection` and
//  therefore one claim. The two windows could then disagree about *which drive is selected* while
//  only one was actually held — NFR-USE-3's hazard, on the screen whose entire job is stopping the
//  wrong drive from being written to. It is the same one-truth-two-views problem the diagnostics
//  scene already solved by being a `Window`; this applies the existing pattern to the main scene.
//
//  **Measured before the change, not assumed** (scratch scene probe, macOS 26, 2026-08-05 — the
//  same two-scene shape and the same `.commands` block as below):
//
//  | | `WindowGroup` | `Window` |
//  |---|---|---|
//  | File menu | New Window ⌘N, Close ⌘W, Close All ⇧⌘W | **no File menu at all** |
//  | Window menu | the open-window list | a permanent item titled with the window's title |
//
//  So the change removes ⌘N — and ⌘W with it, since SwiftUI stops generating the File menu
//  entirely, which leaves the title-bar button as the only way to close the main window (that is
//  what `MainWindowCloseGuard` intercepts during a run). A closed main window is also not lost:
//  the Window menu keeps an item that brings it back.
//
//  ## Closing the MAIN window quits the app (user decision 2026-08-06)
//
//  Step 9 concluded from the paragraph above that the app need not quit when its window closes —
//  the window is recoverable, so leaving it running costs nothing. **That was reasoned, not
//  observed**, and Step 9 recorded the whole area as measured-on-a-probe-but-never-seen-in-the-product.
//  Seen in the product, it is wrong: the helper's claim outlives the window, so the app could sit
//  invisibly with somebody's drive unmounted and no UI to release it.
//
//  The rule is **the main window's close is a quit request**, and it lives in
//  `QuitPolicy.closeDisposition` where the truth table is tested. The diagnostics and report
//  windows are panels belonging to the app; they go when it goes, and closing one of *them* does
//  nothing to the app.
//
//  An interim version used `applicationShouldTerminateAfterLastWindowClosed` alone, and observing
//  that is what produced the rule above: it fires only when no window is left, so closing the main
//  window quit the app or not depending on whether a panel opened earlier was still up — a
//  behaviour keyed on AppKit's window count rather than on anything the user did. That flag is
//  still set, now as a backstop for ending up with no UI by some route nobody enumerated.
//
//  Neither route can bypass the during-a-run confirmation, which refuses the close before AppKit
//  ever gets as far as terminating.
//

import SwiftUI

@main
struct USBDriveTesterApp: App {

    /// One model for the whole app, owned by the scene tree's root so it outlives any window.
    @State private var model = AppModel()

    /// The app-level lifecycle hook. It exists for one reason: ⌘Q during a run must ask first,
    /// and SwiftUI has no hook that can refuse a termination. See `AppLifecycleDelegate`.
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var lifecycle

    var body: some Scene {
        // Titled explicitly because `Window` requires it, and titled with the product name
        // because that is what `WindowGroup` used to derive from the bundle — the title bar reads
        // the same as it did, and the Window menu's new entry reads the same as the app.
        Window("USBDriveTester", id: WindowID.main) {
            ContentView()
                .environment(model)
                // SwiftUI creates the delegate, so it cannot be handed the model at construction.
                // Wired at a documented lifecycle point instead: a ⌘Q arriving before the main
                // window has ever appeared finds no model and terminates immediately, which is
                // right — no run can be in flight before the UI that starts one exists.
                .onAppear { lifecycle.model = model }
        }
        // **The main window had no declared size at all until Step 11 increment 7**, and that is
        // why it opened enormous. A scene with no `.defaultSize` opens at its content's ideal
        // size, and this content's *maximum* height is unbounded — which is also what
        // `render-ui.sh` is recording when it says the probe's height argument behaves as "a
        // floor, not a ceiling". The result was a window sized to the screen: measured at 1328 pt
        // tall on a 1410 pt display, against content that wanted 675.
        //
        // Set to the comfortable height rather than the minimum, so nothing scrolls on opening at
        // one attached drive; macOS constrains it down on a display that cannot spare it.
        //
        // **It is only consulted when no frame has been saved.** AppKit's frame autosave wins
        // afterwards — the `NSWindow Frame main` key in the app's preferences — so a window that
        // was once screen-height stays that way for that user until the saved frame is cleared.
        .defaultSize(width: WindowMetrics.defaultContentWidth,
                     height: WindowMetrics.defaultContentHeight)
        .commands {
            CommandGroup(after: .windowList) {
                RunReportWindowCommand()
                DiagnosticsWindowCommand()
            }
        }

        // `Window` rather than `WindowGroup`: there is exactly one helper and exactly one
        // registration state, so a second copy of this panel would be two views of one truth
        // that could disagree. `Window` is single-instance by construction — asking to open it
        // again brings the existing one forward.
        Window("Privileged Helper & Diagnostics", id: WindowID.diagnostics) {
            HelperDiagnosticsWindow()
                .environment(model)
        }
        .defaultSize(width: 660, height: 720)

        // Step 10. A `Window` for the same reason the diagnostics panel is one — there is
        // exactly one most-recent run, so a second copy of this would be two views of one truth
        // — and for one more that decided it against a sheet: a `Window` is renderable by
        // `tools/ui-probe`, and a sheet is not. This project has found three defects by
        // rendering that no assertion caught.
        //
        // It opens itself when a run ends and stays reachable from the Window menu afterwards.
        Window("Run Report", id: WindowID.report) {
            RunReportWindow()
                .environment(model)
        }
        .defaultSize(width: 720, height: 760)
    }
}

/// The menu item that opens the run report.
private struct RunReportWindowCommand: View {

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Run Report") { openWindow(id: WindowID.report) }
            .keyboardShortcut("r", modifiers: [.command, .shift])
    }
}

/// The report window's content.
private struct RunReportWindow: View {

    @Environment(AppModel.self) private var model

    var body: some View {
        RunReportView(report: model.lastRunReport)
    }
}

/// The menu item that opens the diagnostics window.
///
/// Split into its own view because `openWindow` is an environment value, and a `Scene`'s
/// `commands` builder has no environment to read it from.
private struct DiagnosticsWindowCommand: View {

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Privileged Helper & Diagnostics") {
            openWindow(id: WindowID.diagnostics)
        }
        .keyboardShortcut("d", modifiers: [.command, .shift])
    }
}

/// The diagnostics window's content: the panel, plus the minimum size a standalone window needs
/// and a disclosure did not.
private struct HelperDiagnosticsWindow: View {

    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        // Seven arguments fewer than before increment 5. The run, the report and the pre-run dialog
        // left when Start took ownership of the sequence; the failure-mode picker left in
        // increment 6, to the pre-run controls beside the I/O-size dropdown. What is left needs the
        // helper, the real run state, and one setting.
        HelperDiagnosticsView(helper: model.helper,
                              runIsActive: model.runIsActive,
                              warningsSuppressed: $model.warningsSuppressed)
            .frame(minWidth: 560, minHeight: 480)
    }
}
