//
//  BSDDeviceNameTests.swift
//  FR-DEV-2 — the device list's presentation order.
//
//  Two properties are being protected. **Numeric correctness**, so `disk10` does not
//  sort ahead of `disk2` — reachable on any Mac with a few APFS containers; the
//  development machine is already at disk9. And **stability**, so the list does not
//  reorder itself between refreshes: the list is rebuilt from scratch on every
//  hot-plug event, and IOKit's iteration order is neither sorted nor documented as
//  stable (it currently returns disk0, disk1, disk3, disk2, disk7, disk9, disk6,
//  disk8 on this machine). A list that reshuffles under the cursor is a list that
//  gets the wrong drive selected.
//

import Testing
import Foundation
@testable import USBDriveTester

struct BSDDeviceNameTests {

    // MARK: - Parsing

    @Test func parsesAWholeDiskName() {
        let name = BSDDeviceName("disk4")
        #expect(name.unitNumber == 4)
        #expect(name.suffix == "")
        #expect(name.isWholeDiskName)
    }

    @Test func parsesADoubleDigitUnit() {
        #expect(BSDDeviceName("disk10").unitNumber == 10)
    }

    @Test func parsesASliceName() {
        let name = BSDDeviceName("disk4s2")
        #expect(name.unitNumber == 4)
        #expect(name.suffix == "s2")
        #expect(!name.isWholeDiskName)
    }

    @Test(arguments: ["", "disk", "rdisk4", "sda1", "diskette"])
    func leavesUnparseableNamesUnparsed(_ raw: String) {
        #expect(BSDDeviceName(raw).unitNumber == nil)
        #expect(!BSDDeviceName(raw).isWholeDiskName)
    }

    /// Not a name macOS produces — but an unchecked integer parse here would be a
    /// crash reachable from device state, which is not a trade worth making.
    @Test func aUnitNumberTooLargeForUInt32IsNotParsed() {
        #expect(BSDDeviceName("disk99999999999999999999").unitNumber == nil)
    }

    /// Non-ASCII digits must not parse, or they would disagree with `UInt32(_:)`.
    @Test func nonASCIIDigitsAreNotTreatedAsANumber() {
        #expect(BSDDeviceName("disk٤").unitNumber == nil)
    }

    // MARK: - Device paths

    @Test func exposesBothDeviceNodes() {
        let name = BSDDeviceName("disk4")
        #expect(name.devicePath == "/dev/disk4")
        #expect(name.rawDevicePath == "/dev/rdisk4")
    }

    // MARK: - Ordering

    @Test func sortsNumericallyNotLexically() {
        #expect(BSDDeviceName("disk2") < BSDDeviceName("disk10"))
        #expect(!(BSDDeviceName("disk10") < BSDDeviceName("disk2")))
    }

    @Test func sortsTheDevelopmentMachinesDisksInOrder() {
        let names = ["disk8", "disk10", "disk4", "disk6", "disk0", "disk2"]
            .map(BSDDeviceName.init)
            .sorted()
            .map(\.rawValue)
        #expect(names == ["disk0", "disk2", "disk4", "disk6", "disk8", "disk10"])
    }

    /// The property the live-refresh path depends on: the same set in any input order
    /// must produce the same output order.
    @Test func orderIsIndependentOfInputOrder() {
        let iokitOrder = ["disk0", "disk1", "disk3", "disk2", "disk7", "disk9", "disk6", "disk8"]
        let reversed = Array(iokitOrder.reversed())

        let a = iokitOrder.map(BSDDeviceName.init).sorted().map(\.rawValue)
        let b = reversed.map(BSDDeviceName.init).sorted().map(\.rawValue)

        #expect(a == b)
        #expect(a == ["disk0", "disk1", "disk2", "disk3", "disk6", "disk7", "disk8", "disk9"])
    }

    /// Unparsed names sort last, so an unrecognised name cannot become the
    /// default-selected device (FR-DEV-3).
    @Test func unparsedNamesSortAfterParsedOnes() {
        let names = ["mystery", "disk4", "disk2"]
            .map(BSDDeviceName.init)
            .sorted()
            .map(\.rawValue)
        #expect(names == ["disk2", "disk4", "mystery"])
    }

    @Test func unparsedNamesSortLexicallyAmongThemselves() {
        let names = ["zebra", "aardvark"].map(BSDDeviceName.init).sorted().map(\.rawValue)
        #expect(names == ["aardvark", "zebra"])
    }

    /// A total order — no two distinct names compare equal — is what makes `sorted()`
    /// deterministic. Without the final tie-break on the raw string, `disk4` and
    /// `disk04` would be interchangeable and could swap places between refreshes.
    @Test func distinctNamesNeverCompareEqual() {
        let a = BSDDeviceName("disk4")
        let b = BSDDeviceName("disk04")
        #expect(a.unitNumber == b.unitNumber)
        #expect((a < b) != (b < a))
    }

    @Test func slicesSortAfterTheirWholeDisk() {
        let names = ["disk4s2", "disk4", "disk4s1"]
            .map(BSDDeviceName.init)
            .sorted()
            .map(\.rawValue)
        #expect(names == ["disk4", "disk4s1", "disk4s2"])
    }
}
