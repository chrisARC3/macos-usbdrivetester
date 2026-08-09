//
//  MainWindowCloseGuard.swift
//  USBDriveTester (app target — unprivileged)
//
//  Makes closing the main window during a run ask the same question ⌘Q asks (user decision,
//  2026-08-05: the same dialog for both entry points).
//
//  ## Why this reaches into AppKit
//
//  SwiftUI has no cancellable "about to close" hook for a window — `onDisappear` runs after the
//  fact, and `dismiss` is an instruction rather than an interception. AppKit's is
//  `NSWindowDelegate.windowShouldClose(_:)`, and SwiftUI's scene windows already have a delegate
//  of their own. So this proxies it: `windowShouldClose(_:)` is answered here, and every other
//  message is forwarded to SwiftUI's own controller untouched.
//
//  ## What was measured before this was written
//
//  A scratch scene probe on macOS 26 (2026-08-05), because "proxy a framework's private delegate"
//  is exactly the kind of thing that appears to work and quietly breaks the framework's
//  bookkeeping:
//
//  | | measured |
//  |---|---|
//  | SwiftUI's window / delegate | `AppKitWindow` / `AppKitWindowController` |
//  | proxy returning `false` | close refused, window still visible |
//  | proxy returning `true` | window closed |
//  | reopening from the Window menu afterwards | **worked** — so `windowWillClose:` reached the real controller through the forward and the scene's own state stayed right |
//
//  That last row is the one that mattered. Had the forward not carried SwiftUI's own messages, the
//  symptom would have been a window that closes once and can never be reopened — a defect that
//  only shows up two steps later.
//
//  ## How it fails
//
//  **Open**, and that is deliberate. If the window cannot be found, or a future macOS stops
//  routing closes through the delegate, the guard simply never fires and the window closes without
//  asking — which is exactly what the app did before this existed. It cannot fail into abandoning
//  a run, because closing the main window does not end a run: the run belongs to `AppModel`'s
//  connection, not to the window, and the window can be brought back from the Window menu. The
//  path that *can* abandon a run is termination, and that is guarded independently in
//  `AppLifecycleDelegate` with no AppKit archaeology in it at all.
//
//  ## Why exactly one window can be guarded, and why that is now safe
//
//  This object is a single delegate for a single window. Attaching it to a second window would
//  leave the first forwarding to the second's controller. That was a real hazard while the main
//  scene was a `WindowGroup` — ⌘N would have made a second main window — and it is not one now:
//  increment 3 made the main scene a `Window`, so there is exactly one. The diagnostics window is
//  deliberately *not* guarded: closing it affects no run, because the connection and the claim
//  live in `AppModel`.
//

import AppKit
import SwiftUI

/// Answers `windowShouldClose(_:)` for the main window, forwarding everything else to SwiftUI.
@MainActor
final class MainWindowCloseGuard: NSObject, NSWindowDelegate {

    /// Consulted on every close attempt. Weak because `AppModel` owns this object — the reference
    /// back to it must not be a cycle.
    weak var model: AppModel?

    /// SwiftUI's own delegate, kept so that every message this class does not implement still
    /// reaches it. Weak, because the window's controller belongs to SwiftUI.
    private weak var swiftUIDelegate: NSWindowDelegate?

    /// Insert this object in front of `window`'s existing delegate.
    ///
    /// Idempotent, and the guard is load-bearing rather than an optimisation: attaching twice
    /// would set `swiftUIDelegate` to `self` and turn the forward into an infinite loop.
    func attach(to window: NSWindow) {
        guard window.delegate !== self else { return }
        swiftUIDelegate = window.delegate
        window.delegate = self
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // No model means the app is not up yet, so there is no run to protect.
        guard let model else { return true }

        switch model.mainWindowCloseRequested() {
        case .allowClose:
            return true

        case .allowCloseAndQuit:
            // **After the close, not during it.** `windowShouldClose` is asked *whether* the
            // window may close; the window has not closed yet at this point, and terminating from
            // inside the answer would have AppKit tearing the app down through a delegate call it
            // is still waiting on. One turn of the run loop later, the close has completed and the
            // termination is an ordinary one — which is what makes it go through
            // `applicationShouldTerminate` and pick up the same guard as ⌘Q.
            DispatchQueue.main.async { [weak model] in
                model?.quitBecauseTheMainWindowClosed()
            }
            return true

        case .askFirst, .refuseSilently:
            // The window never closes as part of a confirmed quit: either the app terminates and
            // takes it, or the user chose to keep testing and it stays exactly where it was.
            return false
        }
    }

    // MARK: - Forwarding

    override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return swiftUIDelegate?.responds(to: aSelector) ?? false
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if super.responds(to: aSelector) { return nil }
        return swiftUIDelegate
    }
}

/// Attaches the app's ``MainWindowCloseGuard`` to whichever window this view lands in.
///
/// The same shape as `TableSelectionPolicy` in `DeviceListView`, including the one-turn deferral:
/// on the first layout pass the view exists before it has a window, so looking now would find
/// nothing and silently do nothing.
struct MainWindowCloseGuardInstaller: NSViewRepresentable {

    let closeGuard: MainWindowCloseGuard

    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            closeGuard.attach(to: window)
        }
    }

    // No `dismantleNSView`: the guard is owned by `AppModel` and outlives every window, and it
    // forwards everything it does not implement — so leaving it installed changes nothing, while
    // detaching it mid-close would mean clearing a delegate out of a window that is using it.
}
