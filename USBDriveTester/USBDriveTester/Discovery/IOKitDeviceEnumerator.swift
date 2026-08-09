//
//  IOKitDeviceEnumerator.swift
//  USBDriveTester (app target — unprivileged)
//
//  Enumerates connected USB mass-storage whole disks from the IOKit registry
//  (FR-DEV-1, FR-DEV-5/6) and reports connect/disconnect events (FR-DEV-7).
//
//  ## Unprivileged, on purpose
//
//  None of this needs root. Discovery is GUI-side work (BUILD-PLAN Step 5) and the
//  helper is not involved at all: it need not even be installed for the device list to
//  work. The geometry read here is provisional — Step 7's ioctls on the opened raw
//  device are the final authority (see `DiscoveredDevice`).
//
//  ## Two filters, and why the second one is not optional
//
//  A whole disk qualifies only if **both** hold:
//
//  1. Its provider is an `IOBlockStorageDriver` — i.e. it is a real disk with a driver
//     behind it, not a synthesized one.
//  2. Some ancestor reports `Physical Interconnect == "USB"` (NFR-COMPAT-4).
//
//  Filter 2 alone is the obvious reading of BUILD-PLAN Step 5 ("walk each media
//  object's parent chain to confirm it sits behind a USB transport") and it is not
//  sufficient. **Synthesized APFS containers also report `Whole = true`, and they
//  inherit the USB interconnect from the physical disk underneath them.** Measured on
//  the development machine on 2026-07-29:
//
//      disk6  IOMedia         parent=IOBlockStorageDriver      link=USB  bs=512   1000204886016
//      disk7  AppleAPFSMedia  parent=AppleAPFSContainerScheme  link=USB  bs=4096   999995129856
//      disk8  IOMedia         parent=IOBlockStorageDriver      link=USB  bs=512  22000969973248
//      disk9  AppleAPFSMedia  parent=AppleAPFSContainerScheme  link=USB  bs=4096  2000624971776
//
//  Without filter 1 every APFS-formatted USB drive is listed **twice** — once real,
//  once virtual — with different block sizes and different capacities, and the virtual
//  entry is the more plausible-looking of the two. Handing that to a raw block writer
//  is not a cosmetic defect. Filter 1 whitelists rather than blacklisting
//  `AppleAPFSMedia` specifically, so other virtual schemes are excluded too.
//
//  Note that disk images are excluded by filter 2, not filter 1: they *do* have an
//  `IOBlockStorageDriver`, but report `Physical Interconnect == "Virtual Interface"`.
//  That is correct per FR-DEV-1, and worth remembering in Step 7, whose gate suggests
//  attaching a disk image as a safe stand-in for a real device — such an image will
//  not appear in this list.
//

import Foundation
import IOKit
import os

// `nonisolated` because everything in this file is: the app target compiles with
// SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, which would otherwise make even this
// immutable logger main-actor-isolated and unreachable from the enumerator.
private nonisolated let log = Logger(subsystem: HelperIdentity.loggingSubsystem,
                                     category: "discovery")

/// Registry property names.
///
/// These are spelled out because the IOKit constants for them (`kIOMediaClass`,
/// `kIOMediaWholeKey`, `kIOMediaSizeKey`, `kIOMediaPreferredBlockSizeKey`,
/// `kIOBSDNameKey`, and the `kIOPropertyProtocolCharacteristicsKey` family) are C
/// `#define`s that are **not** bridged into Swift — referencing them does not compile.
/// Collected in one place so the literals appear exactly once each.
///
/// Sources: `IOKit/storage/IOMedia.h`, `IOKit/storage/IOStorageProtocolCharacteristics.h`,
/// `IOKit/storage/IOStorageDeviceCharacteristics.h`, `IOKit/IOBSD.h`.
private nonisolated enum RegistryKey {
    static let mediaClass                = "IOMedia"
    static let blockStorageDriverClass   = "IOBlockStorageDriver"
    static let whole                     = "Whole"
    static let size                      = "Size"
    static let preferredBlockSize        = "Preferred Block Size"
    static let bsdName                   = "BSD Name"

    static let protocolCharacteristics   = "Protocol Characteristics"
    static let physicalInterconnect      = "Physical Interconnect"
    static let physicalInterconnectUSB   = "USB"

    static let deviceCharacteristics     = "Device Characteristics"
    static let productName               = "Product Name"
    static let vendorName                = "Vendor Name"
    static let mediumType                = "Medium Type"

    /// Lives on the USB device node several levels *above* the media, alongside
    /// `Physical Interconnect` — so it is read with the same upward search, not a direct
    /// property read on the media. Verified on `disk4`, `disk6` and `disk8`, 2026-08-05.
    static let usbSerialNumber           = "USB Serial Number"
}

/// Where the device list comes from.
///
/// A protocol so `DeviceDiscovery` can be driven by a stub in tests. The IOKit
/// implementation below is the only part of Step 5 that requires hardware, which is
/// what keeps the rest of it unit-testable (NFR-MAINT-2).
nonisolated protocol DeviceSource: AnyObject {

    /// Every connected USB mass-storage whole disk, in presentation order (FR-DEV-2).
    func enumerateDevices() -> [DiscoveredDevice]

    /// Begin reporting connect/disconnect events. `onChange` is delivered on the main
    /// queue, coalesced (FR-DEV-7).
    func startObserving(onChange: @escaping () -> Void)

    /// Stop reporting events and release the notification port.
    func stopObserving()
}

/// The IOKit-backed device source.
nonisolated final class IOKitDeviceEnumerator: DeviceSource {

    private var notificationPort: IONotificationPortRef?
    private var matchedIterator: io_iterator_t = 0
    private var terminatedIterator: io_iterator_t = 0
    private var onChange: (() -> Void)?
    private var pendingChange: DispatchWorkItem?

    /// Mount and unmount are **not** IOKit media events, so they need their own source
    /// or the mounted-volume column goes stale — see VolumeChangeWatcher for the
    /// defect this fixes. Both sources funnel into the same coalescing window below,
    /// because both mean the same thing here: the list needs rebuilding.
    private let volumeWatcher = VolumeChangeWatcher()

    /// Hot-plug events arrive in bursts — attaching one drive publishes the whole disk
    /// and then, moments later, every partition and container beneath it. Rebuilding
    /// the list once per event would mean several rebuilds per plug. A short coalescing
    /// window collapses them into one, and stays far inside the "within a second or
    /// two" the Step 5 gate asks for.
    private static let coalescingInterval: DispatchTimeInterval = .milliseconds(200)

    deinit {
        stopObserving()
    }

    // MARK: - Enumeration

    func enumerateDevices() -> [DiscoveredDevice] {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault,
                                                  Self.wholeMediaMatchingDictionary(),
                                                  &iterator)
        guard result == KERN_SUCCESS else {
            log.error("IOServiceGetMatchingServices failed: \(result, privacy: .public)")
            return []
        }
        defer { IOObjectRelease(iterator) }

        // Read the mount table once per enumeration rather than once per device.
        let mountTable = MountTable.current()

        var devices: [DiscoveredDevice] = []
        while case let media = IOIteratorNext(iterator), media != 0 {
            defer { IOObjectRelease(media) }
            if let device = makeDevice(from: media, mountTable: mountTable) {
                devices.append(device)
            }
        }

        let sorted = DiscoveredDevice.sorted(devices)
        log.info("""
                 discovery found \(sorted.count, privacy: .public) USB whole disk(s): \
                 \(sorted.map(\.bsdName.rawValue).joined(separator: ", "), privacy: .public)
                 """)
        return sorted
    }

    /// A fresh matching dictionary for every call.
    ///
    /// `IOServiceGetMatchingServices` and `IOServiceAddMatchingNotification` both
    /// **consume** a reference to the dictionary handed to them, so one cannot be built
    /// once and reused — the second use would be over-released.
    private static func wholeMediaMatchingDictionary() -> CFMutableDictionary {
        let matching = IOServiceMatching(RegistryKey.mediaClass) as NSMutableDictionary
        matching[RegistryKey.whole] = true
        return matching as CFMutableDictionary
    }

    /// Turn one matching registry object into a device, or reject it.
    private func makeDevice(from media: io_object_t,
                            mountTable: [MountedVolume]) -> DiscoveredDevice? {

        guard let bsdName = Self.string(media, RegistryKey.bsdName) else { return nil }

        // Filter 1 — a real disk, not a synthesized container. See the file header.
        guard Self.hasBlockStorageDriverProvider(media) else {
            log.debug("""
                      skipping \(bsdName, privacy: .public): whole media with no \
                      IOBlockStorageDriver provider (synthesized container)
                      """)
            return nil
        }

        // Filter 2 — behind a USB transport (NFR-COMPAT-4).
        let protocolCharacteristics = Self.ancestorDictionary(media,
                                                              RegistryKey.protocolCharacteristics)
        let interconnect = protocolCharacteristics?[RegistryKey.physicalInterconnect] as? String
        guard interconnect == RegistryKey.physicalInterconnectUSB else {
            log.debug("""
                      skipping \(bsdName, privacy: .public): physical interconnect \
                      \(interconnect ?? "unknown", privacy: .public), not USB
                      """)
            return nil
        }

        guard let sizeBytes = Self.number(media, RegistryKey.size) else {
            log.error("skipping \(bsdName, privacy: .public): no Size property")
            return nil
        }
        guard let blockSize = Self.number(media, RegistryKey.preferredBlockSize),
              let logicalBlockSize = UInt32(exactly: blockSize) else {
            log.error("skipping \(bsdName, privacy: .public): no usable Preferred Block Size")
            return nil
        }

        var registryEntryID: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(media, &registryEntryID) == KERN_SUCCESS else {
            log.error("skipping \(bsdName, privacy: .public): no registry entry ID")
            return nil
        }

        let characteristics = Self.ancestorDictionary(media, RegistryKey.deviceCharacteristics)

        return DiscoveredDevice(
            registryEntryID: registryEntryID,
            bsdName: BSDDeviceName(bsdName),
            vendorName: characteristics?[RegistryKey.vendorName] as? String,
            productName: characteristics?[RegistryKey.productName] as? String,
            mediumType: characteristics?[RegistryKey.mediumType] as? String,
            sizeBytes: sizeBytes,
            logicalBlockSize: logicalBlockSize,
            mountedVolumeNames: MountTable.volumeNames(
                on: Self.bsdNamesInSubtree(of: media, wholeDiskName: bsdName),
                in: mountTable),
            // The same subtree, so the names and the nodes describe the same volumes in the same
            // order. Restoring a partial unmount needs the nodes; nothing else does.
            mountedVolumeBSDNames: MountTable.volumeBSDNames(
                on: Self.bsdNamesInSubtree(of: media, wholeDiskName: bsdName),
                in: mountTable),
            // Sanitised rather than taken as read: a bridge reporting sixteen zeros would
            // otherwise become an identifier that every drive behind that bridge shares.
            usbSerialNumber: USBSerialNumber.sanitised(
                Self.ancestorString(media, RegistryKey.usbSerialNumber)))
    }

    // MARK: - Registry helpers

    /// Whether this media object's **immediate provider** is an `IOBlockStorageDriver`.
    ///
    /// The immediate parent specifically, not an ancestor search: a synthesized APFS
    /// container has an `IOBlockStorageDriver` somewhere above it too (the one driving
    /// the physical disk it lives on), so a recursive search would readmit exactly what
    /// this filter exists to exclude.
    private static func hasBlockStorageDriverProvider(_ media: io_object_t) -> Bool {
        var parent: io_object_t = 0
        guard IORegistryEntryGetParentEntry(media, kIOServicePlane, &parent) == KERN_SUCCESS,
              parent != 0 else { return false }
        defer { IOObjectRelease(parent) }
        return IOObjectConformsTo(parent, RegistryKey.blockStorageDriverClass) != 0
    }

    /// Find a dictionary-valued property on this object or any of its ancestors.
    ///
    /// `Protocol Characteristics` and `Device Characteristics` live on the
    /// `IOBlockStorageDevice` several levels up the chain, not on the media itself —
    /// hence the upward recursive search rather than a direct property read.
    /// Find a string-valued property on this object or any of its ancestors.
    ///
    /// Same upward search as ``ancestorDictionary(_:_:)``, for keys that are plain strings rather
    /// than nested dictionaries — `USB Serial Number` is on the USB device node, several levels
    /// above the media.
    private static func ancestorString(_ entry: io_object_t, _ key: String) -> String? {
        let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        return IORegistryEntrySearchCFProperty(entry,
                                               kIOServicePlane,
                                               key as CFString,
                                               kCFAllocatorDefault,
                                               options) as? String
    }

    private static func ancestorDictionary(_ entry: io_object_t, _ key: String) -> [String: Any]? {
        let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        return IORegistryEntrySearchCFProperty(entry,
                                               kIOServicePlane,
                                               key as CFString,
                                               kCFAllocatorDefault,
                                               options) as? [String: Any]
    }

    /// Every BSD name at or below this whole disk in the IOService plane.
    ///
    /// Used to attribute mounted volumes to the physical disk they ultimately sit on.
    /// The walk is downward and recursive because an APFS volume is several levels
    /// below its physical disk and is *not* named after it — see MountedVolumes.swift.
    private static func bsdNamesInSubtree(of media: io_object_t,
                                          wholeDiskName: String) -> Set<String> {
        var names: Set<String> = [wholeDiskName]

        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(media,
                                            kIOServicePlane,
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

    // MARK: - Live refresh (FR-DEV-7)

    func startObserving(onChange: @escaping () -> Void) {
        guard notificationPort == nil else { return }
        self.onChange = onChange

        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            log.error("IONotificationPortCreate failed; the device list will not live-refresh")
            return
        }
        notificationPort = port

        // Deliver callbacks on the main queue rather than scheduling a run-loop source.
        // The list this feeds is main-actor state, and the alternative — a run-loop
        // source plus a hop — has more moving parts and one more place to get the
        // thread wrong.
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)

        let context = Unmanaged.passUnretained(self).toOpaque()

        // Arrival and departure are separate notification types and each needs its own
        // matching dictionary, since the call consumes it.
        addNotification(kIOMatchedNotification, port: port, context: context,
                        into: &matchedIterator)
        addNotification(kIOTerminatedNotification, port: port, context: context,
                        into: &terminatedIterator)

        volumeWatcher.start { [weak self] in
            self?.deviceSetChanged()
        }

        log.notice("watching for USB device connect/disconnect and volume mount/unmount")
    }

    private func addNotification(_ type: String,
                                 port: IONotificationPortRef,
                                 context: UnsafeMutableRawPointer,
                                 into iterator: inout io_iterator_t) {
        let result = IOServiceAddMatchingNotification(port,
                                                      type,
                                                      Self.wholeMediaMatchingDictionary(),
                                                      deviceNotificationCallback,
                                                      context,
                                                      &iterator)
        guard result == KERN_SUCCESS else {
            log.error("""
                      IOServiceAddMatchingNotification(\(type, privacy: .public)) failed: \
                      \(result, privacy: .public)
                      """)
            return
        }

        // Arming the notification requires draining the iterator once. Until it is
        // emptied the notification does not fire — a silent no-op that looks exactly
        // like hardware that never changes.
        drain(iterator)
    }

    /// Empty an iterator, discarding its contents. Called both to arm a notification
    /// and from the callback, where the same rule applies: an undrained iterator stops
    /// delivering.
    fileprivate static func drain(_ iterator: io_iterator_t) {
        while case let object = IOIteratorNext(iterator), object != 0 {
            IOObjectRelease(object)
        }
    }

    private func drain(_ iterator: io_iterator_t) { Self.drain(iterator) }

    /// Called from the IOKit callback, on the main queue, once per notification.
    fileprivate func deviceSetChanged() {
        pendingChange?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onChange?()
        }
        pendingChange = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.coalescingInterval, execute: work)
    }

    func stopObserving() {
        volumeWatcher.stop()

        pendingChange?.cancel()
        pendingChange = nil
        onChange = nil

        if matchedIterator != 0 {
            IOObjectRelease(matchedIterator)
            matchedIterator = 0
        }
        if terminatedIterator != 0 {
            IOObjectRelease(terminatedIterator)
            terminatedIterator = 0
        }
        if let notificationPort {
            IONotificationPortDestroy(notificationPort)
            self.notificationPort = nil
            log.notice("stopped watching for USB device connect/disconnect")
        }
    }
}

/// C callback for both the matched and terminated notifications.
///
/// A free function because `IOServiceMatchingCallback` is a C function pointer and
/// cannot capture context — the enumerator arrives through `refcon`, unretained,
/// because it owns the notification port and outlives every callback it can receive.
private nonisolated func deviceNotificationCallback(_ refcon: UnsafeMutableRawPointer?,
                                        _ iterator: io_iterator_t) {
    IOKitDeviceEnumerator.drain(iterator)
    guard let refcon else { return }
    Unmanaged<IOKitDeviceEnumerator>.fromOpaque(refcon).takeUnretainedValue().deviceSetChanged()
}
