//
//  DeviceLossMessage.swift
//  USBDriveTester (app target — unprivileged)
//
//  Step 12, chunk 6. **What a lost drive says to a person when there is no report to say it.**
//
//  ## The case this exists for, and why it was invisible
//
//  FR-DEV-8 asks for three things: terminate the run, present a suitable error message, and re-run
//  discovery. Chunk 5 made the *report* the error message, which is the right answer almost always
//  — it interrupts, it carries the block and the phase, and it says more than an alert could fit.
//
//  Almost always is not always. `RunController.makeReport` returns `nil` when the sequence has no
//  final reply, and `RunSequencer.lastReply` starts `nil` and is written only when a reply arrives.
//  So a drive that leaves **during the very first call, with the helper never answering it**,
//  produces no reply, therefore no report, therefore — before this type — no message of any kind.
//  The only trace was a log line reading *"the helper refused the call, so no run took place"*,
//  which is false twice over: a run took place, and nothing was refused.
//
//  That combination is not the exotic one. The first call covers a whole slice, up to a gibibyte,
//  and inside it every chunk is read, written back and verified — so the first call is exactly
//  where a write-back is most likely to be in flight when somebody pulls the cable. **The one case
//  that said nothing was the one where the most is at stake.**
//
//  ## Why a type and not a string at the call site
//
//  The same reason `OutcomePresentation` is a type: an `.alert` cannot be rendered by
//  `scripts/render-ui.sh` — it gets its own window, and `.alert(_:isPresented:actions:message:)`
//  takes `ViewBuilder`s AppKit consumes, so there is no value to hand an `NSHostingView` (measured
//  in Step 11 increment 9). Everything about the dialog that is not a pure value is covered by a
//  person at a keyboard and nothing else. So as much as possible is made a pure value: what it
//  says is decided here, where a test can read it, and the view is left holding only the `.alert`.
//
//  ## The text carries no Markdown, and that is a constraint rather than a style
//
//  `RunControlsView` renders the message as `Text(failure.text)` — a `String`, which SwiftUI does
//  **not** parse as Markdown (only `LocalizedStringKey` does). Emphasis therefore has to come from
//  sentence order and word choice, which is why the write-back sentence is second rather than
//  buried: in a paragraph with no bold, the reader's attention is bought by position alone.
//
//  ## Ordering: what happened, what it means for the data, what to do
//
//  Four sentences, in that order, and the order is the design. A person reading an alert about a
//  drive they just unplugged already knows the drive was unplugged; what they do not know is
//  whether their data is intact, and that is the sentence that must not be third.
//

import Foundation

/// The alert a device loss raises when the run produced no report.
///
/// Never the ordinary path. A run with any reply at all gets a report, and the report is the
/// message — see ``RunReport`` and `HonestFraming.claim(about:)`.
nonisolated enum DeviceLossMessage {

    /// The dialog's heading.
    ///
    /// Names the event rather than the consequence. `OutcomeOperation.failureTitle`'s rule — *say
    /// what did not happen* — does not transfer here, because nothing failed: a drive left, which
    /// is a thing that happened rather than an operation that did not succeed. Heading it "The
    /// test could not finish" would put the blame on the app for something the cable did.
    static let title = "The drive was disconnected during the test"

    /// What the dialog says, for a run that ended with the drive gone and no report to show.
    ///
    /// - Parameter ending: which of the removal callback's two ways ended the run, or `nil` when
    ///   nothing recorded one.
    ///
    /// **Exhaustive over `DeviceLossEnding`, including the case that cannot arrive.** A run ended
    /// by `nothingWasInFlight` was paused, and a paused run has already had the reply that settled
    /// the pause — so `lastReply` is not `nil`, a report *is* built, and this function is not
    /// called. That case is named anyway rather than folded into the other, for the reason
    /// `DeviceLossAccount.noRouteSaidAnything` is named: this is a pure function, so the unreachable
    /// case is reachable *by a test*, and a wrong answer there would be a wrong answer in the one
    /// place nobody would look. Collapsing it would also mean a future change that makes it
    /// reachable inherits a sentence about a write-back that provably did not happen.
    static func forRunWithNoReport(endedBy ending: DeviceLossEnding?) -> RunFailureMessage {
        RunFailureMessage(title: title, text: body(ending))
    }

    private static func body(_ ending: DeviceLossEnding?) -> String {
        let opening = "The drive left the USB bus part-way through the run, "
        let closing = " This run cannot be continued — start it again from the beginning."

        switch ending {
        case .theHelperNeverAnswered:
            return opening
                 + "and the privileged helper never answered the call that was in flight. "
                 + "There is no report for this run, because nothing came back to build one from."
                 + "\n\n"
                 + "It cannot be ruled out that a write-back was interrupted: one chunk of the "
                 + "drive may hold partly written data, and nothing can say which one."
                 + "\n\n"
                 + "Exclusive access could not be confirmed as given back either — the same call "
                 + "that went quiet is the one that would have carried the answer. If the helper "
                 + "is still holding the drive, starting another test will say so."
                 + closing

        case .nothingWasInFlight:
            // See the note on `forRunWithNoReport(endedBy:)`: unreachable in the app, reachable in
            // a test, and deliberately says *less* rather than borrowing the sentence above.
            return opening
                 + "while the run was paused. There is no report for this run."
                 + "\n\n"
                 + "Nothing was being written when the drive left, so no chunk was left "
                 + "half-written."
                 + closing

        case nil:
            return opening
                 + "and nothing recorded how it ended. There is no report for this run."
                 + "\n\n"
                 + "It cannot be ruled out that a write-back was interrupted: one chunk of the "
                 + "drive may hold partly written data, and nothing can say which one."
                 + closing
        }
    }
}
