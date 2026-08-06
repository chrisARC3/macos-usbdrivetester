//
//  MetricsChannel.swift
//  Helper — making a run's metrics readable from another thread, and nothing else.
//
//  Step 9 (AI-8), BUILD-PLAN 9.4. This is the concurrency half of the live-metrics path; the
//  arithmetic half is `Core/RunMetrics`, which has no locks by rule and is unit-tested without
//  any.
//
//  ## Why this file has no logic in it
//
//  Deliberately. Everything that could be decided in Core already was — the accumulation, the
//  percentile, the ETA, the three rates. What is left here is a lock and a slot, because that is
//  the part that cannot exist in Core: a run mutates its metrics on the thread XPC delivered
//  `runRetentionCycle` on, and `runProgress` reads them on a different thread entirely.
//
//  Anything with a decision in it that ends up here is in the wrong file.
//
//  ## Why there is no throttle, and no copying
//
//  An earlier sketch published a computed `MetricsSnapshot` into a box after every chunk, with a
//  100 ms throttle to stop it recomputing a percentile forty times a second. Both were solving a
//  problem that only existed because of the design: hold the **accumulator** behind the lock
//  instead, and the snapshot — percentile included — is computed once per *poll*, on the poller's
//  thread, about once a second.
//
//  So the run's per-chunk cost is one uncontended lock acquisition, and nothing is computed for a
//  reader that has not asked. Recording a chunk is ~3 ns of histogram work (measured) inside a
//  lock nobody else holds; the poll walks 2,240 buckets once a second.
//
//  ## Lifetime: the last run's figures survive it
//
//  ``begin()`` replaces the slot, and nothing clears it. A poll arriving after a run finishes
//  therefore returns that run's **final** numbers, which is exactly what a caller wants at the
//  end of a run — and between runs there is no caller to mislead, because the app issues runs on
//  its own connection and knows the lifecycle without asking (user decision 2026-08-04).
//

import Foundation

// MARK: - The run's metrics, readable from another thread

/// Wraps a `RunMetricsObserver` so a run can write to it while `runProgress` reads.
///
/// `@unchecked Sendable` with an explicit lock, the same pattern and for the same reason as
/// `HelperActivity`: XPC delivers calls on arbitrary queues, so serialisation is stated here
/// rather than assumed.
///
/// - Important: the lock is held across `RunMetrics.record` and across snapshot computation, and
///   across nothing else. Neither does I/O, allocates, or calls out — so a poll can never block
///   a run for longer than a percentile walk, and a run can never block a poll for longer than a
///   histogram increment.
final class SynchronizedMetricsObserver: RunObserver, @unchecked Sendable {

    private let lock = NSLock()
    private let inner: RunMetricsObserver

    init(clock: @escaping MonotonicClock = RunClock.monotonicNanoseconds) {
        inner = RunMetricsObserver(clock: clock)
    }

    func runStarted(_ start: RunStart) {
        lock.withLock { inner.runStarted(start) }
    }

    func chunkMeasured(_ chunk: Chunk, measurement: ChunkMeasurement) {
        lock.withLock { inner.chunkMeasured(chunk, measurement: measurement) }
    }

    /// What the run looks like right now, or `nil` before its first event.
    var snapshot: MetricsSnapshot? {
        lock.withLock { inner.snapshot() }
    }
}

// MARK: - Finding it from another connection

/// The process-wide slot holding the current run's metrics.
///
/// A singleton for the same reason `HelperActivity` is one: `runProgress` arrives on a *different
/// connection* from the run it is asking about — it has to, because a second message on the run's
/// own connection is not delivered until the run ends (measured 2026-08-04,
/// `scripts/xpc-concurrency-check.sh`). So there is nowhere connection-scoped to put this.
///
/// It holds no device, takes no slot and blocks nothing. `HelperActivity` remains the authority
/// on what the helper is *doing*; this only remembers what the last run measured.
final class MetricsChannel: @unchecked Sendable {

    static let shared = MetricsChannel()

    private let lock = NSLock()
    private var current: SynchronizedMetricsObserver?

    private init() {}

    /// Start a fresh observer for a new run and install it, replacing any previous run's.
    func begin(clock: @escaping MonotonicClock = RunClock.monotonicNanoseconds)
        -> SynchronizedMetricsObserver {
        let observer = SynchronizedMetricsObserver(clock: clock)
        lock.withLock { current = observer }
        return observer
    }

    /// The current — or most recent — run's figures, or `nil` if no run has started since the
    /// daemon launched.
    var snapshot: MetricsSnapshot? {
        let observer = lock.withLock { current }
        return observer?.snapshot
    }
}

// MARK: - NFR-PERF-3's second number

/// The daemon's own CPU consumption, for the requirement that a run be *device-bound, not
/// host-bound*.
///
/// ## Two numbers, because the requirement and the gate ask different questions
///
/// NFR-PERF-3's own wording is a **ratio of durations** — per-chunk compare, metrics and
/// bookkeeping against the wall-clock of the I/O — and that is measured inside the cycle's loop
/// and arrives as `MetricsSnapshot.hostOverheadFraction`. BUILD-PLAN 9.5a asks for something
/// related but different: CPU as a percentage of one core at a stated MB/s, which is what
/// extrapolates to a faster transport and what goes in Step 16's release note.
///
/// This provides the second. It is **process-wide**, which is the honest scope: during a cycle
/// the daemon does nothing else except answer progress polls, and those polls are part of what
/// the product costs.
///
/// The figure this replaces was somebody watching Activity Monitor. That reading — 36–39% of one
/// core at ~500 MB/s during Step 8's gate — was the *fingerprint's* SHA-256, which is not in the
/// product's run path at all.
enum HelperCPUSample {

    /// Total CPU seconds this process has consumed, user plus system, or `nil` if the kernel
    /// would not say.
    static func processCPUSeconds() -> Double? {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    /// CPU consumed between two readings, as a fraction of **one core**.
    ///
    /// `1.0` means one core saturated; on an M4 there are more, so values above 1 are possible
    /// and would mean the daemon had gone parallel — which it has not, and which would itself be
    /// worth knowing.
    ///
    /// Returns `nil` rather than `0` when it cannot be computed. Zero is a legitimate and very
    /// different answer, and a figure this project intends to quote in a release note must not
    /// have "unknown" and "free" spelled the same way.
    static func coreFraction(from start: Double?, to end: Double?, wallSeconds: Double) -> Double? {
        guard let start, let end, wallSeconds > 0 else { return nil }
        let consumed = end - start
        guard consumed >= 0 else { return nil }        // a counter that went backwards
        return consumed / wallSeconds
    }

    private static func seconds(_ value: timeval) -> Double {
        Double(value.tv_sec) + Double(value.tv_usec) / 1_000_000
    }
}
