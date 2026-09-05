//
//  DeviceLossWireTests.swift
//  Step 12, chunk 3 — protocol v15: a run can end because the device went away.
//
//  ## The one property worth writing a file for
//
//  `interruptedAtBlock` carries two different things depending on the outcome code, and they say
//  **opposite** things about what may happen next. Under `pausedByUser` it is a resume point: the
//  run settled at a chunk boundary with nothing in flight, and starting again from that block is
//  correct. Under `deviceLost` it is where the run died *inside* a chunk, nothing settled, and
//  FR-FAIL-7 forbids continuing across it at all.
//
//  Sharing the slot is right — it is the same quantity, *where the run stopped* — but a single
//  app-side optional meaning either would be one field stating two facts, which is a shape this
//  project has a lesson about. So `RunCycleOutcome` splits it into `resumeBlock` and
//  `deviceLostAtBlock`, and the tests below assert the thing that makes the split worth having:
//  **the two are never both non-nil**, whatever arrives on the wire.
//
//  ## What this cannot check
//
//  The outward mapping — Core's `RunOutcome.deviceLost` becoming this code, and `DeviceLossPhase`
//  becoming `DeviceLossPhaseCode` — lives in the helper's `main.swift`, which the test target does
//  not compile. Same boundary `RunControlWireTests` states for `outcomeCode(_:)`, and the same two
//  covers: both mappings are exhaustive `switch`es, so a new case is a compile error rather than a
//  silent `unrecognised`, and Step 12's hardware gate reads the phase off a real unplug.
//

import Testing
import Foundation
@testable import USBDriveTester

private func reply(_ code: RunOutcomeCode,
                   atBlock block: UInt64 = 0,
                   phase: DeviceLossPhaseCode = .unrecognised) -> RunCycleOutcome {
    RunCycleOutcome(runOutcomeCode: code.rawValue,
                    interruptedAtBlock: block,
                    chunksProcessed: 12,
                    failedRangeCount: 0,
                    failureSummary: "",
                    cacheBypassCode: CacheBypassOutcome.bypassed.rawValue,
                    bufferBytesHeld: 8 << 20,
                    hostOverheadFraction: -1,
                    helperCoreFraction: -1,
                    failureModeUsedCode: FailureModeCode.logAndContinue.rawValue,
                    failedRangesEncoded: "",
                    failedBlockCount: 0,
                    deviceReadBytesPerSecond: -1,
                    writeBytesPerSecond: -1,
                    coverageBytesPerSecond: -1,
                    completedBytesPerSecond: -1,
                    readLatencySampleCount: 0,
                    readLatencyMinimumNanoseconds: 0,
                    readLatencyMaximumNanoseconds: 0,
                    readLatencyP99UpperBoundNanoseconds: 0,
                    message: "",
                    deviceLossPhaseCode: phase.rawValue)
}

struct DeviceLossWireDecodeTests {

    /// **The separation, stated as the property that must hold.** One wire slot, two readings, and
    /// never both at once — for every ending, including the ones that send `0` in that slot.
    @Test func theBlockIsNeverBothAResumePointAndADeviceLoss() {
        let codes: [RunOutcomeCode] = [.completed, .stoppedOnFailure, .pausedByUser,
                                       .stoppedByUser, .deviceLost, .unrecognised]
        for code in codes {
            for block: UInt64 in [0, 4_096, 1_953_525_168] {
                let decoded = reply(code, atBlock: block)
                #expect(decoded.resumeBlock == nil || decoded.deviceLostAtBlock == nil,
                        "code=\(code) block=\(block)")
            }
        }
    }

    /// A device loss reports where it died and offers no resume point — the value that would let
    /// somebody continue does not exist rather than existing and being ignored (FR-FAIL-7).
    @Test func aDeviceLossCarriesItsBlockAndNoResumePoint() {
        let decoded = reply(.deviceLost, atBlock: 4_096, phase: .writingBack)

        #expect(decoded.deviceLostAtBlock == 4_096)
        #expect(decoded.resumeBlock == nil)
        #expect(!decoded.didComplete)
    }

    /// And the other way round: a pause is still a resume point and is not a device loss.
    @Test func aPauseCarriesAResumePointAndNoDeviceLoss() {
        let decoded = reply(.pausedByUser, atBlock: 4_096)

        #expect(decoded.resumeBlock == 4_096)
        #expect(decoded.deviceLostAtBlock == nil)
        #expect(decoded.deviceLossPhase == nil)
    }

    /// **Block 0 is a legitimate value for both**, which is why the code is the discriminator and
    /// no sentinel could do this job. A device lost at the very first chunk — the 2026-08-06 shape,
    /// `ENXIO` at offset 0 — must decode as a real block, not as "no block".
    @Test func blockZeroIsARealAnswerForEitherReading() {
        let lost = reply(.deviceLost, atBlock: 0, phase: .reading)
        #expect(lost.deviceLostAtBlock == 0)
        #expect(lost.resumeBlock == nil)

        let paused = reply(.pausedByUser, atBlock: 0)
        #expect(paused.resumeBlock == 0)
        #expect(paused.deviceLostAtBlock == nil)
    }

    @Test func thePhaseDecodesUnderADeviceLossAndNowhereElse() {
        for phase in [DeviceLossPhaseCode.reading, .writingBack, .verifying] {
            #expect(reply(.deviceLost, phase: phase).deviceLossPhase == phase, "phase=\(phase)")
        }

        // Every other ending sends `unrecognised` in that slot, and the app reports **no phase**
        // rather than an unrecognised one: the absence of a device loss and an unreadable phase
        // are different facts, and only one of them is worth a reader's attention.
        for code in [RunOutcomeCode.completed, .stoppedOnFailure, .pausedByUser,
                     .stoppedByUser, .unrecognised] {
            #expect(reply(code, phase: .writingBack).deviceLossPhase == nil, "code=\(code)")
        }
    }

    /// A phase this build cannot name stays `unrecognised` — distinguishable from "no loss
    /// happened", which is `nil`. A helper newer than this app is the case that produces it.
    @Test func anUnreadablePhaseIsDistinguishableFromNoLossAtAll() {
        let unknown = RunCycleOutcome(runOutcomeCode: RunOutcomeCode.deviceLost.rawValue,
                                      interruptedAtBlock: 8,
                                      chunksProcessed: 1,
                                      failedRangeCount: 0,
                                      failureSummary: "",
                                      cacheBypassCode: CacheBypassOutcome.bypassed.rawValue,
                                      bufferBytesHeld: 0,
                                      hostOverheadFraction: -1,
                                      helperCoreFraction: -1,
                                      failureModeUsedCode: FailureModeCode.logAndContinue.rawValue,
                                      failedRangesEncoded: "",
                                      failedBlockCount: 0,
                                      deviceReadBytesPerSecond: -1,
                                      writeBytesPerSecond: -1,
                                      coverageBytesPerSecond: -1,
                                      completedBytesPerSecond: -1,
                                      readLatencySampleCount: 0,
                                      readLatencyMinimumNanoseconds: 0,
                                      readLatencyMaximumNanoseconds: 0,
                                      readLatencyP99UpperBoundNanoseconds: 0,
                                      message: "",
                                      deviceLossPhaseCode: 99)

        #expect(unknown.deviceLossPhase == .unrecognised)
        #expect(unknown.deviceLossPhase != nil, "a loss did happen; only its phase is unreadable")
        #expect(unknown.deviceLostAtBlock == 8)
    }

    /// **Nothing is recorded against the drive.** The engine records no failed range for an absent
    /// device (chunk 1), so a device-loss reply arrives with an empty list — and the decode must
    /// not manufacture one. This is the assertion that would fail if the two million bad blocks
    /// ever came back by another route.
    @Test func aDeviceLossReplyAccusesTheDriveOfNothing() {
        let decoded = reply(.deviceLost, atBlock: 512, phase: .verifying)

        #expect(decoded.failedRangeCount == 0)
        #expect(decoded.failedBlockCount == 0)
        #expect(decoded.failedRanges?.isEmpty == true)
        #expect(!decoded.listIsTruncated)
    }
}
