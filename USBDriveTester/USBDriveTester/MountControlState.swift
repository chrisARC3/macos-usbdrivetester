//
//  MountControlState.swift
//  USBDriveTester (app target — unprivileged)
//
//  The label and enabled-state of the single Mount All / Unmount All control
//  (FR-SAFE-5, FR-SAFE-7), as pure logic.
//
//  ## Why this is a type and not four conditionals in the view
//
//  FR-SAFE-5 does not merely require the control to exist — it specifies that **its
//  label and its action always agree**, and it was elevated C -> M on 2026-07-30 partly
//  for that reason. On a screen whose entire job is stopping the wrong drive from being
//  touched, a button reading "Mount All" that unmounts is worse than no button. So the
//  agreement is expressed once, as a value: the view renders `label` and calls
//  `direction`, and cannot get them out of step because it never computes either.
//
//  Written the same way as `UninstallPrecondition`: a small policy with a truth table,
//  pulled out where the whole table can be tested rather than left inline where only the
//  paths someone happened to click get exercised.
//
//  ## The rules, and where each comes from
//
//    * **No device selected** -> disabled, label "Unmount All" (FR-SAFE-5, which names
//      that as the default label for the empty case specifically).
//    * **Any volume mounted** -> "Unmount All". A *partially* mounted device therefore
//      reads "Unmount All"; any mounted volume selects the unmount direction (decision 6,
//      confirmed with the user 2026-07-30).
//    * **No volume mounted** -> "Mount All". Mounting is a genuine addition to the
//      baselined spec, not a clarification — a drive left unmounted after a test used to
//      have to be remounted through Disk Utility.
//    * **A run is active, or the helper holds exclusive access** -> disabled (FR-SAFE-7).
//      Derived rather than requested: mounting the device under test would violate
//      NFR-REL-3 directly.
//
//  Note what is *not* a rule: a device with nothing mountable on it is **not** disabled
//  (decision 7). The stated rule disables only the no-selection case, and DiskArbitration's
//  `VolumeMountable` flag can be conservative for third-party filesystems — so the control
//  stays live and `VolumeMounter` reports honestly afterwards that there was nothing to
//  mount. A control that greys out for a reason the user cannot see reads as a bug.
//
//  `nonisolated` throughout: the app target compiles with
//  SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, which would otherwise make even these
//  value types main-actor-isolated and their `Equatable` conformance unusable from the
//  non-isolated test target.
//

import Foundation

/// Which way the control will act when pressed.
nonisolated enum MountControlDirection: Equatable {

    /// Unmount every volume of the selected device.
    case unmountAll

    /// Mount every mountable volume of the selected device.
    case mountAll

    /// The button's title. The single source of the label, so the text shown and the
    /// action taken are the same decision (FR-SAFE-5).
    var label: String {
        switch self {
        case .unmountAll: return "Unmount All"
        case .mountAll:   return "Mount All"
        }
    }

    /// Spoken description for assistive technology, which needs the object as well as the verb.
    ///
    /// **No longer requirement-driven.** This cited NFR-USE-8 until 2026-08-11, when screen-reader
    /// support was removed from scope (user decision; see that document's amendment). Kept because
    /// removing a requirement is not a reason to make the product worse at something it already
    /// does — but nothing verifies it, and no step inherits an obligation to.
    var accessibilityLabel: String {
        switch self {
        case .unmountAll: return "Unmount all volumes on the selected drive"
        case .mountAll:   return "Mount all volumes on the selected drive"
        }
    }
}

/// Everything the view needs to render the control.
nonisolated struct MountControlState: Equatable {

    let direction: MountControlDirection
    let isEnabled: Bool

    /// Why the control is disabled, or `nil` when it is enabled.
    ///
    /// Non-optional in spirit: whenever `isEnabled` is false this is set, and the view
    /// shows it next to the control. Dimming is not a message (NFR-USE-8) — a lesson
    /// from Step 4, where two disabled buttons rendered as faint pills and were reported
    /// as missing entirely.
    let disabledReason: String?

    var label: String { direction.label }
    var accessibilityLabel: String { direction.accessibilityLabel }
}

/// Maps the app's state onto the control (FR-SAFE-5, FR-SAFE-7).
nonisolated enum MountControlPolicy {

    /// - Parameters:
    ///   - hasSelection: Whether a device is selected at all.
    ///   - mountedVolumeCount: How many of the selected device's volumes are mounted.
    ///     Comes from `DiscoveredDevice.mountedVolumeNames`, which live-updates through
    ///     the `VolumeChangeWatcher` added in Step 5 — so the label re-evaluates itself
    ///     when an action completes, with no extra plumbing.
    ///   - isRunActive: Whether a test run is in progress (FR-SAFE-7).
    ///   - helperHoldsDevice: Whether the helper currently holds the exclusive claim
    ///     (FR-SAFE-7). Distinct from `isRunActive`: the helper can hold a device before
    ///     a run starts and after one ends, and mounting it then would be just as wrong.
    ///   - isOperationInFlight: Whether a mount/unmount is already running. Not a
    ///     requirement, but a second press mid-operation would race the first.
    static func state(hasSelection: Bool,
                      mountedVolumeCount: Int,
                      isRunActive: Bool,
                      helperHoldsDevice: Bool,
                      isOperationInFlight: Bool) -> MountControlState {

        // Direction first, so it is decided one way for every branch below. With no
        // selection there is no mount state to track, and FR-SAFE-5 names "Unmount All"
        // as the label for that case — so it is pinned here rather than falling out of
        // `mountedVolumeCount == 0`, which would show "Mount All".
        let direction: MountControlDirection =
            !hasSelection || mountedVolumeCount > 0 ? .unmountAll : .mountAll

        func disabled(_ reason: String) -> MountControlState {
            MountControlState(direction: direction, isEnabled: false, disabledReason: reason)
        }

        guard hasSelection else {
            return disabled("Select a drive to mount or unmount its volumes.")
        }
        guard !isRunActive else {
            return disabled("A test run is in progress. Mounting or unmounting the drive "
                          + "under test is not possible while it runs.")
        }
        guard !helperHoldsDevice else {
            return disabled("The helper holds exclusive access to this drive. Release it "
                          + "before mounting or unmounting its volumes.")
        }
        guard !isOperationInFlight else {
            return disabled("Working…")
        }

        return MountControlState(direction: direction, isEnabled: true, disabledReason: nil)
    }
}
