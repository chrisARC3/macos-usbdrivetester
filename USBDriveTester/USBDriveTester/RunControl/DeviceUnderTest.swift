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
//  ## Why a slice counts
//
//  A drive leaving produces a disappearance for the whole disk **and** one for each of its slices —
//  measured 2026-09-05, see `CONSTRAINTS.md`. Either is accepted here, for a reason that depends on
//  the run's own preconditions: the device under test is unmounted and exclusively claimed, so
//  nothing can be repartitioning it, and therefore a slice of it vanishing can only mean the drive
//  vanished. In practice the whole-disk event fires too, so this is redundancy rather than the
//  primary route — and redundancy is the right shape when the alternative is missing the one event
//  a paused run can be told about.
//
//  **Consequence for the caller: this fires more than once per unplug.** Whatever acts on it in
//  chunk 4 has to be idempotent, because a two-partition drive produces three of these.
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
    /// True for the drive itself and for any slice of it. False for every other disk — including
    /// the ones whose names merely *start* with this one's, which is the trap a `hasPrefix` check
    /// falls into: `disk70` and `disk7s1` both begin with `disk7`, and only one of them is this
    /// drive. The unit number is parsed rather than compared as text for exactly that reason.
    ///
    /// A name that does not parse matches only itself. That is the safe direction for a locator
    /// this code did not generate.
    func wasLost(whenDiskDisappeared disk: DisappearedDisk) -> Bool {
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
