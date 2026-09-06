//
//  RunSequencerTests.swift
//  The whole-device sequencer (Step 11, increment 4). FR-CTRL-1/3/4/9, FR-FAIL-2, FR-TEST-4/10.
//
//  Driven through an **injected caller** that never returns until the test says so, which is what
//  makes every branch below reachable with no hardware, no helper and no claim. The fake records
//  each request and holds its completion, so the test controls the interleaving — including the
//  ones that only exist between two calls, which is where three of this increment's four
//  obligations live.
//
//  Four properties are load-bearing and each looks like a formality:
//
//    * **`mayContinueRun` is consulted before EVERY call**, not once at the start. A run became a
//      sequence in this increment, and that is exactly where "issue no further work" quietly stops
//      being kept. Pinned from three directions: before the first call, between two calls, and at
//      a resume.
//    * **…but a run that had already covered the device COMPLETED**, even if a quit went pending
//      in the meantime. It issued no further work because there was none, not because it was
//      stopped. Same hazard `quittingAfterTheRunHasAlreadyFinishedDoesNotWaitForever` pins on the
//      quit path, and it is a question of which check comes first.
//    * **`stopOnFirstError` stops the RUN.** The helper halts the call; a sequencer that then
//      issued the next one would cover the rest of the drive anyway and turn FR-FAIL-2 into a
//      no-op that still reported honestly per call. Nothing in a per-call reply would reveal it.
//    * **Nothing is summed.** From protocol v11 a reply's figures are already cumulative over the
//      run, so the result is the final reply held whole. Percentiles do not compose; an app
//      aggregating them would produce a number that is not any run's p99.
//

import Testing
import Foundation
@testable import USBDriveTester

// MARK: - Fixtures

/// A four-call device: three whole 4 MiB calls and a short final one, so the final-call exemption
/// and the ordinary case are both exercised by the plain whole-device run.
private enum Device {
    static let blockSize: UInt32 = 512
    static let cap: UInt64 = 4 << 20
    static let ioSize: Int = 1 << 20
    static let blockCount: UInt64 = 8_192 * 3 + 700

    static let expectedCalls: [RunCall] = [
        RunCall(startBlock: 0, blockCount: 8_192),
        RunCall(startBlock: 8_192, blockCount: 8_192),
        RunCall(startBlock: 16_384, blockCount: 8_192),
        RunCall(startBlock: 24_576, blockCount: 700),
    ]
}

/// One `runRetentionCycle` reply, with everything the sequencer does not read defaulted.
///
/// The three fields it *does* read are the ones spelled out at each call site: the outcome code,
/// the resume block, and — for the no-summing check — the cumulative figures.
private func reply(_ outcome: RunOutcomeCode,
                   interruptedAtBlock: UInt64 = 0,
                   chunksProcessed: UInt64 = 0,
                   failedBlockCount: UInt64 = 0,
                   readLatencySampleCount: UInt64 = 0,
                   readLatencyP99Nanoseconds: UInt64 = 0,
                   bufferBytesHeld: Int = 0,
                   message: String = "",
                   deviceLossPhase: DeviceLossPhaseCode = .unrecognised) -> RunCycleOutcome {
    RunCycleOutcome(runOutcomeCode: outcome.rawValue,
                    interruptedAtBlock: interruptedAtBlock,
                    chunksProcessed: chunksProcessed,
                    failedRangeCount: 0,
                    failureSummary: "",
                    cacheBypassCode: CacheBypassOutcome.bypassed.rawValue,
                    bufferBytesHeld: bufferBytesHeld,
                    hostOverheadFraction: -1,
                    helperCoreFraction: -1,
                    failureModeUsedCode: FailureModeCode.logAndContinue.rawValue,
                    failedRangesEncoded: "",
                    failedBlockCount: failedBlockCount,
                    deviceReadBytesPerSecond: -1,
                    writeBytesPerSecond: -1,
                    coverageBytesPerSecond: -1,
                    completedBytesPerSecond: -1,
                    readLatencySampleCount: readLatencySampleCount,
                    readLatencyMinimumNanoseconds: 0,
                    readLatencyMaximumNanoseconds: 0,
                    readLatencyP99UpperBoundNanoseconds: readLatencyP99Nanoseconds,
                    message: message,
                    deviceLossPhaseCode: deviceLossPhase.rawValue)
}

private struct FakeTransportError: Error, LocalizedError {
    var errorDescription: String? { "the helper connection dropped" }
}

/// Records every request and holds its completion until the test answers it.
@MainActor
private final class FakeCaller: RunCycleIssuing {

    struct Request: Equatable {
        let startBlock: UInt64
        let blockCount: UInt64
        let ioSizeBytes: Int
        let failureMode: FailureModeCode
    }

    private(set) var requests: [Request] = []
    private var pending: ((Result<RunCycleOutcome, Error>) -> Void)?

    var hasCallInFlight: Bool { pending != nil }

    var calls: [RunCall] {
        requests.map { RunCall(startBlock: $0.startBlock, blockCount: $0.blockCount) }
    }

    func runRetentionCycle(startBlock: UInt64,
                           blockCount: UInt64,
                           ioSizeBytes: Int,
                           failureMode: FailureModeCode,
                           completion: @escaping (Result<RunCycleOutcome, Error>) -> Void) {
        requests.append(Request(startBlock: startBlock,
                                blockCount: blockCount,
                                ioSizeBytes: ioSizeBytes,
                                failureMode: failureMode))
        pending = completion
    }

    /// Answer the outstanding call. Cleared **before** the completion runs, so the next call the
    /// completion issues installs its own.
    @discardableResult
    func answer(_ result: Result<RunCycleOutcome, Error>) -> Bool {
        guard let completion = pending else { return false }
        pending = nil
        completion(result)
        return true
    }

    @discardableResult
    func answer(_ outcome: RunCycleOutcome) -> Bool { answer(.success(outcome)) }
}

@MainActor
private final class Harness {

    let caller = FakeCaller()
    var mayContinueRun = true
    private(set) var events: [RunSequencerEvent] = []

    private let cap: UInt64

    init(cap: UInt64 = Device.cap) { self.cap = cap }

    lazy var sequencer = RunSequencer(
        caller: caller,
        mayContinueRun: { [unowned self] in self.mayContinueRun },
        maximumBytesPerCall: cap,
        onEvent: { [unowned self] event in self.events.append(event) })

    @discardableResult
    func start(ioSize: Int = Device.ioSize,
               mode: FailureModeCode = .logAndContinue,
               blockCount: UInt64 = Device.blockCount) -> Bool {
        sequencer.start(logicalBlockSize: Device.blockSize,
                        deviceBlockCount: blockCount,
                        ioSizeBytes: ioSize,
                        failureMode: mode)
    }

    /// The one `runEnded` result, or `nil` while the run is still going.
    var result: RunSequenceResult? {
        for event in events {
            if case .runEnded(let result) = event { return result }
        }
        return nil
    }

    var resumeBlocksReported: [UInt64] {
        events.compactMap {
            if case .pauseSettled(let block) = $0 { return block } else { return nil }
        }
    }

    /// Answer every outstanding call with a completion until the run ends.
    func answerEveryCallCompleted(limit: Int = 64) {
        var answered = 0
        while caller.hasCallInFlight, answered < limit {
            caller.answer(reply(.completed))
            answered += 1
        }
    }
}

// MARK: - The ordinary whole-device run

@MainActor
struct RunSequencerRunTests {

    @Test func aWholeDeviceRunIssuesExactlyTheCallsTheSlicerPlanned() {
        let harness = Harness()
        harness.start()
        harness.answerEveryCallCompleted()

        #expect(harness.caller.calls == Device.expectedCalls)
        #expect(harness.result?.outcome == .completed)
    }

    /// FR-TEST-4 and CONSTRAINTS section 2: runs cover the whole device and always start at
    /// block 0. Stated in the result rather than assumed by whatever builds the report.
    @Test func theResultNamesTheWholeDeviceAsWhatWasAskedFor() {
        let harness = Harness()
        harness.start()
        harness.answerEveryCallCompleted()

        #expect(harness.result?.startBlock == 0)
        #expect(harness.result?.blockCount == Device.blockCount)
    }

    /// The mode and the size reach every call, not just the first.
    @Test func everyCallCarriesTheModeAndSizeTheRunStartedWith() {
        let harness = Harness()
        harness.start(ioSize: 2 << 20, mode: .stopOnFirstError)
        harness.answerEveryCallCompleted()

        #expect(harness.caller.requests.count == 4)
        for request in harness.caller.requests {
            #expect(request.ioSizeBytes == 2 << 20)
            #expect(request.failureMode == .stopOnFirstError)
        }
    }

    /// One element, because the size is fixed for the run and changing it ends the run rather than
    /// resuming with a new one (user decision 2026-08-14).
    @Test func theSizeListHoldsTheOneSizeTheRunUsed() {
        let harness = Harness()
        harness.start(ioSize: 8 << 20)
        harness.answerEveryCallCompleted()

        #expect(harness.result?.ioSizesUsed == [8 << 20])
    }

    /// **FR-CTRL-9.** One run at a time, and the second Start is refused rather than issuing a
    /// second sequence into the same claim.
    @Test func startIsRefusedWhileARunIsAlreadyInProgress() {
        let harness = Harness()
        #expect(harness.start())
        #expect(harness.start() == false)
        #expect(harness.caller.requests.count == 1)
    }
}

// MARK: - `mayContinueRun` is a precondition, not a hint

@MainActor
struct RunSequencerQuitTests {

    @Test func aQuitAlreadyPendingIssuesNoCallAtAll() {
        let harness = Harness()
        harness.mayContinueRun = false
        harness.start()

        #expect(harness.caller.requests.isEmpty)
        #expect(harness.result?.outcome == .haltedForQuit)
        // No call returned, so there are no figures. A run that produced none is not a run whose
        // figures are zero — a refused call is not a run, and gets no report.
        #expect(harness.result?.finalReply == nil)
        #expect(harness.result?.ioSizesUsed == [])
    }

    /// **The one this increment exists for.** Checked before every call, not once at the start:
    /// the quit confirmation is window-modal, so it can go pending at any point in a sequence that
    /// runs for hours.
    @Test func aQuitGoingPendingBetweenCallsStopsTheRun() {
        let harness = Harness()
        harness.start()

        harness.caller.answer(reply(.completed))        // call 1 done, call 2 issued
        #expect(harness.caller.requests.count == 2)

        harness.mayContinueRun = false
        harness.caller.answer(reply(.completed))        // call 2 done — call 3 must not be issued

        #expect(harness.caller.requests.count == 2)
        #expect(harness.result?.outcome == .haltedForQuit)
    }

    @Test func aQuitGoingPendingWhilePausedStopsTheResume() {
        let harness = Harness()
        harness.start()
        harness.caller.answer(reply(.pausedByUser, interruptedAtBlock: 8_192))
        #expect(harness.caller.requests.count == 1)

        harness.mayContinueRun = false
        #expect(harness.sequencer.resume())

        #expect(harness.caller.requests.count == 1)
        #expect(harness.result?.outcome == .haltedForQuit)
    }

    /// **And the other way round.** A run that had already covered the device completed — it
    /// issued no further work because there was none left, not because a quit stopped it. This is
    /// which-check-comes-first, and getting it wrong would misreport every run that ends while a
    /// quit dialog is up.
    @Test func aRunThatHadAlreadyCoveredTheDeviceCompletesDespiteAPendingQuit() {
        let harness = Harness()
        harness.start()

        harness.caller.answer(reply(.completed))
        harness.caller.answer(reply(.completed))
        harness.caller.answer(reply(.completed))        // call 4 — the last — now in flight
        #expect(harness.caller.requests.count == 4)

        harness.mayContinueRun = false
        harness.caller.answer(reply(.completed))

        #expect(harness.result?.outcome == .completed)
        #expect(harness.caller.requests.count == 4)
    }
}

// MARK: - The failure mode stops the run, not the call

@MainActor
struct RunSequencerFailureModeTests {

    /// **FR-FAIL-2 at run scope.** The helper halted this call because the mode said to; issuing
    /// the next one would refresh the rest of the drive anyway, turning the mode into a no-op that
    /// still reported honestly per call. Nothing in a reply would reveal that.
    @Test func stoppingOnAFailureStopsTheRunAndNotJustTheCall() {
        let harness = Harness()
        harness.start(mode: .stopOnFirstError)

        harness.caller.answer(reply(.completed))            // call 1 fine, call 2 issued
        harness.caller.answer(reply(.stoppedOnFailure))     // call 2 halted

        #expect(harness.caller.requests.count == 2)
        #expect(harness.result?.outcome == .stoppedOnFailure)
    }

    /// The same reply under log-and-continue is still a stopped run. The helper decides *whether*
    /// a failure stops a call; when it says one did, the sequencer does not second-guess it and
    /// carry on.
    @Test func aStoppedCallEndsTheRunWhicheverModeWasAskedFor() {
        let harness = Harness()
        harness.start(mode: .logAndContinue)
        harness.caller.answer(reply(.stoppedOnFailure))

        #expect(harness.caller.requests.count == 1)
        #expect(harness.result?.outcome == .stoppedOnFailure)
    }
}

// MARK: - Pause, resume and stop

@MainActor
struct RunSequencerControlTests {

    /// The pause arrives as the **call's own reply** carrying `pausedByUser` and its resume block —
    /// the helper stating it settled at a chunk boundary with no write in flight (NFR-REL-10) — not
    /// as the acknowledgement of the pause request.
    @Test func aPauseHaltsTheSequenceAndReportsWhereItWillResume() {
        let harness = Harness()
        harness.start()
        harness.caller.answer(reply(.pausedByUser, interruptedAtBlock: 6_144))

        #expect(harness.resumeBlocksReported == [6_144])
        #expect(harness.caller.requests.count == 1)
        #expect(harness.caller.hasCallInFlight == false)
        // A pause is not the run ending.
        #expect(harness.result == nil)
    }

    @Test func resumingContinuesFromTheResumeBlockRatherThanTheNextCallBoundary() {
        let harness = Harness()
        harness.start()
        harness.caller.answer(reply(.pausedByUser, interruptedAtBlock: 6_144))
        #expect(harness.sequencer.resume())

        #expect(harness.caller.calls.last == RunCall(startBlock: 6_144, blockCount: 8_192))

        harness.answerEveryCallCompleted()
        #expect(harness.result?.outcome == .completed)
        #expect(harness.caller.calls.last?.endBlock == Device.blockCount)
    }

    @Test func resumingIsRefusedWhenNothingIsPaused() {
        let harness = Harness()
        harness.start()
        #expect(harness.sequencer.resume() == false)
        #expect(harness.caller.requests.count == 1)
    }

    /// **FR-CTRL-4 while paused.** Nothing is in flight and no reply is coming, so there is nothing
    /// to settle — without this the run would sit paused forever with no way out.
    @Test func stoppingWhilePausedEndsTheRun() {
        let harness = Harness()
        harness.start()
        harness.caller.answer(reply(.pausedByUser, interruptedAtBlock: 6_144))

        #expect(harness.sequencer.stop())
        #expect(harness.result?.outcome == .stoppedByUser)
        #expect(harness.caller.requests.count == 1)
    }

    /// **Even a call that comes back completed must not be followed by another** once Stop has been
    /// pressed. The helper's own stop settles the call in flight; this is what guarantees the
    /// sequence itself does not simply carry on if that call had already finished.
    @Test func stoppingWhileACallIsInFlightIssuesNoFurtherCall() {
        let harness = Harness()
        harness.start()
        harness.caller.answer(reply(.completed))        // call 2 in flight

        #expect(harness.sequencer.stop())
        harness.caller.answer(reply(.completed))        // call 2 completes normally

        #expect(harness.caller.requests.count == 2)
        #expect(harness.result?.outcome == .stoppedByUser)
    }

    /// The helper settling a stop at a chunk boundary ends the run the same way.
    @Test func aStoppedByUserReplyEndsTheRun() {
        let harness = Harness()
        harness.start()
        harness.caller.answer(reply(.stoppedByUser, interruptedAtBlock: 4_096))

        #expect(harness.result?.outcome == .stoppedByUser)
        #expect(harness.caller.requests.count == 1)
        // FR-FAIL-7: a stopped run cannot be continued, so no resume point exists to be ignored.
        #expect(harness.result?.finalReply?.resumeBlock == nil)
    }

    // MARK: - Device loss (Step 12, protocol v15)

    /// **The device went away, so no further call is issued.** The next range would ask the helper
    /// to address a device that is not there, and FR-FAIL-7 forbids continuing across it in any
    /// case. The request count is what makes this a check rather than a restatement: a sequencer
    /// that treated the fifth code as "keep going" would issue a second call here.
    @Test func aDeviceLossReplyEndsTheRunAndIssuesNoFurtherCall() {
        let harness = Harness()
        harness.start()
        harness.caller.answer(reply(.deviceLost, interruptedAtBlock: 4_096,
                                    deviceLossPhase: .writingBack))

        #expect(harness.result?.outcome == .deviceLost)
        #expect(harness.caller.requests.count == 1)
        #expect(harness.result?.finalReply?.resumeBlock == nil)
        #expect(harness.result?.finalReply?.deviceLostAtBlock == 4_096)
        #expect(harness.result?.finalReply?.deviceLossPhase == .writingBack)
    }

    /// **Device loss is not a call failure**, even though both end a run without covering the
    /// drive. A call that failed says *this app could not talk to the helper*; this says *the
    /// drive is not there any more*. They lead to different sentences and to different next steps
    /// — FR-DEV-8's discovery re-run belongs to exactly one of them — and before v15 the helper
    /// had no way to say which had happened, so this outcome arrived as the other one.
    @Test func aDeviceLossIsNotReportedAsACallFailure() {
        let harness = Harness()
        harness.start()
        harness.caller.answer(reply(.deviceLost, interruptedAtBlock: 0, deviceLossPhase: .reading))

        let outcome = harness.result?.outcome
        #expect(outcome == .deviceLost)
        if case .callFailed = outcome { Issue.record("device loss must not read as a call failure") }
    }

    /// A run that loses its device part-way keeps the figures from the calls that did happen. The
    /// reply is cumulative over the run (protocol v11), so the last one the helper actually sent
    /// is the session as of the moment the drive left — not zero, and not discarded.
    @Test func aDeviceLossKeepsWhatTheRunHadAlreadyMeasured() {
        let harness = Harness()
        harness.start()
        harness.caller.answer(reply(.completed, chunksProcessed: 64))
        harness.caller.answer(reply(.deviceLost, interruptedAtBlock: 8_192,
                                    chunksProcessed: 97, deviceLossPhase: .verifying))

        #expect(harness.result?.outcome == .deviceLost)
        #expect(harness.result?.finalReply?.chunksProcessed == 97)
        #expect(harness.caller.requests.count == 2, "the second call was issued and then died")
    }

    // MARK: - Route (b): the drive left and no reply said so (Step 12, chunk 4)

    /// **The case route (b) exists for, at sequencer scope.** A paused run has returned from its
    /// call and issues no syscalls at all, so `ENXIO` can never arrive and route (a) is
    /// structurally blind. Without this the run would sit paused for ever, holding an exclusive
    /// claim on a drive that is not attached.
    @Test func aDriveLeavingWhilePausedEndsTheRun() {
        let harness = Harness()
        harness.start()
        harness.caller.answer(reply(.pausedByUser, interruptedAtBlock: 6_144))

        #expect(harness.sequencer.deviceLost())
        #expect(harness.result?.outcome == .deviceLost)
        #expect(harness.caller.requests.count == 1, "no further call may be issued")
    }

    /// **Not `stoppedByUser`**, which is what `stop()` from the same phase produces — and the
    /// difference is the whole point of a separate command. Nobody pressed anything; the report's
    /// outcome and FR-DEV-8's next steps both hang off which of the two this was.
    @Test func aDriveLeavingWhilePausedIsNotAUserStop() {
        let harness = Harness()
        harness.start()
        harness.caller.answer(reply(.pausedByUser, interruptedAtBlock: 6_144))
        harness.sequencer.deviceLost()

        #expect(harness.result?.outcome != .stoppedByUser)
    }

    /// With a call in flight the run ends here too — the caller is what decides whether to wait for
    /// route (a) first, and `DeviceLossWindDown` is where that decision lives.
    @Test func aDriveLeavingWithACallInFlightEndsTheRun() {
        let harness = Harness()
        harness.start()

        #expect(harness.sequencer.deviceLost())
        #expect(harness.result?.outcome == .deviceLost)
        #expect(harness.caller.requests.count == 1)
    }

    /// **The two routes must not end one run twice.** Route (b) ends it, then the helper's reply
    /// finally arrives carrying its own device loss — and it changes nothing, because the phase is
    /// already `.ended`. This is the race the whole chunk is built around, run in the order that
    /// produces the double-fire.
    @Test func aReplyArrivingAfterRouteBHasEndedTheRunChangesNothing() {
        let harness = Harness()
        harness.start()
        harness.sequencer.deviceLost()

        harness.caller.answer(reply(.deviceLost, interruptedAtBlock: 4_096))

        let endings = harness.events.filter { if case .runEnded = $0 { return true } else { return false } }
        #expect(endings.count == 1, "the run ended twice")
        #expect(harness.caller.requests.count == 1)
    }

    /// **One unplug, several callbacks** — one for the whole disk and one per slice (measured
    /// 2026-09-05). The second and third find the run already over and cost nothing.
    @Test func aSecondDisappearanceFindsNoRunToEnd() {
        let harness = Harness()
        harness.start()

        #expect(harness.sequencer.deviceLost())
        #expect(!harness.sequencer.deviceLost())
        #expect(!harness.sequencer.deviceLost())

        let endings = harness.events.filter { if case .runEnded = $0 { return true } else { return false } }
        #expect(endings.count == 1)
    }

    /// A drive cannot be lost from a run that was never started. Answering `false` is what lets the
    /// controller treat a disappearance arriving after everything as free.
    @Test func aDriveLeavingWithNoRunEndsNothing() {
        let harness = Harness()
        #expect(!harness.sequencer.deviceLost())
        #expect(harness.result == nil)
    }

    /// The figures the run had already gathered survive it. A drive leaving does not make the
    /// blocks already verified un-verified, and the last reply the helper actually sent is what the
    /// report is built from.
    @Test func aDriveLeavingKeepsWhatTheRunHadAlreadyMeasured() {
        let harness = Harness()
        harness.start()
        harness.caller.answer(reply(.completed, chunksProcessed: 12))

        harness.sequencer.deviceLost()

        #expect(harness.result?.outcome == .deviceLost)
        #expect(harness.result?.finalReply?.chunksProcessed == 12)
    }

    @Test func stoppingIsRefusedWhenThereIsNoRun() {
        let harness = Harness()
        #expect(harness.sequencer.stop() == false)
    }
}

// MARK: - What is not a run

@MainActor
struct RunSequencerRefusalTests {

    @Test func aTransportFailureEndsTheRunWithNoFurtherCall() {
        let harness = Harness()
        harness.start()
        harness.caller.answer(reply(.completed))
        harness.caller.answer(.failure(FakeTransportError()))

        #expect(harness.caller.requests.count == 2)
        guard case .callFailed(let reason)? = harness.result?.outcome else {
            Issue.record("expected a failed call, got \(String(describing: harness.result?.outcome))")
            return
        }
        #expect(reason.contains("connection"))
    }

    /// After a transport failure the figures held are the **previous** call's — the session as of
    /// the last thing the helper actually said. Stating that is honest; the alternative is a result
    /// that has no figures at all for a run that measured plenty.
    @Test func aTransportFailureKeepsTheLastReplyTheHelperActuallySent() {
        let harness = Harness()
        harness.start()
        harness.caller.answer(reply(.completed, chunksProcessed: 11))
        harness.caller.answer(.failure(FakeTransportError()))

        #expect(harness.result?.finalReply?.chunksProcessed == 11)
    }

    /// **Never treated as a completion.** A refusal — or a helper newer than this app — is not a
    /// run, so there is no report and the run does not carry on to the next call.
    @Test func anUnrecognisedOutcomeIsARefusalRatherThanACompletion() {
        let harness = Harness()
        harness.start()
        harness.caller.answer(reply(.unrecognised, message: "the alignment guard refused this"))

        #expect(harness.caller.requests.count == 1)
        guard case .callFailed(let reason)? = harness.result?.outcome else {
            Issue.record("expected a failed call, got \(String(describing: harness.result?.outcome))")
            return
        }
        #expect(reason.contains("alignment"))
    }

    /// Geometry the slicer cannot work with never reaches the helper as a call it would refuse.
    @Test func aDeviceThatCannotBeSlicedIssuesNoCall() {
        let harness = Harness()
        harness.start(blockCount: 0)

        #expect(harness.caller.requests.isEmpty)
        guard case .callFailed? = harness.result?.outcome else {
            Issue.record("expected a failed call, got \(String(describing: harness.result?.outcome))")
            return
        }
    }
}

// MARK: - The sequencer accumulates nothing

@MainActor
struct RunSequencerAccumulationTests {

    /// **The figures are the final reply's, held whole.** From protocol v11 they are already
    /// cumulative over the whole run, so anything the app added would be a second source for facts
    /// that have one.
    ///
    /// The p99 deliberately goes **down** on the third call. That is not a claim about how a
    /// cumulative percentile behaves — it is the discriminator: a sequencer that kept the maximum,
    /// or the first, or a mean, gives a different answer here, and one that passes the last reply
    /// through gives 700.
    @Test func theResultIsTheFinalReplyAndNothingIsSummed() {
        let harness = Harness()
        harness.start()

        harness.caller.answer(reply(.completed, chunksProcessed: 10, failedBlockCount: 1,
                                    readLatencySampleCount: 5, readLatencyP99Nanoseconds: 1_000))
        harness.caller.answer(reply(.completed, chunksProcessed: 20, failedBlockCount: 3,
                                    readLatencySampleCount: 9, readLatencyP99Nanoseconds: 2_000))
        harness.caller.answer(reply(.completed, chunksProcessed: 30, failedBlockCount: 4,
                                    readLatencySampleCount: 14, readLatencyP99Nanoseconds: 500))
        harness.caller.answer(reply(.completed, chunksProcessed: 33, failedBlockCount: 6,
                                    readLatencySampleCount: 17, readLatencyP99Nanoseconds: 700))

        let final = harness.result?.finalReply
        #expect(final?.chunksProcessed == 33)                        // not 93
        #expect(final?.failedBlockCount == 6)                        // not 14
        #expect(final?.readLatencySampleCount == 17)                 // not 45
        #expect(final?.readLatencyP99UpperBound == .nanoseconds(700))  // not 2,000, not 1,000
    }

    /// `bufferBytesHeld` is one of the two fields that stayed **per call** in v11, so the result
    /// carries the last call's — and carries it by passing the reply through rather than by
    /// picking fields out of it.
    @Test func theFinalReplyIsCarriedWholeRatherThanFieldByField() {
        let harness = Harness()
        harness.start()
        harness.caller.answer(reply(.completed, bufferBytesHeld: 111))
        harness.caller.answer(reply(.completed, bufferBytesHeld: 222))
        harness.caller.answer(reply(.completed, bufferBytesHeld: 333))
        let last = reply(.completed, chunksProcessed: 77, bufferBytesHeld: 444, message: "done")
        harness.caller.answer(last)

        #expect(harness.result?.finalReply == last)
    }

    /// A paused run's figures are the pausing call's, and they stay that way across the resume
    /// until the next reply replaces them.
    @Test func aPausedRunKeepsThePausingCallsFigures() {
        let harness = Harness()
        harness.start()
        harness.caller.answer(reply(.pausedByUser, interruptedAtBlock: 6_144, chunksProcessed: 9))
        harness.sequencer.stop()

        #expect(harness.result?.finalReply?.chunksProcessed == 9)
    }
}
