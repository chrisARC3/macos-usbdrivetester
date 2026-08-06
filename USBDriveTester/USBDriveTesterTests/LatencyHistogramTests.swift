//
//  LatencyHistogramTests.swift
//  Step 9's constant-memory percentile, checked against answers computed by sorting.
//
//  ## Why this suite is written the way it is
//
//  A percentile is a number nobody can eyeball. If the only thing these tests did was run the
//  histogram and assert it returned *something*, a green result would be indistinguishable from
//  a histogram that returns a constant — which is the exact defect Step 7's calibration probe
//  and Step 8's fingerprint check were both written to avoid, arriving in a third place.
//
//  So every percentile assertion here is against a value computed **by sorting the samples in
//  the test**, independently of the code under test. And where the answer is a range, the range
//  is required to be tight enough to **exclude the wrong answer** — an interval wide enough to
//  contain both the fast and the slow population would bracket the truth while saying nothing.
//  See ``PercentileTests/p99ExcludesTheFastPopulationEntirely``.
//
//  ## The bucket arithmetic gets exhaustive treatment, not samples
//
//  An off-by-one in `bucketIndex(forNanoseconds:)` would put values in a neighbouring bucket and
//  be **invisible in every result** — no crash, no error, just a percentile that is quietly one
//  bucket wrong forever. That is not a defect a spot check finds, so ``BucketArithmeticTests``
//  walks all 2,240 buckets and checks the tiling, the round-trip and the monotonicity at every
//  boundary rather than at a handful of chosen points.
//
//  ## What is NOT tested here, and why
//
//  That memory does not scale with device capacity is **structural**: `LatencyHistogram.init()`
//  takes no parameters, so there is no input through which a capacity could reach it. It cannot
//  be tested because it cannot be expressed. ``ConstantMemoryTests`` therefore tests the weaker
//  thing that *can* fail — that the footprint does not grow with the number of observations —
//  and drives more observations through it than `disk8` has chunks.
//

import Testing
import Foundation

// MARK: - Fixtures

private enum Fixture {

    /// Fixed so a failure is reproducible. `SplitMix64` lives in `ChunkCycleAudit.swift`.
    static let seed: UInt64 = 0x4C41_5445_4E43_5900        // "LATENCY\0"

    /// `disk8` at a 4 MiB I/O size — the largest chunk count this tool could ever face, and
    /// therefore the honest number to drive a "does it grow?" test with.
    static let disk8ChunkCount = 5_245_440

    /// A 4 MiB read at `disk4`'s measured ~500 MB/s.
    static let realisticReadNanoseconds: UInt64 = 8_400_000

    /// Build a histogram from `samples`, and return it with the samples sorted so a test can
    /// compute the exact answer itself.
    static func histogram(of samples: [UInt64]) -> (LatencyHistogram, [UInt64]) {
        var histogram = LatencyHistogram()
        for sample in samples { histogram.record(nanoseconds: sample) }
        return (histogram, samples.sorted())
    }

    /// The exact nearest-rank percentile of an already-sorted array — computed here, in the
    /// test, with no reference to the code under test.
    static func exactPercentile(_ fraction: Double, of sorted: [UInt64]) -> UInt64 {
        precondition(!sorted.isEmpty)
        let rank = Int((fraction * Double(sorted.count)).rounded(.up))
        return sorted[Swift.max(1, Swift.min(sorted.count, rank)) - 1]
    }
}

/// The widest a bucket may be, as a fraction of its lower bound: one part in `subBucketsPerOctave`.
private let maximumRelativeBucketWidth = 1.0 / 64.0

// MARK: - Bucket arithmetic (exhaustive, not sampled)

struct BucketArithmeticTests {

    @Test func theBucketsTileTheWholeRangeWithNoGapAndNoOverlap() {
        var expectedLower: UInt64 = 0
        for index in 0 ..< LatencyHistogram.bucketCount {
            let bounds = LatencyHistogram.bounds(ofBucket: index)
            #expect(bounds.lower == expectedLower,
                    "bucket \(index) starts at \(bounds.lower), expected \(expectedLower)")
            #expect(bounds.upperExclusive > bounds.lower, "bucket \(index) is empty")
            expectedLower = bounds.upperExclusive
        }
        #expect(expectedLower == LatencyHistogram.maximumRepresentableNanoseconds)
    }

    @Test func everyBucketsFirstAndLastNanosecondMapBackToThatBucket() {
        for index in 0 ..< LatencyHistogram.bucketCount {
            let bounds = LatencyHistogram.bounds(ofBucket: index)
            #expect(LatencyHistogram.bucketIndex(forNanoseconds: bounds.lower) == index,
                    "bucket \(index)'s lower bound \(bounds.lower) mapped elsewhere")
            #expect(LatencyHistogram.bucketIndex(forNanoseconds: bounds.upperExclusive - 1) == index,
                    "bucket \(index)'s last value mapped elsewhere")
        }
    }

    @Test func eachBucketsUpperBoundIsTheNextBucketsFirstValue() {
        for index in 0 ..< LatencyHistogram.bucketCount - 1 {
            let bounds = LatencyHistogram.bounds(ofBucket: index)
            #expect(LatencyHistogram.bucketIndex(forNanoseconds: bounds.upperExclusive) == index + 1,
                    "the value after bucket \(index) did not land in bucket \(index + 1)")
        }
    }

    /// Dense over the region a real read latency lives in, so a discontinuity cannot hide
    /// between two sampled points.
    @Test func theBucketIndexNeverDecreases() {
        var previous = -1
        for nanoseconds in UInt64(0) ..< 200_000 {
            guard let index = LatencyHistogram.bucketIndex(forNanoseconds: nanoseconds) else {
                Issue.record("\(nanoseconds) ns had no bucket")
                return
            }
            #expect(index >= previous, "index fell at \(nanoseconds) ns")
            previous = index
        }
    }

    /// 0–63 ns are held exactly. This is also what makes a zero-duration reading — a read the
    /// clock could not resolve — a counted observation rather than a special case.
    @Test func durationsBelowSixtyFourNanosecondsAreExact() {
        for nanoseconds in UInt64(0) ..< 64 {
            let bounds = LatencyHistogram.bounds(ofBucket: Int(nanoseconds))
            #expect(LatencyHistogram.bucketIndex(forNanoseconds: nanoseconds) == Int(nanoseconds))
            #expect(bounds.lower == nanoseconds)
            #expect(bounds.upperExclusive == nanoseconds + 1)
        }
    }

    /// The accuracy claim, checked at every bucket rather than asserted in a comment.
    @Test func noBucketIsWiderThanOnePartInSixtyFour() {
        for index in LatencyHistogram.subBucketsPerOctave ..< LatencyHistogram.bucketCount {
            let bounds = LatencyHistogram.bounds(ofBucket: index)
            let width = Double(bounds.upperExclusive - bounds.lower) / Double(bounds.lower)
            #expect(width <= maximumRelativeBucketWidth,
                    "bucket \(index) is \(width * 100.0)% wide")
        }
    }

    @Test func theShapeIsTheDocumentedOne() {
        #expect(LatencyHistogram.subBucketsPerOctave == 64)
        #expect(LatencyHistogram.bucketCount == 2_240)
        #expect(LatencyHistogram.storageBytes == 17_920)
        #expect(LatencyHistogram.maximumRepresentableNanoseconds == 1_099_511_627_776)
    }
}

// MARK: - The exact statistics

struct ExactStatisticsTests {

    @Test func anEmptyHistogramAnswersNothingRatherThanZero() {
        let histogram = LatencyHistogram()
        #expect(histogram.isEmpty)
        #expect(histogram.count == 0)
        #expect(histogram.minimumNanoseconds == nil)
        #expect(histogram.maximumNanoseconds == nil)
        #expect(histogram.meanNanoseconds == nil)
        #expect(histogram.percentile(0.99) == nil)
    }

    /// Min, max, count and mean are exact — they are the numbers a user reads first, and the
    /// ones an alarming drive moves.
    @Test func minimumMaximumCountAndMeanAreExact() {
        var generator = SplitMix64(seed: Fixture.seed)
        var samples: [UInt64] = []
        for _ in 0 ..< 10_000 {
            samples.append(UInt64.random(in: 1 ... 50_000_000, using: &generator))
        }

        let (histogram, sorted) = Fixture.histogram(of: samples)

        let total = samples.reduce(UInt64(0)) { $0 &+ $1 }

        #expect(histogram.count == 10_000)
        #expect(histogram.minimumNanoseconds == sorted.first)
        #expect(histogram.maximumNanoseconds == sorted.last)
        #expect(histogram.totalNanoseconds == total)
        #expect(histogram.meanNanoseconds == total / 10_000)
    }

    @Test func aSingleObservationPinsEveryStatisticExactly() throws {
        var histogram = LatencyHistogram()
        histogram.record(nanoseconds: Fixture.realisticReadNanoseconds)

        #expect(histogram.count == 1)
        #expect(histogram.minimumNanoseconds == Fixture.realisticReadNanoseconds)
        #expect(histogram.maximumNanoseconds == Fixture.realisticReadNanoseconds)
        #expect(histogram.meanNanoseconds == Fixture.realisticReadNanoseconds)

        // One sample, and the bucket range is intersected with the exact ends — so the answer
        // collapses to the single value rather than to whatever bucket it fell in.
        let estimate = try #require(histogram.percentile(0.99))
        #expect(estimate.isExact)
        #expect(estimate.lowerBoundNanoseconds == Fixture.realisticReadNanoseconds)
    }

    /// A read the clock could not resolve is data, not noise to drop.
    @Test func aZeroDurationIsCounted() {
        var histogram = LatencyHistogram()
        histogram.record(nanoseconds: 0)
        histogram.record(nanoseconds: 0)

        #expect(histogram.count == 2)
        #expect(histogram.minimumNanoseconds == 0)
        #expect(histogram.occupancy(ofBucket: 0) == 2)
        #expect(histogram.overflowCount == 0)
    }
}

// MARK: - Percentiles, against answers computed by sorting

struct PercentileTests {

    /// A distribution with a deliberate slow tail: 985 reads at 1 ms, 15 at 100 ms. The exact
    /// p99 is computable by hand — rank 990 of 1,000, which is past the 985 fast ones.
    private static let fastNanoseconds: UInt64 = 1_000_000
    private static let slowNanoseconds: UInt64 = 100_000_000

    private static func slowTailSamples() -> [UInt64] {
        [UInt64](repeating: fastNanoseconds, count: 985)
            + [UInt64](repeating: slowNanoseconds, count: 15)
    }

    @Test(arguments: [0.5, 0.9, 0.95, 0.99, 1.0])
    func everyPercentileBracketsTheExactAnswer(fraction: Double) throws {
        let (histogram, sorted) = Fixture.histogram(of: Self.slowTailSamples())
        let exact = Fixture.exactPercentile(fraction, of: sorted)
        let estimate = try #require(histogram.percentile(fraction))

        #expect(estimate.lowerBoundNanoseconds <= exact,
                "p\(fraction) lower bound \(estimate.lowerBoundNanoseconds) > exact \(exact)")
        #expect(estimate.upperBoundNanoseconds >= exact,
                "p\(fraction) upper bound \(estimate.upperBoundNanoseconds) < exact \(exact)")
    }

    /// **The assertion that makes the others mean something.** An interval wide enough to hold
    /// both populations would bracket the truth and say nothing. p99 must land in the slow
    /// tail and exclude the 1 ms population outright.
    @Test func p99ExcludesTheFastPopulationEntirely() throws {
        let (histogram, _) = Fixture.histogram(of: Self.slowTailSamples())
        let estimate = try #require(histogram.percentile(0.99))

        #expect(estimate.lowerBoundNanoseconds > Self.fastNanoseconds,
                "p99's interval still contains the 1 ms population, so it distinguishes nothing")
        #expect(estimate.relativeWidth <= maximumRelativeBucketWidth)
    }

    /// The other half of the same point: the median must land in the fast population and
    /// exclude the slow tail.
    @Test func p50ExcludesTheSlowTailEntirely() throws {
        let (histogram, _) = Fixture.histogram(of: Self.slowTailSamples())
        let estimate = try #require(histogram.percentile(0.5))

        #expect(estimate.upperBoundNanoseconds < Self.slowNanoseconds)
    }

    @Test func percentilesAreBracketedAcrossAWideRandomDistribution() throws {
        var generator = SplitMix64(seed: Fixture.seed &+ 1)
        var samples: [UInt64] = []
        for _ in 0 ..< 50_000 {
            samples.append(UInt64.random(in: 1 ... 2_000_000_000, using: &generator))
        }
        let (histogram, sorted) = Fixture.histogram(of: samples)

        for fraction in [0.01, 0.25, 0.5, 0.75, 0.9, 0.99, 0.999] {
            let exact = Fixture.exactPercentile(fraction, of: sorted)
            let estimate = try #require(histogram.percentile(fraction))
            // One string literal, not a concatenation: `#expect`'s comment is a `Comment`,
            // which is expressible by a string *literal* — `"a" + "b"` is a `String`
            // expression and will not convert.
            #expect(estimate.lowerBoundNanoseconds <= exact && exact <= estimate.upperBoundNanoseconds,
                    "p\(fraction): \(exact) not in \(estimate.lowerBoundNanoseconds)–\(estimate.upperBoundNanoseconds)")
            #expect(estimate.relativeWidth <= maximumRelativeBucketWidth)
        }
    }

    /// The interval is intersected with the exact ends, so p100 collapses onto the exact
    /// maximum rather than reporting the bucket that contains it.
    @Test func p100IsTheExactMaximum() throws {
        let (histogram, sorted) = Fixture.histogram(of: Self.slowTailSamples())
        let estimate = try #require(histogram.percentile(1.0))

        #expect(estimate.upperBoundNanoseconds == sorted.last)
        #expect(histogram.maximumNanoseconds == sorted.last)
    }

    @Test func aFractionOutsideZeroToOneIsClampedRatherThanTrapping() throws {
        let (histogram, sorted) = Fixture.histogram(of: Self.slowTailSamples())

        let above = try #require(histogram.percentile(1.5))
        let below = try #require(histogram.percentile(-0.5))

        #expect(above.fraction == 1.0)
        #expect(below.fraction == 0.0)
        #expect(above.upperBoundNanoseconds == sorted.last)
        #expect(below.lowerBoundNanoseconds == sorted.first)
    }
}

// MARK: - Overflow is reported, never clamped

struct OverflowTests {

    /// The rule `FailureLog.isTruncated` established, in a second place: a structure that
    /// quietly drops what will not fit reads exactly like one that had nothing to drop.
    @Test func aDurationPastTheRepresentableRangeOverflowsRatherThanClamping() {
        var histogram = LatencyHistogram()
        histogram.record(nanoseconds: Fixture.realisticReadNanoseconds)
        histogram.record(nanoseconds: LatencyHistogram.maximumRepresentableNanoseconds)
        histogram.record(nanoseconds: UInt64.max)

        #expect(histogram.overflowCount == 2)
        #expect(histogram.count == 3)

        // The top bucket must be empty: an overflowed value that had been clamped would be
        // sitting in it, and the tail would read as shorter than the one that happened.
        #expect(histogram.occupancy(ofBucket: LatencyHistogram.bucketCount - 1) == 0)
    }

    /// The case where an exact maximum matters most.
    @Test func theMaximumStaysExactThroughAnOverflow() {
        var histogram = LatencyHistogram()
        histogram.record(nanoseconds: Fixture.realisticReadNanoseconds)
        histogram.record(nanoseconds: UInt64.max)

        #expect(histogram.maximumNanoseconds == UInt64.max)
    }

    @Test func aPercentileLandingInTheOverflowSaysSo() throws {
        var histogram = LatencyHistogram()
        for _ in 0 ..< 90 { histogram.record(nanoseconds: Fixture.realisticReadNanoseconds) }
        for _ in 0 ..< 10 { histogram.record(nanoseconds: UInt64.max) }

        let estimate = try #require(histogram.percentile(0.99))
        #expect(estimate.isAboveRepresentableRange)
        #expect(estimate.lowerBoundNanoseconds >= LatencyHistogram.maximumRepresentableNanoseconds)
        #expect(estimate.upperBoundNanoseconds == UInt64.max)

        // …and one that does not land there must not be flagged, or the flag means nothing.
        let median = try #require(histogram.percentile(0.5))
        #expect(!median.isAboveRepresentableRange)
    }
}

// MARK: - Constant memory (NFR-PERF-7)

struct ConstantMemoryTests {

    /// The claim that can actually fail. That memory does not scale with *device capacity* is
    /// structural — `init()` takes no parameters — so what is tested here is that it does not
    /// grow with the number of observations either, driven past `disk8`'s chunk count.
    @Test func moreObservationsThanDisk8HasChunksLeaveTheFootprintUnchanged() {
        var histogram = LatencyHistogram()
        #expect(histogram.allocatedBucketCount == LatencyHistogram.bucketCount)

        var generator = SplitMix64(seed: Fixture.seed &+ 2)
        for _ in 0 ..< Fixture.disk8ChunkCount {
            histogram.record(nanoseconds: UInt64.random(in: 1 ... 50_000_000, using: &generator))
        }

        #expect(histogram.count == UInt64(Fixture.disk8ChunkCount))
        #expect(histogram.allocatedBucketCount == LatencyHistogram.bucketCount)
        #expect(LatencyHistogram.storageBytes == 17_920)
    }

    /// Two histograms fed wildly different *numbers* of observations hold byte-identical
    /// storage. There is no parameter through which a device could make them differ.
    @Test func theFootprintDoesNotDependOnHowMuchWasRecorded() {
        var small = LatencyHistogram()
        var large = LatencyHistogram()

        small.record(nanoseconds: 1)
        for index in 0 ..< 100_000 { large.record(nanoseconds: UInt64(index) &+ 1) }

        #expect(small.allocatedBucketCount == large.allocatedBucketCount)
        #expect(small.allocatedBucketCount == LatencyHistogram.bucketCount)
    }
}
