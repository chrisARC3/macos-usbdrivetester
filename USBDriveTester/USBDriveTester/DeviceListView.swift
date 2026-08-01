//
//  DeviceListView.swift
//  USBDriveTester (app target — unprivileged)
//
//  The device list and the selected-device detail (FR-DEV-1/3/4/6, NFR-USE-3).
//
//  Unlike the Step 3/4 harness this replaces at the top of the window, this is intended
//  to survive: Steps 9, 11 and 14 add run controls, metrics and the mandatory warnings
//  *around* it, not instead of it.
//
//  ## Design notes
//
//  A real `List` with a selection binding rather than buttons in a `Form` row. It is
//  the correct control for "choose exactly one of these", and it brings keyboard
//  navigation and VoiceOver selection semantics with it rather than requiring them to
//  be rebuilt (NFR-USE-8).
//
//  Every row leads with the **BSD name**, because that is the one identifier that ties
//  what this window says to `diskutil`, to `/dev/rdiskN`, and to what the helper will
//  be told to open. Model and capacity follow, so the row can be matched against the
//  label on the physical drive (FR-DEV-6). The detail panel below repeats the identity
//  in full and adds the exact byte count, which is what makes the rounded capacity safe
//  to show at all (NFR-USE-3).
//
//  Status is never carried by colour alone — every state has an icon and words
//  (NFR-USE-8), a habit Step 14 turns into a gate.
//

import SwiftUI

struct DeviceListView: View {

    let discovery: DeviceDiscovery

    /// Shared with `HelperDiagnosticsView` rather than opened again here: one
    /// `NSXPCConnection` to the daemon per app, so a connection dropping means one thing
    /// and the helper sees one client. It also matters for Step 6 specifically — the
    /// helper releases a claim when the connection that took it goes away, so two
    /// connections would mean two different owners of the same device.
    let helper: HelperConnection

    /// Approximate height of one two-line device row, scaled with the user's text size.
    ///
    /// `@ScaledMetric` rather than a constant because the list's height is derived from
    /// it (see `deviceList`): a hard-coded row height would clip rows at larger Dynamic
    /// Type settings, which is a worse outcome than the dead space it is there to
    /// remove (NFR-USE-8).
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 46

    // MARK: - Step 6 state (FR-SAFE-3/4/5/7)

    @State private var mounter = VolumeMounter()

    /// What the helper last said about the selected device. `nil` before the first check,
    /// or when the helper could not be reached.
    @State private var readiness: DeviceReadiness?

    /// Why the helper could not be asked, if it could not. Shown rather than swallowed:
    /// "no banner" and "the helper says everything is fine" must not look the same.
    @State private var readinessError: String?

    /// Whether the helper holds exclusive access to the selected device. Kept alongside
    /// `readiness` because acquire and release change it immediately, without waiting for
    /// the next check to come back.
    @State private var helperHoldsDevice = false

    @State private var mountOperationInFlight = false
    @State private var accessOperationInFlight = false

    /// The last mount/unmount or acquire/release result, shown verbatim.
    @State private var lastOutcome: OutcomeMessage?

    private struct OutcomeMessage: Equatable {
        let ok: Bool
        let text: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            deviceList
            Divider()
            detail
        }
        // The selected device changing invalidates everything below: a readiness answer
        // is about one device, and showing one device's mount state under another's name
        // is precisely the confusion NFR-USE-3 exists to prevent.
        .onChange(of: discovery.selectedDeviceID) { _, _ in
            readiness = nil
            readinessError = nil
            lastOutcome = nil
            helperHoldsDevice = false
            refreshReadiness()
        }
        // The mounted-volume set changing is the other input the banner depends on, and
        // it changes without the selection changing — the user unmounts in Disk Utility,
        // or macOS remounts after a claim is released.
        .onChange(of: discovery.selectedDevice?.mountedVolumeNames ?? []) { _, _ in
            refreshReadiness()
        }
        .onAppear { refreshReadiness() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(discovery.summary)
                    .font(.headline)
                Spacer()
                if let lastRefresh = discovery.lastRefresh {
                    Text("Updated \(lastRefresh, format: .dateTime.hour().minute().second())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Refresh") { discovery.refresh() }
            }

            // The list normally maintains itself (FR-DEV-7). Say so, so the Refresh
            // button does not imply that it does not.
            if let explanation = discovery.freezeExplanation {
                Label(explanation, systemImage: "pause.circle.fill")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("The list updates as drives are connected and disconnected.",
                      systemImage: "arrow.triangle.2.circlepath")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    // MARK: - The list

    private var deviceList: some View {
        Group {
            if discovery.devices.isEmpty {
                emptyState
            } else {
                List(discovery.devices, selection: selectionBinding) { device in
                    row(for: device)
                        .tag(device.registryEntryID)
                }
                .listStyle(.inset)
            }
        }
        .frame(height: listHeight)
    }

    /// Sized to its content, floored so the empty state has room and capped so a
    /// machine with many drives attached scrolls the list instead of squeezing the
    /// selected-device detail off the bottom of the window.
    ///
    /// An uncapped `List` inside a `VStack` absorbs every spare point of height, which
    /// put three drives above a large gap and pushed the detail — the part that stops
    /// the wrong drive being tested — down to the window edge.
    private var listHeight: CGFloat {
        guard !discovery.devices.isEmpty else { return 160 }
        let content = CGFloat(discovery.devices.count) * rowHeight + 16
        return min(max(content, rowHeight * 2), 260)
    }

    /// Bridges the store's `select(_:)` to a `List` selection binding. The store owns
    /// the selection and validates it, so the setter delegates rather than assigning.
    private var selectionBinding: Binding<UInt64?> {
        Binding(get: { discovery.selectedDeviceID },
                set: { if let id = $0 { discovery.select(id) } })
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No USB drives connected")
                .font(.headline)
            Text("""
                 Connect a USB mass-storage drive. Internal disks are deliberately \
                 excluded — this tool writes raw blocks, so only external USB devices \
                 are ever listed.
                 """)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private func row(for device: DiscoveredDevice) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: device.isSelectable
                  ? "externaldrive.fill"
                  : "externaldrive.trianglebadge.exclamationmark")
                .font(.title3)
                .foregroundStyle(device.isSelectable ? .primary : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayTitle)
                    .fontWeight(.medium)
                Text(rowSubtitle(for: device))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !device.isSelectable {
                Label("Unusable", systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: device))
    }

    /// `1.00 TB · Solid State · Test_Drive`
    private func rowSubtitle(for device: DiscoveredDevice) -> String {
        var parts = [device.capacityDescription]
        if let medium = device.mediumType {
            parts.append(medium)
        }
        if let volumes = device.mountedVolumesDescription {
            parts.append(volumes)
        }
        return parts.joined(separator: " · ")
    }

    /// Spoken as one phrase rather than as five separate fragments, and it says
    /// "unusable" in words rather than relying on the badge (NFR-USE-8).
    private func accessibilityLabel(for device: DiscoveredDevice) -> String {
        var label = "\(device.bsdName), \(device.modelDescription), "
                  + "\(device.capacityDescription)"
        if let volumes = device.mountedVolumesDescription {
            label += ", mounted volumes: \(volumes)"
        }
        if !device.isSelectable {
            label += ", cannot be tested"
        }
        return label
    }

    // MARK: - Selected-device detail

    /// The selected-device panel, and below it the safety controls.
    ///
    /// The safety section renders whether or not anything is selected. FR-SAFE-5
    /// specifies the no-selection state of the control — *disabled*, showing the default
    /// label "Unmount All" — and a control that is absent is not a control that is
    /// disabled. Showing it greyed out with a reason also answers the question a missing
    /// button raises ("can this app even do that?") without the user having to select a
    /// drive to find out.
    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let device = discovery.selectedDevice {
                    selectedDeviceIdentity(for: device)
                } else {
                    Text(discovery.devices.isEmpty
                         ? "Connect a drive to see its details here."
                         : "No device is selected.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()
                safetySection(for: discovery.selectedDevice)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func selectedDeviceIdentity(for device: DiscoveredDevice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
                // The selected device has to be unmistakable — this is the line that
                // stands between the user and testing the wrong drive (NFR-USE-3).
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Selected device")
                        .font(.headline)
                }

                Text(device.displayTitle)
                    .font(.title3.weight(.semibold))
                    .textSelection(.enabled)

                Grid(alignment: .leadingFirstTextBaseline,
                     horizontalSpacing: 12,
                     verticalSpacing: 6) {
                    detailRow("Capacity", device.capacityDescription)
                    detailRow("Exact size", device.exactCapacityDescription)
                    detailRow("Geometry", device.geometryDescription)
                    detailRow("Raw device", device.bsdName.rawDevicePath)
                    if let medium = device.mediumType {
                        detailRow("Medium", medium)
                    }
                    detailRow("Mounted volumes",
                              device.mountedVolumesDescription ?? "None mounted")
                }

                if let problem = device.geometryProblem {
                    Label(problem.description, systemImage: "xmark.octagon.fill")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if device.mountedVolumesDescription != nil {
                    // The app's own early warning, shown at the moment of selection. The
                    // guard that actually refuses a run is helper-side and speaks below.
                    Label("""
                          This drive has mounted volumes. A run cannot start until they \
                          are unmounted, and testing a drive you are using is not \
                          advisable.
                          """, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("""
                     Block size and block count are as reported by IOKit. The helper \
                     confirms them directly from the device before any run begins.
                     """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

    // MARK: - Safety: mount control and exclusive access (FR-SAFE-3/4/5/7)

    @ViewBuilder
    private func safetySection(for device: DiscoveredDevice?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                Text("Mounting & exclusive access")
                    .font(.headline)
            }

            readinessBanner

            let control = mountControlState(for: device)

            HStack(spacing: 10) {
                // FR-SAFE-5: one control, whose label and action always agree. Both come
                // from the same value, so the view cannot put them out of step.
                Button(control.label) {
                    if let device { performMountAction(control.direction, on: device) }
                }
                .disabled(!control.isEnabled)
                .accessibilityLabel(control.accessibilityLabel)

                Spacer()

                // Stand-in for Step 11's Start/Stop. The acquire is what actually decides
                // whether a run could begin, and it is the only thing that can detect
                // FR-SAFE-4(b) — so the gate for this step is driven from here until the
                // run-control state machine exists.
                Button("Acquire exclusive access") {
                    if let device { acquire(device) }
                }
                .disabled(device == nil || accessOperationInFlight || helperHoldsDevice)

                Button("Release") { release() }
                    .disabled(accessOperationInFlight || !helperHoldsDevice)
            }

            // Dimming is not a message (NFR-USE-8) — a lesson from Step 4, where two
            // disabled buttons were reported as missing entirely.
            if let reason = control.disabledReason {
                Label(reason, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let lastOutcome {
                Label(lastOutcome.text,
                      systemImage: lastOutcome.ok ? "checkmark.circle.fill"
                                                  : "xmark.octagon.fill")
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// What the helper says about the selected device, or why it could not be asked.
    @ViewBuilder
    private var readinessBanner: some View {
        if discovery.selectedDevice == nil {
            Label("Select a drive above to check whether it is ready for a test.",
                  systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if let readinessError {
            Label("""
                  The helper could not be asked whether this drive is ready: \
                  \(readinessError) Install and enable it under “Privileged helper & \
                  diagnostics” below — only the helper can permit a run.
                  """, systemImage: "questionmark.circle")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        } else if let readiness {
            VStack(alignment: .leading, spacing: 8) {
                Label(readiness.message,
                      systemImage: readiness.needsFullDiskAccess ? "hand.raised.fill"
                                 : helperHoldsDevice ? "lock.fill"
                                 : readiness.isReady ? "checkmark.shield"
                                                     : "exclamationmark.shield")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)

                // NFR-INST-4: the corrective control sits next to the message that asks
                // for it. A missing Full Disk Access grant is not something the user can
                // be expected to guess at from an errno, and it is a different pane from
                // the Login Items approval — so it gets its own button rather than a
                // generic "Open Settings".
                if readiness.needsFullDiskAccess {
                    Button("Open Full Disk Access settings…") {
                        HelperRegistration.openFullDiskAccessSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        } else {
            Label("Checking with the helper…", systemImage: "ellipsis.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// FR-SAFE-5/7, decided by pure logic in `MountControlPolicy` so the label, the
    /// action and the enabled state are one decision rather than three conditionals.
    private func mountControlState(for device: DiscoveredDevice?) -> MountControlState {
        MountControlPolicy.state(
            hasSelection: device != nil,
            mountedVolumeCount: device?.mountedVolumeNames.count ?? 0,
            isRunActive: discovery.isRunActive,
            helperHoldsDevice: helperHoldsDevice,
            isOperationInFlight: mountOperationInFlight)
    }

    // MARK: - Actions

    private func refreshReadiness() {
        guard let device = discovery.selectedDevice else {
            readiness = nil
            readinessError = nil
            return
        }
        helper.checkDeviceReadiness(bsdName: device.bsdName.rawValue) { result in
            // A late reply for a device that is no longer selected must not overwrite the
            // current one. The list rebuilds on every hot-plug, so this is not theoretical.
            guard discovery.selectedDevice?.bsdName == device.bsdName else { return }
            switch result {
            case .success(let value):
                readiness = value
                readinessError = nil
                helperHoldsDevice = value.helperHoldsThisDevice
            case .failure(let error):
                readiness = nil
                readinessError = error.localizedDescription
            }
        }
    }

    private func performMountAction(_ direction: MountControlDirection,
                                    on device: DiscoveredDevice) {
        mountOperationInFlight = true
        lastOutcome = nil

        let finish: (VolumeMountOutcome) -> Void = { outcome in
            mountOperationInFlight = false
            lastOutcome = OutcomeMessage(ok: outcome.isSuccess, text: outcome.message)
            // The device list live-updates through the VolumeChangeWatcher, so the label
            // re-evaluates itself; the readiness banner has to be asked again.
            refreshReadiness()
        }

        switch direction {
        case .unmountAll: mounter.unmountAll(device, completion: finish)
        case .mountAll:   mounter.mountAll(device, completion: finish)
        }
    }

    private func acquire(_ device: DiscoveredDevice) {
        accessOperationInFlight = true
        lastOutcome = nil

        helper.acquireDevice(bsdName: device.bsdName.rawValue) { result in
            accessOperationInFlight = false
            switch result {
            case .success(let acquisition):
                if case .acquired = acquisition {
                    helperHoldsDevice = true
                    lastOutcome = OutcomeMessage(ok: true, text: acquisition.message)
                } else {
                    // A refusal is the *expected* outcome whenever a volume is mounted,
                    // so it is reported as a refusal rather than as a malfunction — but
                    // never as a success.
                    lastOutcome = OutcomeMessage(ok: false, text: acquisition.message)
                }
            case .failure(let error):
                // No permissive reading: if the helper could not be reached, access was
                // not granted. Unlike uninstall, there is nothing safe about proceeding.
                lastOutcome = OutcomeMessage(
                    ok: false,
                    text: """
                          Exclusive access was NOT granted — the helper could not be \
                          reached: \(error.localizedDescription)
                          """)
            }
            refreshReadiness()
        }
    }

    private func release() {
        accessOperationInFlight = true
        lastOutcome = nil

        helper.releaseDevice { result in
            accessOperationInFlight = false
            helperHoldsDevice = false
            switch result {
            case .success(let message):
                lastOutcome = OutcomeMessage(ok: true, text: message
                    + " macOS will normally remount the volumes shortly.")
            case .failure(let error):
                lastOutcome = OutcomeMessage(
                    ok: false,
                    text: "Release failed: \(error.localizedDescription)")
            }
            refreshReadiness()
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
            Text(value)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
