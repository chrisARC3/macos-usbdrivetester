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
//  what `MainWindowCloseGuard` intercepts during a run). And a closed main window is not lost: the
//  Window menu keeps an item that brings it back, which is why this does not need
//  `applicationShouldTerminateAfterLastWindowClosed`.
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
        .commands {
            CommandGroup(after: .windowList) {
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
        HelperDiagnosticsView(simulatedRunActive: $model.simulatedRunActive,
                              helper: model.helper,
                              cycleIsRunning: $model.cycleIsRunning,
                              linkSpeedCode: $model.linkSpeedCode,
                              deviceIsHeld: model.helperHoldsDevice,
                              mayIssueNewWork: model.mayIssueNewWork)
            .frame(minWidth: 560, minHeight: 480)
    }
}
