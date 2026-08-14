//
//  RunSequencer.swift
//  USBDriveTester (app target — unprivileged)
//
//  Step 11, increment 4. A whole-device run is a **sequence of bounded privileged calls**
//  (CONSTRAINTS section 2, Shape A). This is the app side of that sequence: it decides what to ask
//  for next, when to stop asking, and nothing else.
//
//  ## What it deliberately does not do
//
//  **It owns no run state** (user decision 2026-08-14). `RunControlState` stays with increment 5's
//  Start coordinator, which is the thing that performs unmount → acquire → release — so
//  `starting`, `claimEstablished`, `startAborted` and `deviceReleased` are states and events this
//  type can neither cause nor observe. A sequencer holding the machine would be modelling four
//  states it cannot reach. It reports facts through ``RunSequencerEvent`` and the coordinator
//  advances the machine.
//
//  **It accumulates nothing**, and that is the load-bearing one. From protocol v11 the session is
//  the claim, so a cycle reply's `chunksProcessed`, failure list, throughput and latency figures
//  are already **cumulative over the whole run**. The run's result is therefore the *final reply,
//  held whole* — plus the two things only this type knows: which I/O sizes were used, and that the
//  run covered block 0 to the device's end. Summing per-call figures would build a second source
//  for facts that now have one, and for the p99 it would simply be wrong: **percentiles do not
//  compose**, which is why the accumulator moved onto the claim in increment 3 rather than the app
//  doing arithmetic. `RunSequencerTests.theResultIsTheFinalReplyAndNothingIsSummed` is what pins
//  it.
//
//  The two reply fields that really are per-call, and that this type legitimately branches on, are
//  `runOutcomeCode` / `resumeBlock`. `bufferBytesHeld` is the third per-call field; nothing here
//  reads it.
//
//  ## `mayIssueNewWork` is a precondition, not a hint
//
//  It is `false` from the moment a quit is *pending*, and the quit confirmation is window-modal on
//  the main window, so other windows stay clickable underneath it — this is not a guard against an
//  unreachable state. It is consulted **before every call this type issues**, not once when the run
//  starts: "issue no further work" is the first half of the stop-at-the-call-boundary promise, and
//  a run that became a sequence rather than a single call is exactly where that half quietly stops
//  being kept.
//
//  It arrives as a closure rather than a captured value for the reason the engine's `control:` and
//  `grant:` are closures: a value read once would be the answer as it stood when the run started,
//  and the whole point is that it changes underneath a run already in flight.
//
//  ## The I/O size is fixed for the run (user decision 2026-08-14)
//
//  FR-CTRL-8's dropdown is enabled before a run and while one is paused or stopped, and disabled
//  while it is actively running. **Changing the size ends the run** rather than resuming it with a
//  new size — so the claim is released, the session dies with it, and the next Start begins with
//  clean accumulators *by construction*, which is the property Shape A was chosen for. That is why
//  ``RunSequenceResult/ioSizesUsed`` holds at most one element. The control and the FR-CTRL-8
//  amendment are increment 6's.
//

import Foundation
import os

private let log = Logger(subsystem: HelperIdentity.loggingSubsystem, category: "io")

// MARK: - The injected caller

/// Whatever can issue one bounded cycle.
///
/// The signature is `HelperConnection.runRetentionCycle(startBlock:blockCount:ioSizeBytes:failureMode:completion:)`
/// exactly, so the real caller conforms with an empty extension below — and the compiler, not a
/// later increment, is what checks that the abstraction fits the thing it abstracts. Build the
/// instrument before the mechanism.
@MainActor
protocol RunCycleIssuing {
    func runRetentionCycle(startBlock: UInt64,
                           blockCount: UInt64,
                           ioSizeBytes: Int,
                           failureMode: FailureModeCode,
                           completion: @escaping (Result<RunCycleOutcome, Error>) -> Void)
}

extension HelperConnection: RunCycleIssuing {}

// MARK: - What the sequencer reports

/// How a *run* ended — which is not the same question as how its last *call* ended.
///
/// A call that returns ``RunOutcomeCode/completed`` with the device only half covered, at the
/// moment a quit goes pending, is a run that ended without completing. One value answering both
/// questions is the "one flag stating two facts" defect, which the metrics probe already paid for
/// once this step.
nonisolated enum RunSequenceOutcome: Equatable {

    /// Every call completed and the last of them reached the device's final block.
    case completed

    /// **FR-FAIL-2, at run scope.** A call halted at a failed range because the mode said to, and
    /// **no further call was issued.** A sequencer that saw one call stop and then issued the next
    /// would turn `stopOnFirstError` into a no-op that still reported honestly per call.
    case stoppedOnFailure

    /// **FR-CTRL-4.** The user stopped the run. It cannot be continued (FR-FAIL-7).
    case stoppedByUser

    /// A quit went pending between calls, so no further work was issued. The in-flight call was
    /// allowed to return first — that is the call boundary the quit promise is made at.
    case haltedForQuit

    /// A call could not be made or was refused. **A refused call is not a run**: no report, and
    /// `reason` is logged so its absence is explicable.
    case callFailed(reason: String)
}

/// Everything a finished run hands to the report.
nonisolated struct RunSequenceResult: Equatable {

    let outcome: RunSequenceOutcome

    /// The **last reply the helper actually sent**, held whole. Cumulative over the run, per
    /// protocol v11. `nil` when no call ever returned successfully — which is a run that produced
    /// no figures rather than a run whose figures are zero.
    ///
    /// After a transport failure this is the *previous* call's reply: the session as of the last
    /// thing the helper actually said. Stating that is honest; re-deriving it would not be.
    let finalReply: RunCycleOutcome?

    /// The I/O sizes the run used, in order. At most one element — see this file's header.
    let ioSizesUsed: [Int]

    /// Always `0`. Runs cover the whole device and always start at block 0 (FR-TEST-4), and it is
    /// stated rather than assumed by whatever builds the report.
    let startBlock: UInt64

    /// The whole device, from the claim's authoritative ioctl geometry — what the run was *asked*
    /// to cover. How much of it was reached is the session's answer (`runProgress`), not this
    /// type's.
    let blockCount: UInt64
}

/// A fact the sequencer observed, for the coordinator that owns ``RunControlState``.
///
/// One channel rather than two, because "the run ended" and "here is the result" are one fact and
/// two channels for one fact is what `AppModel.helperHoldsDevice` is being deleted for.
nonisolated enum RunSequencerEvent: Equatable {

    /// **The helper settled at a chunk boundary with no write in flight** (NFR-REL-10) — the
    /// second party of the handshake, arriving as the call's own reply rather than as the
    /// acknowledgement of the pause *request*. Maps to `RunControlEvent.pauseSettled`, the only
    /// route to `RunControlState.paused`.
    case pauseSettled(resumeBlock: UInt64)

    /// The run is over, however it ended. Maps to `RunControlEvent.runEnded`.
    case runEnded(RunSequenceResult)
}

// MARK: - The sequencer

/// Issues a whole-device run as a sequence of bounded calls.
@MainActor
final class RunSequencer {

    /// Where the sequence is. **Not** `RunControlState`, deliberately — this is the sequencer's
    /// own bookkeeping about whether a call is outstanding, and it models nothing the coordinator
    /// owns.
    private enum Phase: Equatable { case notStarted, callInFlight, paused, ended }

    private let caller: RunCycleIssuing
    private let mayIssueNewWork: () -> Bool
    private let maximumBytesPerCall: UInt64
    private let onEvent: (RunSequencerEvent) -> Void

    private var phase: Phase = .notStarted
    private var logicalBlockSize: UInt32 = 0
    private var deviceBlockCount: UInt64 = 0
    private var ioSizeBytes = 0
    private var failureMode: FailureModeCode = .standard

    /// First untested block — the sequencer's own bookkeeping for issuing the next call, and
    /// deliberately **not** reported. How far the run got is the session's answer.
    private var position: UInt64 = 0

    private var ioSizesUsed: [Int] = []
    private var lastReply: RunCycleOutcome?
    private var stopRequested = false

    /// - Parameters:
    ///   - mayIssueNewWork: `AppModel.mayIssueNewWork`. A closure, not a value — see the header.
    ///   - maximumBytesPerCall: the per-call cap. Required with no default, so the suite can slice
    ///     with a ragged one and make ``RunSlicing``'s whole-MiB rounding observable.
    init(caller: RunCycleIssuing,
         mayIssueNewWork: @escaping () -> Bool,
         maximumBytesPerCall: UInt64,
         onEvent: @escaping (RunSequencerEvent) -> Void) {
        self.caller = caller
        self.mayIssueNewWork = mayIssueNewWork
        self.maximumBytesPerCall = maximumBytesPerCall
        self.onEvent = onEvent
    }

    // MARK: Commands

    /// Begin a whole-device run at block 0 (FR-TEST-4, FR-CTRL-1).
    ///
    /// - Returns: whether the run was begun. `false` while one is already in progress (FR-CTRL-9).
    ///   The coordinator consults `RunControlPolicy` before getting here, so a refusal is a wiring
    ///   defect announcing itself — which is why it is logged rather than absorbed.
    @discardableResult
    func start(logicalBlockSize: UInt32,
               deviceBlockCount: UInt64,
               ioSizeBytes: Int,
               failureMode: FailureModeCode) -> Bool {
        switch phase {
        case .callInFlight, .paused:
            log.error("run sequencer: start refused, a run is already in progress")
            return false
        case .notStarted, .ended:
            break
        }

        self.logicalBlockSize = logicalBlockSize
        self.deviceBlockCount = deviceBlockCount
        self.ioSizeBytes = ioSizeBytes
        self.failureMode = failureMode
        position = 0
        ioSizesUsed = []
        lastReply = nil
        stopRequested = false
        phase = .callInFlight

        issueNext()
        return true
    }

    /// Continue a paused run from its resume point (FR-CTRL-3).
    ///
    /// In-session, and therefore permitted: this is not FR-FAIL-7's prohibited cross-interruption
    /// resume.
    @discardableResult
    func resume() -> Bool {
        guard phase == .paused else {
            log.error("run sequencer: resume refused, no run is paused")
            return false
        }
        phase = .callInFlight
        issueNext()
        return true
    }

    /// Stop the run (FR-CTRL-4).
    ///
    /// Two different jobs depending on what is outstanding, and only one of them is this type's:
    ///
    ///   * **While a call is in flight**, the *helper* is what stops it — `setRunControl` on the
    ///     second connection, which the run reads at its next chunk boundary. This only guarantees
    ///     that no **further** call is issued whatever that call comes back as, which matters:
    ///     without it a call that completed normally in the same window would be followed by
    ///     another one.
    ///   * **While paused**, nothing is in flight and no reply is coming, so there is nothing to
    ///     settle and the run ends here.
    @discardableResult
    func stop() -> Bool {
        switch phase {
        case .callInFlight:
            stopRequested = true
            return true
        case .paused:
            finish(.stoppedByUser)
            return true
        case .notStarted, .ended:
            log.error("run sequencer: stop refused, there is no run to stop")
            return false
        }
    }

    // MARK: The loop

    private func issueNext() {
        switch RunSlicing.nextCall(from: position,
                                   logicalBlockSize: logicalBlockSize,
                                   deviceBlockCount: deviceBlockCount,
                                   maximumBytesPerCall: maximumBytesPerCall) {

        case .deviceCovered:
            // Asked FIRST, before the two permissions below, and the order is the point: a run
            // that has already covered the device issued no further work because there was none
            // left, not because a quit stopped it. Reporting `haltedForQuit` here would be the
            // hazard `quittingAfterTheRunHasAlreadyFinishedDoesNotWaitForever` pins on the quit
            // path, wearing a different hat.
            finish(.completed)

        case .cannotSlice(let reason):
            finish(.callFailed(reason: reason))

        case .call(let call):
            guard !stopRequested else {
                finish(.stoppedByUser)
                return
            }
            // **Before every call, not once at the start.**
            guard mayIssueNewWork() else {
                log.notice("run sequencer: a quit is pending, issuing no further calls")
                finish(.haltedForQuit)
                return
            }

            if ioSizesUsed.isEmpty { ioSizesUsed.append(ioSizeBytes) }
            phase = .callInFlight
            caller.runRetentionCycle(startBlock: call.startBlock,
                                     blockCount: call.blockCount,
                                     ioSizeBytes: ioSizeBytes,
                                     failureMode: failureMode) { [weak self] result in
                self?.callReturned(call, result)
            }
        }
    }

    private func callReturned(_ call: RunCall, _ result: Result<RunCycleOutcome, Error>) {
        // A reply arriving after the run ended — a stop that raced its own call — changes nothing.
        guard phase == .callInFlight else { return }

        switch result {
        case .failure(let error):
            // No reply, so nothing to attribute to this call. `lastReply` keeps the previous
            // call's cumulative figures, which is the session as of the last thing the helper
            // actually said.
            finish(.callFailed(reason: error.localizedDescription))

        case .success(let reply):
            lastReply = reply

            // Exhaustive rather than defaulted, so Step 12's device-loss outcome is a compile
            // error here instead of a silent fall-through to "keep going".
            switch reply.outcome {
            case .completed:
                position = call.endBlock
                issueNext()

            case .stoppedOnFailure:
                // **The mode stops the RUN, not the call.** The helper stopped this call because
                // FR-FAIL-2 said to; issuing the next one would cover the rest of the drive
                // anyway and turn the mode into a no-op that still reported honestly per call.
                finish(.stoppedOnFailure)

            case .pausedByUser:
                // `resumeBlock` is non-nil exactly for this code — the code is the discriminator,
                // not the value, because block 0 is a legitimate resume point.
                position = reply.resumeBlock ?? call.startBlock
                phase = .paused
                onEvent(.pauseSettled(resumeBlock: position))

            case .stoppedByUser:
                finish(.stoppedByUser)

            case .unrecognised:
                // A refusal, or a helper newer than this app. Never treated as a completion.
                finish(.callFailed(reason: reply.message))
            }
        }
    }

    private func finish(_ outcome: RunSequenceOutcome) {
        guard phase != .ended else { return }
        phase = .ended
        onEvent(.runEnded(RunSequenceResult(outcome: outcome,
                                            finalReply: lastReply,
                                            ioSizesUsed: ioSizesUsed,
                                            startBlock: 0,
                                            blockCount: deviceBlockCount)))
    }
}
