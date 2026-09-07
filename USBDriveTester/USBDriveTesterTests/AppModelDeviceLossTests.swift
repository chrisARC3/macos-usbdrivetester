//
//  AppModelDeviceLossTests.swift
//  USBDriveTesterTests
//
//  Step 12, chunk 6. FR-DEV-8's **third** obligation: the device list is rebuilt after a loss.
//

import Testing
@testable import USBDriveTester

/// What `AppModel.deviceUnderTestWasLost()` does, and the one property that makes it work.
///
/// This was very nearly written off as uncoverable — the run controller's side of the wiring is
/// tested through a closure that counts calls, and the model's side looked like it would need a
/// real `IOKitDeviceEnumerator` to observe. It does not: `AppModel.init` takes a `DeviceSource`,
/// and `StubDeviceSource` already counts enumerations. **The gap was in the reach of the bench,
/// not in the code**, which is the distinction the mutation-round rule asks for before anything
/// goes on the human checklist.
@MainActor
@Suite("Device loss rebuilds the list (Step 12, FR-DEV-8)")
struct AppModelDeviceLossTests {

    /// A model whose device list is driven by the test, with discovery already started.
    private func bench(_ devices: [DiscoveredDevice] = [DeviceFixtures.testDrive])
    -> (AppModel, StubDeviceSource) {
        let source = StubDeviceSource(devices: devices)
        let model = AppModel(suppressionStore: InMemoryPreRunWarningSuppression(),
                             deviceSource: source)
        model.terminateAction = {}
        model.discovery.start()
        return (model, source)
    }

    @Test func theListIsRebuiltFromTheSource() {
        let (model, source) = bench()
        let enumerationsBefore = source.enumerationCount

        model.deviceUnderTestWasLost()

        #expect(source.enumerationCount == enumerationsBefore + 1,
                "the source was not asked again, so the list still names the drive that left")
    }

    /// **The load-bearing one.** A lost drive is gone from IOKit, so the point of the rebuild is
    /// that the row disappears — and the row only disappears if the *new* enumeration is the one
    /// the list ends up holding.
    @Test func theDriveThatLeftIsNoLongerInTheList() {
        let (model, source) = bench([DeviceFixtures.testDrive, DeviceFixtures.largeDrive])
        #expect(model.discovery.devices.count == 2)

        source.devices = [DeviceFixtures.largeDrive]   // the drive under test de-enumerated
        model.deviceUnderTestWasLost()

        #expect(model.discovery.devices.map(\.bsdName.rawValue) == ["disk8"])
    }

    /// **FR-DEV-7's freeze does not apply to this call, and that is the whole reason it is
    /// `refresh(reason:)` rather than anything that goes through the change path.**
    ///
    /// The freeze exists so a hot-plug cannot rearrange the list under a running test. Here the
    /// run is over precisely *because* the device vanished, so leaving the row in place would show
    /// the user a drive that is not attached — the state FR-DEV-8 asks to be corrected. Discovery
    /// is deliberately still frozen when this runs: the controller re-runs discovery from
    /// `driveIsBack`, and nothing has told discovery the run ended at that point.
    @Test func theRebuildHappensEvenWhileDiscoveryIsFrozenForTheRun() {
        let (model, source) = bench([DeviceFixtures.testDrive, DeviceFixtures.largeDrive])
        model.discovery.setRunActive(true)

        source.devices = [DeviceFixtures.largeDrive]
        model.deviceUnderTestWasLost()

        #expect(model.discovery.devices.map(\.bsdName.rawValue) == ["disk8"],
                "the FR-DEV-7 freeze swallowed FR-DEV-8's rebuild")
    }

    /// A frozen-and-deferred change is a different mechanism from this one, and the rebuild must
    /// not leave discovery believing an update is still owed — the list header would go on saying
    /// devices had connected or disconnected since the run started, about a change it has applied.
    @Test func theRebuildClearsTheDeferredChangeItJustApplied() {
        let (model, source) = bench([DeviceFixtures.testDrive, DeviceFixtures.largeDrive])
        model.discovery.setRunActive(true)
        source.simulateChange(to: [DeviceFixtures.largeDrive])
        #expect(model.discovery.hasPendingChange, "the bench did not reach the state it needs")

        model.deviceUnderTestWasLost()

        #expect(!model.discovery.hasPendingChange)
        #expect(model.discovery.freezeExplanation?.contains("Devices have connected") != true)
    }

    /// The selection is re-derived rather than left naming a drive that is no longer there.
    ///
    /// `DeviceSelectionPolicy.selection(in:previousSelection:)` is what decides this and it is
    /// tested in its own right; what is pinned here is that this path goes *through* it, so a
    /// selection pointing at the departed drive cannot survive the run that lost it.
    @Test func theSelectionDoesNotSurviveTheDriveItNamed() {
        let (model, source) = bench([DeviceFixtures.testDrive, DeviceFixtures.largeDrive])
        #expect(model.discovery.selectedDevice?.bsdName.rawValue == "disk4",
                "the bench did not default-select the drive this test loses")

        source.devices = [DeviceFixtures.largeDrive]
        model.deviceUnderTestWasLost()

        #expect(model.discovery.selectedDevice?.bsdName.rawValue == "disk8")
    }
}
