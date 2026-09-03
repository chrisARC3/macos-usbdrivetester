//
//  HelperConnection.swift
//  USBDriveTester (app target — unprivileged)
//
//  The app side of the XPC link. It NEVER performs privileged work itself
//  (FR-ARCH-2, NFR-SEC-1); it only talks to the helper over an authenticated XPC
//  connection (FR-ARCH-4). As of Step 3 the Mach service is resolvable because
//  `SMAppService` registered the daemon — see HelperRegistration.swift — rather than
//  because of a manual `launchctl bootstrap`.
//
//  Note on trust direction: the *helper* authenticates *us*, by pinning our Team ID
//  (see the helper's ListenerDelegate). Nothing is required of this side beyond
//  being genuinely signed by that team — which is why Step 3 depends on the app
//  being signed as Apple Development rather than adhoc.
//

import Foundation
import os

private let log = Logger(subsystem: HelperIdentity.loggingSubsystem, category: "xpc")

/// Errors surfaced by the app-side connection wrapper.
enum HelperConnectionError: LocalizedError {
    case proxyUnavailable

    var errorDescription: String? {
        switch self {
        case .proxyUnavailable:
            return "Could not obtain a remote proxy for the helper."
        }
    }
}

/// Outcome of the protocol-version handshake (NFR-MAINT-1).
///
/// `nonisolated` since Step 11 increment 9, when `HelperAvailability` — which is nonisolated so the
/// test target can reach it — became the first type to read ``description``. The app target's
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` would otherwise make that property main-actor-isolated
/// and unreadable from there (a warning today, an error under the Swift 6 language mode).
///
/// **Free, unlike the same change on `HelperIdentity`.** This type is declared in an app-target file
/// and is referenced by nothing in `Shared/` or the helper, so the keyword cannot move the helper
/// source hash. `HelperIdentity` is in `Shared/TesterControl.swift`, which the helper compiles —
/// see `HelperAvailability.notFound`'s message for what that cost and what was done instead.
nonisolated enum ProtocolVersionCheck: Equatable {
    /// Helper implements the same version this app was built against.
    case match(version: Int)
    /// Versions differ — the app and the registered daemon are out of step, which
    /// happens when an app update lands while an older daemon is still installed.
    case mismatch(helper: Int, app: Int)

    var isMatch: Bool { if case .match = self { return true } else { return false } }

    var description: String {
        switch self {
        case .match(let version):
            return "Protocol v\(version) — app and helper agree."
        case .mismatch(let helper, let app):
            return """
                   Protocol mismatch: helper implements v\(helper), this app expects v\(app). \
                   Re-register the helper so the installed daemon matches this app.
                   """
        }
    }
}

/// What the helper can say about a device without touching it (FR-SAFE-1/2, Step 6).
nonisolated struct DeviceReadiness: Equatable {

    /// Nothing known would refuse an acquire. **Not** a promise that one will succeed —
    /// see `HelperConnection.checkDeviceReadiness(bsdName:completion:)`.
    let isReady: Bool

    /// How many of the device's volumes the *helper* sees mounted. The app's own count
    /// from discovery drives the list; this one is authoritative for the guard.
    let mountedVolumeCount: Int

    /// `Test_Drive` / `Data, Macintosh HD`, or empty when nothing is mounted.
    let mountedVolumeSummary: String

    /// Whether the helper already holds exclusive access to *this* device (FR-SAFE-7).
    let helperHoldsThisDevice: Bool

    /// What is standing in the way, or `.unrecognised` (raw value 0) when nothing is.
    /// Drives which corrective control the UI offers — Unmount All for a mounted volume,
    /// Open Settings for a missing Full Disk Access grant.
    let blockingCause: DeviceAccessRefusalCause

    /// Human-readable summary.
    ///
    /// **Its one surviving consumer is the Full Disk Access modal** (Step 11 increment 10). It used
    /// to be the readiness banner's text; that banner is deleted, and what reaches the user now is
    /// this string on the one branch that stops a run. `FullDiskAccessState.explanation` is where
    /// the wording is written, so the app composes nothing of its own — two copies of that sentence
    /// is the drift `OutcomePresentation` and `HonestFraming` both exist to prevent.
    let message: String

    /// Whether the helper lacks Full Disk Access (NFR-INST-4). Surfaced before a run is
    /// attempted, not after one fails.
    ///
    /// **True only for a probe that came back `denied`.** `FullDiskAccessState` is three-state
    /// because the probe is conclusive in two directions only, and `.unknown` must never be read as
    /// either — so this is `false` for an inconclusive answer, and `DevicePreparation` carries on
    /// and lets the acquire's own precondition decide. Do not widen it to "not known to be granted".
    var needsFullDiskAccess: Bool { blockingCause == .accessNotPermitted }
}

/// The outcome of asking the helper for exclusive access (FR-SAFE-3/4).
nonisolated enum DeviceAcquisition: Equatable {

    /// Access is held. The helper keeps it until released, the connection drops, or the
    /// daemon exits.
    case acquired(String)

    /// Refused, with the cause preserved so the UI can offer the matching fix.
    case refused(cause: DeviceAccessRefusalCause, message: String)

    var message: String {
        switch self {
        case .acquired(let text): return text
        case .refused(_, let text): return text
        }
    }

    /// Whether the refusal is FR-SAFE-4(a) — the one case the Unmount All control fixes.
    var isFixableByUnmounting: Bool {
        if case .refused(let cause, _) = self { return cause == .volumesMounted }
        return false
    }
}

/// What the helper established about the device it holds (Step 7's `deviceProfile`, called from
/// the app from Step 9).
nonisolated struct DeviceProfile: Equatable {

    /// `false` when no device is held; everything else is then meaningless.
    let isAvailable: Bool

    /// Authoritative, ioctl-derived geometry (BUILD-PLAN 7.3).
    let logicalBlockSize: UInt32
    let blockCount: UInt64

    /// The FR-TEST-9 verdict as it stood at acquire.
    let cacheBypass: CacheBypassOutcome

    /// Raw IORegistry `Device Speed` code, or `-1` when the registry reported none. Raw rather
    /// than interpreted, because no SDK header declares this enumeration — see
    /// `Core/USBLinkSpeed` and `scripts/usb-speed-check.sh`.
    let usbLinkSpeedCode: Int

    let message: String

    /// Capacity in bytes, for showing measured throughput against something.
    var byteCount: UInt64 { blockCount * UInt64(logicalBlockSize) }
}

/// How a bounded cycle ended — everything the end-of-run report is built from (Step 10, v9).
nonisolated struct RunCycleOutcome: Equatable {

    /// How the run ended (FR-RPT-4), as the helper stated it.
    ///
    /// **Replaced a `didComplete` boolean in protocol v10.** FR-CTRL-2/4 give a run four ways to
    /// end, and a boolean beside a separate "why" field would be two statements of one fact — the
    /// defect `AppModel.helperHoldsDevice` is being deleted for in this same step. `didComplete`
    /// survives below as a derived property, so callers that only wanted the boolean did not change.
    let outcome: RunOutcomeCode

    /// Where a paused run resumes (FR-CTRL-3), or `nil` for every other ending.
    ///
    /// `nil` rather than `0` for the three non-resumable endings, and the discriminator is the
    /// **outcome code, not the value**: block 0 is a perfectly legitimate resume point, so a
    /// sentinel would make "resume from the beginning" and "cannot be resumed" the same reply.
    ///
    /// It is `nil` for ``RunOutcomeCode/stoppedByUser`` too. A stopped run cannot be continued
    /// (FR-FAIL-7), so the value that would let somebody continue it does not exist rather than
    /// existing and being ignored — which is the version a later edit turns back on.
    let resumeBlock: UInt64?

    /// Every planned chunk was processed. **Says nothing about whether they all passed** — a run
    /// that finds bad blocks and keeps going still completes (FR-FAIL-3).
    var didComplete: Bool { outcome.didComplete }

    let chunksProcessed: UInt64

    /// Failed ranges the run produced, **retained plus any the cap dropped** (FR-RPT-1).
    /// Compare against ``failedRanges``'s count: a difference is the truncation, and a report
    /// showing the list must say so.
    let failedRangeCount: Int

    /// The human one-line summary, as the helper composed it.
    let failureSummary: String

    /// The retained failed ranges themselves (FR-RPT-1).
    ///
    /// `nil` — not empty — when the helper sent something this build could not decode. The two
    /// are deliberately different: empty means *the run found nothing*, and `nil` means *this
    /// app cannot say what the run found*. Collapsing them would let a decode failure render as
    /// a clean drive, which is the worst available way for this particular field to be wrong.
    let failedRanges: [FailedBlockRange]?

    /// Every failing block the run saw, **including blocks in ranges the cap dropped**. Never
    /// approximate, and not derivable from ``failedRanges`` once truncation has happened.
    let failedBlockCount: UInt64

    /// The mode the run was actually performed in, as reported by the helper (FR-FAIL-1).
    ///
    /// Checked against what was asked for rather than assumed: the helper's `RunCoordinator` is
    /// not in the test target, so nothing in the unit suite can show that the deciding observer
    /// was installed — and a healthy drive produces no failure that would reveal its absence.
    /// `.unrecognised` when no run happened.
    let failureModeUsed: FailureModeCode

    /// FR-TEST-9's verdict at the end of the run. Qualifies the verify result when it is not
    /// `.bypassed`.
    let cacheBypass: CacheBypassOutcome

    /// NFR-PERF-1's figure: 2 × the I/O size, whatever the range's size.
    let bufferBytesHeld: Int

    /// Host work as a fraction of device I/O time (NFR-PERF-3), or `nil` if not established.
    let hostOverheadFraction: Double?

    /// The daemon's CPU as a fraction of one core over the run (BUILD-PLAN 9.5a), or `nil`.
    let helperCoreFraction: Double?

    /// **The device's read speed** over the run — original reads and verify reads together, over
    /// the time spent on both (FR-RPT-2, v14) — or `nil` when nothing was measured.
    let deviceReadBytesPerSecond: Double?

    /// **The device's write speed** over the run: bytes written ÷ time spent writing (FR-RPT-2,
    /// v14). Legitimately above the read rate on a drive that writes faster than it reads.
    let writeBytesPerSecond: Double?

    /// How fast the run covered the drive, **against running time** (FR-METR-5) — the one rate on
    /// this reply that did not move to phase time in v14, because it is the ETA's denominator.
    /// About a third of the two above and not directly comparable to them.
    ///
    /// **Attempted work**, and displayed nowhere — see ``completedBytesPerSecond`` below and
    /// `RunProgressSnapshot.coverageBytesPerSecond` for why it stays on the wire regardless.
    let coverageBytesPerSecond: Double?

    /// **`R-W-R-C speed`** (v14): bytes in chunks that were read, written back, read again and
    /// matched, over all successful phase time — successful work, where the rate above is
    /// attempted work.
    ///
    /// It equalled ``writeBytesPerSecond`` on a clean run until v14 and no longer does; it is
    /// roughly a third of it, being a per-cycle rate beside per-phase ones. The relationship that
    /// replaced the equality is `1/completed = 2/deviceRead + 1/write`, and falling below what
    /// that predicts is what a divergence means.
    let completedBytesPerSecond: Double?

    /// How many original reads the three latency figures are computed over. `0` makes them all
    /// `nil`, because `0` nanoseconds is a legitimate reading and cannot be its own sentinel.
    let readLatencySampleCount: UInt64

    /// FR-RPT-3's three, `nil` when there are no samples. The p99 is the **upper bound**: the
    /// true value is at or below it, within one histogram bucket. A report printing "p99 = x"
    /// would dress a bracketing interval as a measurement.
    let readLatencyMinimum: Duration?
    let readLatencyMaximum: Duration?
    let readLatencyP99UpperBound: Duration?

    let message: String

    /// Decode one `runRetentionCycle` reply.
    ///
    /// **Every parameter is labelled, and that is the point.** The reply block is twenty-two
    /// positional values, eight of which are adjacent same-typed numbers — four `Double` rates
    /// from v13, four `UInt64` latency figures — and it is assembled in the helper's `main.swift`
    /// and consumed in a closure, neither of which any unit test can reach. A transposition there
    /// compiles, runs, and puts read throughput under "write" in an exported report.
    ///
    /// Labelling does not make that impossible, but it puts each value's name beside it at the
    /// one call site where the mistake would be made, and `RunCycleOutcomeTests` pins the decode
    /// itself with values that are distinguishable from one another — a suite using `1.0` and
    /// `1.0` would pass with the two swapped.
    init(runOutcomeCode: Int,
         interruptedAtBlock: UInt64,
         chunksProcessed: UInt64,
         failedRangeCount: Int,
         failureSummary: String,
         cacheBypassCode: Int,
         bufferBytesHeld: Int,
         hostOverheadFraction: Double,
         helperCoreFraction: Double,
         failureModeUsedCode: Int,
         failedRangesEncoded: String,
         failedBlockCount: UInt64,
         deviceReadBytesPerSecond: Double,
         writeBytesPerSecond: Double,
         coverageBytesPerSecond: Double,
         completedBytesPerSecond: Double,
         readLatencySampleCount: UInt64,
         readLatencyMinimumNanoseconds: UInt64,
         readLatencyMaximumNanoseconds: UInt64,
         readLatencyP99UpperBoundNanoseconds: UInt64,
         message: String) {

        func latency(_ nanoseconds: UInt64) -> Duration? {
            WireSentinel.latency(nanoseconds, sampleCount: readLatencySampleCount)
        }

        let outcome = RunOutcomeCode(wireValue: runOutcomeCode)
        self.outcome = outcome
        // The code decides, not the value. See `resumeBlock`.
        self.resumeBlock = outcome == .pausedByUser ? interruptedAtBlock : nil
        self.chunksProcessed = chunksProcessed
        self.failedRangeCount = failedRangeCount
        self.failureSummary = failureSummary
        self.failedRanges = FailedRangeCoding.decode(failedRangesEncoded)
        self.failedBlockCount = failedBlockCount
        self.failureModeUsed = FailureModeCode(wireValue: failureModeUsedCode)
        self.cacheBypass = CacheBypassOutcome(wireValue: cacheBypassCode)
        self.bufferBytesHeld = bufferBytesHeld
        self.hostOverheadFraction = WireSentinel.rate(hostOverheadFraction)
        self.helperCoreFraction = WireSentinel.rate(helperCoreFraction)
        self.deviceReadBytesPerSecond = WireSentinel.rate(deviceReadBytesPerSecond)
        self.writeBytesPerSecond = WireSentinel.rate(writeBytesPerSecond)
        self.coverageBytesPerSecond = WireSentinel.rate(coverageBytesPerSecond)
        self.completedBytesPerSecond = WireSentinel.rate(completedBytesPerSecond)
        self.readLatencySampleCount = readLatencySampleCount
        self.readLatencyMinimum = latency(readLatencyMinimumNanoseconds)
        self.readLatencyMaximum = latency(readLatencyMaximumNanoseconds)
        self.readLatencyP99UpperBound = latency(readLatencyP99UpperBoundNanoseconds)
        self.message = message
    }

    /// How many retained ranges the cap dropped, or `nil` when the list could not be decoded.
    ///
    /// **Must be surfaced wherever ``failedRanges`` is shown.** A truncated list that does not
    /// say it is truncated reads exactly like a complete one — `FailureLog`'s rule, carried
    /// across the boundary into the artefact that outlives the session.
    var droppedRangeCount: Int? {
        failedRanges.map { max(0, failedRangeCount - $0.count) }
    }

    /// Did the cap drop anything?
    var listIsTruncated: Bool { (droppedRangeCount ?? 0) > 0 }
}

/// Owns the `NSXPCConnection`s to the privileged helper and exposes typed calls.
final class HelperConnection {

    private var connection: NSXPCConnection?

    /// A **second, non-owning** connection, used only for `runProgress`.
    ///
    /// ## Why two connections is not a design preference
    ///
    /// Measured 2026-08-04 (`scripts/xpc-concurrency-check.sh disk4`, 0 failures): while the
    /// helper is inside a blocking privileged call, **a second message on that same connection is
    /// not delivered until the call returns.** Twenty-four pings issued at 100 ms intervals during
    /// a 2,827.9 ms `digestRange` were all answered between 2,828.0 and 2,828.5 ms — the queue
    /// draining *after* the call finished. A **second connection** was answered concurrently
    /// throughout, in 0.2–0.3 ms.
    ///
    /// `runRetentionCycle` blocks for the whole run. So polling progress on ``connection`` would
    /// return nothing at all until the run ended, which is indistinguishable from a wedged
    /// daemon — and would make NFR-PERF-5's "refresh at least once per second" unachievable by
    /// construction rather than by a bug.
    ///
    /// ## Non-owning, and why that word is load-bearing
    ///
    /// This connection **never calls `acquireDevice`**. The helper releases a claim when the
    /// connection that acquired it goes away (NFR-REL-5), scoped by
    /// `HelperActivity.releaseIfOwned(by:)` to that connection's own acquisition — so this one
    /// dropping releases nothing and cannot pull a device out from under a run. The device has
    /// exactly one owner, which is why Step 6 hoisted `HelperConnection` to a single shared
    /// instance in the first place.
    private var progressConnection: NSXPCConnection?

    // MARK: - Connection lifecycle

    /// Lazily create (or reuse) the connection to the helper's Mach service.
    private func currentConnection() -> NSXPCConnection {
        if let connection { return connection }

        // `.privileged` looks the service up in the system (LaunchDaemon) domain.
        // This lookup is why the app must not be sandboxed: a sandboxed process
        // cannot resolve a privileged global Mach name without a temporary-exception
        // entitlement.
        let new = NSXPCConnection(machServiceName: HelperIdentity.machServiceName,
                                  options: .privileged)
        new.remoteObjectInterface = NSXPCInterface(with: TesterControl.self)
        new.invalidationHandler = { [weak self] in
            log.error("helper connection invalidated")
            // Hop to the main actor before touching `connection`: XPC delivers these
            // handlers on its own queue, and every other access to this property is
            // on the main actor.
            DispatchQueue.main.async { self?.connection = nil }
        }
        new.interruptionHandler = {
            log.error("helper connection interrupted")
        }
        new.resume()
        connection = new
        return new
    }

    /// The progress connection, created on first use.
    private func currentProgressConnection() -> NSXPCConnection {
        if let progressConnection { return progressConnection }

        let new = NSXPCConnection(machServiceName: HelperIdentity.machServiceName,
                                  options: .privileged)
        new.remoteObjectInterface = NSXPCInterface(with: TesterControl.self)
        new.invalidationHandler = { [weak self] in
            log.error("helper progress connection invalidated")
            DispatchQueue.main.async { self?.progressConnection = nil }
        }
        new.interruptionHandler = {
            log.error("helper progress connection interrupted")
        }
        new.resume()
        progressConnection = new
        return new
    }

    /// Tear down both connections. Used before re-registering the daemon (a stale
    /// connection outlives the daemon it pointed at) and on app exit. Step 4 folds
    /// this into the productised teardown path.
    func invalidate() {
        log.notice("invalidating helper connections")
        connection?.invalidate()
        connection = nil
        progressConnection?.invalidate()
        progressConnection = nil
    }

    // MARK: - Calls

    /// Ping the helper. Completion is always delivered on the main queue so the UI
    /// can bind to it directly.
    func ping(completion: @escaping (Result<String, Error>) -> Void) {
        withProxy(completion) { tester, finish in
            tester.ping { reply in finish(.success(reply)) }
        }
    }

    /// Query the helper's protocol version and compare it with this app's
    /// (NFR-MAINT-1).
    func checkProtocolVersion(completion: @escaping (Result<ProtocolVersionCheck, Error>) -> Void) {
        withProxy(completion) { tester, finish in
            tester.protocolVersion { helperVersion in
                let check: ProtocolVersionCheck = helperVersion == TesterProtocol.version
                    ? .match(version: helperVersion)
                    : .mismatch(helper: helperVersion, app: TesterProtocol.version)
                if case .mismatch = check {
                    log.error("\(check.description, privacy: .public)")
                }
                finish(.success(check))
            }
        }
    }

    /// Ask the helper to validate prospective run parameters (NFR-REL-7).
    ///
    /// The reply reflects the *helper's* independent verdict. The app deliberately
    /// does not pre-screen these values: a client-side check would only hide whether
    /// the boundary guard actually works, which is precisely what Step 3's gate has
    /// to demonstrate.
    func validateRunParameters(byteOffset: UInt64,
                               byteLength: UInt64,
                               logicalBlockSize: UInt32,
                               deviceBlockCount: UInt64,
                               completion: @escaping (Result<(accepted: Bool, message: String), Error>) -> Void) {
        withProxy(completion) { tester, finish in
            tester.validateRunParameters(byteOffset: byteOffset,
                                         byteLength: byteLength,
                                         logicalBlockSize: logicalBlockSize,
                                         deviceBlockCount: deviceBlockCount) { accepted, message in
                finish(.success((accepted: accepted, message: message)))
            }
        }
    }

    /// Ask the helper whether it is safe to remove, and have it release what it holds
    /// (NFR-INST-3, NFR-REL-5).
    ///
    /// Note the return type: this hands back a ``HelperShutdownReadiness``, never a
    /// `Result`. That is deliberate. Every failure — transport error, an older helper
    /// without this method, no answer at all — maps to
    /// ``HelperShutdownReadiness/unknown(detail:)``, so a caller *cannot* accidentally
    /// treat "we could not ask" as "unsafe" and strand an unremovable privileged
    /// daemon. The fail-open policy is encoded in the type rather than left to each
    /// call site to remember.
    ///
    /// - Parameter timeout: Guards the case the connection is accepted but the reply
    ///   never arrives. Without it a wedged helper would hang the uninstall forever —
    ///   precisely the situation failing open exists to survive.
    func prepareForShutdown(timeout: TimeInterval = 5,
                            completion: @escaping (HelperShutdownReadiness) -> Void) {
        var settled = false
        let settle: (HelperShutdownReadiness) -> Void = { readiness in
            // Both paths below deliver on the main queue, so this needs no lock.
            guard !settled else { return }
            settled = true
            completion(readiness)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            settle(.unknown(detail: "the helper did not answer within \(Int(timeout))s"))
        }

        withProxy({ (result: Result<HelperShutdownReadiness, Error>) in
            switch result {
            case .success(let readiness):
                settle(readiness)
            case .failure(let error):
                log.error("""
                          prepareForShutdown failed, treating as unknown: \
                          \(error.localizedDescription, privacy: .public)
                          """)
                settle(.unknown(detail: error.localizedDescription))
            }
        }) { tester, finish in
            tester.prepareForShutdown { safeToRemove, message in
                finish(.success(safeToRemove ? .safeToRemove(message)
                                             : .busy(reason: message)))
            }
        }
    }

    // MARK: - Step 6: the mount guard (FR-SAFE-1/2/3/4)

    /// Ask the helper what it can tell about a device without touching it.
    ///
    /// Safe to call on every selection change: the helper's implementation is
    /// side-effect-free, which is why it is a separate method from ``acquireDevice``.
    ///
    /// - Important: a `ready` of `true` does **not** promise an acquire will succeed.
    ///   Establishing FR-SAFE-4(b) requires actually claiming and opening the device, and
    ///   this call deliberately does neither. Treating it as a promise would put the "can
    ///   this run start?" decision app-side, which is exactly where it must not live.
    func checkDeviceReadiness(bsdName: String,
                              completion: @escaping (Result<DeviceReadiness, Error>) -> Void) {
        withProxy(completion) { tester, finish in
            tester.checkDeviceReadiness(bsdName: bsdName) { ready, count, summary, held, cause, message in
                finish(.success(DeviceReadiness(
                    isReady: ready,
                    mountedVolumeCount: count,
                    mountedVolumeSummary: summary,
                    helperHoldsThisDevice: held,
                    blockingCause: DeviceAccessRefusalCause(wireValue: cause),
                    message: message)))
            }
        }
    }

    /// Ask the helper to take exclusive whole-disk access (FR-SAFE-3).
    ///
    /// Note the return type: an ``DeviceAcquisition``, not a `Result` collapsed into a
    /// boolean. The refusal cause has to survive to the UI so the right corrective
    /// control can be offered — an Unmount All button is the fix for cause (a) and
    /// useless for cause (b).
    ///
    /// A *transport* failure — no helper, wrong version, connection dropped — is a
    /// `.failure` and must be treated as "access was not granted". Unlike the teardown
    /// path, which fails open by design, this one has no safe permissive reading: a run
    /// on a device nobody claimed is the exact situation the mount guard exists to
    /// prevent.
    func acquireDevice(bsdName: String,
                       completion: @escaping (Result<DeviceAcquisition, Error>) -> Void) {
        withProxy(completion) { tester, finish in
            tester.acquireDevice(bsdName: bsdName) { acquired, causeCode, message in
                finish(.success(acquired
                    ? .acquired(message)
                    : .refused(cause: DeviceAccessRefusalCause(wireValue: causeCode),
                               message: message)))
            }
        }
    }

    /// Ask the helper to release whatever device it holds (NFR-REL-5).
    ///
    /// - Important: success does not mean the device is immediately reusable. Release is
    ///   asynchronous, and macOS will remount the volumes shortly afterwards.
    func releaseDevice(completion: @escaping (Result<String, Error>) -> Void) {
        withProxy(completion) { tester, finish in
            tester.releaseDevice { _, message in finish(.success(message)) }
        }
    }

    // MARK: - Step 7's device profile, called by the app from Step 9

    /// What the helper established about the device it holds — geometry, the FR-TEST-9 verdict,
    /// and the **negotiated USB link speed**.
    ///
    /// On the protocol since Step 7 but never called from the app until now. Step 9 needs the
    /// link speed: judging a drive's throughput means comparing it with the manufacturer's
    /// advertised sustained figure *after accounting for the negotiated link*, and that is the
    /// user's judgement to make (decision 2026-08-04) — which they cannot make with only one of
    /// the two numbers.
    ///
    /// Passive and side-effect-free: it performs no I/O and opens nothing. Requires a device to
    /// be held.
    func deviceProfile(completion: @escaping (Result<DeviceProfile, Error>) -> Void) {
        withProxy(completion) { tester, finish in
            tester.deviceProfile { available, ioctlBlockSize, ioctlBlockCount, _, _,
                                   cacheBypassCode, linkSpeedCode, _, message in
                finish(.success(DeviceProfile(
                    isAvailable: available,
                    logicalBlockSize: ioctlBlockSize,
                    blockCount: ioctlBlockCount,
                    cacheBypass: CacheBypassOutcome(wireValue: cacheBypassCode),
                    usbLinkSpeedCode: linkSpeedCode,
                    message: message)))
            }
        }
    }

    // MARK: - Step 9: the run, and watching it

    /// Run the bounded read → write-back → verify cycle over the held device.
    ///
    /// **This is the only call the app makes that writes to a drive**, and it blocks for the
    /// whole run — which is precisely why ``runProgress(completion:)`` goes out on a different
    /// connection.
    ///
    /// Bounded to `TesterProtocol.maximumBytesPerCall`; the helper validates the request rather
    /// than trusting it. Step 11 replaces this with real run control.
    /// - Parameter failureMode: FR-FAIL-1's mode. Required — there is no default here, so
    ///   "nobody chose" and "somebody chose log-and-continue" cannot be the same call. The helper
    ///   refuses a code it does not recognise rather than defaulting.
    func runRetentionCycle(startBlock: UInt64,
                           blockCount: UInt64,
                           ioSizeBytes: Int,
                           failureMode: FailureModeCode,
                           completion: @escaping (Result<RunCycleOutcome, Error>) -> Void) {
        withProxy(completion) { tester, finish in
            tester.runRetentionCycle(startBlock: startBlock,
                                     blockCount: blockCount,
                                     ioSizeBytes: ioSizeBytes,
                                     failureModeCode: failureMode.rawValue) {
                runOutcomeCode, interruptedAtBlock, chunks, failedRangeCount, failureSummary,
                cacheBypassCode, _, bufferBytesHeld, hostOverheadFraction, helperCoreFraction,
                failureModeUsedCode, failedRangesEncoded, failedBlockCount,
                deviceReadBytesPerSecond, writeBytesPerSecond, coverageBytesPerSecond,
                completedBytesPerSecond, readLatencySampleCount,
                readLatencyMinimum, readLatencyMaximum, readLatencyP99Upper, message in

                // Straight into a labelled initialiser, one value per line. Twenty-two positional
                // values with eight adjacent same-typed numbers among them is exactly where a
                // transposition hides, and this closure is not reachable by any unit test.
                finish(.success(RunCycleOutcome(
                    runOutcomeCode: runOutcomeCode,
                    interruptedAtBlock: interruptedAtBlock,
                    chunksProcessed: chunks,
                    failedRangeCount: failedRangeCount,
                    failureSummary: failureSummary,
                    cacheBypassCode: cacheBypassCode,
                    bufferBytesHeld: bufferBytesHeld,
                    hostOverheadFraction: hostOverheadFraction,
                    helperCoreFraction: helperCoreFraction,
                    failureModeUsedCode: failureModeUsedCode,
                    failedRangesEncoded: failedRangesEncoded,
                    failedBlockCount: failedBlockCount,
                    deviceReadBytesPerSecond: deviceReadBytesPerSecond,
                    writeBytesPerSecond: writeBytesPerSecond,
                    coverageBytesPerSecond: coverageBytesPerSecond,
                    completedBytesPerSecond: completedBytesPerSecond,
                    readLatencySampleCount: readLatencySampleCount,
                    readLatencyMinimumNanoseconds: readLatencyMinimum,
                    readLatencyMaximumNanoseconds: readLatencyMaximum,
                    readLatencyP99UpperBoundNanoseconds: readLatencyP99Upper,
                    message: message)))
            }
        }
    }

    /// Ask the helper what the run in progress is doing (FR-METR-2/4/5/6, NFR-PERF-5).
    ///
    /// **Goes out on ``progressConnection``, not the main one**, because a second message on a
    /// connection with a blocking call in flight is not delivered until that call returns
    /// (measured 2026-08-04). Safe to call once a second for a whole run: the helper takes a
    /// lock, reads counters and walks a fixed 2,240-bucket histogram.
    func runProgress(completion: @escaping (Result<RunProgressSnapshot, Error>) -> Void) {
        withProxy(completion, on: currentProgressConnection()) { tester, finish in
            tester.runProgress { available, fraction, currentBlock, readRate, writeRate,
                                 coveringRate, completedRate, remainingSeconds, latencySamples,
                                 latencyMinimum,
                                 latencyMaximum, latencyP99Upper, chunksFailed in
                finish(.success(RunProgressSnapshot(
                    available: available,
                    fractionComplete: fraction,
                    currentBlock: currentBlock,
                    deviceReadBytesPerSecond: readRate,
                    writeBytesPerSecond: writeRate,
                    coverageBytesPerSecond: coveringRate,
                    completedBytesPerSecond: completedRate,
                    estimatedRemainingSeconds: remainingSeconds,
                    readLatencySampleCount: latencySamples,
                    readLatencyMinimumNanoseconds: latencyMinimum,
                    readLatencyMaximumNanoseconds: latencyMaximum,
                    readLatencyP99UpperBoundNanoseconds: latencyP99Upper,
                    chunksFailed: chunksFailed)))
            }
        }
    }

    /// Tell the helper what the run in flight should do at its next chunk boundary
    /// (FR-CTRL-2/3/4, NFR-REL-10).
    ///
    /// **Goes out on ``progressConnection``, not the owning one**, and that is not a style choice:
    /// a second message on a connection with a blocking call in flight is not delivered until that
    /// call returns (measured 2026-08-04). Sent on the run's own connection, a pause would arrive
    /// *after* the run it was meant to interrupt had already ended — the button would appear dead,
    /// and then the run would stop by itself a few seconds later, which is the worst available way
    /// for a control to be wrong.
    ///
    /// The connection stays **non-owning**: this method never acquires, so its death still releases
    /// nothing (NFR-REL-5).
    ///
    /// ## The reply is NOT the acknowledgement
    ///
    /// Success here means the helper *recorded* the request. It does **not** mean the run has
    /// settled, and nothing may show "Paused" on the strength of it — that is precisely the
    /// two-party handshake BUILD-PLAN's risks note forbids collapsing. The acknowledgement is the
    /// **`runRetentionCycle` reply** coming back with `RunOutcomeCode.pausedByUser` and its resume
    /// block, which is the helper stating it settled at a chunk boundary with no write in flight.
    func setRunControl(_ code: RunControlCode,
                       completion: @escaping (Result<(accepted: Bool, message: String), Error>) -> Void) {
        withProxy(completion, on: currentProgressConnection()) { tester, finish in
            tester.setRunControl(code: code.rawValue) { accepted, message in
                finish(.success((accepted: accepted, message: message)))
            }
        }
    }

    // MARK: - Plumbing

    /// Obtain the remote proxy and hand it to `body`, routing every failure path —
    /// transport error, proxy type mismatch — to `completion` on the main queue.
    ///
    /// Worth noting what a "transport error" means here after Step 3: if this app
    /// were not signed under the expected Team ID, the helper's code-signing
    /// requirement would invalidate the connection and every call below would fail
    /// through this path. A foreign client sees exactly this.
    /// - Parameter connection: which connection to send on. Defaults to the owning one; only
    ///   ``runProgress(completion:)`` passes the progress connection, and it must, because the
    ///   owning connection is blocked for the duration of a run.
    private func withProxy<T>(_ completion: @escaping (Result<T, Error>) -> Void,
                              on connection: NSXPCConnection? = nil,
                              _ body: (TesterControl, @escaping (Result<T, Error>) -> Void) -> Void) {
        let finish: (Result<T, Error>) -> Void = { result in
            DispatchQueue.main.async { completion(result) }
        }

        let proxy = (connection ?? currentConnection())
            .remoteObjectProxyWithErrorHandler { error in
                log.error("helper transport error: \(error.localizedDescription, privacy: .public)")
                finish(.failure(error))
            }

        guard let tester = proxy as? TesterControl else {
            finish(.failure(HelperConnectionError.proxyUnavailable))
            return
        }

        body(tester, finish)
    }
}
