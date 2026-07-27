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
