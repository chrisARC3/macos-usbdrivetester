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

    /// Approximate height of one two-line device row, scaled with the user's text size.
    ///
    /// `@ScaledMetric` rather than a constant because the list's height is derived from
    /// it (see `deviceList`): a hard-coded row height would clip rows at larger Dynamic
    /// Type settings, which is a worse outcome than the dead space it is there to
    /// remove (NFR-USE-8).
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 46

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            deviceList
            Divider()
            detail
        }
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

    @ViewBuilder
    private var detail: some View {
        if let device = discovery.selectedDevice {
            selectedDetail(for: device)
        } else {
            Text(discovery.devices.isEmpty
                 ? "Connect a drive to see its details here."
                 : "No device is selected.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func selectedDetail(for device: DiscoveredDevice) -> some View {
        ScrollView {
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
                    // Not the mount guard — Step 6 owns that, helper-side, and is what
                    // actually refuses a run (FR-SAFE-1/2). This is the early warning,
                    // shown at the moment of selection rather than at the moment of
                    // starting.
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
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
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
