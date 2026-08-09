//
//  OutcomePresentation.swift
//  USBDriveTester (app target — unprivileged)
//
//  How the result of a mount / unmount / acquire / release reaches the user (NFR-USE-5).
//
//  ## Why this is a type rather than an `if` in a view
//
//  It exists because of a defect found on 2026-08-09, and the defect is worth stating because it
//  is not the kind a test would have caught.
//
//  The unmount rollback's error message was **correct, complete, and never seen**. The state was
//  right — the unified log showed `outcome shown (error): Could not unmount Vol_ExFAT…` with no
//  clearing line after it, ever — and the text was rendered faithfully. It was simply the last
//  element inside the detail pane's `ScrollView`, below a device-identity block that is tall when
//  the selected drive has several mounted volumes. So it drew just past the bottom edge, in a
//  scroll region that does not advertise itself as scrollable.
//
//  > *"if I missed the error message multiple times, and I'm the owner of this project, a user is
//  > also very likely to miss it — so it needs to be way more prominent."* — user, 2026-08-09
//
//  Three earlier rounds of this control were argued about rather than measured, and the thing that
//  finally distinguished "never set" from "set and erased" was a log line. This type is the same
//  move applied to the next question along: **which route did the message take to the user?** is
//  now a value that can be asserted, not a branch buried in a `body`.
//
//  ## And why failures interrupt while successes do not
//
//  A modal on every successful unmount teaches the user to dismiss the dialog unread, which spends
//  the prominence exactly when it is next needed. Failures interrupt; successes are reported in
//  place. **The inline copy is kept either way** — the alert guarantees the message is seen once,
//  the inline copy lets it be re-read and text-selected after the dialog is gone.
//
//  ## What this cannot do, stated rather than left to be discovered
//
//  A SwiftUI `alert` gets its **own window**, so `scripts/render-ui.sh` cannot capture it — the
//  same property that made Step 10 give the run report a `Window` scene instead of a sheet, after
//  two of that increment's defects were found only by looking at a render. So "a dialog actually
//  appeared" will always need a person. What is testable is everything up to that point: which
//  outcomes interrupt, and what the dialog is headed. That is what lives here.
//

import Foundation

/// The operation an outcome is about. Carried so a failure can be headed with what failed, rather
/// than with a generic banner the user has to read the body to interpret.
nonisolated enum OutcomeOperation: Equatable, CaseIterable {
    case unmount
    case mount
    case acquire
    case release

    /// The headline for a failed operation.
    ///
    /// Short and specific: an alert's title is the one line a user reliably reads, so it says what
    /// did not happen. The body carries the cause and the corrective step (NFR-USE-5).
    var failureTitle: String {
        switch self {
        case .unmount:  return "The drive could not be unmounted"
        case .mount:    return "The volumes could not be mounted"
        case .acquire:  return "Exclusive access was not granted"
        case .release:  return "The drive could not be released"
        }
    }

    /// Whether a **successful** outcome needs saying at all.
    ///
    /// ## Unmount: no (user decision 2026-08-09)
    ///
    /// Three reasons, and the first is structural:
    ///
    /// 1. **Step 11 folds unmounting into the start of a run.** There will be no "Mounting &
    ///    exclusive access" pane to report into, so a message here is one Step 11 deletes.
    /// 2. **Finder already says it** — the volume disappears from the desktop.
    /// 3. **The Selected device pane already says it**, in standing text rather than a transient
    ///    one: `Mounted volumes — None mounted`, rendered from the live device record.
    ///
    /// A confirmation that repeats what two other surfaces already show is not reassurance, it is
    /// noise competing with the messages that *do* need reading — which is the same argument that
    /// keeps successes out of the modal.
    ///
    /// ## Mount: yes, and the asymmetry is deliberate
    ///
    /// A successful `mountAll` can mount **nothing** — an unformatted drive, or a filesystem macOS
    /// cannot read — and DiskArbitration reports no dissenter either way. Its message is the only
    /// place that explains it, and the standing pane says "None mounted" for both "nothing was
    /// asked" and "everything was asked and nothing could". Reason 3 does not hold there, so the
    /// message stays.
    ///
    /// Acquire and release likewise say something not otherwise visible — release's message
    /// carries "macOS will normally remount the volumes shortly."
    var successIsSelfEvident: Bool {
        switch self {
        case .unmount:                    return true
        case .mount, .acquire, .release:  return false
        }
    }
}

/// How an outcome is delivered.
nonisolated enum OutcomePresentation: Equatable {

    /// Not shown to the user at all — the result is already evident from surfaces that outlive
    /// this one. **Still logged**; see ``logName``.
    case silent

    /// Reported in place. The user is not interrupted.
    case inline

    /// Interrupts with a modal dialog headed `title`, **and** is still reported in place.
    case interrupt(title: String)

    /// For the log, so the route taken is recoverable after the fact rather than inferred from
    /// whether somebody remembers seeing a dialog.
    ///
    /// **`.silent` is silent to the *user*, never to the log.** An outcome nobody was told about
    /// and nobody recorded is exactly the state this whole area has been paying for: on
    /// 2026-08-09 a correct message that was never seen was indistinguishable from a message that
    /// was never produced, and the only thing that told them apart was a log line.
    var logName: String {
        switch self {
        case .silent:    return "not shown — evident from the device pane and Finder"
        case .inline:    return "inline"
        case .interrupt: return "inline + modal alert"
        }
    }

    /// Whether this presentation puts a dialog on screen.
    var interrupts: Bool {
        if case .interrupt = self { return true }
        return false
    }

    /// Whether the message is left in the pane.
    var showsInline: Bool { self != .silent }

    /// The rule: **failures always interrupt. Successes are shown in place, unless the operation's
    /// success is already evident elsewhere, in which case nothing is shown.**
    ///
    /// The failure branch is deliberately keyed on success/failure alone, with no per-operation
    /// exemption: that is how "this one is not important enough to interrupt" enters, and the
    /// operation that gets exempted is invariably the one nobody expected to fail. Only the
    /// *success* branch consults the operation — see ``OutcomeOperation/successIsSelfEvident``.
    static func forOutcome(ok: Bool, operation: OutcomeOperation) -> OutcomePresentation {
        guard ok else { return .interrupt(title: operation.failureTitle) }
        return operation.successIsSelfEvident ? .silent : .inline
    }
}
