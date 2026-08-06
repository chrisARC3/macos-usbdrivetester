//
//  main.swift
//  com.arc3solutions.USBDriveTester.Helper
//
//  The privileged LaunchDaemon, installed and started by `SMAppService` (FR-ARCH-3,
//  NFR-SEC-5). In the finished product this process is the ONLY place raw, uncached,
//  block-level I/O happens (FR-ARCH-6, NFR-SEC-1). As of Step 3 it still does nothing
//  privileged — it stands up the XPC listener, authenticates callers, and validates
//  parameters. Device access arrives in Steps 6/7.
//
//  This process runs as **root**. Two consequences shape everything below:
//
//    1. Every caller must prove it is ours before it can reach the exported object
//       (FR-ARCH-5, NFR-SEC-2) — see `ListenerDelegate`.
//    2. Every argument is untrusted input even from an authenticated caller
//       (NFR-REL-7, NFR-SEC-3). Authentication answers "who", never "is this sane".
//       See `validateRunParameters`.
//

import Foundation
import Security
import os

private let log = Logger(subsystem: HelperIdentity.loggingSubsystem, category: "xpc")
private let lifecycleLog = Logger(subsystem: HelperIdentity.loggingSubsystem, category: "lifecycle")

/// Step 6's category (NFR-OBS-1): the mount guard, the claim, and every refusal. Shared
/// with `DeviceClaim.swift`, so one predicate shows the whole acquire/release story:
/// `log show --predicate 'subsystem == "com.arc3solutions.USBDriveTester" and category == "safety"'`.
private let safetyLog = Logger(subsystem: HelperIdentity.loggingSubsystem, category: "safety")

/// Step 7's category (NFR-OBS-1): geometry, uncached-I/O configuration, and the cache-bypass
/// verdict. Shared with `RawDeviceGeometry.swift`, so one predicate shows the whole I/O story:
/// `log show --predicate 'subsystem == "com.arc3solutions.USBDriveTester" and category == "io"'`.
private let ioLog = Logger(subsystem: HelperIdentity.loggingSubsystem, category: "io")

// MARK: - Advisory peer identification (logging only)

/// Best-effort description of an XPC peer, **for log messages only**.
///
/// ## This is not a security check and must never become one.
///
/// It resolves the peer by **PID**, which is unsafe as an authorisation mechanism:
/// a PID can be reused between the moment it is captured and the moment it is
/// resolved, so a hostile process can in principle arrange to be described as
/// something it is not. The actual trust decision is made by
/// `NSXPCConnection.setCodeSigningRequirement(_:)`, which evaluates the peer's
/// **audit token** — an unforgeable, non-reusable credential.
///
/// The reason this exists at all: the Step 3 gate requires that a rejection be
/// *logged*, and "rejected pid 5312 (identifier `negative-client`, team: none)" is a
/// far more useful breadcrumb than "rejected pid 5312" (NFR-OBS-1). A misleading log
/// line is an acceptable failure mode; a misleading authorisation decision is not.
private enum PeerDescription {

    static func describe(pid: pid_t) -> String {
        guard let (identifier, team) = signingInfo(pid: pid) else {
            return "pid \(pid) (signing information unavailable)"
        }
        return "pid \(pid) (identifier \(identifier), team \(team ?? "none — unsigned or adhoc"))"
    }

    private static func signingInfo(pid: pid_t) -> (identifier: String, team: String?)? {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: NSNumber(value: pid)] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code else { return nil }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode else { return nil }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode,
                                            SecCSFlags(rawValue: kSecCSSigningInformation),
                                            &information) == errSecSuccess,
              let dictionary = information as? [String: Any] else { return nil }

        let identifier = dictionary[kSecCodeInfoIdentifier as String] as? String ?? "unknown"
        let team = dictionary[kSecCodeInfoTeamIdentifier as String] as? String
        return (identifier, team)
    }
}

// MARK: - What the helper is holding

/// Tracks the resources this daemon currently owns, so it can answer authoritatively
/// when the GUI asks whether it is safe to remove (NFR-INST-3, NFR-REL-5).
///
/// The GUI cannot answer this question for itself: its own run state lives in a
/// process the user can force-quit and relaunch, whereas *this* process is the one
/// holding the device node and the DiskArbitration claim.
///
/// ## Step 6 status: live
///
/// Step 4 built this shape and left it deliberately always idle, because nothing could
/// yet acquire a device. Step 6 closes that loop: acquiring stores an ``AcquiredDevice``
/// here, which makes ``current`` non-nil, which makes `prepareForShutdown` genuinely
/// refuse — the refusal path that had never been reachable — and gives ``releaseAll()``
/// something real to release (NFR-REL-5). Step 11 wires it to the run-control state
/// machine.
///
/// ## One device at a time (FR-CTRL-9)
///
/// At most one ``AcquiredDevice`` is held. Enforced here rather than in the XPC method,
/// because two connections can call `acquireDevice` concurrently and XPC delivers them on
/// separate queues.
///
/// ## Ownership, and why a crashed GUI must not strand a claim
///
/// Each acquisition records the connection that made it. If that connection goes away —
/// the app quit, crashed, or was force-quit — the claim is released (see
/// `ListenerDelegate`). Without that, a claim would outlive its owner and the device's
/// volumes would stay unmountable until this daemon was restarted, which is precisely the
/// stuck state NFR-REL-5 exists to prevent. It matters more here than it looks: macOS
/// only remounts once the claim is dropped, so an orphaned claim is invisible except as a
/// drive that has silently stopped mounting.
///
/// `@unchecked Sendable` with an explicit lock: XPC delivers calls on arbitrary
/// queues, so every access is serialised here rather than assuming a single caller.
final class HelperActivity: @unchecked Sendable {

    static let shared = HelperActivity()

    private let lock = NSLock()

    /// The device currently held, and which connection acquired it.
    private var held: (device: AcquiredDevice, owner: UUID)?

    /// Set while an acquire is in flight, so two concurrent acquires cannot both get
    /// past the check. Separate from ``held`` because acquiring blocks for up to the
    /// claim timeout, and the lock must not be held across that — a `prepareForShutdown`
    /// arriving meanwhile would otherwise stall for five seconds.
    private var acquireInProgress = false

    /// What the helper is doing with the held device right now, or `nil` when it is merely
    /// holding it (Step 8). Same reasoning as ``acquireInProgress`` and more so: a cycle
    /// **writes**, so nothing may release the device or tear the helper down underneath it
    /// (NFR-REL-5). The lock is never held across the operation itself, which is bounded to
    /// `TesterProtocol.maximumBytesPerCall`.
    ///
    /// A description rather than a `Bool` because a digest and a cycle are both exclusive uses
    /// of the one descriptor but are very different things to tell a user about — "a retention
    /// cycle is writing to disk4" would be a lie during a read-only fingerprint.
    private var deviceOperation: String?

    private init() {}

    /// What the helper is busy with, or `nil` if it is idle and safe to remove.
    var current: String? {
        lock.withLock {
            if let operation = deviceOperation, let held {
                return "\(operation) on \(held.device.device.rawValue)"
            }
            if let held { return held.device.activityDescription }
            if acquireInProgress { return "a device is being acquired" }
            return nil
        }
    }

    /// Whether the device is in use, so `releaseDevice` can refuse rather than close the
    /// descriptor out from under an operation in progress.
    var isBusy: Bool { lock.withLock { deviceOperation != nil } }

    /// The device currently held, or `nil`. Lets the readiness check answer FR-SAFE-7's
    /// question — is this device held? — without side effects.
    var heldDeviceName: String? {
        lock.withLock { held?.device.device.rawValue }
    }

    /// The held device itself, for read-only interrogation (Step 7's `deviceProfile`).
    ///
    /// Returns the object rather than copying facts out of it one at a time, so a caller
    /// cannot assemble a profile from values read at different moments.
    var heldDevice: AcquiredDevice? {
        lock.withLock { held?.device }
    }

    /// Take exclusive access on behalf of `owner`, if nothing is held already.
    func acquire(_ device: WholeDiskName,
                 owner: UUID) -> Result<AcquiredDevice, DeviceAccessRefusal> {

        lock.lock()
        if let held {
            let heldName = held.device.device.rawValue
            lock.unlock()
            return .failure(.alreadyHeld(bsdName: device.rawValue, heldDeviceName: heldName))
        }
        if acquireInProgress {
            lock.unlock()
            return .failure(.checkIncomplete(
                bsdName: device.rawValue,
                detail: "another acquire is already in progress"))
        }
        acquireInProgress = true
        lock.unlock()

        // Deliberately outside the lock: this blocks for up to DeviceClaim.claimTimeout.
        let result = DeviceClaim.acquire(device)

        lock.lock()
        acquireInProgress = false
        if case .success(let acquired) = result {
            held = (acquired, owner)
        }
        lock.unlock()

        return result
    }

    /// The outcome of asking for exclusive use of the held device (Step 8).
    enum DeviceOperationClaim {
        case started(AcquiredDevice)
        case refused(RetentionCycleRefusal)
    }

    /// Take the device-operation slot, if a device is held and nothing else is using it.
    ///
    /// Returns the held device rather than requiring the caller to fetch it separately, so an
    /// operation cannot begin against a device that was released between the check and the work.
    ///
    /// - Parameter description: what is being done, in words a user can be shown while it is
    ///   happening — it becomes `prepareForShutdown`'s refusal reason.
    func beginDeviceOperation(_ description: String) -> DeviceOperationClaim {
        lock.lock()
        defer { lock.unlock() }

        guard let held else { return .refused(.noDeviceHeld) }
        guard deviceOperation == nil else {
            return .refused(.deviceBusy(deviceName: held.device.device.rawValue,
                                        operation: deviceOperation ?? "an operation"))
        }
        deviceOperation = description
        return .started(held.device)
    }

    /// Give the slot back. Always paired with a successful ``beginDeviceOperation(_:)`` via
    /// `defer`.
    func endDeviceOperation() {
        lock.withLock { deviceOperation = nil }
    }

    /// Release everything held, and describe what was released.
    ///
    /// Idempotent, and safe to call when nothing is held — which is what
    /// `prepareForShutdown` does on its idle path.
    ///
    /// - Important: this does **not** check ``isRunning``. Callers that can refuse must check
    ///   it first — `releaseDevice` does. The one caller that must not refuse is the
    ///   connection-loss path: a claim that outlives its owner leaves the drive unmountable
    ///   until the daemon restarts, which is worse than interrupting a write. The cycle's own
    ///   per-chunk write guard is what makes that interruption safe — the grant is recomputed,
    ///   so the very next write is refused (NFR-REL-3, NFR-REL-5).
    func releaseAll() -> String {
        lock.lock()
        let device = held?.device
        held = nil
        lock.unlock()

        guard let device else {
            return "No device is held, so there was nothing to release."
        }
        return device.release()
    }

    /// Release only if `owner` is the connection that acquired it.
    ///
    /// Returns what was released, or `nil` if this owner held nothing — so a connection
    /// dropping does not tear down a device some *other* connection is using.
    func releaseIfOwned(by owner: UUID) -> String? {
        lock.lock()
        guard let current = held, current.owner == owner else {
            lock.unlock()
            return nil
        }
        held = nil
        lock.unlock()

        return current.device.release()
    }
}

// MARK: - Exported object

/// Concrete implementation of the XPC interface (``TesterControl``).
///
/// A fresh instance is vended per connection, so no state can leak between clients.
final class TesterControlImpl: NSObject, TesterControl {

    /// Peer description captured at accept time, carried purely so log lines from
    /// this connection can be attributed.
    private let peer: String

    /// Identifies this connection as the owner of anything it acquires, so the claim can
    /// be released if the connection dies (see `HelperActivity.releaseIfOwned(by:)`).
    /// A fresh instance is vended per connection, so this is per-connection by
    /// construction. Deliberately not the peer's pid: pids are reused, and a reused pid
    /// would let an unrelated process's disconnect release someone else's device.
    let owner = UUID()

    init(peer: String) {
        self.peer = peer
    }

    /// Bound the length of anything a caller sends before it reaches a message or a log
    /// line. The value is only ever displayed, never executed or turned into a path —
    /// but a root daemon should not write a caller-controlled megabyte into the unified
    /// log because someone asked it to.
    private static func truncated(_ value: String, limit: Int = 64) -> String {
        value.count <= limit ? value : String(value.prefix(limit)) + "…"
    }

    func ping(reply: @escaping (String) -> Void) {
        log.info("ping from \(self.peer, privacy: .public); replying pong")
        reply("pong")
    }

    func protocolVersion(reply: @escaping (Int) -> Void) {
        log.info("""
                 protocol-version handshake with \(self.peer, privacy: .public); \
                 helper implements v\(TesterProtocol.version, privacy: .public)
                 """)
        reply(TesterProtocol.version)
    }

    func validateRunParameters(byteOffset: UInt64,
                               byteLength: UInt64,
                               logicalBlockSize: UInt32,
                               deviceBlockCount: UInt64,
                               reply: @escaping (Bool, String) -> Void) {

        // The helper re-derives the verdict itself rather than trusting anything the
        // caller asserted about it (NFR-REL-7). From Step 7 the geometry arrives from
        // the helper's own DKIOCGETBLOCKSIZE / DKIOCGETBLOCKCOUNT ioctls instead of
        // over the wire; the validation call below is unchanged by that switch.
        let geometry = DeviceGeometry(logicalBlockSize: logicalBlockSize,
                                      blockCount: deviceBlockCount)

        do {
            let range = try RunParameterValidator.validate(byteOffset: byteOffset,
                                                           byteLength: byteLength,
                                                           geometry: geometry)
            // Offsets, lengths and block counts are safe to log; device *contents*
            // never are (NFR-SEC-6). Nothing here touches device data.
            log.info("""
                     parameters ACCEPTED from \(self.peer, privacy: .public): \
                     \(range.blockCount, privacy: .public) block(s) of \
                     \(logicalBlockSize, privacy: .public) B from block \
                     \(range.startBlock, privacy: .public)
                     """)
            reply(true, """
                        Parameters accepted: \(range.blockCount) block(s) of \
                        \(logicalBlockSize) bytes starting at block \(range.startBlock).
                        """)

        } catch let rejection as RunParameterRejection {
            log.error("""
                      parameters REJECTED from \(self.peer, privacy: .public): \
                      \(rejection.description, privacy: .public)
                      """)
            reply(false, rejection.description)

        } catch {
            // Unreachable today — RunParameterValidator throws only
            // RunParameterRejection — but a root process should fail closed rather
            // than let an unanticipated error fall through as success.
            log.error("""
                      parameters REJECTED from \(self.peer, privacy: .public) \
                      (unexpected error): \(error.localizedDescription, privacy: .public)
                      """)
            reply(false, "Parameters rejected: \(error.localizedDescription)")
        }
    }

    func prepareForShutdown(reply: @escaping (Bool, String) -> Void) {
        // Refuse rather than release while busy. This is the safe direction twice
        // over: it keeps a teardown from leaving a half-written device (NFR-REL-5),
        // and it means no caller — including a correctly Team-ID-signed one — can use
        // this method to abort a run in progress.
        if let activity = HelperActivity.shared.current {
            lifecycleLog.notice("""
                                prepareForShutdown REFUSED for \(self.peer, privacy: .public): \
                                \(activity, privacy: .public)
                                """)
            reply(false, activity)
            return
        }

        let released = HelperActivity.shared.releaseAll()
        lifecycleLog.notice("""
                            prepareForShutdown ACCEPTED for \(self.peer, privacy: .public); \
                            safe to remove — \(released, privacy: .public)
                            """)
        reply(true, released)
    }

    // MARK: - Step 6: the mount guard (FR-SAFE-1/2/3/4)

    func checkDeviceReadiness(bsdName: String,
                              reply: @escaping (Bool, Int, String, Bool, Int, String) -> Void) {

        let heldDeviceName = HelperActivity.shared.heldDeviceName
        let holdsThisDevice = heldDeviceName == bsdName

        // Every failure path still reports whether this device is held, so the app's
        // FR-SAFE-7 disable condition is answered even when the rest of the check
        // could not be performed.
        func fail(_ message: String, cause: DeviceAccessRefusalCause) {
            safetyLog.info("""
                           readiness check for \(Self.truncated(bsdName), privacy: .public) \
                           from \(self.peer, privacy: .public): \(message, privacy: .public)
                           """)
            reply(false, 0, "", holdsThisDevice, cause.rawValue, message)
        }

        let device: WholeDiskName
        do {
            device = try WholeDiskName(validating: bsdName)
        } catch let rejection as DeviceNameRejection {
            fail(rejection.description, cause: .deviceNotEligible)
            return
        } catch {
            fail("The device name could not be validated: \(error.localizedDescription)",
                 cause: .checkIncomplete)
            return
        }

        let eligible: EligibleDevice
        switch HelperDeviceRegistry.eligibility(of: device) {
        case .success(let value):
            eligible = value
        case .failure(let refusal):
            fail(refusal.description, cause: .deviceNotEligible)
            return
        }

        let mountState = HelperMountTable.mountState(ofSubtree: eligible.subtreeBSDNames)
        let volumeNames = mountState.volumeNames

        // NFR-INST-4. Checks the *permission*, never the device — probing the device with
        // the flags that actually reach the TCC gate makes DiskArbitration remount the
        // volume 4 ms later, which would undo the user's unmount on every poll. See
        // DeviceClaim.fullDiskAccessState().
        //
        // Skipped while we hold the device: we demonstrably opened it, which is stronger
        // evidence than any probe.
        let accessState: FullDiskAccessState =
            holdsThisDevice ? .granted : DeviceClaim.fullDiskAccessState()

        // Ready means "nothing known would refuse an acquire". It cannot mean "an
        // acquire will succeed": establishing FR-SAFE-4(b) requires actually claiming
        // and opening the device, and this method must stay side-effect-free so the GUI
        // can poll it to drive a display.
        let ready = !mountState.isMounted && heldDeviceName == nil && !accessState.isDenied

        // Ordered by what the user must fix first. Full Disk Access leads: without it
        // nothing else can be attempted, so telling someone to unmount a volume when the
        // permission is also missing would just send them round twice.
        let cause: DeviceAccessRefusalCause
        let message: String

        if accessState.isDenied {
            cause = .accessNotPermitted
            message = accessState.explanation ?? "Full Disk Access is required."
        } else if let heldDeviceName {
            cause = .alreadyHeld
            message = holdsThisDevice
                ? "This app holds exclusive access to \(device.rawValue). Release it "
                + "before starting another run."
                : "This app holds exclusive access to \(heldDeviceName); only one device "
                + "can be held at a time."
        } else if mountState.isMounted {
            cause = .volumesMounted
            message = volumeNames.count == 1
                ? "\(device.rawValue) has 1 mounted volume (\(volumeNames[0])). It must be "
                + "unmounted before a test can start."
                : "\(device.rawValue) has \(volumeNames.count) mounted volumes "
                + "(\(volumeNames.joined(separator: ", "))). They must be unmounted before "
                + "a test can start."
        } else {
            cause = .unrecognised   // raw value 0 — nothing is blocking
            var text = "\(device.rawValue) has no mounted volumes. Exclusive access has not "
                     + "been attempted yet — that happens when a run starts, and it is the "
                     + "only thing that can confirm no other process holds the device."
            // An inconclusive permission probe is surfaced rather than swallowed: a run
            // may still fail, and the user is entitled to know why in advance.
            if case .unknown = accessState, let detail = accessState.explanation {
                text += " " + detail
            }
            message = text
        }

        safetyLog.info("""
                       readiness check for \(device.rawValue, privacy: .public) from \
                       \(self.peer, privacy: .public): ready=\(ready, privacy: .public), \
                       \(volumeNames.count, privacy: .public) mounted volume(s), \
                       full-disk-access=\(String(describing: accessState), privacy: .public)
                       """)
        reply(ready, volumeNames.count, volumeNames.joined(separator: ", "),
              holdsThisDevice, cause.rawValue, message)
    }

    func acquireDevice(bsdName: String, reply: @escaping (Bool, Int, String) -> Void) {

        func refuse(_ refusal: DeviceAccessRefusal) {
            reply(false, refusal.causeCode, refusal.description)
        }

        let device: WholeDiskName
        do {
            device = try WholeDiskName(validating: bsdName)
        } catch let rejection as DeviceNameRejection {
            // A name that does not validate never becomes a path. This is the boundary
            // that stops a root daemon opening whatever string it is handed.
            safetyLog.error("""
                            acquire REFUSED for \(self.peer, privacy: .public): \
                            \(rejection.description, privacy: .public)
                            """)
            refuse(.deviceNotEligible(bsdName: Self.truncated(bsdName),
                                      reason: rejection.description))
            return
        } catch {
            refuse(.checkIncomplete(bsdName: Self.truncated(bsdName),
                                    detail: "the device name could not be validated"))
            return
        }

        switch HelperActivity.shared.acquire(device, owner: owner) {
        case .success(let acquired):
            safetyLog.notice("""
                             acquire GRANTED for \(self.peer, privacy: .public): \
                             \(acquired.activityDescription, privacy: .public)
                             """)
            reply(true, 0, """
                           Exclusive whole-disk access to \(device.rawValue) is held: no \
                           volumes are mounted, the DiskArbitration claim is in place so \
                           the system cannot remount them, and \(device.rawDevicePath) is \
                           open exclusively.
                           """)

        case .failure(let refusal):
            // DeviceClaim already logged the detail; this line attributes it to a caller.
            safetyLog.error("""
                            acquire REFUSED for \(self.peer, privacy: .public) on \
                            \(device.rawValue, privacy: .public), cause \
                            \(refusal.causeCode, privacy: .public)
                            """)
            refuse(refusal)
        }
    }

    func releaseDevice(reply: @escaping (Bool, String) -> Void) {
        // Step 8: never close the descriptor out from under a write in progress (NFR-REL-5).
        // Bounded by `TesterProtocol.maximumBytesPerCall`, so this refusal cannot last
        // long — which is the same property that makes the uncancellable cycle safe at all.
        guard !HelperActivity.shared.isBusy else {
            let message = "Cannot release: the device is in use — "
                        + (HelperActivity.shared.current ?? "an operation is in progress")
                        + ". Every such operation is bounded to "
                        + "\(TesterProtocol.maximumBytesPerCall) bytes per call, so try again "
                        + "shortly."
            safetyLog.notice("""
                             release REFUSED for \(self.peer, privacy: .public): \
                             \(HelperActivity.shared.current ?? "busy", privacy: .public)
                             """)
            reply(false, message)
            return
        }

        let message = HelperActivity.shared.releaseAll()
        safetyLog.notice("""
                         release requested by \(self.peer, privacy: .public): \
                         \(message, privacy: .public)
                         """)
        reply(true, message)
    }

    // MARK: - Step 7: what the helper established about the held device

    func deviceProfile(reply: @escaping (Bool, UInt32, UInt64, UInt32, UInt64,
                                          Int, Int, UInt64, String) -> Void) {

        guard let held = HelperActivity.shared.heldDevice else {
            ioLog.info("""
                       deviceProfile from \(self.peer, privacy: .public): no device is held
                       """)
            reply(false, 0, 0, 0, 0,
                  CacheBypassOutcome.unrecognised.rawValue, -1, 0,
                  "No device is held. Geometry comes from ioctls on the open descriptor, so a "
                + "device must be acquired first — the helper will not open a device "
                + "speculatively to answer a query, because releasing that open would make "
                + "macOS remount the volume.")
            return
        }

        let authoritative = held.deviceGeometry
        let ioKit = held.reconciliation.ioKit

        // Offsets, block counts and geometry are safe to log and to return; device *contents*
        // never are, and nothing here touches them (NFR-SEC-6).
        var message = "\(held.device.rawValue): \(authoritative.blockCount) blocks of "
                    + "\(authoritative.logicalBlockSize) bytes "
                    + "(\(authoritative.blockCount * UInt64(authoritative.logicalBlockSize)) bytes), "
                    + "from DKIOCGETBLOCKSIZE/DKIOCGETBLOCKCOUNT on the held descriptor. "

        if let disagreement = held.reconciliation.disagreement {
            message += "IOKit disagrees — \(disagreement) — and the ioctl values are used, "
                     + "because they are what the kernel enforces on every transfer. "
        } else if ioKit != nil {
            message += "The helper's own IOKit reading agrees. "
        } else {
            message += "IOKit reported no usable geometry to compare against. "
        }

        message += held.cacheBypass.reportLine

        ioLog.notice("""
                     deviceProfile for \(held.device.rawValue, privacy: .public) requested by \
                     \(self.peer, privacy: .public): \
                     \(held.reconciliation.logDescription, privacy: .public); \
                     cache-bypass \(String(describing: held.cacheBypass), privacy: .public)
                     """)

        reply(true,
              authoritative.logicalBlockSize,
              authoritative.blockCount,
              ioKit?.logicalBlockSize ?? 0,
              ioKit?.blockCount ?? 0,
              held.cacheBypass.wireCode,
              Self.linkSpeedCode(held.usbLinkSpeed),
              held.rawGeometry.maximumByteCountRead ?? 0,
              message)
    }

    // MARK: - Step 8: the read -> write-back -> verify cycle
    //
    // The only method on this interface that writes to a drive. Everything it needs to decide
    // has already been decided: `acquireDevice` established that nothing is mounted and that
    // exclusive access is held, `RunCoordinator` validates the request, and the pure engine
    // re-checks the write guard before every single chunk.

    func runRetentionCycle(startBlock: UInt64,
                           blockCount: UInt64,
                           ioSizeBytes: Int,
                           reply: @escaping (Bool, UInt64, Int, String,
                                             Int, Double, Int, Double, Double, String) -> Void) {

        ioLog.notice("""
                     runRetentionCycle from \(self.peer, privacy: .public): \
                     startBlock=\(startBlock, privacy: .public) \
                     blockCount=\(blockCount, privacy: .public) \
                     ioSize=\(ioSizeBytes, privacy: .public)
                     """)

        switch RunCoordinator.runCycle(startBlock: startBlock,
                                       blockCount: blockCount,
                                       ioSizeBytes: ioSizeBytes) {

        case .success(let result):
            let summary = result.summary
            // `completed` says every planned chunk was processed. It deliberately does NOT
            // mean they all passed — a run that finds bad blocks and keeps going still
            // completes (FR-FAIL-3), and collapsing the two would be the report saying
            // "clean" when it means "finished".
            var message = "Cycle \(summary.outcome.description): "
                        + "\(summary.chunksProcessed) of \(summary.chunksPlanned) chunks; "
                        + "\(summary.failures.summaryLine). "

            // FR-TEST-9: mandatory, not conditional on having failed. An absent line is
            // indistinguishable from a passing one.
            message += summary.cacheBypass.state.reportLine

            reply(summary.isComplete,
                  summary.chunksProcessed,
                  summary.failures.totalRangeCount,
                  summary.failures.summaryLine,
                  summary.cacheBypass.state.wireCode,
                  summary.cacheBypass.fastestObservedBytesPerSecond,
                  summary.bufferBytesHeld,
                  // NFR-PERF-3's two figures. `-1` for "could not be established" — never 0,
                  // which is a legitimate and very different answer.
                  result.hostOverheadFraction ?? -1,
                  result.helperCoreFraction ?? -1,
                  message)

        case .failure(let refusal):
            ioLog.error("""
                        runRetentionCycle REFUSED for \(self.peer, privacy: .public): \
                        \(refusal.description, privacy: .public)
                        """)
            reply(false, 0, 0, "",
                  CacheBypassOutcome.unrecognised.rawValue, 0, 0, -1, -1,
                  refusal.description)
        }
    }

    // MARK: - Step 9: live metrics
    //
    // Called on a SECOND connection while `runRetentionCycle` blocks this one. That is not a
    // convention, it is what the transport requires: measured 2026-08-04, a second message on a
    // connection with a call in flight is not delivered until the call returns.
    //
    // Read-only, takes no device slot, touches no descriptor. It reads the accumulating counters
    // under the metrics lock and computes a percentile over a fixed 2,240-bucket histogram, so
    // it is safe to call once a second for the whole of a run.

    func runProgress(reply: @escaping (Bool, Double, UInt64, Double, Double, Double,
                                       UInt64, UInt64, UInt64, UInt64, UInt64) -> Void) {

        guard let snapshot = MetricsChannel.shared.snapshot else {
            // No run has started since this daemon launched. Everything else is meaningless
            // and is zero rather than a plausible-looking figure.
            reply(false, 0, 0, -1, -1, -1, 0, 0, 0, 0, 0)
            return
        }

        // `-1` for a rate that has not been measured yet. Zero would print as "0 MB/s", which
        // means *stalled* — a real and alarming condition — and using it for "nothing has
        // happened yet" would show an alarm to report an absence.
        let readRate = snapshot.readBytesPerSecond ?? -1
        let writeRate = snapshot.writeBytesPerSecond ?? -1
        let remaining = snapshot.estimatedRemainingNanoseconds
            .map { Double($0) / 1_000_000_000 } ?? -1

        // The p99 travels as its upper bound: the true value is at or below it, within one
        // bucket of at most 1.5625%. `readLatencySampleCount` is what says whether the three
        // latency figures mean anything — 0 nanoseconds is itself a legitimate reading.
        let latency = snapshot.readLatency

        reply(true,
              snapshot.fractionComplete,
              snapshot.currentBlock,
              readRate,
              writeRate,
              remaining,
              latency.count,
              latency.minimumNanoseconds ?? 0,
              latency.maximumNanoseconds ?? 0,
              latency.p99?.upperBoundNanoseconds ?? 0,
              snapshot.chunksFailed)
    }

    /// SHA-256 of a bounded range of the held device (Step 8, gate item 5).
    ///
    /// Read-only. It is on this interface at all because a separate process **cannot** read the
    /// device while the helper holds `O_EXLOCK` — measured `EBUSY` on 2026-08-02, with a root
    /// process carrying Terminal's Full Disk Access grant and requesting no lock of its own.
    func digestRange(startBlock: UInt64,
                     blockCount: UInt64,
                     reply: @escaping (Bool, UInt64, String, String) -> Void) {

        switch RunCoordinator.digestRange(startBlock: startBlock, blockCount: blockCount) {

        case .success(let result):
            // The digest is logged: it is a fingerprint, not device contents (NFR-SEC-6), and
            // having it in the log is what lets a disagreement be investigated after the fact
            // (NFR-OBS-2).
            ioLog.notice("""
                         digest for \(self.peer, privacy: .public): blocks \
                         \(startBlock, privacy: .public)–\
                         \(startBlock + blockCount - 1, privacy: .public) \
                         (\(result.bytes, privacy: .public) B) = \
                         \(result.hex, privacy: .public)
                         """)
            reply(true, result.bytes, result.hex,
                  "Fingerprinted \(result.bytes) bytes from block \(startBlock).")

        case .failure(let refusal):
            ioLog.error("""
                        digestRange REFUSED for \(self.peer, privacy: .public): \
                        \(refusal.description, privacy: .public)
                        """)
            reply(false, 0, "", refusal.description)
        }
    }

    /// The raw IORegistry `Device Speed` code, or `-1` when none was reported.
    ///
    /// Sent as the raw code rather than an interpreted speed so the app is not forced to trust
    /// this build's reading of an enum that no SDK header declares (see `Core/USBLinkSpeed.swift`).
    private static func linkSpeedCode(_ speed: USBLinkSpeed?) -> Int {
        switch speed {
        case .none:                       return -1
        case .low:                        return 0
        case .full:                       return 1
        case .high:                       return 2
        case .superSpeed:                 return 3
        case .superSpeedPlus:             return 4
        case .superSpeedPlusBy2:          return 5
        case .unrecognised(let code):     return code
        }
    }
}

// MARK: - Listener delegate (the trust boundary)

/// Arms the Team-ID code-signing requirement on every inbound connection and wires
/// up the exported object.
///
/// Note that this delegate does not itself *decide* who gets served: XPC enforces
/// the requirement lazily, per message, after the delegate returns. See the extended
/// comment in `listener(_:shouldAcceptNewConnection:)`.
final class ListenerDelegate: NSObject, NSXPCListenerDelegate {

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {

        let pid = newConnection.processIdentifier
        let peer = PeerDescription.describe(pid: pid)
        log.info("""
                 incoming connection from \(peer, privacy: .public) \
                 euid \(newConnection.effectiveUserIdentifier, privacy: .public)
                 """)

        // THE SECURITY GATE (FR-ARCH-5, NFR-SEC-2).
        //
        // Pin the peer to our Team ID. XPC evaluates the requirement against the
        // peer's **audit token** — an unforgeable credential — which is why this,
        // and not the advisory PID lookup above, is what the trust decision rests on.
        //
        // Enforcement timing, per the SDK header for -setCodeSigningRequirement::
        //
        //   "If the requirement is malformed, an exception is thrown. If new
        //    messages do not match the requirement, the connection is invalidated.
        //    It is recommended to set this before calling `resume`, as it is an XPC
        //    error to call it more than once."
        //
        // Three consequences, all of which the code below depends on:
        //
        //   1. The method does NOT throw a Swift error, so there is nothing to
        //      `try`. A malformed requirement raises an ObjC exception, which would
        //      crash the daemon — acceptable and arguably correct, since a helper
        //      that cannot arm its own requirement must not serve anyone. The
        //      requirement is a compile-time constant, so this is not a runtime risk.
        //   2. Enforcement is LAZY and per-message. A non-conforming peer is NOT
        //      refused here — `shouldAcceptNewConnection` returns true for it — and
        //      is torn down by XPC when it sends its first message. So returning
        //      `true` below is not "this caller is trusted"; it is "the requirement
        //      is armed on this connection".
        //   3. It follows that the *rejection* surfaces in `invalidationHandler`,
        //      which is therefore where the Step 3 gate's "rejection is logged"
        //      requirement is satisfied — not here.
        //
        // Called exactly once per connection, before `resume()`, as required.
        newConnection.setCodeSigningRequirement(HelperIdentity.codeSigningRequirement)

        let exported = TesterControlImpl(peer: peer)
        newConnection.exportedInterface = NSXPCInterface(with: TesterControl.self)
        newConnection.exportedObject = exported

        // Captured by value, not by capturing `exported`: the connection already retains
        // the exported object, and retaining it again from a handler the connection also
        // owns would be a cycle.
        let owner = exported.owner

        // Because enforcement is lazy, this handler is the rejection path for a
        // foreign caller (see note 3 above). It also fires on an ordinary client
        // disconnect, and XPC does not tell us which occurred — so the message stays
        // honest about the ambiguity rather than asserting a rejection that may not
        // have happened. In practice the two are easy to tell apart in the log: a
        // rejected peer invalidates without any preceding ping / handshake /
        // parameter-validation entry attributed to it.
        newConnection.invalidationHandler = {
            log.notice("""
                       connection from \(peer, privacy: .public) invalidated — either the client \
                       disconnected, or it sent a message and FAILED the Team-ID requirement \
                       [\(HelperIdentity.codeSigningRequirement, privacy: .public)]. \
                       No preceding request log line for this peer means it was rejected.
                       """)

            // A device held by this connection must not outlive it (NFR-REL-5). If the
            // GUI quit, crashed, or was force-quit while holding the claim, nothing else
            // would ever release it — and because macOS only remounts once a claim is
            // dropped, the symptom would be a drive that has silently stopped mounting,
            // with no process visibly responsible. Scoped to this connection's own
            // acquisition, so one client disconnecting cannot release another's device.
            if let released = HelperActivity.shared.releaseIfOwned(by: owner) {
                safetyLog.notice("""
                                 released on connection loss from \(peer, privacy: .public): \
                                 \(released, privacy: .public)
                                 """)
            }
        }
        newConnection.interruptionHandler = {
            log.notice("connection from \(peer, privacy: .public) interrupted")
        }

        newConnection.resume()
        log.info("""
                 admitted connection from \(peer, privacy: .public) with the Team-ID requirement \
                 armed; exporting TesterControl v\(TesterProtocol.version, privacy: .public). \
                 A peer that does not satisfy the requirement is invalidated on its first message.
                 """)
        return true
    }
}

// MARK: - Daemon entry point

let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: HelperIdentity.machServiceName)
listener.delegate = delegate
listener.resume()

lifecycleLog.notice("""
                    helper started as uid \(getuid(), privacy: .public); \
                    listening on \(HelperIdentity.machServiceName, privacy: .public); \
                    protocol v\(TesterProtocol.version, privacy: .public); \
                    requiring [\(HelperIdentity.codeSigningRequirement, privacy: .public)]
                    """)

// Keep the daemon alive to service connections.
dispatchMain()
