//
//  MetricsFormatting.swift
//  USBDriveTester (app target — unprivileged)
//
//  Step 9 (AI-8). NFR-USE-1 and NFR-USE-2 in one file: throughput and latency "in an easily
//  readable form, with clear units", and progress "including percent complete, current position,
//  and the live ETA".
//
//  Pure functions over primitives, `nonisolated` so the app target's MainActor default does not
//  make a formatter into something a background reply has to hop for. Unit-tested through
//  `@testable import USBDriveTester` — no target-membership tick needed, unlike `Core/`.
//
//  ## Three rules, and the first one is why this file exists separately from the view
//
//  1. **An unknown is never formatted as a number.** Every entry point takes an optional and
//     returns an em-dash for `nil`. A view cannot accidentally render a missing rate as `0 MB/s`
//     — which means *stalled*, a real and alarming condition — because there is no path from
//     `nil` to a digit. This is the same defect that appeared in the D1 probe's own reporting on
//     2026-08-04 ("worst reply during the call: 0.0 ms" printed when there had been no replies at
//     all), and it is worth closing structurally rather than by remembering.
//
//  2. **Decimal MB, not MiB.** A drive's advertised sustained rate is quoted in decimal
//     megabytes, and the whole point of showing throughput is that the user can compare it with
//     that figure (user decision 2026-08-04). Using 2²⁰ here would make every reading ~4.8% lower
//     than the number on the box, for no reason the user could see.
//
//  3. **No verdict, ever.** These functions render magnitudes. Whether 320 MB/s is bad for a
//     drive advertised at 540 MB/s is the user's judgement, made with the negotiated link speed
//     in hand — not something this tool decides. There is deliberately no `isSlow`, no colour
//     rule keyed to a threshold, and no adjective.
//

import Foundation

/// Renders measured quantities for display (NFR-USE-1, NFR-USE-2).
nonisolated enum MetricsFormatting {

    /// What every "not measured" renders as. An em-dash, because it is visibly not a number —
    /// where `0`, `-`, or `n/a` each read as a value, a range, or an error respectively.
    static let unknown = "—"

    // MARK: - Throughput (FR-METR-1/2, NFR-USE-1)

    /// Bytes per second as MB/s, in **decimal** megabytes so it compares directly with a
    /// manufacturer's advertised sustained figure.
    ///
    /// Switches to GB/s above 1,000 MB/s: a USB4 enclosure can reach it, and "1,340 MB/s" is
    /// harder to read at a glance than "1.34 GB/s".
    static func throughput(_ bytesPerSecond: Double?) -> String {
        guard let bytesPerSecond, bytesPerSecond >= 0, bytesPerSecond.isFinite else {
            return unknown
        }
        if bytesPerSecond >= 1_000_000_000 {
            return String(format: "%.2f GB/s", bytesPerSecond / 1_000_000_000)
        }
        if bytesPerSecond >= 1_000_000 {
            return String(format: "%.0f MB/s", bytesPerSecond / 1_000_000)
        }
        return String(format: "%.0f kB/s", bytesPerSecond / 1_000)
    }

    // MARK: - Latency (FR-METR-3/4, NFR-USE-1)

    /// A per-chunk read latency in milliseconds, or microseconds when that would otherwise read
    /// as `0.000 ms`.
    ///
    /// Three decimals at millisecond scale, because a 4 MiB read at ~500 MB/s is about 8.4 ms and
    /// the differences worth seeing between a healthy and a struggling drive are smaller than
    /// that.
    static func latency(_ duration: Duration?) -> String {
        guard let duration else { return unknown }
        let nanoseconds = duration.wholeNanoseconds
        if nanoseconds < 1_000 { return "\(nanoseconds) ns" }
        if nanoseconds < 1_000_000 {
            return String(format: "%.1f µs", Double(nanoseconds) / 1_000)
        }
        if nanoseconds < 1_000_000_000 {
            return String(format: "%.3f ms", Double(nanoseconds) / 1_000_000)
        }
        return String(format: "%.2f s", Double(nanoseconds) / 1_000_000_000)
    }

    /// p99, labelled as the **upper bound** it is.
    ///
    /// The histogram knows the answer to within one bucket — at most 1.5625% — and reporting a
    /// single number would be the bucket's midpoint pretending to be a measurement. "≤" costs one
    /// character and is true.
    static func percentileUpperBound(_ duration: Duration?) -> String {
        guard let duration else { return unknown }
        return "≤ " + latency(duration)
    }

    // MARK: - Progress (FR-METR-5/6, NFR-USE-2)

    /// `0...1` as a percentage. No decimals: a progress figure that jitters in its last digit
    /// once a second is harder to read, not more precise.
    static func percent(_ fraction: Double) -> String {
        let clamped = Swift.min(Swift.max(fraction, 0), 1)
        return String(format: "%.0f%%", clamped * 100)
    }

    /// A block offset, grouped so it can be read and compared at a glance —
    /// `1,234,567` rather than `1234567`.
    static func blockOffset(_ block: UInt64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: block)) ?? "\(block)"
    }

    /// When a run started, as a date **and** a time.
    ///
    /// ## Why the date is always shown, and never elided to just a clock time (2026-08-05)
    ///
    /// A bare "16:14" is unreadable the moment it is not today's — and nothing on screen says
    /// which day it is. The figures in this panel are a *measurement of somebody's hardware*, and
    /// a measurement whose date is ambiguous invites being compared against a later one as though
    /// both were current. Showing the date costs a few characters and removes the question.
    ///
    /// `.abbreviated` rather than `.numeric` deliberately: `05/08/2026` reads as 5 August or as
    /// 8 May depending on where the reader is, and this is a figure people will quote to each
    /// other. `5 Aug 2026` cannot be misread.
    static func runTimestamp(_ date: Date?) -> String {
        guard let date else { return unknown }
        return date.formatted(.dateTime.day().month(.abbreviated).year()
                                       .hour().minute())
    }

    /// A remaining duration, in the largest units that still say something useful.
    ///
    /// Rounded deliberately coarsely as it grows: an ETA of "about 3 hours" is honest about what
    /// a measured-throughput extrapolation knows, where "2 h 57 m 13 s" would imply a precision
    /// the estimate does not have (NFR-PERF-6 — it converges, it is not exact).
    static func remaining(_ interval: TimeInterval?) -> String {
        guard let interval, interval >= 0, interval.isFinite else { return unknown }

        let seconds = Int(interval.rounded())
        if seconds < 1 { return "less than a second" }
        if seconds < 60 { return "\(seconds) s" }

        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min \(seconds % 60) s" }

        let hours = minutes / 60
        if hours < 24 { return "\(hours) h \(minutes % 60) min" }
        return "\(hours / 24) d \(hours % 24) h"
    }

    // MARK: - The link speed, beside the measured rate (user decision 2026-08-04)

    /// The negotiated USB link speed, from `deviceProfile`'s raw registry code.
    ///
    /// Presented **next to** measured throughput because the user's stated method for judging a
    /// drive is to compare the measured rate against the manufacturer's advertised sustained
    /// figure *after accounting for negotiated speed limits* — and they cannot do that with only
    /// one of the two numbers.
    ///
    /// - Important: the code is the raw IORegistry `Device Speed` value, which is **not** the
    ///   enumeration any SDK header declares (see `Core/USBLinkSpeed`). An unrecognised code is
    ///   reported as unrecognised, with the number, rather than guessed at — `scripts/usb-speed-check.sh`
    ///   is what detects a shift in that mapping.
    static func linkSpeed(code: Int) -> String {
        switch code {
        case -1: return unknown
        case 0:  return "1.5 Mb/s (USB 1.0 low speed)"
        case 1:  return "12 Mb/s (USB 1.1 full speed)"
        case 2:  return "480 Mb/s (USB 2.0 high speed)"
        case 3:  return "5 Gb/s (USB 3.0)"
        case 4:  return "10 Gb/s (USB 3.1 Gen 2)"
        case 5:  return "20 Gb/s (USB 3.2 Gen 2×2)"
        default: return "unrecognised link speed code \(code)"
        }
    }
}

// MARK: -

private extension Duration {

    /// Whole nanoseconds. `Duration` stores attoseconds; this is the only resolution any clock
    /// here produces.
    ///
    /// `nonisolated` because the app target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
    /// which isolates even an extension on a standard-library value type — and `MetricsFormatting`
    /// is `nonisolated` so a background XPC reply can format without hopping. The same gotcha
    /// that Steps 5 and 6 hit on plain value types, arriving on an extension this time.
    nonisolated var wholeNanoseconds: Int64 {
        let parts = components
        return parts.seconds * 1_000_000_000 + parts.attoseconds / 1_000_000_000
    }
}
