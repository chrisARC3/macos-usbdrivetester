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
                                // Narrower than `isRunActive` at both ends: `starting` has written
                                // nothing, and from `finishing` the figures belong to the report.
                                // `paused` IS included — the claim is held and the figures are this
                                // run's, and hiding them was the defect found on 2026-08-18.
                                isRunning: model.runControl?.hasLiveSession ?? false,
                                linkSpeedCode: model.runControl?.linkSpeedCode ?? -1,
                                deviceName: model.runControl?.lastRunDevice?.bsdNameAtRunTime,
                                deviceSerial: model.runControl?.lastRunDevice?.usbSerialNumber,
                                startedAt: model.runControl?.lastRunStartedAt)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        // **There is no minimum height here any more, and its absence is the point** (Step 11
        // increment 7).
        //
        // What stood here was `minHeight: 760`, measured once against the three-volume fixture and
        // then asserted. The comment it carried recorded that the number had **expired twice** —
        // 700 was true when written and false once Step 10 added the mounted-volumes row;
        // re-measured in increment 5; false again the moment increment 6 put two picker rows above
        // Start. Each expiry was silent, because nothing recomputes a literal. It had expired a
        // third time before it was removed: at 760 the `starting` state wanted 775 and clipped.
        //
        // Now each pane that can scroll declares **its own floor** — `WindowMetrics` — and SwiftUI
        // sums them with the blocks that cannot scroll to get the window's minimum. Adding a row
        // moves that minimum by construction. `scripts/window-fit-check.sh` asks the real view
        // hierarchy what limits it hands a window and fails if they stop fitting a 13.3-inch Mac,
        // so the number is checked without ever being written down.
        //
        // Worth being clear about what this did and did not do. It was **never** what made the run
        // controls reachable: that is their being outside every scroll region, which still holds
        // by construction — this view has no `ScrollView` of its own, and `RunControlsView` is a
        // direct child of the stack rather than content inside either neighbouring pane. A height
        // minimum could not have delivered that anyway, since any fixed number is a threshold some
        // drive crosses: the block above grows with the selected drive's mounted-volume count, and
        // the list above *that* grows with how many drives are attached (measured at 168 pt
        // between one drive and six).
        .frame(minWidth: WindowMetrics.minimumContentWidth)
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
