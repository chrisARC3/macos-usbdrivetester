//
//  ContentView.swift
//  USBDriveTester
//
//  The window's composition root as of Step 5: the device list is the primary UI, and
//  the Step 3/4 helper harness is demoted behind a disclosure (see
//  HelperDiagnosticsView, which is where that code now lives).
//
//  This is the point where the app stops being a gate harness and starts being the
//  tool. Steps 9, 11 and 14 add metrics, run controls and the mandatory pre-run
//  warnings around the device list rather than replacing it, and retire the diagnostics
//  section when the helper's real callers exist.
//
//  ## Two owners of one piece of state
//
//  `simulatedRunActive` lives here rather than in either child, because both need it:
//  it blocks uninstall (Step 4, NFR-REL-5) and freezes device discovery (Step 5,
//  FR-DEV-7). Step 11's state machine becomes the single authoritative source for both.
//

import SwiftUI

struct ContentView: View {

    /// Long-lived: discovery starts once and keeps itself current for the app's
    /// lifetime (FR-DEV-7).
    @State private var discovery = DeviceDiscovery()

    /// Stand-in for the run-control state machine built in Step 11.
    @State private var simulatedRunActive = false

    /// Collapsed by default. The helper is not needed to discover devices, so the
    /// registration state is not something the user should have to scroll past to
    /// reach the list.
    @State private var showDiagnostics = false

    /// One connection to the daemon for the whole app, shared by both children.
    ///
    /// Hoisted here in Step 6, when the device list gained its own reason to talk to the
    /// helper. It is not merely tidier than one connection per view: the helper releases a
    /// device when the connection that acquired it goes away (NFR-REL-5), so two
    /// connections would mean two owners, and a view being torn down could release a claim
    /// another part of the app believed it still held.
    @State private var helper = HelperConnection()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DeviceListView(discovery: discovery, helper: helper)

            Divider()

            DisclosureGroup(isExpanded: $showDiagnostics) {
                HelperDiagnosticsView(simulatedRunActive: $simulatedRunActive,
                                      helper: helper)
            } label: {
                Label("Privileged helper & diagnostics", systemImage: "wrench.and.screwdriver")
                    .font(.callout)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        // Raised from 620 in Step 6. The selected-device panel gained the mount control,
        // the readiness banner and the refusal message, and at 620 the refusal — the one
        // thing FR-SAFE-4 exists to communicate — started below the fold. Step 4 hit the
        // same class of defect: a control the user has to go looking for is one they
        // report as missing.
        .frame(minWidth: 640, minHeight: 720)
        .onAppear { discovery.start() }
        .onDisappear { discovery.stop() }
        // Keeps the two consumers of the run-state stand-in in step. Step 11 removes
        // this by making the state machine the one source both read.
        .onChange(of: simulatedRunActive) { _, isActive in
            discovery.setRunActive(isActive)
        }
    }
}

#Preview {
    ContentView()
}
