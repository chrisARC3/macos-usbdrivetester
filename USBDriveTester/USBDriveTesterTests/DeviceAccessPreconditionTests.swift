//
//  DeviceAccessPreconditionTests.swift
//  Exercises the Step 6 mount guard's decision logic (FR-SAFE-1/2/3/4, NFR-REL-3).
//
//  This suite is what closes gate item 4 — "the write path has an enforced guard that
//  exclusive access is held, verified by a unit/integration check that the guard trips
//  when access is absent" — and it does most of the work of gate items 1 and 2 as well,
//  since the thing those items check on hardware is that the *right refusal* comes back.
//  Hardware can only ever show one path at a time; this shows the whole table.
//
//  The classification is worth testing this hard because of what was measured on
//  2026-07-30: **both of FR-SAFE-4's causes surface as the same `EBUSY`.** The only
//  reason the tool can tell a user "unmount Test_Drive" rather than "something is using
//  the disk" is the ordering encoded in `evaluate`, and an ordering is exactly the kind
//  of thing a later refactor reshuffles without noticing.
//

import Testing
import Foundation
@testable import USBDriveTester

struct DeviceAccessPreconditionTests {

    private let disk4 = try! WholeDiskName(validating: "disk4")

    // MARK: - Device-name validation (NFR-REL-7)
    //
    // This string becomes "/dev/rdisk4" in a process running as root. Authenticating the
    // caller's code signature says who is calling, not that what they sent is sane.

    @Test func canonicalWholeDiskNamesAreAccepted() throws {
        #expect(try WholeDiskName(validating: "disk0").unitNumber == 0)
        #expect(try WholeDiskName(validating: "disk4").unitNumber == 4)
        #expect(try WholeDiskName(validating: "disk10").unitNumber == 10)
        #expect(try WholeDiskName(validating: "disk4294967295").unitNumber == 4_294_967_295)
    }

    @Test func devicePathsAreBuiltFromTheValidatedName() throws {
        let name = try WholeDiskName(validating: "disk4")
        #expect(name.devicePath == "/dev/disk4")
        #expect(name.rawDevicePath == "/dev/rdisk4")
    }

    @Test func emptyNameIsRejected() {
        #expect(throws: DeviceNameRejection.empty) {
            try WholeDiskName(validating: "")
        }
    }

    /// A slice is not a whole disk. Addressing `disk4s2` would mean writing *inside* a
    /// partition while believing the whole device was covered.
    @Test func sliceNameIsRejected() {
        #expect(throws: DeviceNameRejection.notACanonicalWholeDiskName("disk4s2")) {
            try WholeDiskName(validating: "disk4s2")
        }
    }

    /// The raw node is derived here, never accepted. Otherwise `/dev/r` + `rdisk4`
    /// would name something that does not exist, and the failure would look like a
    /// hardware problem.
    @Test func rawNodeNameIsRejected() {
        #expect(throws: DeviceNameRejection.notACanonicalWholeDiskName("rdisk4")) {
            try WholeDiskName(validating: "rdisk4")
        }
    }

    /// The inputs that matter: anything that could escape `/dev/` once the string is
    /// interpolated into a path.
    @Test func pathLikeNamesAreRejected() {
        for candidate in ["/dev/disk4", "../../etc/passwd", "disk4/../../etc/passwd",
                          "disk4;rm -rf /", "disk4\u{0}", "./disk4"] {
            #expect(throws: DeviceNameRejection.self, "\(candidate) must be rejected") {
                try WholeDiskName(validating: candidate)
            }
        }
    }

    /// Non-canonical spellings that would otherwise parse. `disk04` reaches the same
    /// device number as `disk4` but is not the string discovery produces — accepting it
    /// would mean two names for one device, and one of them not matching what a later
    /// "is this the device I hold?" comparison expects.
    @Test func nonCanonicalSpellingsAreRejected() {
        for candidate in ["disk04", "disk 4", "disk4 ", " disk4", "DISK4", "Disk4",
                          "disk", "disk+4", "disk-1", "disk4.0"] {
            #expect(throws: DeviceNameRejection.self, "\(candidate) must be rejected") {
                try WholeDiskName(validating: candidate)
            }
        }
    }

    /// A unit number too large for `UInt32`. Not a name macOS produces — which is the
    /// point, since it is exactly the sort of input that turns an unchecked `Int(...)!`
    /// into a crash in a root daemon.
    @Test func oversizedUnitNumberIsRejected() {
        #expect(throws: DeviceNameRejection.self) {
            try WholeDiskName(validating: "disk99999999999999999999")
        }
    }

    /// Non-ASCII digits look numeric to `Character.isNumber` but do not parse
    /// consistently with `UInt32(_:)`. Rejected explicitly rather than by luck.
    @Test func nonASCIIDigitsAreRejected() {
        #expect(throws: DeviceNameRejection.self) {
            try WholeDiskName(validating: "disk\u{0664}")   // Arabic-Indic digit four
        }
    }

    @Test func nameRejectionsExplainThemselves() {
        #expect(!DeviceNameRejection.empty.description.isEmpty)
        let rejection = DeviceNameRejection.notACanonicalWholeDiskName("disk4s2")
        #expect(rejection.description.contains("disk4s2"))
        #expect(rejection.description.contains("disk4"))
    }

    // MARK: - MountState

    /// "Mounted, with nothing mounted" must not be representable through the factory —
    /// it would classify as FR-SAFE-4(a) and refuse a run while naming no volume.
    @Test func emptyVolumeListIsUnmounted() {
        #expect(MountState(mountedVolumeNames: []) == .unmounted)
        #expect(!MountState(mountedVolumeNames: []).isMounted)
    }

    @Test func nonEmptyVolumeListIsMounted() {
        let state = MountState(mountedVolumeNames: ["Test_Drive"])
        #expect(state.isMounted)
        #expect(state.volumeNames == ["Test_Drive"])
    }

    // MARK: - FR-SAFE-4(a): volumes mounted

    @Test func mountedVolumeRefuses() {
        let decision = DeviceAccessPrecondition.evaluate(
            device: disk4,
            mountState: .mounted(volumeNames: ["Test_Drive"]),
            claim: nil,
            exclusiveOpen: nil)

        #expect(decision == .refuse(.volumesMounted(bsdName: "disk4",
                                                    volumeNames: ["Test_Drive"])))
    }

    /// The mount check comes first and is not overridable. Physically this combination
    /// cannot occur — the kernel fails the open with EBUSY while anything is mounted —
    /// but the ordering is what makes cause (a) reachable at all, so it is pinned rather
    /// than left to the physics.
    @Test func mountedVolumeRefusesEvenIfClaimAndOpenSucceeded() {
        let decision = DeviceAccessPrecondition.evaluate(
            device: disk4,
            mountState: .mounted(volumeNames: ["Test_Drive"]),
            claim: .granted,
            exclusiveOpen: .opened)

        #expect(decision.refusal?.causeCode == DeviceAccessRefusalCause.volumesMounted.rawValue)
    }

    @Test func mountedRefusalNamesTheVolumeAndTheCorrectiveStep() throws {
        let refusal = try #require(DeviceAccessPrecondition.evaluate(
            device: disk4,
            mountState: .mounted(volumeNames: ["Test_Drive"]),
            claim: nil,
            exclusiveOpen: nil).refusal)

        #expect(refusal.description.contains("Test_Drive"))
        #expect(refusal.description.contains("disk4"))
        #expect(refusal.description.lowercased().contains("unmount"))
    }

    /// FR-SAFE-6, stated in the refusal itself: starting a test never changes the mount
    /// state. The user is told that, so a refusal cannot be read as "it will unmount and
    /// carry on if I wait".
    @Test func mountedRefusalSaysNothingWasUnmounted() throws {
        let refusal = try #require(DeviceAccessPrecondition.evaluate(
            device: disk4,
            mountState: .mounted(volumeNames: ["Test_Drive"]),
            claim: nil,
            exclusiveOpen: nil).refusal)

        #expect(refusal.description.contains("Nothing was unmounted for you"))
    }

    @Test func mountedRefusalReadsCorrectlyForSeveralVolumes() throws {
        let refusal = try #require(DeviceAccessPrecondition.evaluate(
            device: disk4,
            mountState: .mounted(volumeNames: ["Test_Drive", "Scratch"]),
            claim: nil,
            exclusiveOpen: nil).refusal)

        #expect(refusal.description.contains("Test_Drive"))
        #expect(refusal.description.contains("Scratch"))
        #expect(refusal.description.contains("2 volumes"))
        // Plural agreement: "are still mounted", not "is still mounted".
        #expect(refusal.description.contains("are still mounted"))
    }

    @Test func mountedRefusalReadsCorrectlyForOneVolume() throws {
        let refusal = try #require(DeviceAccessPrecondition.evaluate(
            device: disk4,
            mountState: .mounted(volumeNames: ["Test_Drive"]),
            claim: nil,
            exclusiveOpen: nil).refusal)

        #expect(refusal.description.contains("the volume Test_Drive is"))
        #expect(!refusal.description.contains("volumes"))
    }

    // MARK: - FR-SAFE-4(b): held by another process

    /// The measured behaviour, encoded: a contended claim is never dissented, it stays
    /// pending. If this ever starts reading as an error rather than as cause (b), the
    /// tool will tell users their drive is broken when another app simply has it open.
    @Test func pendingClaimIsClassifiedAsAnotherProcess() {
        let decision = DeviceAccessPrecondition.evaluate(
            device: disk4,
            mountState: .unmounted,
            claim: .timedOut(afterSeconds: 5),
            exclusiveOpen: nil)

        #expect(decision.refusal?.causeCode
                == DeviceAccessRefusalCause.claimedByAnotherProcess.rawValue)
    }

    @Test func pendingClaimRefusalExplainsWhyATimeoutMeansContention() throws {
        let refusal = try #require(DeviceAccessPrecondition.evaluate(
            device: disk4,
            mountState: .unmounted,
            claim: .timedOut(afterSeconds: 5),
            exclusiveOpen: nil).refusal)

        #expect(refusal.description.contains("5s"))
        #expect(refusal.description.contains("another process"))
    }

    @Test func dissentedClaimIsClassifiedAsAnotherProcess() {
        let decision = DeviceAccessPrecondition.evaluate(
            device: disk4,
            mountState: .unmounted,
            claim: .dissented(status: -119930616, reason: "Disk Utility is using it"),
            exclusiveOpen: nil)

        #expect(decision.refusal?.causeCode
                == DeviceAccessRefusalCause.claimedByAnotherProcess.rawValue)
    }

    @Test func dissenterReasonReachesTheUser() throws {
        let refusal = try #require(DeviceAccessPrecondition.evaluate(
            device: disk4,
            mountState: .unmounted,
            claim: .dissented(status: -119930616, reason: "Disk Utility is using it"),
            exclusiveOpen: nil).refusal)

        #expect(refusal.description.contains("Disk Utility is using it"))
    }

    /// A dissenter with no status string still has to classify, and still has to say
    /// something the user can act on.
    @Test func dissenterWithoutAReasonStillClassifies() throws {
        let refusal = try #require(DeviceAccessPrecondition.evaluate(
            device: disk4,
            mountState: .unmounted,
            claim: .dissented(status: -119930616, reason: nil),
            exclusiveOpen: nil).refusal)

        #expect(refusal.causeCode == DeviceAccessRefusalCause.claimedByAnotherProcess.rawValue)
        #expect(!refusal.description.isEmpty)
    }

    /// The second path to cause (b): the claim can be granted and the exclusive open
    /// still lose, because they are different mechanisms. Whether phase 3 of the probe
    /// was excluded by the holder's claim or by its `O_EXLOCK` could not be told apart
    /// from the data, which is precisely why both paths are handled.
    @Test func exclusiveOpenBusyIsClassifiedAsAnotherProcess() {
        let decision = DeviceAccessPrecondition.evaluate(
            device: disk4,
            mountState: .unmounted,
            claim: .granted,
            exclusiveOpen: .failed(errnoCode: EBUSY))

        #expect(decision.refusal?.causeCode
                == DeviceAccessRefusalCause.claimedByAnotherProcess.rawValue)
    }

    // MARK: - The two causes must be distinguishable (FR-SAFE-4, gate items 1 & 2)

    /// The point of the whole file. BUILD-PLAN Step 6.3: "Never show a generic
    /// 'couldn't start'". These are the two messages the gate compares on hardware.
    @Test func theTwoCausesProduceDifferentMessages() throws {
        let mounted = try #require(DeviceAccessPrecondition.evaluate(
            device: disk4,
            mountState: .mounted(volumeNames: ["Test_Drive"]),
            claim: nil, exclusiveOpen: nil).refusal)

        let claimed = try #require(DeviceAccessPrecondition.evaluate(
            device: disk4,
            mountState: .unmounted,
            claim: .granted,
            exclusiveOpen: .failed(errnoCode: EBUSY)).refusal)

        #expect(mounted.description != claimed.description)
        #expect(mounted.causeCode != claimed.causeCode)

        // Each names its own cause and not the other's.
        #expect(mounted.description.contains("mounted"))
        #expect(!mounted.description.contains("another process"))
        #expect(claimed.description.contains("another process"))
        #expect(claimed.description.contains("no mounted volumes"))
    }

    // MARK: - Other device errors

    // MARK: - Full Disk Access detection (NFR-INST-4)

    @Test func successfulWriteOpenMeansAccessIsGranted() {
        #expect(FullDiskAccessState.from(openErrno: nil) == .granted)
    }

    @Test func epermOnTheProbeMeansAccessIsDenied() {
        #expect(FullDiskAccessState.from(openErrno: EPERM) == .denied)
    }

    /// `EACCES` is ordinary filesystem permissions, not TCC — and Full Disk Access is not
    /// the fix for it. Reporting it as denied would send the user to grant a permission
    /// that changes nothing.
    @Test func eaccesIsNotReportedAsAFullDiskAccessDenial() {
        let state = FullDiskAccessState.from(openErrno: EACCES)
        #expect(state != .denied)
        #expect(state != .granted)
    }

    /// Any other errno leaves the question open. The probe answers conclusively in two
    /// directions only, and must not guess in the third.
    @Test func otherErrnosLeaveTheQuestionUnresolved() {
        for code in [EBUSY, ENXIO, ENOENT, EIO] {
            let state = FullDiskAccessState.from(openErrno: code)
            #expect(state != .granted, "errno \(code) must not read as granted")
            #expect(state != .denied, "errno \(code) must not read as denied")
        }
    }

    /// A permission that is present is not news. An always-on banner is one nobody reads
    /// by the time it matters.
    @Test func grantedAccessSaysNothing() {
        #expect(FullDiskAccessState.granted.explanation == nil)
    }

    @Test func deniedAccessNamesTheSettingAndTheRootCaveat() throws {
        let text = try #require(FullDiskAccessState.denied.explanation)
        #expect(text.contains("Full Disk Access"))
        #expect(text.contains("System Settings"))
        #expect(text.lowercased().contains("administrator"))
    }

    /// An unknown result must read as unknown — neither a clean bill of health nor an
    /// accusation that the permission is missing.
    @Test func unknownAccessIsHonestAboutBeingUnknown() throws {
        let text = try #require(FullDiskAccessState.unknown(detail: "errno 6").explanation)
        #expect(text.contains("Could not confirm"))
        #expect(text.contains("errno 6"))
    }

    @Test func onlyDeniedReportsAsDenied() {
        #expect(FullDiskAccessState.denied.isDenied)
        #expect(!FullDiskAccessState.granted.isDenied)
        #expect(!FullDiskAccessState.unknown(detail: "x").isDenied)
    }

    // MARK: - EPERM means Full Disk Access, not a bad drive
    //
    // Measured on hardware 2026-08-01: the helper's O_EXLOCK open of an *unmounted*,
    // uncontended external disk failed EPERM, and tccd logged
    // `kTCCServiceSystemPolicyAllFiles … Denied (Service Policy)` plus
    // `kTCCServiceSystemPolicyRemovableVolumes denied by TCC` at the same instant.
    // Running as root is not sufficient.

    @Test func epermIsClassifiedAsMissingFullDiskAccess() {
        let decision = DeviceAccessPrecondition.evaluate(
            device: disk4,
            mountState: .unmounted,
            claim: .granted,
            exclusiveOpen: .failed(errnoCode: EPERM))

        #expect(decision.refusal?.causeCode
                == DeviceAccessRefusalCause.accessNotPermitted.rawValue)
    }

    /// The corrective step is a checkbox in System Settings. Saying "the device refused
    /// the open" — which is what the generic device-error message says — would send the
    /// user to check the cable or suspect a failing drive.
    @Test func fullDiskAccessRefusalNamesTheSettingAndNotTheDrive() throws {
        let refusal = try #require(DeviceAccessPrecondition.evaluate(
            device: disk4,
            mountState: .unmounted,
            claim: .granted,
            exclusiveOpen: .failed(errnoCode: EPERM)).refusal)

        #expect(refusal.description.contains("Full Disk Access"))
        #expect(refusal.description.contains("System Settings"))
        #expect(refusal.description.contains("Nothing is wrong with the drive"))
        // Must not be mistaken for either FR-SAFE-4 cause.
        #expect(!refusal.description.contains("still mounted"))
        #expect(!refusal.description.contains("another process"))
    }

    /// Root is not enough, and the message has to say so — otherwise the natural reading
    /// of "permission denied" from a *privileged helper* is that something is broken.
    @Test func fullDiskAccessRefusalSaysRootIsNotSufficient() throws {
        let refusal = try #require(DeviceAccessPrecondition.evaluate(
            device: disk4,
            mountState: .unmounted,
            claim: .granted,
            exclusiveOpen: .failed(errnoCode: EPERM)).refusal)

        #expect(refusal.description.lowercased().contains("administrator"))
    }

    /// EPERM and EACCES are different failures and must not collapse into one.
    @Test func epermAndEaccesAreClassifiedDifferently() {
        let eperm = DeviceAccessPrecondition.evaluate(
            device: disk4, mountState: .unmounted, claim: .granted,
            exclusiveOpen: .failed(errnoCode: EPERM)).refusal
        let eacces = DeviceAccessPrecondition.evaluate(
            device: disk4, mountState: .unmounted, claim: .granted,
            exclusiveOpen: .failed(errnoCode: EACCES)).refusal

        #expect(eperm?.causeCode != eacces?.causeCode)
        #expect(eperm?.description != eacces?.description)
    }

    /// Not every failure is one of FR-SAFE-4's two causes. `EACCES` on the raw node
    /// means the helper is not running as root — reporting that as "another process has
    /// it" would send the user hunting for a process that does not exist.
    ///
    /// The property being asserted is that the user is not given cause (b)'s *corrective
    /// step*, so the check is against that instruction rather than against the phrase
    /// "another process". The device-error message mentions the phrase on purpose — it
    /// rules both FR-SAFE-4 causes out explicitly — and an earlier version of this test
    /// failed on exactly that, having tested the wording instead of the meaning.
    @Test func otherErrnoIsADeviceErrorNotCauseB() throws {
        let refusal = try #require(DeviceAccessPrecondition.evaluate(
            device: disk4,
            mountState: .unmounted,
            claim: .granted,
            exclusiveOpen: .failed(errnoCode: EACCES)).refusal)

        #expect(refusal.causeCode == DeviceAccessRefusalCause.deviceError.rawValue)
        #expect(refusal.description.contains("\(EACCES)"))
        #expect(!refusal.description.contains("Quit whatever is using the drive"))
    }

    /// The other half of the same idea: a device error tells the user which of the two
    /// familiar causes it is *not*, so an unexplained failure does not get mistaken for
    /// one of them.
    @Test func deviceErrorRulesOutBothFRSafe4Causes() throws {
        let refusal = try #require(DeviceAccessPrecondition.evaluate(
            device: disk4,
            mountState: .unmounted,
            claim: .granted,
            exclusiveOpen: .failed(errnoCode: EACCES)).refusal)

        #expect(refusal.description.contains("not a mounted volume"))
        #expect(refusal.description.contains("not another process"))
    }

    @Test func deviceErrorNamesTheErrnoInWords() throws {
        let refusal = try #require(DeviceAccessPrecondition.evaluate(
            device: disk4,
            mountState: .unmounted,
            claim: .granted,
            exclusiveOpen: .failed(errnoCode: ENXIO)).refusal)

        #expect(refusal.description.contains(String(cString: strerror(ENXIO))))
    }

    // MARK: - Failing closed
    //
    // The asymmetry with UninstallPrecondition, which fails open. Here the thing being
    // guarded is raw block writes, so anything unestablished refuses.

    @Test func missingClaimRefuses() {
        let decision = DeviceAccessPrecondition.evaluate(
            device: disk4, mountState: .unmounted, claim: nil, exclusiveOpen: .opened)

        #expect(decision.refusal?.causeCode
                == DeviceAccessRefusalCause.checkIncomplete.rawValue)
    }

    @Test func missingOpenRefuses() {
        let decision = DeviceAccessPrecondition.evaluate(
            device: disk4, mountState: .unmounted, claim: .granted, exclusiveOpen: nil)

        #expect(decision.refusal?.causeCode
                == DeviceAccessRefusalCause.checkIncomplete.rawValue)
    }

    /// No DiskArbitration session is a reason to stop, not a reason to skip the claim.
    /// Without the claim macOS remounts the volume mid-run — measured, not theorised.
    @Test func unavailableSessionRefusesRatherThanProceeding() throws {
        let refusal = try #require(DeviceAccessPrecondition.evaluate(
            device: disk4,
            mountState: .unmounted,
            claim: .sessionUnavailable(detail: "DASessionCreate returned nil"),
            exclusiveOpen: .opened).refusal)

        #expect(refusal.causeCode == DeviceAccessRefusalCause.checkIncomplete.rawValue)
        #expect(refusal.description.contains("DASessionCreate returned nil"))
    }

    @Test func nothingEstablishedAtAllRefuses() {
        let decision = DeviceAccessPrecondition.evaluate(
            device: disk4, mountState: .unmounted, claim: nil, exclusiveOpen: nil)

        #expect(decision.isRefusal)
    }

    // MARK: - The one path that grants

    @Test func unmountedClaimedAndExclusivelyOpenedAcquires() {
        let decision = DeviceAccessPrecondition.evaluate(
            device: disk4,
            mountState: .unmounted,
            claim: .granted,
            exclusiveOpen: .opened)

        #expect(decision == .acquire)
        #expect(!decision.isRefusal)
        #expect(decision.refusal == nil)
    }

    /// Exactly one combination out of the whole input space grants. Stated as its own
    /// test because "does it refuse when it should" and "does it refuse when it should
    /// not" are different failures, and only the second shows up as a user complaint.
    @Test func onlyOneCombinationGrants() {
        let mountStates: [MountState] = [.unmounted, .mounted(volumeNames: ["Test_Drive"])]
        let claims: [DiskClaimOutcome?] = [
            nil, .granted, .timedOut(afterSeconds: 5),
            .dissented(status: -1, reason: nil),
            .sessionUnavailable(detail: "x"),
        ]
        let opens: [ExclusiveOpenOutcome?] = [
            nil, .opened, .failed(errnoCode: EBUSY), .failed(errnoCode: EACCES),
        ]

        var granted = 0
        for mountState in mountStates {
            for claim in claims {
                for open in opens {
                    let decision = DeviceAccessPrecondition.evaluate(
                        device: disk4, mountState: mountState,
                        claim: claim, exclusiveOpen: open)

                    if decision == .acquire {
                        granted += 1
                        #expect(!mountState.isMounted)
                        #expect(claim == .granted)
                        #expect(open == .opened)
                    } else {
                        // Every refusal carries a message that is actually usable.
                        #expect(decision.refusal?.description.isEmpty == false)
                    }
                }
            }
        }
        #expect(granted == 1, "exactly one input combination may grant access")
    }

    // MARK: - Device eligibility (BUILD-PLAN Step 3.5 — helper re-checks identity)

    @Test func ineligibleDeviceRefusalNamesTheDeviceAndTheReason() {
        let refusal = DeviceAccessRefusal.deviceNotEligible(
            bsdName: "disk0",
            reason: "its physical interconnect is Apple Fabric, not USB.")

        #expect(refusal.causeCode == DeviceAccessRefusalCause.deviceNotEligible.rawValue)
        #expect(refusal.description.contains("disk0"))
        #expect(refusal.description.contains("Apple Fabric"))
    }

    // MARK: - Wire-code agreement
    //
    // The one place both representations are visible at once: Core comes into this
    // target as source, `DeviceAccessRefusalCause` through @testable import. They are
    // separate types because Core is deliberately not compiled into the app module, so
    // nothing but this test stops them drifting.

    @Test func causeCodesMatchTheWireEnum() {
        let pairs: [(DeviceAccessRefusal, DeviceAccessRefusalCause)] = [
            (.deviceNotEligible(bsdName: "disk0", reason: "x"), .deviceNotEligible),
            (.volumesMounted(bsdName: "disk4", volumeNames: ["v"]), .volumesMounted),
            (.claimedByAnotherProcess(bsdName: "disk4", detail: "x"), .claimedByAnotherProcess),
            (.deviceError(bsdName: "disk4", errnoCode: EACCES), .deviceError),
            (.checkIncomplete(bsdName: "disk4", detail: "x"), .checkIncomplete),
            (.alreadyHeld(bsdName: "disk4", heldDeviceName: "disk8"), .alreadyHeld),
            (.accessNotPermitted(bsdName: "disk4"), .accessNotPermitted),
        ]

        for (refusal, wireCause) in pairs {
            #expect(refusal.causeCode == wireCause.rawValue)
            #expect(DeviceAccessRefusalCause(wireValue: refusal.causeCode) == wireCause)
        }
    }

    /// A helper newer than the app must never have an unknown cause read as success.
    @Test func unknownWireCauseDegradesToUnrecognised() {
        #expect(DeviceAccessRefusalCause(wireValue: 99) == .unrecognised)
        #expect(DeviceAccessRefusalCause(wireValue: -1) == .unrecognised)
    }

    /// No refusal may ever carry the "nothing was refused" code, or the app would show a
    /// refusal it cannot classify as a refusal.
    @Test func noRefusalUsesTheUnrecognisedCode() {
        let refusals: [DeviceAccessRefusal] = [
            .deviceNotEligible(bsdName: "disk0", reason: "x"),
            .volumesMounted(bsdName: "disk4", volumeNames: ["v"]),
            .claimedByAnotherProcess(bsdName: "disk4", detail: "x"),
            .deviceError(bsdName: "disk4", errnoCode: EACCES),
            .checkIncomplete(bsdName: "disk4", detail: "x"),
            .alreadyHeld(bsdName: "disk4", heldDeviceName: "disk8"),
            .accessNotPermitted(bsdName: "disk4"),
        ]
        for refusal in refusals {
            #expect(refusal.causeCode != DeviceAccessRefusalCause.unrecognised.rawValue)
        }
    }

    /// Every cause code is distinct. They are hand-written rather than derived from a
    /// `CaseIterable` raw value, so two cases sharing a number is a live possibility and
    /// would make the app offer the wrong corrective control for one of them.
    @Test func causeCodesAreUnique() {
        let refusals: [DeviceAccessRefusal] = [
            .deviceNotEligible(bsdName: "d", reason: "x"),
            .volumesMounted(bsdName: "d", volumeNames: ["v"]),
            .claimedByAnotherProcess(bsdName: "d", detail: "x"),
            .deviceError(bsdName: "d", errnoCode: EACCES),
            .checkIncomplete(bsdName: "d", detail: "x"),
            .alreadyHeld(bsdName: "d", heldDeviceName: "e"),
            .accessNotPermitted(bsdName: "d"),
        ]
        #expect(Set(refusals.map(\.causeCode)).count == refusals.count)
    }

    // MARK: - Already held (FR-CTRL-9)

    /// The corrective step is inside this app. Reporting it as cause (b) would send the
    /// user hunting for another process that does not exist.
    @Test func alreadyHeldNamesTheAppNotAnotherProcess() {
        let refusal = DeviceAccessRefusal.alreadyHeld(bsdName: "disk4",
                                                      heldDeviceName: "disk8")

        #expect(refusal.causeCode == DeviceAccessRefusalCause.alreadyHeld.rawValue)
        #expect(refusal.description.contains("this app"))
        #expect(refusal.description.contains("disk4"))
        #expect(refusal.description.contains("disk8"))
        #expect(!refusal.description.contains("Quit whatever is using the drive"))
    }

    /// Re-acquiring the *same* device reads differently from being blocked by a
    /// different one — "release disk4 before acquiring disk4" would be nonsense.
    @Test func alreadyHeldReadsSensiblyForTheSameDevice() {
        let refusal = DeviceAccessRefusal.alreadyHeld(bsdName: "disk4",
                                                      heldDeviceName: "disk4")
        #expect(refusal.description.contains("already holds exclusive access to disk4"))
        #expect(!refusal.description.contains("before acquiring disk4"))
    }

    // MARK: - The write guard (NFR-REL-3) — gate item 4

    private let fullGrant = DeviceAccessGrant(deviceName: "disk4",
                                              claimHeld: true,
                                              exclusiveOpenHeld: true)

    @Test func writeIsPermittedWithACompleteGrantOnTheSameDevice() throws {
        try WritePrecondition.check(fullGrant, writingTo: "disk4")
    }

    /// The gate's wording: "the guard trips when access is absent".
    @Test func writeIsRefusedWithNoGrantAtAll() {
        #expect(throws: WritePreconditionViolation.noAccessHeld(requested: "disk4")) {
            try WritePrecondition.check(nil, writingTo: "disk4")
        }
    }

    /// The dangerous one. A write that lands on the wrong drive is the failure this
    /// entire tool exists to avoid, and it is the only violation here that could destroy
    /// data on a device the user never selected.
    @Test func writeIsRefusedOnADifferentDeviceThanIsHeld() {
        #expect(throws: WritePreconditionViolation.wrongDevice(held: "disk4",
                                                               requested: "disk8")) {
            try WritePrecondition.check(fullGrant, writingTo: "disk8")
        }
    }

    /// A half-held grant is what the type system cannot see: a grant is still a grant
    /// after its claim has been released, and without the claim macOS can remount a
    /// volume in the middle of a write.
    @Test func writeIsRefusedWithoutTheClaim() {
        let grant = DeviceAccessGrant(deviceName: "disk4",
                                      claimHeld: false,
                                      exclusiveOpenHeld: true)
        #expect(throws: WritePreconditionViolation.claimNotHeld("disk4")) {
            try WritePrecondition.check(grant, writingTo: "disk4")
        }
    }

    /// Without `O_EXLOCK` the open excludes nobody — measured: two plain `O_RDWR` opens
    /// of an unmounted raw disk both succeeded. So an open on its own is not access.
    @Test func writeIsRefusedWithoutTheExclusiveOpen() {
        let grant = DeviceAccessGrant(deviceName: "disk4",
                                      claimHeld: true,
                                      exclusiveOpenHeld: false)
        #expect(throws: WritePreconditionViolation.exclusiveOpenNotHeld("disk4")) {
            try WritePrecondition.check(grant, writingTo: "disk4")
        }
    }

    @Test func aGrantIsCompleteOnlyWithBothHalves() throws {
        #expect(fullGrant.isComplete)
        #expect(!DeviceAccessGrant(deviceName: "disk4", claimHeld: true,
                                   exclusiveOpenHeld: false).isComplete)
        #expect(!DeviceAccessGrant(deviceName: "disk4", claimHeld: false,
                                   exclusiveOpenHeld: true).isComplete)
        #expect(try DeviceAccessGrant(fullyHeldOn: WholeDiskName(validating: "disk4"))
                == fullGrant)
    }

    /// Every combination of grant state and target device, so no partial grant is
    /// accidentally accepted by a future edit that simplifies the four guards into one.
    @Test func fullGuardMatrix() {
        for claimHeld in [true, false] {
            for openHeld in [true, false] {
                for target in ["disk4", "disk8"] {
                    let grant = DeviceAccessGrant(deviceName: "disk4",
                                                  claimHeld: claimHeld,
                                                  exclusiveOpenHeld: openHeld)
                    let shouldPass = claimHeld && openHeld && target == "disk4"

                    if shouldPass {
                        #expect(throws: Never.self) {
                            try WritePrecondition.check(grant, writingTo: target)
                        }
                    } else {
                        #expect(throws: WritePreconditionViolation.self,
                                "claim=\(claimHeld) open=\(openHeld) target=\(target)") {
                            try WritePrecondition.check(grant, writingTo: target)
                        }
                    }
                }
            }
        }
    }

    @Test func everyViolationExplainsItself() {
        let violations: [WritePreconditionViolation] = [
            .noAccessHeld(requested: "disk4"),
            .wrongDevice(held: "disk4", requested: "disk8"),
            .claimNotHeld("disk4"),
            .exclusiveOpenNotHeld("disk4"),
        ]
        for violation in violations {
            #expect(violation.description.contains("Refusing to write"))
            #expect(violation.description.contains("disk"))
        }
    }
}
