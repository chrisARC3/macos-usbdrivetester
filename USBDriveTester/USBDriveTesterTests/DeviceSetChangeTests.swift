//
//  DeviceSetChangeTests.swift
//  NFR-OBS-1 — recovering connect/disconnect events from a wholesale refresh.
//
//  The device list is rebuilt from scratch on every hot-plug rather than patched, which
//  keeps the refresh path simple but leaves no event to log. The diff reconstructs one.
//  The case worth protecting is the last: one drive swapped for another on the same BSD
//  name must read as a departure *and* an arrival, not as nothing having happened.
//

import Testing
import Foundation
@testable import USBDriveTester

struct DeviceSetChangeTests {

    @Test func noChangeBetweenIdenticalLists() {
        let devices = [DeviceFixtures.testDrive, DeviceFixtures.workingDrive]
        let change = DiscoveredDevice.changes(from: devices, to: devices)
        #expect(change.isEmpty)
        #expect(change.logDescription == "no change")
    }

    @Test func detectsAnArrival() {
        let change = DiscoveredDevice.changes(from: [DeviceFixtures.workingDrive],
                                              to: [DeviceFixtures.testDrive,
                                                   DeviceFixtures.workingDrive])
        #expect(change.added.map(\.bsdName.rawValue) == ["disk4"])
        #expect(change.removed.isEmpty)
        #expect(change.logDescription == "connected disk4")
    }

    @Test func detectsADeparture() {
        let change = DiscoveredDevice.changes(from: [DeviceFixtures.testDrive,
                                                     DeviceFixtures.workingDrive],
                                              to: [DeviceFixtures.workingDrive])
        #expect(change.removed.map(\.bsdName.rawValue) == ["disk4"])
        #expect(change.added.isEmpty)
        #expect(change.logDescription == "disconnected disk4")
    }

    @Test func detectsBothAtOnce() {
        let change = DiscoveredDevice.changes(from: [DeviceFixtures.testDrive],
                                              to: [DeviceFixtures.largeDrive])
        #expect(change.logDescription == "connected disk8; disconnected disk4")
    }

    @Test func reportsEveryArrival() {
        let change = DiscoveredDevice.changes(from: [],
                                              to: [DeviceFixtures.testDrive,
                                                   DeviceFixtures.workingDrive,
                                                   DeviceFixtures.largeDrive])
        #expect(change.added.count == 3)
        #expect(change.logDescription == "connected disk4, disk6, disk8")
    }

    /// Unplug one drive and plug a different one into the same port: same BSD name,
    /// different registry object. Diffing by name would report no change at all, and
    /// the log would show nothing happening at the exact moment the selected device
    /// became a different piece of hardware.
    @Test func aSwappedDriveOnTheSameNameIsBothADepartureAndAnArrival() {
        let before = DeviceFixtures.device(id: 0xAAAA, bsdName: "disk4", product: "Portable SSD T5")
        let after = DeviceFixtures.device(id: 0xBBBB, bsdName: "disk4", product: "T7 Shield")

        let change = DiscoveredDevice.changes(from: [before], to: [after])
        #expect(change.added.map(\.registryEntryID) == [0xBBBB])
        #expect(change.removed.map(\.registryEntryID) == [0xAAAA])
        #expect(!change.isEmpty)
    }

    /// Log lines carry names and nothing read from the device (NFR-SEC-6).
    @Test func theLogLineNamesOnlyDevices() {
        let change = DiscoveredDevice.changes(from: [DeviceFixtures.workingDrive],
                                              to: [DeviceFixtures.testDrive])
        #expect(change.logDescription == "connected disk4; disconnected disk6")
    }
}
