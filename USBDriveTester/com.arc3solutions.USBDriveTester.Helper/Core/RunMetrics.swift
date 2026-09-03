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
//  ## The rates, their denominators, and picking the wrong denominator is the easy mistake
//
//  A cycle moves **three times** the range it covers: read the original, write it back, read it
//  again. That alone makes several genuinely different rates, but the division that actually
//  matters is *what each one is divided by*.
//
//  **The heading used to carry a count and the count was wrong.** It read "Five rates" over a
//  six-row table before Step 11 increment 11, and that increment made it "Six" over seven. A
//  number in prose that nothing asserts drifts, and this one drifted through two edits without
//  being noticed; CONSTRAINTS section 3 is the standing rule it broke. It is gone rather than
//  corrected, because correcting it would only restart the clock.
//
//  | Rate | Definition | What it is for |
//  |---|---|---|
//  | ``MetricsSnapshot/readBytesPerSecond`` | bytes read ÷ **time spent reading** | The original read's speed, alone. Diagnostic; logged, never displayed — the displayed figure pools it with the verify. |
//  | ``MetricsSnapshot/writeBytesPerSecond`` | bytes written ÷ **time spent writing** | FR-METR-1. **What the app shows as `Write`**. |
//  | ``MetricsSnapshot/verifyBytesPerSecond`` | bytes verified ÷ **time spent verifying** | A verify much faster than the original read is what a drive-side cache looks like. |
//  | ``MetricsSnapshot/deviceReadBytesPerSecond`` | (bytes read + bytes verified) ÷ **time spent on both reads** | FR-METR-1. **What the app shows as `Read`**. |
//  | ``MetricsSnapshot/completedBytesPerSecond`` | bytes in chunks that **matched** ÷ **time spent in successful phases** | **What the app shows as `R-W-R-C speed`**. Successful work per second of I/O, where the two above are per second of *their own* I/O. |
//  | ``MetricsSnapshot/sustainedReadBytesPerSecond`` | (bytes read + bytes verified) ÷ **running time** | What Activity Monitor shows. Diagnostic; logged, never displayed. |
//  | ``MetricsSnapshot/sustainedWriteBytesPerSecond`` | bytes written ÷ **running time** | What Activity Monitor shows. Diagnostic; logged, never displayed. |
//  | ``MetricsSnapshot/coverageBytesPerSecond`` | range bytes covered ÷ **running time** | FR-METR-5. How fast the *run* is progressing, and the only correct ETA denominator. On the wire, displayed nowhere. |
//
//  ## THE THREE DISPLAYED RATES SATISFY AN EXACT IDENTITY (2026-09-02)
//
//  Because all three now divide by phase time, they are tied together by arithmetic rather than
//  by a tolerance band. On a run where every chunk completes, with covered bytes *B* and phase
//  times *r*, *w* and *v*:
//
//      Read     = 2B / (r + v)          R-W-R-C  = B / (r + w + v)
//      Write    =  B / w
//
//  and therefore, by substitution and with no approximation anywhere:
//
//      1 / R-W-R-C  =  2 / Read  +  1 / Write
//
//  ``aCleanRunSatisfiesTheReciprocalIdentity`` asserts it. This **replaces** the `read ≈ 2 ×
//  covering, write ≈ 1 × covering` band that `metrics-check.sh` carried from increment 5, and is
//  strictly better in three ways: it is an equality rather than a ±10–20% window, it relates the
//  figures the user can actually see rather than tying them to `coverageBytesPerSecond` — which
//  is on no screen — and it is checkable in a unit test, where the band needed hardware.
//
//  **It breaks in exactly one direction, and that is the point.** A ``ChunkOutcome/verifyMismatch``
//  contributes to *r*, *w*, *v*, `Read` and `Write` but not to ``MetricsSnapshot/bytesCompleted``,
//  so R-W-R-C falls **below** what the other two predict. A chunk that fails its read or its write
//  contributes to none of them — its time goes to ``MetricsSnapshot/failedPhaseNanoseconds`` — so
//  the identity still holds and the failed-block list is what describes that run. The residual is
//  therefore a retention signal specifically, not a general failure signal.
//
//  The first five divide bytes by the time that actually moved those bytes, which is why the
//  timing accumulators below separate successful phases from failed ones. A failed read
//  transferred nothing; folding its duration into the read accumulator would quietly depress a
//  number labelled "read speed" with time in which no reading happened.
//
//  ## RUNNING time, and why the ETA still divides by it (2026-08-18, amended 2026-09-02)
//
//  **Read this section for `coverageBytesPerSecond` and the ETA.** It was written when the
//  displayed rates divided by running time too; they no longer do (see the reversal below), but
//  every word of it still governs the two quantities that do, and the two denominators it refutes
//  are refuted for those as well.
//
//  ``runningNanoseconds`` — the wall clock from the run's start to the end of its last call,
//  **minus the gaps between calls**. Not ``elapsedNanoseconds``, and not device-plus-host either.
//  Both of those were tried on hardware and both were wrong, in opposite directions.
//
//  `metrics-check.sh` is what forced this, on hardware, and no unit test could have. Elapsed is
//  `now - start` evaluated at snapshot time, so it keeps growing after a call ends. The gate
//  polls after the reply and compares: the same bytes over a bigger denominator gave 270.5 MB/s
//  in the reply and 258.2 MB/s from a poll 1.51 s later. Twelve failures, one cause.
//
//  Three things were wrong, and only the first was visible:
//
//    1. The reply and a later poll disagreed about the same run.
//    2. A finished run's rate **decayed on screen** while the claim was held and nothing ran.
//    3. A **paused** run's rate decayed and its ETA inflated — `elapsed x remaining / covered`
//       grows without bound while paused. That one predates this change: the ETA has divided by
//       live elapsed since Step 9, and nothing displayed coverage, so nobody could see it.
//
//  **Device-plus-host was the second attempt.** It is stable and it excludes a pause, so it very
//  nearly worked — but it also excludes the scheduling inside a call that an outside observer
//  does count, and on `disk10` that put it **1.35% above** the call's true wall-clock rate
//  (161.1 MB/s covering against 159.0). Small, but in the direction this change exists to fix,
//  and a figure that is high by construction will be high by more on slower hardware.
//
//  Read the three against **the reply's own wall clock on the first call**, where no inter-call
//  gap yet exists and so the comparison is clean:
//
//      wall clock, at the reply        159.0 MB/s   —
//      wall clock, at a later poll     133.2 MB/s   -16.2%   <- the defect
//      device + host overhead          161.1 MB/s    +1.35%
//      wall clock - inter-call gaps    158.8 MB/s    -0.11%   <- this
//
//  A warning about that table, because it cost a wrong conclusion: **133.2 is not a baseline.**
//  It is the broken poll, inflated by the 1.31 s between the call ending and the poll being
//  taken. Comparing against it made device-plus-host look 19% high when it was 1.35% high.
//
//  So the denominator excludes exactly one thing: **time between calls**. That is where a pause
//  lives — a paused run's call returns and the next does not begin until the user resumes — and
//  it is the only span in which the drive is genuinely doing nothing on this run's behalf.
//  Everything inside a call stays in, so a rate means the same thing an outside observer's does.
//
//  Two properties follow, and `metrics-check.sh` asserts both:
//
//    * **Ask twice, get the same answer.** Once the last call ends the numerator and denominator
//      are both fixed, so a reply and a poll after it agree bit-for-bit.
//    * **A pause costs nothing.** The gap is subtracted when the next call starts, so a run that
//      waited half an hour reports the throughput it actually achieved.
//
//  ``elapsedNanoseconds`` is kept as the true wall clock, because it is what makes
//  ``unaccountedNanoseconds`` mean anything.
//
//  ## THE DISPLAYED RATES WENT BACK TO PHASE TIME (FR-METR-1 amended 2026-09-02)
//
//  **This reverses the decision the section above was written to justify, and the reversal is a
//  requirement change rather than a bug fix.** The history matters, because without it the record
//  reads as a loop.
//
//  On 2026-08-17 the app divided read and write by phase time and it was reported as a **bug**.
//  Measured on the 4 TB T5 EVO, the helper logged `read 375.8 MB/s, write 418.9 MB/s, covering
//  122.4 MB/s`, while DriveSpeed and Activity Monitor — which agreed with each other exactly —
//  showed about 245 and 122. Our read looked 53% high and our write **3.4×** high. Nothing was
//  wrong with the arithmetic: every other tool on the machine divides by the wall clock, because
//  that is the only denominator an outside observer has. Dividing by phase time meant our "write
//  speed" described the drive during the ~29% of the run it was writing and silently omitted the
//  rest. The figures were correct answers to a question nobody had asked. That became protocol
//  v12 at `1a10438`.
//
//  **What changed on 2026-09-02 was the question.** The 2026-08-18 complaint was that the figures
//  did not reconcile with other tools; matching them was adopted as the objective. Reconciling
//  with Activity Monitor is no longer an objective of this product. A tool that exists to
//  characterise a *device* should report what the device did while it was working — a drive that
//  writes at 419 MB/s and spends 29% of the run writing has a write speed of 419 MB/s, and
//  reporting 122 tells the user about this program's duty cycle, not about their hardware. The
//  duty-cycle figure is the one that omits something.
//
//  So the same three quantities are on screen and each divides by the time that moved its own
//  bytes. **The 3.4× is still there and is still real — it is now the intended reading, and the
//  displayed figures are disclaimed against external comparison instead of aiming at it.**
//  `ThroughputFraming.definition` is where that disclaimer lives, and it is the load-bearing part
//  of this change: an undisclaimed figure 3.4× what another window shows is how this started.
//
//  The relationship the sustained pair satisfies is kept, because it is still true and still a
//  check on the accounting:
//
//      sustained read ≈ 2 × covering        (the original read and the verify read)
//      sustained write ≈ 1 × covering       (one write per covered byte)
//
//  On the measurement above: 2 × 122.4 = 244.8 and 1 × 122.4 = 122.4, which is what the two
//  independent tools showed. It is no longer what `metrics-check.sh` asserts on the displayed
//  figures — the reciprocal identity at the top of this file is — because these three quantities
//  now reach no screen.
//
//  **The roles simply swapped, and the earlier hazard swapped with them.** The sustained rates
//  are now what the phase rates were: computed, tested, logged every call by `RunCoordinator`,
//  and off the wire. That is a deliberate repeat of an arrangement this file warns about — a
//  measurement that is not on the wire does not exist as far as the user is concerned — and it is
//  accepted here for the same reason `coverageBytesPerSecond` is not: nothing displays them, and
//  a wire field with no consumer is the other half of the same trap.
//
//  ## Progress advances on failure. It has to.
//
//  A chunk that failed still consumed time and still moved the position, so
//  ``rangeBytesCovered`` and ``currentBlock`` count **attempted** work, not successful work.
//  The alternative — advancing only on success — freezes the progress bar on exactly the drive
//  this tool exists to find, at exactly the moment somebody is watching it. Whether the work
//  *succeeded* is carried separately, by ``chunksFailed`` and the failure log.
//
//  ## And successful work is counted separately, because the two used to share a label
//
//  ``bytesCompleted`` is the counterpart: bytes in chunks whose outcome is ``ChunkOutcome/completed``
//  and nothing else. It exists because a figure derived from ``rangeBytesCovered`` was displayed as
//  `Covering` under a label that read as successful work, and the gap between the two shows only on
//  a failing drive — the one occasion anyone reads the number closely. That row was deleted in Step
//  11 increment 10; this is the quantity it should have been, added in increment 11 as the app's
//  `R-W-R-C speed`.
//
//  **Only ``ChunkOutcome/completed`` counts, and the exclusion that matters is
//  ``ChunkOutcome/verifyMismatch``.** That outcome ran all four steps and the compare failed — it is
//  a *data* failure, not an I/O one, so it is deliberately **not** an ``ChunkOutcome/isPhaseFailure``
//  and it contributes to every rate and both histograms above. A counter written as
//  `!outcome.isPhaseFailure` would therefore score a retention failure — the thing this tool exists
//  to find — as success. Test the case, do not negate the other one.
//
//  On a drive where nothing fails this **counter** equals ``bytesWritten`` exactly, because a cycle
//  writes each covered byte once and every chunk matches.
//
//  **The displayed rates no longer inherit that equality, and that is the 2026-09-02 change's one
//  real cost.** Increment 11 shipped `R-W-R-C speed` on the argument that it read identically to
//  `Write` on a healthy drive and that a divergence therefore meant something. It divided by
//  running time then, and `Write` did too. Both now divide by their own phase time, and a
//  per-cycle rate against a per-phase rate is roughly a third of it: on the 4 TB T5 EVO figures
//  above a **flawless** run reads about `Read 376, Write 419, R-W-R-C 130`. The row looks alarming
//  on hardware with nothing wrong with it, which is precisely the shape of the 2026-08-17 report.
//  What replaces the equality is the reciprocal identity at the top of this file — weaker to read
//  off a panel by eye, stronger as a check, and the prose on both surfaces has to carry it.
//
//  **The two gaps are different sizes and only one of them is on screen** — worth knowing before
//  reading a panel, and derived from the branches in ``record(_:)`` rather than assumed:
//
//      covered - completed  =  every outcome but `.completed`
//      written - completed  =  `.verifyMismatch` and `.failedVerifying` only
//
//  A chunk that failed its *read* or its *write* holds both counters back equally, so it moves Write
//  and `R-W-R-C speed` down together. The two part only where the write **succeeded and the chunk
//  still did not end clean**: the verify could not be read, or it read back different bytes. Since
//  `Covering` is displayed nowhere, that narrower gap is the one a user can actually see, and it is
//  the more interesting of the two — it is bytes this drive accepted and could not then confirm.
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

    /// Bytes in chunks that completed **and matched** — successful work, where
    /// ``rangeBytesCovered`` above is attempted work.
    ///
    /// Counts ``ChunkOutcome/completed`` and nothing else. ``ChunkOutcome/verifyMismatch`` moved
    /// every byte and failed the compare, so it is excluded here while still contributing to
    /// ``bytesRead``, ``bytesWritten`` and ``bytesVerified``. See the file header: a counter
    /// written as `!isPhaseFailure` would score a retention failure as success.
    public let bytesCompleted: UInt64

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

    /// Wall clock in which **no call was running** — the gaps between one call and the next, and
    /// therefore any time the run spent paused (FR-CTRL-3).
    ///
    /// Subtracted from ``elapsedNanoseconds`` to give ``runningNanoseconds``. Carried separately
    /// rather than pre-subtracted so that a reader can still see the run's true wall clock, and
    /// so ``unaccountedNanoseconds`` keeps meaning what it says.
    public let idleNanoseconds: UInt64

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
                bytesCompleted: UInt64,
                elapsedNanoseconds: UInt64,
                readNanoseconds: UInt64,
                writeNanoseconds: UInt64,
                verifyNanoseconds: UInt64,
                failedPhaseNanoseconds: UInt64,
                hostOverheadNanoseconds: UInt64,
                idleNanoseconds: UInt64 = 0,
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
        self.bytesCompleted = bytesCompleted
        self.elapsedNanoseconds = elapsedNanoseconds
        self.readNanoseconds = readNanoseconds
        self.writeNanoseconds = writeNanoseconds
        self.verifyNanoseconds = verifyNanoseconds
        self.failedPhaseNanoseconds = failedPhaseNanoseconds
        self.hostOverheadNanoseconds = hostOverheadNanoseconds
        self.idleNanoseconds = idleNanoseconds
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

    /// **What the app displays as `Write`** (FR-METR-1, amended 2026-09-02): the device's write
    /// speed — bytes written ÷ the time spent writing them.
    ///
    /// Unchanged since Step 9; what changed is that it reaches a screen. It was displayed until
    /// 2026-08-18, replaced by ``sustainedWriteBytesPerSecond`` after a bug report, and restored
    /// when the requirement was amended. The file header carries why that is not a loop.
    public var writeBytesPerSecond: Double? {
        Self.rate(bytes: bytesWritten, nanoseconds: writeNanoseconds)
    }

    /// The verify read's speed. Diagnostic — a verify markedly faster than the original read is
    /// what a drive-side cache looks like (FR-TEST-9's neighbourhood).
    ///
    /// Pooled into ``deviceReadBytesPerSecond`` for display, so a caching drive raises the
    /// displayed `Read` rather than showing up on its own. That signal is visible here and in
    /// `RunCoordinator`'s log line, and nowhere the user looks.
    public var verifyBytesPerSecond: Double? {
        Self.rate(bytes: bytesVerified, nanoseconds: verifyNanoseconds)
    }

    /// **What the app displays as `Read`** (FR-METR-1, amended 2026-09-02): every byte this run
    /// read — the original read *and* the verify read — ÷ the time spent on both.
    ///
    /// Both reads are counted because both are reads, and a figure that omitted the verify would
    /// silently describe half the reading the run performed. Both *times* are counted for the
    /// same reason: pairing pooled bytes with one phase's duration is the arithmetic error this
    /// whole area of the file exists to prevent.
    ///
    /// Distinct from ``readBytesPerSecond``, which is the original read alone. The two differ
    /// only when the verify runs at a different speed from the first read — which is what a
    /// drive-side cache looks like, so they are kept separate rather than one being derived.
    public var deviceReadBytesPerSecond: Double? {
        Self.rate(bytes: bytesRead &+ bytesVerified,
                  nanoseconds: readNanoseconds &+ verifyNanoseconds)
    }

    /// Every byte read ÷ ``runningNanoseconds``. **What Activity Monitor shows**, and displayed
    /// nowhere since 2026-09-02.
    ///
    /// About 2 × ``coverageBytesPerSecond`` on a healthy drive; markedly less means reads are
    /// failing. Kept because that relationship is a check on the accounting and because "the
    /// drive is slow while it works" and "the drive spends a long time not working" are different
    /// faults — this tool exists to tell faults apart. `RunCoordinator` logs it every call.
    public var sustainedReadBytesPerSecond: Double? {
        Self.rate(bytes: bytesRead &+ bytesVerified, nanoseconds: runningNanoseconds)
    }

    /// Bytes written ÷ ``runningNanoseconds``. **What Activity Monitor shows**, and displayed
    /// nowhere since 2026-09-02.
    ///
    /// About 1 × ``coverageBytesPerSecond``, because a cycle writes each covered byte once.
    public var sustainedWriteBytesPerSecond: Double? {
        Self.rate(bytes: bytesWritten, nanoseconds: runningNanoseconds)
    }

    /// How fast the **run** is covering its range, against the wall clock. About a third of the
    /// read speed, because every covered byte is read, written and read again — and **this is
    /// the only correct ETA denominator**.
    public var coverageBytesPerSecond: Double? {
        Self.rate(bytes: rangeBytesCovered, nanoseconds: runningNanoseconds)
    }

    /// **What the app displays as `R-W-R-C speed`**: bytes that were read, written back, read
    /// again and matched, ÷ ``successfulPhaseNanoseconds`` — the time the device spent moving
    /// bytes, whether or not the chunk they belonged to ended clean.
    ///
    /// The successful-work counterpart of ``coverageBytesPerSecond``, which counts attempted work.
    /// The denominator is deliberately *not* restricted to the phases of chunks that completed:
    /// a mismatched chunk really did occupy the drive, and excluding its time would let a failing
    /// drive report an undiminished rate. Successful bytes over all the I/O it took to find out.
    ///
    /// **Roughly a third of its two neighbours on a flawless run**, because it is a per-cycle
    /// rate and they are per-phase — about `130` where `Read` is `376` and `Write` is `419`. It
    /// read identically to `Write` until 2026-09-02 and no longer does; the file header records
    /// why that equality was lost and what replaced it. Precisely, on a clean run:
    ///
    ///     1 / completedBytesPerSecond  =  2 / deviceReadBytesPerSecond + 1 / writeBytesPerSecond
    ///
    /// A ``ChunkOutcome/verifyMismatch`` or a ``ChunkOutcome/failedVerifying`` pushes this figure
    /// **below** what that identity predicts — those chunks spend time in the denominator and
    /// contribute nothing to the numerator. That residual is the retention signal, and it is why
    /// this rate is on screen at all.
    ///
    /// Not an ETA denominator, and it must never become one — an estimate built on successful
    /// bytes never converges on a drive with a bad region, which is what
    /// ``coverageBytesPerSecond`` exists for and why that quantity stayed after its label went.
    public var completedBytesPerSecond: Double? {
        Self.rate(bytes: bytesCompleted, nanoseconds: successfulPhaseNanoseconds)
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
        guard rangeBytesCovered > 0, runningNanoseconds > 0 else { return nil }

        let remaining = Double(deviceBytesTotal - rangeBytesCovered)
        // `Double` rather than integer arithmetic: `running × remaining` overflows `UInt64` on
        // any real device, and 53 bits of mantissa is exact to ~104 days of nanoseconds.
        //
        // Running time, not wall clock: an ETA built on elapsed grows without bound while a run
        // is PAUSED, because the numerator keeps ticking and the denominator does not. It reads
        // as "this run is getting slower" to somebody who simply stepped away. This estimates
        // remaining **running** time, which is the only part this tool can predict.
        let estimate = Double(runningNanoseconds) * remaining / Double(rangeBytesCovered)
        return estimate.isFinite && estimate >= 0 ? UInt64(estimate) : nil
    }

    // MARK: - Derived: the denominator the displayed rates use

    /// **The denominator every displayed rate divides by**: wall clock, less the time between
    /// calls.
    ///
    /// ``elapsedNanoseconds`` already stops at the end of the last call — the session observer
    /// hands this type the effective reading, not the live one — so the only subtraction left is
    /// ``idleNanoseconds``, the gaps in which no call was running.
    ///
    /// Everything inside a call counts, including the parts that are not a measured I/O phase,
    /// because an outside observer counts them too. That is what keeps this comparable to
    /// Activity Monitor, and it is where the device-plus-host denominator went wrong: it read
    /// 19% high on hardware by excluding time the drive was genuinely occupied.
    public var runningNanoseconds: UInt64 {
        elapsedNanoseconds > idleNanoseconds ? elapsedNanoseconds - idleNanoseconds : 0
    }

    // MARK: - Derived: NFR-PERF-3

    /// Time the device spent in phases that **moved bytes** — read, write and verify, each of
    /// which is already successful-only. The denominator of ``completedBytesPerSecond``.
    ///
    /// Named for the explicit contrast with ``failedPhaseNanoseconds``, and deliberately not
    /// called anything resembling ``deviceNanoseconds``: the two differ by exactly that term, and
    /// a pair of similar names meaning different spans of time is how a denominator gets picked
    /// wrong. Which is this file's subject.
    public var successfulPhaseNanoseconds: UInt64 {
        readNanoseconds &+ writeNanoseconds &+ verifyNanoseconds
    }

    /// Time the **device** was busy: every phase, successful or not.
    public var deviceNanoseconds: UInt64 {
        successfulPhaseNanoseconds &+ failedPhaseNanoseconds
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

    /// Wall-clock this run did not spend working — scheduling, XPC, the gap between one call and
    /// the next, and any time the run was **paused**. Never negative: a clock that appeared to
    /// run backwards yields zero.
    ///
    /// This is ``elapsedNanoseconds`` minus the phases and the host work, and it is the honest
    /// completeness check on the figures above: if it were large, `hostOverheadFraction` would be
    /// measuring a fraction of the story. Measured at about 1.3% of a call on `disk10` — the
    /// scheduling between one chunk and the next — and the displayed rates deliberately do **not**
    /// subtract it, because an outside observer watching the same drive counts it too. See
    /// ``runningNanoseconds``.
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
    private var bytesCompleted: UInt64 = 0

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

    /// Wall clock in which no call was running, accumulated across the session.
    ///
    /// Fed by ``RunSessionObserver``, which is the only thing that can see a call boundary. The
    /// accumulator itself has no clock, so it cannot notice a gap on its own.
    public private(set) var idleNanoseconds: UInt64 = 0

    /// Record a span in which no call was running — the gap between one call and the next, which
    /// is where a **pause** lives.
    ///
    /// Additive rather than assigned: a session has as many gaps as it has calls, and the run's
    /// throughput must be free of all of them, not just the last.
    public mutating func noteIdle(nanoseconds: UInt64) {
        idleNanoseconds &+= nanoseconds
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

        // Successful work, and the one counter here that advances on nothing but `.completed`.
        //
        // Written as `== .completed` and never as `!measurement.outcome.isPhaseFailure`, which
        // would read as the same test and is not: `.verifyMismatch` moved every byte and failed
        // the compare, so it is deliberately not a phase failure. The negated form would count a
        // retention failure — the fault this whole tool exists to find — as success, on the
        // figure a user reads to find it.
        if measurement.outcome == .completed { bytesCompleted &+= bytes }

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
                               bytesCompleted: bytesCompleted,
                               elapsedNanoseconds: elapsed,
                               readNanoseconds: readNanoseconds,
                               writeNanoseconds: writeNanoseconds,
                               verifyNanoseconds: verifyNanoseconds,
                               failedPhaseNanoseconds: failedPhaseNanoseconds,
                               hostOverheadNanoseconds: hostOverheadNanoseconds,
                               idleNanoseconds: idleNanoseconds,
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

    /// Is a call running right now?
    ///
    /// Decides which reading a snapshot is taken at. **While a call runs, the live clock**, so
    /// progress and throughput move as they should. **Between calls, the reading the last call
    /// ended at**, so a finished run's figures are the figures — a poll a minute later returns
    /// what the reply returned, rather than the same bytes over a bigger denominator.
    ///
    /// `metrics-check.sh` is what forced this: it polls after a call's reply and compares the
    /// two, and with a live clock in the denominator they disagreed by 19% (2026-08-18).
    private var callInFlight = false

    /// When the last call ended, or `nil` before any has.
    private var lastCallEndedAtNanoseconds: UInt64?

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
    ///
    /// Also closes the gap since the previous call. That gap is not the drive's fault and must
    /// not be charged to its throughput: it is the app assembling the next call, and — the case
    /// that matters — it is **a pause**, which can last as long as the user likes (FR-CTRL-3).
    /// Charged to the rate, half an hour away from the keyboard would halve a healthy drive's
    /// reported speed.
    public func runStarted(_ start: RunStart) {
        let now = clock()
        if let ended = lastCallEndedAtNanoseconds, now > ended {
            metrics?.noteIdle(nanoseconds: now - ended)
        }
        callInFlight = true

        guard metrics != nil else {
            metrics = RunMetrics(chunksPlanned: start.chunkCount,
                                 deviceBytesTotal: deviceBytesTotal,
                                 startBlock: start.startBlock,
                                 startedAtNanoseconds: now)
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
        lastCallEndedAtNanoseconds = clock()
        callInFlight = false
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
        metrics?.snapshot(atNanoseconds: effectiveNanoseconds)
    }

    /// The reading a snapshot should be taken at: live while a call runs, frozen at the last
    /// call's end otherwise. See ``callInFlight``.
    private var effectiveNanoseconds: UInt64 {
        callInFlight ? clock() : (lastCallEndedAtNanoseconds ?? clock())
    }

    /// What the run looked like at a given reading. For tests driving a deterministic clock.
    public func snapshot(atNanoseconds nanoseconds: UInt64) -> MetricsSnapshot? {
        metrics?.snapshot(atNanoseconds: nanoseconds)
    }
}
