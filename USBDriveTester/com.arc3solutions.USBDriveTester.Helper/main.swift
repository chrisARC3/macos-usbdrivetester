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

// MARK: - Exported object

/// Concrete implementation of the XPC interface (``TesterControl``).
///
/// A fresh instance is vended per connection, so no state can leak between clients.
final class TesterControlImpl: NSObject, TesterControl {

    /// Peer description captured at accept time, carried purely so log lines from
    /// this connection can be attributed.
    private let peer: String

    init(peer: String) {
        self.peer = peer
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

        newConnection.exportedInterface = NSXPCInterface(with: TesterControl.self)
        newConnection.exportedObject = TesterControlImpl(peer: peer)

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
