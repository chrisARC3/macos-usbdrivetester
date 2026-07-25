//
//  HelperConnection.swift
//  USBDriveTester (app target — unprivileged)
//
//  The app side of the XPC link. It NEVER performs privileged work itself
//  (FR-ARCH-2, NFR-SEC-1); it only talks to the helper over an authenticated XPC
//  connection. For Step 1 the single call is `ping`. SMAppService registration
//  (which makes the Mach service resolvable without a manual launchctl bootstrap)
//  arrives in Step 3.
//

import Foundation
import os

private let log = Logger(subsystem: "com.arc3solutions.USBDriveTester", category: "app.xpc")

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

/// Owns the `NSXPCConnection` to the privileged helper and exposes typed calls.
final class HelperConnection {

    private var connection: NSXPCConnection?

    /// Lazily create (or reuse) the connection to the helper's Mach service.
    private func currentConnection() -> NSXPCConnection {
        if let connection { return connection }

        // `.privileged` looks the service up in the system (LaunchDaemon) domain.
        let new = NSXPCConnection(machServiceName: HelperIdentity.machServiceName,
                                  options: .privileged)
        new.remoteObjectInterface = NSXPCInterface(with: TesterControl.self)
        new.invalidationHandler = { [weak self] in
            log.error("helper connection invalidated")
            self?.connection = nil
        }
        new.interruptionHandler = {
            log.error("helper connection interrupted")
        }
        new.resume()
        connection = new
        return new
    }

    /// Ping the helper. Completion is always delivered on the main queue so the
    /// UI can bind to it directly.
    func ping(completion: @escaping (Result<String, Error>) -> Void) {
        let finish: (Result<String, Error>) -> Void = { result in
            DispatchQueue.main.async { completion(result) }
        }

        let proxy = currentConnection().remoteObjectProxyWithErrorHandler { error in
            log.error("ping transport error: \(error.localizedDescription, privacy: .public)")
            finish(.failure(error))
        }

        guard let tester = proxy as? TesterControl else {
            finish(.failure(HelperConnectionError.proxyUnavailable))
            return
        }

        tester.ping { reply in
            finish(.success(reply))
        }
    }

    /// Tear down the connection (used on app exit / future Step 4 teardown).
    func invalidate() {
        connection?.invalidate()
        connection = nil
    }
}
