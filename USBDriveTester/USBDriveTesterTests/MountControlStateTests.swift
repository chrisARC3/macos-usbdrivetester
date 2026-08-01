//
//  MountControlStateTests.swift
//  Exercises the Mount All / Unmount All control's label and enabled-state
//  (FR-SAFE-5, FR-SAFE-7).
//
//  The whole truth table is covered, for the same reason `UninstallPreconditionTests`
//  covers its cross-product: FR-SAFE-5's substance is that **the label and the action
//  always agree**, and that is a property of the table as a whole, not of any one row.
//  A test suite that only checked the two rows someone happened to click would let a
//  later edit invert a corner of it silently.
//
//  Two rows are load-bearing and easy to "tidy" into something more obvious:
//
//    * **No selection shows "Unmount All", not "Mount All".** Nothing is mounted when
//      nothing is selected, so the naive derivation gives "Mount All" — and FR-SAFE-5
//      names "Unmount All" as the default label for exactly that case.
//    * **A partially-mounted device shows "Unmount All".** Any mounted volume selects
//      the unmount direction (decision 6, confirmed with the user 2026-07-30).
//

import Testing
import Foundation
@testable import USBDriveTester

struct MountControlStateTests {

    /// The ordinary case: a selected drive with nothing else going on.
    private func idle(mountedVolumeCount: Int) -> MountControlState {
        MountControlPolicy.state(hasSelection: true,
                                 mountedVolumeCount: mountedVolumeCount,
                                 isRunActive: false,
                                 helperHoldsDevice: false,
                                 isOperationInFlight: false)
    }

    // MARK: - Direction (FR-SAFE-5)

    @Test func anyMountedVolumeSelectsUnmount() {
        #expect(idle(mountedVolumeCount: 1).direction == .unmountAll)
    }

    @Test func nothingMountedSelectsMount() {
        #expect(idle(mountedVolumeCount: 0).direction == .mountAll)
    }

    /// A device with several volumes, only some of them mounted, reads "Unmount All".
    /// The other reading — "Mount All, because not everything is mounted" — is defensible
    /// and was explicitly not chosen.
    @Test func partiallyMountedDeviceReadsUnmountAll() {
        #expect(idle(mountedVolumeCount: 1).direction == .unmountAll)
        #expect(idle(mountedVolumeCount: 2).direction == .unmountAll)
        #expect(idle(mountedVolumeCount: 7).direction == .unmountAll)
    }

    @Test func labelAlwaysMatchesTheDirection() {
        #expect(idle(mountedVolumeCount: 1).label == "Unmount All")
        #expect(idle(mountedVolumeCount: 0).label == "Mount All")
    }

    // MARK: - No selection (FR-SAFE-5)

    @Test func noSelectionDisablesTheControl() {
        let state = MountControlPolicy.state(hasSelection: false,
                                             mountedVolumeCount: 0,
                                             isRunActive: false,
                                             helperHoldsDevice: false,
                                             isOperationInFlight: false)
        #expect(!state.isEnabled)
    }

    /// The load-bearing row. `mountedVolumeCount` is 0 with no selection, so the naive
    /// derivation produces "Mount All"; FR-SAFE-5 requires "Unmount All".
    @Test func noSelectionShowsTheDefaultUnmountLabel() {
        let state = MountControlPolicy.state(hasSelection: false,
                                             mountedVolumeCount: 0,
                                             isRunActive: false,
                                             helperHoldsDevice: false,
                                             isOperationInFlight: false)
        #expect(state.direction == .unmountAll)
        #expect(state.label == "Unmount All")
    }

    // MARK: - FR-SAFE-7 — disabled during a run or while the helper holds the device

    @Test func activeRunDisablesTheControl() {
        let state = MountControlPolicy.state(hasSelection: true,
                                             mountedVolumeCount: 0,
                                             isRunActive: true,
                                             helperHoldsDevice: false,
                                             isOperationInFlight: false)
        #expect(!state.isEnabled)
    }

    /// Distinct from an active run on purpose: the helper can hold the claim before a run
    /// starts and after one ends, and mounting the device then would violate NFR-REL-3
    /// just the same.
    @Test func helperHoldingTheDeviceDisablesTheControl() {
        let state = MountControlPolicy.state(hasSelection: true,
                                             mountedVolumeCount: 0,
                                             isRunActive: false,
                                             helperHoldsDevice: true,
                                             isOperationInFlight: false)
        #expect(!state.isEnabled)
    }

    @Test func operationInFlightDisablesTheControl() {
        let state = MountControlPolicy.state(hasSelection: true,
                                             mountedVolumeCount: 1,
                                             isRunActive: false,
                                             helperHoldsDevice: false,
                                             isOperationInFlight: true)
        #expect(!state.isEnabled)
    }

    /// Disabling must not change what the button says it would do. A control that
    /// silently flips direction while unavailable would flip back when re-enabled, and
    /// the user would have watched it change for no reason they can account for.
    @Test func disablingDoesNotChangeTheDirection() {
        let mountedRunning = MountControlPolicy.state(hasSelection: true,
                                                      mountedVolumeCount: 2,
                                                      isRunActive: true,
                                                      helperHoldsDevice: false,
                                                      isOperationInFlight: false)
        #expect(mountedRunning.direction == .unmountAll)

        let unmountedHeld = MountControlPolicy.state(hasSelection: true,
                                                     mountedVolumeCount: 0,
                                                     isRunActive: false,
                                                     helperHoldsDevice: true,
                                                     isOperationInFlight: false)
        #expect(unmountedHeld.direction == .mountAll)
    }

    // MARK: - Decision 7 — nothing mountable does not disable

    /// An unmounted device keeps the control enabled even though we cannot know from
    /// here whether anything on it is mountable. DiskArbitration's `VolumeMountable`
    /// flag can be conservative for third-party filesystems, and a control that greys
    /// out for a reason the user cannot see reads as a bug. `VolumeMounter` reports
    /// afterwards that there was nothing to mount.
    @Test func unmountedDeviceStaysEnabled() {
        let state = idle(mountedVolumeCount: 0)
        #expect(state.isEnabled)
        #expect(state.direction == .mountAll)
    }

    // MARK: - Every disabled state explains itself (NFR-USE-8)

    /// Dimming is not a message. Step 4 produced a defect from exactly this: two
    /// disabled buttons rendered as faint pills and were reported as not present at all.
    @Test func everyDisabledStateCarriesAReason() {
        let disabledStates = [
            MountControlPolicy.state(hasSelection: false, mountedVolumeCount: 0,
                                     isRunActive: false, helperHoldsDevice: false,
                                     isOperationInFlight: false),
            MountControlPolicy.state(hasSelection: true, mountedVolumeCount: 1,
                                     isRunActive: true, helperHoldsDevice: false,
                                     isOperationInFlight: false),
            MountControlPolicy.state(hasSelection: true, mountedVolumeCount: 1,
                                     isRunActive: false, helperHoldsDevice: true,
                                     isOperationInFlight: false),
            MountControlPolicy.state(hasSelection: true, mountedVolumeCount: 1,
                                     isRunActive: false, helperHoldsDevice: false,
                                     isOperationInFlight: true),
        ]

        for state in disabledStates {
            #expect(!state.isEnabled)
            #expect(state.disabledReason?.isEmpty == false,
                    "a disabled control must say why it is disabled")
        }
    }

    @Test func enabledStateCarriesNoReason() {
        #expect(idle(mountedVolumeCount: 1).disabledReason == nil)
        #expect(idle(mountedVolumeCount: 0).disabledReason == nil)
    }

    // MARK: - Exhaustive matrix

    /// Guards the property FR-SAFE-5 is actually about: across every combination of
    /// inputs, the label agrees with the direction, and enablement follows exactly the
    /// four disabling conditions and nothing else.
    @Test func fullMatrixMatchesTheSpecifiedTable() {
        for hasSelection in [true, false] {
            for mountedVolumeCount in [0, 1, 3] {
                for isRunActive in [true, false] {
                    for helperHoldsDevice in [true, false] {
                        for isOperationInFlight in [true, false] {
                            let state = MountControlPolicy.state(
                                hasSelection: hasSelection,
                                mountedVolumeCount: mountedVolumeCount,
                                isRunActive: isRunActive,
                                helperHoldsDevice: helperHoldsDevice,
                                isOperationInFlight: isOperationInFlight)

                            // The label and the action never disagree.
                            #expect(state.label == state.direction.label)

                            let shouldBeEnabled = hasSelection
                                && !isRunActive
                                && !helperHoldsDevice
                                && !isOperationInFlight
                            #expect(state.isEnabled == shouldBeEnabled,
                                    """
                                    selection=\(hasSelection) mounted=\(mountedVolumeCount) \
                                    run=\(isRunActive) held=\(helperHoldsDevice) \
                                    busy=\(isOperationInFlight)
                                    """)

                            let expectedDirection: MountControlDirection =
                                !hasSelection || mountedVolumeCount > 0 ? .unmountAll
                                                                        : .mountAll
                            #expect(state.direction == expectedDirection)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Accessibility (NFR-USE-8)

    @Test func accessibilityLabelNamesTheObjectNotJustTheVerb() {
        #expect(idle(mountedVolumeCount: 1).accessibilityLabel.contains("Unmount"))
        #expect(idle(mountedVolumeCount: 1).accessibilityLabel.contains("volumes"))
        #expect(idle(mountedVolumeCount: 0).accessibilityLabel.contains("Mount"))
        #expect(idle(mountedVolumeCount: 0).accessibilityLabel.contains("volumes"))
    }
}
