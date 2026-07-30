//
//  DeviceDiscovery.swift
//  USBDriveTester (app target — unprivileged)
//
//  The device list the GUI binds to: what is connected, what is selected, and keeping
//  both current as drives come and go (FR-DEV-1/2/3/4/7).
//
//  Everything with a decision in it has been pushed out of this type and into pure,
//  tested code — ordering into `BSDDeviceName`, selection into `DeviceSelectionPolicy`,
//  usability into `DiscoveredDevice`, enumeration behind `DeviceSource`. What is left
//  here is sequencing and state, which is what makes the store itself testable against
//  a stub source with no hardware attached.
//
//  ## Freezing during a run (FR-DEV-7)
//
//  The list refreshes only while no run is active. During a run the device set is
//  frozen: re-sorting the list, or worse moving the selection, underneath a run in
//  progress would be at best confusing and at worst dangerous. Hot-unplug of the
//  device *under test* is a different problem with a different answer, handled in
//  Step 12 (FR-DEV-8).
//
//  A change arriving while frozen is remembered, not discarded, and applied when the
//  run ends — otherwise the list silently misrepresents the machine for as long as the
//  app stays open afterwards.
//
//  Until Step 11 builds the run-control state machine, `isRunActive` is driven by the
//  interim simulated-run toggle that Step 4 already introduced for the uninstall guard.
//

import Foundation
import Observation
import os

private let log = Logger(subsystem: HelperIdentity.loggingSubsystem, category: "discovery")

@MainActor
@Observable
final class DeviceDiscovery {

    /// Connected USB whole disks, in presentation order (FR-DEV-1, FR-DEV-2).
    private(set) var devices: [DiscoveredDevice] = []

    /// Registry entry ID of the selected device (FR-DEV-3, FR-DEV-4).
    private(set) var selectedDeviceID: UInt64?

    /// When the list was last rebuilt. Shown in the UI so a stale list is visible as
    /// stale rather than merely wrong.
    private(set) var lastRefresh: Date?

    /// Whether discovery is currently frozen because a run is in progress.
    private(set) var isRunActive = false

    /// Set when a hot-plug event arrives while frozen, so it can be applied on unfreeze.
    private(set) var hasPendingChange = false

    private let source: DeviceSource
    private var isObserving = false

    /// - Parameter source: Defaults to the real IOKit enumerator; tests inject a stub.
    init(source: DeviceSource = IOKitDeviceEnumerator()) {
        self.source = source
    }

    deinit {
        // `stop()` is main-actor isolated and deinit is not; the source's own teardown
        // is safe to call directly and is idempotent.
        source.stopObserving()
    }

    // MARK: - Lifecycle

    /// Enumerate once and begin watching for changes (FR-DEV-1, FR-DEV-7).
    func start() {
        refresh(reason: "initial enumeration")

        guard !isObserving else { return }
        isObserving = true
        source.startObserving { [weak self] in
            self?.deviceSetChanged()
        }
    }

    /// Stop watching. Called when the app goes away; the store is otherwise long-lived.
    func stop() {
        guard isObserving else { return }
        isObserving = false
        source.stopObserving()
    }

    // MARK: - Refresh

    /// Rebuild the list from the source and re-apply the selection policy.
    ///
    /// Runs whatever the freeze state — the freeze governs *automatic* refreshes, and
    /// an explicit call (the Refresh button, or Step 12's post-device-loss re-run of
    /// discovery, FR-DEV-8) is a deliberate act.
    func refresh(reason: String = "manual refresh") {
        let previous = devices
        let current = source.enumerateDevices()

        let change = DiscoveredDevice.changes(from: previous, to: current)
        if !change.isEmpty {
            log.notice("\(reason, privacy: .public): \(change.logDescription, privacy: .public)")
        }

        devices = current
        selectedDeviceID = DeviceSelectionPolicy.selection(in: current,
                                                           previousSelection: selectedDeviceID)
        lastRefresh = Date()
        hasPendingChange = false
    }

    /// A device arrived or departed (FR-DEV-7). Delivered on the main queue, already
    /// coalesced by the source.
    private func deviceSetChanged() {
        guard !isRunActive else {
            hasPendingChange = true
            log.notice("device change ignored while a run is active; will refresh when it ends")
            return
        }
        refresh(reason: "device connect/disconnect")
    }

    // MARK: - Selection (FR-DEV-4)

    /// The selected device, or `nil` when nothing is selected — including the moment
    /// after the selected device has been unplugged.
    var selectedDevice: DiscoveredDevice? {
        DeviceSelectionPolicy.device(withID: selectedDeviceID, in: devices)
    }

    /// Change the selection in response to the user choosing a row.
    ///
    /// Ignores ids that are not in the current list rather than clearing the selection:
    /// a stale tap arriving just as a device disappears should be a no-op, not a
    /// deselection the user did not ask for.
    func select(_ id: UInt64) {
        guard devices.contains(where: { $0.registryEntryID == id }) else { return }
        guard id != selectedDeviceID else { return }
        selectedDeviceID = id

        if let device = DeviceSelectionPolicy.device(withID: id, in: devices) {
            log.notice("""
                       selected \(device.bsdName.rawValue, privacy: .public) \
                       (\(device.capacityDescription, privacy: .public))
                       """)
        }
    }

    // MARK: - Run state (FR-DEV-7)

    /// Freeze or unfreeze automatic refreshes.
    ///
    /// Unfreezing applies any change that arrived while frozen, so the list is correct
    /// again the moment it is allowed to be.
    func setRunActive(_ active: Bool) {
        guard active != isRunActive else { return }
        isRunActive = active
        log.notice("discovery \(active ? "frozen (run active)" : "resumed", privacy: .public)")

        if !active, hasPendingChange {
            refresh(reason: "applying device changes deferred during the run")
        }
    }

    // MARK: - Presentation

    /// Why the list is not currently updating itself, or `nil` when it is.
    var freezeExplanation: String? {
        guard isRunActive else { return nil }
        return hasPendingChange
            ? "A run is in progress, so the list is frozen. Devices have connected or "
            + "disconnected since it started; the list updates when the run ends."
            : "A run is in progress, so the list will not update until it ends."
    }

    /// Summary line for the list header.
    var summary: String {
        switch devices.count {
        case 0:  return "No USB drives connected"
        case 1:  return "1 USB drive"
        default: return "\(devices.count) USB drives"
        }
    }
}
