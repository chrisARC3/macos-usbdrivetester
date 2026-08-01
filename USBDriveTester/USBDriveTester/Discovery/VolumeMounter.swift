//
//  VolumeMounter.swift
//  USBDriveTester (app target — unprivileged)
//
//  Mounts or unmounts every volume of a selected device (FR-SAFE-5), through
//  DiskArbitration.
//
//  ## Why this is app-side and not in the helper
//
//  It needs no privilege: `diskutil unmountDisk` succeeds without `sudo` on an external
//  drive, and DiskArbitration authorises the caller itself. Keeping it here holds the
//  privileged XPC surface down to check / acquire / release (NFR-SEC-3) — the helper runs
//  as root, so every method that does not have to exist there should not.
//
//  ## Whole-disk options, not per-volume calls
//
//  `kDADiskUnmountOptionWhole` and `kDADiskMountOptionWhole` act on "the volumes tied to
//  the whole disk object", which is what `diskutil unmountDisk` / `mountDisk` do. Driving
//  each volume individually would need the volumes' own device nodes, and for an APFS
//  drive those are not derivable from the physical disk's name — `1TB_Samsung` is mounted
//  from `/dev/disk7s1` while its physical disk is `disk6`, and only the IOKit registry
//  connects the two (see MountedVolumes.swift). Letting `diskarbitrationd` resolve the
//  relationship is both less code and correct for filesystems we have not tested against.
//
//  It also makes mounting possible at all: the mount table cannot list the volumes that
//  are *not* mounted, so "mount all" has nothing to enumerate.
//
//  ## What it never does
//
//  Nothing here is ever called as part of starting a test (FR-SAFE-6). It runs only when
//  the user presses the control. That separation is the whole point of the FR-SAFE-5/6
//  amendment: a mounted volume produces a refusal that names it, never a silent unmount.
//

import Foundation
import DiskArbitration
import os

private nonisolated let log = Logger(subsystem: HelperIdentity.loggingSubsystem,
                                     category: "safety")

/// The result of a mount or unmount, in words the user can act on (NFR-USE-5).
nonisolated enum VolumeMountOutcome: Equatable {

    /// The operation was accepted. The message points at the device list rather than
    /// asserting what is now mounted — the list is the authoritative display and updates
    /// itself through the `VolumeChangeWatcher`.
    case succeeded(String)

    /// It was refused or failed. The message names the volume and the reason.
    case failed(String)

    var isSuccess: Bool { if case .succeeded = self { return true } else { return false } }

    var message: String {
        switch self {
        case .succeeded(let text), .failed(let text): return text
        }
    }
}

/// Mounts and unmounts all volumes of a device.
///
/// One instance per use is fine; it holds no state between calls. Completions are
/// delivered on the main queue so the UI can bind to them directly.
nonisolated final class VolumeMounter {

    /// Guards the case where DiskArbitration neither completes nor dissents. A control
    /// stuck on "Working…" forever is worse than an honest "no answer": the user cannot
    /// tell whether the drive is busy or the app is.
    private static let timeout: TimeInterval = 20

    init() {}

    /// Unmount every volume of `device` (FR-SAFE-5).
    func unmountAll(_ device: DiscoveredDevice,
                    completion: @escaping (VolumeMountOutcome) -> Void) {

        let volumeList = device.mountedVolumesDescription ?? "its volumes"
        perform(on: device, verb: "unmount", completion: completion) { disk, callback, context in
            DADiskUnmount(disk, DADiskUnmountOptions(kDADiskUnmountOptionWhole),
                          callback, context)
        } describeSuccess: {
            "Unmounted every volume on \(device.bsdName): \(volumeList)."
        } describeFailure: { reason in
            // Names the volume(s) and the reason, not merely that it failed
            // (NFR-USE-5). An unmount refused because a file is open is the common case,
            // and "unmount failed" alone leaves the user with nowhere to go.
            "Could not unmount \(volumeList) on \(device.bsdName): \(reason) "
          + "Close any open files or applications using the drive, then try again."
        }
    }

    /// Mount every mountable volume of `device` (FR-SAFE-5).
    func mountAll(_ device: DiscoveredDevice,
                  completion: @escaping (VolumeMountOutcome) -> Void) {

        perform(on: device, verb: "mount", completion: completion) { disk, callback, context in
            DADiskMount(disk, nil, DADiskMountOptions(kDADiskMountOptionWhole),
                        callback, context)
        } describeSuccess: {
            // Deliberately does not claim anything was mounted. A device with nothing
            // macOS can mount keeps the control enabled (decision 7) and has to report
            // honestly rather than imply a result it did not produce.
            "Asked macOS to mount every volume on \(device.bsdName). If nothing appears "
          + "below, the drive has no volumes this Mac can mount — an unformatted drive, "
          + "or a filesystem macOS does not read."
        } describeFailure: { reason in
            "Could not mount the volumes on \(device.bsdName): \(reason)"
        }
    }

    // MARK: - Plumbing

    /// Shared body of both directions: create a session, run the DiskArbitration call,
    /// and settle exactly once — on the callback, or on the timeout.
    private func perform(on device: DiscoveredDevice,
                         verb: String,
                         completion: @escaping (VolumeMountOutcome) -> Void,
                         _ operation: (DADisk, @escaping DADiskUnmountCallback,
                                       UnsafeMutableRawPointer) -> Void,
                         describeSuccess: @escaping () -> String,
                         describeFailure: @escaping (String) -> String) {

        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session,
                                                 device.bsdName.rawValue) else {
            log.error("""
                      \(verb, privacy: .public) failed for \
                      \(device.bsdName.rawValue, privacy: .public): no DiskArbitration session
                      """)
            completion(.failed("""
                               Could not talk to the disk-management service, so \
                               \(device.bsdName) was not changed.
                               """))
            return
        }

        let box = OperationBox(session: session,
                               describeSuccess: describeSuccess,
                               describeFailure: describeFailure) { outcome in
            switch outcome {
            case .succeeded(let message):
                log.notice("""
                           \(verb, privacy: .public) succeeded on \
                           \(device.bsdName.rawValue, privacy: .public): \
                           \(message, privacy: .public)
                           """)
            case .failed(let message):
                log.error("""
                          \(verb, privacy: .public) failed on \
                          \(device.bsdName.rawValue, privacy: .public): \
                          \(message, privacy: .public)
                          """)
            }
            completion(outcome)
        }

        // The session must outlive this scope for the callback to arrive, and the
        // callback is a C function pointer that cannot capture — so the box is retained
        // here and released by the callback, exactly as `DeviceClaim` does.
        //
        // The timeout below does NOT release it. That is deliberate: releasing from
        // whichever path ran first would mean deciding, from the timeout, whether a
        // callback is still coming — and getting that wrong is a use-after-free, which
        // cost the exclusivity probe a crash mid-measurement. If DiskArbitration never
        // calls back at all, this leaks one small object; a bounded leak on a path that
        // should not occur is the right trade against corrupting memory on one that does.
        DASessionSetDispatchQueue(session, DispatchQueue.main)
        let context = Unmanaged.passRetained(box).toOpaque()

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeout) {
            box.settle(.failed("""
                               \(device.bsdName) did not respond to the \(verb) request \
                               within \(Int(Self.timeout)) seconds. The drive may be busy; \
                               try again, or use Disk Utility.
                               """))
        }

        operation(disk, operationCallback, context)
    }
}

// MARK: - Callback plumbing

/// Carries a single operation's completion across the C callback boundary.
///
/// Two paths can finish an operation — the DiskArbitration callback and the timeout — and
/// exactly one of them may deliver a result. ``settle(_:)`` enforces that: settling twice
/// would report two outcomes for one button press.
///
/// `@unchecked Sendable` without a lock, unusually: every path into this type is on the
/// main queue. The session's callbacks are scheduled there
/// (`DASessionSetDispatchQueue(session, .main)`) and the timeout is a
/// `DispatchQueue.main.asyncAfter`. A lock would suggest a concurrency that does not
/// exist here — and would not help, since the completion it calls updates SwiftUI state
/// that has to be on the main actor anyway.
private nonisolated final class OperationBox: @unchecked Sendable {

    private let session: DASession
    private let describeSuccess: () -> String
    private let describeFailure: (String) -> String
    private let completion: (VolumeMountOutcome) -> Void
    private var settled = false

    init(session: DASession,
         describeSuccess: @escaping () -> String,
         describeFailure: @escaping (String) -> String,
         completion: @escaping (VolumeMountOutcome) -> Void) {
        self.session = session
        self.describeSuccess = describeSuccess
        self.describeFailure = describeFailure
        self.completion = completion
    }

    /// Deliver `outcome`, unless the operation has already been settled by the other
    /// path. Called only on the main queue.
    func settle(_ outcome: VolumeMountOutcome) {
        guard !settled else { return }
        settled = true
        DASessionSetDispatchQueue(session, nil)
        completion(outcome)
    }

    /// A `nil` dissenter is DiskArbitration's way of saying the operation succeeded.
    func settle(dissenter: DADissenter?) {
        guard let dissenter else {
            settle(.succeeded(describeSuccess()))
            return
        }
        settle(.failed(describeFailure(DAStatus.explain(dissenter))))
    }
}

/// Shared by mount and unmount — the two callback types have identical signatures.
private nonisolated let operationCallback: DADiskUnmountCallback = { _, dissenter, context in
    guard let context else { return }
    let box = Unmanaged<OperationBox>.fromOpaque(context).takeRetainedValue()
    box.settle(dissenter: dissenter)
}

// MARK: - Making a dissenter readable

/// Turns a DiskArbitration refusal into something worth showing a user (NFR-USE-5).
private nonisolated enum DAStatus {

    /// Prefer the dissenter's own status string — it is the most specific thing
    /// available, and for a busy volume it often names the responsible process. Fall back
    /// to the status code, which is still far better than "an error occurred".
    static func explain(_ dissenter: DADissenter) -> String {
        if let reason = DADissenterGetStatusString(dissenter) as String?, !reason.isEmpty {
            return reason.hasSuffix(".") ? reason : reason + "."
        }
        return describe(DADissenterGetStatus(dissenter))
    }

    private static func describe(_ status: DAReturn) -> String {
        switch status {
        case DAReturn(kDAReturnBusy):
            return "the disk is in use."
        case DAReturn(kDAReturnExclusiveAccess):
            return "another process holds exclusive access to the disk."
        case DAReturn(kDAReturnNotMounted):
            return "it is not mounted."
        case DAReturn(kDAReturnNotPermitted), DAReturn(kDAReturnNotPrivileged):
            return "macOS did not permit the operation."
        case DAReturn(kDAReturnNotReady):
            return "the disk is not ready."
        case DAReturn(kDAReturnNotFound):
            return "the disk could not be found."
        case DAReturn(kDAReturnUnsupported):
            return "the operation is not supported on this disk."
        case DAReturn(kDAReturnNoResources):
            return "the system is out of resources for the operation."
        case DAReturn(kDAReturnBadArgument):
            return "the request was rejected as invalid."
        default:
            let hex = String(UInt32(bitPattern: Int32(status)), radix: 16)
            return "DiskArbitration refused it (status 0x\(hex))."
        }
    }
}
