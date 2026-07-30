//
//  CapacityFormattingTests.swift
//  NFR-USE-3 / NFR-USE-1 — capacities the user can reconcile against the drive label.
//
//  The capacities asserted here are the real byte counts reported by the devices on
//  the development machine, so "1.00 TB" is being checked against the number IOKit
//  actually produces for a drive labelled 1 TB — which is the only claim that matters.
//
//  Separators are passed explicitly wherever a grouped number is asserted. The
//  production defaults follow the user's locale, and a test that hard-codes a comma
//  while relying on the default would pass in one region and fail in another for no
//  reason connected to the code.
//

import Testing
import Foundation
@testable import USBDriveTester

struct CapacityFormattingTests {

    // MARK: - Small counts are shown exactly

    @Test func zeroBytes() {
        #expect(CapacityFormatting.humanReadable(0) == "0 bytes")
    }

    @Test func oneByteIsSingular() {
        #expect(CapacityFormatting.humanReadable(1) == "1 byte")
    }

    @Test func aSingleBlockIsShownAsBytes() {
        #expect(CapacityFormatting.humanReadable(512) == "512 bytes")
        #expect(CapacityFormatting.humanReadable(999) == "999 bytes")
    }

    // MARK: - Base-10 scaling

    @Test func scalingStartsAtOneThousand() {
        #expect(CapacityFormatting.humanReadable(1000) == "1.00 kB")
    }

    @Test func realDrivesFormatAsTheirLabels() {
        // Samsung Portable SSD T5 and SSD 990 EVO Plus, both labelled 1 TB.
        #expect(CapacityFormatting.humanReadable(1_000_204_886_016) == "1.00 TB")
        // Seagate Expansion HDD, labelled 22 TB.
        #expect(CapacityFormatting.humanReadable(22_000_969_973_248) == "22.00 TB")
        // Internal Apple SSD, labelled 256 GB.
        #expect(CapacityFormatting.humanReadable(251_000_193_024) == "251.00 GB")
    }

    @Test func anEFIPartitionSizedCount() {
        #expect(CapacityFormatting.humanReadable(209_715_200) == "209.72 MB")
    }

    /// The unit is re-checked *after* rounding. This exact count is what the
    /// synthesized APFS container on the 1 TB test drive reports: below the 1 TB
    /// threshold before rounding, not after it. Without the re-check it formats as the
    /// nonsense "1000.00 GB".
    @Test func aCountThatRoundsUpAcrossAUnitBoundaryIsPromoted() {
        #expect(CapacityFormatting.humanReadable(999_995_129_856) == "1.00 TB")
    }

    @Test func justBelowAUnitBoundaryIsNotPromoted() {
        // 999.00 GB rounds to itself and must stay in GB.
        #expect(CapacityFormatting.humanReadable(999_000_000_000) == "999.00 GB")
    }

    /// The largest count expressible at all — the formatter must not run off the end
    /// of its unit table (NFR-COMPAT-6 is about not having capacity limits).
    @Test func theLargestPossibleCountFormats() {
        #expect(CapacityFormatting.humanReadable(UInt64.max) == "18.45 EB")
    }

    /// Two decimal places exist to distinguish drives of similar size.
    @Test func twoDecimalPlacesDiscriminateSimilarDrives() {
        #expect(CapacityFormatting.humanReadable(1_000_204_886_016) !=
                CapacityFormatting.humanReadable(1_020_204_886_016))
    }

    // MARK: - Digit grouping

    @Test func groupsFromTheRight() {
        #expect(CapacityFormatting.grouped(0, separator: ",") == "0")
        #expect(CapacityFormatting.grouped(999, separator: ",") == "999")
        #expect(CapacityFormatting.grouped(1000, separator: ",") == "1,000")
        #expect(CapacityFormatting.grouped(1_953_525_168, separator: ",") == "1,953,525,168")
    }

    @Test func groupsTheLargestValue() {
        #expect(CapacityFormatting.grouped(UInt64.max, separator: ",")
                == "18,446,744,073,709,551,615")
    }

    @Test func honoursANonCommaSeparator() {
        #expect(CapacityFormatting.grouped(1_000_204_886_016, separator: " ")
                == "1 000 204 886 016")
    }

    // MARK: - Exact byte counts

    /// The figure the user reconciles against `diskutil info`, which reports the T5 as
    /// "1.0 TB (1000204886016 Bytes)".
    @Test func exactBytesMatchesDiskutil() {
        #expect(CapacityFormatting.exactBytes(1_000_204_886_016, groupingSeparator: ",")
                == "1,000,204,886,016 bytes")
    }

    @Test func exactBytesIsSingularForOne() {
        #expect(CapacityFormatting.exactBytes(1, groupingSeparator: ",") == "1 byte")
    }
}
