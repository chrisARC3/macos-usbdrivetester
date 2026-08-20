//
//  PreRunControlsTests.swift
//  The two pre-run controls (Step 11, increment 6). FR-CTRL-7, FR-CTRL-8, FR-FAIL-1/4.
//
//  **The table is covered in full**, for the reason `RunControlPolicyTests` gives at length: the
//  substance of "chosen before a run and fixed for the whole of it" is a property of the table *as
//  a whole*, not a claim about the states somebody happened to click, so a suite that covered the
//  interesting-looking rows would let a later edit invert a corner of it silently.
//
//  Three properties here look removable and are not:
//
//    * **`paused` is on the DEAD side.** It is the row a reader is most likely to think is a
//      mistake — FR-CTRL-8 read *"or while a run is paused"* from 2026-08-04 until the controls
//      were seen, paused, on real hardware and the requirement was reversed (2026-08-19).
//    * **The derivation from `isRunActive` is pinned, not trusted.** `PreRunControls` delegates to
//      that property on purpose; this suite is what stops the delegation being silently wrong.
//    * **Every refusal is a sentence, walked over the whole table** rather than over the controls a
//      view happens to render. Increment 1's mutation M9 blanked a disabled reason and passed all
//      827 tests precisely because the check walked the rendered surface; the fix was to walk the
//      table, and this suite is written that way from the start.
//

import Testing
import Foundation
@testable import USBDriveTester

// MARK: - When the pre-run controls are live (FR-CTRL-7, FR-CTRL-8, FR-FAIL-1)

struct PreRunControlTableTests {

    /// **One rule for both controls**: live before a run and once one has finished, dead for the
    /// whole of a run.
    ///
    /// `finished` is FR-CTRL-8's "stopped": `RunControlState` has one terminal state rather than
    /// three, because all three enable the same controls and differ only by an outcome the report
    /// is authoritative for.
    @Test func theControlsAreLiveInExactlyTwoStates() {
        let live = RunControlState.allCases.filter { PreRunControls.availability(in: $0).isEnabled }
        #expect(live == [.idle, .finished])
    }

    /// **`paused` is on the dead side, and that is the reversal of 2026-08-19.** Asserted on its
    /// own rather than left to the set above, because it is the one row a reader is most likely to
    /// think is a mistake: FR-CTRL-8 said *"or while a run is paused"* from 2026-08-04 until the
    /// controls were looked at, paused, on real hardware.
    @Test func thePreRunControlsAreDeadWhilePausedToo() {
        #expect(!PreRunControls.availability(in: .paused).isEnabled)
    }

    /// The derivation from `isRunActive` is **pinned, not trusted**. `PreRunControls` delegates to
    /// that property deliberately — the controls freezing is the same fact as the device list
    /// freezing — and this is what stops the delegation being silently wrong for some state.
    @Test func theControlsAreLiveExactlyWhenNoRunIsActive() {
        for state in RunControlState.allCases {
            #expect(PreRunControls.availability(in: state).isEnabled == !state.isRunActive,
                    "state=\(state)")
        }
    }

    /// **Dimming is not a message** (NFR-USE-8), walked over the whole table rather than over the
    /// controls a view happens to render. Increment 1's mutation M9 blanked a disabled reason and
    /// passed all 827 tests precisely because the check walked the rendered surface.
    @Test func everyRefusalInTheWholeTableIsASentence() {
        for state in RunControlState.allCases {
            guard let reason = PreRunControls.availability(in: state).disabledReason else { continue }
            #expect(reason.count >= 20, "state=\(state) reason=\(reason)")
            #expect(reason.hasSuffix("."), "state=\(state) reason=\(reason)")
        }
    }

    /// An enabled control never carries a reason, and a disabled one always does — the invariant
    /// `RunControlAvailability` is documented to hold *"without exception"*.
    @Test func aReasonIsPresentExactlyWhenTheControlsAreDisabled() {
        for state in RunControlState.allCases {
            let availability = PreRunControls.availability(in: state)
            #expect(availability.isEnabled == (availability.disabledReason == nil))
        }
    }

    /// The one sentence has to speak for **both** controls, since it is all a user gets when either
    /// is dimmed. A reason naming only the I/O size would leave the failure-mode picker unexplained.
    @Test func theOneReasonNamesBothControls() {
        guard let reason = PreRunControls.availability(in: .running).disabledReason else {
            Issue.record("a disabled control must say why")
            return
        }
        // Substrings, so the sentence can be reworded without the check going quiet. They track
        // the wording rather than pinning it: increment 7 shortened this sentence by 15 pt of
        // wrapped height to fit a 13.3-inch Mac at its smallest scaling, and what had to survive
        // that edit is exactly what is asserted here — both controls named, and a way out given.
        #expect(reason.contains("I/O size"))
        #expect(reason.contains("failure handling"))
        // Case-insensitive: the corrective step is what matters, not whether the sentence happens
        // to open with it. It reads "stop it to change them" now and "Stop this run" before.
        #expect(reason.lowercased().contains("stop"),
                "a refusal names the corrective step (NFR-USE-5)")
    }
}

// MARK: - Rendering a size

struct IOSizeLabelTests {

    @Test func everyPermittedSizeRendersAsWholeMiB() {
        #expect(TesterProtocol.permittedIOSizes.map(IOSizeSelection.label)
                    == ["1 MiB", "2 MiB", "4 MiB", "8 MiB"])
    }

    /// The label is shared by the dropdown, the report window and the exported Markdown. Pinned so
    /// a change to it is a deliberate act in all three at once, rather than a drift between them.
    @Test func theDefaultRendersAsFourMiB() {
        #expect(IOSizeSelection.label(TesterProtocol.defaultIOSizeBytes) == "4 MiB")
    }
}

// MARK: - Where the choice is kept

struct IOSizeStoreTests {

    /// A throwaway suite, so the suite never touches the preferences of whoever ran it.
    private func scratchDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "PreRunControlsTests.\(name)")!
        defaults.removePersistentDomain(forName: "PreRunControlsTests.\(name)")
        return defaults
    }

    /// FR-CTRL-8's default **by construction**: `integer(forKey:)` returns `0` for a key that has
    /// never been set, and `0` is not a permitted size. A fresh install, a new user account and a
    /// deleted preferences file are all this case, with no default registered anywhere.
    @Test func anUnsetPreferenceReadsAsFourMiB() {
        let store = UserDefaultsIOSize(defaults: scratchDefaults("unset"))
        #expect(store.ioSizeBytes == TesterProtocol.defaultIOSizeBytes)
        #expect(store.ioSizeBytes == 4 << 20)
    }

    @Test func aStoredSizeSurvivesAndComesBack() {
        let defaults = scratchDefaults("roundTrip")
        UserDefaultsIOSize(defaults: defaults).ioSizeBytes = 8 << 20
        // A **second instance** over the same defaults, which is what a relaunch is.
        #expect(UserDefaultsIOSize(defaults: defaults).ioSizeBytes == 8 << 20)
    }

    /// **The persisted value is not trusted.** A hand-edited plist, or one written by a version
    /// whose permitted set differed, would otherwise reach the helper — which validates the size
    /// at the XPC boundary and would *refuse the call*. That refusal produces no report and reads
    /// as the drive failing rather than the preference being wrong.
    @Test func anUnpermittedStoredSizeFallsBackToTheDefault() {
        let defaults = scratchDefaults("tampered")
        for bogus in [0, -1, 3 << 20, 16 << 20, 512, Int.max] {
            defaults.set(bogus, forKey: UserDefaultsIOSize.key)
            #expect(UserDefaultsIOSize(defaults: defaults).ioSizeBytes
                        == TesterProtocol.defaultIOSizeBytes,
                    "stored \(bogus)")
        }
    }

    /// Every permitted size survives the round trip — a fallback that swallowed a legitimate
    /// choice would look exactly like one that swallowed a bad one.
    @Test func everyPermittedSizeRoundTrips() {
        let defaults = scratchDefaults("permitted")
        for size in TesterProtocol.permittedIOSizes {
            UserDefaultsIOSize(defaults: defaults).ioSizeBytes = size
            #expect(UserDefaultsIOSize(defaults: defaults).ioSizeBytes == size)
        }
    }

    /// **The double must not admit what the real store rejects.** A test double that is more
    /// permissive than the thing it stands in for makes a green test mean less than it appears to.
    @Test func theInMemoryDoubleValidatesLikeTheRealStore() {
        let store = InMemoryIOSize()
        #expect(store.ioSizeBytes == TesterProtocol.defaultIOSizeBytes)
        store.ioSizeBytes = 16 << 20
        #expect(store.ioSizeBytes == TesterProtocol.defaultIOSizeBytes)
        store.ioSizeBytes = 2 << 20
        #expect(store.ioSizeBytes == 2 << 20)
    }

    /// The default the whole feature rests on, pinned so a change to it is a deliberate act.
    @Test func fourMiBIsTheDefaultAndIsPermitted() {
        #expect(TesterProtocol.defaultIOSizeBytes == 4 << 20)
        #expect(TesterProtocol.permittedIOSizes.contains(TesterProtocol.defaultIOSizeBytes))
    }
}

// MARK: - The model's write-through

@MainActor
struct AppModelIOSizeTests {

    /// The store is the persistence and the property is the value; the two cannot drift because
    /// the property is the only writer and it writes through on every set. Same arrangement as
    /// `warningsSuppressed`, and for the same `@Observable` reason.
    @Test func settingTheSizeWritesItThroughToTheStore() {
        let store = InMemoryIOSize()
        let model = AppModel(suppressionStore: InMemoryPreRunWarningSuppression(),
                             ioSizeStore: store,
                             deviceSource: StubDeviceSource())
        #expect(model.ioSizeBytes == TesterProtocol.defaultIOSizeBytes)

        model.ioSizeBytes = 8 << 20
        #expect(store.ioSizeBytes == 8 << 20)
    }

    /// A launch reads what the last one left. The half of persistence a write-through test cannot
    /// see on its own.
    @Test func theModelStartsAtTheStoredSize() {
        let store = InMemoryIOSize(ioSizeBytes: 1 << 20)
        let model = AppModel(suppressionStore: InMemoryPreRunWarningSuppression(),
                             ioSizeStore: store,
                             deviceSource: StubDeviceSource())
        #expect(model.ioSizeBytes == 1 << 20)
    }

    /// FR-FAIL-4's default, which increment 6 moved the *control* for and not the value.
    @Test func theFailureModeStillDefaultsToLogAndContinue() {
        let model = AppModel(suppressionStore: InMemoryPreRunWarningSuppression(),
                             ioSizeStore: InMemoryIOSize(),
                             deviceSource: StubDeviceSource())
        #expect(model.failureMode == .standard)
        #expect(model.failureMode == .logAndContinue)
    }
}
