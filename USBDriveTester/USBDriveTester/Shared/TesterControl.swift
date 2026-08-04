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
//    * checkDeviceReadiness   — side-effect-free mount/permission check (Step 6)
//    * acquireDevice          — the exclusive whole-disk claim (Step 6)
//    * releaseDevice          — release it (Step 6)
//    * deviceProfile          — geometry + cache-bypass verdict for the held device (Step 7)
//    * runRetentionCycle      — the read -> write-back -> verify cycle, bounded (Step 8)
//    * digestRange            — SHA-256 of a bounded range of the held device (Step 8)
//
//  Deferred on purpose: pause / resume / stop and the helper -> GUI progress-callback
//  protocol. Those need Step 9's metrics and Step 11's state machine to be meaningful;
//  stubbing them now would be dead code AND attack surface. Widening the protocol
//  later is cheap, walking a wide one back is not (BUILD-PLAN Step 3, risks).
//
//  NOTE (Step 8): `runRetentionCycle` is the FIRST method here that writes to a drive. The
//  surface stayed narrow rather than growing a `startRun` family, and the call is bounded to
//  `TesterProtocol.maximumBytesPerCall` precisely so it cannot quietly become the
//  run-control API Step 11 is meant to design properly.
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

    /// What the helper established about the device it is holding (Step 7).
    ///
    /// **Passive and side-effect-free.** It performs no I/O and opens nothing: everything it
    /// reports was determined during ``acquireDevice(bsdName:reply:)``, when the descriptor
    /// was configured and the geometry ioctls were issued. Safe to call repeatedly.
    ///
    /// Requires a device to be held. There is no other way to obtain this information —
    /// geometry comes from `DKIOCGETBLOCKSIZE`/`DKIOCGETBLOCKCOUNT` on the open descriptor,
    /// and opening the raw node speculatively to answer a query is precisely what makes
    /// DiskArbitration remount the volume ~4 ms later (measured 2026-08-01). The requirement
    /// is therefore structural, not a policy choice.
    ///
    /// - Note: one method rather than separate geometry and cache-bypass queries. They were
    ///   originally split because the cache-bypass check was going to perform two timed reads;
    ///   `scripts/nocache-calibration.sh` showed re-read timing cannot discriminate on a raw
    ///   character device, so that check became structural and passive, and a second privileged
    ///   method would have bought nothing (NFR-SEC-3).
    ///
    /// - Parameter reply: `(available, ioctlBlockSize, ioctlBlockCount, ioKitBlockSize,
    ///   ioKitBlockCount, cacheBypassCode, usbLinkSpeedCode, maximumByteCountRead, message)`.
    ///
    ///   **Both geometries are reported**, deliberately. The ioctl values are authoritative
    ///   (BUILD-PLAN 7.3) and the IOKit values are what the helper independently read from the
    ///   registry; returning both lets the gate compare each against `diskutil info` and makes
    ///   any disagreement visible rather than absorbed. A disagreement is not fatal — the ioctl
    ///   block count is the bound the kernel itself enforces on every transfer — but it is
    ///   never silent.
    ///
    ///   `cacheBypassCode` is a ``CacheBypassOutcome`` raw value. `usbLinkSpeedCode` is the raw
    ///   IORegistry `Device Speed` code, or `-1` when the registry reported none;
    ///   `maximumByteCountRead` is `0` when the device did not answer. Both are diagnostic:
    ///   `disk4` advertises a 1 MiB maximum read yet returns a full 8 MiB `pread` in one call,
    ///   because the kernel splits transfers internally (measured 2026-08-02).
    func deviceProfile(reply: @escaping (Bool, UInt32, UInt64, UInt32, UInt64,
                                          Int, Int, UInt64, String) -> Void)

    /// Run the read → write-back → read-verify cycle over a **bounded** range of the held
    /// device (Step 8, FR-TEST-1/3/4/7/8, FR-FAIL-6, NFR-REL-1/2/4/8).
    ///
    /// **This is the only method on this interface that writes to a drive.**
    ///
    /// Requires a device to be held — `acquireDevice` is what proves nothing is mounted and
    /// that exclusive access was taken (NFR-REL-3), and the write guard is re-checked inside
    /// the cycle before **every** chunk, not once at the start.
    ///
    /// ## Why it is bounded, and why that is not a placeholder
    ///
    /// A whole-device run on a 1 TB drive moves 3 TB and takes hours. There is no way to
    /// cancel one until Step 11's state machine, and no progress channel until Step 9's
    /// metrics callbacks. An uncancellable privileged operation that any accepted caller can
    /// start must therefore be **bounded by construction** — otherwise a single call wedges a
    /// root daemon for hours, with `prepareForShutdown` correctly refusing the whole time and
    /// nothing able to stop it.
    ///
    /// So a request may cover at most ``TesterProtocol/maximumBytesPerCall``. At
    /// `disk4`'s measured 475 MB/s that is about 6.8 s of work, and about 15 s at the 200 MB/s
    /// floor a slower device might manage. Step 11 replaces this with real run control; until
    /// then, this is what Step 8's hardware gate drives and it is deliberately not enough to
    /// serve as a substitute for the run-control machinery.
    ///
    /// - Parameters:
    ///   - startBlock: first block of the range, in the device's **logical** blocks.
    ///   - blockCount: how many blocks to cover. The range is tiled into chunks of
    ///     `ioSizeBytes` from `startBlock`, and the final chunk is the exact remainder
    ///     (FR-TEST-5), so a `blockCount` that is not a whole multiple of the I/O size is
    ///     legal and is how the short-chunk path gets exercised.
    ///   - ioSizeBytes: one of ``TesterProtocol/permittedIOSizes`` (FR-CTRL-8). The helper
    ///     validates this rather than trusting it (NFR-REL-7): the *engine* accepts any
    ///     positive multiple of the block size so tests can use awkward sizes, but nothing
    ///     across this boundary may.
    ///   - reply: `(completed, chunksProcessed, failedRangeCount, failureSummary,
    ///     cacheBypassCode, fastestObservedBytesPerSecond, bufferBytesHeld, message)`.
    ///
    ///     `completed` is `true` only when every chunk in the range was processed — it says
    ///     nothing about whether they all *passed*, because a run that finds bad blocks and
    ///     keeps going still completes (FR-FAIL-3). `failedRangeCount` and `failureSummary`
    ///     are how the result is judged; the summary carries block addressing only, never
    ///     device contents (NFR-SEC-6).
    ///
    ///     `cacheBypassCode` is a ``CacheBypassOutcome`` raw value — the FR-TEST-9 verdict as
    ///     it stood at the **end** of the run, which is the acquire-time verdict possibly
    ///     downgraded by what the run's own throughput revealed. It never improves.
    ///     `fastestObservedBytesPerSecond` is what the falsifier actually measured, so a gate
    ///     can assert the reads were transport-plausible rather than only that a threshold was
    ///     not crossed. `bufferBytesHeld` is NFR-PERF-1's figure: 2 × the I/O size,
    ///     whatever the range's size.
    func runRetentionCycle(startBlock: UInt64,
                           blockCount: UInt64,
                           ioSizeBytes: Int,
                           reply: @escaping (Bool, UInt64, Int, String,
                                             Int, Double, Int, String) -> Void)

    /// SHA-256 of a bounded range of the **held** device (Step 8, gate item 5).
    ///
    /// Read-only. It exists so a gate can establish that a retention cycle left the rest of the
    /// device untouched — which the cycle's own verify cannot show, because that comparison only
    /// covers the offset the cycle meant to write. A write landing somewhere else is invisible
    /// to it, so a run can report "0 bad blocks" and still have moved data.
    ///
    /// ## Why this is on the privileged interface at all
    ///
    /// It was a separate process — `tools/media-digest` — until it was measured on hardware
    /// (2026-08-02) that **it cannot be**. While the helper holds `O_EXLOCK`, a second process
    /// that is root, carries Terminal's Full Disk Access grant, and requests *no lock at all* is
    /// refused `EBUSY`. And the fingerprints have to be taken while the claim is held: releasing
    /// makes DiskArbitration remount the volume ~4 ms later, and a mounted exFAT volume writes
    /// to itself, so an "after" fingerprint taken post-release would differ for reasons that
    /// have nothing to do with the cycle.
    ///
    /// The classification itself lives in `Core/DeviceDigest.swift` and is unit-tested against
    /// known SHA-256 vectors — because a fingerprint taken by the same process on both sides of
    /// a cycle is only evidence if the fingerprint function is known to work. A digest that
    /// returned a constant would make "before == after" pass unconditionally.
    ///
    /// - Parameters:
    ///   - startBlock: first block, in the device's logical blocks.
    ///   - blockCount: how many blocks. Bounded by ``TesterProtocol/maximumBytesPerCall`` for
    ///     the same reason `runRetentionCycle` is: there is no cancellation until Step 11, so an
    ///     uncancellable privileged call must be bounded by construction. A caller covering a
    ///     whole device issues one call per gibibyte.
    ///   - reply: `(ok, bytesCovered, sha256Hex, message)`. `sha256Hex` is lower-case hex, empty
    ///     on failure. A hash is a fingerprint, not the data (NFR-SEC-6).
    func digestRange(startBlock: UInt64,
                     blockCount: UInt64,
                     reply: @escaping (Bool, UInt64, String, String) -> Void)
}

/// Whether the helper could establish that its reads reach the device (FR-TEST-9), as it
/// travels over the wire.
///
/// - Important: these raw values are duplicated by `CacheBypassState.wireCode` in
///   `Core/CacheBypassCheck.swift`, which is where the classification happens, for the same
///   reason `DeviceAccessRefusalCause` is duplicated: Core compiles into the helper and the
///   test target but deliberately **not** into the app module. A test pins the two together.
public enum CacheBypassOutcome: Int {

    /// The descriptor is the raw character device with caching disabled. The verify comparison
    /// means what it says.
    case bypassed = 1

    /// Something can answer a read without the device. **The verify result is not
    /// trustworthy** — but the run's read → write-back still refreshed the medium, so a run
    /// continues and its result is qualified rather than discarded.
    case likelyCached = 2

    /// The question could not be settled. Never treated as either of the above.
    case inconclusive = 3

    /// Anything this build does not recognise — a helper newer than this app. Treated as
    /// inconclusive, never as success.
    case unrecognised = 0

    public init(wireValue: Int) {
        self = CacheBypassOutcome(rawValue: wireValue) ?? .unrecognised
    }

    /// Does this outcome qualify the run's verify result (FR-TEST-9)?
    public var qualifiesVerifyResult: Bool { self != .bypassed }
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
    /// - **5** — Step 7: adds `deviceProfile`, reporting the ioctl-derived geometry, the
    ///   helper's own IOKit geometry for comparison, the FR-TEST-9 cache-bypass verdict, the
    ///   negotiated USB link speed and the advertised maximum read. Purely **additive** — a v4
    ///   client's existing calls decode identically — but bumped anyway, because an app that
    ///   needs the profile must be able to tell a helper that cannot provide it from one that
    ///   can, and a missing method surfaces as a transport failure rather than as "too old".
    /// - **6** — Step 8: adds `runRetentionCycle`, the read → write-back → read-verify cycle
    ///   over a bounded range of the held device. Additive, and bumped for the same reason as
    ///   v5 — but this one matters more than either: it is **the first method that writes to a
    ///   drive**. A client that believes it is talking to a v6 daemon and is not must find out
    ///   from the version handshake, not from a call that silently does nothing.
    /// - **7** — Step 8, after measuring that a held `O_EXLOCK` refuses a second `O_RDONLY`
    ///   open (`EBUSY`, 2026-08-02): adds `digestRange`. The gate's before/after fingerprints
    ///   were to be taken by a separate process, and that turns out to be impossible while the
    ///   claim is held — so the helper has to take them through its own descriptor.
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
    public static let version = 7

    /// The most one privileged, uncancellable call may cover — ``TesterControl/runRetentionCycle(startBlock:blockCount:ioSizeBytes:reply:)``
    /// and ``TesterControl/digestRange(startBlock:blockCount:reply:)`` alike. **1 GiB.**
    ///
    /// Not a tuning parameter — it is what makes an uncancellable privileged write operation
    /// safe to expose at all. There is no cancellation until Step 11 and no progress channel
    /// until Step 9, so the only thing bounding how long a caller can occupy the daemon is the
    /// size of what it asked for. 1 GiB is 3 GiB of I/O (read + write + verify): about 6.8 s
    /// at `disk4`'s measured 475 MB/s, and about 15 s at a 200 MB/s floor.
    ///
    /// It is deliberately *not* enough to stand in for the run-control machinery Step 11 owns.
    ///
    /// One bound for both because they carry the same hazard: a caller occupying a root daemon
    /// for an unbounded time with no way to stop it. A digest pass is one read where a cycle is
    /// three, so a 1 GiB digest is about 2.2 s at `disk4`'s measured rate.
    public static let maximumBytesPerCall: UInt64 = 1 << 30

    /// The I/O sizes a run may use (FR-CTRL-8), smallest first. Default 4 MiB.
    ///
    /// The **engine** accepts any positive multiple of the logical block size, so tests can
    /// use deliberately awkward sizes to exercise the final chunk. Nothing arriving over XPC
    /// may: this is a privileged, untrusted boundary, and a narrow allowed set is one fewer
    /// thing to reason about (NFR-REL-7, NFR-SEC-3).
    public static let permittedIOSizes: [Int] = [1 << 20, 2 << 20, 4 << 20, 8 << 20]

    /// FR-CTRL-8's default.
    public static let defaultIOSizeBytes = 4 << 20
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
