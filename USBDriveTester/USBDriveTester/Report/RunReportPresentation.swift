//
//  RunReportPresentation.swift
//  USBDriveTester (app target — unprivileged)
//
//  What the run report's header SHOWS for an outcome: a symbol, and a tint (NFR-USE-8).
//
//  ## Why this is a type rather than two private funcs in the view
//
//  It was two private funcs in `RunReportView` until 2026-08-11, which meant the one rule
//  NFR-USE-8 states as an absolute — **never convey pass/fail by colour alone** — was held up by a
//  comment. Nothing in the suite could reach `iconName` or `iconTint`, so a future edit that made
//  two outcomes share a symbol, leaving the tint as the only thing telling them apart, would have
//  compiled, rendered plausibly, and passed 794 tests.
//
//  That is this project's oldest lesson in its usual costume: *a comment acknowledging a hole is
//  not a check*, and *a check must be shown capable of failing*. `RunReportPresentationTests`
//  mutation-tests exactly that collision.
//
//  ## Why the tint is a MEANING and not a `Color`
//
//  A `Color` would drag SwiftUI into the test target for no benefit — and worse, it would make the
//  interesting property untestable, because two `Color`s being equal says nothing about whether a
//  reader can tell two states apart. What matters is not "which orange" but "do these two states
//  differ **other than** by their tint". Naming the tint semantically lets the test ask that
//  question directly; `RunReportView` maps it to a `Color` at the point of use, which is the only
//  line in this area SwiftUI needs to see.
//
//  ## What this deliberately does not decide
//
//  The words. `RunReport.headline` already owns those, carrying FR-TEST-9's qualification clause,
//  and it is what actually discharges NFR-USE-8 — measured 2026-08-11, the headline renders at
//  13.97:1 against the window background in light appearance and 12.63:1 in dark, while the tints
//  measure 2.22:1 (green) and 2.31:1 (orange) in light. **The symbol and the words carry the
//  meaning; the tint is decoration on top of them**, which is the right way round and is why the
//  low-contrast tint is not a defect. See the Step 14 increment 6 accessibility audit.
//

import Foundation

/// What a status tint MEANS, so the rule about it can be stated without naming a colour.
nonisolated enum RunStatusTint: Equatable, CaseIterable {

    /// Nothing failed, the range was covered, and no qualification applies.
    case affirmative

    /// Something failed, the run was cut short, or the result is unverified. One case rather than
    /// three: the report's job here is to stop a reader skimming past a result that is not a clean
    /// pass, and grading the shades of not-clean would be a judgement the tool does not have.
    case cautionary
}

/// The report header's symbol and tint for a given result (NFR-USE-8).
nonisolated struct RunReportPresentation: Equatable {

    /// An SF Symbol name. **Distinct per meaning**, so the greyscale rendering of two different
    /// results never collides — verified in greyscale on 2026-08-11, both appearances.
    let symbolName: String

    let tint: RunStatusTint

    /// The rule: an unverified result is shown as a question regardless of what it concluded,
    /// because FR-TEST-9's qualification is about whether the conclusion can be relied on at all.
    ///
    /// Below that, the four outcomes get four distinguishable symbols. `checkmark.circle` and
    /// `stop.circle` are both circles and that is deliberate — they are the two "the run did what
    /// it was told" cases — but they are **not** distinguished by tint alone: their headlines are
    /// entirely different sentences, which is what the test pins.
    static func forResult(outcome: RunReportOutcome,
                          verifyResultIsQualified: Bool) -> RunReportPresentation {
        guard !verifyResultIsQualified else {
            return RunReportPresentation(symbolName: "questionmark.circle.fill", tint: .cautionary)
        }
        switch outcome {
        case .completedClean:
            return RunReportPresentation(symbolName: "checkmark.circle.fill", tint: .affirmative)
        case .completedWithFailures:
            return RunReportPresentation(symbolName: "exclamationmark.triangle.fill",
                                         tint: .cautionary)
        case .stoppedOnError:
            return RunReportPresentation(symbolName: "stop.circle.fill", tint: .cautionary)
        case .incomplete:
            return RunReportPresentation(symbolName: "exclamationmark.circle.fill",
                                         tint: .cautionary)
        }
    }
}
