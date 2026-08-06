//
//  QuitSequence.swift
//  USBDriveTester (app target — unprivileged)
//
//  The last few hundred milliseconds of "Cancel and Quit": release the device, then terminate —
//  exactly once, and without being able to hang.
//
//  ## Why this is a type rather than a nested completion handler
//
//  It has two ways in and one way out, which is the shape that produces double-fires:
//
//    * the helper answers the release, or
//    * the helper does not answer at all.
//
//  Both must lead to termination, and **only one of them may cause it**. A `terminate()` called
//  twice is not a harmless repeat — the second one arrives during AppKit's own teardown. Pulling
//  the sequence out of the view layer makes that property testable, which is the whole point:
//  the deadline path is unreachable by clicking, because it needs a daemon that accepts a message
//  and never replies.
//
//  ## Why there is a deadline at all
//
//  `HelperConnection.releaseDevice` reports transport failures through its completion, so an
//  absent daemon is handled. What is not handled by anything is a daemon that *accepts* the
//  message and never replies — and quitting must not be blockable by a wedged privileged process.
//  `prepareForShutdown` reached the same conclusion in Step 4 and for the same reason, so this
//  uses its 5-second figure.
//
//  Failing open is safe here, and that is not an assumption: the helper releases a claim when the
//  connection that took it goes away (NFR-REL-5), so terminating without an acknowledgement still
//  ends with the device released. The acknowledgement is what makes the release *observable*, not
//  what makes it happen.
//
//  ## Why the clock is injected
//
//  Same reason `RunMetrics` takes its clock readings rather than reading a clock: a test that has
//  to sleep for a deadline is a test that is slow and occasionally wrong. `schedule` is handed in,
//  so the deadline path is driven deterministically.
//

import Foundation

/// Releases the device and terminates the app, once.
@MainActor
final class QuitSequence {

    /// Asks the helper to release whatever it holds, calling back when it answers.
    /// `nil` when nothing is held — there is then nothing to wait for.
    typealias Release = (@escaping () -> Void) -> Void

    /// Runs `work` after `seconds`. Injected so tests need no real time.
    ///
    /// `work` is `@MainActor` because it is: it finishes a sequence that owns main-actor state.
    /// Saying so is also what keeps the default implementation warning-free — handing a
    /// non-Sendable closure to `DispatchQueue.asyncAfter` is a concurrency warning, and a
    /// main-actor-isolated closure is `Sendable` by construction.
    typealias Schedule = (_ seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) -> Void

    private let release: Release?
    private let schedule: Schedule
    private let terminate: () -> Void
    private let deadlineSeconds: TimeInterval

    private var hasBegun = false
    private var hasFinished = false

    /// - Parameters:
    ///   - release: how to release the device, or `nil` if nothing is held.
    ///   - deadlineSeconds: how long to wait for the helper to acknowledge before terminating
    ///     anyway.
    ///   - schedule: how to run something later. Defaults to the main queue.
    ///   - terminate: what "quit" means. Injected so this class never mentions `NSApplication`,
    ///     which is what lets it be tested at all.
    init(release: Release?,
         deadlineSeconds: TimeInterval = 5,
         schedule: @escaping Schedule = { seconds, work in
             // The main *queue*, not a run-loop `Timer`. Measured 2026-08-05: a default-mode
             // timer is starved by AppKit's own nested run loops, and this deadline exists
             // precisely for the case where something has gone wrong.
             DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                 MainActor.assumeIsolated { work() }
             }
         },
         terminate: @escaping () -> Void) {
        self.release = release
        self.deadlineSeconds = deadlineSeconds
        self.schedule = schedule
        self.terminate = terminate
    }

    /// Start the sequence. Idempotent: a second call does nothing, so a stray second trigger
    /// cannot start a second release or a second deadline.
    func begin() {
        guard !hasBegun else { return }
        hasBegun = true

        guard let release else {
            // Nothing is held, so there is nothing to release and nothing to wait for.
            finish()
            return
        }

        // Armed *before* the release is issued, deliberately. A release that fails synchronously
        // and never calls back would otherwise leave nothing scheduled at all.
        schedule(deadlineSeconds) { [weak self] in self?.finish() }
        release { [weak self] in self?.finish() }
    }

    /// Whether the sequence has already terminated. Exposed for tests; nothing else needs it.
    var isFinished: Bool { hasFinished }

    private func finish() {
        guard !hasFinished else { return }
        hasFinished = true
        terminate()
    }
}
