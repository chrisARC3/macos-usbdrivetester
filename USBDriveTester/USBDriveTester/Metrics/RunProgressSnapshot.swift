//
//  RunProgressSnapshot.swift
//  USBDriveTester (app target — unprivileged)
//
//  Step 9 (AI-8). The app's view of what a run is doing: `runProgress`'s eleven primitives,
//  decoded back into something with names and optionals.
//
//  ## Why this type exists at all, rather than the app using Core's `MetricsSnapshot`
//
//  `Core/` compiles into the helper and the test target but **deliberately not into the app
//  module** — the app sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which would infect a core
//  that has to stay pure. So the app cannot see `MetricsSnapshot`, and the metrics cross the
//  boundary as primitives like everything else on this protocol. This is the same arrangement as
//  `DeviceReadiness` and `CacheBypassOutcome`.
//
//  ## Turning sentinels back into `nil`, once, here
//
//  The wire cannot carry an optional, so the helper sends `-1` for a rate it has not measured and
//  a sample count of `0` for latency figures that mean nothing yet. **Those sentinels stop at
//  this type.** Every consumer above it sees `nil`, and no view has to remember that `-1` is not
//  a speed.
//
//  That matters more than it sounds. The alternative — passing `-1` up and formatting it
//  somewhere — is how a display ends up reading "-1.0 MB/s", or worse "0 MB/s", which means
//  *stalled*: a real and alarming condition being used to report that nothing has happened yet.
//

import Foundation

/// What the helper reported about the run in progress.
nonisolated struct RunProgressSnapshot: Equatable {

    /// `false` when no run has started since the daemon launched. Every other property is then
    /// `nil` or zero and means nothing.
    let isAvailable: Bool

    /// `0...1` (FR-METR-5).
    let fractionComplete: Double

    /// One past the last block reached (FR-METR-6).
    let currentBlock: UInt64

    /// The device's read speed, or `nil` until a read has been timed (FR-METR-1).
    let readBytesPerSecond: Double?

    /// The device's write speed, or `nil` until a write has been timed (FR-METR-1).
    let writeBytesPerSecond: Double?

    /// Remaining wall-clock from measured throughput, or `nil` until there is something to
    /// extrapolate from (FR-METR-5, NFR-PERF-6).
    let estimatedRemaining: TimeInterval?

    /// How many original reads the latency figures are computed over. `0` means they mean
    /// nothing — which is *not* the same as a latency of zero, itself a legitimate reading.
    let readLatencySampleCount: UInt64

    /// Shortest original read (FR-METR-3). `nil` when there are no samples.
    let readLatencyMinimum: Duration?

    /// Longest original read (FR-METR-3). `nil` when there are no samples.
    let readLatencyMaximum: Duration?

    /// The **upper bound** of p99 (FR-METR-3): the true value is at or below it, within one
    /// histogram bucket of at most 1.5625%. Displayed as "p99 ≤ x" rather than "p99 = x",
    /// because a single number here would be a bucket's midpoint dressed up as a measurement.
    let readLatencyP99UpperBound: Duration?

    /// Failed chunks so far. Surfaced live because a user watching a suspect drive wants to see
    /// the first one appear, not read about it at the end.
    let chunksFailed: UInt64

    /// Nothing has started.
    static let unavailable = RunProgressSnapshot(
        isAvailable: false, fractionComplete: 0, currentBlock: 0,
        readBytesPerSecond: nil, writeBytesPerSecond: nil, estimatedRemaining: nil,
        readLatencySampleCount: 0, readLatencyMinimum: nil, readLatencyMaximum: nil,
        readLatencyP99UpperBound: nil, chunksFailed: 0)

    /// Decode one `runProgress` reply. **The only place the wire's sentinels are interpreted.**
    ///
    /// - Parameters:
    ///   - rates: `-1` for "not measured yet", which becomes `nil`. A negative rate is otherwise
    ///     impossible, which is what makes the sentinel unambiguous.
    ///   - latencySampleCount: `0` makes the three latency values `nil` regardless of what they
    ///     contain, because `0` nanoseconds is a real reading and cannot be its own sentinel.
    init(available: Bool,
         fractionComplete: Double,
         currentBlock: UInt64,
         readBytesPerSecond: Double,
         writeBytesPerSecond: Double,
         estimatedRemainingSeconds: Double,
         readLatencySampleCount: UInt64,
         readLatencyMinimumNanoseconds: UInt64,
         readLatencyMaximumNanoseconds: UInt64,
         readLatencyP99UpperBoundNanoseconds: UInt64,
         chunksFailed: UInt64) {

        func rate(_ value: Double) -> Double? {
            value >= 0 && value.isFinite ? value : nil
        }
        func latency(_ nanoseconds: UInt64) -> Duration? {
            readLatencySampleCount > 0 ? .nanoseconds(nanoseconds) : nil
        }

        self.isAvailable = available
        self.fractionComplete = Swift.min(Swift.max(fractionComplete, 0), 1)
        self.currentBlock = currentBlock
        self.readBytesPerSecond = rate(readBytesPerSecond)
        self.writeBytesPerSecond = rate(writeBytesPerSecond)
        self.estimatedRemaining = rate(estimatedRemainingSeconds)
        self.readLatencySampleCount = readLatencySampleCount
        self.readLatencyMinimum = latency(readLatencyMinimumNanoseconds)
        self.readLatencyMaximum = latency(readLatencyMaximumNanoseconds)
        self.readLatencyP99UpperBound = latency(readLatencyP99UpperBoundNanoseconds)
        self.chunksFailed = chunksFailed
    }

    /// Memberwise, for the `unavailable` case and for tests.
    init(isAvailable: Bool,
         fractionComplete: Double,
         currentBlock: UInt64,
         readBytesPerSecond: Double?,
         writeBytesPerSecond: Double?,
         estimatedRemaining: TimeInterval?,
         readLatencySampleCount: UInt64,
         readLatencyMinimum: Duration?,
         readLatencyMaximum: Duration?,
         readLatencyP99UpperBound: Duration?,
         chunksFailed: UInt64) {
        self.isAvailable = isAvailable
        self.fractionComplete = fractionComplete
        self.currentBlock = currentBlock
        self.readBytesPerSecond = readBytesPerSecond
        self.writeBytesPerSecond = writeBytesPerSecond
        self.estimatedRemaining = estimatedRemaining
        self.readLatencySampleCount = readLatencySampleCount
        self.readLatencyMinimum = readLatencyMinimum
        self.readLatencyMaximum = readLatencyMaximum
        self.readLatencyP99UpperBound = readLatencyP99UpperBound
        self.chunksFailed = chunksFailed
    }

    /// Whether any latency statistic is meaningful yet.
    var hasLatencySamples: Bool { readLatencySampleCount > 0 }
}
