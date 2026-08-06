//
//  USBSerialNumberTests.swift
//  Which USB serial numbers are worth showing the user (added 2026-08-05).
//
//  The case that matters is `0000000000000000`, and it is not hypothetical: it is what the Ugreen
//  enclosure holding this machine's `disk6` reports as its SCSI INQUIRY serial. Accepting it would
//  give every drive behind that bridge model the same identifier, so the UI would state — with
//  confidence, and wrongly — that the last run was on the drive currently selected.
//
//  That is strictly worse than the BSD-name problem this whole mechanism exists to fix: a wrong
//  identity that reads as authoritative, versus a transient one everybody knows is transient.
//

import Testing
@testable import USBDriveTester

struct USBSerialNumberTests {

    // MARK: - Real serials, measured on this machine 2026-08-05

    @Test(arguments: [
        "12345686DAA9",     // Samsung Portable SSD T5      — disk4
        "013117100578",     // Ugreen enclosure (990 EVO+)  — disk6
        "00000000NT17XBRA", // Seagate Expansion HDD        — disk8
    ])
    func realSerialsFromTheDevelopmentMachineAreAccepted(_ serial: String) {
        #expect(USBSerialNumber.sanitised(serial) == serial)
    }

    /// `00000000NT17XBRA` begins with eight zeros and is perfectly valid. A rejection rule written
    /// as "starts with zeros" or "contains mostly zeros" would throw away a real drive's identity,
    /// which is why the rule is *all one repeated character* and nothing looser.
    @Test func aSerialThatMerelyStartsWithZerosIsKept() {
        #expect(USBSerialNumber.sanitised("00000000NT17XBRA") != nil)
    }

    // MARK: - The placeholder that prompted this

    @Test func sixteenZerosIsRejected() {
        #expect(USBSerialNumber.sanitised("0000000000000000") == nil)
    }

    /// A bridge padding with `F`, `-` or spaces is making the identical claim, so singling out
    /// zero would catch one spelling of the defect and pass the others.
    @Test(arguments: ["FFFFFFFFFFFF", "------------", "            ", "00000000"])
    func anySingleRepeatedCharacterIsRejected(_ placeholder: String) {
        #expect(USBSerialNumber.sanitised(placeholder) == nil)
    }

    // MARK: - Absent and degenerate

    @Test func anAbsentPropertyIsNil() {
        #expect(USBSerialNumber.sanitised(nil) == nil)
    }

    @Test(arguments: ["", "   ", "\n", "\t "])
    func emptyAndWhitespaceOnlyAreRejected(_ blank: String) {
        #expect(USBSerialNumber.sanitised(blank) == nil)
    }

    @Test(arguments: ["1", "AB", "X-2"])
    func tooShortToDistinguishTwoDrivesIsRejected(_ short: String) {
        #expect(USBSerialNumber.sanitised(short) == nil)
    }

    @Test func surroundingWhitespaceIsTrimmedRatherThanRejected() {
        #expect(USBSerialNumber.sanitised("  12345686DAA9\n") == "12345686DAA9")
    }

    /// Trimming happens *before* the length and repetition checks, so a padded placeholder cannot
    /// slip through by being long enough with its spaces attached.
    @Test func aPaddedPlaceholderIsStillRejected() {
        #expect(USBSerialNumber.sanitised("   0000   ") == nil)
    }

    // MARK: - What the device shows

    /// A rejected or absent serial must never surface as an empty string: a blank where an
    /// identifier belongs reads as a rendering fault, and the user cannot tell it from a value
    /// that has not loaded yet.
    @Test func aDeviceWithoutASerialSaysSoRatherThanShowingNothing() {
        let device = DeviceFixtures.device(usbSerialNumber: nil)

        #expect(device.serialDescription == "Serial number not available")
        #expect(device.serialSummary == "Serial number not available")
        #expect(!device.serialSummary.isEmpty)
    }

    /// The `S/N` prefix is dropped when there is no number, because `S/N Serial number not
    /// available` doubles the label.
    @Test func theSerialSummaryIsPrefixedOnlyWhenThereIsANumber() {
        let identified = DeviceFixtures.device(usbSerialNumber: "12345686DAA9")

        #expect(identified.serialSummary == "S/N 12345686DAA9")
        #expect(identified.serialDescription == "12345686DAA9")
    }
}
