//
//  DeviceUnderTestTests.swift
//  Step 12, chunk 2 — route (b)'s predicate: did the drive under test just leave?
//
//  ## What is decidable here, and what is not
//
//  The *matching* is pure and is settled below: given a disk that disappeared and the drive a run
//  is testing, does the one mean the other is gone? No DiskArbitration, no hardware.
//
//  What no unit test can show is that the callback fires at all, or that the name is readable
//  inside it. Those are facts about DiskArbitration, they were measured on 2026-09-05 against a
//  real session driven by `hdiutil` ram disks, and they are recorded in `CONSTRAINTS.md` — with
//  the boundary stated there too, because a ram disk detaching cleanly is not the same event as a
//  USB drive being pulled. Step 12's hardware gate is what closes that.
//
//  ## The trap this file exists for
//
//  `disk7` and `disk70` share a prefix and are different drives. A `hasPrefix` check — the obvious
//  way to write "is this a slice of my disk" — matches both, and would end a healthy run because
//  an unrelated drive was unplugged. Every naming case below is chosen so that a prefix comparison
//  fails it.
//

import Testing
import Foundation
@testable import USBDriveTester

private extension DeviceUnderTest {
    /// The 1 TB scratch T5, named the way the project names drives: by serial.
    static func scratch(at bsdName: String) -> DeviceUnderTest {
        DeviceUnderTest(usbSerialNumber: "12345686DAA9",
                        bsdName: BSDDeviceName(bsdName),
                        modelDescription: "Samsung Portable SSD T5")
    }
}

private func gone(_ name: String, whole: Bool? = nil) -> DisappearedDisk {
    let bsdName = BSDDeviceName(name)
    return DisappearedDisk(bsdName: bsdName, isWholeDisk: whole ?? bsdName.isWholeDiskName)
}

struct DeviceUnderTestMatchingTests {

    @Test func theDriveItselfDisappearingIsTheDriveBeingLost() {
        #expect(DeviceUnderTest.scratch(at: "disk7").wasLost(whenDiskDisappeared: gone("disk7")))
    }

    /// A drive leaving fires for the whole disk **and** each slice (measured 2026-09-05). Either
    /// is accepted: under an exclusive claim nothing can be repartitioning the drive, so a slice
    /// of it vanishing can only mean the drive vanished.
    @Test func aSliceOfTheDriveDisappearingIsAlsoTheDriveBeingLost() {
        let underTest = DeviceUnderTest.scratch(at: "disk7")
        for slice in ["disk7s1", "disk7s2", "disk7s1s1"] {
            #expect(underTest.wasLost(whenDiskDisappeared: gone(slice)), "slice=\(slice)")
        }
    }

    /// **The prefix trap.** Every name here starts with `disk7` as text and is a different drive.
    /// A `hasPrefix` implementation passes every other test in this file and fails this one.
    @Test func aDifferentDriveWhoseNameSharesThePrefixIsNotTheDriveBeingLost() {
        let underTest = DeviceUnderTest.scratch(at: "disk7")
        for other in ["disk70", "disk71", "disk700", "disk79"] {
            #expect(!underTest.wasLost(whenDiskDisappeared: gone(other)),
                    "\(other) shares a prefix with disk7 and is a different drive")
        }
    }

    /// The same trap from the other side: a two-digit drive must not be lost when a one-digit one
    /// goes. `disk1` and `disk3` are both prefixes-in-reverse of `disk13`.
    @Test func aMultiDigitDriveIsNotLostWhenASingleDigitOneGoes() {
        let underTest = DeviceUnderTest.scratch(at: "disk13")
        for other in ["disk1", "disk3", "disk130"] {
            #expect(!underTest.wasLost(whenDiskDisappeared: gone(other)), "other=\(other)")
        }
        #expect(underTest.wasLost(whenDiskDisappeared: gone("disk13s1")))
    }

    @Test func anUnrelatedDriveIsNotTheDriveBeingLost() {
        let underTest = DeviceUnderTest.scratch(at: "disk7")
        for other in ["disk4", "disk6", "disk6s2", "disk0"] {
            #expect(!underTest.wasLost(whenDiskDisappeared: gone(other)), "other=\(other)")
        }
    }

    /// A name this code did not generate matches only itself — the safe direction for a locator.
    @Test func anUnparsableNameMatchesOnlyItself() {
        let odd = DeviceUnderTest(usbSerialNumber: nil,
                                  bsdName: BSDDeviceName("nvme0"),
                                  modelDescription: "Odd")
        #expect(odd.wasLost(whenDiskDisappeared: gone("nvme0")))
        #expect(!odd.wasLost(whenDiskDisappeared: gone("nvme1")))
        #expect(!odd.wasLost(whenDiskDisappeared: gone("disk7")))

        // And a parsable drive is not lost when an unparsable disk goes.
        #expect(!DeviceUnderTest.scratch(at: "disk7").wasLost(whenDiskDisappeared: gone("nvme0")))
    }

    /// An empty name is what `describe(_:)` falls back to when `DADiskGetBSDName` returns nil.
    /// It must match nothing, or a failed read would end every run in progress.
    @Test func anEmptyNameMatchesNoDriveUnderTest() {
        #expect(!DeviceUnderTest.scratch(at: "disk7").wasLost(whenDiskDisappeared: gone("")))
    }

    /// Whole-ness does not change the answer — it is carried for the log line and for chunk 4,
    /// not used as a filter. A slice-only disappearance still means the drive went.
    @Test func theAnswerDoesNotDependOnWholeness() {
        let underTest = DeviceUnderTest.scratch(at: "disk7")
        for whole in [true, false] {
            #expect(underTest.wasLost(whenDiskDisappeared: gone("disk7", whole: whole)))
            #expect(!underTest.wasLost(whenDiskDisappeared: gone("disk8", whole: whole)))
        }
    }
}

struct DeviceUnderTestIdentityTests {

    /// **The serial leads.** A log outlives the enumeration that produced the BSD name, and the
    /// 2026-08-06 rule is that a persisted artefact names a drive by its serial. The locator is
    /// still there — two identifiers a reader can cross-check beat one — and it is labelled as
    /// what it was *at the time* rather than presented as the drive's name.
    @Test func theLogLineNamesTheDriveBySerialAndLabelsTheLocator() {
        let text = DeviceUnderTest.scratch(at: "disk7").logIdentification

        #expect(text.contains("12345686DAA9"))
        #expect(text.contains("serial"))
        #expect(text.contains("Samsung Portable SSD T5"))
        #expect(text.contains("disk7"))
        #expect(text.contains("at run time"), "the BSD name must be labelled as a locator")
    }

    /// A drive with no usable serial says so. Silence would read as "identified", and this project
    /// has already shipped one artefact that could not say which drive it was about.
    @Test func aDriveWithNoSerialSaysSoRatherThanSayingNothing() {
        let anonymous = DeviceUnderTest(usbSerialNumber: nil,
                                        bsdName: BSDDeviceName("disk9"),
                                        modelDescription: "Generic USB Disk")
        let text = anonymous.logIdentification

        #expect(text.contains("no usable serial"))
        #expect(!text.contains("serial "), "there is no serial to print")
        #expect(text.contains("disk9"))
    }

    /// Built from the same record the report is built on, so the two cannot disagree about which
    /// drive a run was about.
    @Test func itIsBuiltFromTheRecordTheReportUses() throws {
        let reported = ReportedDevice(modelDescription: "Samsung Portable SSD T5",
                                      usbSerialNumber: "12345686DAA9",
                                      bsdNameAtRunTime: "disk7",
                                      capacityBytes: 1_000_000_000_000,
                                      logicalBlockSize: 512)

        let underTest = try #require(DeviceUnderTest(reported))

        #expect(underTest.bsdName.rawValue == "disk7")
        #expect(underTest.usbSerialNumber == "12345686DAA9")
        #expect(underTest.wasLost(whenDiskDisappeared: gone("disk7")))
    }

    /// A run whose drive carries no BSD name cannot have its disappearance recognised. Answering
    /// "there is nothing to match" is the honest form of that — the alternative, an instance whose
    /// empty name matches nothing, is the same outcome reached less legibly.
    @Test func aRecordWithNoLocatorCannotBeMatchedAtAll() {
        let noLocator = ReportedDevice(modelDescription: "Samsung Portable SSD T5",
                                       usbSerialNumber: "12345686DAA9",
                                       bsdNameAtRunTime: nil,
                                       capacityBytes: 1_000_000_000_000,
                                       logicalBlockSize: 512)

        #expect(DeviceUnderTest(noLocator) == nil)
    }
}
