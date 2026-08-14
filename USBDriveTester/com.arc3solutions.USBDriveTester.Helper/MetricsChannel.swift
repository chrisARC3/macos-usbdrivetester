//
//  MetricsChannel.swift
//  Helper — making a run's accumulators readable from another thread, and nothing else.
//
//  Step 9 (AI-8), BUILD-PLAN 9.4; reshaped in Step 11 increment 3 when a run stopped being one
//  call. This is the concurrency half of the live-metrics path; the arithmetic half is
//  `Core/RunMetrics`, which has no locks by rule and is unit-tested without any.
//
//  ## Why this file has no logic in it
//
//  Deliberately. Everything that could be decided in Core already was — the accumulation, the
//  percentile, the ETA, the three rates, the failure coalescing. What is left here is a lock and a
//  lookup, because that is the part that cannot exist in Core: a run mutates its accumulators on
//  the thread XPC delivered `runRetentionCycle` on, and `runProgress` reads them on a different
//  thread entirely.
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
//  ## LIFETIME: THE SESSION IS THE CLAIM, AND THAT IS WHY THERE IS NO SLOT ANY MORE
//
//  Until Step 11 this file owned a process-wide slot that `begin()` replaced when a run started
//  and nothing ever cleared. That was right when one call was one run, and it carried a known
//  hazard: `begin()` ran *after* validation, so a **refused** call left the previous run's figures
//  installed, and a caller that polled would find them and report them as its own. Protocol v9's
//  answer was to carry the figures in the cycle's own reply, read from the observer that call had
//  installed — "the figures belong to this run or they do not exist".
//
//  A run is now a sequence of bounded calls and the accumulators live on the **claim**
//  (CONSTRAINTS section 2), so that mechanism is gone and had to be replaced rather than ported:
//
//    * **The slot is deleted.** The session is a stored property of ``AcquiredDevice``, created by
//      `DeviceClaim.acquire` and destroyed by `release()`. Its lifetime *is* the claim's, so a new
//      claim necessarily starts empty and a released claim necessarily answers nothing. That
//      property is no longer maintained by anybody remembering to clear something.
//    * **The v9 hazard cannot occur at all.** There is no previous run's accumulator to confuse
//      this run with — it died with its claim. A poll arriving after a refused call now returns
//      *this* session's figures, which is a true statement about the run in progress rather than a
//      different run's numbers wearing its name.
//    * **What still guards the reply is the result type.** Every figure in `runRetentionCycle`'s
//      reply is read out of `RunCoordinator.CycleResult`, and a `CycleResult` exists only on the
//      success path; a refusal returns `.failure` and `main.swift`'s `refuse()` has nothing to read
//      from. That is a weaker guard than v9's — under v9 the refusal path *could not* reach any
//      figures, and now they exist one line away — and `main.swift` is not in the test target, so
//      the only check that reaches it is `metrics-check.sh`'s assertion that a refused call
//      reports no mode and no figures. Say so rather than rounding it up.
//
//  What this class keeps is the half its name is about: **finding** the session from a connection
//  other than the one running.
//

import Foundation

// MARK: - The run's accumulators, readable from another thread

/// One run's session: the accumulators that span every bounded call the run is made of, behind a
/// lock so `runProgress` can read them while the run writes.
///
/// Held by ``AcquiredDevice`` for exactly as long as the claim is held. `@unchecked Sendable` with
/// an explicit lock, the same pattern and for the same reason as `HelperActivity`: XPC delivers
/// calls on arbitrary queues, so serialisation is stated here rather than assumed.
///
/// - Important: the lock is held across `RunSessionObserver`'s mutations and across snapshot
///   computation, and across nothing else. Neither does I/O, allocates, or calls out — so a poll
///   can never block a run for longer than a percentile walk, and a run can never block a poll for
///   longer than a histogram increment.
final class RunSession: RunObserver, @unchecked Sendable {

    private let lock = NSLock()
    private let inner: RunSessionObserver

    /// The daemon's CPU when the session opened, for NFR-PERF-3's second figure.
    ///
    /// Taken at **acquire** rather than at the first call, so the fraction covers the run as the
    /// user experiences it — including the gaps between calls, in which the daemon is idle and so
    /// contributes wall-clock but no CPU. The alternative, bracketing each call and summing, would
    /// report the cost of the calls rather than the cost of the run.
    private let cpuAtOpen: Double?
    private let wallAtOpen: UInt64

    init(deviceBytesTotal: UInt64,
         cacheBypass: CacheBypassAssessment,
         clock: @escaping MonotonicClock = RunClock.monotonicNanoseconds) {
        inner = RunSessionObserver(deviceBytesTotal: deviceBytesTotal,
                                   cacheBypass: cacheBypass,
                                   clock: clock)
        cpuAtOpen = HelperCPUSample.processCPUSeconds()
        wallAtOpen = RunClock.monotonicNanoseconds()
    }

    // MARK: RunObserver

    func runStarted(_ start: RunStart) {
        lock.withLock { inner.runStarted(start) }
    }

    func chunkMeasured(_ chunk: Chunk, measurement: ChunkMeasurement) {
        lock.withLock { inner.chunkMeasured(chunk, measurement: measurement) }
    }

    func failureDetected(_ failure: BlockRangeFailure) -> FailureDisposition {
        lock.withLock { inner.failureDetected(failure) }
    }

    func runFinished(_ summary: RunSummary) {
        lock.withLock { inner.runFinished(summary) }
    }

    // MARK: Reading it

    /// What the run looks like right now, or `nil` before its first call.
    var snapshot: MetricsSnapshot? {
        lock.withLock { inner.snapshot() }
    }

    /// Every failed range the run has produced, coalesced across calls and capped once.
    var failureLog: FailureLog {
        lock.withLock { inner.failureLog }
    }

    /// The FR-TEST-9 verdict as it stands — seeded at acquire, then only ever downgraded by what
    /// the run's own throughput has revealed. **This is what seeds the next call**, which is what
    /// stops a downgrade being forgotten at a call boundary.
    var cacheBypass: CacheBypassAssessment {
        lock.withLock { inner.cacheBypass }
    }

    /// The daemon's CPU over the run so far, as a fraction of one core (BUILD-PLAN 9.5a).
    ///
    /// `nil` when it could not be established — never `0`, which means something else.
    var helperCoreFraction: Double? {
        let wallSeconds = Double(RunClock.monotonicNanoseconds() &- wallAtOpen) / 1_000_000_000
        return HelperCPUSample.coreFraction(from: cpuAtOpen,
                                            to: HelperCPUSample.processCPUSeconds(),
                                            wallSeconds: wallSeconds)
    }
}

// MARK: - Finding it from another connection

/// Where `runProgress` looks for the run in progress.
///
/// This exists because `runProgress` arrives on a *different connection* from the run it is asking
/// about — it has to, because a second message on the run's own connection is not delivered until
/// the run ends (measured 2026-08-04, `scripts/xpc-concurrency-check.sh`). So there is nowhere
/// connection-scoped to look.
///
/// It **owns nothing**. `HelperActivity` is the authority on what the helper holds, and the session
/// is a property of the held claim; this is one indirection with its reasoning attached, kept as a
/// named seam so that reasoning stays attached to something rather than becoming a bare
/// `HelperActivity.shared.heldDevice?.runSession` at the call site.
enum MetricsChannel {

    /// The current run's figures, or `nil` when no device is held or its session has issued no
    /// call yet.
    ///
    /// Two different absences, deliberately reported the same way: in both, no run has measured
    /// anything, and `runProgress` has nothing true to say. What it cannot return is a *previous*
    /// run's figures, because releasing the claim destroyed them.
    static var snapshot: MetricsSnapshot? {
        HelperActivity.shared.heldDevice?.runSession.snapshot
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
