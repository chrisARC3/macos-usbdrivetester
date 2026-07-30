//
//  CapacityFormatting.swift
//  USBDriveTester (app target — unprivileged)
//
//  Human-readable capacities for the device list (NFR-USE-3, NFR-USE-1).
//
//  ## Base-10, and why
//
//  BUILD-PLAN Step 5 flags this explicitly: pick base-10 or base-2, use it
//  consistently, and label the units. This uses **base-10** (1 kB = 1000 bytes)
//  because every other number the user will check this against is base-10 — the label
//  on the drive, `diskutil info`, Disk Utility, and the manufacturer's spec. A 1 TB
//  drive shown as "931.51 GiB" is arithmetically correct and actively unhelpful when
//  the job at hand is *confirming you selected the right physical device*
//  (NFR-USE-3).
//
//  The exact byte count is shown alongside for the selected device, so nothing is
//  hidden by the rounding — that is what makes the friendly number safe.
//
//  ## Why not ByteCountFormatter
//
//  It is locale-dependent in both its separators and its unit names, which would make
//  these values change with the user's region and make the tests assert whatever the
//  test machine happens to be set to. Capacity is a fact about the hardware; the
//  digits should not move. `String(format:)` with no locale argument formats
//  non-localized, which is what is wanted here.
//

import Foundation

/// Formats byte counts for display.
nonisolated enum CapacityFormatting {

    /// Base-10 (SI) units, matching drive labelling and `diskutil`.
    private static let scaledUnits = ["kB", "MB", "GB", "TB", "PB", "EB"]

    /// A short, human-readable capacity such as `1.00 TB` (NFR-USE-3).
    ///
    /// Counts below 1000 bytes are shown exactly, since rounding them buys nothing.
    /// Everything else gets two decimal places — enough to tell a 1.00 TB drive from
    /// a 1.02 TB one, which is the discrimination this string exists to support.
    static func humanReadable(_ byteCount: UInt64) -> String {
        if byteCount < 1000 {
            return byteCount == 1 ? "1 byte" : "\(byteCount) bytes"
        }

        var value = Double(byteCount)
        var unitIndex = -1

        // Scale first…
        while value >= 1000, unitIndex < scaledUnits.count - 1 {
            value /= 1000
            unitIndex += 1
        }

        // …then re-check after rounding. Without this, 999_995_129_856 bytes formats
        // as "1000.00 GB": it is below the 1 TB threshold before rounding but not
        // after it. (That is not a hypothetical — it is the size the synthesized APFS
        // container on a 1 TB USB drive reports.)
        if (value * 100).rounded() / 100 >= 1000, unitIndex < scaledUnits.count - 1 {
            value /= 1000
            unitIndex += 1
        }

        return String(format: "%.2f %@", value, scaledUnits[unitIndex])
    }

    /// The exact count, digit-grouped: `1,000,204,886,016 bytes`.
    ///
    /// Shown for the *selected* device so the friendly figure above can be reconciled
    /// against `diskutil info` byte-for-byte before anything is written to the drive.
    ///
    /// - Parameter groupingSeparator: Defaults to the user's locale so the number
    ///   reads naturally, and is injectable so tests assert a fixed string rather than
    ///   whatever region the machine running them is set to.
    static func exactBytes(_ byteCount: UInt64,
                           groupingSeparator: String = Locale.current.groupingSeparator ?? ",")
    -> String {
        let unit = byteCount == 1 ? "byte" : "bytes"
        return "\(grouped(byteCount, separator: groupingSeparator)) \(unit)"
    }

    /// Insert `separator` every three digits from the right.
    static func grouped(_ value: UInt64, separator: String = Locale.current.groupingSeparator ?? ",")
    -> String {
        let digits = String(value)
        guard digits.count > 3 else { return digits }

        var groups: [String] = []
        var remaining = Substring(digits)
        while remaining.count > 3 {
            groups.append(String(remaining.suffix(3)))
            remaining = remaining.dropLast(3)
        }
        groups.append(String(remaining))

        return groups.reversed().joined(separator: separator)
    }
}
