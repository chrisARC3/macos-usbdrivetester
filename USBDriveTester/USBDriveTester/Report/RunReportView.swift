//
//  RunReportView.swift
//  USBDriveTester (app target — unprivileged)
//
//  Step 10 (AI-7), BUILD-PLAN 10.4. The end-of-run report on screen, and the "Export report…"
//  action that writes it (FR-RPT-5, NFR-USE-7).
//
//  ## Why the report is a window and not a sheet (user decision 2026-08-06)
//
//  Three things were weighed. A **panel in the main window** would have gone under a device list
//  that is already at `minHeight: 700` with a ~300 pt metrics panel during a run — and Step 9
//  moved the diagnostics form out for exactly that reason. A **sheet** is the conventional shape
//  for a modal result, and it was rejected on **verification**: like the quit confirmation, a
//  sheet gets its own window and `scripts/render-ui.sh` cannot capture it, so every check of this
//  surface would need a person. This project has found three defects by rendering that no
//  assertion caught, and a surface that cannot be rendered gives that up.
//
//  So: a `Window`, single-instance by construction, opened when a run ends and reachable again
//  from the Window menu.
//
//  ## What this view renders, and what it does not decide
//
//  It renders a `RunReport`. Every judgement — the outcome wording, the FR-TEST-9 qualification,
//  what may and may not be said about a drive — was made in `RunReport`, where it is unit-tested.
//  **This file must not add a claim of its own**; if something needs saying about a run, it
//  belongs in the model so the exported file says it too. The screen and the file must not be
//  able to disagree, and the way that is kept true is that both read the same properties.
//
//  ## Why this is a native layout and not the Markdown rendered
//
//  The first version displayed `RunReportMarkdown.render(report)` through
//  `AttributedString(markdown:)`, on the reasoning that one source cannot disagree with itself.
//  **Rendering it showed what that actually looks like** (`render-ui.sh report-qualified`,
//  2026-08-06): `## Outcome` and `| Model | Samsung Portable SSD T5 |` on screen, pipes and
//  hashes included. `.inlineOnlyPreservingWhitespace` interprets bold and code spans and leaves
//  every block-level construct — headings, tables, block quotes — as literal text, and SwiftUI's
//  `Text` cannot render presentation intents even with `.full`. So the "one source" was a source
//  *listing*, shown to a user in place of a report.
//
//  The two media want different things: a `.md` file wants Markdown, a window wants a `Grid`.
//  What must not fork is the **wording**, and it does not — every string below comes from
//  `RunReport`, and `RunReportViewTests` pins the ones that carry a claim.
//
//  Found by looking, not by an assertion. Every test passed against the version that displayed
//  raw pipes.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import os

/// Same category the helper logs a run under, so one predicate shows both sides of it
/// (NFR-OBS-1):
/// `log show --predicate 'subsystem == "com.arc3solutions.USBDriveTester" and category == "io"'`.
private let reportLog = Logger(subsystem: HelperIdentity.loggingSubsystem, category: "io")

// MARK: - The window's content

struct RunReportView: View {

    /// The report, or `nil` when no run has finished this session.
    let report: RunReport?

    /// What "export" does. Injected so the probe can render this view without a save panel, and
    /// so a test could drive the surrounding logic — `NSSavePanel` itself is not testable.
    var exportAction: (RunReport) -> Void = RunReportExport.presentSavePanel

    var body: some View {
        Group {
            if let report {
                reportBody(report)
            } else {
                emptyState
            }
        }
        .frame(minWidth: 620, minHeight: 560)
    }

    // MARK: Idle

    /// Before any run has finished.
    ///
    /// Not a blank window: a window that can be opened from a menu can be opened before there is
    /// anything in it, and "empty" and "broken" look identical unless one of them says which it
    /// is. The same lesson as the metrics panel's idle placeholder in Step 9.
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No run has finished yet")
                .font(.headline)
            Text("""
                 A report appears here when a test run ends. Each run stands alone — no history \
                 is kept — so exporting is the only way to keep one.
                 """)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: The report

    @ViewBuilder
    private func reportBody(_ report: RunReport) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(report)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // FR-TEST-9's statement, above everything else and in every verdict — the
                    // same placement the exported document uses, for the same reason: a reader
                    // must not reach "no block ranges failed" without passing it.
                    prose(report.cacheBypassStatement)
                    if report.verifyResultIsQualified {
                        callout("The refresh half of this run — reading each block and writing "
                              + "it back unchanged — is unaffected and remains valid. It is the "
                              + "fault-detection half that is in doubt.")
                    }

                    section("Drive") { driveRows(report) }
                    if let caveat = report.device.identificationCaveat {
                        callout(caveat, emphasised: true)
                    }

                    section("Run") { runRows(report) }
                    if report.rangeByteCount < report.device.capacityBytes {
                        callout("This run covered the range above, not the whole drive. Blocks "
                              + "outside it were not tested.")
                    }

                    section("Failed block ranges") { failureContent(report) }
                    section("Measurements") { measurementRows(report) }

                    honestFraming(report)
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }

            Divider()
            footer(report)
        }
    }

    private func header(_ report: RunReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // The headline carries its own FR-TEST-9 qualification — see `RunReport.headline`.
            // Icon **and** text, never colour alone (NFR-USE-8).
            Label {
                Text(report.headline).font(.headline)
            } icon: {
                Image(systemName: iconName(report))
                    .foregroundStyle(iconTint(report))
            }
            .fixedSize(horizontal: false, vertical: true)

            Text(report.device.identification)
                .font(.callout)
                .foregroundStyle(.secondary)

            Text(LocalizedStringKey(report.outcome.explanation))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    // MARK: Sections

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.weight(.semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func driveRows(_ report: RunReport) -> some View {
        let device = report.device
        return Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            labelled("Model", device.modelDescription)
            labelled("USB serial number", device.usbSerialNumber ?? "none reported")
            labelled("Capacity", CapacityFormatting.humanReadable(device.capacityBytes))
            labelled("Logical block size", "\(device.logicalBlockSize) bytes")
            if let bsdName = device.bsdNameAtRunTime {
                // The locator, labelled. Shown because a live surface benefits from two
                // identifiers a user can cross-check — and labelled because this one does not
                // survive a replug.
                labelled("Device node at run time", "/dev/\(bsdName) — a locator, not an "
                                                  + "identity; it may name a different drive "
                                                  + "after a replug or a reboot")
            }
        }
    }

    private func runRows(_ report: RunReport) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            labelled("Started", MetricsFormatting.runTimestamp(report.startedAt))
            labelled("Finished", MetricsFormatting.runTimestamp(report.finishedAt))
            labelled("Failure-handling mode", modeName(report.failureMode))
            labelled("I/O size", report.ioSizesUsed
                        .map { "\($0 / (1 << 20)) MiB" }
                        .joined(separator: ", then "))
            labelled("Range tested",
                     "blocks \(MetricsFormatting.blockOffset(report.startBlock))–"
                   + "\(MetricsFormatting.blockOffset(report.startBlock + report.blockCount - 1))"
                   + " (\(CapacityFormatting.humanReadable(report.rangeByteCount)))")
            labelled("Chunks processed", MetricsFormatting.blockOffset(report.chunksProcessed))
        }
    }

    @ViewBuilder
    private func failureContent(_ report: RunReport) -> some View {
        // A list that could not be read is not an empty list, and must never look like one.
        if report.failureListIsUnavailable {
            callout("The list of failed ranges could not be read. The helper reported "
                  + "\(report.totalFailedRangeCount) failed range(s) and "
                  + "\(report.failedBlockCount) failing block(s), but the list itself could not "
                  + "be decoded by this build. Do not read this as \"no failures\".",
                    emphasised: true)
        } else if let ranges = report.failedRanges, ranges.isEmpty, report.failedBlockCount == 0 {
            Text("No block ranges failed.").font(.callout)
        } else if let ranges = report.failedRanges {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 3) {
                GridRow {
                    Text("First block").gridColumnAlignment(.trailing)
                    Text("Last block").gridColumnAlignment(.trailing)
                    Text("Blocks").gridColumnAlignment(.trailing)
                    Text("Failure")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

                ForEach(ranges, id: \.startBlock) { range in
                    GridRow {
                        Text(MetricsFormatting.blockOffset(range.startBlock))
                        Text(MetricsFormatting.blockOffset(range.endBlock - 1))
                        Text(MetricsFormatting.blockOffset(range.blockCount))
                        Text(range.kind.reportName)
                    }
                    .font(.callout.monospacedDigit())
                }
            }
            Text("\(MetricsFormatting.blockOffset(report.failedBlockCount)) block(s) failed "
               + "across \(report.totalFailedRangeCount) range(s).")
                .font(.callout.weight(.semibold))

            // A truncated list that does not say so reads exactly like a complete one.
            if let dropped = report.droppedRangeCount, dropped > 0 {
                callout("This list is truncated: \(dropped) further range(s) are not shown. The "
                      + "block count above includes every failing block, shown or not.",
                        emphasised: true)
            }
        }
    }

    private func measurementRows(_ report: RunReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                labelled("Average read throughput",
                         MetricsFormatting.throughput(report.readBytesPerSecond))
                labelled("Average write throughput",
                         MetricsFormatting.throughput(report.writeBytesPerSecond))
                if let linkSpeed = report.usbLinkSpeedDescription {
                    labelled("Negotiated USB link speed", linkSpeed)
                }
                labelled("Read latency, minimum",
                         MetricsFormatting.latency(report.readLatencyMinimum))
                labelled("Read latency, maximum",
                         MetricsFormatting.latency(report.readLatencyMaximum))
                // The upper bound, spelled as one.
                labelled("Read latency, p99",
                         MetricsFormatting.percentileUpperBound(report.readLatencyP99UpperBound))
                labelled("Reads measured",
                         MetricsFormatting.blockOffset(report.readLatencySampleCount))
            }

            prose("Throughput is reported, not graded. Whether a rate indicates wear is a "
                + "judgement against the manufacturer's advertised sustained figure for this "
                + "model and the negotiated link speed above — neither of which this tool knows. "
                + "It measures; it does not diagnose.")

            if report.latencySpansMultipleIOSizes {
                callout("The I/O size changed during this run and the latency statistics "
                      + "accumulate across the change, so these figures span more than one "
                      + "transfer size.")
            }
        }
    }

    /// FR-WARN-3/4 and NFR-USE-6, echoed on the result surface as well as into the file.
    ///
    /// - Note: the wording comes from `HonestFraming`, shared with the exported report and Step
    ///   14's pre-run dialog. It used to be written here as a second set of literals, and on
    ///   2026-08-10 those were found to have drifted from the report's: this surface had lost the
    ///   clause explaining *why* a matching verify does not prove retention, and had reworded the
    ///   dual-role opener. Nothing failed, because no test compared them.
    private func honestFraming(_ report: RunReport) -> some View {
        section("What this test does and does not prove") {
            VStack(alignment: .leading, spacing: 6) {
                prose(HonestFraming.summary.plain)
                ForEach(HonestFraming.claims) { claim in
                    bullet(claim.plain)
                }
                if report.outcome == .stoppedOnError {
                    bullet(HonestFraming.rangeBeyondTheFailureWasNotTested.plain)
                }
            }
        }
    }

    // MARK: Small pieces

    private func labelled(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
            Text(value)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
    }

    /// Model prose, with its inline Markdown interpreted.
    ///
    /// These strings carry `**bold**` because the exported `.md` needs it, and a plain
    /// `Text(String)` renders the asterisks literally — which is what the first render of this
    /// view showed. `Text(LocalizedStringKey:)` is the initialiser that parses inline Markdown,
    /// and inline is all these strings contain.
    private func prose(_ text: String) -> some View {
        Text(LocalizedStringKey(text))
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("•").foregroundStyle(.secondary)
            Text(LocalizedStringKey(text))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
    }

    private func callout(_ text: String, emphasised: Bool = false) -> some View {
        Text(LocalizedStringKey(text))
            .font(.callout)
            .fontWeight(emphasised ? .semibold : .regular)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    private func modeName(_ mode: FailureModeCode) -> String {
        switch mode {
        case .stopOnFirstError: return "Stop on first error"
        case .logAndContinue:   return "Log and continue"
        case .unrecognised:     return "not reported"
        }
    }

    private func footer(_ report: RunReport) -> some View {
        HStack {
            Text("No run history is kept. Exporting is the only way to keep this report.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Export report…") { exportAction(report) }
                .keyboardShortcut("s", modifiers: .command)
        }
        .padding(12)
    }

    /// Pass/fail conveyed by **icon and text**, never by colour alone (NFR-USE-8). The tint is an
    /// addition to a distinguishable symbol, not the carrier of the meaning — the headline above
    /// says it in words regardless.
    private func iconName(_ report: RunReport) -> String {
        if report.verifyResultIsQualified { return "questionmark.circle.fill" }
        switch report.outcome {
        case .completedClean:        return "checkmark.circle.fill"
        case .completedWithFailures: return "exclamationmark.triangle.fill"
        case .stoppedOnError:        return "stop.circle.fill"
        case .incomplete:            return "exclamationmark.circle.fill"
        }
    }

    private func iconTint(_ report: RunReport) -> Color {
        if report.verifyResultIsQualified { return .orange }
        return report.outcome.foundFailures || report.outcome == .incomplete ? .orange : .green
    }

}

// MARK: - Writing it out (FR-RPT-5)

/// The export action, kept out of the view so what it decides is visible in one place.
enum RunReportExport {

    /// The type a `.md` file is, or plain text if the system does not know it.
    static var markdownType: UTType { UTType(filenameExtension: "md") ?? .plainText }

    /// Ask where to write, then write (FR-RPT-5, NFR-USE-7).
    ///
    /// The App Sandbox is off for this app (it has to be — the helper's registration and the raw
    /// device work depend on it), so this needs no security-scoped bookmark and no entitlement.
    @MainActor
    static func presentSavePanel(_ report: RunReport) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [markdownType]
        // Keyed on the **serial** and the time, never the BSD name: a folder of `disk4-…`
        // reports would be a folder of files that no longer say which drive each is about.
        panel.nameFieldStringValue = report.suggestedFileName()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = "Export run report"
        panel.message = "Each run stands alone — no history is kept, so this is the only copy "
                      + "that will exist."

        guard panel.runModal() == .OK, let url = panel.url else {
            reportLog.notice("run report export cancelled")
            return
        }

        do {
            try write(report, to: url)
        } catch {
            // **The alert belongs here, not in `write`.** An export that failed and said nothing
            // would leave a user believing they had a file — and each run stands alone, so the
            // file they think they have is the only copy that was ever going to exist.
            NSAlert(error: error).runModal()
        }
    }

    /// Write the report to `url`, logging either way (NFR-OBS-1).
    ///
    /// **Throws rather than presenting anything.** It was written to show an `NSAlert` on
    /// failure, and the test for the failure path hung the test runner on a modal dialog — which
    /// is the shape of the problem rather than an inconvenience: a function that writes a file
    /// and also puts a window on screen cannot be exercised anywhere a window would be wrong,
    /// and the failure path is precisely the one worth exercising. The panel above owns the UI;
    /// this owns the file.
    static func write(_ report: RunReport, to url: URL) throws {
        let markdown = RunReportMarkdown.render(report)
        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            // Addressing and outcome only — never device contents, and never the file's
            // contents (NFR-SEC-6). The path is the user's own choice and is theirs to see.
            reportLog.notice("""
                             run report exported: outcome \(report.outcome.headline, privacy: .public); \
                             drive serial \(report.device.usbSerialNumber ?? "none", privacy: .public); \
                             \(markdown.count, privacy: .public) bytes
                             """)
        } catch {
            reportLog.error("""
                            run report export FAILED: \(error.localizedDescription, privacy: .public)
                            """)
            throw error
        }
    }
}

// MARK: - Logging what a run concluded (BUILD-PLAN 10.6, NFR-OBS-1)

enum RunReportLog {

    /// The user chose a failure-handling mode.
    ///
    /// Logged where the *choice* is made rather than where the run starts, because those are two
    /// events and a run that never started still had a mode selected for it.
    static func modeSelected(_ mode: FailureModeCode) {
        reportLog.notice("failure-handling mode selected: \(String(describing: mode), privacy: .public)")
    }

    /// A run concluded and produced a report.
    ///
    /// The helper logs its own view of the outcome under the same category; this is the app's,
    /// in the report's honest wording — which is the wording the user will have read.
    static func reportProduced(_ report: RunReport) {
        reportLog.notice("""
                         run report: \(report.outcome.headline, privacy: .public); \
                         mode \(String(describing: report.failureMode), privacy: .public); \
                         drive serial \(report.device.usbSerialNumber ?? "none", privacy: .public); \
                         \(report.failedBlockCount, privacy: .public) failing block(s) in \
                         \(report.totalFailedRangeCount, privacy: .public) range(s); \
                         verify result qualified: \(report.verifyResultIsQualified, privacy: .public)
                         """)
    }

    /// A call the helper refused, which is **not** a run and gets no report.
    ///
    /// Logged so the absence of a report after pressing the button is explicable from the log
    /// rather than looking like a lost one.
    static func noReportForRefusedCall(_ message: String) {
        reportLog.notice("""
                         no run report: the helper refused the call, so no run took place — \
                         \(message, privacy: .public)
                         """)
    }
}
