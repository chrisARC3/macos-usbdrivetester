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
//    * runProgress            — live metrics for the run in progress (Step 9)
//    * setRunControl          — pause / resume / stop the run in flight (Step 11)
//
//  `setRunControl` was deferred until it could be meaningful, which is this step: stubbing it
//  earlier would have been dead code AND attack surface. Note it is ONE method carrying a *level*,
//  not a pause/resume/stop triple carrying edges — the run READS it at each chunk boundary, and an
//  edge would have to be delivered to a connection that is blocked for the run's whole duration
//  (measured 2026-08-04). Widening the protocol later is cheap, walking a wide one back is not
//  (BUILD-PLAN Step 3, risks).
//
//  NOTE (Step 9): the helper -> GUI *callback* protocol that earlier notes anticipated was
//  not built. Measured 2026-08-04, a second connection is answered concurrently while a
//  privileged call blocks, so the GUI polls `runProgress` on its own connection instead —
//  no reverse interface, no exported object on the app side, and the daemon keeps the
//  property that it never initiates traffic to a client. See `scripts/xpc-concurrency-check.sh`.
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
    ///   - failureModeCode: a ``FailureModeCode`` raw value (FR-FAIL-1). **Required, and
    ///     refused rather than defaulted** if this build does not recognise it: quietly
    ///     resolving an unknown code to FR-FAIL-4's default would answer a caller asking to
    ///     stop on the first error with a run that writes to the whole drive.
    ///   - reply: twenty values, in the order below.
    ///
    ///     **The run** — `runOutcomeCode`, `interruptedAtBlock`, `chunksProcessed`, `message`.
    ///     `runOutcomeCode` is a ``RunOutcomeCode`` raw value and it **replaced a `completed`
    ///     boolean in v10**: with FR-CTRL-2/4 there are now four ways for a run to end, and a
    ///     boolean beside a separate "why" field would be two statements of one fact — which is
    ///     the defect `AppModel.helperHoldsDevice` is being deleted for. `completed` survives as a
    ///     *derived* property on the app side, so nothing that only wanted the boolean had to
    ///     change. It still says nothing about whether every chunk *passed*: a run that finds bad
    ///     blocks and keeps going still completes (FR-FAIL-3).
    ///
    ///     `interruptedAtBlock` is the block a paused run resumes from (FR-CTRL-3), and is
    ///     meaningful **only** when `runOutcomeCode` is ``RunOutcomeCode/pausedByUser`` — the code
    ///     is the discriminator, exactly as `readLatencySampleCount` is for the latency figures.
    ///     It is `0` otherwise, and `0` is a legitimate resume point, which is why the code and
    ///     not a sentinel decides.
    ///
    ///     **The failures (FR-RPT-1)** — `failedRangeCount` (retained **plus** any the cap
    ///     dropped), `failureSummary` (the human line, also carried inside `message`),
    ///     `failedRangesEncoded` (``FailedRangeCoding``) and `failedBlockCount` (every failing
    ///     block, *including* those in dropped ranges — never approximate). The retained ranges
    ///     are what decodes; `failedRangeCount` minus their number is what the cap dropped, and
    ///     a report showing the list must say so. All of it is block addressing, never device
    ///     contents (NFR-SEC-6).
    ///
    ///     **The mode the run actually used** — `failureModeUsedCode`, a ``FailureModeCode`` raw
    ///     value, or `0` when no run happened. Echoed back because the helper's `RunCoordinator`
    ///     is not in the test target, so "the deciding observer really is installed" is otherwise
    ///     a code-level inference — and on a healthy drive there is no failure to not-stop on, so
    ///     nothing would ever reveal it.
    ///
    ///     **The final figures (FR-RPT-2/3)** — `sustainedReadBytesPerSecond`,
    ///     `sustainedWriteBytesPerSecond`, `coverageBytesPerSecond`, `readLatencySampleCount`,
    ///     and the three latency figures. **Cumulative over the whole run from v11**, and here
    ///     rather than polled from ``runProgress(reply:)`` afterwards so that they belong to this
    ///     run or do not exist.
    ///
    ///     **All three rates divide by the wall clock, from v12.** The two that v11 carried
    ///     divided by *phase* time — bytes read ÷ time spent reading — which made them
    ///     incomparable to every other throughput figure on the machine and was reported as a
    ///     defect the first time anybody checked (see `RunMetrics`). The phase rates still exist
    ///     in Core and are still logged every call; they are simply not on this wire, because a
    ///     wire field nothing displays is how `coverageBytesPerSecond` went a week without ever
    ///     reaching a screen.
    ///
    ///     That property was v9's, and the mechanism behind it changed in v11 rather than
    ///     surviving. v9 read them from an observer installed *after* validation, so a refused
    ///     call had nothing to misattribute. The accumulators now live on the claim and predate
    ///     the call; what keeps the property is that the helper assembles this reply only on its
    ///     success path, and a refusal replies with sentinels. The hazard v9 was written for —
    ///     a poll returning a **previous** run's figures — cannot occur at all now, because the
    ///     previous run's accumulators died with its claim.
    ///
    ///     Same sentinels as `runProgress`: rates are `-1` when not measured (never `0`, which
    ///     means *stalled*), and a `readLatencySampleCount` of `0` makes the three latency values
    ///     meaningless — `0` nanoseconds is itself a legitimate reading. The p99 travels as its
    ///     **upper bound**, and from v11 it is a **whole-run** p99: percentiles do not compose, so
    ///     no app-side aggregation of per-call values could produce one.
    ///
    ///     **The rest** — `cacheBypassCode` is a ``CacheBypassOutcome`` raw value, the FR-TEST-9
    ///     verdict as it stood at the **end** of the run: the acquire-time verdict possibly
    ///     downgraded by what the run's own throughput revealed. It never improves.
    ///     `fastestObservedBytesPerSecond` is what the falsifier actually measured, so a gate can
    ///     assert the reads were transport-plausible rather than only that a threshold was not
    ///     crossed. `bufferBytesHeld` is NFR-PERF-1's figure: 2 × the I/O size, whatever the
    ///     range's size. `hostOverheadFraction` and `helperCoreFraction` are **NFR-PERF-3's two
    ///     numbers**, read once by a gate and by Step 16's release note rather than watched; both
    ///     are `-1` when they could not be established, never `0`.
    func runRetentionCycle(startBlock: UInt64,
                           blockCount: UInt64,
                           ioSizeBytes: Int,
                           failureModeCode: Int,
                           reply: @escaping (Int,      //  1 runOutcomeCode             (v10)
                                             UInt64,   //  2 interruptedAtBlock         (v10)
                                             UInt64,   //  3 chunksProcessed
                                             Int,      //  4 failedRangeCount
                                             String,   //  5 failureSummary
                                             Int,      //  6 cacheBypassCode
                                             Double,   //  7 fastestObservedBytesPerSecond
                                             Int,      //  8 bufferBytesHeld
                                             Double,   //  9 hostOverheadFraction
                                             Double,   // 10 helperCoreFraction
                                             Int,      // 11 failureModeUsedCode        (v9)
                                             String,   // 12 failedRangesEncoded        (v9)
                                             UInt64,   // 13 failedBlockCount           (v9)
                                             Double,   // 14 sustainedReadBytesPerSecond  (v12)
                                             Double,   // 15 sustainedWriteBytesPerSecond (v12)
                                             Double,   // 16 coverageBytesPerSecond       (v12)
                                             UInt64,   // 17 readLatencySampleCount     (v9)
                                             UInt64,   // 18 readLatencyMinimumNs       (v9)
                                             UInt64,   // 19 readLatencyMaximumNs       (v9)
                                             UInt64,   // 20 readLatencyP99UpperBoundNs (v9)
                                             String)   // 21 message
                                            -> Void)

    /// Tell the helper what the run in flight should do at its next chunk boundary
    /// (FR-CTRL-2/3/4, NFR-REL-10).
    ///
    /// ## This MUST be called on a second connection
    ///
    /// Measured 2026-08-04 (`scripts/xpc-concurrency-check.sh`): while the helper is inside a
    /// blocking privileged call, **a second message on that same connection is not delivered until
    /// the call returns**, while a second connection is answered concurrently in 0.2–0.3 ms. So a
    /// pause sent on the connection running `runRetentionCycle` would be delivered *after* the run
    /// it was meant to interrupt had already ended — the request would appear to do nothing, and
    /// then the run would stop by itself, which is the worst available way for a control to be
    /// wrong. The app sends this on the same non-owning connection it polls `runProgress` on.
    ///
    /// ## A level, not an edge — and therefore no `resume`
    ///
    /// This states what the app wants **now**. Resume is ``RunControlCode/proceed`` sent again.
    /// An edge-triggered control would have to be delivered while the run was looking, and the
    /// whole reason this method exists is that a blocked connection cannot be delivered to.
    ///
    /// The helper never clears it: the app owns the state and sets `proceed` before every run and
    /// on every resume. A stale `pause` or `stop` can therefore only make a run do **less** than
    /// asked, and the run it would shorten has not started.
    ///
    /// ## Why this may abort a run when `prepareForShutdown` may not
    ///
    /// `prepareForShutdown` deliberately refuses while busy, so that no caller — even a correctly
    /// Team-ID-signed one — can use it to abort a run. The difference is what each would leave
    /// behind. A teardown mid-write can leave a half-written device (NFR-REL-5). A stop cannot:
    /// the engine settles at a chunk boundary with the previous chunk's full read → write-back →
    /// verify complete, which is exactly NFR-REL-10's guarantee. And FR-CTRL-4 *requires* the user
    /// to be able to stop a run. Nothing is granted here that an accepted caller did not already
    /// have — one wanting to keep a drive claimed could simply call `acquireDevice` and hold it.
    ///
    /// - Parameters:
    ///   - code: a ``RunControlCode`` raw value. An unrecognised code is **refused, never
    ///     defaulted** — the same rule as ``FailureModeCode``, and for a sharper reason here:
    ///     defaulting an unknown code to `proceed` would answer a caller asking to *stop a write*
    ///     with a run that keeps writing.
    ///   - reply: `(accepted, message)`. Deliberately does **not** report whether a run is in
    ///     flight: the app issues its own runs and receives their completions, so it already knows
    ///     the lifecycle, and a second source for that fact is a second thing that can be wrong
    ///     (user decision 2026-08-04, the same reason `runProgress` carries no "is a run active"
    ///     flag).
    func setRunControl(code: Int, reply: @escaping (Bool, String) -> Void)

    /// A snapshot of the run currently in progress (Step 9, FR-METR-2/4/5/6, NFR-PERF-5).
    ///
    /// **Read-only, cheap, and safe to call once a second** — it takes a lock, reads the
    /// accumulating counters and computes a percentile over a fixed 2,240-bucket histogram. It
    /// does not touch the device and does not take the device-operation slot.
    ///
    /// ## Why this must be called on a SECOND connection
    ///
    /// Measured 2026-08-04 (`scripts/xpc-concurrency-check.sh`): while the helper is inside a
    /// blocking privileged call, **a second message on that same connection is not delivered
    /// until the call returns.** Twenty-four pings issued during a 2,827.9 ms `digestRange` were
    /// all answered between 2,828.0 and 2,828.5 ms — the queue draining *after* the call
    /// finished. A **second connection** was answered concurrently throughout, in 0.2–0.3 ms.
    ///
    /// So a caller polling this on the connection that issued `runRetentionCycle` will receive
    /// nothing until the run ends, which is indistinguishable from a wedged daemon. The app owns
    /// a separate, **non-owning** connection for exactly this — non-owning because
    /// `HelperActivity.releaseIfOwned(by:)` scopes release-on-disconnect to the connection that
    /// acquired, so a progress connection dropping releases nothing (NFR-REL-5).
    ///
    /// ## What it deliberately does not carry
    ///
    /// No run identifier and no "is a run active" flag. The app issues the run on its own
    /// connection and receives its completion there, so it already knows the lifecycle; having
    /// the helper restate it would be a second source of a fact that already has one. Between
    /// runs this returns the **last** run's final figures, which is what a caller wants to
    /// display at the end of one — and a caller that has not started a run has nothing to
    /// mistake them for.
    ///
    /// - Parameter reply: `(available, fractionComplete, currentBlock,
    ///   sustainedReadBytesPerSecond, sustainedWriteBytesPerSecond, coverageBytesPerSecond,
    ///   estimatedRemainingSeconds, readLatencySampleCount, readLatencyMinimumNanoseconds,
    ///   readLatencyMaximumNanoseconds, readLatencyP99UpperBoundNanoseconds, chunksFailed)`.
    ///
    ///   `available` is `false` when no run has started since the daemon launched; every other
    ///   value is then meaningless and is zero.
    ///
    ///   **The three rates all divide by the wall clock** (v12), which is what makes them
    ///   comparable to Activity Monitor and to any other tool watching the same drive. Read
    ///   counts the verify read as well as the original — both are reads, and the kernel counts
    ///   both — so on a healthy drive read is about 2 × covering and write about 1 × covering.
    ///   The phase-isolated rates v11 sent instead are still computed and logged by the helper;
    ///   they are not sent, because nothing displays them.
    ///
    ///   **The four `Double`s are `-1` when not yet known, never `0`.** A rate of zero means
    ///   "stalled", which is a real and alarming condition; using it for "not measured yet"
    ///   would print an alarming number to mean nothing happened. `readLatencySampleCount` plays
    ///   the same role for the three latency figures, where `0` nanoseconds is a legitimate
    ///   reading (a read the clock could not resolve).
    ///
    ///   The p99 is reported as its **upper bound** — the true value is at or below it, within
    ///   one bucket, which is at most 1.5625% wide. A single number pretending to be exact would
    ///   be the bucket's midpoint dressed up as a measurement; an upper bound is honest and is
    ///   what a display can show as "p99 ≤ x".
    ///
    ///   Throughput is reported and **never graded** (user decision 2026-08-04). Whether a rate
    ///   indicates wear is the user's judgement, made against the manufacturer's advertised
    ///   sustained figure and the negotiated link speed — which the app already holds from
    ///   ``deviceProfile(reply:)``. This tool measures; it does not diagnose.
    func runProgress(reply: @escaping (Bool, Double, UInt64, Double, Double, Double, Double,
                                       UInt64, UInt64, UInt64, UInt64, UInt64) -> Void)

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
nonisolated public enum CacheBypassOutcome: Int {

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

/// Which of FR-FAIL-1's two failure-handling modes a run was started in, as it travels over
/// the wire.
///
/// - Important: these raw values are duplicated by `FailureMode.wireCode` in
///   `Core/RetentionRun.swift`, which is where the modes actually decide anything, for the same
///   reason ``DeviceAccessRefusalCause`` is duplicated: Core compiles into the helper and the
///   test target but deliberately **not** into the app module. `FailureModeTests` pins the two.
///
/// ## Why this one has an unrecognised case and `FailureMode` does not
///
/// They sit on opposite sides of the trust boundary. Anything arriving over this interface is
/// untrusted input even though the connection is code-signature-authenticated (NFR-REL-7), so a
/// code this build does not know has to be *representable* in order to be **refused** — the same
/// treatment an unpermitted I/O size gets. Inside the helper there is no such case, because a
/// run that does not know its mode never starts.
///
/// It is never defaulted. Quietly resolving an unknown code to FR-FAIL-4's default would mean a
/// caller asking to stop on the first error and getting a run that writes to the whole drive
/// instead — a request silently answered with a different, larger action.
nonisolated public enum FailureModeCode: Int {

    /// **FR-FAIL-2** — halt on the first failed range.
    case stopOnFirstError = 1

    /// **FR-FAIL-3/4** — record it and keep going. The default.
    case logAndContinue = 2

    /// Anything this build does not recognise. **Refused, never defaulted.**
    case unrecognised = 0

    /// FR-FAIL-4's default, for a caller that has no reason to choose.
    public static let standard = FailureModeCode.logAndContinue

    /// Map a wire value, never trapping on one this build does not know.
    public init(wireValue: Int) {
        self = FailureModeCode(rawValue: wireValue) ?? .unrecognised
    }

    /// Is this a mode a run may actually start in?
    public var isRunnable: Bool { self != .unrecognised }
}

/// What the app wants the run in flight to do, as it travels over the wire (FR-CTRL-2/3/4).
///
/// - Important: these raw values are duplicated by ``RunControlSignal`` in `Core/RetentionRun.swift`,
///   which is what the engine actually reads, for the same reason ``FailureModeCode`` is duplicated:
///   Core compiles into the helper and the test target but deliberately **not** into the app module.
///   `RunControlWireTests` is the only place both are visible at once, and it pins them together.
///
/// ## Why this one has an unrecognised case and `RunControlSignal` does not
///
/// The same asymmetry, for the same reason: anything arriving over this interface is untrusted input
/// even though the connection is code-signature-authenticated (NFR-REL-7), so a code this build does
/// not know has to be *representable* in order to be **refused**. Inside the helper there is no such
/// case, because a run cannot be in a control state it cannot read.
///
/// It is never defaulted, and the direction matters more here than anywhere else on this interface:
/// resolving an unknown code to ``proceed`` would answer a caller asking to **stop a write** with a
/// run that keeps writing.
nonisolated public enum RunControlCode: Int {

    /// Carry on. Also what a resume sends (FR-CTRL-3) — this is a level, not an edge.
    case proceed = 1

    /// **FR-CTRL-2.** Settle at the next chunk boundary and reply with the resume point.
    case pause = 2

    /// **FR-CTRL-4.** Settle at the next chunk boundary and end the run.
    case stop = 3

    /// Anything this build does not recognise. **Refused, never defaulted.**
    case unrecognised = 0

    /// Map a wire value, never trapping on one this build does not know.
    public init(wireValue: Int) {
        self = RunControlCode(rawValue: wireValue) ?? .unrecognised
    }

    /// Is this a control state the helper may actually adopt?
    public var isActionable: Bool { self != .unrecognised }
}

/// How a run ended, as it travels over the wire (FR-RPT-4).
///
/// Replaced v9's `completed` boolean in **v10**. With FR-CTRL-2/4 there are four ways for a run to
/// end, and a boolean beside a separate "why" field would be two statements of one fact.
///
/// - Important: duplicated by ``RunOutcome`` in `Core/RetentionRun.swift`, which is where a run
///   actually ends, for the same reason the other wire enums are. `RunControlWireTests` pins them.
nonisolated public enum RunOutcomeCode: Int {

    /// Every chunk in the range was processed. **Not** a claim that they all passed — a run that
    /// finds bad blocks and keeps going still completes (FR-FAIL-3).
    case completed = 1

    /// **FR-FAIL-2.** The run halted at a failed range because the mode said to.
    case stoppedOnFailure = 2

    /// **FR-CTRL-2, NFR-REL-10.** The user paused; the helper settled at a chunk boundary with no
    /// write in flight. The **only** code for which `interruptedAtBlock` means anything.
    case pausedByUser = 3

    /// **FR-CTRL-4.** The user stopped the run. It cannot be continued (FR-FAIL-7).
    case stoppedByUser = 4

    /// No run happened — a refusal — or a code this build does not recognise. Never treated as a
    /// completion.
    case unrecognised = 0

    /// Map a wire value, never trapping on one this build does not know.
    public init(wireValue: Int) {
        self = RunOutcomeCode(rawValue: wireValue) ?? .unrecognised
    }

    /// Did every planned chunk get processed? What v9's `completed` boolean answered.
    public var didComplete: Bool { self == .completed }

    /// Was the run cut short by the user, either way? Both mean the drive is only partly covered,
    /// and a report must never read as a clean pass over the whole device.
    public var wasInterruptedByUser: Bool {
        self == .pausedByUser || self == .stoppedByUser
    }
}

/// What kind of failure a reported range was, as it travels over the wire.
///
/// - Important: duplicated by `BlockFailureKind` in `Core/RetentionRun.swift`; pinned by
///   `FailedRangeCodingTests`.
nonisolated public enum FailedBlockRangeKind: Int, CaseIterable {

    /// The original read failed, so nothing was written to this range.
    case readError = 1

    /// The write-back failed, so nothing was verified.
    case writeError = 2

    /// The write reported success and the re-read differed from what was written.
    case verifyMismatch = 3

    /// Map a wire value. `nil` — not a fallback case — because a range whose kind cannot be
    /// read is a range the report must not print. See ``FailedRangeCoding``.
    public init?(wireValue: Int) {
        self.init(rawValue: wireValue)
    }

    /// How the kind is named in the report and in a log line. Matches
    /// `BlockFailureKind.description` word for word, so one failure does not acquire two names
    /// depending on which side of the boundary printed it.
    public var reportName: String {
        switch self {
        case .readError:      return "read error"
        case .writeError:     return "write error"
        case .verifyMismatch: return "verify mismatch"
        }
    }
}

/// One failed block range, on its way from the helper to the report (FR-RPT-1).
///
/// Block units rather than bytes, because that is what a user can act on — a byte offset into a
/// 1 TB device is not a thing anyone can look up — and because it is what the report tabulates.
///
/// The initialiser is failable and enforces the two invariants that make ``endBlock`` safe to
/// compute and the range meaningful to print. That is the same move ``LoadedChunk`` makes in
/// Core: a value that cannot be represented is better than one that is checked at every use
/// site and eventually isn't.
nonisolated public struct FailedBlockRange: Equatable, CustomStringConvertible {

    /// First failing block.
    public let startBlock: UInt64

    /// How many blocks failed. Always at least 1.
    public let blockCount: UInt64

    /// What went wrong.
    public let kind: FailedBlockRangeKind

    /// - Returns: `nil` when `blockCount` is zero — an empty failed range says nothing and
    ///   would render as a blank row — or when the range would run past the end of the address
    ///   space, which would make ``endBlock`` trap.
    public init?(startBlock: UInt64, blockCount: UInt64, kind: FailedBlockRangeKind) {
        guard blockCount >= 1 else { return nil }
        guard !startBlock.addingReportingOverflow(blockCount).overflow else { return nil }
        self.startBlock = startBlock
        self.blockCount = blockCount
        self.kind = kind
    }

    /// One past the last failing block. Cannot overflow — the initialiser refuses a range that
    /// would.
    public var endBlock: UInt64 { startBlock + blockCount }

    /// Matches `BlockRangeFailure.description`, for the reason given on
    /// ``FailedBlockRangeKind/reportName``.
    public var description: String {
        blockCount == 1
            ? "block \(startBlock): \(kind.reportName)"
            : "blocks \(startBlock)–\(endBlock - 1) (\(blockCount)): \(kind.reportName)"
    }
}

/// Carries ``FailedBlockRange`` values across the XPC boundary as one `String`.
///
/// ## Why a string rather than an array of objects
///
/// Every parameter on ``TesterControl`` is an ObjC-representable primitive, deliberately, so the
/// interface needs no `NSSecureCoding` class whitelist (see this file's header). A list of
/// ranges is the first thing Step 10 needs that is not naturally one — so it is encoded here,
/// once, in the file both the app and the helper compile, rather than duplicated on each side
/// the way the wire *enums* have to be.
///
/// ## Why a malformed record fails the whole decode
///
/// ``decode(_:)`` returns `nil` if **any** record is bad, rather than skipping it. Skipping
/// would produce a shorter list that still looks complete — the same failure `FailureLog`'s
/// `isTruncated` exists to prevent, arriving by a different door and into the one artefact that
/// outlives the session. A report that silently omits a bad block is worse than no report.
///
/// Format: records separated by `;`, fields by `:`, as
/// `<startBlock>:<blockCount>:<kindCode>`. An empty string means no failed ranges, which is the
/// commonest case and costs nothing. Human-glanceable on purpose — it appears in log lines.
nonisolated public enum FailedRangeCoding {

    static let recordSeparator: Character = ";"
    static let fieldSeparator: Character = ":"

    /// Encode a list. The inverse of ``decode(_:)`` for every list this can produce.
    public static func encode(_ ranges: [FailedBlockRange]) -> String {
        ranges
            .map { "\($0.startBlock)\(fieldSeparator)\($0.blockCount)\(fieldSeparator)\($0.kind.rawValue)" }
            .joined(separator: String(recordSeparator))
    }

    /// Decode a list, or `nil` if anything about the input is not exactly what ``encode(_:)``
    /// produces.
    ///
    /// Strict by intent. `UInt64(_: String)` alone would accept a leading `+` and reject a value
    /// that overflows — useful, but not a complete accept-set — so the digits are checked
    /// explicitly first. Everything a caller could send that is not a canonical encoding is a
    /// `nil`, and a `nil` is the app declining to build a report rather than building a wrong one.
    public static func decode(_ encoded: String) -> [FailedBlockRange]? {
        guard !encoded.isEmpty else { return [] }

        var ranges: [FailedBlockRange] = []
        ranges.reserveCapacity(encoded.count / 8)

        for record in encoded.split(separator: recordSeparator, omittingEmptySubsequences: false) {
            let fields = record.split(separator: fieldSeparator, omittingEmptySubsequences: false)
            guard fields.count == 3,
                  let startBlock = digits(fields[0]),
                  let blockCount = digits(fields[1]),
                  let kindCode = digits(fields[2]),
                  kindCode <= UInt64(Int.max),
                  let kind = FailedBlockRangeKind(wireValue: Int(kindCode)),
                  let range = FailedBlockRange(startBlock: startBlock,
                                               blockCount: blockCount,
                                               kind: kind)
            else { return nil }
            ranges.append(range)
        }
        return ranges
    }

    /// A run of ASCII digits and nothing else, in range for `UInt64`.
    ///
    /// Rejects the empty string, `+5`, ` 5`, `0x10`, non-ASCII digits, and anything that
    /// overflows. Written out rather than left to `UInt64.init(_:)` so the accept-set is exact
    /// and can be tested as one.
    private static func digits(_ text: Substring) -> UInt64? {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return UInt64(text)
    }
}

/// Version of the ``TesterControl`` contract (NFR-MAINT-1).
///
/// Bump ``version`` whenever a change would break an older peer: removing or
/// renaming a method, changing a signature, or changing the meaning of an argument.
/// Purely additive changes that an older peer simply never calls do not require a
/// bump, but bumping is cheap and a mismatch is far easier to diagnose than a
/// silently missing method.
///
/// `nonisolated` for the reason the six wire enums above it are, and added in Step 11 increment 6
/// when the first `nonisolated` type needed to read one of these constants. The **app** target
/// compiles with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which otherwise makes even a
/// namespace of immutable `static let`s main-actor-isolated — so `IOSizeSelection.permitted(_:)`,
/// which must know `permittedIOSizes` to validate a stored preference against it, could not read
/// one without a warning.
///
/// **This changes nothing for the helper**, whose target does not set that flag, so these
/// constants were already nonisolated there. Verified rather than argued: the helper binary's
/// `__TEXT,__text` and `__TEXT,__cstring` are byte-identical across the change, which is the
/// comparison CONSTRAINTS names for *"did this change behaviour"* — and the reason the source
/// hash moving here does not put Step 10's three hardware gates back into question.
nonisolated public enum TesterProtocol {

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
    /// - **8** — Step 9: adds `runProgress`, the live metrics query (FR-METR-2/4/5/6,
    ///   NFR-PERF-5), and widens `runRetentionCycle`'s reply with NFR-PERF-3's two figures.
    ///   A **signature change**, so the bump is mandatory rather than merely cheap — a v7 daemon
    ///   would decode the cycle's reply block differently.
    ///
    ///   `runProgress` must be called on a **second connection**. Measured 2026-08-04: while the
    ///   helper is inside a blocking privileged call, a second message on that same connection is
    ///   not delivered until the call returns, while a second connection is answered concurrently
    ///   in 0.2–0.3 ms. Polling on the run's own connection would return nothing until the run
    ///   ended — indistinguishable from a wedged daemon.
    /// - **9** — Step 10: `runRetentionCycle` takes a ``FailureModeCode`` (FR-FAIL-1) and its
    ///   reply carries what the end-of-run report needs — the failed ranges themselves
    ///   (FR-RPT-1), the total failing block count, the final throughput and read-latency figures
    ///   (FR-RPT-2/3), and the mode the run actually used. A **signature change on both sides**,
    ///   so the bump is mandatory: a v8 daemon would neither receive the mode nor encode the
    ///   reply block this app decodes.
    ///
    ///   The figures are in the reply rather than polled from `runProgress` afterwards because
    ///   `MetricsChannel`'s slot is replaced when a run *starts* — after validation — so a
    ///   **refused** run leaves the previous run's figures installed, and a report assembled from
    ///   a post-reply poll would export the wrong run's measurements. In the reply they belong to
    ///   this run or they do not exist.
    ///
    /// - **10** — Step 11: adds `setRunControl`, and `runRetentionCycle`'s reply gains
    ///   ``RunOutcomeCode`` and the resume block while **losing** the `completed` boolean it
    ///   replaces. A **signature change on the reply**, so the bump is mandatory: a v9 client would
    ///   decode `Int` where it expected `Bool` and read every field after it one position out.
    ///
    ///   `setRunControl` must be called on a **second connection**, for the same measured reason
    ///   `runProgress` must be (2026-08-04). It is the first method on this interface that changes
    ///   what a call *already in flight* will do — every other one either asks a question or starts
    ///   something — which is why it is a level the run reads rather than a message the run
    ///   receives: a blocked connection cannot be delivered to.
    ///
    ///   `completed` became `runOutcomeCode` rather than gaining a sibling because FR-CTRL-2/4 give
    ///   a run four ways to end, and a boolean beside a separate "why" would be two statements of
    ///   one fact — the defect `AppModel.helperHoldsDevice` is being deleted for in this same step.
    ///
    /// - **11** — Step 11 increment 3: **a run is a sequence of bounded calls, and the session is
    ///   the claim** (CONSTRAINTS section 2). No signature changed and no method was added — what
    ///   changed is the **meaning of nine reply arguments**, which the rule above makes a
    ///   mandatory bump on its own.
    ///
    ///   `chunksProcessed`, `failedRangeCount`, `failureSummary`, `failedRangesEncoded`,
    ///   `failedBlockCount`, `readBytesPerSecond`, `writeBytesPerSecond`, the three latency
    ///   figures, `hostOverheadFraction`, `helperCoreFraction`, `cacheBypassCode` and
    ///   `fastestObservedBytesPerSecond` are now **cumulative over the whole run** — every call
    ///   the session has completed since `acquireDevice` — rather than describing the one call
    ///   that returned them. `runProgress`'s `fractionComplete` and `estimatedRemainingSeconds`
    ///   are correspondingly against the **whole device**, not the call's range.
    ///
    ///   Two fields stay per-call and are the exceptions worth knowing: `bufferBytesHeld`, because
    ///   it is 2× *this call's* I/O size and FR-CTRL-8 lets the size change mid-run; and
    ///   `runOutcomeCode` / `interruptedAtBlock`, because how *this* call ended is what a
    ///   sequencer branches on.
    ///
    ///   **A silent meaning change is exactly what the handshake exists to catch.** A v10 daemon
    ///   answering a v11 app would return one gibibyte's figures where the app expects the run's,
    ///   and the report would understate a whole-device run by a factor of a thousand with nothing
    ///   in the reply to reveal it — every field well-formed, plausible, and wrong.
    ///
    ///   `acquireDevice` opens the session and `releaseDevice` closes it. No lifecycle method was
    ///   added for it, which is the property Shape A was chosen for.
    ///
    /// - **12** — Step 11, between increments 5 and 6 (an unplanned fix, not a planned
    ///   increment): **every throughput on this interface divides by the run's RUNNING time** —
    ///   wall clock less the gaps between calls, which is where a pause lives. See
    ///   `MetricsSnapshot.runningNanoseconds` for why it is not the raw wall clock and not
    ///   device-plus-host either; both were tried and refuted on hardware.
    ///   `readBytesPerSecond` and `writeBytesPerSecond` become
    ///   `sustainedReadBytesPerSecond` and `sustainedWriteBytesPerSecond`, and both replies gain
    ///   `coverageBytesPerSecond`. A **signature change on both replies** *and* a meaning change
    ///   on two arguments, so the bump is doubly mandatory.
    ///
    ///   Reported by the user on 2026-08-17 as "our speed measurements are way off": against the
    ///   4 TB T5 EVO the app claimed 375.8 MB/s read and 418.9 MB/s write while DriveSpeed and
    ///   Activity Monitor — agreeing with each other exactly — showed about 245 and 122. Read was
    ///   53% high; write was **3.4×** high.
    ///
    ///   Not a regression, and nothing was miscounted. v11's rates divided bytes by *phase* time,
    ///   so "write speed" described the drive during the fraction of the run it was writing and
    ///   omitted the rest. Every other tool divides by the wall clock, because that is the only
    ///   denominator an outside observer has. We were answering a question nobody asked, in a
    ///   field labelled as though we had answered theirs.
    ///
    ///   `coverageBytesPerSecond` was the one honest run-progress figure and it existed the whole
    ///   time — computed, unit-tested, and logged every call since Step 9 — but it had never been
    ///   put on the wire, so no screen could show it and no report could carry it. **That is the
    ///   lesson worth keeping from this bump**: a measurement that is not on the wire does not
    ///   exist as far as the user is concerned, however well tested it is.
    ///
    ///   Deriving the sustained rates app-side, to avoid a bump, was considered and rejected: a
    ///   chunk that fails its read still advances `rangeBytesCovered` but contributes no
    ///   `bytesRead`, so `2 × covered` breaks precisely on the failing drives this tool exists to
    ///   find. The numbers must come from the side that counted the bytes.
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
    public static let version = 12

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
