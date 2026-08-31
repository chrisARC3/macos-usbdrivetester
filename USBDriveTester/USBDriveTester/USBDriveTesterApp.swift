//
//  USBDriveTesterApp.swift
//  USBDriveTester
//
//  Created by Christopher Karr on 6/26/26.
//
//  **Two scenes.** Step 10 briefly made it three — the run report had a window of its own — and
//  increment 8 made it a **sheet on the main window** instead (user decision 2026-08-19), because a
//  run started underneath an open report emptied it. `RunReportView`'s header carries that account,
//  including why the 2026-08-06 reason for preferring a window was measurably wrong.
//
//  The diagnostics panel moved out of the main window because the
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
//  `QuitPolicy.closeDisposition` where the truth table is tested. The diagnostics window is a panel
//  belonging to the app; it goes when the app goes, and closing *it* does nothing to the app.
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

import AppKit
import Combine
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
                // **The launch-time helper gate fires HERE and not in `ContentView.onAppear`, and
                // that placement is the whole of its isolation** (increment 9).
                //
                // `tools/ui-probe` renders the real `ContentView` for its seven `content-*` cases.
                // A check fired from that view's own `onAppear` would make every render read this
                // machine's live `SMAppService.status` and issue a real XPC call — ambient machine
                // state leaking into an offscreen render, which CONSTRAINTS records this project
                // paying for twice (the appearance bug of 2026-08-10, and the progress bar
                // measuring two different fills in one day).
                //
                // Measured rather than arranged around: `USBDriveTesterApp.swift` is excluded **by
                // name** from all three harnesses — `render-ui.sh:201`, `window-fit-check.sh:144`
                // and `build-tools.sh:62`. A modifier applied at this call site is therefore not
                // carried by the probe's bare `ContentView()`, so every render is provably free of
                // the gate while `ContentView` still *compiles* the sheet that presents it. Without
                // this placement the alternative was a fourth injected dependency on `AppModel.init`.
                //
                // What it costs, stated rather than left to be discovered: this line is in the one
                // file nothing automated compiles. `build.sh` and `test.sh` still compile it, so a
                // compile error is caught; a logic error is not. That is mutation M4, and this
                // placement is what makes its survival structural rather than incidental.
                .onAppear { model.refreshHelperAvailability() }
                // **And again on every activation, while the gate is up** (user request,
                // 2026-08-27, found walking chunk 13 item 4).
                //
                // Without this the gate is a snapshot of the moment the app launched. The
                // `requiresApproval` remedy sends the user to System Settings, and coming back with
                // the switch turned on changed nothing: the modal stayed up until Open Login Items
                // was pressed a *second* time, which is what made that one button do double duty —
                // open Settings, and re-check. Re-checking on activation is what the user expects a
                // window to do when they return to it having done what it asked.
                //
                // **This is what retires the item-4 question**, which had been framed as a choice
                // between a button that quietly does two things and a third button (Open Login
                // Items… · Retry · Quit) departing from the action table approved 2026-08-26.
                // Neither is needed: the re-check has no button at all.
                //
                // Guarded on the gate being up, deliberately. Unguarded, every ⌘-Tab back to this
                // app would issue an XPC round trip for an answer nothing is waiting on. The cost
                // of the guard is that a helper dying while the app is in the background is not
                // noticed on return — which is not this trigger's job: Start prepares the device
                // through the helper, and ⇧⌘D asks directly.
                //
                // Here rather than on `ContentView` for the reason the launch trigger is here: this
                // is the one file no harness compiles, so no render can acquire an activation
                // observer on this machine's live `SMAppService` status.
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.didBecomeActiveNotification)) { _ in
                    guard !model.helperAvailability.isAvailable else { return }
                    model.refreshHelperAvailability()
                }
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
                // Handed the model rather than reading it from the environment: a `Scene`'s
                // `commands` builder has no environment, which is also why each of these is a
                // `View` rather than a `Button` written inline.
                RunReportCommand(model: model)
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

/// The menu item that raises the run report (⇧⌘R), titled **View Last Run Report**.
///
/// **Named for what it opens, not as an instruction** (user decision, 2026-08-27). It read
/// *Run Report* until then, which in a menu is a verb phrase: it looks like a control that
/// *starts* a run report, in an app whose entire subject is starting runs. Nothing is ever
/// generated on demand here — the item opens the last finished run's report, or the empty
/// state that says `No run has finished yet`.
///
/// **The wording is load-bearing for the human checklist**, which tells a tester to look for
/// this item by name in chunks 11 and 13. Renaming it without renaming them there leaves a
/// checklist that cannot be followed.
///
/// **Disabled while a run is active** (user decision, 2026-08-21). A run clears the report as it
/// begins, so during one there is nothing to raise but the empty state — and the report is a
/// window-modal sheet, so raising it would put Pause and Stop out of reach until it was dismissed.
///
/// **And while a pre-run dialog is up**, which is not the same condition and was found at the
/// keyboard rather than reasoned: a menu command is *not* swallowed by a window-modal sheet, so
/// this button ran, SwiftUI queued a second sheet, and the report appeared by itself when the
/// dialog was cancelled. The action calls a model method that re-checks the rule, because a rule
/// living only in a view modifier is one nothing automated can see.
///
/// It asks `AppModel.reportMayBeRaisedFromMenu`, which is deliberately **not** the question of
/// whether the report may be shown: the report a finished run produces is raised from `finishing`,
/// which is run-active. See that property.
private struct RunReportCommand: View {

    let model: AppModel

    var body: some View {
        Button("View Last Run Report") { model.reportRequestedFromMenu() }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!model.reportMayBeRaisedFromMenu)
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
        //
        // **One back** in increment 9: the registration, which this panel used to construct for
        // itself. The launch gate needs `register()` too, and two `HelperRegistration` instances
        // would be two registration states that can disagree — the same one-truth-two-views problem
        // this scene is a `Window` rather than a `WindowGroup` to avoid.
        HelperDiagnosticsView(helper: model.helper,
                              registration: model.registration,
                              runIsActive: model.runIsActive,
                              warningsSuppressed: $model.warningsSuppressed)
            .frame(minWidth: 560, minHeight: 480)
    }
}
