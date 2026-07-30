//
//  BSDDeviceName.swift
//  USBDriveTester (app target — unprivileged)
//
//  The BSD device name of a whole disk (`disk4`), and the *total order* the device
//  list is presented in (FR-DEV-2).
//
//  Pure: Foundation only, no IOKit, no hardware. That is the point — FR-DEV-2's
//  "stable order" is the part of discovery most likely to be got subtly wrong and the
//  easiest to pin down without a drive attached, so it lives here rather than inline
//  in the enumerator.
//
//  ## Why not just sort the strings
//
//  Lexicographic ordering puts `disk10` before `disk2`, and BSD unit numbers routinely
//  reach double digits on a machine with a few APFS containers — this Mac is currently
//  at disk9. The order also has to be **stable**: the list is rebuilt from scratch on
//  every hot-plug event (see DeviceDiscovery), so any two enumerations of the same set
//  of devices must produce the same sequence, whatever order IOKit hands them back in.
//  IOKit's iteration order is not sorted and is not documented as stable — on this
//  machine it currently returns disk0, disk1, disk3, disk2, disk7, disk9, disk6, disk8.
//
//  A `Comparable` conformance that is a genuine total order gives both properties at
//  once: `sorted()` is deterministic when no two elements compare equal, which is why
//  the comparison below always falls through to `rawValue` rather than stopping at the
//  unit number.
//

import Foundation

/// A BSD device name such as `disk4`, ordered numerically rather than lexically.
nonisolated struct BSDDeviceName: Hashable, Comparable, CustomStringConvertible {

    /// The name exactly as IOKit reported it (`kIOBSDNameKey`).
    let rawValue: String

    /// The unit number parsed out of a `disk<N>…` name, or `nil` when the name does
    /// not have that shape (or its number does not fit in 32 bits — see ``parse(_:)``).
    let unitNumber: UInt32?

    /// Whatever followed the digits: `""` for a whole disk, `"s2"` for a slice.
    let suffix: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
        (self.unitNumber, self.suffix) = Self.parse(rawValue)
    }

    var description: String { rawValue }

    /// Whether this names a **whole** disk rather than a slice of one.
    ///
    /// Discovery filters on IOKit's `Whole` property, not on this, so it is a
    /// cross-check rather than the mechanism — but it makes an assertion possible at
    /// the point a device is turned into a run target (Steps 6/7), where addressing a
    /// slice by mistake would mean writing inside a partition.
    var isWholeDiskName: Bool { unitNumber != nil && suffix.isEmpty }

    /// Buffered device node, e.g. `/dev/disk4`. Used by DiskArbitration in Step 6.
    var devicePath: String { "/dev/\(rawValue)" }

    /// **Raw** device node, e.g. `/dev/rdisk4` — the unbuffered node the helper opens
    /// for uncached I/O in Step 7 (FR-TEST-6). Kept next to its buffered sibling so the
    /// two are never confused: reading through `/dev/diskN` would let the unified
    /// buffer cache satisfy the verify read and make the whole test meaningless.
    var rawDevicePath: String { "/dev/r\(rawValue)" }

    // MARK: - Parsing

    /// Split `disk4s2` into `(4, "s2")`.
    ///
    /// Returns `(nil, "")` for anything that is not `disk` followed by at least one
    /// ASCII digit — including a number too large for `UInt32`, which is not a name
    /// macOS produces but is exactly the sort of input that turns an unchecked
    /// `Int(...)!` into a crash. Unparsed names still sort, just lexically.
    private static func parse(_ name: String) -> (UInt32?, String) {
        let prefix = "disk"
        guard name.hasPrefix(prefix) else { return (nil, "") }

        let rest = name.dropFirst(prefix.count)
        // Deliberately not `Character.isNumber`, which is true for non-ASCII digits
        // such as "٤" — those would parse inconsistently with `UInt32(_:)`.
        let digits = rest.prefix { $0 >= "0" && $0 <= "9" }
        guard !digits.isEmpty, let number = UInt32(digits) else { return (nil, "") }

        return (number, String(rest.dropFirst(digits.count)))
    }

    // MARK: - Ordering (FR-DEV-2)

    /// A total order: numeric on the unit number first, then on the slice suffix, then
    /// on the raw string as a final tie-break so no two distinct names ever compare
    /// equal (which is what makes `sorted()` stable across refreshes).
    ///
    /// Names that do not parse sort **after** those that do. They should not occur for
    /// whole disks, so putting them last keeps them out of the default selection
    /// (FR-DEV-3) rather than having an unrecognised name silently become the
    /// pre-selected drive.
    ///
    /// - Note: the suffix comparison is lexical, so `s10` would sort before `s2`. The
    ///   device list contains whole disks only, whose suffix is always empty, so this
    ///   never arises in practice — it is documented rather than solved because
    ///   solving it would be untested code guarding a case we filter out upstream.
    static func < (lhs: BSDDeviceName, rhs: BSDDeviceName) -> Bool {
        switch (lhs.unitNumber, rhs.unitNumber) {
        case let (left?, right?):
            if left != right { return left < right }
            if lhs.suffix != rhs.suffix { return lhs.suffix < rhs.suffix }
            return lhs.rawValue < rhs.rawValue
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return lhs.rawValue < rhs.rawValue
        }
    }
}
