//
//  DeviceClaim.swift
//  com.arc3solutions.USBDriveTester.Helper (privileged)
//
//  Step 6 (AI-4): the privileged half of the mount guard — verify nothing is mounted,
//  claim the whole disk through DiskArbitration, and open the raw node exclusively
//  (FR-SAFE-1/2/3, NFR-REL-3, NFR-REL-5).
//
//  Everything here is the *doing*. The *deciding* is in `Core/DeviceAccessPrecondition.swift`,
//  which is pure and exhaustively unit-tested; this file gathers three facts — mount
//  state, claim outcome, open errno — and hands them over. Splitting it that way is what
//  keeps the hardware-dependent part of Step 6's gate down to two shell scripts instead
//  of the whole classification table.
//
//  ## The sequence, and why it is in this order
//
//    1. **Re-check the device's identity.** The caller's BSD name is untrusted input
//       even from a Team-ID-authenticated peer (BUILD-PLAN Step 3.5, NFR-REL-7). Without
//       this, any client that passes the code-signature check could name `disk0`.
//    2. **Check mounted volumes** — refuse with cause (a) if any. This is the only check
//       that separates FR-SAFE-4's two causes, which are otherwise the same `EBUSY`.
//    3. **Claim, with a timeout** — a timeout *is* cause (b).
//    4. **Open `O_RDWR | O_EXLOCK | O_NONBLOCK`** — `EBUSY` is cause (b) too.
//
//  What the sequence never does is unmount anything (FR-SAFE-6). Unmounting is only ever
//  the result of the user pressing the control in the app; starting a test does not
//  change mount state as a side effect. BUILD-PLAN Step 6.2 was amended on 2026-07-30 to
//  match, because the original wording conflicted with FR-SAFE-4(a).
//
//  ## Measured facts this file is built on (2026-07-30, `scripts/exclusivity-probe.sh`)
//
//    * **The mount guard is kernel-enforced.** `open(rdiskN, O_RDWR)` fails `EBUSY`
//      while any volume is mounted, so step 2 is backed by the OS and not only by
//      policy. It is still checked explicitly, because the errno alone cannot say why.
//    * **A plain `O_RDWR` open excludes nobody** — two independent opens of an unmounted
//      raw disk both succeeded. `O_EXLOCK` is the mechanism; `O_NONBLOCK` is what makes a
//      contended open return rather than block.
//    * **A contended `DADiskClaim` is never dissented — it stays pending forever.** A
//      blocking claim would wedge the daemon, so the claim times out, and the timeout is
//      the positive signal for cause (b).
//    * **macOS silently remounts an unmounted volume the moment a claim is released.**
//      The claim is mandatory for the run's whole duration, not defensive.
//    * **Release is asynchronous** — an open immediately after `DADiskUnclaim` can still
//      see `EBUSY`, so nothing here assumes the device is instantly reusable.
//

import Foundation
import DiskArbitration
import IOKit
import os

private let log = Logger(subsystem: HelperIdentity.loggingSubsystem, category: "safety")

// MARK: - Registry keys

/// IOKit registry property names.
///
/// Spelled out because the constants for them (`kIOMediaClass`, `kIOMediaWholeKey`,
/// `kIOBSDNameKey`, the `kIOPropertyProtocolCharacteristicsKey` family) are C `#define`s
/// that are **not** bridged into Swift.
///
/// - Note: deliberately duplicated from the app's `IOKitDeviceEnumerator`. They cannot
///   be shared — that file is in the app target, this one is in the helper — and they
///   *should* not be, because this copy exists precisely so the helper does not depend on
///   the app having filtered correctly. A shared filter would mean one bug excusing
///   itself on both sides of the trust boundary.
private enum RegistryKey {
    static let blockStorageDriverClass = "IOBlockStorageDriver"
    static let whole                   = "Whole"
    static let size                    = "Size"
    static let preferredBlockSize      = "Preferred Block Size"
    static let bsdName                 = "BSD Name"

    static let protocolCharacteristics = "Protocol Characteristics"
    static let physicalInterconnect    = "Physical Interconnect"
    static let physicalInterconnectUSB = "USB"

    /// Negotiated USB connection speed, several levels above the media in the IOService plane.
    ///
    /// The enum behind this value is **not declared in any SDK header** — see
    /// `Core/USBLinkSpeed.swift` for the full account and the evidence that established it.
    /// `scripts/usb-speed-check.sh` re-checks the mapping against every attached device.
    static let deviceSpeed = "Device Speed"
}

// MARK: - The helper's own view of the device

/// What the helper independently established about a device before touching it.
struct EligibleDevice {

    /// Every BSD name at or below the whole disk in the IOService plane. Needed because
    /// the mount table does not name the physical disk: an APFS volume is mounted from
    /// `/dev/disk7s1`, and only the registry connects `disk7` back to the physical
    /// `disk6`.
    let subtreeBSDNames: Set<String>

    /// Capacity as IOKit reports it. Provisional — Step 7's `DKIOCGETBLOCKCOUNT` on the
    /// opened descriptor is the final authority.
    let sizeBytes: UInt64

    /// Logical block size as IOKit reports it. Also provisional (see above).
    let logicalBlockSize: UInt32

    /// The negotiated USB link speed, or `nil` if the registry did not report one.
    ///
    /// Used by FR-TEST-9's throughput falsifier to derive a ceiling above which a read cannot
    /// have crossed the wire — 1.333 GB/s for `disk4`'s 10 Gb/s link, against the ~0.475 GB/s
    /// it actually delivers (both measured 2026-08-02). `nil` is not an error: the check falls
    /// back to a fixed ceiling and says so.
    let usbLinkSpeed: USBLinkSpeed?
}

/// The helper's independent re-check of *which* device it has been asked to open.
///
/// This exists because of what the trust boundary actually guarantees: the Team-ID
/// code-signing requirement establishes that the caller is our app, not that the caller
/// is behaving. A root daemon that opens whatever `/dev/rdiskN` it is told to open is one
/// bug in the GUI away from writing to the boot disk.
enum HelperDeviceRegistry {

    /// Resolve and vet a whole-disk name.
    ///
    /// Applies the same two filters as the app's discovery, for the same measured
    /// reasons: `Whole = true` alone is not sufficient, because synthesized APFS
    /// containers also report it and inherit the USB interconnect from the physical disk
    /// beneath them.
    static func eligibility(of device: WholeDiskName) -> Result<EligibleDevice, DeviceAccessRefusal> {

        func refuse(_ reason: String) -> Result<EligibleDevice, DeviceAccessRefusal> {
            .failure(.deviceNotEligible(bsdName: device.rawValue, reason: reason))
        }

        guard let matching = IOBSDNameMatching(kIOMainPortDefault, 0, device.rawValue) else {
            return refuse("its BSD name could not be matched in the IOKit registry.")
        }
        let media = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard media != 0 else {
            return refuse("no such device is present.")
        }
        defer { IOObjectRelease(media) }

        // Whole disks only. Addressing a slice would mean writing inside a partition
        // while believing the whole device was covered.
        guard boolean(media, RegistryKey.whole) == true else {
            return refuse("it is not a whole disk.")
        }

        // Filter 1 — a real disk with a driver behind it, not a synthesized container.
        // The *immediate* provider specifically: a synthesized APFS container has an
        // IOBlockStorageDriver further up as well, so a recursive search would readmit
        // exactly what this excludes.
        guard hasBlockStorageDriverProvider(media) else {
            return refuse("it is a synthesized volume, not a physical disk.")
        }

        // Filter 2 — behind a USB transport (NFR-COMPAT-4). This is what excludes the
        // internal disk, and also disk images, which report "Virtual Interface".
        let characteristics = ancestorDictionary(media, RegistryKey.protocolCharacteristics)
        let interconnect = characteristics?[RegistryKey.physicalInterconnect] as? String
        guard interconnect == RegistryKey.physicalInterconnectUSB else {
            return refuse("its physical interconnect is "
                        + "\(interconnect ?? "not reported") rather than USB.")
        }

        guard let sizeBytes = number(media, RegistryKey.size),
              let blockSize = number(media, RegistryKey.preferredBlockSize),
              let logicalBlockSize = UInt32(exactly: blockSize) else {
            return refuse("it does not report usable geometry.")
        }

        // The USB link speed lives on the IOUSBHostDevice several levels up, like the protocol
        // characteristics above — a disk's IOMedia entry does not carry it, which is why
        // `ioreg -n disk4` cannot answer this and `tools/usb-speed-probe` exists.
        let linkSpeed = ancestorNumber(media, RegistryKey.deviceSpeed)
            .map { USBLinkSpeed.from(deviceSpeedCode: Int($0)) }

        return .success(EligibleDevice(
            subtreeBSDNames: bsdNamesInSubtree(of: media, wholeDiskName: device.rawValue),
            sizeBytes: sizeBytes,
            logicalBlockSize: logicalBlockSize,
            usbLinkSpeed: linkSpeed))
    }

    // MARK: Registry helpers

    private static func hasBlockStorageDriverProvider(_ media: io_object_t) -> Bool {
        var parent: io_object_t = 0
        guard IORegistryEntryGetParentEntry(media, kIOServicePlane, &parent) == KERN_SUCCESS,
              parent != 0 else { return false }
        defer { IOObjectRelease(parent) }
        return IOObjectConformsTo(parent, RegistryKey.blockStorageDriverClass) != 0
    }

    /// `Protocol Characteristics` lives on the `IOBlockStorageDevice` several levels up,
    /// not on the media itself — hence an upward recursive search.
    private static func ancestorDictionary(_ entry: io_object_t,
                                           _ key: String) -> [String: Any]? {
        let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        return IORegistryEntrySearchCFProperty(entry, kIOServicePlane, key as CFString,
                                               kCFAllocatorDefault, options) as? [String: Any]
    }

    /// The same upward search, for a numeric property.
    ///
    /// Needed for `Device Speed`, which lives on the `IOUSBHostDevice` — past the
    /// block-storage driver and the SCSI peripheral. ``number(_:_:)`` reads the entry itself
    /// and would find nothing.
    private static func ancestorNumber(_ entry: io_object_t, _ key: String) -> UInt64? {
        let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        return (IORegistryEntrySearchCFProperty(entry, kIOServicePlane, key as CFString,
                                                kCFAllocatorDefault, options) as? NSNumber)?
            .uint64Value
    }

    /// Every BSD name at or below this whole disk. Downward and recursive, because an
    /// APFS volume is several levels below its physical disk and is not named after it.
    private static func bsdNamesInSubtree(of media: io_object_t,
                                          wholeDiskName: String) -> Set<String> {
        var names: Set<String> = [wholeDiskName]

        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(media, kIOServicePlane,
                                            IOOptionBits(kIORegistryIterateRecursively),
                                            &iterator) == KERN_SUCCESS else { return names }
        defer { IOObjectRelease(iterator) }

        while case let child = IOIteratorNext(iterator), child != 0 {
            defer { IOObjectRelease(child) }
            if let name = string(child, RegistryKey.bsdName) {
                names.insert(name)
            }
        }
        return names
    }

    private static func string(_ entry: io_object_t, _ key: String) -> String? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }

    private static func number(_ entry: io_object_t, _ key: String) -> UInt64? {
        (IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber)?.uint64Value
    }

    private static func boolean(_ entry: io_object_t, _ key: String) -> Bool? {
        (IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber)?.boolValue
    }
}

// MARK: - Mount state, helper-side and authoritative

/// Reads the system mount table (FR-SAFE-1/2).
///
/// Deliberately the helper's own read, never the caller's assertion. The app has an
/// equivalent in `Discovery/MountedVolumes.swift` and it is used for the device list's
/// advisory label; *this* one is what may permit a run.
enum HelperMountTable {

    /// The mount state of the device whose registry subtree covers `bsdNames`.
    ///
    /// `getfsstat` rather than `getmntinfo`, whose static buffer is shared process-wide.
    /// `MNT_NOWAIT` returns cached information rather than asking each filesystem to
    /// refresh its statistics — a stalled network mount must not be able to hang the
    /// guard.
    static func mountState(ofSubtree bsdNames: Set<String>) -> MountState {
        let count = getfsstat(nil, 0, MNT_NOWAIT)
        guard count > 0 else { return .unmounted }

        var stats = Array(repeating: statfs(), count: Int(count))
        let written = getfsstat(&stats,
                                Int32(MemoryLayout<statfs>.stride * Int(count)),
                                MNT_NOWAIT)
        guard written > 0 else { return .unmounted }

        var seen = Set<String>()
        var names: [String] = []

        for entry in stats.prefix(Int(written)) {
            let node = string(from: entry.f_mntfromname)
            guard node.hasPrefix("/dev/") else { continue }
            let nodeName = String(node.dropFirst("/dev/".count))
            guard bsdNames.contains(nodeName) else { continue }

            let mountPoint = string(from: entry.f_mntonname)
            let volumeName = (mountPoint as NSString).lastPathComponent
            let display = volumeName.isEmpty || volumeName == "/" ? mountPoint : volumeName
            if seen.insert(display).inserted {
                names.append(display)
            }
        }

        return MountState(mountedVolumeNames: names)
    }

    /// Convert one of `statfs`' fixed-size `CChar` tuples into a `String`.
    private static func string<T>(from tuple: T) -> String {
        withUnsafePointer(to: tuple) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) {
                String(cString: $0)
            }
        }
    }
}

// MARK: - The claim callback

/// Carries the claim's outcome from the DiskArbitration callback back to the waiter.
///
/// `@unchecked Sendable` with an explicit lock: the callback runs on the session's queue
/// while the acquiring thread waits on the semaphore.
private final class ClaimOutcomeBox: @unchecked Sendable {

    let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var stored: DiskClaimOutcome?
    private var abandoned = false

    /// Held so a late grant can be released, and so DiskArbitration still has a live
    /// session to deliver the callback on. Dropping the session on timeout would strand
    /// the claim instead of releasing it.
    private let session: DASession
    private let disk: DADisk

    init(session: DASession, disk: DADisk) {
        self.session = session
        self.disk = disk
    }

    var outcome: DiskClaimOutcome? { lock.withLock { stored } }

    func settle(_ outcome: DiskClaimOutcome) {
        lock.withLock { stored = outcome }
        semaphore.signal()
    }

    /// Called by the waiter once it has given up. Any grant arriving after this must be
    /// released rather than silently kept.
    func abandon() {
        lock.withLock { abandoned = true }
    }

    /// The callback's view: report whether the waiter has already walked away.
    func claimArrived(granted: Bool) {
        let wasAbandoned = lock.withLock { abandoned }
        guard wasAbandoned else { return }

        if granted {
            // THE BUG THIS EXISTS TO FIX, observed in diskarbitrationd's own log
            // 2026-08-01:
            //
            //   08:44:02.059  unable to unclaim disk /dev/disk4 (status 0xF8DA0003)
            //   08:44:02.102  claimed disk /dev/disk4, success
            //
            // The old timeout path called DADiskUnclaim immediately. The claim was still
            // *pending*, so the unclaim failed with kDAReturnBadArgument — and the grant
            // then landed 43 ms later into a session nobody was watching. Unclaiming a
            // pending claim does not cancel it; the only correct moment to release is
            // when the grant actually arrives.
            DADiskUnclaim(disk)
            let name = DADiskGetBSDName(disk).map { String(cString: $0) } ?? "the disk"
            log.notice("""
                       late DiskArbitration grant for \(name, privacy: .public) arrived \
                       after the claim had timed out; released it immediately so it cannot \
                       strand the disk
                       """)
        }
        DASessionSetDispatchQueue(session, nil)
    }
}

/// Balances the `passRetained` in `DeviceClaim.claim(_:timeoutAfter:)` — see the note
/// there about why the context is retained rather than passed unretained.
private let claimCallback: DADiskClaimCallback = { _, dissenter, context in
    guard let context else { return }
    let box = Unmanaged<ClaimOutcomeBox>.fromOpaque(context).takeRetainedValue()

    if let dissenter {
        box.settle(.dissented(status: DADissenterGetStatus(dissenter),
                              reason: DADissenterGetStatusString(dissenter) as String?))
        box.claimArrived(granted: false)
    } else {
        box.settle(.granted)
        box.claimArrived(granted: true)
    }
}

// MARK: - Full Disk Access probe (NFR-INST-4)

extension DeviceClaim {

    /// Does this helper hold Full Disk Access?
    ///
    /// ## Why this does not touch the device — the constraint that forced it
    ///
    /// Three probes were tried against the device itself. All were wrong, and the last one
    /// was actively harmful. Measured on hardware, Full Disk Access **not** granted:
    ///
    /// | Flags on `/dev/rdiskN` | Result |
    /// |---|---|
    /// | `O_RDONLY` | succeeds — reports `granted` when nothing was granted |
    /// | `O_RDWR \| O_NONBLOCK` | succeeds — same false answer |
    /// | `O_RDWR \| O_EXLOCK \| O_NONBLOCK` | `EPERM` — correct, **and unusable here** |
    ///
    /// So TCC gates neither reading nor writing: it gates **taking the exclusive lock**,
    /// the operation that amounts to claiming the whole device. Only the third probe is
    /// faithful — and the third probe cannot be used in a polled readiness check, because
    /// *releasing* an exclusive lock makes DiskArbitration re-probe the media and mount it
    /// again. Measured 2026-08-01:
    ///
    /// ```
    /// 14:47:00.184  unmounted disk /dev/disk4s2, success
    /// 14:47:00.198  readiness check … full-disk-access=granted   <- probe opened and closed
    /// 14:47:00.202  probed disk /dev/disk4s1 …                   <- 4 ms later
    /// 14:47:00.425  mounted disk /dev/disk4s2, success           <- the user's unmount undone
    /// ```
    ///
    /// That is the same auto-remount measured for a released `DADiskClaim` on 2026-07-30.
    /// A readiness check that silently remounts the drive defeats FR-SAFE-5 outright: the
    /// user presses Unmount All and the volume returns a heartbeat later.
    ///
    /// ## So this checks the permission, not the device
    ///
    /// It reads the protected TCC database, which is gated by exactly the grant the user
    /// makes when they add this app to Full Disk Access
    /// (`kTCCServiceSystemPolicyAllFiles`). No device is opened, nothing is locked, and
    /// nothing can be remounted as a consequence.
    ///
    /// This **is** a proxy, and proxies have already been wrong twice in this file, so the
    /// limits are stated rather than glossed: it establishes whether the app holds Full
    /// Disk Access, not whether this particular device can be opened. The two could differ
    /// — a device could be refused for some reason unrelated to the grant.
    /// ``DeviceClaim/acquire(_:)`` remains the only authority on whether a run can start,
    /// and it reports the same condition precisely from the real open
    /// (``DeviceAccessRefusal/accessNotPermitted(bsdName:)``). This is an early warning,
    /// and it is allowed to be silent when it should not be; it is not allowed to cause a
    /// remount.
    static func fullDiskAccessState() -> FullDiskAccessState {
        // Opened read-only and closed immediately. The file is never read or parsed —
        // whether it *opens* is the entire signal (NFR-SEC-6: nothing about its contents
        // is of interest, and none is logged).
        let fd = open(tccDatabasePath, O_RDONLY)
        guard fd >= 0 else {
            return FullDiskAccessState.from(openErrno: errno)
        }
        close(fd)
        return .granted
    }

    /// The system TCC database. Readable only by a process holding Full Disk Access.
    private static let tccDatabasePath =
        "/Library/Application Support/com.apple.TCC/TCC.db"
}

// MARK: - Acquiring

/// Takes and releases exclusive whole-disk access.
enum DeviceClaim {

    /// How long to wait for the claim before concluding another process holds the disk.
    ///
    /// A timeout is required, not a nicety: a contended claim is never dissented, so
    /// without this the daemon would wait forever for a callback that never comes.
    static let claimTimeout: TimeInterval = 5

    /// Take exclusive whole-disk access, or explain precisely why it cannot be taken.
    ///
    /// - Returns: an ``AcquiredDevice`` — the only value that unlocks Steps 7/8's write
    ///   path — or the refusal to report to the user (FR-SAFE-4, NFR-USE-5).
    static func acquire(_ device: WholeDiskName) -> Result<AcquiredDevice, DeviceAccessRefusal> {

        // 1. Identity. Untrusted input, re-checked against our own view of the registry.
        let eligible: EligibleDevice
        switch HelperDeviceRegistry.eligibility(of: device) {
        case .success(let value):
            eligible = value
        case .failure(let refusal):
            log.error("acquire REFUSED for \(device.rawValue, privacy: .public): \(refusal.description, privacy: .public)")
            return .failure(refusal)
        }

        // 2. Mounted volumes — FR-SAFE-4(a). Nothing is unmounted here (FR-SAFE-6).
        let mountState = HelperMountTable.mountState(ofSubtree: eligible.subtreeBSDNames)
        if mountState.isMounted {
            let decision = DeviceAccessPrecondition.evaluate(device: device,
                                                             mountState: mountState,
                                                             claim: nil,
                                                             exclusiveOpen: nil)
            return refuseAndLog(decision, device: device)
        }

        // 3. The DiskArbitration claim. Mandatory: the moment a claim is released macOS
        //    silently remounts the volume, so nothing else keeps the disk unmounted for
        //    the hours a run can take.
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, device.rawValue) else {
            let decision = DeviceAccessPrecondition.evaluate(
                device: device,
                mountState: mountState,
                claim: .sessionUnavailable(
                    detail: "a DiskArbitration session for \(device.rawValue) could not be created"),
                exclusiveOpen: nil)
            return refuseAndLog(decision, device: device)
        }

        // Callbacks go to a dedicated serial queue, never to the main queue: the
        // acquiring thread blocks on a semaphore, and a callback scheduled on the queue
        // that is blocked would never arrive. The probe lost a callback to exactly that.
        let queue = DispatchQueue(label: "\(HelperIdentity.machServiceName).diskarbitration")
        DASessionSetDispatchQueue(session, queue)

        let claimOutcome = claim(session, disk, timeoutAfter: claimTimeout)
        guard claimOutcome == .granted else {
            // On a timeout the session is deliberately NOT torn down here: the claim is
            // still pending, and `ClaimOutcomeBox.claimArrived(granted:)` needs a live
            // session to receive the grant on so it can release it. Tearing down now is
            // what stranded the claim before (see that method).
            if case .timedOut = claimOutcome {
                log.notice("""
                           claim on \(device.rawValue, privacy: .public) timed out; leaving \
                           the session alive so a late grant can be released rather than \
                           stranded
                           """)
            } else {
                DASessionSetDispatchQueue(session, nil)
            }

            let decision = DeviceAccessPrecondition.evaluate(device: device,
                                                             mountState: mountState,
                                                             claim: claimOutcome,
                                                             exclusiveOpen: nil)
            return refuseAndLog(decision, device: device)
        }

        // 4. The exclusive open. This is what actually excludes another writer — a plain
        //    O_RDWR open does not (measured). Step 7 adds F_NOCACHE and the geometry
        //    ioctls to this same descriptor.
        let fd = open(device.rawDevicePath, O_RDWR | O_EXLOCK | O_NONBLOCK)
        let openOutcome: ExclusiveOpenOutcome = fd >= 0 ? .opened : .failed(errnoCode: errno)

        let decision = DeviceAccessPrecondition.evaluate(device: device,
                                                         mountState: mountState,
                                                         claim: claimOutcome,
                                                         exclusiveOpen: openOutcome)
        guard decision == .acquire else {
            // The claim was granted but we are not proceeding. Releasing it here is not
            // optional: a disk left claimed by a refusal stays unmountable until this
            // daemon exits.
            if fd >= 0 { close(fd) }
            DADiskUnclaim(disk)
            DASessionSetDispatchQueue(session, nil)
            return refuseAndLog(decision, device: device)
        }

        log.notice("""
                   acquired \(device.rawValue, privacy: .public): claim held, \
                   \(device.rawDevicePath, privacy: .public) open exclusively (fd \(fd, privacy: .public)); \
                   IOKit reports \(eligible.sizeBytes, privacy: .public) bytes in \
                   \(eligible.logicalBlockSize, privacy: .public)-byte blocks
                   """)

        // 5. Step 7: configure the descriptor and establish the real geometry.
        //
        //    Done here, at acquire, rather than on first use, so `AcquiredDevice` carries
        //    authoritative geometry from birth and there is no window in which some caller
        //    could address the device using IOKit's provisional numbers.
        let uncachedIO = RawDeviceGeometry.configureUncachedIO(fileDescriptor: fd,
                                                                devicePath: device.rawDevicePath)
        let cacheBypass = CacheBypassCheck.evaluate(uncachedIO)

        let reconciliation: GeometryReconciliation
        let rawGeometry: RawDeviceGeometry.RawGeometry
        switch RawDeviceGeometry.establishGeometry(fileDescriptor: fd,
                                                    ioKit: eligible,
                                                    devicePath: device.rawDevicePath) {
        case .success(let established):
            reconciliation = established.reconciliation
            rawGeometry = established.raw

        case .failure(let refusal):
            // Fails closed, and everything acquired so far is released. A run that does not
            // know the size of the device cannot address it safely, so this is a refusal
            // rather than a fallback to IOKit's provisional numbers — the whole point of
            // preferring the ioctls is that they are what the kernel enforces.
            close(fd)
            DADiskUnclaim(disk)
            DASessionSetDispatchQueue(session, nil)
            let decision = DeviceAccessDecision.refuse(
                .checkIncomplete(bsdName: device.rawValue, detail: refusal.description))
            return refuseAndLog(decision, device: device)
        }

        log.notice("""
                   \(device.rawValue, privacy: .public) configured for uncached I/O: \
                   F_NOCACHE rc=\(uncachedIO.noCacheResult, privacy: .public), \
                   F_GLOBAL_NOCACHE rc=\(uncachedIO.globalNoCacheResult, privacy: .public), \
                   node is a \(String(describing: uncachedIO.nodeKind), privacy: .public); \
                   cache-bypass check says \(String(describing: cacheBypass), privacy: .public); \
                   link \(eligible.usbLinkSpeed?.description ?? "speed not reported", privacy: .public)
                   """)

        return .success(AcquiredDevice(device: device,
                                       session: session,
                                       disk: disk,
                                       sessionQueue: queue,
                                       fileDescriptor: fd,
                                       geometry: eligible,
                                       reconciliation: reconciliation,
                                       rawGeometry: rawGeometry,
                                       uncachedIO: uncachedIO,
                                       cacheBypass: cacheBypass))
    }

    /// Claim `disk`, waiting at most `timeout` seconds.
    ///
    /// The callback context is **retained**, and the callback releases it. Passing it
    /// unretained cost the probe a use-after-free: on timeout the local deallocated and a
    /// late callback dereferenced freed memory.
    ///
    /// On a timeout the box is *abandoned* rather than discarded — it keeps the session
    /// and disk alive precisely so a late grant can be released when it arrives. That is
    /// the fix for the stranded claim observed on 2026-08-01; see
    /// ``ClaimOutcomeBox/claimArrived(granted:)``. If no callback ever comes, this leaks
    /// one small object, which remains the right trade against a use-after-free.
    private static func claim(_ session: DASession,
                              _ disk: DADisk,
                              timeoutAfter timeout: TimeInterval) -> DiskClaimOutcome {
        let box = ClaimOutcomeBox(session: session, disk: disk)
        DADiskClaim(disk,
                    DADiskClaimOptions(kDADiskClaimOptionDefault),
                    nil, nil,
                    claimCallback,
                    Unmanaged.passRetained(box).toOpaque())

        guard box.semaphore.wait(timeout: .now() + timeout) == .success,
              let outcome = box.outcome else {
            box.abandon()
            return .timedOut(afterSeconds: Int(timeout))
        }
        return outcome
    }

    private static func refuseAndLog(_ decision: DeviceAccessDecision,
                                     device: WholeDiskName) -> Result<AcquiredDevice, DeviceAccessRefusal> {
        guard let refusal = decision.refusal else {
            // Unreachable: every caller here has already established the decision is a
            // refusal. A root daemon fails closed rather than letting an unexpected
            // state fall through as success.
            let fallback = DeviceAccessRefusal.checkIncomplete(
                bsdName: device.rawValue,
                detail: "the acquire sequence reached an unexpected state")
            log.error("acquire REFUSED for \(device.rawValue, privacy: .public): \(fallback.description, privacy: .public)")
            return .failure(fallback)
        }
        log.error("""
                  acquire REFUSED for \(device.rawValue, privacy: .public) \
                  [cause \(refusal.causeCode, privacy: .public)]: \
                  \(refusal.description, privacy: .public)
                  """)
        return .failure(refusal)
    }
}

// MARK: - What is held

/// Exclusive whole-disk access, held.
///
/// **Constructible only by a successful ``DeviceClaim/acquire(_:)``** — the initialiser is
/// `fileprivate`. That is the compile-time half of NFR-REL-3: Steps 7/8's write path takes
/// one of these as a parameter, so there is no call site without the guard, because there
/// is no way to reach the write path without a value that proves access was granted.
///
/// The runtime half is `WritePrecondition.check(_:writingTo:)` in Core, which catches
/// what the type system cannot see — a grant whose descriptor has since been closed, or a
/// write aimed at a different device than the one held.
final class AcquiredDevice: @unchecked Sendable {

    /// The device access is held on.
    let device: WholeDiskName

    /// Geometry as IOKit reported it. **Provisional** — kept for comparison and for the log.
    /// ``deviceGeometry`` is the authority.
    let geometry: EligibleDevice

    /// The ioctl geometry and how it compared with IOKit's (BUILD-PLAN 7.3).
    let reconciliation: GeometryReconciliation

    /// Everything the geometry ioctls returned, including the diagnostic values.
    let rawGeometry: RawDeviceGeometry.RawGeometry

    /// How the descriptor was configured for uncached I/O, and what kind of node it is.
    let uncachedIO: UncachedIOConfiguration

    /// The run-start cache-bypass verdict (FR-TEST-9), established at acquire.
    ///
    /// Step 8 seeds a `CacheBypassAssessment` from this and the link speed, then feeds the
    /// run's throughput in — which can only ever downgrade it. From Step 11 that assessment
    /// lives on ``runSession``, so the downgrade survives a call boundary.
    let cacheBypass: CacheBypassState

    /// **The run's session** — the accumulators that span every bounded call the run is made of:
    /// metrics, the failure log, and the FR-TEST-9 assessment (Step 11 increment 3, CONSTRAINTS
    /// section 2).
    ///
    /// It is a property of the claim, not of a call, and that is the whole design. `acquireDevice`
    /// opens the session by constructing this object; `releaseDevice` closes it by destroying it.
    /// So the accumulators cannot outlive the claim, a fresh claim cannot inherit a previous run's
    /// figures, and neither property needs anybody to remember to clear anything.
    ///
    /// Created here rather than lazily on the first call so that the progress denominator is the
    /// **authoritative ioctl geometry** established two lines above, stated once. A session that
    /// learned its device's size from whichever call happened to be first would be a second place
    /// that fact comes from.
    let runSession: RunSession

    /// **The authoritative geometry**: ioctl-derived, reconciled, and validated. Everything
    /// that addresses the device uses this, never ``geometry``.
    var deviceGeometry: DeviceGeometry { reconciliation.authoritative }

    /// The negotiated USB link speed, or `nil` if the registry did not report one.
    var usbLinkSpeed: USBLinkSpeed? { geometry.usbLinkSpeed }

    private let session: DASession
    private let disk: DADisk
    private let sessionQueue: DispatchQueue
    private var fd: Int32
    private let lock = NSLock()
    private var released = false

    fileprivate init(device: WholeDiskName,
                     session: DASession,
                     disk: DADisk,
                     sessionQueue: DispatchQueue,
                     fileDescriptor: Int32,
                     geometry: EligibleDevice,
                     reconciliation: GeometryReconciliation,
                     rawGeometry: RawDeviceGeometry.RawGeometry,
                     uncachedIO: UncachedIOConfiguration,
                     cacheBypass: CacheBypassState) {
        self.device = device
        self.session = session
        self.disk = disk
        self.sessionQueue = sessionQueue
        self.fd = fileDescriptor
        self.geometry = geometry
        self.reconciliation = reconciliation
        self.rawGeometry = rawGeometry
        self.uncachedIO = uncachedIO
        self.cacheBypass = cacheBypass

        // The run's session opens here, with the claim. Both of its inputs are facts this acquire
        // has just established: the device's capacity from the geometry ioctls (never IOKit's
        // provisional numbers), and the FR-TEST-9 verdict from the descriptor as it was opened.
        let authoritative = reconciliation.authoritative
        self.runSession = RunSession(
            deviceBytesTotal: authoritative.blockCount * UInt64(authoritative.logicalBlockSize),
            cacheBypass: CacheBypassAssessment(uncachedIO, linkSpeed: geometry.usbLinkSpeed))
    }

    /// A `RawBlockDevice` over the held descriptor, using the authoritative geometry.
    ///
    /// Built on demand rather than stored, so it cannot outlive the descriptor it borrows.
    /// Returns `nil` once ``release()`` has run.
    func blockDevice() throws -> FileDescriptorBlockDevice? {
        let descriptor = fileDescriptor
        guard descriptor >= 0 else { return nil }
        return try FileDescriptorBlockDevice(fileDescriptor: descriptor,
                                             geometry: deviceGeometry)
    }

    /// The open raw descriptor, or `-1` once released. Step 7 does its `pread`/`pwrite`
    /// through this.
    var fileDescriptor: Int32 { lock.withLock { fd } }

    /// What is held, as the pure guard understands it (NFR-REL-3).
    ///
    /// Recomputed rather than stored, so that after ``release()`` the guard sees a grant
    /// that is no longer complete and trips — which is the case a stored value would
    /// silently get wrong.
    var grant: DeviceAccessGrant {
        lock.withLock {
            DeviceAccessGrant(deviceName: device.rawValue,
                              claimHeld: !released,
                              exclusiveOpenHeld: !released && fd >= 0)
        }
    }

    /// Human-readable description of what is being held, for `prepareForShutdown` and
    /// the logs.
    var activityDescription: String {
        "exclusive whole-disk access to \(device.rawValue) is held "
      + "(DiskArbitration claim + \(device.rawDevicePath) open with O_EXLOCK)"
    }

    /// Release everything, in the order that leaves the least window: close the
    /// descriptor first, then unclaim, then tear the session down.
    ///
    /// Idempotent. Returns a description of what was released, for the caller to log or
    /// report.
    ///
    /// - Important: the disk is **not** necessarily usable the instant this returns.
    ///   Measured 2026-07-30: an open immediately after `DADiskUnclaim` can still see
    ///   `EBUSY`. Nothing downstream may treat a successful release as "the device is
    ///   free now" (NFR-REL-5). Expect macOS to remount the volumes shortly afterwards —
    ///   also measured, and the reason the claim has to be held for the whole run.
    @discardableResult
    func release() -> String {
        lock.withLock {
            guard !released else {
                return "Exclusive access to \(device.rawValue) had already been released."
            }
            released = true

            if fd >= 0 {
                close(fd)
                fd = -1
            }
            DADiskUnclaim(disk)
            DASessionSetDispatchQueue(session, nil)

            log.notice("""
                       released \(self.device.rawValue, privacy: .public): descriptor closed, \
                       DiskArbitration claim dropped. The system may remount its volumes; \
                       the node may briefly remain busy.
                       """)

            return "Released exclusive access to \(device.rawValue): the raw device was "
                 + "closed and the DiskArbitration claim dropped."
        }
    }
}
