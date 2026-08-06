//
//  LatencyHistogram.swift
//  Core — min, max and a high percentile of a stream of durations, in constant memory.
//
//  Step 9 (AI-8), BUILD-PLAN 9.2, decision D3. Satisfies the constant-memory half of
//  NFR-PERF-7 and the p99 half of FR-METR-3.
//
//  Pure Foundation. No privilege, no clock of its own, no I/O — it is handed durations and
//  answers questions about them, so it is testable against an exactly-computed answer with no
//  hardware anywhere near it.
//
//  ## Why a histogram, and not the two obvious alternatives
//
//  NFR-PERF-7 forbids keeping per-chunk samples: `disk8` at 4 MiB is 5,245,440 chunks, and an
//  array of those is the same capacity-scaling growth Step 7 removed from the chunk plan and
//  Step 8 removed from the failure list. So the percentile has to be approximate. Three
//  candidates, and the choice is not about accuracy:
//
//  | Method | Memory | Why not |
//  |---|---|---|
//  | **t-digest** | bounded, variable | Floating-point merge invariants. Accurate at the tails, and genuinely hard to pin against a known-correct answer — which is the property that actually matters here. |
//  | **P² (Jain & Chlamtac)** | 5 markers | A heuristic with **no statable error bound**, and known to do badly on multimodal distributions. A drive with a slow tail *is* multimodal; that is the entire case being measured. |
//  | **this** | fixed, 17.5 KiB | Error bounded **by construction**, and every answer can be checked against a value computed by sorting in a test. |
//
//  The deciding property is the last one. A percentile is a number nobody can eyeball, so a
//  method whose answer cannot be checked against an exact one is a method whose check cannot
//  fail — and Step 7's lesson is that a check which has never been shown capable of failing is
//  a substitute for a test.
//
//  ## Constant memory is structural, not measured
//
//  ``init()`` **takes no parameters.** There is no input through which a device's capacity
//  could reach this type, so "memory does not scale with capacity" is unrepresentable rather
//  than something to measure and hope for — the same argument `ChunkBuffers` makes, and the
//  same one Step 2's materialised chunk plan failed to make while satisfying its gate's
//  wording.
//
//  `LatencyHistogramTests` still drives millions of observations through it and asserts the
//  footprint is unchanged, because a structural argument that is never exercised is an
//  argument.
//
//  ## How a duration becomes a bucket, in about five instructions
//
//  Values **0–63 ns get their own bucket each** — exact, no approximation at all. There is no
//  point spending buckets on sub-nanosecond resolution that no clock can produce
//  (`CLOCK_MONOTONIC_RAW` on Apple Silicon advances in ~41.67 ns steps), and it means a
//  zero-duration reading is *counted* rather than being a special case.
//
//  From 64 ns up, each **octave** — each doubling — is divided into **64 equal sub-buckets**:
//
//      octave      = 63 - d.leadingZeroBitCount        // floor(log2 d), one `clz`
//      subBucket   = (d >> (octave - 6)) & 63          // shift, mask
//      index       = 64 + (octave - 6) * 64 + subBucket
//
//  No floating point, no division, no lookup table. That matters because this runs once per
//  chunk inside the run loop, and NFR-PERF-3 is a requirement about exactly that cost.
//
//  ### What that costs in accuracy, stated honestly
//
//  A bucket is 1/64 of its octave's base, so its **relative width runs from 1.5625% at the
//  start of an octave to 0.78% at the end**. Geometric spacing (2^(1/64) per bucket) would be a
//  uniform 1.09%, but selecting a geometric bucket needs floating point or a table. The trade
//  is deliberate: half a percent on an interval that is *already reported as an interval* is
//  worth less than keeping the hot path integer-only.
//
//  So ``percentile(_:)`` returns a ``LatencyPercentile`` — a **range the true value lies
//  inside** — and never a single number pretending to a precision it does not have.
//
//  ## What is exact, and it is the part that matters most
//
//  ``minimumNanoseconds``, ``maximumNanoseconds``, ``count`` and the mean are **exact**. They
//  cost four scalars and no approximation, and they are the two ends of the distribution — the
//  numbers a user reads first and the ones an alarming drive moves. Only the interior
//  percentile is estimated.
//

import Foundation

// MARK: - An estimated percentile, reported as the range it actually is

/// Where a percentile lies, as a **closed range of nanoseconds** the true value is inside.
///
/// A range rather than a number because that is what a bucketed histogram honestly knows. A
/// point estimate would be the bucket's midpoint dressed up as a measurement.
///
/// `Sendable` because it travels inside a `MetricsSnapshot`, which the helper hands across a
/// thread once a second. Four scalars, no reference, no mutation — the conformance is free.
public struct LatencyPercentile: Equatable, Sendable, CustomStringConvertible {

    /// The fraction requested, e.g. `0.99`.
    public let fraction: Double

    /// Lowest nanosecond value the true percentile could take.
    public let lowerBoundNanoseconds: UInt64

    /// Highest nanosecond value the true percentile could take. Always >= the lower bound.
    public let upperBoundNanoseconds: UInt64

    /// The percentile fell **past the top of the representable range**, so the bounds are
    /// derived from the exact maximum rather than from a bucket.
    ///
    /// Surfaced rather than absorbed: a histogram that silently clamps an out-of-range value
    /// reports a tail that is shorter than the one that happened, which on this tool is the
    /// difference between "slow drive" and "fine".
    public let isAboveRepresentableRange: Bool

    public init(fraction: Double,
                lowerBoundNanoseconds: UInt64,
                upperBoundNanoseconds: UInt64,
                isAboveRepresentableRange: Bool) {
        self.fraction = fraction
        self.lowerBoundNanoseconds = lowerBoundNanoseconds
        self.upperBoundNanoseconds = Swift.max(lowerBoundNanoseconds, upperBoundNanoseconds)
        self.isAboveRepresentableRange = isAboveRepresentableRange
    }

    /// How wide the interval is, as a fraction of its lower bound. `0` when the bound is exact.
    ///
    /// Lets a report say *how well* it knows the answer instead of implying it knows exactly.
    public var relativeWidth: Double {
        guard lowerBoundNanoseconds > 0 else { return 0 }
        return Double(upperBoundNanoseconds - lowerBoundNanoseconds) / Double(lowerBoundNanoseconds)
    }

    /// Whether the interval pins a single value.
    public var isExact: Bool { lowerBoundNanoseconds == upperBoundNanoseconds }

    public var description: String {
        let percent = Int((fraction * 100).rounded())
        let suffix = isAboveRepresentableRange ? " (above the representable range)" : ""
        return isExact
            ? "p\(percent) = \(lowerBoundNanoseconds) ns\(suffix)"
            : "p\(percent) in \(lowerBoundNanoseconds)–\(upperBoundNanoseconds) ns\(suffix)"
    }
}

// MARK: - The histogram

/// A fixed-size histogram of durations in nanoseconds.
///
/// Not thread-safe, deliberately, and for the same reason `ChunkBuffers` is not: a run drives
/// one device from one task. Publishing a snapshot across threads is the *helper's* job, not
/// this type's — Core stays free of concurrency primitives.
public struct LatencyHistogram: Equatable {

    // MARK: Shape

    /// `log2` of the sub-buckets per octave. Six, so a shift and a 6-bit mask select one.
    public static let subBucketBits = 6

    /// Sub-buckets each octave is divided into. **64.**
    public static let subBucketsPerOctave = 1 << subBucketBits

    /// Octaves covered above the exact region. `2^40 ns` is **18.3 minutes**, which is far past
    /// any single chunk read that is not already a dead drive — and a value past it is counted
    /// in ``overflowCount`` rather than being clamped into the top bucket.
    public static let topOctave = 40

    /// Total buckets: 64 exact ones for 0–63 ns, then 64 per octave from 2^6 to 2^40.
    public static let bucketCount =
        subBucketsPerOctave + (topOctave - subBucketBits) * subBucketsPerOctave

    /// The first duration this histogram cannot place in a bucket.
    public static let maximumRepresentableNanoseconds: UInt64 = 1 << UInt64(topOctave)

    /// Bytes of counter storage — a compile-time constant, and the whole of NFR-PERF-7's
    /// memory claim. **17,920 bytes.**
    public static let storageBytes = bucketCount * MemoryLayout<UInt64>.stride

    // MARK: State

    private var buckets: [UInt64]

    /// How many durations were recorded, including any that overflowed. Exact.
    public private(set) var count: UInt64 = 0

    /// Sum of every duration recorded. Exact, and the basis of ``meanNanoseconds``.
    ///
    /// Wrapping arithmetic on purpose. `UInt64` nanoseconds is 585 years, so the wrap is
    /// unreachable — but a trap here would crash a **root daemon holding a disk claim**, and a
    /// stuck claim is a worse outcome than an arithmetic edge no run can reach (NFR-REL-5).
    public private(set) var totalNanoseconds: UInt64 = 0

    /// Shortest duration seen. Exact, never estimated. `nil` before the first observation.
    public private(set) var minimumNanoseconds: UInt64?

    /// Longest duration seen. Exact, never estimated — including when it overflowed the
    /// buckets, which is the case where it matters most.
    public private(set) var maximumNanoseconds: UInt64?

    /// Durations at or past ``maximumRepresentableNanoseconds``.
    ///
    /// **Must be surfaced wherever a percentile is** — the same rule as `FailureLog.isTruncated`,
    /// for the same reason. A histogram quietly clamping its tail reads exactly like one whose
    /// tail was short.
    public private(set) var overflowCount: UInt64 = 0

    /// Takes **no parameters**, which is what makes the memory claim structural: there is no
    /// input through which a device's capacity could reach this type.
    public init() {
        buckets = [UInt64](repeating: 0, count: Self.bucketCount)
    }

    // MARK: Recording

    /// Record one duration. Constant time, no allocation, no floating point.
    public mutating func record(nanoseconds: UInt64) {
        count &+= 1
        totalNanoseconds &+= nanoseconds

        if let smallest = minimumNanoseconds {
            if nanoseconds < smallest { minimumNanoseconds = nanoseconds }
        } else {
            minimumNanoseconds = nanoseconds
        }
        if let largest = maximumNanoseconds {
            if nanoseconds > largest { maximumNanoseconds = nanoseconds }
        } else {
            maximumNanoseconds = nanoseconds
        }

        guard let index = Self.bucketIndex(forNanoseconds: nanoseconds) else {
            overflowCount &+= 1
            return
        }
        buckets[index] &+= 1
    }

    // MARK: Reading

    /// Whether anything has been recorded.
    public var isEmpty: Bool { count == 0 }

    /// Exact mean, or `nil` when nothing has been recorded.
    public var meanNanoseconds: UInt64? {
        count == 0 ? nil : totalNanoseconds / count
    }

    /// The range the requested percentile lies in, or `nil` when nothing has been recorded.
    ///
    /// Uses the **nearest-rank** definition: the smallest recorded value at or below which at
    /// least `fraction` of observations fall. Chosen because it is unambiguous over integers
    /// and is trivially computable in a test by sorting — which is what makes the answer
    /// checkable against a known-correct one.
    ///
    /// The bucket's range is then **intersected with the exact minimum and maximum**. That is
    /// sound (the true value is in both) and it tightens the answer for free — notably at
    /// p100, where it collapses to the exact maximum.
    ///
    /// - Parameter fraction: `0...1`. Values outside are clamped.
    public func percentile(_ fraction: Double) -> LatencyPercentile? {
        guard count > 0, let smallest = minimumNanoseconds, let largest = maximumNanoseconds else {
            return nil
        }

        let clamped = Swift.min(Swift.max(fraction, 0), 1)
        // Nearest rank, 1-based. `ceil` so p99 of 100 samples is the 99th, not the 98th.
        let rawRank = (clamped * Double(count)).rounded(.up)
        let targetRank = Swift.max(UInt64(1), Swift.min(count, UInt64(rawRank)))

        /// Narrow a bucket's range to what the exact ends already rule out.
        func clampToObserved(_ lower: UInt64, _ upper: UInt64) -> (UInt64, UInt64) {
            let low = Swift.max(lower, smallest)
            let high = Swift.min(upper, largest)
            // Only if the intersection is non-empty. It always should be — the true value is
            // in both ranges — but a wrong answer must not be produced by an inverted interval.
            return low <= high ? (low, high) : (lower, upper)
        }

        var cumulative: UInt64 = 0
        for index in 0 ..< Self.bucketCount {
            let occupancy = buckets[index]
            guard occupancy > 0 else { continue }
            cumulative &+= occupancy
            guard cumulative >= targetRank else { continue }

            let bounds = Self.bounds(ofBucket: index)
            let (low, high) = clampToObserved(bounds.lower, bounds.upperExclusive - 1)
            return LatencyPercentile(fraction: clamped,
                                     lowerBoundNanoseconds: low,
                                     upperBoundNanoseconds: high,
                                     isAboveRepresentableRange: false)
        }

        // Falling out of the loop means the rank lands among the overflowed durations. The
        // maximum is still exact, so the answer is a real range and not a shrug.
        return LatencyPercentile(
            fraction: clamped,
            lowerBoundNanoseconds: Swift.max(Self.maximumRepresentableNanoseconds, smallest),
            upperBoundNanoseconds: largest,
            isAboveRepresentableRange: true)
    }

    /// How many observations landed in `index`. For tests and diagnostics.
    public func occupancy(ofBucket index: Int) -> UInt64 {
        guard index >= 0, index < Self.bucketCount else { return 0 }
        return buckets[index]
    }

    /// Buckets actually allocated. Asserted by the tests after millions of observations: this
    /// is the claim that the structure does not grow.
    public var allocatedBucketCount: Int { buckets.count }

    // MARK: Bucket arithmetic

    /// Which bucket a duration belongs in, or `nil` if it is past the representable range.
    ///
    /// Monotonic in `nanoseconds`, and the buckets tile `0 ..< maximumRepresentableNanoseconds`
    /// with no gap and no overlap — both asserted exhaustively by `LatencyHistogramTests`,
    /// because an off-by-one here would put a value in a neighbouring bucket and be invisible
    /// in every result.
    public static func bucketIndex(forNanoseconds nanoseconds: UInt64) -> Int? {
        // The exact region: 0–63 ns each get their own bucket.
        if nanoseconds < UInt64(subBucketsPerOctave) { return Int(nanoseconds) }
        guard nanoseconds < maximumRepresentableNanoseconds else { return nil }

        let octave = 63 - nanoseconds.leadingZeroBitCount        // floor(log2)
        let shift = UInt64(octave - subBucketBits)
        let subBucket = Int((nanoseconds >> shift) & UInt64(subBucketsPerOctave - 1))
        return subBucketsPerOctave
             + (octave - subBucketBits) * subBucketsPerOctave
             + subBucket
    }

    /// The half-open nanosecond range a bucket covers.
    public static func bounds(ofBucket index: Int) -> (lower: UInt64, upperExclusive: UInt64) {
        if index < subBucketsPerOctave {
            return (UInt64(index), UInt64(index) + 1)
        }
        let offset = index - subBucketsPerOctave
        let octave = subBucketBits + offset / subBucketsPerOctave
        let subBucket = UInt64(offset % subBucketsPerOctave)
        let shift = UInt64(octave - subBucketBits)
        let base = UInt64(subBucketsPerOctave) + subBucket
        return (base << shift, (base + 1) << shift)
    }
}
