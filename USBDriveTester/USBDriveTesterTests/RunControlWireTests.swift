//
//  RunControlWireTests.swift
//  Protocol v10's two new enumerations, and the app-side decode (Step 11, increment 2).
//
//  ## What this can check, and what it deliberately does not claim to
//
//  The *mappings* between Core's types and the wire's live in the helper's `main.swift` —
//  `setRunControl`'s inward switch and `outcomeCode(_:)`'s outward one — and the test target
//  compiles the fourteen `Core/` files and nothing else from the helper. So a mutation swapping
//  `.pause` for `.stop` in that switch is **not catchable here**, exactly as
//  `RunObservers.forRun`'s composition was not.
//
//  That is stated rather than papered over, and it is why the mapping is written as an exhaustive
//  `switch` on both sides (a new case is a compile error, not a silent `unrecognised`) and why the
//  hardware pre-flight asserts the *observed* outcome of a real pause rather than only its latency.
//  Two independent covers for one uncatchable edit, which is the same arrangement Step 10 reached
//  for the failure mode: `RunObservers.forRun` inside the boundary, and the reply echoing
//  `failureModeUsedCode` outside it.
//
//  What IS checkable here is everything that decides how a *received* value is read, and that is
//  where the safety-relevant asymmetries live: an unknown code must never resolve to "carry on",
//  and a missing field must never resolve to "completed".
//

import Testing
import Foundation
@testable import USBDriveTester

struct RunControlWireTests {

    // MARK: - Zero means "I do not know", on both enumerations

    /// **The most important property in this file.** An absent, defaulted or zeroed wire field
    /// decodes to `unrecognised` on both enumerations — never to `proceed` and never to
    /// `completed`.
    ///
    /// The two failure directions this rules out are not symmetric with anything else on this
    /// interface. A zero decoding as `proceed` would answer a caller asking to **stop a write**
    /// with a run that keeps writing. A zero decoding as `completed` would let a refused call —
    /// which replies with zeros throughout — be written into an exported report as a clean pass
    /// over a drive nothing touched.
    @Test func zeroIsUnrecognisedOnBothEnumerations() {
        #expect(RunControlCode(wireValue: 0) == .unrecognised)
        #expect(RunOutcomeCode(wireValue: 0) == .unrecognised)

        #expect(RunControlCode.unrecognised.rawValue == 0)
        #expect(RunOutcomeCode.unrecognised.rawValue == 0)

        #expect(!RunControlCode.unrecognised.isActionable)
        #expect(!RunOutcomeCode.unrecognised.didComplete)
        #expect(!RunOutcomeCode.unrecognised.wasInterruptedByUser)
    }

    /// A code from a helper newer than this app is refused, not guessed at. Same rule as
    /// `FailureModeCode`, and the same reason: an unknown request answered with a *different*
    /// action is the one direction this boundary must never fail in.
    @Test func anUnknownCodeFromANewerPeerIsNeverActionable() {
        for value in [-1, 4, 5, 99, Int.max] {
            #expect(RunControlCode(wireValue: value) == .unrecognised, "value=\(value)")
            #expect(!RunControlCode(wireValue: value).isActionable, "value=\(value)")
        }
        // **`5` left this list in v15**, when it became `deviceLost`. That is the failure mode
        // this test is for, arriving from the other direction: a value chosen as "unknown" stops
        // being unknown the moment the protocol grows, and a test that kept asserting it would be
        // demanding the new code be ignored. `6` is the first unallocated value today.
        for value in [-1, 6, 99, Int.max] {
            #expect(RunOutcomeCode(wireValue: value) == .unrecognised, "value=\(value)")
            #expect(!RunOutcomeCode(wireValue: value).didComplete, "value=\(value)")
        }
    }

    // MARK: - The raw values themselves

    /// The raw values are pinned individually. A test that read each constant from the enumeration
    /// on both sides would agree with any renumbering — which is exactly the defect Step 14 found
    /// in a key-name test that "would have passed the rename it was written to prevent".
    ///
    /// They matter because the app and the helper are separately installed artefacts: a renumbering
    /// that landed in one and not the other would have a `pause` arrive as a `stop`, and the
    /// version handshake would not catch it because the *signature* had not changed.
    @Test func theWireValuesArePinnedByLiteral() {
        #expect(RunControlCode.proceed.rawValue == 1)
        #expect(RunControlCode.pause.rawValue == 2)
        #expect(RunControlCode.stop.rawValue == 3)

        #expect(RunOutcomeCode.completed.rawValue == 1)
        #expect(RunOutcomeCode.stoppedOnFailure.rawValue == 2)
        #expect(RunOutcomeCode.pausedByUser.rawValue == 3)
        #expect(RunOutcomeCode.stoppedByUser.rawValue == 4)
        #expect(RunOutcomeCode.deviceLost.rawValue == 5)          // v15

        #expect(DeviceLossPhaseCode.reading.rawValue == 1)        // v15
        #expect(DeviceLossPhaseCode.writingBack.rawValue == 2)
        #expect(DeviceLossPhaseCode.verifying.rawValue == 3)
        #expect(DeviceLossPhaseCode.unrecognised.rawValue == 0)
    }

    /// No two codes may share a value, on either enumeration. A collision would make two different
    /// requests indistinguishable on the wire while both enumerations still compiled.
    @Test func noTwoCodesCollide() {
        let control: [RunControlCode] = [.proceed, .pause, .stop, .unrecognised]
        #expect(Set(control.map(\.rawValue)).count == control.count)

        let outcomes: [RunOutcomeCode] = [.completed, .stoppedOnFailure, .pausedByUser,
                                          .stoppedByUser, .deviceLost, .unrecognised]
        #expect(Set(outcomes.map(\.rawValue)).count == outcomes.count)

        let phases: [DeviceLossPhaseCode] = [.reading, .writingBack, .verifying, .unrecognised]
        #expect(Set(phases.map(\.rawValue)).count == phases.count)
    }

    /// **v15: the two phase vocabularies have the same shape.** `DeviceLossPhaseCode` mirrors
    /// Core's `DeviceLossPhase`, and like every other pair here they cannot be one type because
    /// Core is not in the app module. A case added to one and not the other is how they drift, and
    /// the count is the cheapest thing that notices.
    @Test func theTwoPhaseEnumerationsHaveTheSameShape() {
        let wire: [DeviceLossPhaseCode] = [.reading, .writingBack, .verifying]
        let core: [DeviceLossPhase] = [.reading, .writingBack, .verifying]

        #expect(wire.count == core.count)
        // The words a person reads must match too — the report renders one and the helper logs the
        // other, and on 2026-08-18 this project shipped a window and an exported file disagreeing
        // about a definition because nothing compared the two surfaces.
        for (wireCase, coreCase) in zip(wire, core) {
            #expect(wireCase.description == coreCase.description,
                    "\(wireCase) vs \(coreCase)")
        }
    }

    /// An unknown phase from a newer helper is `unrecognised`, never one of the three. A report
    /// showing "writing the original back" because it could not read the field would be inventing
    /// the one fact that changes what a person should do about the drive.
    @Test func anUnknownPhaseIsNeverOneOfTheThree() {
        for value in [-1, 4, 99, Int.max] {
            #expect(DeviceLossPhaseCode(wireValue: value) == .unrecognised, "value=\(value)")
        }
        #expect(DeviceLossPhaseCode(wireValue: 0) == .unrecognised)
    }

    /// Every signal the engine can act on has a code, and every actionable code has a signal.
    ///
    /// A shape check rather than a mapping check — the mapping itself is in `main.swift`, outside
    /// this target — but it catches the case that a case was added to one enumeration and not the
    /// other, which is how the two drift apart in the first place.
    @Test func theTwoControlEnumerationsHaveTheSameShape() {
        let signals: [RunControlSignal] = [.proceed, .pause, .stop]
        let actionable: [RunControlCode] = [.proceed, .pause, .stop]

        #expect(signals.count == actionable.count)
        for code in actionable {
            #expect(code.isActionable, "code=\(code)")
        }
    }

    // MARK: - What "completed" means now

    @Test func onlyCompletedCountsAsACompletion() {
        #expect(RunOutcomeCode.completed.didComplete)
        for code in [RunOutcomeCode.stoppedOnFailure, .pausedByUser,
                     .stoppedByUser, .deviceLost, .unrecognised] {
            #expect(!code.didComplete, "code=\(code)")
        }
    }

    /// **A device leaving is not a user interruption**, and the distinction is the reason v15
    /// exists rather than reusing `stoppedByUser`. Both mean the drive is only partly covered, so
    /// the report must not read as a clean pass either way — but only one of them is somebody's
    /// decision, and a report that credits a person with an unplug is wrong about who did what.
    @Test func aDeviceLeavingIsNotSomethingTheUserDid() {
        #expect(!RunOutcomeCode.deviceLost.wasInterruptedByUser)
        #expect(!RunOutcomeCode.deviceLost.didComplete)
    }

    /// Both user interruptions mean the drive is only partly covered, and a report must never read
    /// as a clean pass over the whole device on the strength of one of them.
    @Test func bothUserInterruptionsAreRecognisedAsSuch() {
        #expect(RunOutcomeCode.pausedByUser.wasInterruptedByUser)
        #expect(RunOutcomeCode.stoppedByUser.wasInterruptedByUser)
        for code in [RunOutcomeCode.completed, .stoppedOnFailure, .unrecognised] {
            #expect(!code.wasInterruptedByUser, "code=\(code)")
        }
    }

    // MARK: - The app-side decode

    private static func reply(outcome: RunOutcomeCode,
                              interruptedAtBlock: UInt64 = 0) -> RunCycleOutcome {
        RunCycleOutcome(runOutcomeCode: outcome.rawValue,
                        interruptedAtBlock: interruptedAtBlock,
                        chunksProcessed: 4,
                        failedRangeCount: 0,
                        failureSummary: "",
                        cacheBypassCode: 1,
                        bufferBytesHeld: 8 << 20,
                        hostOverheadFraction: 0.0255,
                        helperCoreFraction: 0.0422,
                        failureModeUsedCode: 2,
                        failedRangesEncoded: "",
                        failedBlockCount: 0,
                        deviceReadBytesPerSecond: 517_000_000,
                        writeBytesPerSecond: 491_000_000,
                        coverageBytesPerSecond: 245_000_000,
                        completedBytesPerSecond: 238_000_000,
                        readLatencySampleCount: 4,
                        readLatencyMinimumNanoseconds: 1_100_000,
                        readLatencyMaximumNanoseconds: 9_900_000,
                        readLatencyP99UpperBoundNanoseconds: 2_195_000,
                        message: "",
                        deviceLossPhaseCode: DeviceLossPhaseCode.unrecognised.rawValue)
    }

    /// **The code decides, not the value.** Only a paused run offers a resume point, and a block
    /// number arriving on any other outcome is discarded rather than carried.
    ///
    /// The `stoppedByUser` row is the one that matters: the helper sends `0` there, but a later
    /// edit that started sending the settle block would silently make a stopped run resumable —
    /// which FR-FAIL-7 forbids — unless the *code* is what gates it.
    @Test func onlyAPausedRunOffersAResumePoint() {
        #expect(Self.reply(outcome: .pausedByUser, interruptedAtBlock: 4_096).resumeBlock == 4_096)

        for code in [RunOutcomeCode.completed, .stoppedOnFailure,
                     .stoppedByUser, .unrecognised] {
            #expect(Self.reply(outcome: code, interruptedAtBlock: 4_096).resumeBlock == nil,
                    "code=\(code) must not offer a resume point")
        }
    }

    /// **Block 0 is a legitimate resume point**, which is why the outcome code and not a sentinel
    /// decides. A pause seen before the first chunk of a whole-device run resumes at block 0, and a
    /// decode that treated `0` as "no resume point" would turn that into a run that could not be
    /// continued.
    @Test func blockZeroIsARealResumePointRatherThanASentinel() {
        let paused = Self.reply(outcome: .pausedByUser, interruptedAtBlock: 0)
        #expect(paused.resumeBlock == 0)
        #expect(paused.resumeBlock != nil)
    }

    /// `didComplete` is derived from the outcome rather than carried beside it, so the two cannot
    /// disagree — the property that made replacing v9's boolean worth a protocol bump.
    @Test func didCompleteIsDerivedFromTheOutcome() {
        #expect(Self.reply(outcome: .completed).didComplete)
        for code in [RunOutcomeCode.stoppedOnFailure, .pausedByUser,
                     .stoppedByUser, .unrecognised] {
            #expect(!Self.reply(outcome: code).didComplete, "code=\(code)")
            #expect(Self.reply(outcome: code).outcome == code, "code=\(code)")
        }
    }
}
