//
//  FailureStreak.swift
//  USBDriveTester (app target — unprivileged)
//
//  The rule that keeps a repeating failure from flooding the error channel: the first line of each
//  kind in a streak is logged, the repeats are held back and counted, and the end of the streak is
//  logged once with the count.
//
//  ## Why it exists
//
//  Found 2026-09-25 under Step 11's chunk 16 item 3, with the helper switched off in Login Items:
//  the live metrics panel's 1 Hz progress poll logged `helper progress connection invalidated` and
//  `helper transport error` on every ask — 11 of each in ten seconds — while nothing on screen
//  changed. Recorded as *Owed* (h); the shape was decided by the user 2026-09-26 and paid in
//  Step 15's chunk 3, 2026-09-30: **the first failure of a streak logged at error, the repeats
//  silent, and one notice with the count when progress answers again**, the rule a small pure type
//  with tests. This is that type; `HelperConnection` applies it to the progress poll and to nothing
//  else (user decision 2026-09-30, *"poll only"*) — a Pause or Stop that does not reach the helper
//  is logged every time.
//
//  ## Why *per kind*
//
//  One failed poll produces two lines that say different things — the connection's invalidation,
//  and the transport error that carries the reason — and XPC does not promise their order. Logging
//  the first line of the streak alone would keep whichever came first and could drop the reason.
//  Logging the first of each kind keeps exactly what the first failed poll logged before this
//  existed, and silences only the repeats.
//
//  Pure and clock-free: the caller passes the time in, so the tests need no waiting.
//

import Foundation

nonisolated struct FailureStreak<Kind: Hashable>: Equatable {

    /// How a streak ended, for the one notice that says so.
    struct Recovery: Equatable {
        /// Failure lines held back since the streak began — the repeats, not the first of each kind.
        let heldBack: Int
        /// From the streak's first failure to the answer that ended it.
        let seconds: TimeInterval
    }

    /// When the current streak began; `nil` when there is none.
    private(set) var startedAt: Date?

    /// The kinds already logged in the current streak.
    private(set) var logged: Set<Kind> = []

    /// Repeats held back in the current streak.
    private(set) var heldBack = 0

    var isActive: Bool { startedAt != nil }

    /// A failure of `kind` happened. Returns whether to log it.
    mutating func failed(_ kind: Kind, at now: Date) -> Bool {
        if startedAt == nil { startedAt = now }
        if logged.insert(kind).inserted { return true }
        heldBack += 1
        return false
    }

    /// The thing that was failing answered. Returns the recovery to log when this ends a streak, and
    /// `nil` when there was no streak — an ordinary success logs nothing.
    mutating func answered(at now: Date) -> Recovery? {
        guard let startedAt else { return nil }
        let recovery = Recovery(heldBack: heldBack, seconds: now.timeIntervalSince(startedAt))
        self = FailureStreak()
        return recovery
    }
}
