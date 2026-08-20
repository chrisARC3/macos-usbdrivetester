//
//  RunReportMarkdown.swift
//  USBDriveTester (app target — unprivileged)
//
//  Step 10 (AI-7), BUILD-PLAN 10.4. FR-RPT-5's Markdown export and NFR-USE-7's shape for it:
//  headings, a clear pass/fail outcome line, and **tabulated** bad-block ranges and statistics.
//
//  A pure function of a `RunReport`. No file system, no save panel, no clock — increment 5 owns
//  where the string goes. That separation is what lets every claim below be asserted in a test.
//
//  ## The order of the document is an argument, not a layout
//
//  Outcome, then the qualification, then the drive, then the failures, then the numbers.
//
//  **The FR-TEST-9 statement sits directly under the outcome line, above everything else**, and
//  that placement is the requirement rather than a preference. This file outlives the session,
//  the UI banner and any memory of which runs were qualified; a reader skimming for the verdict
//  must not be able to reach "no bad blocks were found" without also reading whether the check
//  that looked for them could be trusted. Below the tables it would be a footnote to a conclusion
//  already drawn.
//
//  ## Two things this renderer will not print
//
//  - **A grade.** Throughput appears beside the negotiated link speed so a reader can judge it
//    against the manufacturer's advertised sustained figure. No threshold, no verdict, no
//    "healthy/slow" (user decision 2026-08-04).
//  - **`0` or `—` standing in for a measurement that was not taken.** An em-dash renders for
//    absent figures, and it is visibly not a number. `0 MB/s` means *stalled*.
//

import Foundation

/// Renders a ``RunReport`` as Markdown (FR-RPT-5, NFR-USE-7).
nonisolated enum RunReportMarkdown {

    /// The document.
    ///
    /// - Parameter timeZone: injected so a test can pin the timestamps. The default is the
    ///   reader's own zone, which is what makes the times mean anything to them.
    static func render(_ report: RunReport, timeZone: TimeZone = .current) -> String {
        var lines: [String] = []

        lines.append("# USB drive test report")
        lines.append("")

        // The outcome, then immediately what qualifies it. Nothing goes between them.
        lines.append("## Outcome")
        lines.append("")
        // `report.headline`, not `report.outcome.headline`: the qualification travels in the bold
        // line, because that is the line a reader skimming for the verdict takes. See
        // `RunReport.headline` for what rendering the earlier version made obvious.
        lines.append("**\(report.headline)**")
        lines.append("")
        lines.append(report.outcome.explanation)
        lines.append("")
        lines.append(report.cacheBypassStatement)
        lines.append("")

        if report.verifyResultIsQualified {
            lines.append("> The refresh half of this run — reading each block and writing it "
                       + "back unchanged — is unaffected and remains valid. It is the "
                       + "fault-detection half that is in doubt.")
            lines.append("")
        }

        lines.append(contentsOf: driveSection(report))
        lines.append(contentsOf: runSection(report, timeZone: timeZone))
        lines.append(contentsOf: failureSection(report))
        lines.append(contentsOf: statisticsSection(report))
        lines.append(contentsOf: whatThisDoesNotProve(report))

        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - The drive

    private static func driveSection(_ report: RunReport) -> [String] {
        let device = report.device
        var lines = ["## Drive", ""]

        // Identity first and by serial. The BSD name is a row further down and is labelled as
        // the locator it was — never as the answer to "which drive was tested?".
        lines.append("| | |")
        lines.append("|---|---|")
        lines.append(row("Model", device.modelDescription))
        lines.append(row("USB serial number", device.usbSerialNumber ?? "*none reported*"))
        lines.append(row("Capacity", CapacityFormatting.humanReadable(device.capacityBytes)
                                   + " (\(grouped(device.capacityBytes)) bytes)"))
        lines.append(row("Logical block size", "\(device.logicalBlockSize) bytes"))
        if let bsdName = device.bsdNameAtRunTime {
            // Labelled, and the label is doing real work.
            lines.append(row("Device node at run time", "`/dev/\(bsdName)` — a locator, not an "
                                                      + "identity; it may name a different "
                                                      + "drive after a replug or a reboot"))
        }
        lines.append("")

        if let caveat = device.identificationCaveat {
            lines.append("> **\(caveat)**")
            lines.append("")
        }

        return lines
    }

    // MARK: - The run

    private static func runSection(_ report: RunReport, timeZone: TimeZone) -> [String] {
        var lines = ["## Run", ""]
        lines.append("| | |")
        lines.append("|---|---|")
        lines.append(row("Started", timestamp(report.startedAt, timeZone: timeZone)))
        lines.append(row("Finished", timestamp(report.finishedAt, timeZone: timeZone)))
        lines.append(row("Elapsed", elapsed(report.duration)))
        lines.append(row("Failure-handling mode", modeName(report.failureMode)))
        lines.append(row("I/O size", ioSizes(report)))
        lines.append(row("Range tested", "blocks \(grouped(report.startBlock))–"
                                       + "\(grouped(report.startBlock + report.blockCount - 1)) "
                                       + "(\(grouped(report.blockCount)) blocks, "
                                       + "\(CapacityFormatting.humanReadable(report.rangeByteCount)))"))
        lines.append(row("Chunks processed", grouped(report.chunksProcessed)))
        lines.append("")

        // A bounded range is not the whole drive, and a report that did not say so would invite
        // being read as a whole-device pass. Whole-device runs arrive with Step 11.
        if report.blockCount * UInt64(report.device.logicalBlockSize) < report.device.capacityBytes {
            lines.append("> This run covered the range above, **not the whole drive**. Blocks "
                       + "outside it were not tested.")
            lines.append("")
        }

        return lines
    }

    /// The I/O size, and the caveat that comes with more than one of them.
    private static func ioSizes(_ report: RunReport) -> String {
        let sizes = report.ioSizesUsed
        guard !sizes.isEmpty else { return MetricsFormatting.unknown }
        let names = sizes.map(IOSizeSelection.label)
        guard report.latencySpansMultipleIOSizes else { return names[0] }
        return names.joined(separator: ", then ")
             + " — the read-latency figures below span all of them"
    }

    // MARK: - The failures (FR-RPT-1)

    private static func failureSection(_ report: RunReport) -> [String] {
        var lines = ["## Failed block ranges", ""]

        // A list that could not be read is not an empty list, and must never render as one.
        guard let ranges = report.failedRanges else {
            lines.append("> **The list of failed ranges could not be read.** The privileged "
                       + "helper reported \(grouped(UInt64(max(0, report.totalFailedRangeCount)))) "
                       + "failed range(s) and \(grouped(report.failedBlockCount)) failing "
                       + "block(s), but the list itself could not be decoded by this build — "
                       + "usually a sign that the helper is a newer version than the app. "
                       + "**Do not read this section as \"no failures\".**")
            lines.append("")
            return lines
        }

        if ranges.isEmpty && report.failedBlockCount == 0 {
            lines.append("No block ranges failed.")
            lines.append("")
            return lines
        }

        lines.append("| First block | Last block | Blocks | Failure |")
        lines.append("|---|---|---|---|")
        for range in ranges {
            lines.append("| \(grouped(range.startBlock)) "
                       + "| \(grouped(range.endBlock - 1)) "
                       + "| \(grouped(range.blockCount)) "
                       + "| \(range.kind.reportName) |")
        }
        lines.append("")

        lines.append("**\(grouped(report.failedBlockCount)) block(s) failed across "
                   + "\(grouped(UInt64(max(0, report.totalFailedRangeCount)))) range(s).**")
        lines.append("")

        // A truncated list that does not say so reads exactly like a complete one.
        if let dropped = report.droppedRangeCount, dropped > 0 {
            lines.append("> **This list is truncated.** \(grouped(UInt64(dropped))) further "
                       + "range(s) are not shown: the helper retains a bounded number so that a "
                       + "badly failing drive cannot produce an unbounded list. The block count "
                       + "above includes every failing block, shown or not.")
            lines.append("")
        }

        lines.append("A *read error* means the drive could not return the data at all. A *write "
                   + "error* means it refused the write, so nothing was verified there. A "
                   + "*verify mismatch* means the drive accepted the write, reported success, "
                   + "and returned different bytes when the range was read back.")
        lines.append("")

        return lines
    }

    // MARK: - The numbers (FR-RPT-2/3)

    private static func statisticsSection(_ report: RunReport) -> [String] {
        var lines = ["## Measurements", ""]

        lines.append("| | |")
        lines.append("|---|---|")
        lines.append(row("Read throughput",
                         MetricsFormatting.throughput(report.sustainedReadBytesPerSecond)))
        lines.append(row("Write throughput",
                         MetricsFormatting.throughput(report.sustainedWriteBytesPerSecond)))
        lines.append(row("Covering",
                         MetricsFormatting.throughput(report.coverageBytesPerSecond)))
        if let linkSpeed = report.usbLinkSpeedDescription {
            lines.append(row("Negotiated USB link speed", linkSpeed))
        }
        lines.append(row("Read latency, minimum",
                         MetricsFormatting.latency(report.readLatencyMinimum)))
        lines.append(row("Read latency, maximum",
                         MetricsFormatting.latency(report.readLatencyMaximum)))
        // The upper bound, spelled as one. See below for why the report says it twice.
        lines.append(row("Read latency, p99",
                         MetricsFormatting.percentileUpperBound(report.readLatencyP99UpperBound)))
        lines.append(row("Reads measured", grouped(report.readLatencySampleCount)))
        lines.append("")

        // **The definition travels with the numbers.** A rate whose denominator is unstated
        // cannot be checked against anything, and the first person to check ours against
        // Activity Monitor reported them as a defect (2026-08-17) — correctly. The report is the
        // copy that gets forwarded and re-read months later, detached from any screen, so it is
        // the artefact that most needs to say what it measured.
        lines.append(ThroughputFraming.definition.markdown)
        lines.append("")

        // Throughput is reported and never graded (user decision 2026-08-04). Saying so in the
        // report matters more than saying it in the UI: a bare pair of numbers in a file invites
        // the reader to supply the missing verdict themselves, and the honest thing is to name
        // what they would need in order to.
        // Deliberately does NOT restate the denominator: the paragraph above defines it, and
        // saying it twice is how the two came to disagree. Found by reading the rendered report
        // rather than the source — this said "against the wall clock" while the paragraph above
        // it said "the time the run spent working" (2026-08-18).
        lines.append(ThroughputFraming.notGraded.markdown)
        lines.append("")

        if report.readLatencySampleCount > 0 {
            lines.append("The **p99 is an upper bound**: the true value is at or below the figure "
                       + "shown, within one histogram bucket. A single number here would be a "
                       + "bucket's midpoint presented as a measurement.")
            lines.append("")
        }

        if report.latencySpansMultipleIOSizes {
            lines.append("> The I/O size changed during this run, and the latency statistics "
                       + "accumulate across the change. The distribution therefore spans more "
                       + "than one transfer size, and these figures should not be compared with "
                       + "a run that used a single size throughout.")
            lines.append("")
        }

        return lines
    }

    // MARK: - The honest framing (BUILD-PLAN 10.5, FR-WARN-3/4, NFR-USE-6)

    /// Echoed into the report, not only shown before the run.
    ///
    /// NFR-USE-6 requires a clean pass not to be reasonably mistakable for a health certificate,
    /// and Step 14's detailed step 3 asks for this framing on the result *and* in the report's
    /// wording. The report is the copy that gets forwarded, filed and re-read months later,
    /// detached from whatever was on screen at the time.
    ///
    /// - Note: the wording is **not** written here. It comes from `HonestFraming`, which is the
    ///   single definition shared with the result screen and Step 14's pre-run dialog. Until
    ///   2026-08-10 this function held its own literals and the result screen held a second set —
    ///   and they had already drifted, the screen having lost the clause explaining why a matching
    ///   verify does not prove retention. Re-inlining a sentence here re-creates that.
    private static func whatThisDoesNotProve(_ report: RunReport) -> [String] {
        var lines = ["## What this test does and does not prove", ""]

        lines.append(HonestFraming.summary.markdown)
        lines.append("")
        for claim in HonestFraming.claims {
            lines.append("- \(claim.markdown)")
        }
        if report.outcome == .stoppedOnError {
            lines.append("- \(HonestFraming.rangeBeyondTheFailureWasNotTested.markdown)")
        }
        lines.append("")

        return lines
    }

    // MARK: - Formatting

    private static func row(_ label: String, _ value: String) -> String {
        "| \(label) | \(value) |"
    }

    /// Digit-grouped, so a nine-digit block number can be read and compared at a glance.
    private static func grouped(_ value: UInt64) -> String {
        MetricsFormatting.blockOffset(value)
    }

    /// Date and time with the offset spelled out.
    ///
    /// ISO 8601 rather than a localised style, and this is deliberate for a **persisted** file:
    /// `05/08/2026` is 5 August or 8 May depending on who reads it, and a report is exactly the
    /// kind of document that travels to somebody else. The zone offset is included because a
    /// bare local time is ambiguous the moment the file leaves the machine that wrote it.
    private static func timestamp(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withFullDate, .withSpaceBetweenDateAndTime,
                                   .withTime, .withColonSeparatorInTime,
                                   .withTimeZone, .withColonSeparatorInTimeZone]
        return formatter.string(from: date)
    }

    private static func elapsed(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return "\(hours) h \(minutes) min \(seconds) s" }
        if minutes > 0 { return "\(minutes) min \(seconds) s" }
        return String(format: "%.1f s", interval)
    }

    private static func modeName(_ mode: FailureModeCode) -> String {
        switch mode {
        case .stopOnFirstError: return "Stop on first error"
        case .logAndContinue:   return "Log and continue"
        case .unrecognised:     return "*not reported*"
        }
    }
}
