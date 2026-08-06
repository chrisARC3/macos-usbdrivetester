//
//  ContentView.swift
//  USBDriveTester
//
//  The main window's composition root: the device list is the primary UI, with Step 9's live
//  metrics panel beneath it.
//
//  This is the point where the app stops being a gate harness and starts being the tool. Steps 11
//  and 14 add run controls and the mandatory pre-run warnings around the device list rather than
//  replacing it.
//
//  ## What moved out, and why (Step 9, 2026-08-04)
//
//  The Step 3/4 helper harness used to sit here behind a disclosure. It now has **its own
//  window** (`USBDriveTesterApp`): between the device list, the selected-device detail, the mount
//  controls and the metrics panel, one column had stopped being able to hold everything.
//
//  Shared state went with it, into `AppModel`. That is not tidiness — the bounded cycle is started
//  from the diagnostics window and displayed here, and the helper ties a device claim to the
//  connection that acquired it (NFR-REL-5), so both windows must share exactly one
//  `HelperConnection`.
//

import SwiftUI

struct ContentView: View {

    /// Shared with the diagnostics window. See `AppModel`.
    @Environment(AppModel.self) private var model

    /// Brings this window forward when the quit confirmation appears. ⌘Q can be pressed while the
    /// *diagnostics* window is key, and a sheet on a window behind another one is a dialog the
    /// user never sees — which reads as the app ignoring ⌘Q. For a `Window` scene, asking to open
    /// an already-open window brings it forward.
    @Environment(\.openWindow) private var openWindow

    /// Long-lived, and specific to this window: discovery starts once and keeps itself current
    /// for the app's lifetime (FR-DEV-7). The diagnostics window has no use for it.
    @State private var discovery = DeviceDiscovery()

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 0) {
            if model.isWindingDown { windingDownBanner }

            DeviceListView(discovery: discovery, helper: model.helper)

            Divider()

            // Product surface (FR-METR-2/4/5/6). The control that starts a bounded pass is
            // scaffolding and lives in the diagnostics window; what a user must be able to *see*
            // during a run lives here.
            LiveRunMetricsPanel(helper: model.helper,
                                isRunning: model.cycleIsRunning,
                                linkSpeedCode: model.linkSpeedCode,
                                deviceName: model.lastRunDeviceName,
                                deviceSerial: model.lastRunDeviceSerial,
                                startedAt: model.lastRunStartedAt)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        // 700 is where the idle window's content stops being clipped — measured with
        // `scripts/render-ui.sh`, not guessed: at 620 the mount controls fall below the fold, and
        // a control the user has to go looking for is one they report as missing (Steps 4 and 6
        // both learned that the hard way, and FR-SAFE-4's refusal is the one message that must
        // never be clipped).
        //
        // Only 20 less than Step 6's 720, because moving the diagnostics form out bought back
        // roughly what the metrics panel spends. The panel is ~55 pt idle and ~300 pt with a run
        // in progress, so the *running* window wants nearer 900 — it is resizable, and if that
        // proves excessive the next lever is making the selected-device detail collapsible rather
        // than shrinking anything that carries a warning.
        .frame(minWidth: 640, minHeight: 700)
        .onAppear {
            discovery.start()
            // Seeded, not just observed — found by rendering, 2026-08-05. `onChange` fires on a
            // *transition*, and this store is built fresh with the view: a window that appears
            // while a run is already under way would therefore never be told, leaving the list
            // live during a run (FR-DEV-7) and, worse, leaving `select`/`deselect` willing to
            // change the selection — which releases the claim, under an active write.
            //
            // Reachable in the shipped app, and not only in the probe: the bounded cycle is
            // started from the *diagnostics* window, so the main window can be closed, a run
            // started, and the main window then reopened from the Window menu. `setRunActive`
            // ignores a value it already holds, so seeding costs nothing when nothing is running.
            discovery.setRunActive(model.runIsActive)
        }
        .onDisappear { discovery.stop() }
        // Freezing the device list during a run is FR-DEV-7: the list must not rebuild underneath
        // one. `runIsActive` is either source — the Step 4/5 stand-in toggle or a real cycle —
        // and Step 11 collapses both into the run-control state machine.
        .onChange(of: model.runIsActive) { _, isActive in
            discovery.setRunActive(isActive)
        }
        // Makes closing this window ask the same question ⌘Q asks (user decision 2026-08-05).
        // Installed from here because this view is what lives in the main window; the guard
        // itself is owned by `AppModel`, since `NSWindow.delegate` is weak.
        .background(MainWindowCloseGuardInstaller(closeGuard: model.mainWindowCloseGuard))
        .onChange(of: model.quitConfirmationIsPresented) { _, isPresented in
            if isPresented { openWindow(id: WindowID.main) }
        }
        .alert("A test run is in progress", isPresented: $model.quitConfirmationIsPresented) {
            // "Cancel and Quit" first, matching the decision's own wording. `.cancel` on
            // "Continue Testing" makes carrying on the default action — Return and Escape both
            // keep the run — which is the right way round for a dialog that can end one.
            Button("Cancel and Quit", role: .destructive) { model.cancelAndQuit() }
            Button("Continue Testing", role: .cancel) { model.continueTesting() }
        } message: {
            Text("""
                 Quitting cancels the run.

                 The operation already issued to the privileged helper cannot be called back, so \
                 the app will issue nothing further, wait for that operation to finish — normally \
                 a few seconds — release the drive, and then quit. Nothing beyond it is written.

                 A cancelled run cannot be resumed: testing this drive would have to start again \
                 from the beginning.
                 """)
        }
    }

    /// Shown while the app is waiting for the call boundary so it can quit.
    ///
    /// Not a spinner over an inert window: the metrics panel below keeps updating throughout,
    /// because the wind-down happens in the app's ordinary run loop (which is the reason
    /// `AppLifecycleDelegate` answers `.terminateCancel` rather than `.terminateLater`). The user
    /// watches the operation they are waiting on actually finish.
    private var windingDownBanner: some View {
        Label("""
              Quitting when the current operation finishes. No further work will be issued, and \
              the drive is released before the app closes.
              """, systemImage: "hourglass")
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.quaternary)
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
}
