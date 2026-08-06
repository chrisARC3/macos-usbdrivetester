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

    @Test func closingIsAllowedWhenNothingIsHappening() {
        #expect(QuitPolicy.closeDisposition(runIsActive: false, quitState: .idle) == .allowClose)
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
            (false, .idle,        .allowClose),
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
                #expect(QuitPolicy.closeDisposition(runIsActive: active, quitState: state)
                        != .allowClose)
            }
        }
    }
}
