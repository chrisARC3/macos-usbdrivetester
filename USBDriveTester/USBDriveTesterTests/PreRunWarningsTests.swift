//
//  PreRunWarningsTests.swift
//  What stands between pressing Start and a write (FR-WARN-1/2/3/4, NFR-USE-4).
//
//  ## The fixture is the Seagate, deliberately
//
//  Every test here names the **22 TB Seagate Expansion HDD with Backup and Time Machine mounted**,
//  serial `00000000NT17XBRA`. That is not a neutral placeholder: FR-DEV-3 selects the first usable
//  device in FR-DEV-2's BSD-name order, and on 2026-08-09 that drive is what "first" names on the
//  development machine — re-measured by rendering the real device list through the app's own
//  enumerator, not carried over from the 2026-08-06 note. It is the drive this entire step exists
//  to keep from being written to by accident, so it is the drive these assertions are about.
//
//  ## What these tests can and cannot reach
//
//  They cover the decision: which dialog is raised, whether a run may be issued, and whether the
//  suppression preference is recorded. They **cannot** cover the sheet appearing — a SwiftUI sheet
//  gets its own window, which `render-ui.sh` cannot capture. That limitation is stated rather than
//  papered over, and it is why increment 3 gives each dialog a standalone renderable `View`: what
//  can be checked headlessly is checked headlessly, and a person is left with *"did a dialog
//  appear"* rather than *"was the right thing decided"*.
//

import Testing
@testable import USBDriveTester

private enum Fixture {

    /// The drive FR-DEV-3 default-selects on this machine, with a live Time Machine on it.
    static func seagate(serial: String? = "00000000NT17XBRA") -> ReportedDevice {
        ReportedDevice(modelDescription: "Seagate Expansion HDD",
                       usbSerialNumber: serial,
                       bsdNameAtRunTime: "disk4",
                       capacityBytes: 22_000_969_973_248,
                       logicalBlockSize: 512)
    }
}

struct PreRunWarningPolicyTests {

    // MARK: - A dialog is raised either way

    /// **The requirement, and the reason `PreRunPrompt` has no third case.**
    ///
    /// The warning *text* is suppressible; the deliberate *act* is not. A mutation that let
    /// suppression skip the dialog entirely would put the product one launch and one click from a
    /// write to whichever drive sorted first — which is the hazard BUILD-PLAN Step 11's gating on
    /// this step exists to close.
    @Test func aDialogIsRaisedWhetherOrNotTheWarningsAreSuppressed() {
        for suppressed in [false, true] {
            let prompt = PreRunPrompt.forRun(warningsSuppressed: suppressed,
                                             device: Fixture.seagate())
            #expect(prompt.device.usbSerialNumber == "00000000NT17XBRA",
                    "suppressed=\(suppressed) must still raise a dialog naming the drive")
        }
    }

    /// The default state: the full text, every run.
    @Test func theWarningsAreShownInFullUntilTheUserSuppressesThem() {
        #expect(PreRunPrompt.forRun(warningsSuppressed: false, device: Fixture.seagate())
                == .fullWarnings(Fixture.seagate(), purpose: .newRun))
    }

    /// Suppression downgrades the dialog; it does not remove it. A mutation returning
    /// `.fullWarnings` here makes the checkbox a no-op — the annoyance the user asked to be rid of
    /// — and one returning nothing at all removes the guard.
    @Test func suppressionDowngradesTheDialogRatherThanRemovingIt() {
        #expect(PreRunPrompt.forRun(warningsSuppressed: true, device: Fixture.seagate())
                == .briefConfirmation(Fixture.seagate(), purpose: .newRun))
    }

    // MARK: - Both dialogs name the drive

    /// The suppressed dialog has nothing else to say, so if it did not name the drive it would say
    /// nothing at all.
    @Test func everyPromptCarriesTheDriveItIsAbout() {
        let device = Fixture.seagate()
        for prompt in [PreRunPrompt.fullWarnings(device, purpose: .newRun),
                       .briefConfirmation(device, purpose: .newRun)] {
            #expect(prompt.device == device, "\(prompt.logName) must name its drive")
        }
    }

    /// **Model and USB serial**, per the inherited note on this step: an acknowledgement whose
    /// subject is "disk4" is an acknowledgement of a name that may have moved. On 2026-08-09 the
    /// scratch drive moved from `disk8` to `disk10` inside three days, which is the whole argument.
    @Test func theDriveIsIdentifiedByModelAndSerialNotByItsBSDName() {
        let identification = Fixture.seagate().identification
        #expect(identification.contains("Seagate Expansion HDD"))
        #expect(identification.contains("00000000NT17XBRA"))
        #expect(!identification.contains("disk4"),
                "the BSD name is a locator and must not be the identity in a confirmation")
    }

    /// The case the suppressed dialog cannot afford to get wrong: with no serial, the confirmation
    /// is the *only* identification the user gets, and it must admit that it cannot tell this drive
    /// from another of the same model rather than implying an identity it does not have.
    @Test func aDriveWithNoSerialSaysSoRatherThanImplyingAnIdentity() {
        let anonymous = Fixture.seagate(serial: nil)
        #expect(anonymous.identificationCaveat != nil)
        #expect(anonymous.identification == "Seagate Expansion HDD")
    }

    /// Step 10's mutation **S4** in the same place: a log that cannot tell two routes apart cannot
    /// answer the question it exists for. Which dialog a user was shown is the first thing anyone
    /// diagnosing "I was never warned" needs.
    @Test func theTwoPromptsAreDistinguishableInTheLog() {
        let device = Fixture.seagate()
        #expect(PreRunPrompt.fullWarnings(device, purpose: .newRun).logName
                != PreRunPrompt.briefConfirmation(device, purpose: .newRun).logName)
    }

    // MARK: - Restart's dialog (FR-CTRL-5, increment 8)

    /// **Suppression chooses the form; it does not reach the discard warning.** What is
    /// suppressible is the standing FR-WARN-1/2/3 text — advice about the tool, the same on every
    /// run. This is a consequence of the press being made now, and a consequence the user has
    /// never been shown cannot have been consented to in advance (NFR-USE-4 as qualified
    /// 2026-08-09).
    @Test func aRestartWarnsAboutDiscardingWhicheverFormTheDialogTakes() {
        for suppressed in [false, true] {
            let prompt = PreRunPrompt.forRestart(warningsSuppressed: suppressed,
                                                 device: Fixture.seagate())
            #expect(prompt.discardsRunInProgress,
                    "suppression removed the discard warning (suppressed=\(suppressed))")
            #expect(prompt.purpose == .restart)
        }
    }

    /// And a Start never carries it — the other half, so the property above cannot be satisfied by
    /// warning about discarding on every run.
    @Test func aStartNeverWarnsAboutDiscardingARun() {
        for suppressed in [false, true] {
            let prompt = PreRunPrompt.forRun(warningsSuppressed: suppressed,
                                             device: Fixture.seagate())
            #expect(!prompt.discardsRunInProgress)
            #expect(prompt.purpose == .newRun)
        }
    }

    /// The suppression preference still chooses the form on the restart path, so a user who has
    /// turned the text off does not get it back because they pressed a different button.
    @Test func restartStillHonoursTheSuppressionPreferenceForTheFormOfTheDialog() {
        #expect(PreRunPrompt.forRestart(warningsSuppressed: false, device: Fixture.seagate())
                == .fullWarnings(Fixture.seagate(), purpose: .restart))
        #expect(PreRunPrompt.forRestart(warningsSuppressed: true, device: Fixture.seagate())
                == .briefConfirmation(Fixture.seagate(), purpose: .restart))
    }

    /// **A restart prompt is a different dialog from a start prompt for the same drive.**
    ///
    /// Both halves matter. The log must be able to say which of the two acts the user acknowledged
    /// — Step 10's mutation S4 in the run controls — and `sheet(item:)` decides whether a *new*
    /// dialog is being presented by comparing ids, so sharing one would let an acknowledgement of
    /// a Start stand as the acknowledgement of a Restart.
    @Test func aRestartPromptIsToldApartFromAStartPromptForTheSameDrive() {
        let device = Fixture.seagate()
        for suppressed in [false, true] {
            let start = PreRunPrompt.forRun(warningsSuppressed: suppressed, device: device)
            let restart = PreRunPrompt.forRestart(warningsSuppressed: suppressed, device: device)

            #expect(start.id != restart.id, "sheet(item:) cannot tell the two dialogs apart")
            #expect(start.logName != restart.logName, "the log cannot tell the two acts apart")
        }
    }

    /// The sentence says the thing that cannot be recovered from, and names it as a consequence
    /// rather than a caution. Asserted on the substance, not on the whole string.
    @Test func theDiscardWarningSaysTheProgressIsGoneAndCannotBeContinued() {
        let text = PreRunWarningText.restartDiscardsProgress.lowercased()
        #expect(text.contains("discarded"))
        #expect(text.contains("cannot be continued"))
        #expect(text.contains("from the beginning"))
    }

    // MARK: - The presentation identity (increment 5)

    /// `sheet(item:)` decides whether a *different* dialog is being presented by comparing ids.
    /// **A prompt raised for one drive must never be reused for another** — the drive is what the
    /// acknowledgement is about, and on this machine `disk8` named two different drives in three
    /// days. An id that ignored the device would let a dialog raised for the scratch drive stand as
    /// the acknowledgement for the 22 TB backup drive.
    @Test func promptsForDifferentDrivesHaveDifferentIdentities() {
        let seagate = PreRunPrompt.fullWarnings(Fixture.seagate(), purpose: .newRun)
        let other = PreRunPrompt.fullWarnings(
            ReportedDevice(modelDescription: "Samsung Portable SSD T5",
                           usbSerialNumber: "12345686DAA9",
                           bsdNameAtRunTime: "disk10",
                           capacityBytes: 1_000_204_886_016,
                           logicalBlockSize: 512),
            purpose: .newRun)
        #expect(seagate.id != other.id)
    }

    /// The other half: suppressing the text mid-session changes which dialog should be on screen,
    /// so the two forms must not share an identity either.
    @Test func theTwoFormsHaveDifferentIdentitiesForTheSameDrive() {
        let device = Fixture.seagate()
        #expect(PreRunPrompt.fullWarnings(device, purpose: .newRun).id
                != PreRunPrompt.briefConfirmation(device, purpose: .newRun).id)
    }

    /// And the same prompt is the same dialog — otherwise a redraw could re-present it, which for a
    /// dialog gating a write means asking twice for one decision.
    @Test func theSamePromptKeepsOneIdentity() {
        #expect(PreRunPrompt.fullWarnings(Fixture.seagate(), purpose: .newRun).id
                == PreRunPrompt.fullWarnings(Fixture.seagate(), purpose: .newRun).id)
    }

    /// A drive with no serial still needs to be told apart from a different drive with no serial.
    /// The model name is the only axis left, and using it is the honest best available — not an
    /// identification, which `identificationCaveat` says plainly on the dialog itself.
    @Test func drivesWithNoSerialAreStillDistinguishedAsFarAsPossible() {
        let anonymous = PreRunPrompt.briefConfirmation(Fixture.seagate(serial: nil), purpose: .newRun)
        let otherAnonymous = PreRunPrompt.briefConfirmation(
            ReportedDevice(modelDescription: "Generic USB 3.0 Enclosure",
                           usbSerialNumber: nil,
                           bsdNameAtRunTime: "disk4",
                           capacityBytes: 500_107_862_016,
                           logicalBlockSize: 512),
            purpose: .newRun)
        #expect(anonymous.id != otherAnonymous.id)
    }

    // MARK: - What dismissing the dialog does

    @Test func proceedIssuesTheRun() {
        let outcome = PreRunWarningPolicy.outcome(button: .proceed,
                                                  suppressionRequested: false,
                                                  mayIssueNewWork: true)
        #expect(outcome.issuesRun)
    }

    @Test func cancelIssuesNothing() {
        let outcome = PreRunWarningPolicy.outcome(button: .cancel,
                                                  suppressionRequested: false,
                                                  mayIssueNewWork: true)
        #expect(!outcome.issuesRun)
    }

    @Test func proceedWithTheBoxTickedRecordsTheSuppression() {
        let outcome = PreRunWarningPolicy.outcome(button: .proceed,
                                                  suppressionRequested: true,
                                                  mayIssueNewWork: true)
        #expect(outcome.issuesRun)
        #expect(outcome.persistsSuppression)
    }

    /// **The safety row.** Cancel is what a user presses when something is wrong — most plausibly
    /// that the selected drive is not the one they meant, on the screen whose whole job is stopping
    /// exactly that. Recording *"never warn me again"* out of a dialog they backed away from would
    /// reduce future warnings at the moment the warnings just did their job.
    @Test func cancelWithTheBoxTickedRecordsNothing() {
        let outcome = PreRunWarningPolicy.outcome(button: .cancel,
                                                  suppressionRequested: true,
                                                  mayIssueNewWork: true)
        #expect(!outcome.issuesRun)
        #expect(!outcome.persistsSuppression,
                "a preference expressed about a run that was then declined is not carried")
    }

    /// `AppModel.mayIssueNewWork` is "a precondition, not a hint" (BUILD-PLAN Step 11), and it is
    /// the one precondition that can flip **while this sheet is up**: the quit confirmation is
    /// window-modal on the main window, so the window raising this sheet stays clickable
    /// underneath it. Checking it when the sheet was raised is not checking it before the call.
    @Test func proceedWhileAQuitIsPendingIssuesNothing() {
        let outcome = PreRunWarningPolicy.outcome(button: .proceed,
                                                  suppressionRequested: false,
                                                  mayIssueNewWork: false)
        #expect(!outcome.issuesRun)
    }

    /// The other half of the same rule: **the preference is recorded only by a run that actually
    /// starts.** A press that could not start one did not start one.
    @Test func proceedWhileAQuitIsPendingRecordsNothingEither() {
        let outcome = PreRunWarningPolicy.outcome(button: .proceed,
                                                  suppressionRequested: true,
                                                  mayIssueNewWork: false)
        #expect(!outcome.persistsSuppression)
    }

    /// Nothing is ever suppressed that the user did not ask to suppress — across every button and
    /// every precondition, so a mutation that hard-codes `persistsSuppression` is caught wherever
    /// it is put.
    @Test func nothingIsSuppressedWithoutTheBoxBeingTicked() {
        for button in PreRunButton.allCases {
            for mayIssue in [false, true] {
                let outcome = PreRunWarningPolicy.outcome(button: button,
                                                          suppressionRequested: false,
                                                          mayIssueNewWork: mayIssue)
                #expect(!outcome.persistsSuppression,
                        "button=\(button) mayIssueNewWork=\(mayIssue) suppressed without asking")
            }
        }
    }

    /// No button may issue a run while a quit is pending — stated over the whole table rather than
    /// only the `.proceed` row, so a mutation that reverses the guard has nowhere to hide.
    @Test func noButtonIssuesARunWhileAQuitIsPending() {
        for button in PreRunButton.allCases {
            let outcome = PreRunWarningPolicy.outcome(button: button,
                                                      suppressionRequested: false,
                                                      mayIssueNewWork: false)
            #expect(!outcome.issuesRun, "button=\(button) issued work during a wind-down")
        }
    }

    // MARK: - The store

    /// Warnings are shown until the user says otherwise. A double that defaulted to *suppressed*
    /// would make every other test in this file pass against the wrong starting state.
    @Test func warningsAreNotSuppressedByDefault() {
        #expect(!InMemoryPreRunWarningSuppression().warningsSuppressed)
    }

    @Test func theInMemoryStoreRemembersWhatItIsTold() {
        let store = InMemoryPreRunWarningSuppression()
        store.warningsSuppressed = true
        #expect(store.warningsSuppressed)
        store.warningsSuppressed = false
        #expect(!store.warningsSuppressed)
    }
}
