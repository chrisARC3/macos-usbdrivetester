//
//  WindowMetricsTests.swift
//  The main window's size policy (Step 11, increment 7). NFR-USE-9.
//
//  ## What this suite is NOT
//
//  It is not the check that the window fits a 13.3-inch Mac. **It cannot be**, and being clear
//  about that is the point of this header: a unit test cannot lay out SwiftUI, so it cannot know
//  what these floors add up to once the blocks that do not scroll are included, and it cannot see
//  that the `starting` state's three refusal sentences each gain a line at 640 pt wide. Nothing
//  here would have caught any of the four defects increment 7 was opened for.
//
//  `scripts/window-fit-check.sh` is that gate. It asks the real view hierarchy, through
//  `ui-probe --limits`, for the limits it hands a window and compares them to a screen budget.
//  A test asserting `metricsFloor == 97` would restate the source and prove nothing, and would
//  make this file *look* like the cover it is not — which is worse than leaving it empty.
//
//  ## What this suite is for
//
//  The relationships **between** these numbers, which are the part a careless edit can invert
//  without any layout being involved. Each assertion below fails on a plausible edit rather than
//  on a hypothetical one:
//
//    * a default size that is smaller than the minimum is silently clamped by AppKit, so the
//      declared default becomes a lie that no render would show;
//    * an ideal below its own floor is incoherent — `.frame(minHeight:idealHeight:)` with those
//      the wrong way round resolves to something neither number describes;
//    * a floor of zero or a negative one compiles, lays out, and quietly removes the guarantee
//      the constant exists to make.
//
//  The reason each of these is worth a test rather than a comment is `WindowMetrics`'s own
//  history: the file exists because a single measured literal in `ContentView` expired three
//  times, silently. Numbers in this project are not assumed to stay true.
//

import Testing
import CoreGraphics
@testable import USBDriveTester

// MARK: - The floors

struct WindowMetricsFloorTests {

    /// Every floor is a real, positive length.
    ///
    /// Walked as a table rather than asserted one at a time, for the reason `PreRunControlsTests`
    /// gives: a suite that checks the constants somebody remembered lets a later addition go
    /// uncovered. A constant added to `WindowMetrics` and not added here is the gap; naming them
    /// together at least puts the omission in one visible place.
    @Test func everyDeclaredLengthIsPositiveAndFinite() {
        let declared: [(String, CGFloat)] = [
            ("deviceListFloor", WindowMetrics.deviceListFloor),
            ("deviceDetailFloor", WindowMetrics.deviceDetailFloor),
            ("metricsFloor", WindowMetrics.metricsFloor),
            ("metricsIdeal", WindowMetrics.metricsIdeal),
            ("minimumContentWidth", WindowMetrics.minimumContentWidth),
            ("defaultContentWidth", WindowMetrics.defaultContentWidth),
            ("defaultContentHeight", WindowMetrics.defaultContentHeight),
        ]
        for (name, value) in declared {
            #expect(value > 0, "\(name) is \(value); a floor of zero removes the guarantee silently")
            #expect(value.isFinite, "\(name) is \(value)")
        }
    }

    /// The metrics panel's ideal is not below its own floor.
    ///
    /// These two are handed to one `.frame(minHeight:idealHeight:maxHeight:)`, and inverted they
    /// resolve to something that is neither — a panel that asks to be smaller than it insists on
    /// being. It is also the pair most likely to be edited carelessly, because tightening the
    /// panel means moving one of them and it is not obvious which.
    @Test func theMetricsIdealIsAtLeastItsFloor() {
        #expect(WindowMetrics.metricsIdeal >= WindowMetrics.metricsFloor)
    }

    /// The metrics ideal leaves room for something above the heading.
    ///
    /// `metricsFloor` is the panel's chrome alone — heading and padding, with every measurement
    /// scrolled. `metricsIdeal` is documented as that plus the progress row, which is what makes
    /// FR-METR-5's progress bar visible without scrolling at any height above the minimum. An
    /// ideal *equal* to the floor would satisfy the check above while quietly meaning "heading
    /// only", so the difference is asserted rather than the ordering alone.
    @Test func theMetricsIdealClearsTheHeadingByARowOrMore() {
        #expect(WindowMetrics.metricsIdeal - WindowMetrics.metricsFloor >= 40)
    }
}

// MARK: - The window

struct WindowMetricsDefaultSizeTests {

    /// A default narrower than the minimum is not a default — AppKit clamps it, and the declared
    /// number becomes something the window never has.
    @Test func theDefaultWidthIsAtLeastTheMinimum() {
        #expect(WindowMetrics.defaultContentWidth >= WindowMetrics.minimumContentWidth)
    }

    /// The window does not open already compressed.
    ///
    /// The floors are what each scrolling pane keeps when there is *nothing to spare*. A default
    /// height at or below their sum would mean a fresh install opens with all three panes already
    /// at their floors and content scrolled away — which is the state the minimum exists to make
    /// survivable, not the state to greet a user with.
    ///
    /// Deliberately a weak bound: the real opening height also carries the device header, the run
    /// controls and every divider, none of which a unit test can measure. It catches a default set
    /// to something small, and it does not pretend to be `window-fit-check.sh`.
    @Test func theDefaultHeightIsWellAboveTheDeclaredFloors() {
        let floors = WindowMetrics.deviceListFloor
                   + WindowMetrics.deviceDetailFloor
                   + WindowMetrics.metricsFloor
        #expect(WindowMetrics.defaultContentHeight > floors)
    }

    /// The default fits the screen it was chosen for.
    ///
    /// 700 pt of content plus the measured 32 pt title bar is 732, against the 800 pt a 13.3-inch
    /// Mac has at its default scaling with the Dock showing. A default taller than that opens
    /// clamped on the machine the budget was written for, which is exactly the "opens far larger
    /// than it needs to" complaint that started this increment — arriving by a different route.
    ///
    /// The two constants here are measured facts about macOS rather than choices this project
    /// makes, which is why they are spelled out at the call site: `window-fit-check.sh` carries
    /// the same pair, and the comment there records how they were measured.
    @Test func theDefaultHeightFitsTheSmallestSupportedScreen() {
        let titleBar: CGFloat = 32
        let budgetAtDefaultScaling: CGFloat = 800
        #expect(WindowMetrics.defaultContentHeight + titleBar <= budgetAtDefaultScaling)
    }
}
