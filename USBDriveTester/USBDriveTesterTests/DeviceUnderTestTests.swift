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
//  ## The second trap, found on hardware 2026-09-08 (chunk 7f)
//
//  A slice of the drive under test disappears because **this run claimed the drive** — the
//  exclusive whole-disk open tears the partition scheme down. Accepting a slice therefore ends a
//  healthy run about ten milliseconds after it starts, on any drive with a partition table. No
//  unit test found it because every event here is synthesised, and the four hardware gates drive
//  the helper, where route (b) does not live. It took a person starting a run.
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

    /// **The regression this file was rewritten for, 2026-09-08 (chunk 7f).**
    ///
    /// A slice of the drive under test disappearing is **not** the drive leaving. This used to
    /// assert the opposite, on the reasoning that an exclusively claimed drive cannot be
    /// repartitioned — which is true and beside the point: taking the exclusive whole-disk open
    /// is *itself* what tears the partition scheme down and makes the slices disappear.
    ///
    /// On the 1 TB scratch T5 (GPT, EFI + one exFAT volume) the app killed its own run **ten
    /// milliseconds** after the claim was granted, and the run it discarded went on to complete
    /// 128/128 chunks with no failed block ranges. Nothing in this suite could see it: every
    /// bench feeds synthesised events, and the four hardware gates drive the helper directly,
    /// where route (b) does not live.
    @Test func aSliceOfTheDriveDisappearingIsNotTheDriveBeingLost() {
        let underTest = DeviceUnderTest.scratch(at: "disk7")
        for slice in ["disk7s1", "disk7s2", "disk7s1s1"] {
            #expect(!underTest.wasLost(whenDiskDisappeared: gone(slice)), "slice=\(slice)")
        }
    }

    /// The exact sequence the app logged at 14:28:23.896 on 2026-09-08, in order. Both events are
    /// slices of the drive under test, arriving while it is claimed; neither may end the run.
    @Test func theRunsOwnClaimTearingDownItsSlicesEndsNothing() {
        let underTest = DeviceUnderTest.scratch(at: "disk7")
        let asLogged = [gone("disk7s1", whole: false), gone("disk7s2", whole: false)]

        for disk in asLogged {
            #expect(!underTest.wasLost(whenDiskDisappeared: disk),
                    "\(disk.bsdName.rawValue) disappeared because this run claimed disk7")
        }

        // And the event that *does* mean the drive left still does.
        #expect(underTest.wasLost(whenDiskDisappeared: gone("disk7", whole: true)))
    }

    /// **The two predicates partition the cases, and that is the point of having both.** Exactly
    /// one of them is true for a disappearance that names this drive, and neither is true for one
    /// that does not — so a refusal is never ambiguous, and the log line can say which kind it was.
    @Test func everyDisappearanceIsLostOrIgnoredOrNotOurs() {
        let underTest = DeviceUnderTest.scratch(at: "disk7")

        let ours = gone("disk7", whole: true)
        #expect(underTest.wasLost(whenDiskDisappeared: ours))
        #expect(!underTest.isASliceOfThisDrive(ours))

        for slice in ["disk7s1", "disk7s2", "disk7s1s1"] {
            let disk = gone(slice, whole: false)
            #expect(!underTest.wasLost(whenDiskDisappeared: disk), "slice=\(slice)")
            #expect(underTest.isASliceOfThisDrive(disk), "slice=\(slice)")
        }

        // Another drive is neither — including the prefix traps, which must not be logged as
        // "a slice of the drive under test" any more than they may end the run.
        for other in ["disk70", "disk8", "disk70s1", "disk8s2"] {
            let disk = gone(other, whole: other.hasSuffix("1") || other.hasSuffix("2") ? false : true)
            #expect(!underTest.wasLost(whenDiskDisappeared: disk), "other=\(other)")
            #expect(!underTest.isASliceOfThisDrive(disk), "other=\(other)")
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
        // The slice does not count (chunk 7f) — but the whole disk still does, which is what
        // keeps this a test about *numbering* rather than about the wholeness gate.
        #expect(!underTest.wasLost(whenDiskDisappeared: gone("disk13s1")))
        #expect(underTest.wasLost(whenDiskDisappeared: gone("disk13")))
    }

    @Test func anUnrelatedDriveIsNotTheDriveBeingLost() {
        let underTest = DeviceUnderTest.scratch(at: "disk7")
        for other in ["disk4", "disk6", "disk6s2", "disk0"] {
            #expect(!underTest.wasLost(whenDiskDisappeared: gone(other)), "other=\(other)")
        }
    }

    /// A name this code did not generate matches only itself — the safe direction for a locator.
    ///
    /// **Wholeness is passed explicitly here**, and the reason is worth stating. The `gone(_:)`
    /// helper defaults it from `BSDDeviceName.isWholeDiskName`, which is `unitNumber != nil &&
    /// suffix.isEmpty` — so it answers `false` for `nvme0`, a name it cannot parse at all. In
    /// production the flag comes from `DAMediaWhole` and a whole `nvme0` would report `true`;
    /// the name-shape rule is only the fallback for when the description cannot be copied.
    ///
    /// ⚠️ **That fallback would refuse a whole device whose name is not `diskN`** — it cannot
    /// parse one, so it calls it a slice. Harmless for this app, which tests USB drives and those
    /// are always `diskN`, and it fails in the safe direction: a missed disappearance ends no
    /// healthy run. Recorded rather than fixed, because inventing a second parser for names this
    /// project never sees would be untested code guarding nothing.
    @Test func anUnparsableNameMatchesOnlyItself() {
        let odd = DeviceUnderTest(usbSerialNumber: nil,
                                  bsdName: BSDDeviceName("nvme0"),
                                  modelDescription: "Odd")
        #expect(odd.wasLost(whenDiskDisappeared: gone("nvme0", whole: true)))
        #expect(!odd.wasLost(whenDiskDisappeared: gone("nvme1", whole: true)))
        #expect(!odd.wasLost(whenDiskDisappeared: gone("disk7", whole: true)))

        // And a parsable drive is not lost when an unparsable disk goes.
        #expect(!DeviceUnderTest.scratch(at: "disk7")
            .wasLost(whenDiskDisappeared: gone("nvme0", whole: true)))
    }

    /// An empty name is what `describe(_:)` falls back to when `DADiskGetBSDName` returns nil.
    /// It must match nothing, or a failed read would end every run in progress.
    @Test func anEmptyNameMatchesNoDriveUnderTest() {
        #expect(!DeviceUnderTest.scratch(at: "disk7").wasLost(whenDiskDisappeared: gone("")))
    }

    /// **Wholeness is the filter** (corrected 2026-09-08). It used to be carried only for the log
    /// line, and this test used to assert that it changed nothing. Both halves matter: the right
    /// drive is not lost when only a slice goes, and the wrong drive is not lost either way.
    @Test func onlyAWholeDiskDisappearanceCanMeanTheDriveWasLost() {
        let underTest = DeviceUnderTest.scratch(at: "disk7")

        #expect(underTest.wasLost(whenDiskDisappeared: gone("disk7", whole: true)))
        #expect(!underTest.wasLost(whenDiskDisappeared: gone("disk7", whole: false)))

        for whole in [true, false] {
            #expect(!underTest.wasLost(whenDiskDisappeared: gone("disk8", whole: whole)))
        }
    }

    /// `isWholeDisk` comes from `DAMediaWhole`, with the name as fallback when the description
    /// cannot be copied. The gate reads the flag, **not** the shape of the string — so a whole
    /// disk reported with an odd name is still accepted, and a slice is refused even if something
    /// upstream mislabels its name.
    @Test func theGateReadsTheFlagRatherThanTheNamesShape() {
        let underTest = DeviceUnderTest.scratch(at: "disk7")

        // Flag says whole, name looks like a slice: accepted, because the system said whole.
        #expect(underTest.wasLost(whenDiskDisappeared: gone("disk7s1", whole: true)))
        // Flag says slice, name looks whole: refused, for the same reason.
        #expect(!underTest.wasLost(whenDiskDisappeared: gone("disk7", whole: false)))
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
