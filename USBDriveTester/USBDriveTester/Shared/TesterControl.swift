//
//  TesterControl.swift
//  Shared between the unprivileged app and the privileged helper.
//
//  This is the *versioned XPC contract* (NFR-MAINT-1) and the single source of
//  truth for the helper's identity. It is deliberately kept as small as the current
//  build step allows (NFR-SEC-3): every method here is reachable by anything that
//  passes the helper's code-signature check, so the surface is widened only when a
//  step actually needs it.
//
//  Current surface:
//    * ping                   — liveness / plumbing (carried from Step 1)
//    * protocolVersion        — the version handshake (NFR-MAINT-1)
//    * validateRunParameters  — boundary parameter validation (NFR-REL-7)
//    * prepareForShutdown     — teardown handshake (Step 4; NFR-INST-3, NFR-REL-5)
//
//  Deferred on purpose: startRun / pause / resume / stop and the helper -> GUI
//  progress-callback protocol. Those need Step 6's exclusive device claim, Step 7's
//  real geometry, Step 9's metrics and Step 11's state machine to be meaningful;
//  stubbing them now would be dead code AND attack surface. Widening the protocol
//  later is cheap, walking a wide one back is not (BUILD-PLAN Step 3, risks).
//
//  IMPORTANT (trust boundary): this file must be a member of BOTH the app target
//  and the helper target. With Xcode's file-system-synchronized groups it joins
//  the app target automatically because it lives under the app's folder; the helper
//  target membership was added in Step 1 via the File Inspector.
//
//  It is ALSO compiled standalone (by swiftc, with tools/negative-client/main.swift)
//  to build the adhoc-signed client that proves the helper rejects foreign callers.
//  Keep this file free of any app-only or helper-only dependency: Foundation only.
//

import Foundation

/// The XPC interface vended by the privileged helper.
///
/// Must be `@objc` so it can be wrapped by `NSXPCInterface`. Every method is
/// asynchronous with a reply block, as required by the NSXPC reply-based model, and
/// every parameter is an ObjC-representable primitive so nothing needs a custom
/// `NSSecureCoding` whitelist on the interface.
@objc public protocol TesterControl {

    /// Liveness / plumbing check. Replies with `"pong"`.
    ///
    /// Step 1 used this to confirm the connection, the interface wiring and the
    /// reply path across the process boundary. Step 3 re-uses it as the first
    /// acceptance item, this time through the *SMAppService-registered* daemon
    /// rather than a manually bootstrapped one.
    func ping(reply: @escaping (String) -> Void)

    /// Replies with the protocol version the *helper* implements.
    ///
    /// The GUI compares this against ``TesterProtocol/version`` on connect and
    /// refuses to issue further commands on a mismatch (NFR-MAINT-1). This matters
    /// because the app and the helper are separately installed artefacts: an app
    /// update can land while an older registered daemon is still resident.
    func protocolVersion(reply: @escaping (Int) -> Void)

    /// Ask the helper to validate a prospective run's addressing parameters.
    ///
    /// The helper re-checks alignment and range *itself* rather than trusting the
    /// caller (NFR-REL-7, NFR-SEC-3). It runs as root, so every byte arriving over
    /// this connection is untrusted input even though the connection is
    /// code-signature-authenticated — authentication says *who* is calling, not that
    /// what they sent is sane.
    ///
    /// - Note: `logicalBlockSize` and `deviceBlockCount` are supplied by the caller
    ///   **for Step 3 only**, because the helper has no device-access code until
    ///   Steps 6/7. From Step 7 the helper derives geometry itself via
    ///   `DKIOCGETBLOCKSIZE`/`DKIOCGETBLOCKCOUNT` on the opened raw device and the
    ///   caller-supplied values are dropped entirely. The validation *logic*
    ///   (`RunParameterValidator`) is unchanged by that switch — only where the
    ///   geometry comes from changes.
    ///
    /// - Parameters:
    ///   - byteOffset: Start of the prospective transfer, in bytes from block 0.
    ///   - byteLength: Length of the prospective transfer, in bytes.
    ///   - logicalBlockSize: Device logical block size (512 or 4096, NFR-COMPAT-5).
    ///   - deviceBlockCount: Total addressable blocks (64-bit, NFR-COMPAT-6).
    ///   - reply: `(accepted, message)`. `message` is always human-readable and
    ///     names the actual cause on rejection, never a generic failure (NFR-USE-5).
    func validateRunParameters(byteOffset: UInt64,
                               byteLength: UInt64,
                               logicalBlockSize: UInt32,
                               deviceBlockCount: UInt64,
                               reply: @escaping (Bool, String) -> Void)

    /// Ask the helper whether it is safe to remove, and — if it is — have it release
    /// everything it holds (NFR-INST-3, NFR-REL-5).
    ///
    /// The GUI calls this immediately before `SMAppService.unregister()`. The helper
    /// is the authority here, not the GUI: the GUI's own notion of "a run is active"
    /// lives in a process that can be force-quit and relaunched, whereas the helper
    /// is the process actually holding the device node and the DiskArbitration claim.
    ///
    /// - Important: the helper **refuses** while busy rather than releasing on
    ///   demand. That is deliberate on two counts. It keeps a torn-down run from
    ///   leaving a half-written device (NFR-REL-5), and it means this method cannot
    ///   be used by *any* caller — even one correctly signed under our Team ID — to
    ///   abort a run in progress. Refusing is the safe direction for both.
    ///
    /// - Note: callers must treat a failure of this call as "unknown", not as
    ///   "unsafe". An uninstall must never be blocked by a helper that is wedged,
    ///   unreachable, or too old to implement this method — a privileged daemon that
    ///   cannot be removed is a worse outcome than the one being guarded against.
    ///   See `UninstallPrecondition` on the app side.
    ///
    /// - Parameter reply: `(safeToRemove, message)`. `message` explains what was
    ///   released, or names precisely what is still in progress (NFR-USE-5).
    func prepareForShutdown(reply: @escaping (Bool, String) -> Void)

    /// Ask the helper what it can tell about a device **without touching it**
    /// (FR-SAFE-1/2, Step 6).
    ///
    /// Read-only and side-effect-free, which is the whole reason it is a separate method
    /// from ``acquireDevice(bsdName:reply:)``. The GUI has to show "2 volumes mounted"
    /// *before* Start is pressed, and a check with side effects cannot drive a display —
    /// it is safe to poll, and safe to call on every selection change.
    ///
    /// - Important: this **cannot** detect FR-SAFE-4 cause (b). Establishing that another
    ///   process holds the node requires actually attempting the claim and the exclusive
    ///   open, which are side effects — the claim in particular would keep the disk from
    ///   remounting. So a `ready` of `true` means "nothing here would refuse an acquire",
    ///   not "an acquire will succeed". Only ``acquireDevice(bsdName:reply:)`` can say
    ///   the latter, and it is the only thing that may permit a run.
    ///
    /// - Parameters:
    ///   - bsdName: Whole-disk BSD name, e.g. `disk4`. Validated by the helper; the app's
    ///     assertion about it is not trusted (NFR-REL-7).
    ///   - reply: `(ready, mountedVolumeCount, mountedVolumeSummary, helperHoldsThisDevice,
    ///     blockingCause, message)`. `mountedVolumeSummary` is a comma-separated list,
    ///     empty when nothing is mounted — a `String` rather than an array so the
    ///     interface needs no `NSSecureCoding` class whitelist, keeping every parameter on
    ///     this protocol an ObjC-representable primitive.
    ///
    ///     `blockingCause` is a ``DeviceAccessRefusalCause`` raw value, or `0` when
    ///     nothing is blocking. It exists so the GUI can offer the *matching* corrective
    ///     control — Unmount All for a mounted volume, Open Settings for a missing Full
    ///     Disk Access grant — which a message string alone cannot drive.
    ///
    ///     The Full Disk Access check (NFR-INST-4) is folded in here rather than given its
    ///     own method: it answers the same question this method already asks — "could a
    ///     run start on this device right now?" — and widening the privileged surface with
    ///     a second query would be the wrong trade (NFR-SEC-3).
    func checkDeviceReadiness(bsdName: String,
                              reply: @escaping (Bool, Int, String, Bool, Int, String) -> Void)

    /// Take exclusive whole-disk access, or refuse with a precise cause (FR-SAFE-3/4).
    ///
    /// The helper verifies the device's identity, verifies nothing is mounted, claims the
    /// disk through DiskArbitration with a timeout, and opens `/dev/rdiskN` with
    /// `O_EXLOCK`. All four must succeed. **Nothing is ever unmounted** as part of this
    /// (FR-SAFE-6): a mounted volume produces a refusal naming it, not an unmount.
    ///
    /// On success the helper holds the claim and the descriptor until
    /// ``releaseDevice(reply:)``, the connection drops, or the daemon exits. It must:
    /// macOS silently remounts a volume the moment a claim is released (measured
    /// 2026-07-30), so the claim is what keeps the device unmounted for the run's whole
    /// duration.
    ///
    /// - Parameter reply: `(acquired, causeCode, message)`. On success `causeCode` is 0.
    ///   On refusal it is a ``DeviceAccessRefusalCause`` raw value, so the app can offer
    ///   the matching corrective control; `message` always names the actual cause and the
    ///   corrective step (NFR-USE-5).
    func acquireDevice(bsdName: String,
                       reply: @escaping (Bool, Int, String) -> Void)

    /// Release whatever device the helper holds (NFR-REL-5).
    ///
    /// Takes no device name because the helper holds at most one device at a time
    /// (FR-CTRL-9). Idempotent: releasing when nothing is held succeeds and says so.
    ///
    /// - Important: a successful reply does **not** mean the device is immediately
    ///   reusable. Release is asynchronous — an open straight after `DADiskUnclaim` can
    ///   still see `EBUSY` — so no caller may treat this as "the device is free now".
    ///
    /// - Parameter reply: `(released, message)`. `message` describes what was released.
    func releaseDevice(reply: @escaping (Bool, String) -> Void)
}

/// Why the helper refused exclusive whole-disk access, as it travels over the wire.
///
/// FR-SAFE-4 requires the two causes to be told apart, and the message strings already
/// do that for the user. This exists so the *app* can tell them apart too: cause (a) has
/// a one-click fix and should surface the Unmount All control, cause (b) does not and
/// offering it there would be misleading. It also lets `scripts/claim-contention-test.sh`
/// assert the classification mechanically rather than by grepping prose.
///
/// - Important: these raw values are duplicated by `DeviceAccessRefusal.causeCode` in
///   `Core/DeviceAccessPrecondition.swift`, which is where the classification actually
///   happens. The two cannot be one type: Core compiles into the helper and the test
///   target but deliberately **not** into the app module, and this file compiles into the
///   app and the helper. `DeviceAccessPreconditionTests.causeCodesMatchTheWireEnum` is
///   the only place both are visible at once, and it pins them together.
public enum DeviceAccessRefusalCause: Int {

    /// The named device is not a USB mass-storage whole disk.
    case deviceNotEligible = 1

    /// **FR-SAFE-4(a)** — one or more of the device's volumes are still mounted.
    case volumesMounted = 2

    /// **FR-SAFE-4(b)** — unmounted, but the device node is held by another process.
    case claimedByAnotherProcess = 3

    /// The open failed for some other reason; the message names the `errno`.
    case deviceError = 4

    /// A step of the acquire sequence did not complete, so access was never established.
    /// Refuses: a check that did not complete is not permission.
    case checkIncomplete = 5

    /// The helper already holds a device, and holds at most one at a time (FR-CTRL-9).
    /// The corrective step is inside this app, not in some other process.
    case alreadyHeld = 6

    /// TCC refused the raw-device open: the helper needs **Full Disk Access**. Running as
    /// root is not sufficient. Measured 2026-08-01 — see `DeviceAccessRefusal`.
    case accessNotPermitted = 7

    /// Anything the app does not recognise — a helper newer than this app. Treated as a
    /// refusal with no specific corrective control, never as success.
    case unrecognised = 0

    /// Map a wire value, never trapping on one this build does not know.
    public init(wireValue: Int) {
        self = DeviceAccessRefusalCause(rawValue: wireValue) ?? .unrecognised
    }
}

/// Version of the ``TesterControl`` contract (NFR-MAINT-1).
///
/// Bump ``version`` whenever a change would break an older peer: removing or
/// renaming a method, changing a signature, or changing the meaning of an argument.
/// Purely additive changes that an older peer simply never calls do not require a
/// bump, but bumping is cheap and a mismatch is far easier to diagnose than a
/// silently missing method.
public enum TesterProtocol {

    /// History:
    /// - **1** — Step 3: `ping`, `protocolVersion`, `validateRunParameters`.
    /// - **2** — Step 4: adds `prepareForShutdown`.
    /// - **3** — Step 6: adds `checkDeviceReadiness`, `acquireDevice`, `releaseDevice` —
    ///   the mount guard and the exclusive whole-disk claim (FR-SAFE-1/2/3/4).
    /// - **4** — Step 6, after measuring that the helper needs **Full Disk Access**
    ///   (NFR-INST-4, added 2026-08-01): `checkDeviceReadiness` gains a `blockingCause`
    ///   so the GUI can offer the matching corrective control, and now reports a missing
    ///   Full Disk Access grant *before* a run is attempted rather than as a run failure.
    ///   A signature change, so a bump is mandatory rather than merely cheap — a v3
    ///   daemon would decode the reply block differently.
    ///
    /// The bump matters in practice, not just on paper: the app and the daemon are
    /// separately installed artefacts, so after an app update a **v2 daemon can still
    /// be registered** until the user reinstalls it. Such a daemon does not implement
    /// the device methods and will fail those calls. The teardown path is written to
    /// tolerate exactly that (see `prepareForShutdown`'s note on treating failure as
    /// "unknown"), which is what makes an old daemon removable rather than stuck.
    ///
    /// Note the asymmetry that comes with Step 6: teardown tolerates an out-of-date
    /// daemon on purpose, but the device methods must **not**. A helper that cannot
    /// answer `acquireDevice` has not granted access, and treating a failed call as
    /// anything but a refusal would put a run on a device nobody claimed.
    public static let version = 4
}

/// Single source of truth for the helper's identity and the trust it is pinned to.
///
/// The identity string is used, unchanged, as:
///   * the LaunchDaemon `Label`,
///   * the advertised Mach service name,
///   * the base name of the `SMAppService` daemon plist, and
///   * the helper's `CFBundleIdentifier` (embedded via
///     `CREATE_INFOPLIST_SECTION_IN_BINARY` on the helper target).
///
/// Keeping it here prevents those from drifting apart — a mismatch between them is
/// the single most common cause of `SMAppService` returning `.notFound`.
public enum HelperIdentity {

    /// Reverse-DNS identity of the privileged helper.
    public static let machServiceName = "com.arc3solutions.USBDriveTester.Helper"

    /// Bundle identifier of the unprivileged GUI app that owns this helper. Must
    /// match the daemon plist's `AssociatedBundleIdentifiers`, which is what makes
    /// the daemon appear under the app's name in System Settings (NFR-INST-1).
    public static let appBundleIdentifier = "com.arc3solutions.USBDriveTester"

    /// Unified-logging subsystem shared by **both** executables.
    ///
    /// The app and the helper deliberately log under one subsystem so a single
    /// predicate shows the whole trace across the trust boundary — which is exactly
    /// what Step 15's gate asks for:
    /// `log show --predicate 'subsystem == "com.arc3solutions.USBDriveTester"'`.
    /// Categories (`xpc`, `lifecycle`, `discovery`, `safety`, `io`, `metrics`) are
    /// what separate them (NFR-OBS-1).
    public static let loggingSubsystem = "com.arc3solutions.USBDriveTester"

    /// File name passed to `SMAppService.daemon(plistName:)`. Resolved by the system
    /// against `Contents/Library/LaunchDaemons/` inside the registering app bundle.
    public static var daemonPlistName: String { "\(machServiceName).plist" }

    /// The Apple Developer **Team ID** every accepted client must be signed under.
    ///
    /// This is the `OU` field of the signing certificate's subject — verified
    /// against the local `Apple Development` identity on 2026-07-25:
    /// `UID=N9Y2LXCNFE, CN=Apple Development: … (424WY3TDB4), OU=5JC55GTLZA`.
    /// Note that the identifier in the certificate's common name (`424WY3TDB4`) is
    /// the *individual* ID and is NOT the Team ID — pinning that would reject our
    /// own client.
    public static let expectedTeamID = "5JC55GTLZA"

    /// Code-signing requirement the helper imposes on every incoming XPC peer
    /// (FR-ARCH-5, NFR-SEC-2).
    ///
    /// `anchor apple generic` establishes that the leaf chains to an Apple-issued
    /// developer certificate — without it, anyone could mint a self-signed
    /// certificate carrying our Team ID in its `OU` and walk straight through.
    /// The `OU` clause then pins that certificate to our team.
    ///
    /// Per NFR-SEC-2 (resolved 2026-06-25) Team-ID match is the accepted bar: the
    /// bundle identifier is deliberately **not** additionally pinned, so the app can
    /// be renamed or split without breaking the helper contract.
    public static var codeSigningRequirement: String {
        "anchor apple generic and certificate leaf[subject.OU] = \"\(expectedTeamID)\""
    }
}
