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
enum ProtocolVersionCheck: Equatable {
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

    /// Human-readable summary, shown as the readiness banner.
    let message: String

    /// Whether the helper lacks Full Disk Access (NFR-INST-4). Surfaced before a run is
    /// attempted, not after one fails.
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

/// Owns the `NSXPCConnection` to the privileged helper and exposes typed calls.
final class HelperConnection {

    private var connection: NSXPCConnection?

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

    /// Tear down the connection. Used before re-registering the daemon (a stale
    /// connection outlives the daemon it pointed at) and on app exit. Step 4 folds
    /// this into the productised teardown path.
    func invalidate() {
        log.notice("invalidating helper connection")
        connection?.invalidate()
        connection = nil
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

    // MARK: - Plumbing

    /// Obtain the remote proxy and hand it to `body`, routing every failure path —
    /// transport error, proxy type mismatch — to `completion` on the main queue.
    ///
    /// Worth noting what a "transport error" means here after Step 3: if this app
    /// were not signed under the expected Team ID, the helper's code-signing
    /// requirement would invalidate the connection and every call below would fail
    /// through this path. A foreign client sees exactly this.
    private func withProxy<T>(_ completion: @escaping (Result<T, Error>) -> Void,
                              _ body: (TesterControl, @escaping (Result<T, Error>) -> Void) -> Void) {
        let finish: (Result<T, Error>) -> Void = { result in
            DispatchQueue.main.async { completion(result) }
        }

        let proxy = currentConnection().remoteObjectProxyWithErrorHandler { error in
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
