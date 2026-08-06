//
//  AppLifecycleDelegate.swift
//  USBDriveTester (app target — unprivileged)
//
//  The ⌘Q half of "ask before quitting during a run" (user decision, 2026-08-05).
//
//  ## Why an `NSApplicationDelegate` at all
//
//  SwiftUI has no hook that can refuse a termination. AppKit's is
//  `applicationShouldTerminate(_:)`, reachable from SwiftUI through
//  `@NSApplicationDelegateAdaptor`, and it covers every route to quitting — the menu item, ⌘Q,
//  `NSApp.terminate(_:)`, a logout — rather than the one control a button handler would see.
//
//  ## Why `.terminateCancel` and not `.terminateLater`
//
//  `.terminateLater` is the API written for "I need a moment before I quit", and it was the
//  obvious first choice. It was measured (scratch scene probe, macOS 26, 2026-08-05) and it does
//  work: main-queue blocks *are* delivered while the terminate handshake is outstanding, so a
//  helper reply could in principle be awaited inside it. Two facts decided against it anyway:
//
//    1. **A run-loop `Timer` scheduled during `.terminateLater` never fired**, where a GCD
//       main-queue block scheduled beside it fired on time. AppKit runs that wait in its own
//       run-loop mode. The live metrics panel is driven by a `Timer` — so the seconds spent
//       waiting for the boundary would be exactly the seconds where the display of the operation
//       being waited on stops moving. The window would look wedged at the one moment the app is
//       asking the user to trust that it is not.
//    2. `.terminateCancel` puts the wind-down in the app's **ordinary** run loop, where the
//       banner, the metrics and the window all behave normally, and rests on nothing that had to
//       be measured.
//
//  The cost is one real difference: a **logout or shutdown** during a run is *cancelled* rather
//  than deferred. That is defensible on this product — a run is writing raw blocks to somebody's
//  drive, cannot be resumed (FR-FAIL-7), and Step 13 will hold a power assertion for the same
//  reason — and the user still gets the dialog and can choose to quit.
//
//  ## Every route ends in the same two lines
//
//  The decision to ask, and the state it moves the app into, live in `AppModel`/`QuitPolicy`. This
//  class contains no policy: it asks, and translates the answer into AppKit's vocabulary. The
//  window-close route does the same thing through `MainWindowCloseGuard`, which is what makes
//  "the same dialog for both entry points" a fact about the code rather than a promise about it.
//

import AppKit

/// Refuses a termination that would abandon a run, and lets every other one through.
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {

    /// Set by the main scene when it appears. Weak: the model is owned by the scene tree.
    weak var model: AppModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // No model means the main window has never appeared, so nothing can have started a run.
        // Quitting is unambiguously fine, and refusing it would strand an app with no UI.
        guard let model else { return .terminateNow }

        switch model.quitRequested() {
        case .quitImmediately:
            return .terminateNow
        case .askFirst, .waitForBoundary:
            // Refused *for now*. When the user chooses to quit, the wind-down calls
            // `NSApp.terminate(_:)` again from the call boundary and that one goes through.
            return .terminateCancel
        }
    }
}
