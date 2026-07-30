//
//  DeviceSelectionPolicy.swift
//  USBDriveTester (app target — unprivileged)
//
//  What is selected after the device list changes (FR-DEV-3, FR-DEV-4, FR-DEV-7).
//
//  Pure and side-effect-free, for the same reason `UninstallPrecondition` is: this is
//  a small decision with an easy-to-miss failure mode, and a small decision that lives
//  inline in a refresh callback is one nobody ever tests. The failure mode here is
//  specific — a live refresh (FR-DEV-7) that quietly moves the user's selection onto a
//  different physical drive between the moment they choose it and the moment they
//  press Start.
//
//  ## The rules
//
//  1. **Keep what the user chose**, if it is still connected. Re-selection is the
//     user's to make (FR-DEV-4); a device appearing or disappearing elsewhere in the
//     list is not a reason to override it.
//  2. Otherwise select the **first usable device** (FR-DEV-3), in the presentation
//     order of FR-DEV-2.
//  3. If nothing is usable, select the first device anyway, so the user sees it and
//     the reason it cannot be used rather than an empty detail pane.
//  4. An empty list selects nothing.
//
//  Identity is the IOKit registry entry ID, never the BSD name — see the note on
//  `DiscoveredDevice.registryEntryID` for why re-plugging a drive must *not* restore
//  the old selection.
//

import Foundation

/// Decides what should be selected after the device list is rebuilt.
nonisolated enum DeviceSelectionPolicy {

    /// - Parameters:
    ///   - devices: The new list, already in presentation order
    ///     (``DiscoveredDevice/sorted(_:)``).
    ///   - previousSelection: The registry entry ID selected before the refresh, if any.
    /// - Returns: The registry entry ID to select, or `nil` when there is nothing to
    ///   select.
    static func selection(in devices: [DiscoveredDevice],
                          previousSelection: UInt64?) -> UInt64? {

        // 1. The user's choice wins while the device it names is still present.
        if let previousSelection,
           devices.contains(where: { $0.registryEntryID == previousSelection }) {
            return previousSelection
        }

        // 2. Default to the first device that can actually be run (FR-DEV-3).
        if let firstUsable = devices.first(where: \.isSelectable) {
            return firstUsable.registryEntryID
        }

        // 3./4. Nothing usable: show the first device (and its problem), or nothing.
        return devices.first?.registryEntryID
    }

    /// Resolve a selection back to the device it names.
    ///
    /// Returns `nil` if the id is not in the list, which is the correct behaviour
    /// during the window where a selected device has just been unplugged: the caller
    /// shows "no device selected" rather than the stale details of a drive that is no
    /// longer attached.
    static func device(withID id: UInt64?, in devices: [DiscoveredDevice]) -> DiscoveredDevice? {
        guard let id else { return nil }
        return devices.first { $0.registryEntryID == id }
    }
}
