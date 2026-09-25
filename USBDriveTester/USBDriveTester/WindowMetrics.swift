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
//  The window must fit a **13.3-inch Apple Silicon Mac** — the smallest Apple Silicon laptop — at
//  **1280x800** with the Dock showing (user decision, 2026-08-20). It was every scaling that
//  machine offers for one day, chosen from figures the gate was producing incorrectly; see the
//  correction below.
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
//      | 1280x800            |  800   |  700   the budget            |
//      | 1152x720            |  720   |  620   not a target          |
//
//  1152x720 was the target for one day and a standing claim after it ("fits outright", 2026-08-24).
//  **It is not maintained after 2026-09-24** (NFR-USE-9's amendment of that date): keeping a
//  second, tighter figure true was costing more than that scaling is worth, and nothing checks it.
//
//  The window's minimum measures **556 pt of content with one drive and 568 with two or more** —
//  a 588–600 pt window, which clears the 700 pt budget by 100 or more. The `starting` state is the
//  tallest, at 582 of content and a 614 pt window, and clears it by 86. Measured with `ui-probe` on
//  2026-09-24 against the Xcode 27.0 / macOS 27.0 build; a real window can read a few points
//  taller, for reasons ``deviceListFloor`` gives. Since that date the height a user can drag the
//  window to and the height its content fits are **the same number in every state** — the first
//  was 46–57 pt below the second until then.
//
//  **Those are observations, not assertions**, and deliberately not constants here: writing one
//  down would recreate exactly the literal this file exists to delete. `scripts/window-fit-check.sh`
//  is what checks them, and a row added three steps from now moves the measured minimum and the
//  gate says so.
//
//  ## The correction of 2026-08-20, and why the numbers above are not the ones first recorded
//
//  This file originally reported ~567 pt of content and a 599 pt window. Both came from
//  `NSWindow.contentMinSize` — what SwiftUI **declares** — and that number was **58 pt short in
//  every state**, for the reason ``deviceListFloor`` now records at length: a floor this file asks
//  for and the control ignores. A render at the declared minimum clips its header, and the shipped
//  app clamps 58 pt higher than the gate was reporting.
//
//  The gate now measures the laid-out hierarchy rather than reading the declaration, so the figures
//  above are the ones a user actually meets by dragging the window's edge.
//
//  **2026-09-24: on the Xcode 27 / macOS 27 build that last sentence was false**, and it is true
//  again for a different reason. That build's window does not clamp at the table's floor: it drags
//  down to the declaration, 46–57 pt short of the measured figures (not bisected — the SDK, the OS
//  or both). The declaration has been raised onto the measurement instead; ``deviceListFloor`` has
//  the account, and `window-fit-check.sh` now fails when the two part.
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
//  45 pt against the 46 pt floor, so one whole row already fits at the bottom of the range. (The
//  floor was 46 then. It is 104 since 2026-09-24, for a reason of its own; the fix still matters,
//  because two rows are still fewer than the drives a list that small can be holding.)
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

    /// The drive list's floor: **the height below which the table behind it will not lay out** —
    /// a measurement, asserted, which the header says is the kind of number this file exists to
    /// delete. Why it is here anyway is the point of this comment.
    ///
    /// The `List` in `DeviceListView` is backed by an AppKit table, and that table will not lay out
    /// below **the smaller of its own height and about 104 pt**, whatever `minHeight` it is handed.
    /// `ui-probe` reads 103 against the Xcode 27.0 / macOS 27.0 build (2026-09-24) — the same with
    /// 40 pt rows as with the real 46, so it is the table's own floor and not a count of rows — and
    /// below the list's own height with one or two drives, where `DeviceListView.listHeight` is
    /// under it. Hence `min(deviceListFloor, listHeight)` at the one use, which is what the table
    /// does anyway: without it SwiftUI resolves the contradictory frame to the minimum, silently,
    /// and a one-drive window's floor is 12 pt taller than it needs to be.
    ///
    /// **104 and not the probe's 103**, because the probe reads this table 1 pt short of a real
    /// window and the real window is the one a user drags: 542 against the shipped app's 543 on
    /// 2026-08-20, when setting this to 104 moved the declared minimum onto the enforced one
    /// exactly; and 567 against the 568 of content a real window was returned to by Window > Zoom
    /// on 2026-09-23, with a run finished and six drives attached, read off the window server.
    /// Given 104, the probe measures the frame this asks for, and the two numbers agree.
    ///
    /// **What would make it wrong, and what notices.** An SDK or OS that moves the table's floor.
    /// Upward, and the window can again be dragged to a height its content does not fit —
    /// `scripts/window-fit-check.sh` fails on exactly that, a state whose declared minimum is below
    /// its measured one. Downward, and the window's minimum is a few points taller than it has to
    /// be, which nothing checks and nothing needs to. With no drives attached the pane shows a
    /// placeholder rather than the table and keeps this floor; that case is unmeasured, because
    /// the probe's fleet is never empty.
    ///
    /// The placeholder is also what the **first** layout sees, because `ContentView` enumerates
    /// drives at `onAppear`. So for that moment the window's minimum is this floor's, and with one
    /// drive attached a window restored below 600 pt can open 12 pt taller than the one-drive
    /// minimum — nothing shrinks a window back. Seen in the probe, whose host has the same timing:
    /// a one-drive render asked for 556 comes out 568, and 556 again when only the placeholder's
    /// floor is put back to 46 (2026-09-24). Kept, knowingly: the placeholder's text does not
    /// compress, so a lower floor there is a band where it is cut off.
    ///
    /// ## 46 until 2026-09-24, knowingly ignored
    ///
    /// It was 46 pt — one row, `rowHeight` at the default text size — and known not to be
    /// honoured. Found on 2026-08-20 by resizing the shipped window with accessibility scripting:
    /// the table refused below roughly 104 pt, SwiftUI's `contentMinSize` believed the 46, and the
    /// declared window minimum came out **58 pt** below any height the content could occupy — the
    /// shape CONSTRAINTS records under "SwiftUI modifiers fail silently".
    ///
    /// It was left at 46 on two grounds: raising it would *assert* a number measured from that
    /// day's AppKit, and it would change nothing on screen, **because the window clamped at the
    /// table's floor anyway**. The second ground failed on the Xcode 27 / macOS 27 build, and
    /// nothing announced that either: its window does not clamp there. It drags down to the
    /// declaration, 46–57 pt short of where the content fits (not bisected — the SDK, the OS or
    /// both). Everything found at the bottom of the window's range on 2026-09-23 and 2026-09-24
    /// lived in that band: the drive-count heading under the title bar, the idle metrics box cut
    /// off, and Step 11 chunk 11 item 6's report sheet overhanging the window's bottom edge by
    /// 20 pt. Without the second ground the first is a price worth paying, and the gate's check is
    /// what keeps the assertion honest.
    ///
    /// One row was also chosen, on 2026-08-19, so that the window could cover every 13.3-inch
    /// scaling, 1152x720 included: two rows cost 46 pt that scaling did not have. That target was
    /// dropped on 2026-09-24 (NFR-USE-9's amendment of that date), and 1280x800 has the room.
    ///
    /// `rowHeight` is `@ScaledMetric` and this is not, which is now simply right: the table's floor
    /// is not a row. CONSTRAINTS section 1 records that Dynamic Type moves no font in this app on
    /// macOS in any case.
    static let deviceListFloor: CGFloat = 104

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

    // MARK: - The report sheet

    /// The margin left around the report sheet, so the window shows at its edges.
    ///
    /// **Cosmetic, and the only number in this file that is.** The sheet's *size* is not declared
    /// anywhere: `ContentView` hands it the window's measured content area less this margin on each
    /// axis, so it grows and shrinks with the window and can never exceed a screen the window
    /// itself fits (NFR-USE-9). What this decides is only whether the sheet reads as a sheet — a
    /// modal exactly covering its parent reads as the window having vanished.
    ///
    /// ("Can never exceed" was false on the Xcode 27 build until 2026-09-24, below about 600 pt:
    /// what `ContentView` measures is the content, and the window could be dragged shorter than
    /// it. That can no longer happen; see ``deviceListFloor`` and `ContentView.reportSheetSize`.)
    ///
    /// The report carried `minWidth: 620, minHeight: 560` while it was a window, chosen once for a
    /// surface the user could drag bigger. A sheet cannot be dragged, so the constant would have
    /// become a floor with no escape from it; deriving the size from the window deletes it rather
    /// than re-measuring it.
    static let reportSheetMargin: CGFloat = 24
}
