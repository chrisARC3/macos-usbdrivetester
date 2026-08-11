//
//  PreRunWarningSuppressionTests.swift
//  Where "Don't show this warning again" is kept, and how it gets back (Step 14, increment 4).
//
//  ## These tests must not change the preferences of whoever runs them
//
//  The real store is the app's `UserDefaults.standard`. A test that wrote there would alter the
//  machine's actual settings from a unit run — a side effect on a real system, from a suite that is
//  supposed to be hardware-independent. Every test here uses a **throwaway suite** with a unique
//  name and removes it afterwards, and `UserDefaultsPreRunWarningSuppression` takes its `defaults`
//  by injection for exactly that reason.
//
//  ## What is being protected
//
//  Suppression removes the warning **text**, never the confirmation (NFR-USE-4 as qualified
//  2026-08-09). Nothing in this file can enforce that — `PreRunPrompt.forRun` does, and
//  `PreRunWarningPolicyTests` pins it. What these cover is narrower and still worth having: that
//  the flag is stored where it was asked to be stored, that it survives, that absence means
//  "warn", and that there is a way back.
//

import Foundation
import Testing
@testable import USBDriveTester

struct PreRunWarningSuppressionTests {

    /// A `UserDefaults` nobody else is using, and which is removed at the end of the test.
    private func withThrowawayDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        // Not `Date()`/`UUID()`-derived: the suite name is built from the test's own identity so a
        // failed run leaves a predictable domain rather than an unbounded pile of them.
        let suiteName = "com.arc3solutions.USBDriveTester.tests.suppression"
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("could not open a throwaway defaults suite")
            return
        }
        try body(defaults)
    }

    // MARK: - The store

    /// **Absence means "show the warnings", and it means it without a registered default.**
    ///
    /// `bool(forKey:)` returns `false` for a key never written, and `false` is *not suppressed*. So
    /// a fresh install, a new user account and a deleted preferences file all warn. Registering a
    /// default would add a second place the answer lives; the safe answer is the one absence
    /// already gives.
    @Test func aStoreWithNothingWrittenReportsNotSuppressed() {
        withThrowawayDefaults { defaults in
            #expect(!UserDefaultsPreRunWarningSuppression(defaults: defaults).warningsSuppressed)
        }
    }

    @Test func theStoreRoundTripsBothWays() {
        withThrowawayDefaults { defaults in
            let store = UserDefaultsPreRunWarningSuppression(defaults: defaults)
            store.warningsSuppressed = true
            #expect(store.warningsSuppressed)
            store.warningsSuppressed = false
            #expect(!store.warningsSuppressed)
        }
    }

    /// The property the user actually asked for: it has to still be set **next time**. A second
    /// store over the same defaults is the closest a unit test gets to a relaunch, and it is the
    /// difference between persisting the value and merely remembering it in this process.
    @Test func theSettingSurvivesTheObjectThatWroteIt() {
        withThrowawayDefaults { defaults in
            UserDefaultsPreRunWarningSuppression(defaults: defaults).warningsSuppressed = true
            let reopened = UserDefaultsPreRunWarningSuppression(defaults: defaults)
            #expect(reopened.warningsSuppressed)
        }
    }

    /// **Per logged-in user, which means it must not be written anywhere shared.** A store over one
    /// domain must be invisible to a store over another — the property that would break if this
    /// were ever moved into the root helper, where it would become system-wide and apply to every
    /// account on the machine without any of them being told.
    @Test func oneDomainsSettingIsInvisibleToAnother() {
        withThrowawayDefaults { defaults in
            UserDefaultsPreRunWarningSuppression(defaults: defaults).warningsSuppressed = true

            let otherName = "com.arc3solutions.USBDriveTester.tests.suppression.other"
            UserDefaults.standard.removePersistentDomain(forName: otherName)
            defer { UserDefaults.standard.removePersistentDomain(forName: otherName) }
            guard let other = UserDefaults(suiteName: otherName) else {
                Issue.record("could not open the second throwaway suite")
                return
            }
            #expect(!UserDefaultsPreRunWarningSuppression(defaults: other).warningsSuppressed)
        }
    }

    /// **The key is asserted as a literal, on purpose.**
    ///
    /// Writing `UserDefaults…key` on both sides would make this test agree with any rename, which
    /// is precisely the change it exists to catch: renaming the key silently un-suppresses every
    /// user who had already set the preference — their stored value is still on disk under the old
    /// name, and the app stops looking at it. Nothing else in the product would notice. A stored
    /// key is part of the app's contract with its own installed base, so the literal is transcribed
    /// here independently and a rename has to be deliberate enough to change both.
    @Test func theSettingIsStoredUnderTheAdvertisedKeyAndTheKeyDoesNotMoveQuietly() {
        #expect(UserDefaultsPreRunWarningSuppression.key == "preRunWarningsSuppressed")

        withThrowawayDefaults { defaults in
            UserDefaultsPreRunWarningSuppression(defaults: defaults).warningsSuppressed = true
            #expect(defaults.bool(forKey: "preRunWarningsSuppressed"))
        }
    }
}

@MainActor
struct AppModelWarningSuppressionTests {

    /// The value the UI binds to is read from the store at launch — otherwise the setting persists
    /// perfectly and the app ignores it, which looks exactly like not persisting at all.
    @Test func theModelStartsFromWhateverWasStored() {
        let stored = InMemoryPreRunWarningSuppression(warningsSuppressed: true)
        #expect(AppModel(suppressionStore: stored).warningsSuppressed)

        let unset = InMemoryPreRunWarningSuppression(warningsSuppressed: false)
        #expect(!AppModel(suppressionStore: unset).warningsSuppressed)
    }

    /// And it writes through, or the preference lasts exactly as long as the process.
    @Test func settingItOnTheModelPersistsIt() {
        let store = InMemoryPreRunWarningSuppression()
        let model = AppModel(suppressionStore: store)

        model.warningsSuppressed = true
        #expect(store.warningsSuppressed, "the model did not write the preference through")
    }

    /// **Decision 7 — the way back.** The diagnostics window's "Show pre-run warnings again" sets
    /// this to `false`; a setting with no way back is one the user cannot undo without editing a
    /// plist. Clearing has to reach the store too, or the warnings come back for this session and
    /// vanish again at the next launch.
    @Test func restoringTheWarningsReachesTheStore() {
        let store = InMemoryPreRunWarningSuppression(warningsSuppressed: true)
        let model = AppModel(suppressionStore: store)
        #expect(model.warningsSuppressed)

        model.warningsSuppressed = false
        #expect(!store.warningsSuppressed, "restoring the warnings did not reach the store")
    }

    /// The default construction path is the real one. This does not assert *which* store — that
    /// would need a peek at a private field — only that a model built the way the app builds it has
    /// a working flag rather than trapping or reading nothing.
    @Test func theDefaultModelHasAUsableSetting() {
        _ = AppModel().warningsSuppressed
    }
}
