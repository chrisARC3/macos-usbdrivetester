//
//  HonestFraming.swift
//  USBDriveTester (app target — unprivileged)
//
//  Step 14, increment 2. **The** wording of what this tool proves and does not prove
//  (FR-WARN-1/2/3/4, NFR-USE-6), and the three mandatory pre-run warnings, in one place.
//
//  ## Why one place, and the evidence that it had to be
//
//  Three surfaces say this: the pre-run dialog (Step 14), the result screen and the exported
//  Markdown report (both Step 10). Before this file there were **two** copies, written in the same
//  increment by the same hand — and on 2026-08-10 they were found to have already diverged:
//
//  | | |
//  |---|---|
//  | report | "…It does not prove the medium retained it**: the drive's own cache sits below every check a host can make.**" |
//  | result screen | "…It does not prove the medium retained it." |
//
//  The screen was missing the clause that explains *why*, and the dual-role opener was reworded
//  too. Nothing failed, because no test compared them — `RunReportTests` asserts the Markdown
//  contains "degrading but still correctable" and never looks at the view. Adding a third copy for
//  the pre-run dialog would have made three surfaces that agree only by the author remembering to
//  keep them in step.
//
//  This is the product's central honesty claim. It is the thing standing between "the test passed"
//  and "the drive is fine", and NFR-USE-6 makes it a **M** requirement. A version of it that is
//  quietly weaker on one surface than another is the same class of defect as a percentile printed
//  without its bound: not false, just no longer saying what it was written to say.
//
//  ## Why the three mandatory warnings live here too
//
//  Because **FR-WARN-3 *is* one of these claims.** "A clean pass means no currently-unreadable
//  blocks were found, not that the drive is healthy" is simultaneously a mandatory pre-run warning
//  and the framing echoed into the report. Putting the warnings in their own file would mean
//  writing that sentence twice on day one, which is the exact failure this file exists to remove.
//
//  ## How emphasis survives two renderers
//
//  Each claim is written **once, in Markdown**, and `plain` is derived from it by removing the
//  emphasis markers. So the exported report keeps its bold, SwiftUI surfaces get readable text, and
//  there is no second literal to fall out of step. Deriving in that direction is deliberate: the
//  richer form is the source, so a renderer can only ever lose decoration, never meaning.
//

import Foundation

/// A single claim, authored in Markdown.
nonisolated struct HonestFramingClaim: Equatable, Identifiable {

    /// The canonical wording, with `**emphasis**`. **This is the only place the sentence exists.**
    let markdown: String

    /// The same sentence for a surface that cannot render Markdown.
    ///
    /// Derived rather than stored — a stored second copy is the defect this file was written for.
    var plain: String { markdown.replacingOccurrences(of: "**", with: "") }

    var id: String { markdown }

    init(_ markdown: String) { self.markdown = markdown }
}

/// What this test does and does not prove. One definition, three surfaces.
nonisolated enum HonestFraming {

    /// FR-WARN-4's dual-role framing — the tool is a retention refresher **and** a fault detector,
    /// and saying only one of those invites the other to be assumed.
    static let summary = HonestFramingClaim(
        "This tool does two things: it **refreshes charge retention** by reading each block and "
      + "writing the same bytes back, and it **detects hard faults** by reading back what it wrote "
      + "and comparing.")

    /// FR-WARN-3, in the wording the report's headline is also built to match: what was observed,
    /// and when. "The drive is healthy" would be a claim about the future.
    static let cleanResultMeans = HonestFramingClaim(
        "A clean result means **no currently-unreadable blocks were found** in the range tested, at "
      + "the time it was tested.")

    /// The limit that makes FR-WARN-3 necessary rather than pedantic: the failure mode most likely
    /// to matter is the one this tool structurally cannot see.
    static let degradingBlocksAreInvisible = HonestFramingClaim(
        "Blocks that are **degrading but still correctable** by the drive's own error correction "
      + "cannot be detected at the USB block level. This test cannot see them, and a drive close to "
      + "failing can pass it.")

    /// The second limit, and the clause the result screen had lost: a verify proves the data got
    /// through the I/O path, not that the medium kept it.
    static let verifyProvesRoundTripNotRetention = HonestFramingClaim(
        "A verify that matches proves the data **round-tripped through the drive's I/O path**. It "
      + "does not prove the medium retained it: the drive's own cache sits below every check a host "
      + "can make.")

    /// Shown on every surface, in this order.
    static let claims: [HonestFramingClaim] = [
        cleanResultMeans,
        degradingBlocksAreInvisible,
        verifyProvesRoundTripNotRetention,
    ]

    /// Added by the **report** surfaces only, and only for a run that stopped on an error.
    ///
    /// Not in ``claims`` because it is about one particular run rather than about the tool, and it
    /// says "the failure above" — there is no "above" in a dialog shown before the run starts.
    static let rangeBeyondTheFailureWasNotTested = HonestFramingClaim(
        "**The range beyond the failure above was not tested.** Untested is not the same as passed.")

    /// The same point for a run **the user ended** (FR-RPT-4, increment 8). A separate sentence
    /// rather than a reworded one, because the reason the range went untested is different and the
    /// other sentence points at a failure that does not exist here.
    static let rangeBeyondTheStopWasNotTested = HonestFramingClaim(
        "**The rest of the drive was not tested** — the run was stopped before it got there. "
      + "Untested is not the same as passed.")

    /// The same point again for a run whose **drive left** (FR-DEV-8, Step 12 chunk 5).
    ///
    /// A third sentence rather than a reworded second, on the rule the second was written under:
    /// *the reason the range went untested is different.* This one also has to avoid a trap the
    /// other two do not — it must not read as a complaint about the drive. "The drive was no
    /// longer there" is what happened; whether that is the drive's fault is a question this tool
    /// cannot answer and does not raise here.
    static let rangeBeyondTheDisconnectionWasNotTested = HonestFramingClaim(
        "**The rest of the drive was not tested** — it was no longer attached when the run ended. "
      + "Untested is not the same as passed.")

    // MARK: - What a vanished drive was left holding (Step 12, FR-DEV-8)

    /// The one sentence a person actually needs after a drive leaves mid-run: **was a chunk
    /// part-way through being written back?**
    ///
    /// ## Why the wording differs per case rather than being one hedged sentence
    ///
    /// Because the four answers are genuinely different claims, and a single sentence covering all
    /// of them would have to be the most conservative — warning about a partly written chunk on a
    /// run that was paused with provably nothing outstanding. A false alarm about somebody's drive,
    /// in a file that outlives the session, is not the safe side of this trade: it teaches a reader
    /// to discount the document, which costs them the warning that *is* real when it comes.
    ///
    /// ## Why this is here and not in the two renderers
    ///
    /// The file's governing rule. Four cases × two surfaces is eight literals to keep in step, and
    /// the 7.2 defect this file was written for was two.
    ///
    /// - Returns: one claim, always. Unlike ``claim(addedBy:)`` there is no "adds nothing" answer —
    ///   a report that names a vanished drive and then says nothing about what it was doing at the
    ///   time has left out the only part a reader cannot reconstruct.
    static func claim(about account: DeviceLossAccount) -> HonestFramingClaim {
        // **Digit-grouped, and by the same formatter the row beside it uses.** A sentence saying
        // `block 4194304` above a table row saying `block 4,194,304` is one document giving two
        // spellings of one number, which is a small version of the defect this whole file exists
        // for — and the reader has to compare them by eye to notice they are the same reading.
        func blockName(_ block: UInt64) -> String { MetricsFormatting.blockOffset(block) }

        switch account {
        case .theHelperSaidWhere(let block, .reading):
            return HonestFramingClaim(
                "The drive left while this tool was **reading** block \(blockName(block)). Nothing had "
              + "been written to that chunk, so it holds what it held before the run "
              + "reached it.")

        case .theHelperSaidWhere(let block, .writingBack):
            // The one case with a real hazard in it, and it is stated without being dressed up.
            return HonestFramingClaim(
                "The drive left while this tool was **writing block \(blockName(block)) back**. That "
              + "is the one point in the cycle where the original had been read and not yet "
              + "fully written back, so **that chunk may hold partly written data**. No other "
              + "chunk is affected: every earlier one was written back and verified, and no "
              + "later one was started.")

        case .theHelperSaidWhere(let block, .verifying):
            return HonestFramingClaim(
                "The drive left while this tool was **re-reading block \(blockName(block)) to verify "
              + "it**. The write-back had already completed, so the chunk was whole when the "
              + "drive went — it is unverified, and **unverified is not the same as bad**.")

        case .theHelperSaidWhere(let block, .unrecognised):
            // A helper newer than this app. Print the block, refuse to name the phase, and take
            // the conservative reading — `DeviceLossAccount.aWriteBackMayBeUnfinished` agrees.
            return HonestFramingClaim(
                "The drive left at block \(blockName(block)), during a step this version of the app "
              + "does not recognise — usually a sign that the privileged helper is newer than "
              + "the app. **It cannot be ruled out that a write-back was interrupted**, so that "
              + "chunk may hold partly written data.")

        case .nothingWasInFlight:
            return HonestFramingClaim(
                "The run was **paused** when the drive left, so no chunk was part-way through "
              + "anything and nothing was left half-written. Every chunk the run had reached was "
              + "written back and verified before it stopped.")

        case .theHelperNeverAnswered:
            // **Two facts, and the second one is the claim rather than the data.**
            //
            // Every other case here answers one question: what may have happened to the bytes.
            // This one also answers a second, because it is the only account that implies it. The
            // deadline expiring means the helper went quiet *inside the owning connection's
            // blocking call*, and a second message on a connection with a call in flight is not
            // delivered until that call returns (measured 2026-08-04). So the release that follows
            // could not be acknowledged either, and `RunController.releaseCannotBeConfirmed` is
            // set for exactly this ending and no other.
            //
            // **Derived rather than carried, and there is a test standing behind the derivation.**
            // `RunReport` gains no field for it: `releaseCannotBeConfirmed` is set from
            // `ending == .theHelperNeverAnswered`, and this account arises from that same ending
            // whenever route (a) supplied nothing — which the deadline expiring already
            // guarantees, since a reply that had arrived would have stood the wind-down down.
            // That chain crosses three types, so it is pinned rather than assumed:
            // `anUnansweredCallsReportSaysTheHelperNeverAnswered` drives the deadline and asserts
            // this account comes out (Step 12 chunk 5).
            //
            // It is stated in the past tense on purpose. In an exported file read weeks later it
            // is history — *the release could not be confirmed* — which stays true, where advice
            // about what to do next would not.
            return HonestFramingClaim(
                "A chunk was in progress when the drive left, and the privileged helper never "
              + "reported which step it had reached. **It cannot be ruled out that a write-back "
              + "was interrupted**, so one chunk may hold partly written data — this report "
              + "cannot say which one. The same silence means exclusive access could not be "
              + "confirmed as given back; if it was still held, the next test to start would have "
              + "been refused with the helper's own reason.")

        case .noRouteSaidAnything:
            // The contradiction case. It says less than the others because it knows less, and
            // saying so is the point — see `DeviceLossAccount.noRouteSaidAnything`.
            return HonestFramingClaim(
                "The run ended because the drive was gone, and **neither the privileged helper "
              + "nor the system's removal notification said when**. This report cannot say what "
              + "the run was doing at the time, so **it cannot be ruled out that a write-back was "
              + "interrupted**.")
        }
    }

    // MARK: - What the run's range does and does not cover

    /// The requested range was smaller than the drive — a bounded diagnostic run.
    ///
    /// **Reworded in increment 8, and the old wording was a false claim rather than a clumsy one.**
    /// It read *"This run covered the range above, not the whole drive"*, which asserts that the
    /// run covered the range — true for every run that could reach this sentence when it was
    /// written, and false the moment FR-CTRL-4's Stop control existed. It now states only the
    /// relationship between the range and the drive, which is the fact it was there to give, and
    /// composes with ``rangeWasNotReachedToItsEnd`` instead of contradicting it.
    static let rangeWasSmallerThanTheDrive = HonestFramingClaim(
        "The range above is **not the whole drive**. Blocks outside it were not tested.")

    /// The run ended before reaching the end of the range it asked for (FR-RPT-4).
    ///
    /// **It does not say how far it got, on purpose.** A byte figure here would have to be derived
    /// from the chunk count, and CONSTRAINTS' rule is that progress is byte-denominated and that
    /// the report must not re-derive what the session already reports. The report prints
    /// ``RunReport/chunksProcessed`` a line above; inventing a precision the reply does not carry
    /// would be worse than saying plainly that the end was not reached.
    static let rangeWasNotReachedToItsEnd = HonestFramingClaim(
        "The run ended before reaching the end of that range. Blocks beyond the point it stopped "
      + "were **not tested**.")

    /// The caveats a run's coverage carries, in the order they are shown.
    ///
    /// ## Why this is here rather than in the two renderers
    ///
    /// Because it was in both, twice over. Until increment 8 `RunReportView` and
    /// `RunReportMarkdown` each held **their own literal** of the bounded-range sentence *and*
    /// **their own copy of the condition** — one written `rangeByteCount < capacityBytes`, the
    /// other `blockCount * UInt64(logicalBlockSize) < capacityBytes`, which is the same arithmetic
    /// spelled twice. Two surfaces, two sentences, two conditions, nothing comparing any of them:
    /// the 7.2 defect's exact shape, in a paragraph this file had never been asked to cover.
    ///
    /// - Parameters:
    ///   - rangeIsWholeDrive: whether the range the run *asked for* was the whole device.
    ///   - coveredTheRange: whether the run reached the end of what it asked for —
    ///     ``RunReportOutcome/didCoverTheRequestedRange``.
    static func rangeCaveats(rangeIsWholeDrive: Bool,
                             coveredTheRange: Bool) -> [HonestFramingClaim] {
        var caveats: [HonestFramingClaim] = []
        if !rangeIsWholeDrive { caveats.append(rangeWasSmallerThanTheDrive) }
        if !coveredTheRange { caveats.append(rangeWasNotReachedToItsEnd) }
        return caveats
    }

    /// The one claim, if any, that a **particular outcome** adds to ``claims`` on the report
    /// surfaces (FR-RPT-4).
    ///
    /// ## Why this is a function here and not an `if` in each renderer
    ///
    /// It was two `if report.outcome == .stoppedOnError` statements — one in `RunReportView`, one
    /// in `RunReportMarkdown` — which is two places deciding one thing. **That is the shape of the
    /// 7.2 defect this whole file exists to end**: on 2026-08-18 the window and the exported file
    /// were found disagreeing about the throughput denominator, because the guidance had been
    /// changed on one surface and not the other, and nothing compared them. Adding a second outcome
    /// with a second sentence would have doubled the number of places to keep in step at exactly
    /// the moment the count went from one to two.
    ///
    /// A `switch` with no `default`, so Step 12's device-loss outcome is a compile error here —
    /// which is the question worth being forced to answer: *does this ending need its own sentence
    /// about what went untested?*
    ///
    /// - Returns: `nil` for the outcomes that add nothing. `completedClean` and
    ///   `completedWithFailures` covered the whole range, so there is no untested remainder to
    ///   speak of; `incomplete` already says in its own explanation that the part not reached was
    ///   not tested, and a report that cannot say *why* the run ended must not imply it knows.
    ///
    ///   ``RunReportOutcome/deviceLost`` gets a sentence of its own, and this is the narrow one:
    ///   what went **untested**. What the drive was left holding is a different question with a
    ///   different answer per detection route, and it is ``claim(about:)`` that answers it.
    static func claim(addedBy outcome: RunReportOutcome) -> HonestFramingClaim? {
        switch outcome {
        case .stoppedOnError:
            return rangeBeyondTheFailureWasNotTested
        case .stoppedByUser:
            return rangeBeyondTheStopWasNotTested
        case .deviceLost:
            return rangeBeyondTheDisconnectionWasNotTested
        case .completedClean, .completedWithFailures, .incomplete:
            return nil
        }
    }
}

// MARK: - The three mandatory warnings (FR-WARN-1/2/3, NFR-USE-4)

/// One of the mandatory pre-run warnings.
nonisolated struct PreRunWarning: Equatable, Identifiable {

    /// The requirement this discharges, e.g. `"FR-WARN-1"`. Carried so a test can assert the set is
    /// complete by **requirement** rather than by counting three of something.
    let requirement: String

    let title: String

    /// The body, as one or more claims. Several of these are shared with ``HonestFraming`` rather
    /// than restated.
    let points: [HonestFramingClaim]

    var id: String { requirement }
}

/// The warnings shown before a run, and the order they are shown in.
nonisolated enum PreRunWarningText {

    /// FR-WARN-1. The distinction it turns on is *by design* versus *guaranteed*, and stating only
    /// the first is how a user concludes the second.
    static let backUpFirst = PreRunWarning(
        requirement: "FR-WARN-1",
        title: "Back up this drive first",
        points: [
            HonestFramingClaim(
                "This test is non-destructive **by design**: every block is written back with "
              + "exactly the bytes just read from it, and nothing else is ever written."),
            HonestFramingClaim(
                "Design is not a guarantee. A power loss, a cable or enclosure fault, or a drive "
              + "that fails mid-write can still cost data. **Back up anything on this drive that "
              + "you cannot afford to lose before starting.**"),
        ])

    /// FR-WARN-2. Deliberately says what the cost *is* rather than only that there is one — "run
    /// this infrequently" without a reason is advice a user has no way to weigh.
    static let infrequentOnFlash = PreRunWarning(
        requirement: "FR-WARN-2",
        title: "Run this only occasionally on flash drives",
        points: [
            HonestFramingClaim(
                "A full pass rewrites **every block on the device**, so it spends flash write "
              + "endurance across the whole drive rather than only the parts in use."),
            HonestFramingClaim(
                "On SSDs and USB flash media this is a tool to reach for **occasionally**, when "
              + "charge retention is the concern — not something to run on a schedule."),
        ])

    /// FR-WARN-3, built from the shared claims rather than restating them. If this ever stops
    /// drawing from ``HonestFraming``, the pre-run warning and the report can disagree about the
    /// one sentence NFR-USE-6 exists to protect.
    static let cleanPassIsNotHealth = PreRunWarning(
        requirement: "FR-WARN-3",
        title: "A clean pass is not a clean bill of health",
        points: [
            HonestFraming.cleanResultMeans,
            HonestFraming.degradingBlocksAreInvisible,
        ])

    /// All three, in the order shown. FR-WARN-1 is first because it is the only one that asks the
    /// user to *do* something before continuing.
    static let mandatory: [PreRunWarning] = [backUpFirst, infrequentOnFlash, cleanPassIsNotHealth]

    // MARK: The dialogs' own wording

    /// Heading of the full pre-run dialog.
    ///
    /// The suppressed dialog has **no separate heading**: ``confirmationQuestion(for:)`` is its
    /// heading. It briefly had one reading "Start testing this drive?" above a question reading
    /// "Start testing the 22.00 TB Seagate Expansion HDD, serial …?", which said the same words
    /// twice — invisible in the source, because the two strings live in different files, and
    /// obvious the moment `render-ui.sh warnings-confirm` put them next to each other.
    static let fullDialogTitle = "Before you start"

    /// The label on the suppression checkbox (decision 5, user wording).
    static let suppressionCheckbox = "Don't show this warning again"

    /// What the checkbox actually promises, said next to it.
    ///
    /// It does **not** promise no dialog — the deliberate act is not suppressible (NFR-USE-4 as
    /// qualified 2026-08-09). A checkbox that implied otherwise would be the product overstating
    /// what it is about to do, on the one screen whose job is not overstating things.
    static let suppressionCaveat =
        "You will still be asked to confirm the drive before each run. This can be turned back on "
      + "in the Privileged Helper & Diagnostics window."

    /// Names the drive a confirmation is about (decision 6).
    ///
    /// **Model, capacity and USB serial**, because the acknowledgement has to survive a
    /// renumbering: on this machine the scratch drive moved from `disk8` to `disk10` inside three
    /// days, and FR-DEV-3's default lands on whichever drive sorts first. A question whose subject
    /// is "disk4" is a question about a name, not about a drive.
    static func confirmationQuestion(for device: ReportedDevice) -> String {
        let capacity = CapacityFormatting.humanReadable(device.capacityBytes)
        guard let serial = device.usbSerialNumber else {
            return "Start testing the \(capacity) \(device.modelDescription)?"
        }
        return "Start testing the \(capacity) \(device.modelDescription), serial \(serial)?"
    }

    /// The one line of consequence that goes with the question.
    ///
    /// A confirmation that named the drive but not what is about to happen to it would be asking
    /// the user to agree to something unstated. This is the shortest honest form: what it does, and
    /// that it writes.
    static let confirmationConsequence =
        "Every block on it will be read, written back unchanged, and read again to verify."
}
