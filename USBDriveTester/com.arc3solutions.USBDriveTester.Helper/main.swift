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

    private init() {}

    /// What the helper is busy with, or `nil` if it is idle and safe to remove.
    var current: String? {
        lock.withLock {
            if let held { return held.device.activityDescription }
            if acquireInProgress { return "a device is being acquired" }
            return nil
        }
    }

    /// The device currently held, or `nil`. Lets the readiness check answer FR-SAFE-7's
    /// question — is this device held? — without side effects.
    var heldDeviceName: String? {
        lock.withLock { held?.device.device.rawValue }
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

    /// Release everything held, and describe what was released.
    ///
    /// Idempotent, and safe to call when nothing is held — which is what
    /// `prepareForShutdown` does on its idle path.
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
        let message = HelperActivity.shared.releaseAll()
        safetyLog.notice("""
                         release requested by \(self.peer, privacy: .public): \
                         \(message, privacy: .public)
                         """)
        reply(true, message)
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
