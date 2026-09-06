//
//  DeviceLossAccount.swift
//  USBDriveTester (app target — unprivileged)
//
//  Step 12, chunk 5. **What the report is entitled to say about a drive that left.**
//
//  ## The question this type exists to answer
//
//  Not "did the drive go away" — ``RunReportOutcome/deviceLost`` already says that. This answers
//  the only question a person has that the outcome cannot:
//
//  > **Was this tool part-way through writing a chunk back when the drive went?**
//
//  It matters because of what the tool does. Every chunk is read, written back unchanged, and read
//  again (FR-TEST-1/3/7). During the **write-back** — and only then — the tool holds the chunk's
//  only copy of the original and has not finished putting it back. A drive that leaves in that
//  window may hold partly written data in that one chunk. A drive that leaves during a read, or
//  during the verify that follows a write-back the helper already reported as successful, does not.
//
//  So the answer is worth a lot, and getting it wrong in either direction is expensive: a false
//  alarm in a file that outlives the session teaches a reader to discount this document, and a
//  false reassurance is the failure this whole step exists to stop.
//
//  ## Why it is three-and-a-bit cases rather than a block and a phase
//
//  Because the two routes that detect device loss know different things, and one of them knows
//  nothing about *when* (see `DeviceLossWindDown`'s header):
//
//    * **Route (a)** — the helper's `pread`/`pwrite` answered `ENXIO`, the reply carries the block
//      and the phase (protocol v15). This is the case where the report can be specific.
//    * **Route (b), nothing in flight** — the run was **paused**, so no call was outstanding and no
//      chunk was part-way through anything. That is a genuinely reassuring fact and the report
//      should say it.
//    * **Route (b), the deadline expired** — a call *was* in flight and the helper never said which
//      phase it had reached. The report cannot rule a write-back out, and must not pretend to.
//
//  Collapsing the last two would mean warning about a partly written chunk on a run that was
//  demonstrably paused with nothing outstanding. That is a false alarm about somebody's drive, in
//  a persisted document, and it is exactly the kind of over-claim `HonestFraming` exists to stop.
//
//  ## Why it is a pure function of what the two routes reported
//
//  ``forRun(endedBy:lostAtBlock:phase:removalCallbackSaid:)`` takes what each route said and
//  returns what may be claimed. That makes the **contradiction** case — a run that ended as a
//  device loss with neither route saying anything — directly reachable by a test, which is the only
//  reason it can be a named case rather than a force-unwrap or a silent guess. See
//  ``noRouteSaidAnything``.
//

import Foundation

/// What is known about the moment the drive under test left, from whichever route saw it.
///
/// `nil` at the call site — rather than a case of this enum — means **no device loss happened**.
/// A run that ended some other way has no account, and that is different from having an empty one.
nonisolated enum DeviceLossAccount: Equatable {

    /// **Route (a).** The helper's own reply named where the run was and what it was doing
    /// (protocol v15, Step 12 chunk 3). The specific case, and the common one: the reply is
    /// normally milliseconds behind the removal callback.
    case theHelperSaidWhere(block: UInt64, phase: DeviceLossPhaseCode)

    /// **Route (b), way 1.** The run was paused when the drive left, so nothing was outstanding.
    ///
    /// A paused run issues no syscalls, which is why route (a) is blind to this case entirely —
    /// and it is also why this case can state something the others cannot: no chunk was part-way
    /// through, so nothing was left half-written.
    case nothingWasInFlight

    /// **Route (b), way 3.** A call was in flight and the helper never answered it.
    ///
    /// The report knows a chunk was outstanding and cannot say which phase it had reached, so a
    /// write-back cannot be ruled out — nor can it be asserted.
    case theHelperNeverAnswered

    /// **Neither route said anything**, on a run that nevertheless ended because the device was
    /// gone.
    ///
    /// A contradiction rather than an expected ending: `RunController` sets the removal callback's
    /// ending before it asks the sequencer to end the run, and route (a) cannot reach this outcome
    /// without a reply. It is a named case rather than a `fatalError` or a silent fold into
    /// ``theHelperNeverAnswered`` for the reason
    /// ``RunReportOutcome/forRun(endedBy:replyDidComplete:foundFailures:)`` keeps its own
    /// refuse-to-guess guards: **the app cannot resolve a contradiction between its own sources,
    /// and naming one is honest where picking a side is not.** Being a case of a pure function's
    /// return type is what makes it testable at all.
    case noRouteSaidAnything

    /// Whether this account leaves open the possibility that a chunk was **part-way through being
    /// written back**.
    ///
    /// The safety-relevant reading, and deliberately conservative: anything short of positive
    /// knowledge that no write was outstanding answers `true`. `false` is a claim, and only the
    /// three cases that have earned it make it.
    var aWriteBackMayBeUnfinished: Bool {
        switch self {
        case .theHelperSaidWhere(_, let phase):
            switch phase {
            case .writingBack:
                return true
            case .reading, .verifying:
                // `reading` had written nothing; `verifying` follows a write-back the helper had
                // already reported successful, so the chunk was whole before the drive went.
                return false
            case .unrecognised:
                // A helper newer than this app named a phase it cannot map. **Never read as
                // success** — the same rule `CacheBypassOutcome.unrecognised` follows.
                return true
            }
        case .nothingWasInFlight:
            return false
        case .theHelperNeverAnswered, .noRouteSaidAnything:
            return true
        }
    }

    /// The block the run had reached, where a route was able to say. `nil` is not "block 0".
    var block: UInt64? {
        if case .theHelperSaidWhere(let block, _) = self { return block }
        return nil
    }

    /// The block as a reader sees it, digit-grouped. `nil`, never `"0"` and never an em-dash,
    /// where no route could say — this file's rule about a figure that was not measured.
    var blockDescription: String? {
        block.map { "block " + MetricsFormatting.blockOffset($0) }
    }

    /// Which phase was in flight, where a route was able to say.
    ///
    /// `nil` for every route-(b) case **and** for a phase this build cannot name: a report that
    /// does not know the phase and one that was sent a phase it cannot map are both reports with
    /// no phase to print, and neither may print a guess.
    var namedPhase: DeviceLossPhaseCode? {
        guard case .theHelperSaidWhere(_, let phase) = self, phase != .unrecognised else {
            return nil
        }
        return phase
    }

    /// Decide the account from what each route reported.
    ///
    /// - Parameters:
    ///   - ending: how the **run** ended. Anything but ``RunSequenceOutcome/deviceLost`` has no
    ///     account at all, which is why the return is optional.
    ///   - lostAtBlock: `RunCycleOutcome.deviceLostAtBlock` — route (a)'s block, or `nil`.
    ///   - phase: `RunCycleOutcome.deviceLossPhase` — route (a)'s phase, or `nil`. The two arrive
    ///     together or not at all, and one without the other is treated as neither.
    ///   - removalCallbackSaid: how the removal callback's wind-down ended the run, or `nil` where
    ///     it was not the thing that ended it.
    static func forRun(endedBy ending: RunSequenceOutcome,
                       lostAtBlock: UInt64?,
                       phase: DeviceLossPhaseCode?,
                       removalCallbackSaid: DeviceLossEnding?) -> DeviceLossAccount? {
        guard ending == .deviceLost else { return nil }

        // Route (a) first where it spoke, because it is the only route that knows *when*. Both
        // halves are required: `HelperConnection` sets them together from one outcome code, so one
        // without the other is a wiring defect rather than a partial answer, and half of route
        // (a)'s reading is not better than none of it.
        if let lostAtBlock, let phase {
            return .theHelperSaidWhere(block: lostAtBlock, phase: phase)
        }

        switch removalCallbackSaid {
        case .nothingWasInFlight:     return .nothingWasInFlight
        case .theHelperNeverAnswered: return .theHelperNeverAnswered
        case nil:                     return .noRouteSaidAnything
        }
    }
}
