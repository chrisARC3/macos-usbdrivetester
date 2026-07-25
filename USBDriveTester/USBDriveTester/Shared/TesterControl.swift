//
//  TesterControl.swift
//  Shared between the unprivileged app and the privileged helper.
//
//  This is the *versioned XPC contract* (NFR-MAINT-1). For Step 1 it carries a
//  single placeholder method, `ping`, purely to prove the app <-> helper plumbing
//  end-to-end. The real device-control surface (geometry query, start/pause/
//  resume/stop, progress callbacks) is added in Step 3 and later, and stays as
//  minimal as possible (NFR-SEC-3).
//
//  IMPORTANT (trust boundary): this file must be a member of BOTH the app target
//  and the helper target. With Xcode's file-system-synchronized groups it joins
//  the app target automatically because it lives under the app's folder; you add
//  the helper target via the File Inspector's "Target Membership" checkbox.
//

import Foundation

/// The XPC interface vended by the privileged helper.
///
/// Must be `@objc` so it can be wrapped by `NSXPCInterface`. Every method is
/// asynchronous with a reply block, as required by the NSXPC reply-based model.
@objc public protocol TesterControl {

    /// Liveness / plumbing check. Replies with `"pong"`.
    ///
    /// Step 1 acceptance uses this to confirm the connection, the interface
    /// wiring, and the reply path all work across the process boundary.
    func ping(reply: @escaping (String) -> Void)
}

/// Single source of truth for the helper's identity. This one string is used as:
///   * the LaunchDaemon `Label`,
///   * the advertised Mach service name, and
///   * the `SMAppService` daemon plist name (Step 3).
/// Keeping it here prevents the three from drifting apart.
public enum HelperIdentity {
    public static let machServiceName = "com.arc3solutions.USBDriveTester.Helper"
}
