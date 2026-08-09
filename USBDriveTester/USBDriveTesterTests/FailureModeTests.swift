//
//  FailureModeTests.swift
//  FR-FAIL-1/2/3/4 — the two failure-handling modes, and what each does about each kind of
//  failure. Step 10, increment 1.
//
//  Nothing calls `FailureMode` yet: increment 2 puts it behind the engine's observer and
//  increment 3 puts it on the wire. This suite exists first because the mode is a **safety**
//  decision — it is what decides whether a run keeps writing to a drive that has already failed
//  — and the two requirements it has to satisfy together are not obvious from either alone.
//
//  ## The conjunction this suite exists to pin
//
//  FR-FAIL-2 says stop-on-first-error halts on "any I/O failure". FR-TEST-8 and FR-FAIL-6 make a
//  **verify mismatch** a block-range failure, and it is not an I/O failure in the ordinary sense
//  — the read succeeded, the write succeeded, and the drive handed back different bytes. Read
//  narrowly, FR-FAIL-2 would let a mismatch continue in a mode whose whole promise is that it
//  stops. So `dispositionsAreCoveredForEveryModeAndKind` walks the full 2 x 3 table rather than
//  sampling it, and the mismatch rows are the ones that matter.
//
//  ## And the one that must NOT be defaulted
//
//  `FailureModeCode` has an `unrecognised` case and `FailureMode` deliberately does not. An
//  unknown code arriving over XPC has to be representable so it can be **refused** (NFR-REL-7);
//  resolving it to FR-FAIL-4's default would answer "stop on the first error" with a run that
//  writes to the whole drive — a request silently met by a larger action. There is no way to
//  build a `FailureMode` from an unrecognised code, and `noWireCodeCollidesWithUnrecognised`
//  plus `unknownWireCodeDoesNotBecomeAMode` are what keep it that way.
//

import Testing
import Foundation
@testable import USBDriveTester

struct FailureModeTests {

    // MARK: - What each mode does about each kind of failure

    /// The full 2 x 3 table. Sampling it would leave exactly the interesting corner uncovered.
    @Test func dispositionsAreCoveredForEveryModeAndKind() {
        let kinds: [BlockFailureKind] = [.readError, .writeError, .verifyMismatch]

        for kind in kinds {
            #expect(FailureMode.logAndContinue.disposition(for: kind) == .continueRun,
                    "log-and-continue must never stop")
            #expect(FailureMode.stopOnFirstError.disposition(for: kind) == .stopRun,
                    "stop-on-first-error must stop on every kind")
        }

        // The table is only "full" if these are all the kinds there are. A fourth case added
        // later must fail here rather than acquire a disposition by falling through a `switch`.
        #expect(kinds.count == 3)
    }

    /// FR-TEST-8 read together with FR-FAIL-2, stated on its own because it is the row a narrow
    /// reading of "any I/O failure" would get wrong. A drive that accepts a write and returns
    /// different bytes has failed at the one thing this tool checks.
    @Test func aVerifyMismatchStopsARunInStopOnFirstErrorMode() {
        #expect(FailureMode.stopOnFirstError.disposition(for: .verifyMismatch) == .stopRun)
    }

    /// FR-FAIL-3: the mode's entire point is that it survives a failure.
    @Test func logAndContinueSurvivesAVerifyMismatch() {
        #expect(FailureMode.logAndContinue.disposition(for: .verifyMismatch) == .continueRun)
    }

    // MARK: - The default (FR-FAIL-4)

    @Test func theDefaultModeIsLogAndContinue() {
        #expect(FailureMode.standard == .logAndContinue)
        #expect(FailureModeCode.standard == .logAndContinue)
    }

    /// The two sides of the boundary must agree about the default, or a caller that omits a mode
    /// and a helper that supplies one would disagree about what the run did.
    @Test func bothSidesAgreeOnTheDefault() {
        #expect(FailureMode.standard.wireCode == FailureModeCode.standard.rawValue)
    }

    // MARK: - The wire mirror

    /// `FailureMode` compiles into the test target from Core's source, `FailureModeCode` through
    /// the `@testable import`. They are separate types for the reason recorded on each: Core
    /// deliberately does not compile into the app module. **This is the only place both are
    /// visible at once**, so it is the only place the mapping can be pinned.
    @Test func wireCodesMatchTheWireEnum() {
        let pairs: [(FailureMode, FailureModeCode)] = [
            (.stopOnFirstError, .stopOnFirstError),
            (.logAndContinue, .logAndContinue),
        ]

        for (mode, wire) in pairs {
            #expect(mode.wireCode == wire.rawValue)
            #expect(FailureModeCode(wireValue: mode.wireCode) == wire)
        }

        // Every mode is covered. A third mode added to Core without a wire code would otherwise
        // travel as whatever `rawValue` a `default:` produced.
        #expect(pairs.count == FailureMode.allCases.count)
    }

    /// A helper newer than this app, or an app newer than the helper, must not have an unknown
    /// mode read as a runnable one.
    @Test func unknownWireCodeDoesNotBecomeAMode() {
        for value in [-1, 0, 3, 99, Int.max, Int.min] {
            #expect(FailureModeCode(wireValue: value) == .unrecognised,
                    "\(value) must not resolve to a runnable mode")
            #expect(FailureModeCode(wireValue: value).isRunnable == false)
        }
    }

    /// No real mode may carry the "not a mode" code, or a valid request would be refused.
    @Test func noWireCodeCollidesWithUnrecognised() {
        for mode in FailureMode.allCases {
            #expect(mode.wireCode != FailureModeCode.unrecognised.rawValue)
        }
    }

    @Test func bothRealCodesAreRunnable() {
        #expect(FailureModeCode.stopOnFirstError.isRunnable)
        #expect(FailureModeCode.logAndContinue.isRunnable)
    }

    // MARK: - How the mode is named

    /// The report and the log both print this, and it is what a reader will go looking for in
    /// the UI. Matching FR-FAIL-1's own wording means the three places agree.
    @Test func modesAreNamedAsTheRequirementNamesThem() {
        #expect(FailureMode.stopOnFirstError.reportName == "Stop on first error")
        #expect(FailureMode.logAndContinue.reportName == "Log and continue")
    }

    /// One name, not two. A mode that logs under one string and reports under another is two
    /// facts that can drift.
    @Test func theDescriptionIsTheReportName() {
        for mode in FailureMode.allCases {
            #expect(mode.description == mode.reportName)
        }
    }

    @Test func theTwoModesAreNamedDifferently() {
        #expect(FailureMode.stopOnFirstError.reportName != FailureMode.logAndContinue.reportName)
    }
}
