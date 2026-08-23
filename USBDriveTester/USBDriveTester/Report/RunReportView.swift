//
//  RunReportView.swift
//  USBDriveTester (app target — unprivileged)
//
//  Step 10 (AI-7), BUILD-PLAN 10.4. The end-of-run report on screen, and the "Export report…"
//  action that writes it (FR-RPT-5, NFR-USE-7).
//
//  ## It was a window until Step 11 increment 8, and is now a sheet (user decision 2026-08-19)
//
//  **The 2026-08-06 decision, recorded and superseded.** A **panel in the main window** would have
//  gone under a device list already asking for 700 pt with a ~300 pt metrics panel beside it — the
//  reason Step 9 moved the diagnostics form out. A **sheet** was rejected on *verification*: like
//  the quit confirmation, a sheet gets its own window and `scripts/render-ui.sh` cannot capture it,
//  so every check of this surface would need a person. So: a `Window`.
//
//  **That reason was wrong, and measurably so.** `render-ui.sh` and `window-fit-check.sh` compile
//  the app's sources with `USBDriveTesterApp.swift` **excluded by name**, and host this view
//  directly. The scene was never involved in a render, and all seven report render cases are
//  unchanged by the move — the same arrangement `PreRunPromptSheet` has always used, and its own
//  note in `tools/ui-probe` records the same limit. What a sheet actually costs is *in-place*
//  capture, the report as it sits on its parent, which these renders never had.
//
//  **What changed the decision was hardware.** Starting a run underneath an open report emptied it,
//  because a beginning run clears `AppModel.lastRunReport` — the previous run's report is not this
//  run's. A sheet is window-modal, so the run controls are out of reach while it is up and the
//  report must be dismissed before a run can start: the defect becomes unreachable by construction
//  instead of guarded against.
//
//  ## The size is the window's, and there is no constant here any more
//
//  `.frame(minWidth: 620, minHeight: 560)` stood here for the window era and is gone. `ContentView`
//  sizes the sheet to the main window's content area less a margin, so this view's floor **is** the
//  main window's floor — which `scripts/window-fit-check.sh` already governs against NFR-USE-9 —
//  rather than a second number that expires quietly. Increment 7's lesson applied to this view: the
//  620x560 was chosen for a window the user could drag bigger, and a sheet cannot be dragged.
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
//  `RunReport` or from `HonestFraming`.
//
//  ## NOTHING IN THIS FILE IS UNDER TEST, AND A COMMENT HERE CLAIMED OTHERWISE FOR FOUR STEPS
//
//  The sentence above used to end *"…and `RunReportViewTests` pins the ones that carry a claim."*
//  **There is no such file and there never has been.** Step 11 increment 8 went looking for it
//  while predicting which mutations would survive, and found a citation to cover that does not
//  exist — the same failure as the three source references to `NFR-USE-8` that pointed at an
//  accessibility requirement saying nothing about window size (CONSTRAINTS section 3: *a
//  requirement you are about to cite may not exist*). A wrong citation is worse than none,
//  because it reads as having been checked.
//
//  What actually holds this file honest, measured rather than asserted — increment 8 mutated it
//  three times, in two rounds, and the whole suite passed every time (M13 against 1,008 tests; N10
//  and N11 against 1,013):
//
//    * every claim-bearing string is `RunReport`'s or `HonestFraming`'s, and the **model** side of
//      each is pinned there, which is what stops the wording forking between this window and the
//      exported file;
//    * that those values are actually *rendered here* is covered by `scripts/render-ui.sh` and by
//      the human checklist — item 7.2, which reads the window and the export side by side. That
//      pair is the whole of it.
//
//  So: deleting a paragraph from this view is invisible to 1,013 tests. Treat an edit here as
//  unverified until it has been rendered and looked at.
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

    /// Dismisses the report. **No default**, so every call site has to answer: a sheet with no way
    /// out is a modal the user cannot leave, and this view spent four steps as a window where the
    /// title bar answered it for free.
    let onDone: () -> Void

    var body: some View {
        Group {
            if let report {
                reportBody(report)
            } else {
                emptyBody
            }
        }
        // Escape, which is what a macOS sheet is expected to answer. `Done` takes the default
        // action, so Return works as well and neither key is the only way out.
        .onExitCommand(perform: onDone)
    }

    // MARK: Idle

    /// The empty state and the one control a sheet cannot do without.
    ///
    /// **The empty state had no footer at all while this was a window**, because the title bar
    /// closed it. Nothing in the suite would have noticed: no test drives this view.
    private var emptyBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            emptyState
            Divider()
            HStack {
                Spacer()
                doneButton
            }
            .padding(12)
        }
    }

    /// Before any run has finished.
    ///
    /// Not a blank panel: a report that can be raised from a menu can be raised before there is
    /// anything in it, and "empty" and "broken" look identical unless one of them says which it
    /// is. The same lesson as the metrics panel's idle placeholder in Step 9.
    private var emptyState: some View {
        VStack(spacing: 12) {
            // Decorative — "No run has finished yet" below says it.
            Image(systemName: "doc.text")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
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
                    // Which caveats this run's range carries is `RunReport`'s decision, from
                    // `HonestFraming`'s wording. It was a literal and a condition of its own here,
                    // with a second copy of both in the Markdown renderer.
                    ForEach(report.rangeCaveats) { caveat in
                        callout(caveat.plain)
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
                        .map(IOSizeSelection.label)
                        .joined(separator: ", then "))
            // **Requested, not tested.** See `RunReport.rangeByteCount` for why the word changed:
            // a stopped run's requested range is not the range it reached, and this row was
            // asserting the second while holding the first.
            labelled("Range requested",
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
                labelled("Read throughput",
                         MetricsFormatting.throughput(report.sustainedReadBytesPerSecond))
                labelled("Write throughput",
                         MetricsFormatting.throughput(report.sustainedWriteBytesPerSecond))
                labelled("Covering",
                         MetricsFormatting.throughput(report.coverageBytesPerSecond))
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

            // Both from `ThroughputFraming`, never literals here. The screen carried its own
            // copy until 2026-08-18 and it was the STALE one — still naming the advertised figure
            // as the comparison basis after the exported report had stopped doing so.
            prose(ThroughputFraming.definition.plain)
            prose(ThroughputFraming.notGraded.plain)

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
                // The same decision the exported file makes, from the same place. Two `if`s
                // deciding this independently is how the window and the export came to disagree
                // on 2026-08-18.
                if let added = HonestFraming.claim(addedBy: report.outcome) {
                    bullet(added.plain)
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
            doneButton
        }
        .padding(12)
    }

    /// Dismisses the sheet.
    ///
    /// A sheet has no title bar, so this button **is** the close box. It takes the default action
    /// because dismissing is what a reader does when they have finished reading — and because the
    /// alternative default, Export, writes a file.
    private var doneButton: some View {
        Button("Done", action: onDone)
            .keyboardShortcut(.defaultAction)
    }

    /// Pass/fail conveyed by **icon and text**, never by colour alone (NFR-USE-8). The tint is an
    /// addition to a distinguishable symbol, not the carrier of the meaning — the headline above
    /// says it in words regardless.
    ///
    /// The decision itself moved to `RunReportPresentation` on 2026-08-11 so a test could reach it;
    /// see that file for why. What is left here is the one thing that genuinely needs SwiftUI:
    /// turning a meaning into a colour.
    private func presentation(_ report: RunReport) -> RunReportPresentation {
        RunReportPresentation.forResult(outcome: report.outcome,
                                        verifyResultIsQualified: report.verifyResultIsQualified)
    }

    private func iconName(_ report: RunReport) -> String { presentation(report).symbolName }

    private func iconTint(_ report: RunReport) -> Color {
        switch presentation(report).tint {
        case .affirmative: return .green
        case .cautionary:  return .orange
        }
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

    /// A run produced a report with **no drive record behind it**, so the report cannot say which
    /// drive it is about.
    ///
    /// Should be unreachable: the run control's precondition is a held device, and the held device
    /// is what the pre-run dialog just named. Logged at `error` rather than absorbed because the
    /// silent version of this is what shipped — until 2026-08-11 an unidentified report was produced
    /// by a `??` with nothing to say it had happened, and the only reason it was caught is that a
    /// person read an exported file and noticed the model, serial and capacity were missing.
    ///
    /// The same reasoning as `PreRunWarningLog.promptRaisedForAnUnnamedDrive`, at the other end of
    /// the same run: an inconsistency the code cannot resolve is logged, never quietly rendered.
    static func reportBuiltWithNoHeldDevice() {
        reportLog.error("""
                        run report built with NO held device — the report cannot identify its \
                        drive. The run control requires a held device, so this state should be \
                        unreachable; treat any report from this run as unattributable.
                        """)
    }
}
