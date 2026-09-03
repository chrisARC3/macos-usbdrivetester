//
//  RunMetricsView.swift
//  USBDriveTester (app target — unprivileged)
//
//  Step 9 (AI-8). The live metrics display: FR-METR-2 (throughput), FR-METR-4 (read latency),
//  FR-METR-5/6 (progress, position, ETA), NFR-USE-1 (clear units), NFR-USE-2 (progress conveyed
//  clearly), NFR-PERF-4 (the GUI only renders snapshots — it computes nothing and does no I/O).
//
//  ## Presentation is separated from polling on purpose
//
//  ``RunMetricsView`` is a **pure function of a snapshot**. It owns no timer, no connection and
//  no state, which is what lets `scripts/render-ui.sh metrics` render it from a fixture and check
//  the layout headlessly — the same reason `tools/ui-probe` exists at all. A view that fetched
//  its own data could only be seen by running the signed app against a live daemon.
//
//  ``LiveRunMetricsPanel`` is the thin shell that owns the 1 Hz timer and the connection.
//
//  ## It reports; it does not grade (user decision 2026-08-04)
//
//  There is deliberately **no** "healthy", "slow" or "degraded" anywhere here, no threshold, and
//  no colour keyed to a rate. Whether a measured rate indicates wear is the user's judgement, and
//  this tool does not have what that judgement needs.
//
//  ## And it does not invite the comparison either (user decision 2026-08-17, re-examined 09-02)
//
//  Until v12 this panel told the reader to compare these figures against the drive's advertised
//  sustained rate. The comparison was removed with the argument that the wall-clock write was
//  122 MB/s against an advertised ~460 — 27%, reading as a dying drive and meaning nothing about
//  wear, which is precisely the bias the FR document warns about: "a systematic bias toward
//  *this drive looks worn*, on a tool whose output is a judgement about somebody's hardware".
//
//  **That argument no longer holds and the decision does.** v14 puts the phase rates on this
//  panel — the very figure the comparison would have needed — and on the 4 TB T5 EVO the write
//  reads about 419 MB/s against that same ~460. Roughly 91%, not 27%. The strongest reason for
//  deleting the comparison is gone, and pretending otherwise would leave a justification standing
//  on a number that has changed under it.
//
//  What survives is the reason that never depended on the denominator: **it is a different
//  workload.** An advertised figure is a pure sequential read or a pure sequential write; a cycle
//  interleaves read, write and verify at 1–8 MiB. 91% of a rating earned on a different workload
//  is not 91% of anything, and a reader invited to treat it as a percentage would be reading a
//  wear judgement out of a number that cannot carry one. D9 stands on its own: this tool
//  measures, and does not grade.
//
//  ## The negotiated link speed is not here any more (2026-08-23, user decision)
//
//  It had a row here, on the grounds that it says whether the transport is the bottleneck. It
//  now sits in the Selected device pane, because the question the user actually asks with it —
//  *did this drive negotiate the link I expected, and is there any point starting?* — is asked
//  before a run, and a number that appears only once the run is under way cannot answer it.
//
//  The 2026-08-04 decision that put it beside measured throughput is **not** discarded. The
//  finished report still prints both figures in one block (`RunReportView.measurementRows`), and
//  that is the copy that gets kept, exported and re-read. What is gone is the live side-by-side.
//
//  ## Colour is never the only signal (NFR-USE-8)
//
//  Failed chunks are announced in words and with a symbol as well as in colour.
//

import SwiftUI
// `Timer.publish(...).autoconnect()` is Combine's. The project builds with the
// `MemberImportVisibility` upcoming feature enabled, so a member from another module needs that
// module imported explicitly — SwiftUI re-exporting it is not enough.
import Combine

// MARK: - The display

struct RunMetricsView: View {

    /// What the helper last reported.
    let snapshot: RunProgressSnapshot

    /// Shown while a run is in flight, so a stalled display is distinguishable from a finished
    /// one. The app knows this because it issued the run; the helper is not asked.
    let isRunning: Bool

    /// When the run these figures belong to started, or `nil` when not known.
    let startedAt: Date?

    /// BSD name of the drive these figures are about, or `nil` when none is known.
    ///
    /// Named because this panel sits under a device list and outlives the selection: without it,
    /// "Last run" read as the *currently selected* drive's numbers as soon as the selection moved.
    /// A measurement whose subject is unstated is not wrong — it just does not say what it is
    /// about.
    ///
    /// - Important: a **locator, not an identity**. `disk4` is assigned at enumeration and will be
    ///   a different drive after a replug. ``deviceSerial`` is what actually identifies it; this
    ///   is here because it is what ties the panel to `diskutil` and `/dev/rdiskN`.
    let deviceName: String?

    /// Serial number of the drive these figures are about, or `nil` when it reported none.
    ///
    /// The stable half of the answer to "which drive was this?". When absent the panel says so
    /// with a warning rather than falling silent, because an unqualified model name reads as an
    /// identification when it is only a description.
    let deviceSerial: String?

    var body: some View {
        GroupBox {
            // Replaced rather than overlaid. An overlay left a row of em-dashes visible *behind*
            // the placeholder, so the panel showed empty measurements and a note saying there
            // were none — two statements of the same thing, one of which looked like data.
            // See `showsMeasurements`. `isRunning` as well as `isAvailable` (user decision 2026-08-06). `runProgress`
            // keeps returning the finished run's figures until the next run replaces them, so
            // `isAvailable` alone left this panel showing a completed run indefinitely — the
            // "Last run" pane. Step 10's report window carries that result now, in full and with
            // an export; a second, thinner copy of it under the device list is redundant, and it
            // was the copy that needed a drive name and a timestamp bolted on to stop it being
            // read as the *selected* drive's numbers.
            //
            // What stays is the live half, which is neither redundant nor optional:
            // FR-METR-2/4/5/6 require throughput, latency, progress and ETA to be displayed
            // **during** a run, and no report exists while one is under way.
            //
            // **The scroll region is a bug fix (Step 11 increment 7).** This panel had none: at
            // the window's minimum height it did not compress, it **clipped** — observed on
            // hardware with a run in progress and the bottom three lines cut off (user,
            // 2026-08-19). Figures below the fold were not reachable by any means, which for
            // FR-METR-2/4/5/6 — throughput, latency, progress and ETA, all required to be visible
            // *during* a run — is the requirement silently unmet rather than merely cramped.
            //
            // Inside the `GroupBox` rather than around it, so the heading stays pinned while the
            // figures move. `DeviceListView` keeps its header outside its own `ScrollView` for the
            // same reason: a panel that scrolls its title away leaves numbers on screen with
            // nothing left saying what they are.
            //
            // Every `Spacer()` below is **horizontal**, inside an `HStack`, so none of them is
            // disturbed by a vertical scroll region. Checked rather than assumed — a `Spacer` that
            // had been expanding vertically would collapse to nothing here, and the panel would
            // have lost its spacing the moment it stopped clipping.
            // **The scroll region wraps the figures and NOT the placeholder**, and that asymmetry
            // is a bug fix rather than an economy (2026-08-20).
            //
            // Wrapping both, then asking the whole panel for `fixedSize` when idle, gave SwiftUI
            // two contradictory answers: a `ScrollView` has no meaningful minimum height — it will
            // compress to nothing — while `fixedSize` asks the same view for a definite ideal. The
            // window's reported `contentMinSize` came out **10-15 pt short of the truth**, so at
            // the window's own minimum the placeholder's second line was cut in half. Measured at
            // 720x455, and visible at the top of the window too: the content overflowed its frame
            // and was centred, clipping both ends.
            //
            // Two lines of copy never needed a scroll region. Without one the `GroupBox` sizes to
            // the placeholder, and that height propagates into the window's minimum the way every
            // other block's does.
            if Self.showsMeasurements(snapshot: snapshot, isRunning: isRunning) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        progress
                        Divider()
                        throughput
                        Divider()
                        latency
                        if snapshot.chunksFailed > 0 {
                            Divider()
                            failures
                        }
                        unidentifiedDriveWarning
                    }
                    .padding(.vertical, 4)
                }
            } else {
                idlePlaceholder
            }
        } label: {
            Label(heading, systemImage: "gauge.with.needle")
                .font(.callout.weight(.semibold))
        }
        // **Two different size policies, chosen by whether there is anything to show.**
        //
        // WITH FIGURES: a floor, an ideal and no ceiling. The floor keeps the heading on screen at
        // any window height; the ideal asks for the progress row as well, so FR-METR-5's bar is
        // visible without scrolling above the minimum; and the content scrolls when the window
        // cannot give it all 400-odd points.
        //
        // WITHOUT FIGURES: the same floor, no ideal and **no ceiling** — and no `ScrollView`, which
        // is what makes the ceiling unnecessary. With nothing greedy inside it the `GroupBox` sizes
        // to the placeholder and stops, at any window height.
        //
        // The idle case arrived in two steps, and the first was not enough. Rendering six drives
        // for the first time (2026-08-19) showed this panel and the device detail — both
        // `ScrollView`s, both greedy — splitting spare height evenly, so a 700 pt window spent
        // **265 pt on a box containing one sentence** while the drive list showed two rows of six.
        // Capping the idle panel at `metricsIdeal` fixed the worst of that and still left ~140 pt
        // of empty box, which is what the user saw on hardware and asked to remove
        // (2026-08-20): *finding and choosing a drive is the first thing a user does, so the
        // drive panes get the height.*
        //
        // **A false economy was tried in between, and it is worth recording because it measured
        // well.** Dropping the idle floor as well took 30 pt off every state's reported minimum —
        // 485 to 455 — and `window-fit-check.sh` passed on the new number. It was wrong: with no
        // floor this became the only pane without one, so at the window's own minimum it absorbed
        // the entire shortfall and the placeholder's second line was cut in half. A smaller
        // reported minimum is not automatically a better one; it can mean the window is now
        // permitted to be too small. **The gate cannot see this** — it checks that the minimum is
        // small enough to fit a screen, never that it is large enough to fit the content — and
        // chunk 9.2 of the human checklist is what caught it, at the keyboard, in about a minute.
        //
        // The idle panel therefore cannot scroll and does not need to: it holds `metricsFloor`,
        // which covers the placeholder even at the narrowest width, where it wraps to three lines.
        .frame(minHeight: WindowMetrics.metricsFloor,
               idealHeight: showsFigures ? WindowMetrics.metricsIdeal : nil,
               maxHeight: showsFigures ? .infinity : nil)
    }

    /// Whether there are figures to show, hoisted out of `body` because the panel's **size policy**
    /// now turns on it as well as its content (user decision 2026-08-20).
    private var showsFigures: Bool {
        Self.showsMeasurements(snapshot: snapshot, isRunning: isRunning)
    }

    /// Whether the panel shows figures at all, as a decision rather than a condition buried in
    /// the body.
    ///
    /// ## Why this is extracted
    ///
    /// It is a two-input truth table, and the interesting row is the one Step 10 changed: an
    /// **available snapshot with no run under way**. `runProgress` keeps returning a finished
    /// run's figures until the next run replaces them, so `isAvailable` alone left this panel
    /// displaying a completed run indefinitely — the "Last run" pane, now superseded by the report
    /// window and its export (user decision 2026-08-06).
    ///
    /// Pulled out where it can be tested because the alternative is a `if` inside a SwiftUI
    /// `body`, and this project's record with view conditions verified by reading them is poor:
    /// three modifiers in Step 9 compiled, rendered and did nothing. A render proves it once; a
    /// test keeps it proved.
    ///
    /// Both inputs are load-bearing. Dropping `isRunning` restores the stale pane; dropping
    /// `isAvailable` would show a row of em-dashes at the start of a run, which Step 9 already
    /// fixed once.
    static func showsMeasurements(snapshot: RunProgressSnapshot, isRunning: Bool) -> Bool {
        snapshot.isAvailable && isRunning
    }

    /// `Run in progress — S/N 12345686DAA9 (disk8)`, falling back to the bare phrase when no run
    /// is under way.
    ///
    /// The serial leads and the BSD name is parenthesised, in that order deliberately: the serial
    /// is the identity, and the BSD name is only where to find the drive today.
    ///
    /// Attributed only when there are figures to attribute — heading an empty panel with a drive
    /// name would imply that drive had been run.
    private var heading: String {
        // No "Last run" phrase any more: this panel is only ever the live one, and a finished run
        // lives in the report window.
        let phrase = "Run in progress"
        guard snapshot.isAvailable, isRunning else { return "Live run metrics" }

        switch (deviceSerial, deviceName) {
        case let (serial?, name?): return "\(phrase) — S/N \(serial) (\(name))"
        case let (serial?, nil):   return "\(phrase) — S/N \(serial)"
        case let (nil, name?):     return "\(phrase) — \(name)"
        case (nil, nil):           return phrase
        }
    }

    /// Shown when the tested drive reported no serial (user decision 2026-08-05).
    ///
    /// Leads with a warning symbol, because this is a limit on what the panel above it can claim
    /// rather than a footnote: without a serial these figures cannot be tied to *this physical
    /// drive* rather than to any identical one. Words and a symbol, never colour alone
    /// (NFR-USE-8).
    @ViewBuilder
    private var unidentifiedDriveWarning: some View {
        if snapshot.isAvailable, deviceSerial == nil {
            Label("""
                  This drive reported no serial number, so these results cannot be told apart \
                  from those of an identical model. The name above says where the drive was \
                  found, not which drive it is.
                  """, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Progress (FR-METR-5/6, NFR-USE-2)

    private var progress: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: snapshot.fractionComplete)
                .progressViewStyle(.linear)

            HStack {
                Text(MetricsFormatting.percent(snapshot.fractionComplete))
                    .font(.callout.monospacedDigit().weight(.medium))
                Text("complete")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(MetricsFormatting.remaining(snapshot.estimatedRemaining))
                    .font(.callout.monospacedDigit())
                Text("remaining")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            row("Current block", MetricsFormatting.blockOffset(snapshot.currentBlock))
            row(isRunning ? "Started" : "Run at", MetricsFormatting.runTimestamp(startedAt))
        }
    }

    // MARK: Throughput (FR-METR-1/2)

    private var throughput: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("Read", MetricsFormatting.throughput(snapshot.deviceReadBytesPerSecond))
            row("Write", MetricsFormatting.throughput(snapshot.writeBytesPerSecond))

            // **`R-W-R-C` — the row `Covering` should have been** (Step 11 increment 11). The
            // user's own name for it, kept as an abbreviation here to sit beside `Read` and
            // `Write`; the report and the export spell it `R-W-R-C speed`.
            //
            // Deliberately **not** "Progress speed": the bar and the ETA above are driven by
            // *attempted* bytes, so that name would promise `remaining ÷ rate` and break it
            // precisely when a drive is failing — the same class of error as the mislabel this
            // row exists to correct.
            row("R-W-R-C", MetricsFormatting.throughput(snapshot.completedBytesPerSecond))

            // **`Covering` was deleted here** (Step 11 increment 10), and the reason is the name
            // rather than the arithmetic. It was documented as *"how fast the run is covering the
            // drive"* — a definition using its own term, which is how it survived a review in which
            // every figure was checked against the source and the identity `Covering ≡ Write` was
            // derived correctly. Asked for a definition that did not contain the word, the gap was
            // one sentence away: `rangeBytesCovered` counts **attempted** work and says so in its
            // own comment, while the label promises successful work. The two agree on a healthy
            // drive and part on a failing one — the single occasion anyone reads the number closely.
            //
            // The quantity is right for its two consumers and is untouched: the ETA denominator and
            // the progress fraction both *need* attempted, or a drive with a bad region shows a bar
            // that never reaches 100% and an ETA that never converges. It is still on the wire and
            // still on no screen, which is a decision rather than an oversight.
            //
            // The figure the user actually wanted is the `R-W-R-C` row above, added in increment 11
            // at the cost of protocol v13.

            // **The definition is on screen, next to the number, and from v14 it is doing more
            // work than it used to.** Between v12 and v13 it explained figures that agreed with
            // another window; it now explains figures that deliberately disagree with one, by
            // 1.5x and 3.4x. A rate whose denominator is unstated is not a measurement anyone
            // else can reproduce — that was true when the first reader checked against Activity
            // Monitor and reported a bug (2026-08-17), and it is more true now that the
            // disagreement is the intended result rather than the defect.
            //
            // The sentence about R-W-R-C sitting below its neighbours is not padding. It reads a
            // third of them on a drive with nothing wrong, and a figure that looks like a fault
            // on healthy hardware is exactly what generated that report.
            Text("""
                 Read and Write are the drive's own speeds: each counts the bytes it moved \
                 against the time it spent moving them, so they describe this hardware rather \
                 than this run. They are therefore not comparable to Activity Monitor, which \
                 divides by the whole elapsed time and will show lower figures for the same \
                 drive. Read pools the first read and the read-back. \
                 R-W-R-C counts only bytes that were read, written back, read again and matched, \
                 against all the I/O time that took — a whole cycle where the other two are \
                 single steps, so on a drive with nothing wrong it sits well below both. What \
                 matters is the gap: it widens when a chunk the drive accepted fails to read \
                 back, or reads back different.
                 """)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

        }
    }

    // MARK: Read latency (FR-METR-3/4)

    private var latency: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Read latency")
                    .font(.callout.weight(.medium))
                Spacer()
                if snapshot.hasLatencySamples {
                    Text("over \(snapshot.readLatencySampleCount) reads")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            row("Minimum", MetricsFormatting.latency(snapshot.readLatencyMinimum))
            row("Maximum", MetricsFormatting.latency(snapshot.readLatencyMaximum))
            // "≤" rather than "=": the percentile is known to within one histogram bucket.
            row("p99", MetricsFormatting.percentileUpperBound(snapshot.readLatencyP99UpperBound))
        }
    }

    // MARK: Failures

    private var failures: some View {
        // NFR-USE-8: the symbol and the words carry it, not the colour.
        Label {
            Text(snapshot.chunksFailed == 1
                 ? "1 chunk failed so far"
                 : "\(snapshot.chunksFailed) chunks failed so far")
                .font(.callout.weight(.medium))
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .foregroundStyle(.orange)
    }

    // MARK: Pieces

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout.monospacedDigit())
                .textSelection(.enabled)
        }
    }

    /// Everything this panel says when no run is under way.
    ///
    /// It has to say **where a finished run went**, not merely that nothing is happening. Until
    /// Step 10 this panel retained the last run's figures, so a user who had just run something
    /// found them here. They are now in the report window — and a placeholder that only said
    /// "nothing is under way" would read as the result having been lost.
    private var idlePlaceholder: some View {
        HStack(spacing: 6) {
            // Decorative — the paragraph beside it is the whole content.
            Image(systemName: "info.circle")
                .accessibilityHidden(true)
            // "the run report" and not "the Run Report window": increment 8 made it a sheet on
            // this window, and a placeholder naming a window that no longer exists sends the reader
            // looking for it.
            Text("Measurements appear here while a run is under way. When one finishes, its "
               + "results — including the bad-block list — open in the run report, where they "
               + "can be exported.")
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
    }
}

// MARK: - The polling shell

/// Owns the 1 Hz timer and asks the helper (NFR-PERF-5: at least one refresh per second).
///
/// ## Why the poll goes out on a second connection
///
/// `runRetentionCycle` blocks its connection for the whole run, and measured 2026-08-04 a second
/// message on a connection with a call in flight is **not delivered until that call returns**.
/// `HelperConnection.runProgress` therefore uses a separate, non-owning connection; see the note
/// on `HelperConnection.progressConnection`.
///
/// ## Why 1 Hz and not faster
///
/// NFR-PERF-5 asks for at least one refresh per second, and a display of numbers that settle over
/// a run gains nothing from ten. Each poll costs the helper a lock and a walk over a fixed
/// 2,240-bucket histogram; there is no reason to spend that forty times a second to render text
/// nobody can read that fast.
struct LiveRunMetricsPanel: View {

    let helper: HelperConnection

    /// Set by whatever started the run. The app knows its own run's lifecycle without asking the
    /// helper — which is why the protocol reply carries no "is a run active" flag.
    let isRunning: Bool

    /// The drive the figures belong to. See `RunMetricsView.deviceName`.
    let deviceName: String?

    /// Its serial. See `RunMetricsView.deviceSerial`.
    let deviceSerial: String?

    /// When the run started. See `RunMetricsView.startedAt`.
    let startedAt: Date?

    @State private var snapshot: RunProgressSnapshot = .unavailable

    /// One second exactly (NFR-PERF-5).
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        RunMetricsView(snapshot: snapshot,
                       isRunning: isRunning,
                       startedAt: startedAt,
                       deviceName: deviceName,
                       deviceSerial: deviceSerial)
            .onReceive(tick) { _ in refresh() }
            .onAppear { refresh() }
    }

    private func refresh() {
        helper.runProgress { result in
            // A transport failure leaves the last snapshot on screen rather than blanking it.
            // Blanking would read as "the run reset"; a display that has stopped advancing is
            // the honest symptom of a helper that has stopped answering.
            if case .success(let value) = result { snapshot = value }
        }
    }
}
