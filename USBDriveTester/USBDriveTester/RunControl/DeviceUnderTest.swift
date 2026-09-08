//
//  DeviceUnderTest.swift
//  USBDriveTester (app target — unprivileged)
//
//  Step 12, chunk 2 — route (b)'s question, as a pure type: **did the drive this run is testing
//  just leave the machine?**
//
//  ## Why route (b) exists at all, when route (a) already works
//
//  Chunk 1 taught the engine to read `ENXIO` as device loss. That covers a drive pulled while the
//  run is doing I/O, which is most of the time — but **not while the run is PAUSED**. A paused run
//  has returned from its call and issues no syscalls at all: the helper sits holding the claim and
//  the descriptor with nothing to classify, and no `errno` will ever arrive to tell it the drive
//  went. The removal callback is the only thing that can see it, which makes this route
//  load-bearing rather than a second opinion.
//
//  ## Matching on a BSD name, when a BSD name is not an identity
//
//  `BSDDeviceName`'s header states the rule this appears to break: a BSD name is a **locator**,
//  assigned at enumeration, and nothing that outlives the enumeration may use it as the identity.
//  A reboot on 2026-08-06 swapped this project's scratch drive and a 22 TB backup drive and made
//  every document saying `disk4` wrong in the same moment.
//
//  This does not outlive the enumeration, and that is the whole reason it is allowed to.
//
//  The rule's test is **lifetime**. The question here is asked only while a run holds an exclusive
//  claim on the drive, and it is asked about an event delivered during that same claim. A BSD name
//  cannot be reassigned to a different device while the device holding it is still enumerated —
//  and ours is, until the moment this callback says it is not. The window in which `disk7` could
//  mean a different drive opens *after* the event being reported, never before it.
//
//  The serial is carried anyway, and not as decoration: it is what the log line names the drive by
//  (NFR-OBS-1 and the 2026-08-06 rule both say a persisted artefact names a drive by its serial),
//  and it is what chunks 4–6 will put in front of a person. The locator answers "which of the
//  things attached right now"; the serial answers "which drive".
//
//  ## Why a slice does NOT count — corrected 2026-09-08, chunk 7f
//
//  This file used to accept a slice as proof, and the reasoning was **exactly inverted**:
//
//  > the device under test is unmounted and exclusively claimed, so nothing can be repartitioning
//  > it, and therefore a slice of it vanishing can only mean the drive vanished
//
//  **Taking exclusive whole-disk access is itself what makes the slices vanish.** Opening
//  `/dev/rdiskN` with `O_EXLOCK` tears the partition scheme down, the slices' `IOMedia` nodes
//  terminate, and DiskArbitration reports each one as disappeared. The precondition invoked for
//  safety is the direct cause of the event. Measured on the 1 TB scratch T5 (serial `12345686DAA9`,
//  GPT: EFI + a 1 TB exFAT volume), 2026-09-08, from the app's own log:
//
//      14:28:23.876  APP     unmount succeeded on disk7s2: unmounted
//      14:28:23.885  HELPER  acquired disk7: claim held, /dev/rdisk7 open exclusively (fd 4)
//      14:28:23.886  HELPER  acquire GRANTED
//      14:28:23.896  APP     a disk disappeared: disk7s1 (slice)     <- 10 ms after the claim
//      14:28:23.896  APP     the drive under test left the machine while running   <- FALSE
//      14:28:23.896  APP     a disk disappeared: disk7s2 (slice)
//
//  **The whole disk never disappeared** — zero `disk7` events in the whole capture. The run it
//  killed went on to finish: 128/128 chunks, 1,073,741,824 B read, written back and verified, no
//  failed block ranges, six seconds after the app had told the user the drive was gone.
//
//  So the discriminator is the one the old code carried and did not use: **`isWholeDisk`.** A
//  whole-disk disappearance is what an unplug produces; a slice-only disappearance is what this
//  app's own claim produces. A real unplug still fires the whole-disk event — measured 2026-09-05,
//  `CONSTRAINTS.md` fact 1 — so nothing is missed, including by a paused run, which is the case
//  route (b) exists for.
//
//  ⚠️ **What is assumed and not yet measured**: that the whole-disk event still fires *while the
//  claim is held*. The 2026-09-05 measurement was made against `hdiutil` ram disks with nothing
//  claimed. It is very likely — DiskArbitration reported the slices going while the claim was held,
//  which is the same channel — but it is an inference, and **checklist chunk 3 is what measures
//  it**: pull the cable mid-run and look for `a disk disappeared: disk7 (whole disk)`. If it does
//  not fire, this returns `false` for a real unplug, route (a)'s `ENXIO` still covers a *running*
//  run, and a *paused* one would be blind — which is chunk 4's subject and why chunk 3 runs first.
//
//  **Consequence for the caller: one unplug now yields one accepted event, not three.** The
//  idempotency in `DeviceLossWindDown` becomes belt-and-braces rather than load-bearing. It stays:
//  a mutation deleting it survived the whole suite once, and nothing here makes that safer.
//
//  ## This has no production caller yet, on purpose
//
//  Chunk 2 is the seam and the log line; **chunk 4 is what acts on the answer** — ending the run,
//  releasing a claim on an already-absent device, and doing it once. Stated here rather than left
//  to be discovered, because machinery that appears wired and does nothing is a failure this
//  project has already paid for (`selectionSyncToken`, deleted 2026-08-05).
//
//  ## Why this is in RunControl and not Discovery, which is where it was first written
//
//  Because it reads `ReportedDevice`, and `Discovery` must not depend on `Report`. That is not a
//  matter of taste: `scripts/device-probe.sh` runs the app's **real** discovery headlessly by
//  compiling `Discovery/*.swift` plus one Shared file and nothing else, and it is one of the
//  thirteen clients `build-tools.sh` type-checks. Putting this type in `Discovery` broke it
//  immediately, with an error the full app build could not produce because the app target has
//  every file in it.
//
//  The narrower build is the one that can fail, which is the point of keeping it. `DisappearedDisk`
//  — the *event* — stays in `Discovery` next to the watcher that produces it; the *question asked
//  of a run* lives here. The layering fell out of the instrument rather than out of an opinion.
//

import Foundation

/// The drive a run is testing, and the one question route (b) asks about it.
nonisolated struct DeviceUnderTest: Equatable {

    /// **The identity** (rule recorded 2026-08-06). `nil` is a real case, not a lookup failure:
    /// some USB bridges answer with a placeholder such as sixteen zeros, and this app rejects
    /// those rather than letting every drive behind one bridge share an identifier.
    let usbSerialNumber: String?

    /// **The locator** — and the only thing a disappearance callback can be matched on. See the
    /// file header for why that is sound here and nowhere that outlives the enumeration.
    let bsdName: BSDDeviceName

    /// Vendor and product as the enumerator reported them.
    let modelDescription: String

    init(usbSerialNumber: String?, bsdName: BSDDeviceName, modelDescription: String) {
        self.usbSerialNumber = usbSerialNumber
        self.bsdName = bsdName
        self.modelDescription = modelDescription
    }

    /// Take the run's drive from the record the report is built on, so the two cannot disagree
    /// about which drive a run was about.
    ///
    /// Returns `nil` when the record carries no BSD name — a run whose drive cannot be located
    /// cannot have its disappearance recognised, and answering "no" to every disappearance is
    /// the honest form of that rather than matching everything or matching nothing silently.
    init?(_ device: ReportedDevice) {
        guard let bsdName = device.bsdNameAtRunTime else { return nil }
        self.init(usbSerialNumber: device.usbSerialNumber,
                  bsdName: BSDDeviceName(bsdName),
                  modelDescription: device.modelDescription)
    }

    /// **Does this disappearance mean the drive under test is gone?**
    ///
    /// True only for **the whole disk** — see the header: a slice of the drive under test
    /// disappears as a direct consequence of this run's own exclusive claim, so accepting one
    /// ends a healthy run about ten milliseconds after it starts. False for every other disk,
    /// including the ones whose names merely *start* with this one's, which is the trap a
    /// `hasPrefix` check falls into: `disk70` and `disk7s1` both begin with `disk7`, and only one
    /// of them is this drive. The unit number is parsed rather than compared as text for exactly
    /// that reason.
    ///
    /// A name that does not parse matches only itself. That is the safe direction for a locator
    /// this code did not generate.
    func wasLost(whenDiskDisappeared disk: DisappearedDisk) -> Bool {
        // **Two independent questions, and the wholeness one comes first.** `namesThisDrive` asks
        // *which* drive the event is about; `isWholeDisk` asks whether the event can mean a drive
        // left at all. Keeping them apart is what lets `isASliceOfThisDrive` below say which of
        // the two a rejection was — otherwise a refusal is silent, and route (b) going quiet is
        // indistinguishable from route (b) never having been wired.
        disk.isWholeDisk && namesThisDrive(disk)
    }

    /// **A slice of the drive under test disappeared** — the event this run's own exclusive claim
    /// produces, a few milliseconds after it is granted. Not a device loss; see the header.
    ///
    /// This exists to be *logged*. A guard that refuses silently leaves the chunk 3 walker unable
    /// to tell a working filter from a callback that never fired.
    func isASliceOfThisDrive(_ disk: DisappearedDisk) -> Bool {
        !disk.isWholeDisk && namesThisDrive(disk)
    }

    /// **Identity only** — does this disappearance name the drive under test, whole or sliced?
    ///
    /// False for every other disk, including the ones whose names merely *start* with this one's,
    /// which is the trap a `hasPrefix` check falls into: `disk70` and `disk7s1` both begin with
    /// `disk7`, and only one of them is this drive. The unit number is parsed rather than compared
    /// as text for exactly that reason. A name that does not parse matches only itself — the safe
    /// direction for a locator this code did not generate.
    private func namesThisDrive(_ disk: DisappearedDisk) -> Bool {
        if disk.bsdName.rawValue == bsdName.rawValue { return true }

        // Both must parse before a unit number can be compared. If either does not, the exact
        // match above was the only sound answer available.
        guard let ours = bsdName.unitNumber,
              let theirs = disk.bsdName.unitNumber else { return false }

        return ours == theirs
    }

    /// How the drive is named in a log line: **model and serial**, with the locator labelled as
    /// what it was at the time.
    ///
    /// The serial leads because a log outlives the enumeration that produced the BSD name, and
    /// this project has already shipped one artefact that could not say which drive it was about.
    var logIdentification: String {
        let identity = usbSerialNumber.map { "serial \($0)" } ?? "no usable serial"
        return "\(modelDescription) (\(identity)), \(bsdName.rawValue) at run time"
    }
}
