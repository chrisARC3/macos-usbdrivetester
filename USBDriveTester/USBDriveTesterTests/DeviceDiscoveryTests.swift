//
//  DeviceDiscoveryTests.swift
//  FR-DEV-1/3/4/7 — the device-list store, exercised without any hardware.
//
//  `DeviceDiscovery` reaches the outside world through one seam, `DeviceSource`, so
//  substituting a stub makes the whole store testable: default selection, re-selection,
//  hot-plug refresh, and the freeze-during-a-run behaviour that would otherwise need a
//  running test and a drive in each hand to observe.
//
//  The freeze cases are the reason this file exists. FR-DEV-7 only says the list
//  updates "while no test is running", which is easy to implement as "drop the event"
//  — and that leaves the list quietly wrong for the rest of the session once the run
//  finishes. The deferred-refresh cases pin the intended behaviour down.
//

import Testing
import Foundation
@testable import USBDriveTester

/// A `DeviceSource` whose device set and change events are driven by the test.
///
/// Not actor-isolated, matching the real `IOKitDeviceEnumerator`: that type cannot be
/// `MainActor`-isolated because IOKit reaches it through a C function pointer, which a
/// global-actor-isolated function cannot be converted to. The stub has to sit on the
/// same side of that line or it would not be testing the same contract.
final class StubDeviceSource: DeviceSource {

    var devices: [DiscoveredDevice]
    private(set) var enumerationCount = 0
    private(set) var isObserving = false
    private var onChange: (() -> Void)?
    private var onDiskDisappeared: ((DisappearedDisk) -> Void)?

    init(devices: [DiscoveredDevice] = []) {
        self.devices = devices
    }

    func enumerateDevices() -> [DiscoveredDevice] {
        enumerationCount += 1
        return DiscoveredDevice.sorted(devices)
    }

    func startObserving(onChange: @escaping () -> Void,
                        onDiskDisappeared: @escaping (DisappearedDisk) -> Void) {
        self.onChange = onChange
        self.onDiskDisappeared = onDiskDisappeared
        isObserving = true
    }

    func stopObserving() {
        onChange = nil
        onDiskDisappeared = nil
        isObserving = false
    }

    /// Stand in for a disk leaving the machine (Step 12, FR-DEV-8, route (b)).
    func simulateDisappearance(of disk: DisappearedDisk) {
        onDiskDisappeared?(disk)
    }

    /// Stand in for a hot-plug notification: change the device set, then fire.
    func simulateChange(to devices: [DiscoveredDevice]) {
        self.devices = devices
        onChange?()
    }
}

@MainActor
struct DeviceDiscoveryTests {

    private func makeStore(_ devices: [DiscoveredDevice])
    -> (DeviceDiscovery, StubDeviceSource) {
        let source = StubDeviceSource(devices: devices)
        return (DeviceDiscovery(source: source), source)
    }

    // MARK: - Start-up (FR-DEV-1, FR-DEV-3)

    @Test func startEnumeratesAndDefaultSelectsTheFirstDevice() {
        let (store, _) = makeStore([DeviceFixtures.largeDrive,
                                    DeviceFixtures.workingDrive,
                                    DeviceFixtures.testDrive])
        store.start()

        #expect(store.devices.map(\.bsdName.rawValue) == ["disk4", "disk6", "disk8"])
        #expect(store.selectedDevice?.bsdName.rawValue == "disk4")
        #expect(store.lastRefresh != nil)
    }

    @Test func startBeginsObserving() {
        let (store, source) = makeStore([DeviceFixtures.testDrive])
        store.start()
        #expect(source.isObserving)
    }

    @Test func startIsIdempotent() {
        let (store, source) = makeStore([DeviceFixtures.testDrive])
        store.start()
        store.start()
        // Two enumerations (start refreshes each time) but only one observer.
        #expect(source.isObserving)
        #expect(source.enumerationCount == 2)
    }

    @Test func stopEndsObserving() {
        let (store, source) = makeStore([DeviceFixtures.testDrive])
        store.start()
        store.stop()
        #expect(!source.isObserving)
    }

    @Test func handlesNoDevicesConnected() {
        let (store, _) = makeStore([])
        store.start()
        #expect(store.devices.isEmpty)
        #expect(store.selectedDevice == nil)
        #expect(store.summary == "No USB drives connected")
    }

    @Test func summarisesTheDeviceCount() {
        let (one, _) = makeStore([DeviceFixtures.testDrive])
        one.start()
        #expect(one.summary == "1 USB drive")

        let (several, _) = makeStore([DeviceFixtures.testDrive, DeviceFixtures.largeDrive])
        several.start()
        #expect(several.summary == "2 USB drives")
    }

    // MARK: - Selection (FR-DEV-4)

    @Test func theUserCanChangeTheSelection() {
        let (store, _) = makeStore([DeviceFixtures.testDrive, DeviceFixtures.largeDrive])
        store.start()
        store.select(DeviceFixtures.largeDrive.id)
        #expect(store.selectedDevice?.bsdName.rawValue == "disk8")
    }

    /// A tap arriving just as a device disappears must be a no-op, not a deselection
    /// the user did not ask for.
    @Test func selectingAnAbsentDeviceIsIgnored() {
        let (store, _) = makeStore([DeviceFixtures.testDrive])
        store.start()
        store.select(0xDEAD)
        #expect(store.selectedDevice?.bsdName.rawValue == "disk4")
    }

    // MARK: - Deselection (added 2026-08-05)

    /// The defect this fixes: the view's binding dropped the `nil` a `List` reports on
    /// deselection, so the table deselected while the store went on naming the drive — and every
    /// pane below described a device the list no longer showed as chosen.
    @Test func deselectClearsTheSelection() {
        let (store, _) = makeStore([DeviceFixtures.testDrive, DeviceFixtures.largeDrive])
        store.start()
        #expect(store.selectedDevice != nil)

        store.deselect()

        #expect(store.selectedDeviceID == nil)
        #expect(store.selectedDevice == nil)
    }

    @Test func deselectingWithNothingSelectedIsANoOp() {
        let (store, _) = makeStore([])
        store.start()
        store.deselect()
        #expect(store.selectedDeviceID == nil)
    }

    /// Deselection is **not** durable across a device-set change, and that is a decision rather
    /// than an oversight: `refresh()` re-applies `DeviceSelectionPolicy`, and FR-DEV-3's default
    /// is about a *list* — a rebuilt list is a new one.
    ///
    /// Pinned by a test because it is surprising in use ("I deselected, then plugged in a drive,
    /// and something got selected"), and a surprising behaviour that only a comment defends is
    /// one the next person will quietly "fix".
    @Test func aDeviceSetChangeAfterDeselectingRestoresTheDefaultSelection() {
        let (store, source) = makeStore([DeviceFixtures.testDrive])
        store.start()
        store.deselect()
        #expect(store.selectedDeviceID == nil)

        source.simulateChange(to: [DeviceFixtures.testDrive, DeviceFixtures.largeDrive])

        #expect(store.selectedDevice?.bsdName.rawValue == "disk4")
    }

    /// A deselection must survive everything that is *not* a device-set change. The freeze is the
    /// interesting one: during a run the store defers refreshes, so a deselection made before a
    /// run must still be a deselection during it.
    @Test func deselectionSurvivesTheRunFreeze() {
        let (store, source) = makeStore([DeviceFixtures.testDrive])
        store.start()
        store.deselect()
        store.setRunActive(true)

        source.simulateChange(to: [DeviceFixtures.testDrive, DeviceFixtures.largeDrive])

        #expect(store.selectedDeviceID == nil, "a deferred change must not re-select mid-run")
    }

    // MARK: - The selection is frozen during a run (safety, added 2026-08-05)

    /// Since the helper's claim follows the selection, changing the selection during a run would
    /// release the drive **out from under an active write**. The refusal is enforced here rather
    /// than only in the view, because the view's `selectionDisabled` is a per-row modifier and a
    /// click in the blank space below the last row is not a row.
    ///
    /// Found the hard way: the modifier was first applied to the `List` container, where it
    /// compiles, renders, and does nothing at all.
    @Test func selectingADifferentDeviceDuringARunIsRefused() {
        let (store, _) = makeStore([DeviceFixtures.testDrive, DeviceFixtures.largeDrive])
        store.start()
        #expect(store.selectedDevice?.bsdName.rawValue == "disk4")

        store.setRunActive(true)
        store.select(DeviceFixtures.largeDrive.id)

        #expect(store.selectedDevice?.bsdName.rawValue == "disk4",
                "a run must pin the selection — the claim follows it")
    }

    @Test func deselectingDuringARunIsRefused() {
        let (store, _) = makeStore([DeviceFixtures.testDrive])
        store.start()
        store.setRunActive(true)

        store.deselect()

        #expect(store.selectedDeviceID != nil,
                "deselecting mid-run would release the device under an active write")
    }

    /// The freeze must lift with the run, or the list is left permanently unusable after the
    /// first one — the same failure the deferred-refresh cases exist to prevent.
    @Test func theSelectionIsChangeableAgainOnceTheRunEnds() {
        let (store, _) = makeStore([DeviceFixtures.testDrive, DeviceFixtures.largeDrive])
        store.start()
        store.setRunActive(true)
        store.select(DeviceFixtures.largeDrive.id)
        store.setRunActive(false)

        store.select(DeviceFixtures.largeDrive.id)

        #expect(store.selectedDevice?.bsdName.rawValue == "disk8")
    }

    // MARK: - Live refresh (FR-DEV-7)

    @Test func aConnectedDeviceAppearsInTheList() {
        let (store, source) = makeStore([DeviceFixtures.testDrive])
        store.start()

        source.simulateChange(to: [DeviceFixtures.testDrive, DeviceFixtures.largeDrive])

        #expect(store.devices.map(\.bsdName.rawValue) == ["disk4", "disk8"])
    }

    @Test func aDisconnectedDeviceLeavesTheList() {
        let (store, source) = makeStore([DeviceFixtures.testDrive, DeviceFixtures.largeDrive])
        store.start()

        source.simulateChange(to: [DeviceFixtures.largeDrive])

        #expect(store.devices.map(\.bsdName.rawValue) == ["disk8"])
    }

    @Test func aHotPlugDoesNotDisturbTheSelection() {
        let (store, source) = makeStore([DeviceFixtures.workingDrive])
        store.start()
        #expect(store.selectedDevice?.bsdName.rawValue == "disk6")

        // A drive that sorts *ahead* of the selection appears.
        source.simulateChange(to: [DeviceFixtures.workingDrive, DeviceFixtures.testDrive])

        #expect(store.devices.first?.bsdName.rawValue == "disk4")
        #expect(store.selectedDevice?.bsdName.rawValue == "disk6")
    }

    @Test func unpluggingTheSelectedDeviceMovesTheSelection() {
        let (store, source) = makeStore([DeviceFixtures.testDrive, DeviceFixtures.largeDrive])
        store.start()
        #expect(store.selectedDevice?.bsdName.rawValue == "disk4")

        source.simulateChange(to: [DeviceFixtures.largeDrive])

        #expect(store.selectedDevice?.bsdName.rawValue == "disk8")
    }

    @Test func unpluggingTheLastDeviceLeavesNothingSelected() {
        let (store, source) = makeStore([DeviceFixtures.testDrive])
        store.start()

        source.simulateChange(to: [])

        #expect(store.selectedDevice == nil)
        #expect(store.devices.isEmpty)
    }

    // MARK: - Frozen during a run (FR-DEV-7)

    @Test func discoveryFreezesWhileARunIsActive() {
        let (store, source) = makeStore([DeviceFixtures.testDrive])
        store.start()
        store.setRunActive(true)

        source.simulateChange(to: [DeviceFixtures.testDrive, DeviceFixtures.largeDrive])

        #expect(store.devices.map(\.bsdName.rawValue) == ["disk4"])
        #expect(store.hasPendingChange)
    }

    @Test func aFrozenListSaysWhyItIsNotUpdating() {
        let (store, _) = makeStore([DeviceFixtures.testDrive])
        store.start()
        #expect(store.freezeExplanation == nil)

        store.setRunActive(true)
        #expect(store.freezeExplanation?.contains("run is in progress") == true)
    }

    /// Discarding the event rather than deferring it leaves the list wrong for the
    /// rest of the session. It must catch up the moment it is allowed to.
    @Test func changesDeferredDuringARunAreAppliedWhenItEnds() {
        let (store, source) = makeStore([DeviceFixtures.testDrive])
        store.start()
        store.setRunActive(true)
        source.simulateChange(to: [DeviceFixtures.testDrive, DeviceFixtures.largeDrive])

        store.setRunActive(false)

        #expect(store.devices.map(\.bsdName.rawValue) == ["disk4", "disk8"])
        #expect(!store.hasPendingChange)
    }

    /// No event while frozen means no work on unfreeze.
    @Test func endingARunWithNoChangesDoesNotRefresh() {
        let (store, source) = makeStore([DeviceFixtures.testDrive])
        store.start()
        let countAfterStart = source.enumerationCount

        store.setRunActive(true)
        store.setRunActive(false)

        #expect(source.enumerationCount == countAfterStart)
    }

    @Test func repeatedRunStateUpdatesAreIgnored() {
        let (store, source) = makeStore([DeviceFixtures.testDrive])
        store.start()
        store.setRunActive(true)
        source.simulateChange(to: [])
        store.setRunActive(true)   // no transition — must not apply the pending change

        #expect(store.devices.map(\.bsdName.rawValue) == ["disk4"])
        #expect(store.hasPendingChange)
        #expect(source.enumerationCount == 1)
    }

    /// An explicit refresh is a deliberate act and is not blocked by the freeze — this
    /// is the path Step 12 uses to re-run discovery after device loss (FR-DEV-8).
    @Test func anExplicitRefreshWorksEvenWhileFrozen() {
        let (store, source) = makeStore([DeviceFixtures.testDrive])
        store.start()
        store.setRunActive(true)
        source.devices = [DeviceFixtures.testDrive, DeviceFixtures.largeDrive]

        store.refresh()

        #expect(store.devices.map(\.bsdName.rawValue) == ["disk4", "disk8"])
    }
}
