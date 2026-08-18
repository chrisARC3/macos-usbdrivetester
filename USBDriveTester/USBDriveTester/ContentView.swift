//
//  ContentView.swift
//  USBDriveTester
//
//  The main window's composition root: the device list, the run controls, and Step 9's live
//  metrics panel.
//
//  This is the point where the app stops being a gate harness and starts being the tool.
//
//  ## What moved out, and why (Step 9, 2026-08-04)
//
//  The Step 3/4 helper harness used to sit here behind a disclosure. It now has **its own
//  window** (`USBDriveTesterApp`): between the device list, the selected-device detail, the run
//  controls and the metrics panel, one column had stopped being able to hold everything.
//
//  Shared state went with it, into `AppModel`. That is not tidiness — the helper ties a device
//  claim to the connection that acquired it (NFR-REL-5), so both windows must share exactly one
//  `HelperConnection`.
//
//  ## What moved IN, in Step 11 increment 5
//
//  The **run controls**, taking the place of the `Unmount All` / `Acquire exclusive access` /
//  `Release` controls this increment deletes. They sit here rather than inside `DeviceListView`
//  for one structural reason: this view has **no `ScrollView` at all**, so "the controls are not
//  below the fold" holds by construction rather than by a measured constant that expires silently
//  the next time the content above them grows. That has cost this project three times.
//
//  `DeviceDiscovery` moved the other way, out of here and into `AppModel` — see that file's header.
//  The run needs the selected drive from an escaping closure, and a closure created inside a
//  `View` struct captures what the view was built with.
//

import SwiftUI

struct ContentView: View {

    /// Shared with the diagnostics window. See `AppModel`.
    @Environment(AppModel.self) private var model

    /// Brings this window forward when the quit confirmation appears, and opens the report window
    /// when a run produces one. ⌘Q can be pressed while the *diagnostics* window is key, and a
    /// sheet on a window behind another one is a dialog the user never sees — which reads as the
    /// app ignoring ⌘Q. For a `Window` scene, asking to open an already-open window brings it
    /// forward.
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 0) {
            if model.isWindingDown { windingDownBanner }

            DeviceListView(discovery: model.discovery, helper: model.helper)

            Divider()

            // Pinned outside every scroll region, by construction. See this file's header and
            // `RunControlsView`'s.
            RunControlsView()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            // Product surface (FR-METR-2/4/5/6). What a user must be able to *see* during a run.
            LiveRunMetricsPanel(helper: model.helper,
                                // Narrower than `isRunActive`: during `starting` the drive is being
                                // unmounted and claimed and **nothing has been written**, so a
                                // panel calling itself running would label an empty session live.
                                isRunning: model.runControl?.isMeasuring ?? false,
                                linkSpeedCode: model.runControl?.linkSpeedCode ?? -1,
                                deviceName: model.runControl?.lastRunDevice?.bsdNameAtRunTime,
                                deviceSerial: model.runControl?.lastRunDevice?.usbSerialNumber,
                                startedAt: model.runControl?.lastRunStartedAt)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        // 700 is where the idle window's content stops being clipped — measured with
        // `scripts/render-ui.sh`, not guessed. **A measured constant is only true until the content
        // above it changes**, and this one has already expired once: it was true when written and
        // stopped being true when Step 10 added the mounted-volumes row. It is re-measured in this
        // increment because the run controls replaced the mount controls; what makes the controls
        // reachable is not this number but their being outside the scroll region.
        .frame(minWidth: 640, minHeight: 700)
        .onAppear {
            // Built here rather than in `AppModel.init` because its dependencies close over the
            // model, and a class cannot hand `self` to something it is still constructing. `nil`
            // until now is honest: no run can be in flight before the UI that starts one exists —
            // the same reasoning that wires `AppLifecycleDelegate` at `onAppear`.
            if model.runControl == nil {
                model.runControl = .live(model: model,
                                         openReport: { openWindow(id: WindowID.report) })
            }
            model.discovery.start()
            // Seeded, not just observed — found by rendering, 2026-08-05. `onChange` fires on a
            // *transition*, and a window that appears while a run is already under way would
            // therefore never be told, leaving the list live during a run (FR-DEV-7) and, worse,
            // leaving `select`/`deselect` willing to change the selection. `setRunActive` ignores a
            // value it already holds, so seeding costs nothing when nothing is running.
            model.discovery.setRunActive(model.runIsActive)
        }
        // Freezing the device list during a run is FR-DEV-7: the list must not rebuild underneath
        // one. One source now, where this used to be the union of a stand-in toggle and a cycle.
        .onChange(of: model.runIsActive) { _, isActive in
            model.discovery.setRunActive(isActive)
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

                 The run is stopped at the next chunk boundary — normally a few milliseconds — so \
                 nothing is left half-written. The drive is then released and the app quits.

                 A cancelled run cannot be resumed: testing this drive would have to start again \
                 from the beginning.
                 """)
        }
    }

    /// Shown while the app is waiting for the run to settle so it can quit.
    ///
    /// Not a spinner over an inert window: the metrics panel below keeps updating throughout,
    /// because the wind-down happens in the app's ordinary run loop (which is the reason
    /// `AppLifecycleDelegate` answers `.terminateCancel` rather than `.terminateLater`). The user
    /// watches the operation they are waiting on actually finish.
    private var windingDownBanner: some View {
        Label("""
              Quitting when the run stops. It is being stopped at the next chunk boundary, and the \
              drive is released before the app closes.
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
