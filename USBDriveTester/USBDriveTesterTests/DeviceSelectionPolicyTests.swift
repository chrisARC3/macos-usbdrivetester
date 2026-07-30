//
//  DeviceSelectionPolicyTests.swift
//  FR-DEV-3/4/7 — what is selected after the list changes.
//
//  The case worth the most here is the last one: a drive that is unplugged and plugged
//  back in comes back with the same BSD name but a **new** registry entry ID, and must
//  NOT silently reclaim the selection. Keying selection on the BSD name would look
//  identical in every other test in this file and would quietly transfer the user's
//  choice onto whatever device happened to take that name — which, on a machine where
//  the list also contains the drive holding your source tree, is the one failure this
//  policy exists to prevent.
//

import Testing
import Foundation
@testable import USBDriveTester

struct DeviceSelectionPolicyTests {

    /// The list as discovery presents it: disk4 (scratch), disk6 (source tree),
    /// disk8 (backup).
    private let devices = DiscoveredDevice.sorted([DeviceFixtures.largeDrive,
                                                   DeviceFixtures.workingDrive,
                                                   DeviceFixtures.testDrive])

    // MARK: - Default selection (FR-DEV-3)

    @Test func selectsTheFirstDeviceWhenNothingWasSelected() {
        let selection = DeviceSelectionPolicy.selection(in: devices, previousSelection: nil)
        #expect(selection == DeviceFixtures.testDrive.id)
    }

    @Test func selectsNothingFromAnEmptyList() {
        #expect(DeviceSelectionPolicy.selection(in: [], previousSelection: nil) == nil)
    }

    @Test func selectsNothingFromAnEmptyListEvenWithAPreviousSelection() {
        #expect(DeviceSelectionPolicy.selection(in: [], previousSelection: 0x4000) == nil)
    }

    /// "First" means first *usable*: pre-selecting a device that cannot be run would
    /// present the user with a start button that can never be pressed.
    @Test func skipsAnUnusableFirstDevice() {
        let broken = DeviceFixtures.device(id: 0x0001, bsdName: "disk1", logicalBlockSize: 2048)
        let list = DiscoveredDevice.sorted([DeviceFixtures.testDrive, broken])
        #expect(list.first?.id == broken.id)

        let selection = DeviceSelectionPolicy.selection(in: list, previousSelection: nil)
        #expect(selection == DeviceFixtures.testDrive.id)
    }

    /// When nothing is usable the first device is still selected, so the user sees it
    /// and the reason it cannot be used rather than a blank detail pane.
    @Test func fallsBackToTheFirstDeviceWhenNoneAreUsable() {
        let brokenA = DeviceFixtures.device(id: 0x1, bsdName: "disk1", logicalBlockSize: 2048)
        let brokenB = DeviceFixtures.device(id: 0x2, bsdName: "disk2", sizeBytes: 0)
        let list = DiscoveredDevice.sorted([brokenB, brokenA])

        let selection = DeviceSelectionPolicy.selection(in: list, previousSelection: nil)
        #expect(selection == brokenA.id)
    }

    // MARK: - Preserving the user's choice (FR-DEV-4, FR-DEV-7)

    @Test func keepsTheSelectionWhenTheDeviceIsStillPresent() {
        let selection = DeviceSelectionPolicy.selection(in: devices,
                                                        previousSelection: DeviceFixtures.largeDrive.id)
        #expect(selection == DeviceFixtures.largeDrive.id)
    }

    /// A device appearing elsewhere in the list is not a reason to move the selection,
    /// even when the newcomer sorts ahead of it.
    @Test func anotherDeviceAppearingDoesNotStealTheSelection() {
        let existing = [DeviceFixtures.workingDrive, DeviceFixtures.largeDrive]
        let afterHotplug = DiscoveredDevice.sorted(existing + [DeviceFixtures.testDrive])

        let selection = DeviceSelectionPolicy.selection(in: afterHotplug,
                                                        previousSelection: DeviceFixtures.workingDrive.id)
        #expect(selection == DeviceFixtures.workingDrive.id)
    }

    @Test func keepsASelectionEvenOnAnUnusableDevice() {
        // The user may deliberately select an unusable device to read why it is
        // unusable; a refresh must not yank them off it.
        let broken = DeviceFixtures.device(id: 0x1, bsdName: "disk1", logicalBlockSize: 2048)
        let list = DiscoveredDevice.sorted([DeviceFixtures.testDrive, broken])

        let selection = DeviceSelectionPolicy.selection(in: list, previousSelection: broken.id)
        #expect(selection == broken.id)
    }

    @Test func fallsBackWhenTheSelectedDeviceIsUnplugged() {
        let remaining = DiscoveredDevice.sorted([DeviceFixtures.workingDrive,
                                                 DeviceFixtures.largeDrive])
        let selection = DeviceSelectionPolicy.selection(in: remaining,
                                                        previousSelection: DeviceFixtures.testDrive.id)
        #expect(selection == DeviceFixtures.workingDrive.id)
    }

    @Test func selectsNothingWhenTheLastDeviceIsUnplugged() {
        #expect(DeviceSelectionPolicy.selection(in: [],
                                                previousSelection: DeviceFixtures.testDrive.id) == nil)
    }

    // MARK: - The replug case

    /// Same BSD name, new registry object. The selection must **not** transfer: the
    /// device the user chose is gone, and what is there now is a different physical
    /// enumeration of it (or a different drive entirely, since BSD names are reused).
    @Test func aRepluggedDriveDoesNotInheritTheOldSelection() {
        let original = DeviceFixtures.device(id: 0xAAAA, bsdName: "disk4")
        let after = DeviceFixtures.device(id: 0xBBBB, bsdName: "disk4")
        let list = [DeviceFixtures.workingDrive, after].sorted { $0.bsdName < $1.bsdName }

        let selection = DeviceSelectionPolicy.selection(in: list, previousSelection: original.id)

        // It lands on the new disk4 only because that is the first usable device, not
        // because it carried the old selection across.
        #expect(selection == after.id)
        #expect(selection != original.id)
    }

    /// The same replug where the previous selection was a *different* drive: the
    /// choice must survive untouched.
    @Test func aRepluggedDriveDoesNotDisturbAnUnrelatedSelection() {
        let after = DeviceFixtures.device(id: 0xBBBB, bsdName: "disk4")
        let list = DiscoveredDevice.sorted([DeviceFixtures.workingDrive, after])

        let selection = DeviceSelectionPolicy.selection(in: list,
                                                        previousSelection: DeviceFixtures.workingDrive.id)
        #expect(selection == DeviceFixtures.workingDrive.id)
    }

    // MARK: - Resolution

    @Test func resolvesASelectionToItsDevice() {
        let device = DeviceSelectionPolicy.device(withID: DeviceFixtures.testDrive.id,
                                                  in: devices)
        #expect(device?.bsdName.rawValue == "disk4")
    }

    @Test func resolvesNothingForNoSelection() {
        #expect(DeviceSelectionPolicy.device(withID: nil, in: devices) == nil)
    }

    /// During the window between a device disappearing and the selection being
    /// recomputed, the caller must show "nothing selected" rather than the stale
    /// details of a drive that is no longer attached.
    @Test func resolvesNothingForADeviceThatHasGone() {
        #expect(DeviceSelectionPolicy.device(withID: 0xDEAD, in: devices) == nil)
    }
}
