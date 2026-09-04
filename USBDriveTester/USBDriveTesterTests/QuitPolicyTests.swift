//
//  QuitPolicyTests.swift
//  What ⌘Q and the main window's close button do while a run is active (user decision
//  2026-08-05).
//
//  Both truth tables are covered in full — two inputs, one of them a four-case enum, so "in full"
//  is eight rows each and there is no excuse for sampling. The same reasoning as
//  `MountControlStateTests`: the substance of this policy is a property of the table as a whole,
//  and a suite covering the two rows someone happened to click would let a later edit invert a
//  corner of it silently.
//
//  Three rows are load-bearing and each of them looks removable:
//
//    * **`.terminating` quits immediately even while a run reads as active.** The wind-down's own
//      `NSApp.terminate(_:)` comes back through this policy, and if it is answered "wait for the
//      boundary" the app can never quit at all. That is not hypothetical: the Step 4/5 stand-in
//      toggle leaves `runIsActive` true indefinitely, so an app that reached the boundary with the
//      toggle on would refuse its own termination forever.
//    * **`.confirming` does not ask again.** A second ⌘Q while the dialog is up would stack a
//      second copy over the first and leave the older one unanswered underneath it.
//    * **`.windingDown` does not escalate.** The decision is explicit that "Cancel and Quit" is
//      *not* an immediate kill, so a second ⌘Q must keep waiting rather than abandon the call.
//

import Testing
import Foundation
@testable import USBDriveTester

struct QuitPolicyTests {

    private static let everyState: [QuitState] = [.idle, .confirming, .windingDown, .terminating]

    // MARK: - Quitting

    @Test func anIdleAppWithNoRunQuitsImmediately() {
        #expect(QuitPolicy.disposition(runIsActive: false, quitState: .idle) == .quitImmediately)
    }

    @Test func anIdleAppWithARunAsksFirst() {
        #expect(QuitPolicy.disposition(runIsActive: true, quitState: .idle) == .askFirst)
    }

    /// The row that stops the app deadlocking against itself. Without it, an app that reached the
    /// call boundary with the run-state stand-in still on would answer every termination —
    /// including the one the wind-down just issued — with "wait", forever.
    @Test func terminatingQuitsImmediatelyEvenWhileARunLooksActive() {
        #expect(QuitPolicy.disposition(runIsActive: true, quitState: .terminating)
                == .quitImmediately)
        #expect(QuitPolicy.disposition(runIsActive: false, quitState: .terminating)
                == .quitImmediately)
    }

    /// A second ⌘Q during the wind-down keeps waiting. The decision rules out the immediate kill,
    /// and macOS already offers Force Quit for people who want one.
    @Test func aSecondQuitDuringTheWindDownDoesNotEscalate() {
        #expect(QuitPolicy.disposition(runIsActive: true, quitState: .windingDown)
                == .waitForBoundary)
    }

    @Test func aSecondQuitWhileConfirmingDoesNotStackASecondDialog() {
        #expect(QuitPolicy.disposition(runIsActive: true, quitState: .confirming)
                == .waitForBoundary)
        #expect(QuitPolicy.disposition(runIsActive: false, quitState: .confirming)
                == .waitForBoundary)
    }

    /// Exactly one state–input combination may ever put the dialog on screen. If a second one
    /// could, two entry points could each raise their own.
    @Test func askFirstIsReachableFromExactlyOneRow() {
        let asking = Self.everyState.flatMap { state in
            [true, false].compactMap { active in
                QuitPolicy.disposition(runIsActive: active, quitState: state) == .askFirst
                    ? (active, state)
                    : nil
            }
        }
        #expect(asking.count == 1)
        #expect(asking.first?.0 == true)
        #expect(asking.first?.1 == .idle)
    }

    @Test func theWholeQuitTableIsPinned() {
        let expected: [(Bool, QuitState, QuitDisposition)] = [
            (false, .idle,        .quitImmediately),
            (true,  .idle,        .askFirst),
            (false, .confirming,  .waitForBoundary),
            (true,  .confirming,  .waitForBoundary),
            (false, .windingDown, .waitForBoundary),
            (true,  .windingDown, .waitForBoundary),
            (false, .terminating, .quitImmediately),
            (true,  .terminating, .quitImmediately),
        ]
        for (active, state, want) in expected {
            #expect(QuitPolicy.disposition(runIsActive: active, quitState: state) == want,
                    "runIsActive=\(active) state=\(state)")
        }
    }

    // MARK: - Closing the main window

    /// **Closing the main window is a quit request** (user decision 2026-08-06), not merely a
    /// close. An interim version keyed this on AppKit's `applicationShouldTerminateAfterLastWindowClosed`
    /// instead, and observing it showed the problem: closing the main window quit the app or not
    /// depending on whether a panel opened earlier was still up.
    @Test func closingWhenNothingIsHappeningClosesAndQuits() {
        #expect(QuitPolicy.closeDisposition(runIsActive: false, quitState: .idle)
                == .allowCloseAndQuit)
    }

    /// `.allowClose` — close but stay — survives for exactly one state: the app is already on its
    /// way out and AppKit is taking the windows with it. Answering `.allowCloseAndQuit` there
    /// would request a second termination during the first.
    @Test func plainAllowCloseIsReachableOnlyWhileTerminating() {
        for active in [true, false] {
            for state in [QuitState.idle, .confirming, .windingDown] {
                #expect(QuitPolicy.closeDisposition(runIsActive: active, quitState: state)
                        != .allowClose,
                        "runIsActive=\(active) state=\(state) must not close-and-stay")
            }
        }
        #expect(QuitPolicy.closeDisposition(runIsActive: false, quitState: .terminating)
                == .allowClose)
    }

    /// The point of the decision: the close button asks the same question ⌘Q asks.
    @Test func closingDuringARunAsksTheSameQuestion() {
        #expect(QuitPolicy.closeDisposition(runIsActive: true, quitState: .idle) == .askFirst)
        #expect(QuitPolicy.disposition(runIsActive: true, quitState: .idle) == .askFirst)
    }

    /// AppKit closes every window as the app terminates. Refusing then would be obstructing a
    /// close the app itself asked for.
    @Test func terminatingAllowsTheWindowToClose() {
        #expect(QuitPolicy.closeDisposition(runIsActive: true, quitState: .terminating)
                == .allowClose)
    }

    /// The window carries the wind-down banner and the metrics of the call being waited on.
    @Test func windingDownKeepsTheWindow() {
        #expect(QuitPolicy.closeDisposition(runIsActive: true, quitState: .windingDown)
                == .refuseSilently)
        #expect(QuitPolicy.closeDisposition(runIsActive: false, quitState: .windingDown)
                == .refuseSilently)
    }

    @Test func theWholeCloseTableIsPinned() {
        let expected: [(Bool, QuitState, WindowCloseDisposition)] = [
            (false, .idle,        .allowCloseAndQuit),
            (true,  .idle,        .askFirst),
            (false, .confirming,  .refuseSilently),
            (true,  .confirming,  .refuseSilently),
            (false, .windingDown, .refuseSilently),
            (true,  .windingDown, .refuseSilently),
            (false, .terminating, .allowClose),
            (true,  .terminating, .allowClose),
        ]
        for (active, state, want) in expected {
            #expect(QuitPolicy.closeDisposition(runIsActive: active, quitState: state) == want,
                    "runIsActive=\(active) state=\(state)")
        }
    }

    /// Neither table may ever leave a window closable *and* the app quitting on the same input —
    /// the window would vanish while a privileged write finished behind it.
    @Test func aCloseIsNeverAllowedWhileAQuitIsPending() {
        for state in [QuitState.confirming, .windingDown] {
            for active in [true, false] {
                let disposition = QuitPolicy.closeDisposition(runIsActive: active,
                                                              quitState: state)
                #expect(disposition != .allowClose)
                #expect(disposition != .allowCloseAndQuit,
                        "and it must not close-and-quit either — same hazard, new case")
            }
        }
    }
}

/// The third truth table: what ⌘Q does about whatever modal is on screen (increment 12).
///
/// Nothing here touches AppKit or a view. What is being pinned is the **decision** — which is the
/// whole reason it is a pure type: `AppModelReportTests` already records that four mutations to
/// `RunReportView` passed the entire suite, and every one of this app's five modal surfaces is
/// equally unreachable by a test. A rule that lived in the presentation layer would be a rule
/// nothing could check.
struct ModalQuitPolicyTests {

    // MARK: - The table

    @Test func nothingOnScreenAsksForTheTerminationUnchanged() {
        #expect(QuitPolicy.disposition(underModals: []) == .requestTermination)
    }

    /// The two a quit may discard, named individually rather than as a group, so that a change to
    /// either is a failing test with the surface's name on it.
    @Test func theLaunchGateIsDiscarded() {
        #expect(QuitPolicy.disposition(underModals: [.helperGate]) == .dismiss(.helperGate))
    }

    /// **Chunk 11.7 left this open deliberately** — *"whether the report ought to block quitting is
    /// a separate question, deliberately left open until this has been seen"* — and it was seen on
    /// 2026-08-22, blocking. Settled the other way on 2026-09-04: a report is a document somebody
    /// has finished reading, nothing is claimed while it is up, and the run guard still gets its
    /// vote a moment later.
    @Test func theReportIsDiscarded() {
        #expect(QuitPolicy.disposition(underModals: [.runReport]) == .dismiss(.runReport))
    }

    /// **The 2026-08-18 decision stands.** `RunControlsView` records it: the pre-run sheet is the
    /// last thing between a selected drive and a write, and a keystroke that means "leave" must not
    /// answer a question about writing. What this increment changes is that the refusal stops being
    /// silent, not that it stops being a refusal.
    @Test func thePreRunPromptIsRefused() {
        let disposition = QuitPolicy.disposition(underModals: [.preRunPrompt])
        guard case .refuse = disposition else {
            Issue.record("the pre-run prompt must refuse, got \(disposition)")
            return
        }
    }

    @Test func theFailureAlertIsRefused() {
        let disposition = QuitPolicy.disposition(underModals: [.runFailure])
        guard case .refuse = disposition else {
            Issue.record("the failure alert must refuse, got \(disposition)")
            return
        }
    }

    /// And the confirmation, where dismissing to re-terminate would put the same question back on
    /// screen. `disposition(runIsActive:quitState:)` already answers `.waitForBoundary` in
    /// `.confirming`; the two tables agree here without either consulting the other.
    @Test func theQuitConfirmationIsRefused() {
        let disposition = QuitPolicy.disposition(underModals: [.quitConfirmation])
        guard case .refuse = disposition else {
            Issue.record("the quit confirmation must refuse, got \(disposition)")
            return
        }
        #expect(QuitPolicy.disposition(runIsActive: true, quitState: .confirming)
                == .waitForBoundary)
    }

    /// **Every case is answered**, walked from `allCases` rather than from a list written here —
    /// which is what makes a sixth modal show up as a failure instead of being quietly skipped.
    /// The exhaustive `switch` is the other half; this is the half that catches a case added to the
    /// enum and answered by a `default` somebody reached for.
    @Test func everyModalIsAnswered() {
        for modal in AppModal.allCases {
            let disposition = QuitPolicy.disposition(underModals: [modal])
            #expect(disposition != .requestTermination,
                    "\(modal) must not be treated as nothing being on screen")
        }
    }

    // MARK: - The refusals are sentences

    /// **A refusal that cannot be read is the defect wearing a fix's clothes.** The whole of this
    /// increment is that ⌘Q stopped failing *silently*, so every reason must be a sentence that
    /// says what to do about it — the shape `RunControlPolicy` uses, for the same reason.
    ///
    /// The whole table is walked rather than a case picked, because a refusal added later with an
    /// empty reason is exactly the mutation this exists to catch.
    @Test func everyRefusalInTheWholeTableIsASentence() {
        var refusals: [String] = []
        for modal in AppModal.allCases {
            if case .refuse(let reason) = QuitPolicy.disposition(underModals: [modal]) {
                refusals.append(reason)
            }
        }
        if case .refuse(let reason) = QuitPolicy.disposition(underModals: Set(AppModal.allCases)) {
            refusals.append(reason)
        }

        #expect(refusals.count == 4, "three single-modal refusals and the ambiguous one")
        for reason in refusals {
            #expect(reason.hasSuffix("."), "not a sentence: \(reason)")
            #expect(reason.count > 20, "too short to say anything: \(reason)")
            #expect(reason.first?.isUppercase == true, "does not begin a sentence: \(reason)")
        }
    }

    // MARK: - More than one flagged

    /// **The property the precedence exists to guarantee, walked over all 32 subsets.**
    ///
    /// `dismiss` is produced only when exactly one modal is flagged. The model cannot see SwiftUI's
    /// presentation queue — a run finishing under the quit confirmation raises the report behind it
    /// and SwiftUI queues it (measured 2026-08-21) — so with two flagged, taking down the one that
    /// is not visible leaves the other attached and the termination refused with nothing to show
    /// for it. That is the original defect rebuilt by its own fix, and this is what rules it out.
    @Test func everyAmbiguousSetIsRefused() {
        let all = AppModal.allCases
        for bits in 0..<(1 << all.count) {
            let subset = Set(all.enumerated().compactMap { index, modal in
                bits & (1 << index) != 0 ? modal : nil
            })
            let disposition = QuitPolicy.disposition(underModals: subset)

            if case .dismiss = disposition {
                #expect(subset.count == 1,
                        "dismiss was produced for \(subset.count) modals: \(subset)")
            }
            if subset.count > 1 {
                guard case .refuse = disposition else {
                    Issue.record("\(subset) is ambiguous and must refuse, got \(disposition)")
                    continue
                }
            }
        }
    }

    /// And the sentence an ambiguous set gets is the ambiguous one, not one surface's — naming a
    /// single dialog when two are open would send someone to the wrong window.
    @Test func anAmbiguousSetSaysMoreThanOneRatherThanNamingOne() {
        guard case .refuse(let reason) =
                QuitPolicy.disposition(underModals: [.runReport, .quitConfirmation]) else {
            Issue.record("two modals must refuse")
            return
        }
        #expect(reason.contains("More than one"))
    }

    // MARK: - Precedence, pinned by consequence rather than by reading the order back

    /// The confirmation outranks a report raised underneath it. **This pair is reachable**: a run
    /// finishing while the confirmation is up calls `runProduced(_:)` from `finishing`, which sets
    /// `reportIsPresented` with the alert still on screen.
    @Test func theQuitConfirmationOutranksAReportRaisedUnderneathIt() {
        #expect(AppModal.topmost(of: [.runReport, .quitConfirmation]) == .quitConfirmation)
    }

    /// And the gate outranks the surfaces behind it: while it is up the app is unusable, so
    /// anything else flagged is stale rather than current.
    @Test func theHelperGateOutranksTheRunSurfaces() {
        #expect(AppModal.topmost(of: [.runReport, .preRunPrompt, .helperGate]) == .helperGate)
    }

    @Test func nothingPresentedHasNoTopmost() {
        #expect(AppModal.topmost(of: []) == nil)
    }

    // MARK: - The two tables compose

    /// **The report goes, and the run guard still gets its vote.**
    ///
    /// `runProduced(_:)` is called from `finishing`, which `RunControlState.isRunActive` counts as
    /// active — so there is a real window in which the report is on screen *and* a quit must still
    /// ask. Answering both from one table would make one of them lie; answering them from two is
    /// what lets the sheet be discarded and the question still be put.
    @Test func discardingTheReportStillLeavesTheRunGuardToAsk() {
        #expect(QuitPolicy.disposition(underModals: [.runReport]) == .dismiss(.runReport))
        #expect(QuitPolicy.disposition(runIsActive: true, quitState: .idle) == .askFirst)
    }

    /// And with nothing on screen the two together are exactly today's behaviour, which is the
    /// regression this increment must not cause.
    @Test func nothingOnScreenAndNoRunIsStillAnImmediateQuit() {
        #expect(QuitPolicy.disposition(underModals: []) == .requestTermination)
        #expect(QuitPolicy.disposition(runIsActive: false, quitState: .idle) == .quitImmediately)
    }
}
