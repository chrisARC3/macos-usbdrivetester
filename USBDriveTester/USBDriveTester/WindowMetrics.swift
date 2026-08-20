//
//  WindowMetrics.swift
//  USBDriveTester (app target — unprivileged)
//
//  Step 11, increment 7. **How small the main window is allowed to get, and why that number is
//  not written down here.**
//
//  ## The problem this replaces
//
//  `ContentView` used to carry `.frame(minWidth: 640, minHeight: 760)`, where 760 was measured
//  once against a fixture drive and then asserted. Its own comment recorded that the constant
//  "has now expired twice" — 700 was true until Step 10 added the mounted-volumes row, true again
//  in increment 5, and false the moment increment 6 put two picker rows above Start. **Each
//  expiry was silent**, because nothing recomputes a literal.
//
//  So the total is no longer declared. Each pane that can scroll declares **its own floor**, every
//  other block contributes whatever it contributes, and SwiftUI sums them into the window's
//  minimum. Adding a row moves the minimum by construction. What is left in this file is the three
//  floors and a default size — design choices, not measurements of the current layout.
//
//  ## The budget it exists to satisfy — NFR-USE-9 (user decision 2026-08-19)
//
//  The requirement did not exist when this file was written. Investigating the window's size found
//  that **nothing in either requirements document said what it had to fit**, so there was nothing
//  to be in breach of; NFR-USE-9 was added in the docs pass of this increment to record the
//  decision. It asks for two things, and the second is the unusual one: that the window fit, and
//  that its minimum be **derived** rather than asserted.
//
//  The window must fit a **13.3-inch Apple Silicon Mac** — the smallest Apple Silicon laptop —
//  at every scaled resolution it offers, with the Dock showing.
//
//  That machine's panel is 2560x1600 **pixels**, which is the number to be careful with: macOS
//  lays windows out in **points**, and the panel is 2x, so its default "looks like" setting is
//  **1440x900 points**. The budget is 900 points and not 1600. Measured on the development Mac
//  rather than recalled: the title bar costs **32 pt**, the menu bar takes **30 pt** out of
//  `NSScreen.visibleFrame`, and a bottom Dock at the default tile size takes roughly 70 more.
//
//      | scaling on a 13.3"  | points | usable after menu bar + Dock |
//      |---------------------|--------|------------------------------|
//      | 1440x900 (default)  |  900   |  800                         |
//      | 1280x800            |  800   |  700                         |
//      | 1152x720            |  720   |  620                         |
//
//  With the floors below, the enforced minimum measures ~567 pt of content — a **599 pt window**,
//  which clears the tightest of those by 21 pt.
//
//  **That 567 is an observation, not an assertion**, and it is deliberately not a constant here:
//  writing it down would recreate exactly the literal this file exists to delete. It is checked by
//  `scripts/window-fit-check.sh`, which asks the real view hierarchy for the limits it hands a
//  window and fails if they no longer fit the budget. A row added three steps from now moves the
//  measured minimum and the gate says so.
//
//  ## What scrolls, and in what order (user decision 2026-08-19)
//
//  Three panes can give up height. When the window is shorter than the content wants, **the drive
//  list yields first, then the selected-device detail** — the list is a picker the user has
//  finished with by the time height is scarce, while the detail is what stands between them and
//  testing the wrong drive (NFR-USE-3). That reverses the previous behaviour, where the list was
//  rigid at `listHeight` and the detail absorbed every squeeze.
//
//  The metrics panel is the third, and it is a **bug fix** rather than a tidy-up: it had no scroll
//  region at all, and its `Spacer()`s let it report a small floor while having no way to show its
//  content in that space. It claimed to fit and then clipped — observed on hardware at minimum
//  height, with the bottom three lines of a run in progress cut off (user, 2026-08-19).
//
//  A pane that can fall to one row also has to keep the *right* row on screen, which is a separate
//  problem from how much height it gets. `DeviceListView` scrolls the list the minimum distance
//  needed to keep the selected drive visible whenever this pane's height changes — added
//  2026-08-20, after chunk 9.3 found the chosen drive off screen altogether at the minimum, with
//  the "Selected device" pane naming a drive the list was not showing. It costs no height at all,
//  which is why ``deviceListFloor`` did not have to move for it: the selection capsule measures
//  45 pt against the 46 pt floor, so one whole row already fits at the bottom of the range.
//
//  `nonisolated` for the reason `RunControlState.swift` records: the app target compiles with
//  SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, which would otherwise make even these constants
//  main-actor-isolated and unreachable from the non-isolated test target.
//

import CoreGraphics

/// The main window's size policy (NFR-USE-9).
///
/// Only floors and a default size. **The minimum height is not here** — see this file's header for
/// why deriving it is the whole point.
nonisolated enum WindowMetrics {

    // MARK: - Floors for the panes that scroll

    /// The drive list's floor: **one row**.
    ///
    /// 46 pt is `DeviceListView.rowHeight`'s value at the default text size.
    ///
    /// **It does not scale with it, and that is worth stating rather than leaving to be assumed.**
    /// `rowHeight` is `@ScaledMetric`; this is a plain constant, so at a larger text size the rows
    /// grow past it and the floor stops being exactly one row. The consequence is bounded — the
    /// list scrolls, so a floor slightly under one row costs a sliver of a row and not a feature —
    /// and it is preferred to the alternative, which is a floor that grows the window's minimum
    /// height on the machines least able to spare it.
    ///
    /// It is also, today, moot: CONSTRAINTS section 1 records that Dynamic Type moves no font in
    /// this app on macOS — measured offscreen, then confirmed at the keyboard with the System
    /// Settings slider. `@ScaledMetric` here would be a lever that looks live and does nothing,
    /// which is the specific trap the deleted `dynamicTypeSize` render axis was removed to avoid.
    ///
    /// One row rather than two is a consequence of two user decisions taken together (2026-08-19):
    /// cover every 13.3-inch scaling, and let the list yield before the detail pane. Two rows cost
    /// 46 pt that the tightest scaling does not have. It applies only at the very bottom of the
    /// window's range, where the list scrolls; at any ordinary height the list is at
    /// `DeviceListView.listHeight` as before.
    static let deviceListFloor: CGFloat = 46

    /// The selected-device detail's floor: the identity line plus one row.
    ///
    /// Enough that the pane always answers "which drive is this?" — the question NFR-USE-3 exists
    /// for — with the rest reachable by scrolling. It was already a `ScrollView`; what it lacked
    /// was a declared floor, so it was the only thing absorbing every squeeze in the window.
    static let deviceDetailFloor: CGFloat = 104

    /// The live metrics panel's floor, in **both** its states: its heading, with the figures
    /// scrolling beneath when there are figures, and the placeholder's two lines when there are not.
    ///
    /// - Important: it was briefly removed for the idle panel on 2026-08-20, on the theory that a
    ///   97 pt floor to show two lines of copy was making every window taller than it needed to be.
    ///   **Every state's reported minimum did fall by 30 pt, and every one of those windows
    ///   clipped**: with no floor, this panel became the only pane without one, so it absorbed the
    ///   whole shortfall at the window's minimum and its second line was cut in half. The floor was
    ///   never the reason for the empty box the user asked to remove — the *ceiling* was.
    ///
    /// Measured as the panel's own chrome — the `GroupBox` label and padding — with every
    /// measurement section removed: 97 pt at the body text size. The panel's *ideal* height is
    /// 205 pt, which is that chrome plus the progress row, so at any window height above the
    /// minimum the progress bar is visible without scrolling. The floor is the corner case, not
    /// the normal one.
    ///
    /// The heading stays pinned because the scroll region is **inside** the `GroupBox`, the same
    /// arrangement `DeviceListView` uses: a panel that scrolls its own title away leaves figures
    /// on screen with nothing saying what they are.
    static let metricsFloor: CGFloat = 97

    /// The metrics panel's ideal **while it has figures to show**: heading plus the progress row
    /// (FR-METR-5).
    ///
    /// Declared so the panel asks for the progress bar rather than merely tolerating it. Between
    /// this and ``metricsFloor`` the panel compresses; above it, it grows with the window like the
    /// other two panes.
    static let metricsIdeal: CGFloat = 205

    // MARK: - The window

    /// The narrowest useful width.
    ///
    /// Unchanged from the constant it replaces, and unchanged for a reason: **horizontal space was
    /// never the problem**. Every text block in the window is `fixedSize` under its own `maxWidth`
    /// cap, so the required height does not move at all between 640 and 900 pt of width (measured
    /// 2026-08-19), and 640 pt fits every Mac ever shipped.
    static let minimumContentWidth: CGFloat = 640

    /// What a first launch opens at, and **the reason this type exists at all is partly this**.
    ///
    /// The main window declared no `.defaultSize`, and the content's maximum height is unbounded
    /// — the metrics panel's `Spacer()`s make it so, which is also why `render-ui.sh` records that
    /// the probe's height argument behaves as "a floor, not a ceiling". A scene with no declared
    /// size and no maximum opens **as tall as the screen allows**: measured at 1328 pt on a 1410 pt
    /// display, against content that wanted 675.
    ///
    /// Sized to the comfortable height rather than the minimum: at 700 pt nothing scrolls at one
    /// drive, and macOS constrains it down on a screen that cannot spare it. It is only consulted
    /// when no frame has been saved — AppKit's frame autosave wins afterwards, which is why a
    /// window that was once screen-height stays that way until the saved frame is cleared.
    static let defaultContentHeight: CGFloat = 700

    /// The width a first launch opens at — wider than the minimum, since the device rows and the
    /// report figures both read better with room.
    static let defaultContentWidth: CGFloat = 720
}
