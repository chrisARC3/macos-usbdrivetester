//
//  FailedRangeCodingTests.swift
//  FR-RPT-1's ranges on their way across the XPC boundary. Step 10, increment 1.
//
//  ## Why this codec gets an adversarial suite and not just a round-trip
//
//  The failed-block list is the **substance** of the exported report, and the report is the only
//  thing this product persists. Every other number in it is a measurement of the drive; this one
//  is the answer to "which blocks are bad?", and it is the answer somebody may act on by throwing
//  a drive away.
//
//  So the failure this suite is aimed at is not "the codec crashes" — it is **the codec quietly
//  returning fewer ranges than it was given, or a range at the wrong address.** A report that
//  lists eleven bad ranges when the run found twelve looks exactly like a report that found
//  eleven. That is the same shape as `FailureLog.isTruncated`, as "an empty result is not a
//  finding", and as the probe that printed `0.0 ms` for a reply that never arrived — a value that
//  reads as data when it means something else.
//
//  `decode` therefore returns `nil` for **any** malformed input rather than skipping the bad
//  record, and `aSingleBadRecordFailsTheWholeDecode` is the row that pins it. An app that cannot
//  decode declines to build a report; an app that skips builds a wrong one.
//
//  ## And the crash vector, which is real
//
//  `FailedBlockRange.endBlock` is `startBlock + blockCount` with a trapping `+`, and the report
//  prints it. A record of `18446744073709551615:2:1` would trap the process that formatted it.
//  The failable initialiser is what makes that unrepresentable, and
//  `aRangeThatWouldOverflowIsRefused` is what proves the initialiser is doing it rather than the
//  arithmetic happening to be safe on the values a test author picked.
//

import Testing
import Foundation
@testable import USBDriveTester

struct FailedRangeCodingTests {

    // MARK: - Building a range

    @Test func aWellFormedRangeIsAccepted() {
        let range = FailedBlockRange(startBlock: 100, blockCount: 8, kind: .readError)
        #expect(range?.startBlock == 100)
        #expect(range?.blockCount == 8)
        #expect(range?.kind == .readError)
        #expect(range?.endBlock == 108)
    }

    /// An empty range says nothing and would render as a blank row in the report's table.
    @Test func aZeroLengthRangeIsRefused() {
        #expect(FailedBlockRange(startBlock: 100, blockCount: 0, kind: .readError) == nil)
    }

    /// The crash vector. `endBlock` is a trapping add and the report prints it.
    @Test func aRangeThatWouldOverflowIsRefused() {
        #expect(FailedBlockRange(startBlock: .max, blockCount: 1, kind: .readError) == nil)
        #expect(FailedBlockRange(startBlock: .max, blockCount: .max, kind: .writeError) == nil)
        #expect(FailedBlockRange(startBlock: .max - 1, blockCount: 2, kind: .readError) == nil)
    }

    /// The largest range that *can* be represented still is — the guard must not be off by one
    /// and quietly refuse a legitimate range at the top of the address space.
    @Test func theLargestRepresentableRangeIsStillAccepted() {
        let range = FailedBlockRange(startBlock: .max - 1, blockCount: 1, kind: .readError)
        #expect(range?.endBlock == .max)
    }

    // MARK: - Round trip

    @Test func anEmptyListRoundTrips() {
        #expect(FailedRangeCoding.encode([]) == "")
        #expect(FailedRangeCoding.decode("") == [])
    }

    @Test func oneRangeRoundTrips() {
        let ranges = [FailedBlockRange(startBlock: 4096, blockCount: 8, kind: .verifyMismatch)!]
        #expect(FailedRangeCoding.decode(FailedRangeCoding.encode(ranges)) == ranges)
    }

    /// Every kind, so a kind cannot be dropped or transposed by the codec.
    @Test func everyKindRoundTrips() {
        for kind in FailedBlockRangeKind.allCases {
            let ranges = [FailedBlockRange(startBlock: 8, blockCount: 2, kind: kind)!]
            #expect(FailedRangeCoding.decode(FailedRangeCoding.encode(ranges)) == ranges,
                    "\(kind) did not survive the round trip")
        }
        #expect(FailedBlockRangeKind.allCases.count == 3)
    }

    @Test func manyRangesRoundTripInOrder() {
        let ranges: [FailedBlockRange] = [
            FailedBlockRange(startBlock: 0, blockCount: 1, kind: .readError)!,
            FailedBlockRange(startBlock: 2048, blockCount: 8192, kind: .writeError)!,
            FailedBlockRange(startBlock: 1_953_525_160, blockCount: 8, kind: .verifyMismatch)!,
        ]
        #expect(FailedRangeCoding.decode(FailedRangeCoding.encode(ranges)) == ranges)
    }

    /// A list at the shape `FailureLog` actually caps at (1,024 retained ranges), because the
    /// encoded string is what has to cross XPC and nothing about its length may be a surprise.
    @Test func aFullRetentionLimitOfRangesRoundTrips() {
        let ranges = (0 ..< FailureLog.defaultRetentionLimit).map { index in
            FailedBlockRange(startBlock: UInt64(index) * 4096,
                             blockCount: 8,
                             kind: .verifyMismatch)!
        }
        let encoded = FailedRangeCoding.encode(ranges)
        #expect(FailedRangeCoding.decode(encoded) == ranges)
        #expect(ranges.count == 1_024)
    }

    /// The extremes of the value space, which is where an encoder that used anything narrower
    /// than `UInt64` would come apart. A 22 TB drive is 42,970,644,479 blocks — already past
    /// 2^32 — and NFR-COMPAT-6 exists because a USB bridge truncating to 32 bits is a real
    /// failure mode.
    @Test func extremeBlockNumbersRoundTrip() {
        let ranges: [FailedBlockRange] = [
            FailedBlockRange(startBlock: 0, blockCount: .max, kind: .readError)!,
            FailedBlockRange(startBlock: 42_970_644_471, blockCount: 8, kind: .writeError)!,
            FailedBlockRange(startBlock: .max - 1, blockCount: 1, kind: .verifyMismatch)!,
        ]
        #expect(FailedRangeCoding.decode(FailedRangeCoding.encode(ranges)) == ranges)
    }

    /// The encoding is what appears in log lines, so its shape is worth pinning rather than
    /// leaving to whatever `encode` currently emits.
    @Test func theEncodingIsTheDocumentedShape() {
        let ranges: [FailedBlockRange] = [
            FailedBlockRange(startBlock: 100, blockCount: 8, kind: .readError)!,
            FailedBlockRange(startBlock: 512, blockCount: 16, kind: .verifyMismatch)!,
        ]
        #expect(FailedRangeCoding.encode(ranges) == "100:8:1;512:16:3")
    }

    // MARK: - Everything that is not a canonical encoding

    /// **The row this suite exists for.** Skipping the bad record would produce a shorter list
    /// that still reads as complete.
    @Test func aSingleBadRecordFailsTheWholeDecode() {
        #expect(FailedRangeCoding.decode("100:8:1;garbage;512:16:3") == nil)
        #expect(FailedRangeCoding.decode("100:8:1;512:16:9") == nil)
        #expect(FailedRangeCoding.decode("100:8:1;;512:16:3") == nil)
    }

    @Test func aWrongFieldCountIsRefused() {
        for encoded in ["100:8", "100", "100:8:1:2", "::", "100:8:1:"] {
            #expect(FailedRangeCoding.decode(encoded) == nil, "accepted \(encoded)")
        }
    }

    /// The accept-set is ASCII digits and nothing else. `UInt64(_:)` on its own would take the
    /// first of these, which is why the digits are checked before it is called.
    @Test func onlyPlainAsciiDigitsAreAccepted() {
        for encoded in ["+100:8:1",        // a leading sign
                        "-100:8:1",
                        " 100:8:1",        // whitespace
                        "100 :8:1",
                        "1_00:8:1",        // Swift's own literal grouping
                        "0x64:8:1",        // hex
                        "1e3:8:1",         // exponent
                        "100:8:١",         // an Arabic-Indic digit: `isNumber` is true, ASCII is not
                        "𝟏𝟎𝟎:8:1"] {       // mathematical bold digits
            #expect(FailedRangeCoding.decode(encoded) == nil, "accepted \(encoded)")
        }
    }

    /// A value too large for `UInt64` must be refused rather than saturating or wrapping into a
    /// plausible-looking block number.
    @Test func anOverflowingValueIsRefused() {
        #expect(FailedRangeCoding.decode("18446744073709551616:8:1") == nil)
        #expect(FailedRangeCoding.decode("100:18446744073709551616:1") == nil)
        #expect(FailedRangeCoding.decode("100:8:99999999999999999999") == nil)
    }

    /// The invariants the initialiser enforces must also be enforced on the way in, or a helper
    /// could hand the app a range it could not have constructed itself.
    @Test func anInvalidRangeIsRefusedOnDecodeToo() {
        #expect(FailedRangeCoding.decode("100:0:1") == nil)                       // empty range
        #expect(FailedRangeCoding.decode("18446744073709551615:2:1") == nil)      // would trap
    }

    @Test func anUnknownKindCodeIsRefused() {
        for code in ["0", "4", "99", "18446744073709551615"] {
            #expect(FailedRangeCoding.decode("100:8:\(code)") == nil, "accepted kind \(code)")
        }
    }

    /// Separators appearing where a value should be, which is what a naive `components(separatedBy:)`
    /// plus `Int(...)  ?? 0` would turn into block 0.
    @Test func strayAndTrailingSeparatorsAreRefused() {
        for encoded in [";", ";;", "100:8:1;", ";100:8:1", "100::1", ":8:1", "100:8:"] {
            #expect(FailedRangeCoding.decode(encoded) == nil, "accepted \(encoded)")
        }
    }

    /// Nothing a caller can send may crash the decoder, whatever it is.
    @Test func arbitraryTextIsRefusedWithoutCrashing() {
        for encoded in ["no failed block ranges",                 // the human summary, by mistake
                        "blocks 100–107 (8): read error",         // a description, by mistake
                        "{\"ranges\":[]}",
                        "\u{0}",
                        String(repeating: ":", count: 4096),
                        String(repeating: "9", count: 4096)] {
            #expect(FailedRangeCoding.decode(encoded) == nil, "accepted \(encoded.prefix(32))")
        }
    }

    // MARK: - The wire mirror of the kinds

    /// `BlockFailureKind` compiles into the test target from Core's source,
    /// `FailedBlockRangeKind` through the `@testable import`. Separate types for the reason
    /// recorded on each; this is the only place both are visible at once.
    @Test func kindCodesMatchCoresClassification() {
        let pairs: [(BlockFailureKind, FailedBlockRangeKind)] = [
            (.readError, .readError),
            (.writeError, .writeError),
            (.verifyMismatch, .verifyMismatch),
        ]

        for (core, wire) in pairs {
            #expect(core.description == wire.reportName,
                    "one failure must not acquire two names either side of the boundary")
        }
        #expect(pairs.count == FailedBlockRangeKind.allCases.count)
    }

    /// The report and the log line must read identically for the same range, whichever side
    /// printed it — a user comparing the two should not have to work out that they match.
    @Test func aRangeDescribesItselfExactlyAsCoreDoes() {
        let core = BlockRangeFailure(startBlock: 100, blockCount: 8, kind: .readError)
        let wire = FailedBlockRange(startBlock: 100, blockCount: 8, kind: .readError)!
        #expect(core.description == wire.description)

        let oneCore = BlockRangeFailure(startBlock: 7, blockCount: 1, kind: .verifyMismatch)
        let oneWire = FailedBlockRange(startBlock: 7, blockCount: 1, kind: .verifyMismatch)!
        #expect(oneCore.description == oneWire.description)
        #expect(oneWire.description == "block 7: verify mismatch")
    }
}
