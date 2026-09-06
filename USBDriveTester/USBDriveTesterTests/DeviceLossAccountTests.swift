//
//  DeviceLossAccountTests.swift
//  USBDriveTesterTests
//
//  Step 12, chunk 5. What the report may claim about a drive that left.
//
//  The property under test throughout is **conservatism in one direction only**: this type is
//  allowed to say "a write-back may be unfinished" when it is not, and is never allowed to say a
//  chunk is safe unless a route said so. Half of the tests below exist to pin which cases have
//  earned the reassuring answer, because that is the half where being wrong costs somebody data.
//

import Testing
import Foundation
@testable import USBDriveTester

@Suite("Device-loss account (Step 12, FR-DEV-8)")
struct DeviceLossAccountTests {

    // MARK: Which route the account comes from

    /// Every ending that is not a device loss has no account at all — `nil`, not an empty case.
    ///
    /// Walked over the endings rather than listed, so an ending added later arrives here rather
    /// than quietly defaulting to "no device loss" in a list nobody updated.
    @Test func onlyADeviceLossHasAnAccount() {
        let endings: [RunSequenceOutcome] = [.completed, .stoppedOnFailure, .stoppedByUser,
                                             .haltedForQuit, .callFailed(reason: "refused")]
        for ending in endings {
            #expect(DeviceLossAccount.forRun(endedBy: ending,
                                             lostAtBlock: 4096,
                                             phase: .writingBack,
                                             removalCallbackSaid: .theHelperNeverAnswered) == nil,
                    "\(ending) produced a device-loss account")
        }
    }

    /// **Route (a) wins where it spoke**, and it wins *over* the removal callback rather than
    /// merely in its absence.
    ///
    /// That ordering is the whole reason chunk 4's wind-down waits three seconds instead of ending
    /// the run on the callback: the reply is normally milliseconds behind, and it is the only thing
    /// that knows the block and the phase. A `forRun` that consulted the callback first would throw
    /// that away on every ordinary unplug while still passing every other test in this file.
    @Test func theHelpersOwnReplyOutranksTheRemovalCallback() {
        let account = DeviceLossAccount.forRun(endedBy: .deviceLost,
                                               lostAtBlock: 1_048_576,
                                               phase: .verifying,
                                               removalCallbackSaid: .theHelperNeverAnswered)

        #expect(account == .theHelperSaidWhere(block: 1_048_576, phase: .verifying))
    }

    @Test func aPausedRunTakesTheRemovalCallbacksAnswer() {
        let account = DeviceLossAccount.forRun(endedBy: .deviceLost,
                                               lostAtBlock: nil,
                                               phase: nil,
                                               removalCallbackSaid: .nothingWasInFlight)

        #expect(account == .nothingWasInFlight)
    }

    @Test func anUnansweredCallTakesTheRemovalCallbacksOtherAnswer() {
        let account = DeviceLossAccount.forRun(endedBy: .deviceLost,
                                               lostAtBlock: nil,
                                               phase: nil,
                                               removalCallbackSaid: .theHelperNeverAnswered)

        #expect(account == .theHelperNeverAnswered)
    }

    /// The contradiction: a run ended because the device was gone, and neither route says so.
    ///
    /// `RunController` cannot produce this — it sets the callback's ending before asking the
    /// sequencer to end the run, and route (a) cannot reach the outcome without a reply. It is
    /// reachable **here**, because `forRun` is a pure function, and that is the entire argument for
    /// naming the case rather than force-unwrapping or folding it silently into the case beside it.
    @Test func aDeviceLossNoRouteAccountedForIsNamedRatherThanGuessedAt() {
        let account = DeviceLossAccount.forRun(endedBy: .deviceLost,
                                               lostAtBlock: nil,
                                               phase: nil,
                                               removalCallbackSaid: nil)

        #expect(account == .noRouteSaidAnything)
        #expect(account?.aWriteBackMayBeUnfinished == true, "a report that knows nothing claimed safety")
        #expect(account?.block == nil)
        #expect(account?.namedPhase == nil)
    }

    /// Half of route (a) is not better than none of it.
    ///
    /// `HelperConnection` sets `deviceLostAtBlock` and `deviceLossPhase` together from one outcome
    /// code, so one without the other is a wiring defect. Taking the half that arrived would print
    /// a block with no phase — or, worse, a phase with no block — under a heading that implies the
    /// helper accounted for the loss.
    @Test func halfOfRouteAsAnswerIsTreatedAsNoneOfIt() {
        let blockOnly = DeviceLossAccount.forRun(endedBy: .deviceLost,
                                                 lostAtBlock: 4096,
                                                 phase: nil,
                                                 removalCallbackSaid: .nothingWasInFlight)
        #expect(blockOnly == .nothingWasInFlight)

        let phaseOnly = DeviceLossAccount.forRun(endedBy: .deviceLost,
                                                 lostAtBlock: nil,
                                                 phase: .reading,
                                                 removalCallbackSaid: .nothingWasInFlight)
        #expect(phaseOnly == .nothingWasInFlight)
    }

    /// Block 0 is a real block, and this is the reading that a sentinel would destroy.
    @Test func blockZeroIsABlockAndNotAnAbsentOne() {
        let account = DeviceLossAccount.forRun(endedBy: .deviceLost,
                                               lostAtBlock: 0,
                                               phase: .reading,
                                               removalCallbackSaid: nil)

        #expect(account == .theHelperSaidWhere(block: 0, phase: .reading))
        #expect(account?.block == 0)
        #expect(account?.blockDescription == "block 0")
    }

    // MARK: The safety question

    /// **The table this type exists for.** Every case, and whether it leaves a part-written chunk
    /// open.
    ///
    /// Written as data rather than as six assertions so the shape is visible: exactly three cases
    /// say "no", and each of them has a reason it earned that. Anything else answers "yes".
    @Test func theWriteBackTableIsPinned() {
        let expected: [(DeviceLossAccount, Bool)] = [
            // Route (a). Nothing had been written yet.
            (.theHelperSaidWhere(block: 8, phase: .reading), false),
            // Route (a). The one phase that was mid-write.
            (.theHelperSaidWhere(block: 8, phase: .writingBack), true),
            // Route (a). The write-back had already reported success, so the chunk was whole.
            (.theHelperSaidWhere(block: 8, phase: .verifying), false),
            // Route (a), from a helper newer than this app. Never read as success.
            (.theHelperSaidWhere(block: 8, phase: .unrecognised), true),
            // Route (b). A paused run has nothing outstanding — the only reassuring route-(b) case.
            (.nothingWasInFlight, false),
            // Route (b). A call was in flight and its phase is unknown.
            (.theHelperNeverAnswered, true),
            // Neither route.
            (.noRouteSaidAnything, true),
        ]

        for (account, mayBeUnfinished) in expected {
            #expect(account.aWriteBackMayBeUnfinished == mayBeUnfinished,
                    "\(account) answered \(account.aWriteBackMayBeUnfinished)")
        }
    }

    /// A phase this build cannot name is never printed, and the absence is total: no phase row, and
    /// the conservative safety answer. The two must move together — a report that hid the phase but
    /// kept the reassuring answer would be the worst of both.
    @Test func aPhaseThisBuildCannotNameIsNeitherPrintedNorTrusted() {
        let account = DeviceLossAccount.theHelperSaidWhere(block: 512, phase: .unrecognised)

        #expect(account.namedPhase == nil, "a phase this build cannot map was printed")
        #expect(account.aWriteBackMayBeUnfinished, "an unrecognised phase was read as safe")
        #expect(account.block == 512, "the block is known even where the phase is not")
    }

    /// The three phases this build knows are all printable, and **each reads differently from the
    /// other two**.
    ///
    /// Distinctness rather than non-emptiness, because non-emptiness is what a placeholder passes.
    /// The report prints this string in the row under the sentence, and three phases that render
    /// the same word would put a reader in front of a document that names a phase and tells them
    /// nothing — the failure being tested for is a collision, not a blank.
    @Test func theThreeKnownPhasesEachReadDifferently() {
        let phases: [DeviceLossPhaseCode] = [.reading, .writingBack, .verifying]
        var descriptions: Set<String> = []

        for phase in phases {
            let account = DeviceLossAccount.theHelperSaidWhere(block: 1, phase: phase)
            #expect(account.namedPhase == phase)
            descriptions.insert(account.namedPhase?.description ?? "")
        }

        #expect(descriptions.count == phases.count, "two phases render the same words")
        #expect(!descriptions.contains(""), "a phase rendered nothing")
    }

    /// No route-(b) case has a block, and none of them may invent one.
    @Test func aRouteBAccountHasNoBlockToPrint() {
        for account: DeviceLossAccount in [.nothingWasInFlight, .theHelperNeverAnswered,
                                           .noRouteSaidAnything] {
            #expect(account.block == nil, "\(account) produced a block")
            #expect(account.blockDescription == nil, "\(account) produced a block description")
            #expect(account.namedPhase == nil, "\(account) produced a phase")
        }
    }
}
