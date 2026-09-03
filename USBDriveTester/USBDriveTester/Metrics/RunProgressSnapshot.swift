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

/// The wire's "not measured" conventions, in one place.
///
/// ## Why this is a shared type and not two copies of two `if`s
///
/// From protocol v9 there are **two** replies carrying these figures: `runProgress` for the run
/// in flight, and `runRetentionCycle` for the run that just finished (Step 10 — they are in the
/// cycle's own reply so a *refused* run cannot be reported with the previous run's numbers).
/// Both use the same sentinels, and both must, or the same drive would read one way live and
/// another way in the exported report.
///
/// Two copies of "`-1` means nil" is exactly the kind of duplication that survives until somebody
/// fixes one of them.
nonisolated enum WireSentinel {

    /// A rate, or `nil` when the helper had not measured one.
    ///
    /// `-1` rather than `0`, and this is the whole point: a rate of zero means **stalled** — a
    /// real and alarming condition — so using it for "nothing has happened yet" would print an
    /// alarm to report an absence. A negative rate is otherwise impossible, which is what makes
    /// the sentinel unambiguous. Non-finite values are rejected too: a `NaN` formats as "nan"
    /// and an infinity as "inf", both of which read as data.
    static func rate(_ value: Double) -> Double? {
        value >= 0 && value.isFinite ? value : nil
    }

    /// A latency, or `nil` when there are no samples to have measured one from.
    ///
    /// Gated on the sample count rather than on the value, because **`0` nanoseconds is a
    /// legitimate reading** — a read the clock could not resolve — and cannot be its own
    /// sentinel.
    static func latency(_ nanoseconds: UInt64, sampleCount: UInt64) -> Duration? {
        sampleCount > 0 ? .nanoseconds(nanoseconds) : nil
    }
}

/// What the helper reported about the run in progress.
nonisolated struct RunProgressSnapshot: Equatable {

    /// `false` when no run has started since the daemon launched. Every other property is then
    /// `nil` or zero and means nothing.
    let isAvailable: Bool

    /// `0...1` (FR-METR-5).
    let fractionComplete: Double

    /// One past the last block reached (FR-METR-6).
    let currentBlock: UInt64

    /// **The device's read speed** (FR-METR-1, amended 2026-09-02): the original read and the
    /// verify read together, divided by the time spent on both — or `nil` until something has
    /// been read.
    ///
    /// **Not comparable to Activity Monitor**, deliberately, and about 1.5× what it shows for the
    /// same drive. This carried a wall-clock rate from v12 to v13 for exactly the opposite
    /// reason; the requirement changed, not the arithmetic. `ThroughputFraming.definition` is
    /// what tells the user, and is the reason the change is safe to make.
    let deviceReadBytesPerSecond: Double?

    /// **The device's write speed** (FR-METR-1, amended 2026-09-02): bytes written ÷ the time
    /// spent writing them, or `nil` until something has been written. About **3.4×** what
    /// Activity Monitor shows, and legitimately above ``deviceReadBytesPerSecond`` on a drive
    /// that writes faster than it reads — which the 4 TB T5 EVO does.
    let writeBytesPerSecond: Double?

    /// How fast the run is covering the drive, against the wall clock (FR-METR-5) — and the only
    /// correct ETA denominator.
    ///
    /// **Deliberately not displayed anywhere, since Step 11 increment 10.** The `Covering` row was
    /// deleted from the panel, the report and the export together: `rangeBytesCovered` counts
    /// **attempted** work while the label promised successful work, and the two only part on a
    /// failing drive. The number is right and its name was not.
    ///
    /// It is kept because it is the wire's, not the app's, to remove — the reply signature cannot
    /// change without a protocol version — and because increment 11's `R-W-R-C speed` arrives
    /// beside it. **This is the field CONSTRAINTS warns about**: a wire field nothing displays is
    /// how this very figure went a week computed, tested and logged while no screen could show it.
    /// The difference now is that its absence is a decision written down here rather than an
    /// oversight, and the ETA below is what consumes the quantity.
    let coverageBytesPerSecond: Double?

    /// **`R-W-R-C speed`** (FR-METR-1, protocol v14): bytes in chunks that were read, written
    /// back, read again and **matched**, per second of successful phase time.
    ///
    /// The successful-work counterpart of ``coverageBytesPerSecond`` above, which counts every
    /// byte attempted — and the figure that row was mislabelled as. Displayed on the metrics
    /// panel, the report sheet and the exported Markdown, all three together, because a rate one
    /// surface names and another refuses is the drift `ThroughputFraming` exists to end.
    ///
    /// **It equalled ``writeBytesPerSecond`` on a clean run until v14 and no longer does** — it
    /// is a per-cycle rate where that is per-phase, so it sits at roughly a third of it on a
    /// drive with nothing wrong. Expect a panel reading `376 / 419 / 130` on healthy hardware.
    /// What replaces the equality is an exact relationship among all three:
    ///
    ///     1 / completed  =  2 / deviceRead  +  1 / write
    ///
    /// and this rate falling **below** that prediction is the retention signal — bytes the drive
    /// accepted and could not then confirm.
    let completedBytesPerSecond: Double?

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
        deviceReadBytesPerSecond: nil, writeBytesPerSecond: nil,
        coverageBytesPerSecond: nil, completedBytesPerSecond: nil, estimatedRemaining: nil,
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
         deviceReadBytesPerSecond: Double,
         writeBytesPerSecond: Double,
         coverageBytesPerSecond: Double,
         completedBytesPerSecond: Double,
         estimatedRemainingSeconds: Double,
         readLatencySampleCount: UInt64,
         readLatencyMinimumNanoseconds: UInt64,
         readLatencyMaximumNanoseconds: UInt64,
         readLatencyP99UpperBoundNanoseconds: UInt64,
         chunksFailed: UInt64) {

        func latency(_ nanoseconds: UInt64) -> Duration? {
            WireSentinel.latency(nanoseconds, sampleCount: readLatencySampleCount)
        }

        self.isAvailable = available
        self.fractionComplete = Swift.min(Swift.max(fractionComplete, 0), 1)
        self.currentBlock = currentBlock
        self.deviceReadBytesPerSecond = WireSentinel.rate(deviceReadBytesPerSecond)
        self.writeBytesPerSecond = WireSentinel.rate(writeBytesPerSecond)
        self.coverageBytesPerSecond = WireSentinel.rate(coverageBytesPerSecond)
        self.completedBytesPerSecond = WireSentinel.rate(completedBytesPerSecond)
        self.estimatedRemaining = WireSentinel.rate(estimatedRemainingSeconds)
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
         deviceReadBytesPerSecond: Double?,
         writeBytesPerSecond: Double?,
         coverageBytesPerSecond: Double?,
         completedBytesPerSecond: Double?,
         estimatedRemaining: TimeInterval?,
         readLatencySampleCount: UInt64,
         readLatencyMinimum: Duration?,
         readLatencyMaximum: Duration?,
         readLatencyP99UpperBound: Duration?,
         chunksFailed: UInt64) {
        self.isAvailable = isAvailable
        self.fractionComplete = fractionComplete
        self.currentBlock = currentBlock
        self.deviceReadBytesPerSecond = deviceReadBytesPerSecond
        self.writeBytesPerSecond = writeBytesPerSecond
        self.coverageBytesPerSecond = coverageBytesPerSecond
        self.completedBytesPerSecond = completedBytesPerSecond
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
