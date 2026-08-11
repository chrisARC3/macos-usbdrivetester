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
//  no colour keyed to a rate. Whether a measured rate indicates wear is the user's judgement,
//  made against the manufacturer's advertised sustained figure — which this tool does not know
//  and must not invent.
//
//  What the display owes that judgement is the **other** number it needs: the negotiated link
//  speed, shown beside the measured rate, because "significantly below the advertised rate after
//  accounting for negotiated speed limits" cannot be evaluated with only one of the two.
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

    /// Raw IORegistry `Device Speed` code from `deviceProfile`, or `-1` when unknown.
    let linkSpeedCode: Int

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
            if Self.showsMeasurements(snapshot: snapshot, isRunning: isRunning) {
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
            } else {
                idlePlaceholder
            }
        } label: {
            Label(heading, systemImage: "gauge.with.needle")
                .font(.callout.weight(.semibold))
        }
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
            row("Read", MetricsFormatting.throughput(snapshot.readBytesPerSecond))
            row("Write", MetricsFormatting.throughput(snapshot.writeBytesPerSecond))
            row("USB link negotiated at", MetricsFormatting.linkSpeed(code: linkSpeedCode))

            // The framing the user asked for: this tool measures, the user judges. Stated in
            // the UI rather than only in the docs, because a bare MB/s figure on a drive-testing
            // screen invites being read as a verdict.
            Text("""
                 Compare these against the drive's advertised sustained rate, allowing for the \
                 negotiated link above. A rate well below what the drive claims — once the link \
                 is accounted for — can indicate wear, but this tool does not judge that for you.
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
            Text("Measurements appear here while a run is under way. When one finishes, its "
               + "results — including the bad-block list — open in the Run Report window, "
               + "where they can be exported.")
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

    /// From `deviceProfile`, so the measured rate can be read against the negotiated link.
    let linkSpeedCode: Int

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
                       linkSpeedCode: linkSpeedCode,
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
