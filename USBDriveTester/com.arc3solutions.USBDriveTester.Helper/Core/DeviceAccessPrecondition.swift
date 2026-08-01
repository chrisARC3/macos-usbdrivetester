//
//  DeviceAccessPrecondition.swift
//  Core — the decision that stands between a caller and raw block writes.
//
//  Step 6 (AI-4). Satisfies the decision half of FR-SAFE-1/2/3/4 and the guard of
//  NFR-REL-3; the acquiring itself is in the helper's `DeviceClaim.swift`, which does
//  the DiskArbitration and `open(2)` work and then asks this file what the results mean.
//
//  Split out for the same reason as `UninstallPrecondition`: this is a *safety* policy,
//  and a safety policy that lives inline in the middle of an acquire sequence is one
//  that quietly grows an untested branch. Everything here is pure — Foundation only, no
//  DiskArbitration, no IOKit, no file descriptors — so the whole classification is
//  exhaustively unit-testable with no hardware and no root (NFR-MAINT-2). That is what
//  keeps the hardware-dependent part of Step 6's gate down to two shell scripts.
//
//  ## What this file decides
//
//  Four things, in the order the acquire sequence needs them:
//
//    1. **Is the name even addressable?** — ``WholeDiskName`` validates the BSD name a
//       caller sent before it is ever interpolated into a `/dev/` path.
//    2. **May access be granted?** — ``DeviceAccessPrecondition/evaluate(device:mountState:claim:exclusiveOpen:)``
//       classifies (mount state, claim outcome, open errno) into a grant or a refusal.
//    3. **What do we tell the user?** — ``DeviceAccessRefusal`` carries a message that
//       names the actual cause and the corrective step (FR-SAFE-4, NFR-USE-5).
//    4. **Is it safe to write?** — ``WritePrecondition`` re-checks, at the top of the
//       write path, that access is genuinely held (NFR-REL-3).
//
//  ## Why the classification is not just an errno
//
//  Measured on real hardware 2026-07-30 (`scripts/exclusivity-probe.sh`): **both** of
//  FR-SAFE-4's causes surface as the same `EBUSY`. A mounted volume makes the raw open
//  fail `EBUSY`, and so does another process holding the node. An implementation that
//  classified on the errno alone would be unable to tell a user whose drive is merely
//  mounted — the overwhelmingly common case, with a one-click fix — from a user who has
//  to go hunting for another process. The mount check is the *only* thing that separates
//  them, which is why it is an input here rather than something inferred.
//
//  Two more measured facts are encoded below rather than assumed:
//
//    * A contended `DADiskClaim` is **never dissented — it stays pending forever.** So a
//      claim timeout is not an error condition to report as such; it *is* cause (b).
//      See ``DiskClaimOutcome/timedOut(afterSeconds:)``.
//    * A plain `O_RDWR` open on an unmounted raw disk excludes nobody. Exclusivity comes
//      from `O_EXLOCK`, which is why ``DeviceAccessGrant/exclusiveOpenHeld`` is tracked
//      as its own fact and not folded into "the fd is valid".
//
//  ## Failing closed
//
//  Note the asymmetry with `UninstallPrecondition`, which deliberately fails *open*:
//  being unable to remove a wedged root daemon is worse than the risk of removing it.
//  Here the stakes are reversed — the thing being guarded is raw block writes to a
//  user's drive — so every "we could not establish that" outcome refuses. That is what
//  ``DeviceAccessRefusal/checkIncomplete(bsdName:detail:)`` exists for: a step of the
//  sequence that was skipped or could not be completed can never read as permission.
//

import Foundation

// MARK: - The device name (boundary validation, NFR-REL-7)

/// Why a caller-supplied device name was refused.
public enum DeviceNameRejection: Error, Equatable, CustomStringConvertible {

    /// The name was empty.
    case empty

    /// The name is not `disk` followed by a decimal unit number, or is not the
    /// canonical spelling of one (`disk04`, `disk4s2`, `rdisk4`, `../../etc/passwd`).
    case notACanonicalWholeDiskName(String)

    public var description: String {
        switch self {
        case .empty:
            return "No device was named."
        case .notACanonicalWholeDiskName(let name):
            return "\"\(name)\" is not the name of a whole disk. Expected a BSD whole-disk "
                 + "name such as \"disk4\" — not a slice (\"disk4s2\"), not a raw node "
                 + "(\"rdisk4\"), and not a path."
        }
    }
}

/// A validated BSD **whole-disk** name, e.g. `disk4`.
///
/// The helper runs as root and turns this string into `/dev/rdisk4` before opening it,
/// so it is the single most dangerous value crossing the XPC boundary. Authenticating
/// the peer's code signature establishes *who* is calling; it says nothing about what
/// they sent (NFR-REL-7, NFR-SEC-3). Everything downstream takes this type rather than a
/// `String`, so the path cannot be built from an unvalidated name.
///
/// - Note: this deliberately duplicates part of the app-side `BSDDeviceName`. They are
///   not shareable — Core compiles into the helper and the test target but **not** the
///   app module, which would impose the app's default `MainActor` isolation on it — and
///   they should not be shared even if they were: this one is a *boundary check* on a
///   value arriving from another process, and it is stricter on purpose. `BSDDeviceName`
///   parses whatever IOKit reported and still sorts names it does not recognise; this
///   one rejects them.
public struct WholeDiskName: Equatable, Hashable, CustomStringConvertible {

    /// The canonical name, e.g. `disk4`.
    public let rawValue: String

    /// The unit number, e.g. `4`.
    public let unitNumber: UInt32

    /// Validate a caller-supplied name.
    ///
    /// Accepts **only** `disk` followed by the decimal digits of a `UInt32`, spelled
    /// canonically. The canonicity check is a single comparison against the round-trip
    /// of the parsed number, which is what rejects `disk04`, `disk4 `, `disk4s2` and a
    /// unit number too large for `UInt32` — all in one place, with no separate rule per
    /// attack shape.
    ///
    /// - Throws: ``DeviceNameRejection``.
    public init(validating candidate: String) throws {
        guard !candidate.isEmpty else { throw DeviceNameRejection.empty }

        let prefix = "disk"
        guard candidate.hasPrefix(prefix) else {
            throw DeviceNameRejection.notACanonicalWholeDiskName(candidate)
        }

        // Deliberately not `Character.isNumber`, which is true for non-ASCII digits such
        // as "٤" — those would parse inconsistently with `UInt32(_:)`.
        let digits = candidate.dropFirst(prefix.count)
        guard !digits.isEmpty,
              digits.allSatisfy({ $0 >= "0" && $0 <= "9" }),
              let number = UInt32(digits),
              // The canonicity check. `disk04` parses as 4 but does not round-trip, and
              // a name that does not round-trip is not the one discovery produced.
              "\(prefix)\(number)" == candidate else {
            throw DeviceNameRejection.notACanonicalWholeDiskName(candidate)
        }

        self.rawValue = candidate
        self.unitNumber = number
    }

    /// Buffered device node, e.g. `/dev/disk4` — what DiskArbitration addresses.
    public var devicePath: String { "/dev/\(rawValue)" }

    /// **Raw** device node, e.g. `/dev/rdisk4` — the unbuffered node the helper opens
    /// exclusively here and does uncached I/O through from Step 7 (FR-TEST-6).
    public var rawDevicePath: String { "/dev/r\(rawValue)" }

    public var description: String { rawValue }
}

// MARK: - Inputs to the decision

/// Whether any volume of the device is mounted (FR-SAFE-1/2).
///
/// This is the fact that separates FR-SAFE-4's two causes, which are otherwise the same
/// errno — see the file header.
public enum MountState: Equatable {

    /// No volume of this device is mounted.
    case unmounted

    /// One or more volumes are mounted. Never constructed with an empty list: use
    /// ``MountState/init(mountedVolumeNames:)``, which maps empty to ``unmounted`` so a
    /// "mounted, but nothing is mounted" state cannot exist.
    case mounted(volumeNames: [String])

    /// Build the state from a list of mounted volume names.
    public init(mountedVolumeNames: [String]) {
        self = mountedVolumeNames.isEmpty ? .unmounted
                                          : .mounted(volumeNames: mountedVolumeNames)
    }

    public var isMounted: Bool {
        if case .mounted = self { return true }
        return false
    }

    public var volumeNames: [String] {
        if case .mounted(let names) = self { return names }
        return []
    }
}

/// What `DADiskClaim` did (FR-SAFE-3).
public enum DiskClaimOutcome: Equatable {

    /// The claim callback arrived with no dissenter.
    case granted

    /// A dissenter refused the claim.
    ///
    /// Not observed in practice on macOS 26 — a contended claim goes ``timedOut``
    /// instead — but a dissenter is the documented refusal and is classified rather than
    /// left to fall through some default.
    case dissented(status: Int32, reason: String?)

    /// No callback arrived within the timeout.
    ///
    /// **This is not a failure of the call.** Measured 2026-07-30: a contended
    /// `DADiskClaim` is neither granted nor dissented, it stays pending indefinitely. So
    /// a timeout is the *positive* signal for FR-SAFE-4(b) — another process holds the
    /// disk — and a claim without a timeout would simply wedge the helper.
    case timedOut(afterSeconds: Int)

    /// The claim could not be attempted at all: no DiskArbitration session, or the disk
    /// reference could not be created. Fails closed.
    case sessionUnavailable(detail: String)
}

/// What `open(rawPath, O_RDWR | O_EXLOCK | O_NONBLOCK)` did (FR-SAFE-3).
///
/// The flags matter and are not interchangeable with a plain `O_RDWR`, which was
/// measured to exclude nobody: two independent opens of an unmounted raw disk both
/// succeeded. `O_EXLOCK` is the mechanism; `O_NONBLOCK` is what makes a contended open
/// return the error rather than block.
public enum ExclusiveOpenOutcome: Equatable {

    /// The exclusive open succeeded.
    case opened

    /// It failed with this `errno`.
    case failed(errnoCode: Int32)
}

// MARK: - Full Disk Access (NFR-INST-4)

/// Whether the helper can open a raw device node at all.
///
/// Added 2026-08-01 after measuring that **root is not sufficient**: the raw open is gated
/// by TCC, and a LaunchDaemon has no grant of its own. NFR-INST-4 requires this to be
/// detected and reported *before* a run is attempted, rather than surfacing as a run
/// failure — because `EPERM` from a privileged process reads as a hardware fault, and
/// sends the user to check a cable when the fix is a checkbox.
///
/// Three states rather than a `Bool`, deliberately. The probe can only be conclusive in
/// two directions; anything else must not be reported as either, in the same way
/// `HelperShutdownReadiness` refuses to let "could not ask" collapse into "unsafe".
public enum FullDiskAccessState: Equatable {

    /// A read-only open of the raw node succeeded, so the permission is in place.
    case granted

    /// The open failed `EPERM` — TCC refused it.
    case denied

    /// The probe could not settle the question: some other `errno`, or it was not run.
    /// Never reported as either granted or denied.
    case unknown(detail: String)

    /// Classify a probe's result.
    ///
    /// - Parameter openErrno: `nil` when the probe's open succeeded, otherwise its
    ///   `errno`.
    ///
    ///   What gets probed is deliberately **not** the device — see
    ///   `DeviceClaim.fullDiskAccessState()`. Measured 2026-08-01: the only device open
    ///   that reaches the TCC gate is `O_RDWR | O_EXLOCK`, and releasing that lock makes
    ///   DiskArbitration remount the volume milliseconds later, which would undo the
    ///   user's unmount on every poll. So the permission itself is checked instead.
    public static func from(openErrno: Int32?) -> FullDiskAccessState {
        guard let openErrno else { return .granted }
        switch openErrno {
        case EPERM:
            return .denied
        case EACCES:
            // Classic filesystem permissions, not TCC. The helper runs as root, so this
            // should not occur — and if it does, it is not the thing Full Disk Access
            // fixes, so it must not be reported as such.
            return .unknown(detail: "the raw device refused access (EACCES); the helper "
                                  + "may not be running as root")
        default:
            return .unknown(detail: "the raw device could not be opened "
                                  + "(errno \(openErrno), \(DeviceAccessRefusal.errnoText(openErrno)))")
        }
    }

    public var isDenied: Bool { self == .denied }

    /// What to tell the user, or `nil` when there is nothing to say.
    ///
    /// `granted` returns `nil` on purpose: a permission that is present is not news, and a
    /// banner that is always on screen is one nobody reads by the time it matters.
    public var explanation: String? {
        switch self {
        case .granted:
            return nil
        case .denied:
            return "This app needs Full Disk Access before it can test a drive. Open "
                 + "System Settings › Privacy & Security › Full Disk Access, add "
                 + "USBDriveTester, then try again. Administrator rights are not "
                 + "sufficient on their own — macOS gates direct access to removable "
                 + "drives separately."
        case .unknown(let detail):
            return "Could not confirm whether this app has permission to read the drive "
                 + "directly (\(detail)). A run may fail; if it does, check Full Disk "
                 + "Access in System Settings › Privacy & Security."
        }
    }
}

// MARK: - The verdict

/// Why raw device access was refused, in words the user can act on (NFR-USE-5).
///
/// `Equatable` so tests assert the *exact* refusal rather than merely that something was
/// refused. `CustomStringConvertible` because these strings cross the XPC boundary and
/// are shown verbatim: FR-SAFE-4 requires the message to name the actual cause, and
/// BUILD-PLAN Step 6.3 is explicit that a generic "couldn't start" is not acceptable.
public enum DeviceAccessRefusal: Error, Equatable, CustomStringConvertible {

    /// The named device is not something this tool may ever touch — not a USB whole disk
    /// with a real block-storage driver behind it.
    ///
    /// Checked by the helper against its *own* view of the IOKit registry, never against
    /// what the caller asserted (BUILD-PLAN Step 3.5: the helper independently re-checks
    /// device identity). Without it, any client that passes the Team-ID requirement could
    /// name the internal disk.
    case deviceNotEligible(bsdName: String, reason: String)

    /// **FR-SAFE-4(a)** — one or more volumes are still mounted.
    case volumesMounted(bsdName: String, volumeNames: [String])

    /// **FR-SAFE-4(b)** — volumes are unmounted, but the device node is held by another
    /// process, so exclusive whole-disk access cannot be acquired.
    case claimedByAnotherProcess(bsdName: String, detail: String)

    /// The device could not be opened, for a reason that is neither (a) nor (b).
    case deviceError(bsdName: String, errnoCode: Int32)

    /// A step of the sequence was skipped or could not be completed, so access was never
    /// established. Refuses — see "Failing closed" in the file header.
    case checkIncomplete(bsdName: String, detail: String)

    /// The open was refused with `EPERM` — the helper lacks **Full Disk Access**.
    ///
    /// Measured 2026-08-01 on real hardware. Opening `/dev/rdiskN` on an external drive
    /// makes the kernel consult TCC, and a LaunchDaemon that has not been granted access
    /// is refused:
    ///
    ///     tccd: Handling access request to kTCCServiceSystemPolicyAllFiles,
    ///           from Sub:{com.arc3solutions.USBDriveTester}
    ///           Resp:{…USBDriveTester.Helper, euid=0}
    ///           ReqResult(Auth Right: Denied (Service Policy))
    ///     sandboxd: kTCCServiceSystemPolicyRemovableVolumes denied by TCC
    ///
    /// Running as root is **not** sufficient, which is the surprising part and the reason
    /// this has its own case. The `exclusivity-probe` succeeds at the identical sequence
    /// only because `sudo` from Terminal inherits Terminal's own TCC grant.
    ///
    /// Note what TCC attributes the request to: the **app** bundle
    /// (`com.arc3solutions.USBDriveTester`), not the helper — so the grant belongs to the
    /// containing app, and moves with it.
    ///
    /// Kept distinct from ``deviceError(bsdName:errnoCode:)`` because the corrective step
    /// is completely different and entirely within the user's reach. Reporting this as
    /// "the device refused the open" sends someone to check their cable or suspect a
    /// failing drive, when the actual fix is a checkbox in System Settings.
    case accessNotPermitted(bsdName: String)

    /// The helper already holds a device, and it holds at most one at a time
    /// (FR-CTRL-9).
    ///
    /// Distinct from ``claimedByAnotherProcess(bsdName:detail:)`` on purpose, even though
    /// both mean "something has it". The holder here is *us*, so the corrective step is
    /// inside this app — release it, or stop the run — and telling the user to go hunting
    /// for another process would send them looking for something that does not exist.
    case alreadyHeld(bsdName: String, heldDeviceName: String)

    /// Wire code for this cause, so the app can offer the matching corrective control
    /// (an Unmount All button for (a) is useless for (b)) and so
    /// `scripts/claim-contention-test.sh` can assert the classification mechanically
    /// rather than by grepping prose.
    ///
    /// - Important: these values are duplicated by `DeviceAccessRefusalCause` in
    ///   `Shared/TesterControl.swift`, which is the app's copy — Core cannot be shared
    ///   with the app module. `DeviceAccessPreconditionTests.causeCodesMatchTheWireEnum`
    ///   pins the two together; it is the only place both are visible at once.
    public var causeCode: Int {
        switch self {
        case .deviceNotEligible:        return 1
        case .volumesMounted:           return 2
        case .claimedByAnotherProcess:  return 3
        case .deviceError:              return 4
        case .checkIncomplete:          return 5
        case .alreadyHeld:              return 6
        case .accessNotPermitted:       return 7
        }
    }

    public var description: String {
        switch self {
        case .deviceNotEligible(let bsdName, let reason):
            return "\(bsdName) cannot be tested: \(reason) This tool only ever opens USB "
                 + "mass-storage whole disks."

        case .volumesMounted(let bsdName, let volumeNames):
            let list = volumeNames.joined(separator: ", ")
            let subject = volumeNames.count == 1
                ? "the volume \(list) is"
                : "\(volumeNames.count) volumes (\(list)) are"
            return "Cannot start: on \(bsdName), \(subject) still mounted. Unmount "
                 + (volumeNames.count == 1 ? "it" : "them")
                 + " first — use Unmount All, or unmount in Disk Utility — then try again. "
                 + "Nothing was unmounted for you; starting a test never changes what is "
                 + "mounted."

        case .claimedByAnotherProcess(let bsdName, let detail):
            return "Cannot start: \(bsdName) has no mounted volumes, but its device node "
                 + "is held by another process, so exclusive whole-disk access cannot be "
                 + "acquired (\(detail)). Quit whatever is using the drive — Disk Utility, "
                 + "a disk-imaging or backup tool, or another copy of this app — and try "
                 + "again."

        case .accessNotPermitted(let bsdName):
            return "Cannot start: macOS refused this app permission to read \(bsdName) "
                 + "directly (errno \(EPERM), \(Self.errnoText(EPERM))). Nothing is wrong "
                 + "with the drive, and no volume is mounted — the privileged helper needs "
                 + "Full Disk Access. Open System Settings › Privacy & Security › Full Disk "
                 + "Access, add USBDriveTester, and try again. Running as an administrator "
                 + "is not sufficient on its own."

        case .deviceError(let bsdName, let errnoCode):
            return "Cannot start: opening \(bsdName) for exclusive access failed with "
                 + "errno \(errnoCode) (\(Self.errnoText(errnoCode))). This is not a "
                 + "mounted volume and not another process holding the node; the device "
                 + "itself refused the open."

        case .checkIncomplete(let bsdName, let detail):
            return "Cannot start: exclusive access to \(bsdName) could not be established "
                 + "(\(detail)). Refusing rather than proceeding, because a check that did "
                 + "not complete is not permission."

        case .alreadyHeld(let bsdName, let heldDeviceName):
            if bsdName == heldDeviceName {
                return "Cannot start: this app already holds exclusive access to "
                     + "\(bsdName). Release it before acquiring it again."
            }
            return "Cannot start: this app already holds exclusive access to "
                 + "\(heldDeviceName), and only one device can be held at a time. Release "
                 + "\(heldDeviceName) before acquiring \(bsdName)."
        }
    }

    /// `strerror`, without dragging a formatter into a pure type.
    static func errnoText(_ code: Int32) -> String {
        String(cString: strerror(code))
    }
}

/// The outcome of the acquire sequence.
public enum DeviceAccessDecision: Equatable {

    /// Every precondition holds; access may be granted.
    case acquire

    /// Access is refused, for this reason.
    case refuse(DeviceAccessRefusal)

    public var isRefusal: Bool {
        if case .refuse = self { return true }
        return false
    }

    /// The refusal, or `nil` when access was granted.
    public var refusal: DeviceAccessRefusal? {
        if case .refuse(let refusal) = self { return refusal }
        return nil
    }
}

// MARK: - The classifier

/// Decides whether the helper may take exclusive whole-disk access.
public enum DeviceAccessPrecondition {

    /// Classify the results of the acquire sequence.
    ///
    /// The sequence short-circuits — there is no point claiming a disk whose volumes are
    /// mounted — so the later inputs are optional, and `nil` means "not attempted". A
    /// `nil` that arrives when the sequence *should* have got that far is a programming
    /// error, and is refused as ``DeviceAccessRefusal/checkIncomplete(bsdName:detail:)``
    /// rather than defaulting to success.
    ///
    /// - Parameters:
    ///   - device: The validated device, already established as eligible by the caller.
    ///   - mountState: The **helper's own** view of what is mounted (FR-SAFE-1/2). Never
    ///     the caller's — the whole point of the guard is that it does not take the
    ///     client's word for it.
    ///   - claim: What `DADiskClaim` did, or `nil` if it was not attempted.
    ///   - exclusiveOpen: What the `O_EXLOCK` open did, or `nil` if it was not attempted.
    public static func evaluate(device: WholeDiskName,
                                mountState: MountState,
                                claim: DiskClaimOutcome?,
                                exclusiveOpen: ExclusiveOpenOutcome?) -> DeviceAccessDecision {

        let bsdName = device.rawValue

        // 1. Mounted volumes — FR-SAFE-4(a). First, because it is the only check that
        //    distinguishes the two causes, and because it is the common case with a
        //    one-click fix. Note what does NOT happen here: nothing is unmounted
        //    (FR-SAFE-6). Unmounting is only ever the result of the user pressing the
        //    control, never a side effect of starting a test.
        if mountState.isMounted {
            return .refuse(.volumesMounted(bsdName: bsdName,
                                           volumeNames: mountState.volumeNames))
        }

        // 2. The DiskArbitration claim — mandatory, not defensive. Measured: the moment a
        //    claim is released, macOS silently remounts the volume. Unmounting alone does
        //    not keep a disk unmounted for the hours a run can take.
        guard let claim else {
            return .refuse(.checkIncomplete(
                bsdName: bsdName,
                detail: "the DiskArbitration claim was never attempted"))
        }

        switch claim {
        case .granted:
            break

        case .timedOut(let seconds):
            // A pending claim IS cause (b). See DiskClaimOutcome.timedOut.
            return .refuse(.claimedByAnotherProcess(
                bsdName: bsdName,
                detail: "the DiskArbitration claim was still pending after \(seconds)s; a "
                      + "claim contended by another process is never refused outright, it "
                      + "simply never completes"))

        case .dissented(let status, let reason):
            let hex = String(UInt32(bitPattern: status), radix: 16)
            return .refuse(.claimedByAnotherProcess(
                bsdName: bsdName,
                detail: reason.map { "DiskArbitration refused the claim: \($0)" }
                     ?? "DiskArbitration refused the claim (status 0x\(hex))"))

        case .sessionUnavailable(let detail):
            return .refuse(.checkIncomplete(bsdName: bsdName, detail: detail))
        }

        // 3. The exclusive open — this is what actually excludes another writer. A plain
        //    O_RDWR open does not (measured), so nothing short of a successful O_EXLOCK
        //    open counts as exclusivity here.
        guard let exclusiveOpen else {
            return .refuse(.checkIncomplete(
                bsdName: bsdName,
                detail: "the exclusive open of \(device.rawDevicePath) was never attempted"))
        }

        switch exclusiveOpen {
        case .opened:
            return .acquire

        case .failed(let code) where code == EBUSY:
            // We already know nothing is mounted, so EBUSY here can only be another
            // holder. This is the second of the two paths to cause (b): the claim can be
            // granted and the open still lose, because they are different mechanisms.
            return .refuse(.claimedByAnotherProcess(
                bsdName: bsdName,
                detail: "opening \(device.rawDevicePath) with O_EXLOCK returned EBUSY "
                      + "while no volume is mounted"))

        case .failed(let code) where code == EPERM:
            // TCC, not the device — measured 2026-08-01. Root is not sufficient; the
            // helper needs Full Disk Access. Separated from the generic device error
            // because the fix is a checkbox, not a cable.
            return .refuse(.accessNotPermitted(bsdName: bsdName))

        case .failed(let code):
            return .refuse(.deviceError(bsdName: bsdName, errnoCode: code))
        }
    }
}

// MARK: - The write guard (NFR-REL-3)

/// Proof that exclusive whole-disk access is held, in terms a pure type can express.
///
/// The helper's `AcquiredDevice` — which owns the real file descriptor and the real
/// DiskArbitration claim — carries one of these and can only be constructed by a
/// successful acquire. Steps 7/8's write path takes the `AcquiredDevice` as a parameter,
/// so *no value, no write path*: the guard cannot be forgotten at a call site, because
/// there is no call site without it.
///
/// This type is the runtime half of that guarantee. The compile-time half stops a write
/// being attempted with no access at all; this stops one being attempted against the
/// **wrong device**, or with a grant that is only half-held — which the type system
/// cannot see, because a grant is still a grant after its fd has been closed.
public struct DeviceAccessGrant: Equatable {

    /// Canonical name of the device access is held on.
    public let deviceName: String

    /// Whether the DiskArbitration claim is held (anti-remount, FR-SAFE-3).
    public let claimHeld: Bool

    /// Whether the `O_EXLOCK` open is held (write exclusion, FR-SAFE-3).
    public let exclusiveOpenHeld: Bool

    public init(deviceName: String, claimHeld: Bool, exclusiveOpenHeld: Bool) {
        self.deviceName = deviceName
        self.claimHeld = claimHeld
        self.exclusiveOpenHeld = exclusiveOpenHeld
    }

    /// Convenience for the only state in which a grant is complete.
    public init(fullyHeldOn device: WholeDiskName) {
        self.init(deviceName: device.rawValue, claimHeld: true, exclusiveOpenHeld: true)
    }

    /// Whether both halves are held. Neither alone is sufficient: the claim keeps macOS
    /// from remounting, the `O_EXLOCK` open keeps another process from writing.
    public var isComplete: Bool { claimHeld && exclusiveOpenHeld }
}

/// Why a write was refused at the guard.
public enum WritePreconditionViolation: Error, Equatable, CustomStringConvertible {

    /// No access is held at all.
    case noAccessHeld(requested: String)

    /// Access is held, but on a different device than the one being written to. The
    /// dangerous one: a write that lands on the wrong drive is the failure this whole
    /// tool is built to avoid.
    case wrongDevice(held: String, requested: String)

    /// The DiskArbitration claim is not held, so macOS may remount mid-write.
    case claimNotHeld(String)

    /// The exclusive open is not held, so another process may be writing too.
    case exclusiveOpenNotHeld(String)

    public var description: String {
        switch self {
        case .noAccessHeld(let requested):
            return "Refusing to write to \(requested): no exclusive access is held."
        case .wrongDevice(let held, let requested):
            return "Refusing to write to \(requested): exclusive access is held on "
                 + "\(held), not on \(requested)."
        case .claimNotHeld(let device):
            return "Refusing to write to \(device): the DiskArbitration claim is not "
                 + "held, so the system could remount a volume mid-write."
        case .exclusiveOpenNotHeld(let device):
            return "Refusing to write to \(device): the device is not open exclusively, "
                 + "so another process could be writing to it at the same time."
        }
    }
}

/// The hard precondition on every block write (NFR-REL-3, BUILD-PLAN Step 6.4).
///
/// BUILD-PLAN is explicit that this is "an assertion at the top of the write path, not
/// just a UI check". It is a `throw` rather than a `precondition` because a root daemon
/// should refuse and report, not trap: crashing while holding a claim would leave the
/// disk claimed and the volume unmountable until launchd restarted us.
public enum WritePrecondition {

    /// Check that a write to `device` may proceed.
    ///
    /// - Parameters:
    ///   - grant: What the helper holds, or `nil` if it holds nothing.
    ///   - device: Canonical name of the device about to be written to.
    /// - Throws: ``WritePreconditionViolation``.
    public static func check(_ grant: DeviceAccessGrant?, writingTo device: String) throws {
        guard let grant else {
            throw WritePreconditionViolation.noAccessHeld(requested: device)
        }
        guard grant.deviceName == device else {
            throw WritePreconditionViolation.wrongDevice(held: grant.deviceName,
                                                         requested: device)
        }
        guard grant.claimHeld else {
            throw WritePreconditionViolation.claimNotHeld(device)
        }
        guard grant.exclusiveOpenHeld else {
            throw WritePreconditionViolation.exclusiveOpenNotHeld(device)
        }
    }
}
