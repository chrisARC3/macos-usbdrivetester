//
//  RunMetrics.swift
//  Core — what a run is doing, accumulated in constant memory and answerable at any instant.
//
//  Step 9 (AI-8), BUILD-PLAN 9.1/9.3/9.6. Satisfies FR-METR-1 (average read and write
//  throughput), FR-METR-3 (per-chunk read latency min/max/p99, via `LatencyHistogram`),
//  FR-METR-5/6 (progress, position and a measured-throughput ETA), and carries NFR-PERF-3's
//  ratio so the requirement finally has a number.
//
//  Pure Foundation. No clock of its own — every entry point is handed the current monotonic
//  reading, so the whole of this file is deterministic under `SteppingClock` and a convergence
//  test needs no hardware and no wall-clock patience.
//
//  ## Three rates, and collapsing them is the easy mistake
//
//  A cycle moves **three times** the range it covers: read the original, write it back, read it
//  again. So there are three genuinely different rates here, and using the wrong one for the
//  ETA would make every estimate about three times too optimistic:
//
//  | Rate | Definition | What it is for |
//  |---|---|---|
//  | ``MetricsSnapshot/readBytesPerSecond`` | bytes read ÷ **time spent reading** | FR-METR-1. The device's read speed. |
//  | ``MetricsSnapshot/writeBytesPerSecond`` | bytes written ÷ **time spent writing** | FR-METR-1. The device's write speed. |
//  | ``MetricsSnapshot/coverageBytesPerSecond`` | range bytes covered ÷ **wall-clock elapsed** | FR-METR-5. How fast the *run* is progressing, and the only correct ETA denominator. |
//
//  Each throughput divides bytes by the time that actually moved those bytes, which is why the
//  timing accumulators below separate successful phases from failed ones. A failed read
//  transferred nothing; folding its duration into the read accumulator would quietly depress a
//  number labelled "read speed" with time in which no reading happened.
//
//  ## Progress advances on failure. It has to.
//
//  A chunk that failed still consumed time and still moved the position, so
//  ``rangeBytesCovered`` and ``currentBlock`` count **attempted** work, not successful work.
//  The alternative — advancing only on success — freezes the progress bar on exactly the drive
//  this tool exists to find, at exactly the moment somebody is watching it. Whether the work
//  *succeeded* is carried separately, by ``chunksFailed`` and the failure log.
//
//  ## What the latency histograms hold, and what they deliberately do not
//
//  A read that failed returned no data. Its duration is a *failure* duration — possibly a long
//  controller retry — and mixing it into a distribution labelled "read latency" would conflate
//  "this drive is slow" with "this drive is broken", which are the two things this tool exists
//  to tell apart. So the histograms hold **only reads that returned data**, and the time spent
//  in failing phases is reported separately as ``failedPhaseNanoseconds`` rather than dropped.
//
//  ## Constant memory (NFR-PERF-7)
//
//  Two `LatencyHistogram`s and about twenty scalars: **35,840 bytes plus change, forever.**
//  ``init(chunksPlanned:deviceBytesTotal:startBlock:startedAtNanoseconds:)`` does take the run's
//  size — but as *numbers*, which allocate nothing. There is no collection here whose length
//  depends on the device, the chunk count, or how long the run has been going.
//
//  ## A RUN IS A SEQUENCE OF BOUNDED CALLS, AND THE SESSION IS THE CLAIM (Step 11, increment 3)
//
//  Everything above was written when one XPC call *was* one run. It is not any more. A
//  whole-device run is ~1,000 calls of at most `TesterProtocol.maximumBytesPerCall`, and the
//  accumulators belong to the **claim** that spans them, not to any one call — see CONSTRAINTS
//  section 2. Three consequences are visible in this file:
//
//    * ``RunSessionObserver`` **folds** each call's `RunStart` into one accumulator instead of
//      replacing it. That single line is the whole mechanical difference, and it is why the type
//      was renamed from `RunMetricsObserver`: it now holds a session, not one call's metrics.
//    * ``MetricsSnapshot/deviceBytesTotal`` — which was `rangeBytesTotal`, one call's range — is
//      the **whole device**, stated once when the session opens from the claim's authoritative
//      ioctl geometry. Progress and the ETA are therefore whole-device, which is the property
//      Shape A was chosen for. The rename is deliberate: a name that said "range" for a value
//      that means "device" is exactly the drift CONSTRAINTS section 3 keeps paying for.
//    * A **true whole-run p99**, because percentiles do not compose and no amount of app-side
//      aggregation of per-call p99s could produce one.
//
//  ``chunksPlanned`` is the one figure that stays denominated in *calls asked for* rather than in
//  the device: the whole-device chunk count is not knowable, because FR-CTRL-8 lets the I/O size
//  change mid-run. So ``MetricsSnapshot/isComplete`` means "every chunk the calls asked for was
//  attempted", while ``MetricsSnapshot/fractionComplete`` means "this much of the device". They
//  answer different questions and are deliberately not derived from each other.
//

import Foundation

//  ``ChunkOutcome`` and ``ChunkMeasurement`` — what this file consumes — live in
//  `RetentionRun.swift`, with the rest of the vocabulary a run reports with.

// MARK: - A latency distribution, summarised

/// `LatencyHistogram`'s answers, flattened into a value that can cross a thread or a wire.
///
/// The histogram itself is 17.5 KiB and is not what a GUI needs sixty times a minute; these six
/// numbers are. Computing them walks 2,240 buckets, which at 1 Hz is free.
public struct LatencySummary: Equatable, Sendable {

    public let count: UInt64
    public let minimumNanoseconds: UInt64?
    public let maximumNanoseconds: UInt64?
    public let meanNanoseconds: UInt64?

    /// The high percentile FR-METR-3 asks for, as the range it honestly is.
    public let p99: LatencyPercentile?

    /// Observations past the histogram's representable range. **Must travel with the
    /// percentile** — a distribution that quietly dropped its tail reads exactly like one that
    /// never had a tail.
    public let overflowCount: UInt64

    public init(_ histogram: LatencyHistogram) {
        count = histogram.count
        minimumNanoseconds = histogram.minimumNanoseconds
        maximumNanoseconds = histogram.maximumNanoseconds
        meanNanoseconds = histogram.meanNanoseconds
        p99 = histogram.percentile(0.99)
        overflowCount = histogram.overflowCount
    }

    /// The empty summary, for a run that has not measured anything yet.
    public static let none = LatencySummary(LatencyHistogram())

    public var isEmpty: Bool { count == 0 }
}

// MARK: - The snapshot

/// What the run looked like at one instant. Immutable, cheap to copy, safe to hand across a
/// thread — which is exactly what the helper does with it once a second.
///
/// Every *rate* here is a computed property rather than a stored one. That is deliberate: a
/// stored rate is a number that was true when it was written, and a snapshot that carried both
/// its inputs and a stale derivation of them would eventually disagree with itself.
public struct MetricsSnapshot: Equatable, Sendable {

    // MARK: The run's shape

    /// Chunks the session's calls have asked for, summed. **Not** a whole-device figure: FR-CTRL-8
    /// lets the I/O size change mid-run, so the device's chunk count is not a fixed number.
    public let chunksPlanned: UInt64

    /// Bytes the **whole device** holds — what progress and the ETA are measured against.
    ///
    /// Was `rangeBytesTotal`, one call's range, until Step 11 made a run a sequence of calls. It
    /// is stated once when the session opens, from the claim's authoritative ioctl geometry, so
    /// it cannot drift between calls.
    public let deviceBytesTotal: UInt64

    /// First block of the run — the session's origin, from its first call.
    public let startBlock: UInt64

    // MARK: Progress — counted on **attempt**, so a failing drive still shows movement

    public let chunksAttempted: UInt64
    public let chunksFailed: UInt64
    public let chunksMismatched: UInt64

    /// Range bytes reached so far, successful or not.
    public let rangeBytesCovered: UInt64

    /// One past the last block reached (FR-METR-6).
    public let currentBlock: UInt64

    // MARK: Volume actually moved

    public let bytesRead: UInt64
    public let bytesWritten: UInt64
    public let bytesVerified: UInt64

    // MARK: Time

    /// Wall-clock since the run started, from the injected monotonic clock.
    public let elapsedNanoseconds: UInt64

    /// Time in reads/writes/verifies **that succeeded**, so each pairs with its byte counter.
    public let readNanoseconds: UInt64
    public let writeNanoseconds: UInt64
    public let verifyNanoseconds: UInt64

    /// Time in phases that failed. Reported rather than folded into the rates above, so a
    /// number labelled "read speed" is not depressed by time in which no reading happened.
    public let failedPhaseNanoseconds: UInt64

    /// Host work — compare, metrics, bookkeeping. NFR-PERF-3's numerator.
    public let hostOverheadNanoseconds: UInt64

    // MARK: Latency (FR-METR-3)

    public let readLatency: LatencySummary
    public let verifyLatency: LatencySummary

    public init(chunksPlanned: UInt64,
                deviceBytesTotal: UInt64,
                startBlock: UInt64,
                chunksAttempted: UInt64,
                chunksFailed: UInt64,
                chunksMismatched: UInt64,
                rangeBytesCovered: UInt64,
                currentBlock: UInt64,
                bytesRead: UInt64,
                bytesWritten: UInt64,
                bytesVerified: UInt64,
                elapsedNanoseconds: UInt64,
                readNanoseconds: UInt64,
                writeNanoseconds: UInt64,
                verifyNanoseconds: UInt64,
                failedPhaseNanoseconds: UInt64,
                hostOverheadNanoseconds: UInt64,
                readLatency: LatencySummary,
                verifyLatency: LatencySummary) {
        self.chunksPlanned = chunksPlanned
        self.deviceBytesTotal = deviceBytesTotal
        self.startBlock = startBlock
        self.chunksAttempted = chunksAttempted
        self.chunksFailed = chunksFailed
        self.chunksMismatched = chunksMismatched
        self.rangeBytesCovered = rangeBytesCovered
        self.currentBlock = currentBlock
        self.bytesRead = bytesRead
        self.bytesWritten = bytesWritten
        self.bytesVerified = bytesVerified
        self.elapsedNanoseconds = elapsedNanoseconds
        self.readNanoseconds = readNanoseconds
        self.writeNanoseconds = writeNanoseconds
        self.verifyNanoseconds = verifyNanoseconds
        self.failedPhaseNanoseconds = failedPhaseNanoseconds
        self.hostOverheadNanoseconds = hostOverheadNanoseconds
        self.readLatency = readLatency
        self.verifyLatency = verifyLatency
    }

    // MARK: - Derived: throughput (FR-METR-1)

    private static func rate(bytes: UInt64, nanoseconds: UInt64) -> Double? {
        guard bytes > 0, nanoseconds > 0 else { return nil }
        return Double(bytes) / (Double(nanoseconds) / 1_000_000_000)
    }

    /// The **device's** read speed: bytes read ÷ time spent reading.
    public var readBytesPerSecond: Double? {
        Self.rate(bytes: bytesRead, nanoseconds: readNanoseconds)
    }

    /// The **device's** write speed.
    public var writeBytesPerSecond: Double? {
        Self.rate(bytes: bytesWritten, nanoseconds: writeNanoseconds)
    }

    /// The verify read's speed. Diagnostic — a verify markedly faster than the original read is
    /// what a drive-side cache looks like (FR-TEST-9's neighbourhood).
    public var verifyBytesPerSecond: Double? {
        Self.rate(bytes: bytesVerified, nanoseconds: verifyNanoseconds)
    }

    /// How fast the **run** is covering its range, against the wall clock. About a third of the
    /// read speed, because every covered byte is read, written and read again — and **this is
    /// the only correct ETA denominator**.
    public var coverageBytesPerSecond: Double? {
        Self.rate(bytes: rangeBytesCovered, nanoseconds: elapsedNanoseconds)
    }

    // MARK: - Derived: progress and ETA (FR-METR-5/6, NFR-PERF-6)

    /// How much of the **device** this session has covered, `0...1`. Zero for an empty device
    /// rather than undefined.
    ///
    /// Whole-device from Step 11: covered bytes accumulate across every call in the session, and
    /// the denominator is the device. A caller that runs a bounded region therefore sees the
    /// fraction of the *drive* it covered, which is the true statement — not 100% of the piece it
    /// asked for.
    public var fractionComplete: Double {
        guard deviceBytesTotal > 0 else { return 0 }
        return Swift.min(1, Double(rangeBytesCovered) / Double(deviceBytesTotal))
    }

    /// Remaining wall-clock, from **measured** throughput only — never from a link speed
    /// (NFR-COMPAT-7).
    ///
    /// `nil` until there is something to extrapolate from, because an ETA invented before the
    /// first chunk is a number with no evidence behind it. Converges by construction: the
    /// estimate is `elapsed × remaining ÷ covered`, and `remaining` goes to zero.
    public var estimatedRemainingNanoseconds: UInt64? {
        guard deviceBytesTotal > 0 else { return nil }
        guard rangeBytesCovered < deviceBytesTotal else { return 0 }
        guard rangeBytesCovered > 0, elapsedNanoseconds > 0 else { return nil }

        let remaining = Double(deviceBytesTotal - rangeBytesCovered)
        // `Double` rather than integer arithmetic: `elapsed × remaining` overflows `UInt64` on
        // any real device, and 53 bits of mantissa is exact to ~104 days of nanoseconds.
        let estimate = Double(elapsedNanoseconds) * remaining / Double(rangeBytesCovered)
        return estimate.isFinite && estimate >= 0 ? UInt64(estimate) : nil
    }

    // MARK: - Derived: NFR-PERF-3

    /// Time the **device** was busy: every phase, successful or not.
    public var deviceNanoseconds: UInt64 {
        readNanoseconds &+ writeNanoseconds &+ verifyNanoseconds &+ failedPhaseNanoseconds
    }

    /// **The number NFR-PERF-3 has never had.** Host work as a fraction of device I/O time.
    ///
    /// The requirement says throughput shall be *device-bound, not host-bound* — that "the
    /// per-chunk compare, metrics, and bookkeeping overhead shall remain negligible relative to
    /// the wall-clock time of the underlying raw read → write → read I/O". This is that ratio,
    /// measured in the product's own run path rather than inferred from a CPU percentage.
    ///
    /// `nil` before any I/O has been timed.
    public var hostOverheadFraction: Double? {
        let device = deviceNanoseconds
        guard device > 0 else { return nil }
        return Double(hostOverheadNanoseconds) / Double(device)
    }

    /// Wall-clock this run has not accounted for — scheduling, XPC, anything outside the
    /// measured phases. Never negative: a clock that appeared to run backwards yields zero.
    ///
    /// Exposed because it is the honest completeness check on the two figures above. If this
    /// were large, `hostOverheadFraction` would be measuring a fraction of the story.
    public var unaccountedNanoseconds: UInt64 {
        let accounted = deviceNanoseconds &+ hostOverheadNanoseconds
        return elapsedNanoseconds > accounted ? elapsedNanoseconds - accounted : 0
    }

    /// Every planned chunk was attempted.
    public var isComplete: Bool {
        chunksPlanned > 0 && chunksAttempted >= chunksPlanned
    }
}

// MARK: - The accumulator

/// Accumulates a run's metrics in constant memory, and answers with a ``MetricsSnapshot`` at
/// any instant.
///
/// Not thread-safe, deliberately — the same contract `ChunkBuffers` and `LatencyHistogram`
/// document. A run drives one device from one task; publishing a snapshot across threads is the
/// helper's job, and Core stays free of concurrency primitives.
public struct RunMetrics {

    // The run's shape. Numbers, not storage — nothing here allocates per chunk or per byte.

    /// Chunks the session's calls have asked for so far. A `var` because a run is a sequence of
    /// calls and each one adds its own plan — see ``extendPlan(byChunks:)``.
    public private(set) var chunksPlanned: UInt64
    public let deviceBytesTotal: UInt64
    public let startBlock: UInt64
    private let startedAtNanoseconds: UInt64

    private var chunksAttempted: UInt64 = 0
    private var chunksFailed: UInt64 = 0
    private var chunksMismatched: UInt64 = 0
    private var rangeBytesCovered: UInt64 = 0
    private var currentBlock: UInt64

    private var bytesRead: UInt64 = 0
    private var bytesWritten: UInt64 = 0
    private var bytesVerified: UInt64 = 0

    private var readNanoseconds: UInt64 = 0
    private var writeNanoseconds: UInt64 = 0
    private var verifyNanoseconds: UInt64 = 0
    private var failedPhaseNanoseconds: UInt64 = 0
    private var hostOverheadNanoseconds: UInt64 = 0

    private var readLatency = LatencyHistogram()
    private var verifyLatency = LatencyHistogram()

    /// - Parameters:
    ///   - chunksPlanned: how many chunks the session's first call contains. Later calls add
    ///     theirs through ``extendPlan(byChunks:)``.
    ///   - deviceBytesTotal: the **whole device**, counted **once** — not the 3× the cycle moves,
    ///     and not the range of any one call. This is what progress and the ETA divide by.
    ///   - startBlock: the session's first block, so ``MetricsSnapshot/currentBlock`` starts
    ///     somewhere real.
    ///   - startedAtNanoseconds: the injected clock's reading at run start. No clock is called here.
    public init(chunksPlanned: UInt64,
                deviceBytesTotal: UInt64,
                startBlock: UInt64,
                startedAtNanoseconds: UInt64) {
        self.chunksPlanned = chunksPlanned
        self.deviceBytesTotal = deviceBytesTotal
        self.startBlock = startBlock
        self.startedAtNanoseconds = startedAtNanoseconds
        self.currentBlock = startBlock
    }

    /// Add a further call's chunk plan to the session's total.
    ///
    /// The counterpart of a run being a sequence of bounded calls: each one plans its own chunks,
    /// and ``MetricsSnapshot/isComplete`` is only meaningful against the sum. `&+=` for the same
    /// reason every other counter in this type uses it — a root daemon does not trap — and the
    /// overflow it guards against is unreachable: the largest drive here, the 4 TB T5 EVO at
    /// 7,814,037,168 blocks, is about 3.8 million chunks at the smallest I/O size, against a
    /// 2⁶⁴ counter.
    public mutating func extendPlan(byChunks chunks: UInt64) {
        chunksPlanned &+= chunks
    }

    /// Fold one chunk's measurement in. Constant time, no allocation.
    ///
    /// Which numbers a measurement contributes to is decided by its ``ChunkMeasurement/outcome``
    /// and never by whether a duration happens to be present — so a phase that failed in an
    /// unmeasurably short time cannot be mistaken for a phase that never ran.
    public mutating func record(_ measurement: ChunkMeasurement) {
        let bytes = UInt64(Swift.max(0, measurement.byteLength))

        // Progress advances on attempt, including failure. See the note at the top of the file.
        chunksAttempted &+= 1
        rangeBytesCovered &+= bytes
        currentBlock = measurement.endBlock

        if measurement.outcome.isPhaseFailure { chunksFailed &+= 1 }
        if measurement.outcome == .verifyMismatch { chunksMismatched &+= 1 }

        hostOverheadNanoseconds &+= measurement.hostOverheadNanoseconds

        // The read. It succeeded unless the outcome says it was the read that failed.
        if let duration = measurement.readNanoseconds {
            if measurement.outcome == .failedReading {
                failedPhaseNanoseconds &+= duration
            } else {
                readNanoseconds &+= duration
                bytesRead &+= bytes
                readLatency.record(nanoseconds: duration)
            }
        }

        // The write.
        if let duration = measurement.writeNanoseconds {
            if measurement.outcome == .failedWriting {
                failedPhaseNanoseconds &+= duration
            } else {
                writeNanoseconds &+= duration
                bytesWritten &+= bytes
            }
        }

        // The verify read.
        if let duration = measurement.verifyNanoseconds {
            if measurement.outcome == .failedVerifying {
                failedPhaseNanoseconds &+= duration
            } else {
                verifyNanoseconds &+= duration
                bytesVerified &+= bytes
                verifyLatency.record(nanoseconds: duration)
            }
        }
    }

    /// What the run looks like right now.
    ///
    /// - Parameter nanoseconds: the injected clock's current reading. A reading earlier than the
    ///   run's start yields zero elapsed rather than an underflowed `UInt64` — the clock is
    ///   monotonic, but a metrics type is not the place to find that out the hard way.
    public func snapshot(atNanoseconds nanoseconds: UInt64) -> MetricsSnapshot {
        let elapsed = nanoseconds > startedAtNanoseconds
            ? nanoseconds - startedAtNanoseconds
            : 0

        return MetricsSnapshot(chunksPlanned: chunksPlanned,
                               deviceBytesTotal: deviceBytesTotal,
                               startBlock: startBlock,
                               chunksAttempted: chunksAttempted,
                               chunksFailed: chunksFailed,
                               chunksMismatched: chunksMismatched,
                               rangeBytesCovered: rangeBytesCovered,
                               currentBlock: currentBlock,
                               bytesRead: bytesRead,
                               bytesWritten: bytesWritten,
                               bytesVerified: bytesVerified,
                               elapsedNanoseconds: elapsed,
                               readNanoseconds: readNanoseconds,
                               writeNanoseconds: writeNanoseconds,
                               verifyNanoseconds: verifyNanoseconds,
                               failedPhaseNanoseconds: failedPhaseNanoseconds,
                               hostOverheadNanoseconds: hostOverheadNanoseconds,
                               readLatency: LatencySummary(readLatency),
                               verifyLatency: LatencySummary(verifyLatency))
    }

    /// Buckets held by the two histograms. Asserted by the tests: this is the claim that the
    /// accumulator does not grow with the length of the run.
    public var allocatedBucketCount: Int {
        readLatency.allocatedBucketCount + verifyLatency.allocatedBucketCount
    }
}

// MARK: - Driving the accumulators from a run's sequence of calls

/// The `RunObserver` that accumulates **one run** across the sequence of bounded calls it is made
/// of (Step 11, CONSTRAINTS section 2).
///
/// A class, because `RunObserver` is `AnyObject`-bound and because the helper needs to read the
/// accumulating snapshot from *outside* the run — that is the whole point of a live display.
/// The accumulators themselves stay value types; this owns them.
///
/// ## What it accumulates, and why each one has to be here rather than in the caller
///
/// | | why it cannot be aggregated per call |
/// |---|---|
/// | ``metrics`` | percentiles do not compose, so no app-side combination of per-call p99s is a whole-run p99 (FR-METR-3, FR-RPT-3). The coverage rate and the ETA need one origin for the same reason. |
/// | ``failures`` | `FailureLog`'s cap must apply **once per run**, or its truncation notice means "this call listed a thousand" on a drive with a million bad blocks (FR-RPT-1). |
/// | ``cacheBypass`` | the assessment's whole contract is that it **only ever downgrades**. Re-seeding it per call silently promotes it back, so a `likelyCached` verdict earned at 40% of a drive is gone by 41% (FR-TEST-9). |
///
/// ## `runStarted` folds; it does not replace
///
/// This is the single mechanical difference from the per-call accumulator that preceded it, and
/// it is the whole increment. The engine fires `runStarted` once per XPC call, so *replacing* the
/// accumulator — which is what this type did until Step 11 — wipes the run at every call boundary
/// and leaves a whole-device run reporting the last gibibyte's figures as its own.
///
/// ## Thread-safety is not here, deliberately
///
/// Core holds no locks (`ChunkBuffers`, `LatencyHistogram` and `RunMetrics` all document the
/// same contract: one run, one task). Publishing a snapshot to a *reader on another thread* is
/// the helper's job, because that is where the concurrency lives and where a lock belongs.
/// Reading ``snapshot(atNanoseconds:)`` from another thread while a run is in progress is a data
/// race — the helper's `RunSession` is what makes it safe.
public final class RunSessionObserver: RunObserver {

    /// `nil` until the session's **first** ``runStarted(_:)`` arrives — a run that has issued no
    /// call has measured nothing, and an accumulator invented with guessed totals would report a
    /// percentage of the wrong thing. Every later `runStarted` extends this one.
    public private(set) var metrics: RunMetrics?

    /// Every failed range the **whole run** produced, coalesced and capped once.
    ///
    /// Kept open across calls: ``FailureLog/finish()`` is deliberately *not* called here, so the
    /// range still pending at a call boundary can coalesce with the first failure of the next
    /// call. A contiguous bad region spanning two calls is one range, not two. ``failureLog``
    /// finishes a **copy**, which is what lets that be true and still be readable at any instant.
    private var failures = FailureLog()

    /// The FR-TEST-9 verdict for the run so far.
    ///
    /// Seeded when the session opens, from what the acquire structurally established about the
    /// descriptor, and then replaced by each call's own final verdict — so a downgrade earned by
    /// one call is what the next call starts from. Non-optional precisely so there is no call
    /// site that could reach for a fresh seed instead.
    public private(set) var cacheBypass: CacheBypassAssessment

    /// The whole device, in bytes — what progress and the ETA divide by. Stated once, when the
    /// session opens, from the claim's authoritative ioctl geometry.
    private let deviceBytesTotal: UInt64

    /// The reading to stamp the run's start with — the *same* injected clock the engine uses,
    /// so a test can drive both from one `SteppingClock` and get an exact elapsed time.
    private let clock: MonotonicClock

    /// - Parameters:
    ///   - deviceBytesTotal: the held device's capacity. **Required, with no default**, for the
    ///     reason `control:` is required on the engine: a session that silently measured progress
    ///     against nothing would report `0` forever, and the first place anyone would find out is
    ///     a progress bar that never moves on a run that is working perfectly.
    ///   - cacheBypass: the FR-TEST-9 verdict the acquire established. Also required — a session
    ///     that seeded itself would be a second place the verdict comes from, and the whole point
    ///     of holding it here is that there is exactly one.
    public init(deviceBytesTotal: UInt64,
                cacheBypass: CacheBypassAssessment,
                clock: @escaping MonotonicClock = RunClock.monotonicNanoseconds) {
        self.deviceBytesTotal = deviceBytesTotal
        self.cacheBypass = cacheBypass
        self.clock = clock
    }

    /// Begin the session on the first call, and **extend** it on every one after.
    public func runStarted(_ start: RunStart) {
        guard metrics != nil else {
            metrics = RunMetrics(chunksPlanned: start.chunkCount,
                                 deviceBytesTotal: deviceBytesTotal,
                                 startBlock: start.startBlock,
                                 startedAtNanoseconds: clock())
            return
        }
        metrics?.extendPlan(byChunks: start.chunkCount)
    }

    public func chunkMeasured(_ chunk: Chunk, measurement: ChunkMeasurement) {
        metrics?.record(measurement)
    }

    /// Record the failure against the **run**, and decide nothing.
    ///
    /// `.continueRun` is the neutral answer of an observer that only watches, exactly as
    /// `RunLogger.failureDetected` returns it: `FailureModeObserver` is what obeys FR-FAIL-1, and
    /// `ObserverFanOut`'s stop-wins rule is what makes a neutral answer safe. A recorder that
    /// could also stop a run would be two decisions in one place.
    public func failureDetected(_ failure: BlockRangeFailure) -> FailureDisposition {
        failures.record(failure)
        return .continueRun
    }

    /// Carry this call's final FR-TEST-9 verdict into the session, so the next call is seeded with
    /// it rather than with the acquire-time structural verdict.
    ///
    /// A call that **throws** never reaches here, and that is correct rather than a gap: a throw
    /// is a `RunAbort` — this tool's fault, not the drive's — the call is refused, and a refused
    /// call reports nothing. The session keeps the last verdict a completed call established.
    public func runFinished(_ summary: RunSummary) {
        cacheBypass = summary.cacheBypass
    }

    /// The run's failures as they stand, with the pending range closed.
    ///
    /// Finishes a **copy**: closing the real one would end the coalescing at whatever instant a
    /// caller happened to look, turning one contiguous bad region into two ranges because
    /// somebody polled in the middle of it.
    public var failureLog: FailureLog {
        var closed = failures
        closed.finish()
        return closed
    }

    /// What the run looks like now, or `nil` before its first call.
    public func snapshot() -> MetricsSnapshot? {
        metrics?.snapshot(atNanoseconds: clock())
    }

    /// What the run looked like at a given reading. For tests driving a deterministic clock.
    public func snapshot(atNanoseconds nanoseconds: UInt64) -> MetricsSnapshot? {
        metrics?.snapshot(atNanoseconds: nanoseconds)
    }
}
