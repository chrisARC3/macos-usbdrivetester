//
//  DeviceListView.swift
//  USBDriveTester (app target — unprivileged)
//
//  The device list and the selected-device detail (FR-DEV-1/3/4/6, NFR-USE-3).
//
//  Unlike the Step 3/4 harness this replaces at the top of the window, this is intended
//  to survive: Steps 9, 11 and 14 add run controls, metrics and the mandatory warnings
//  *around* it, not instead of it.
//
//  ## Design notes
//
//  A real `List` with a selection binding rather than buttons in a `Form` row. It is
//  the correct control for "choose exactly one of these", and it brings keyboard
//  navigation and VoiceOver selection semantics with it rather than requiring them to
//  be rebuilt (NFR-USE-8).
//
//  Every row leads with the **BSD name**, because that is the one identifier that ties
//  what this window says to `diskutil`, to `/dev/rdiskN`, and to what the helper will
//  be told to open. Model and capacity follow, so the row can be matched against the
//  label on the physical drive (FR-DEV-6). The detail panel below repeats the identity
//  in full and adds the exact byte count, which is what makes the rounded capacity safe
//  to show at all (NFR-USE-3).
//
//  Status is never carried by colour alone — every state has an icon and words
//  (NFR-USE-8), a habit Step 14 turns into a gate.
//

import SwiftUI
import os

private nonisolated let log = Logger(subsystem: HelperIdentity.loggingSubsystem,
                                     category: "safety")

struct DeviceListView: View {

    let discovery: DeviceDiscovery

    /// Shared with `HelperDiagnosticsView` rather than opened again here: one
    /// `NSXPCConnection` to the daemon per app, so a connection dropping means one thing
    /// and the helper sees one client. It also matters for Step 6 specifically — the
    /// helper releases a claim when the connection that took it goes away, so two
    /// connections would mean two different owners of the same device.
    let helper: HelperConnection

    /// Approximate height of one two-line device row, scaled with the user's text size.
    ///
    /// `@ScaledMetric` rather than a constant because the list's height is derived from
    /// it (see `deviceList`): a hard-coded row height would clip rows at larger Dynamic
    /// Type settings, which is a worse outcome than the dead space it is there to
    /// remove (NFR-USE-8).
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 46

    // MARK: - Step 6 state (FR-SAFE-3/4/5/7)

    @State private var mounter = VolumeMounter()

    /// What the helper last said about the selected device. `nil` before the first check,
    /// or when the helper could not be reached.
    @State private var readiness: DeviceReadiness?

    /// Why the helper could not be asked, if it could not. Shown rather than swallowed:
    /// "no banner" and "the helper says everything is fine" must not look the same.
    @State private var readinessError: String?

    /// Shared app state. This view is where a device is acquired and released, and the
    /// diagnostics *window* needs to know whether one is held before it can offer to run a
    /// cycle — so that fact cannot live in either view's `@State`.
    @Environment(AppModel.self) private var model

    /// Whether the helper holds exclusive access to the selected device. Changed immediately by
    /// acquire and release rather than waiting for the next readiness check to come back.
    ///
    /// Read-only here and written through `model` so there is exactly one copy: a mirrored
    /// `@State` would be a second answer to a question that already has one, and the two would
    /// eventually disagree about whether a run may be offered.
    private var helperHoldsDevice: Bool { model.helperHoldsDevice }

    @State private var mountOperationInFlight = false
    @State private var accessOperationInFlight = false

    /// Keyboard focus for the device list.
    ///
    /// ## Why the list is focused on launch (2026-08-05, user decision)
    ///
    /// `List`'s selection chrome renders in the accent colour only while the list holds keyboard
    /// focus, and in grey otherwise. So the app's **own** default selection — FR-DEV-3's, made by
    /// the app before the user has touched anything — was the one that looked tentative, and a
    /// click was needed to make it look chosen. Two visual states for one logical state, at the
    /// moment the user is deciding which drive they are about to write to.
    ///
    /// That ambiguity is not a cosmetic one here. The selected device is the line that stands
    /// between the user and testing the wrong drive (NFR-USE-3); "is that actually selected?" is
    /// exactly the question this screen must never raise.
    ///
    /// ## The fix is genuine first responder, not a drawn imitation (user decision)
    ///
    /// Custom-drawing a selected background was rejected: the row must be *actually* selected,
    /// exactly as a click leaves it. So this focuses the list and lets AppKit draw what it always
    /// draws — which also keeps ↑/↓ navigation and VoiceOver's selection semantics, both of which
    /// a hand-drawn highlight would have silently cost.
    ///
    /// ## What was measured, because two mechanisms look identical from the outside
    ///
    /// `tools/ui-probe` reports `window.firstResponder` at capture time, so "is the list actually
    /// focused" is a fact rather than an inference from a colour:
    ///
    /// | mechanism | firstResponder | highlight |
    /// |---|---|---|
    /// | `.defaultFocus($deviceListHasFocus, true)` | `NSWindow` — nothing took it | grey |
    /// | `.focused(…)` + assignment deferred one run-loop turn | `SwiftUIOutlineListView` | **blue** |
    ///
    /// The deferral is the whole difference: at `onAppear` the view is not yet in a key window and
    /// the focus request is dropped.
    @FocusState private var deviceListHasFocus: Bool

    /// The last mount/unmount or acquire/release result, shown verbatim.
    @State private var lastOutcome: OutcomeMessage?


    private struct OutcomeMessage: Equatable {
        let ok: Bool
        let text: String
    }

    /// The failure currently being shown modally, or `nil`.
    ///
    /// Separate from ``lastOutcome`` rather than derived from it: the dialog is dismissed while the
    /// inline copy stays, so one value cannot represent both. Deriving the alert's presentation
    /// from `lastOutcome != nil && !ok` would re-raise the dialog on the next unrelated redraw.
    @State private var alert: OutcomeAlert?

    private struct OutcomeAlert: Identifiable, Equatable {
        let title: String
        let text: String
        var id: String { title + text }
    }

    // MARK: - The one place the user-visible outcome is written

    /// Show `text` to the user, and record that it was shown (NFR-OBS-1).
    ///
    /// ## Why every write goes through here
    ///
    /// On 2026-08-09 the unmount rollback's error message was reported as **never appearing**,
    /// across three test cases whose behaviour was otherwise exactly right. With ten scattered
    /// assignments to `lastOutcome` and no logging anywhere near them, "never set" and "set, then
    /// cleared a moment later" produce the identical observation — a blank pane — and the only
    /// available instrument was a person watching the screen and trying to catch it.
    ///
    /// That is the same shape as every other defect this control has produced: a state that
    /// cannot be distinguished from a different state by anything the project can measure. One
    /// funnel with a log line in it makes the two distinguishable, and costs nothing.
    /// - Parameter operation: what the outcome is about, so a failure's dialog can be headed with
    ///   what failed rather than with a generic banner.
    private func present(ok: Bool, _ text: String, from operation: OutcomeOperation) {
        let route = OutcomePresentation.forOutcome(ok: ok, operation: operation)

        // The inline copy is kept on every route that shows anything. The alert guarantees a
        // failure is seen once; the inline copy is what lets it be re-read and text-selected after
        // the dialog is dismissed.
        //
        // `.silent` leaves `lastOutcome` as the operation's own start already left it — nil — so
        // nothing is displayed. It is NOT written and then hidden: a value on screen and a value
        // in state that disagree is the defect this funnel exists to make impossible.
        if route.showsInline {
            lastOutcome = OutcomeMessage(ok: ok, text: text)
        }

        if case .interrupt(let title) = route {
            alert = OutcomeAlert(title: title, text: text)
        }

        log.notice("""
                   outcome shown (\(ok ? "ok" : "error", privacy: .public)) as \
                   \(route.logName, privacy: .public): \(text, privacy: .public)
                   """)
    }

    /// Clear the outcome, saying **why** — the half that makes a vanished message diagnosable.
    ///
    /// Silent when there was nothing to clear, so the log records erasures rather than every
    /// no-op pass through a code path that happens to reset state.
    private func clearOutcome(_ reason: String) {
        guard lastOutcome != nil else { return }
        log.notice("outcome cleared: \(reason, privacy: .public)")
        lastOutcome = nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            deviceList
            Divider()
            detail
        }
        // The selected device changing invalidates everything below: a readiness answer
        // is about one device, and showing one device's mount state under another's name
        // is precisely the confusion NFR-USE-3 exists to prevent.
        .onChange(of: discovery.selectedDeviceID) { _, _ in
            readiness = nil
            readinessError = nil
            clearOutcome("the selected device changed")

            // ## The claim follows the selection (2026-08-05, user decision)
            //
            // Holding exclusive access to a drive the UI does not name as selected is a mismatch
            // between what the app shows and what it actually controls — so the claim is released
            // the moment the selection stops naming it, whether that is a deselection or a switch
            // to another drive.
            //
            // This also *removes* rather than works around the stale-claim defect noted earlier:
            // `helperHoldsDevice` is written from `helperHoldsThisDevice`, a per-device answer,
            // while every use site reads it as "the helper holds some device". Those two can only
            // disagree when the held device and the selected device differ — which this rule makes
            // impossible. It is no longer cleared speculatively here; `release()` clears it when
            // the helper confirms, and `refreshReadiness()` sets it from the helper otherwise.
            //
            // Safe against releasing mid-write because the selection cannot change during a run.
            // That guard is enforced in `DeviceDiscovery.select`/`deselect`, not here and not
            // only in the view: it is the one thing standing between a stray ⌘-click and a claim
            // dropped under an active write, so it belongs where every caller must pass through
            // it and where a test can hold it.
            if model.helperHoldsDevice,
               model.heldDeviceName != discovery.selectedDevice?.bsdName.rawValue {
                release()
            }

            refreshReadiness()
        }
        // The mounted-volume set changing is the other input the banner depends on, and
        // it changes without the selection changing — the user unmounts in Disk Utility,
        // or macOS remounts after a claim is released.
        .onChange(of: discovery.selectedDevice?.mountedVolumeNames ?? []) { _, _ in
            refreshReadiness()
        }
        .onAppear { refreshReadiness() }
        // A failed mount/unmount/acquire/release interrupts (user decision 2026-08-09). The
        // message it replaces was correct and never seen: it was the last element inside the
        // detail pane's ScrollView, below the fold on a drive with several mounted volumes.
        //
        // **Step 11 must carry this with the sequence, not leave it here.** Start takes over
        // unmount → acquire → run → release and deletes the pane this is attached to, and the
        // failure it reports is exactly the one that strands a user with a half-unmounted drive.
        // An alert attached to a deleted view is an error path with nowhere to surface.
        .alert(alert?.title ?? "",
               isPresented: Binding(get: { alert != nil },
                                    set: { presented in if !presented { alert = nil } }),
               presenting: alert) { _ in
            Button("OK", role: .cancel) { }
        } message: { alert in
            Text(alert.text)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(discovery.summary)
                    .font(.headline)
                Spacer()
                // With no Refresh button, this timestamp is the only visible evidence that the
                // list is current — so it earns its place rather than merely surviving the
                // button's removal.
                if let lastRefresh = discovery.lastRefresh {
                    Text("Updated \(lastRefresh, format: .dateTime.hour().minute().second())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // The list maintains itself (FR-DEV-7): `deviceSetChanged()` refreshes on every IOKit
            // arrival and departure, `DeviceSelectionPolicy` keeps the user's selection while the
            // drive it names is still present, and a change deferred during a run is applied when
            // the run ends.
            //
            // ## Why there is no Refresh button (removed 2026-08-05, user decision)
            //
            // USB is hot-pluggable and the list is already driven by arrival/departure
            // notifications, so the button was redundant in normal operation — and worse than
            // redundant during a run. `refresh()` **bypasses the freeze** by design, on the
            // reasoning that an explicit call is a deliberate act; but FR-DEV-7 freezes the list
            // during a run precisely so it cannot rebuild underneath one, and the banner below
            // says so. A user pressing a button next to that banner is not deliberately
            // overriding a safety freeze. The `refresh()` *method* stays — Step 12's
            // post-device-loss re-run of discovery (FR-DEV-8) is exactly the deliberate act the
            // comment describes.
            if let explanation = discovery.freezeExplanation {
                Label(explanation, systemImage: "pause.circle.fill")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("The list updates as drives are connected and disconnected.",
                      systemImage: "arrow.triangle.2.circlepath")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    // MARK: - The list

    private var deviceList: some View {
        Group {
            if discovery.devices.isEmpty {
                emptyState
            } else {
                List(discovery.devices, selection: selectionBinding) { device in
                    row(for: device)
                        .tag(device.registryEntryID)
                        // Frozen during a run, for the same reason the list is (FR-DEV-7) and one
                        // sharper one: the claim follows the selection, so a change mid-run would
                        // release the device out from under an active write.
                        //
                        // On the **row**, not on the `List`. `selectionDisabled` is a per-row
                        // modifier; applied to the container it compiles, renders, and silently
                        // does nothing — which is exactly what happened, and the run-state
                        // stand-in went straight through it.
                        //
                        // `selectionDisabled` rather than `disabled`: the latter would also stop
                        // scrolling, and NFR-PERF-4 requires the window to stay scrollable
                        // throughout a run.
                        .selectionDisabled(discovery.isRunActive)
                }
                .listStyle(.inset)
                // So FR-DEV-3's default selection reads as selected from the first frame rather
                // than as a grey maybe. See `deviceListHasFocus`.
                .focused($deviceListHasFocus)
                .onAppear {
                    // Deferred by one run-loop turn deliberately. At `onAppear` the view is not
                    // yet in a key window, and a focus request made then is dropped on the floor
                    // — measured, not assumed: `.defaultFocus($deviceListHasFocus, true)` left
                    // `window.firstResponder` as the NSWindow itself.
                    DispatchQueue.main.async { deviceListHasFocus = true }
                }
                // ## Preventing the deselection instead of undoing it (2026-08-05)
                //
                // Two attempts to *restore* the highlight after the store declined both failed,
                // and the log convicted each in turn:
                //
                // 1. Bump an observable token and read it in the body, expecting the re-render to
                //    make `List` re-apply its binding. It does not — `List` pushes selection down
                //    only when the bound *value* changes, and a refusal does not change it.
                // 2. Drive `.id()` from that token to force a rebuild. Also no: with the trigger
                //    provably firing, ⌘-click still left the row deselected.
                //
                // So the highlight cannot be put back after the fact. It has to not leave.
                // `allowsEmptySelection` is the AppKit switch that makes ⌘-click and clicks below
                // the last row unable to clear a selection, and it is genuine table behaviour —
                // the selection stays real, nothing is drawn by hand.
                //
                // Held off only while a run is active, because deselection is wanted the rest of
                // the time: it releases the device (user decision 2026-08-05).
                .background(TableSelectionPolicy(allowsEmptySelection: !discovery.isRunActive))
            }
        }
        .frame(height: listHeight)
    }

    /// Sized to its content, floored so the empty state has room and capped so a
    /// machine with many drives attached scrolls the list instead of squeezing the
    /// selected-device detail off the bottom of the window.
    ///
    /// An uncapped `List` inside a `VStack` absorbs every spare point of height, which
    /// put three drives above a large gap and pushed the detail — the part that stops
    /// the wrong drive being tested — down to the window edge.
    private var listHeight: CGFloat {
        guard !discovery.devices.isEmpty else { return 160 }
        let content = CGFloat(discovery.devices.count) * rowHeight + 16
        return min(max(content, rowHeight * 2), 260)
    }

    /// Bridges the store's `select(_:)` to a `List` selection binding. The store owns
    /// the selection and validates it, so the setter delegates rather than assigning.
    private var selectionBinding: Binding<UInt64?> {
        Binding(get: { discovery.selectedDeviceID },
                // `nil` is a real deselection (⌘-click, or a click below the last row) and is
                // passed through rather than dropped. Dropping it was the stale-pane defect: the
                // table deselected, the store did not, and nothing below ever heard about it.
                // Worth knowing before adding logic here: a ⌘-click on the **already-selected**
                // row arrives as `select(thatSameID)`, not as the `nil` a deselection would
                // suggest (measured 2026-08-05, from the unified log). An attempt to detect
                // declines by comparing the requested id against the stored one was built on the
                // opposite assumption and never fired once.
                set: { if let id = $0 { discovery.select(id) } else { discovery.deselect() } })
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            // Decorative — "No USB drives connected" below says it.
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No USB drives connected")
                .font(.headline)
            Text("""
                 Connect a USB mass-storage drive. Internal disks are deliberately \
                 excluded — this tool writes raw blocks, so only external USB devices \
                 are ever listed.
                 """)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private func row(for device: DiscoveredDevice) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: device.isSelectable
                  ? "externaldrive.fill"
                  : "externaldrive.trianglebadge.exclamationmark")
                .font(.title3)
                .foregroundStyle(device.isSelectable ? .primary : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayTitle)
                    .fontWeight(.medium)
                Text(rowSubtitle(for: device))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !device.isSelectable {
                Label("Unusable", systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: device))
    }

    /// `1.00 TB · Solid State · Test_Drive`
    private func rowSubtitle(for device: DiscoveredDevice) -> String {
        var parts = [device.capacityDescription]
        if let medium = device.mediumType {
            parts.append(medium)
        }
        // The serial is in the row, not only in the detail pane, because the row is what the user
        // scans when choosing — and the BSD name beside it is a locator, not an identity
        // (assigned at enumeration, different after any replug).
        parts.append(device.serialSummary)
        if let volumes = device.mountedVolumesDescription {
            parts.append(volumes)
        }
        return parts.joined(separator: " · ")
    }

    /// Spoken as one phrase rather than as five separate fragments, and it says "unusable" in words
    /// rather than relying on the badge.
    ///
    /// Screen-reader support left scope on 2026-08-11 (user decision; NFR document, amendment of
    /// that date), so this is retained voluntarily rather than required. The *visual* half of the
    /// same idea — the badge saying "Unusable" in words beside a distinct icon — is still
    /// NFR-USE-8's colour rule, and is rendered by the `devices-unusable` probe case.
    private func accessibilityLabel(for device: DiscoveredDevice) -> String {
        var label = "\(device.bsdName), \(device.modelDescription), "
                  + "\(device.capacityDescription)"
        if let volumes = device.mountedVolumesDescription {
            label += ", mounted volumes: \(volumes)"
        }
        if !device.isSelectable {
            label += ", cannot be tested"
        }
        return label
    }

    // MARK: - Selected-device detail

    /// The selected-device panel, and below it the safety controls.
    ///
    /// The safety section renders whether or not anything is selected. FR-SAFE-5
    /// specifies the no-selection state of the control — *disabled*, showing the default
    /// label "Unmount All" — and a control that is absent is not a control that is
    /// disabled. Showing it greyed out with a reason also answers the question a missing
    /// button raises ("can this app even do that?") without the user having to select a
    /// drive to find out.
    /// ## The controls are PINNED OUTSIDE the scroll region, and that is a bug fix (2026-08-11)
    ///
    /// They used to sit inside it, below the device-identity block. Reported in real use: **"Run one
    /// bounded cycle" stays disabled no matter what I do** — because its precondition is a held
    /// device, holding one needs `Acquire exclusive access`, and at the window's own
    /// `minHeight: 700` that button was **not on screen at all**. Measured, not inferred: rendered
    /// at 640×700 the whole `Mounting & exclusive access` section is absent, and it appears at 760.
    ///
    /// **Raising `minHeight` would not have fixed it**, which is why this is a structural change
    /// rather than a bigger constant. The identity block above grows with the drive — the number of
    /// mounted volumes is unbounded, and the 4 TB T5 EVO carries three where the drive this was
    /// measured against carries two. Any fixed height is a threshold some drive crosses, and the
    /// constant that was already here (`minHeight: 700`, "measured … not guessed" in Step 9) is
    /// itself an example: it was true when written and expired silently when Step 10 added the
    /// mounted-volumes row and the readiness explanation to the pane above.
    ///
    /// This is the third time this project has paid for the same defect — a control below the fold
    /// in a scroll region that does not advertise itself as scrollable. It cost Step 10 two of its
    /// five rounds on this very pane, and `OutcomePresentation` exists because an error message did
    /// the same thing. Increment 3 pinned the pre-run dialog's footer outside its `ScrollView` for
    /// exactly this reason; this is that move, applied to the control the dialog gates.
    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let device = discovery.selectedDevice {
                        selectedDeviceIdentity(for: device)
                    } else {
                        Text(discovery.devices.isEmpty
                             ? "Connect a drive to see its details here."
                             : "No device is selected.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            safetySection(for: discovery.selectedDevice)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func selectedDeviceIdentity(for device: DiscoveredDevice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
                // The selected device has to be unmistakable — this is the line that
                // stands between the user and testing the wrong drive (NFR-USE-3).
                HStack(spacing: 6) {
                    // Decorative section marker, not a status — hidden so it is not read as one.
                    Image(systemName: "checkmark.circle.fill")
                        .accessibilityHidden(true)
                    Text("Selected device")
                        .font(.headline)
                }

                Text(device.displayTitle)
                    .font(.title3.weight(.semibold))
                    .textSelection(.enabled)

                Grid(alignment: .leadingFirstTextBaseline,
                     horizontalSpacing: 12,
                     verticalSpacing: 6) {
                    detailRow("Capacity", device.capacityDescription)
                    detailRow("Exact size", device.exactCapacityDescription)
                    detailRow("Geometry", device.geometryDescription)
                    detailRow("Raw device", device.bsdName.rawDevicePath)
                    detailRow("Serial number", device.serialDescription)
                    if let medium = device.mediumType {
                        detailRow("Medium", medium)
                    }
                    detailRow("Mounted volumes",
                              device.mountedVolumesDescription ?? "None mounted")
                }

                if let problem = device.geometryProblem {
                    Label(problem.description, systemImage: "xmark.octagon.fill")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Advice, not a rule. The *rule* — that a run cannot start while volumes are
                // mounted — is the helper's to state, and it does so in `readinessBanner` just
                // below. This line used to say both, which meant the same refusal was written in
                // two places from two sources: one computed here from IOKit's volume list, one
                // answered by the process that actually enforces it (NFR-REL-7). Two statements of
                // one fact are two things that can drift.
                //
                // **Unconditional since 2026-08-10** (user decision). It used to be drawn only when
                // the drive had mounted volumes, which fitted the old wording — "testing a drive
                // you are using is not advisable". That sentence was withdrawn as not necessarily
                // true, and its replacement is about data loss, which a drive with nothing mounted
                // has exactly as much of. Leaving the condition would have meant the one sentence
                // that tells a user to back up appearing only on the drives already in use.
                //
                // The text is `PreRunWarningText.standingBackupAdvice`, not a literal here: it is
                // the product's second place for "back up first" beside FR-WARN-1's full statement,
                // and increment 2 exists because two copies of one message had already drifted.
                Label(PreRunWarningText.standingBackupAdvice,
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)

                // Moved here from the "Mounting & exclusive access" section (2026-08-05, user
                // decision): whether this drive is ready **is** part of the drive's state, and
                // having it in a second pane split one question across two headings while
                // duplicating the mounted-volume fact shown above.
                //
                // It also fixes the stale-pane defect that prompted the merge. This banner now
                // renders only inside `selectedDeviceIdentity(for:)`, which is called only with
                // a device — so deselecting cannot leave a readiness answer on screen for a
                // drive that is no longer named anywhere near it.
                readinessBanner(for: device)

                Text("""
                     Block size and block count are as reported by IOKit. The helper \
                     confirms them directly from the device before any run begins. The serial \
                     number is the USB device's: an external enclosure keeps its own serial when \
                     the drive inside it is swapped.
                     """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

    // MARK: - Safety: mount control and exclusive access (FR-SAFE-3/4/5/7)

    @ViewBuilder
    private func safetySection(for device: DiscoveredDevice?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                // Decorative section marker.
                Image(systemName: "lock.shield")
                    .accessibilityHidden(true)
                Text("Mounting & exclusive access")
                    .font(.headline)
            }

            // The readiness banner moved into the Selected device pane on 2026-08-05. What is
            // left here is only the controls that *act*, which is the split the merge was for:
            // "what is this drive and is it ready" above, "do something to it" here.
            //
            // These three controls are themselves scheduled for removal — user decision
            // 2026-08-05, FR-SAFE-5 withdrawn and FR-SAFE-6 reversed. Step 11's Start owns
            // unmount → acquire → run → release, with Step 14's warnings as the confirmation.
            let control = mountControlState(for: device)

            HStack(spacing: 10) {
                // FR-SAFE-5: one control, whose label and action always agree. Both come
                // from the same value, so the view cannot put them out of step.
                Button(control.label) {
                    if let device { performMountAction(control.direction, on: device) }
                }
                .disabled(!control.isEnabled)
                .accessibilityLabel(control.accessibilityLabel)

                Spacer()

                // Stand-in for Step 11's Start/Stop. The acquire is what actually decides
                // whether a run could begin, and it is the only thing that can detect
                // FR-SAFE-4(b) — so the gate for this step is driven from here until the
                // run-control state machine exists.
                Button("Acquire exclusive access") {
                    if let device { acquire(device) }
                }
                .disabled(device == nil || accessOperationInFlight || helperHoldsDevice)

                Button("Release") { release() }
                    .disabled(accessOperationInFlight || !helperHoldsDevice)
            }

            // Dimming is not a message (NFR-USE-8) — a lesson from Step 4, where two
            // disabled buttons were reported as missing entirely.
            if let reason = control.disabledReason {
                Label(reason, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let lastOutcome {
                Label(lastOutcome.text,
                      systemImage: lastOutcome.ok ? "checkmark.circle.fill"
                                                  : "xmark.octagon.fill")
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// What the helper says about the given device, or why it could not be asked.
    ///
    /// - Parameter device: the drive this answer is about. Taking it as a parameter rather than
    ///   reading `discovery.selectedDevice` is what makes the no-selection case *unrepresentable*
    ///   rather than merely handled: there is no longer a code path that renders a readiness
    ///   answer with nothing selected, so none can be left stale by a deselection. The previous
    ///   `selectedDevice == nil` branch is gone with it — this is only ever called from
    ///   `selectedDeviceIdentity(for:)`, which has a device by construction.
    @ViewBuilder
    private func readinessBanner(for device: DiscoveredDevice) -> some View {
        if let readinessError {
            // "below" until Step 9 moved the diagnostics panel into its own window. An
            // instruction that points somewhere the thing no longer is sends the user looking
            // for a control that is not there — NFR-USE-5 asks for the corrective step, and a
            // wrong one is worse than none.
            Label("""
                  The helper could not be asked whether this drive is ready: \
                  \(readinessError) Install and enable it in the Privileged Helper & \
                  Diagnostics window (Window menu, or ⇧⌘D) — only the helper can permit a run.
                  """, systemImage: "questionmark.circle")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        } else if let readiness {
            VStack(alignment: .leading, spacing: 8) {
                Label(readiness.message,
                      systemImage: readiness.needsFullDiskAccess ? "hand.raised.fill"
                                 : helperHoldsDevice ? "lock.fill"
                                 : readiness.isReady ? "checkmark.shield"
                                                     : "exclamationmark.shield")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)

                // NFR-INST-4: the corrective control sits next to the message that asks
                // for it. A missing Full Disk Access grant is not something the user can
                // be expected to guess at from an errno, and it is a different pane from
                // the Login Items approval — so it gets its own button rather than a
                // generic "Open Settings".
                if readiness.needsFullDiskAccess {
                    Button("Open Full Disk Access settings…") {
                        HelperRegistration.openFullDiskAccessSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        } else {
            Label("Checking with the helper…", systemImage: "ellipsis.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// FR-SAFE-5/7, decided by pure logic in `MountControlPolicy` so the label, the
    /// action and the enabled state are one decision rather than three conditionals.
    private func mountControlState(for device: DiscoveredDevice?) -> MountControlState {
        MountControlPolicy.state(
            hasSelection: device != nil,
            mountedVolumeCount: device?.mountedVolumeNames.count ?? 0,
            isRunActive: discovery.isRunActive,
            helperHoldsDevice: helperHoldsDevice,
            isOperationInFlight: mountOperationInFlight)
    }

    // MARK: - Actions

    private func refreshReadiness() {
        guard let device = discovery.selectedDevice else {
            readiness = nil
            readinessError = nil
            return
        }
        helper.checkDeviceReadiness(bsdName: device.bsdName.rawValue) { result in
            // A late reply for a device that is no longer selected must not overwrite the
            // current one. The list rebuilds on every hot-plug, so this is not theoretical.
            guard discovery.selectedDevice?.bsdName == device.bsdName else { return }
            switch result {
            case .success(let value):
                readiness = value
                readinessError = nil
                model.helperHoldsDevice = value.helperHoldsThisDevice
            case .failure(let error):
                readiness = nil
                readinessError = error.localizedDescription
            }
        }
    }

    private func performMountAction(_ direction: MountControlDirection,
                                    on device: DiscoveredDevice) {
        mountOperationInFlight = true
        clearOutcome("a mount or unmount was started")

        let finish: (VolumeMountOutcome) -> Void = { outcome in
            mountOperationInFlight = false
            present(ok: outcome.isSuccess, outcome.message,
                    from: direction == .unmountAll ? .unmount : .mount)
            // The device list live-updates through the VolumeChangeWatcher, so the label
            // re-evaluates itself; the readiness banner has to be asked again.
            refreshReadiness()
        }

        switch direction {
        case .unmountAll:
            // **A failed unmount is undone** (user decision 2026-08-06). A whole-disk unmount
            // dissents as a unit but leaves already-unmounted volumes unmounted, so a refusal by
            // one busy volume otherwise strands the user with a half-dismounted drive — which is
            // what happened, with the wrong drive selected.
            //
            // The sequencing is `VolumeMounter.restoringUnmount` rather than two nested calls
            // here, because written here it was untestable: a mutation deleting the rollback
            // outright was caught by nothing. `finish` runs once, at the end of whichever path
            // was taken, so the control stays disabled through the remount.
            // Captured before anything is unmounted: the restore puts back exactly these, and
            // nothing else. EFI is absent from this list precisely because it was not mounted.
            let before = Array(zip(device.mountedVolumeNames, device.mountedVolumeBSDNames))
                .map { (name: $0.0, bsdName: $0.1) }

            VolumeMounter.restoringUnmount(
                unmount: { done in mounter.unmountAll(device, completion: done) },
                mountedBefore: before,
                // **The postcondition, read back** — `DADiskUnmount` can report success with a
                // volume still mounted (measured 2026-08-06), which is why the first two versions
                // of this were inert.
                //
                // Read from the **mount table alone**, not by re-enumerating. `before` already
                // holds this device's volume nodes, from the enumerator's own IOKit subtree walk,
                // so the attribution question is already answered and `getfsstat` is the whole
                // remaining question. Calling `discovery.refresh()` here — as the first version
                // did — rebuilds the device list underneath the `List` up to a dozen times during
                // the settle, and a selection binding that round-trips fires
                // `.onChange(of: selectedDeviceID)`, which clears `lastOutcome`. That would erase
                // the very message this whole path exists to produce.
                volumesStillMounted: {
                    let mountedNodes = Set(MountTable.current().compactMap(\.bsdName))
                    return before.filter { mountedNodes.contains($0.bsdName) }.map(\.name)
                },
                // 150 ms × 12 ≈ 1.8 s of grace for the table to catch up with the callback.
                retry: { again in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: again)
                },
                restore: { lost, done in mounter.mount(volumeBSDNames: lost, completion: done) },
                completion: finish)

        case .mountAll:
            mounter.mountAll(device, completion: finish)
        }
    }

    private func acquire(_ device: DiscoveredDevice) {
        accessOperationInFlight = true
        clearOutcome("an acquire was started")

        helper.acquireDevice(bsdName: device.bsdName.rawValue) { result in
            accessOperationInFlight = false
            switch result {
            case .success(let acquisition):
                if case .acquired = acquisition {
                    model.helperHoldsDevice = true
                    // Identity captured at CLAIM time. The enumeration that produced it can
                    // be gone by the time a report is written; the report is about the drive
                    // the run touched, not whatever is present afterwards.
                    model.heldDevice = ReportedDevice(device)
                    present(ok: true, acquisition.message, from: .acquire)
                } else {
                    // A refusal is the *expected* outcome whenever a volume is mounted,
                    // so it is reported as a refusal rather than as a malfunction — but
                    // never as a success.
                    present(ok: false, acquisition.message, from: .acquire)
                }
            case .failure(let error):
                // No permissive reading: if the helper could not be reached, access was
                // not granted. Unlike uninstall, there is nothing safe about proceeding.
                present(ok: false, """
                                   Exclusive access was NOT granted — the helper could not be \
                                   reached: \(error.localizedDescription)
                                   """, from: .acquire)
            }
            refreshReadiness()
        }
    }

    private func release() {
        accessOperationInFlight = true
        clearOutcome("a release was started")

        helper.releaseDevice { result in
            accessOperationInFlight = false
            model.helperHoldsDevice = false
            // `lastRunDeviceName` and `lastRunDeviceSerial` are deliberately *not* cleared: the
            // run they name happened, and its figures are still on screen.
            model.heldDevice = nil
            switch result {
            case .success(let message):
                present(ok: true, message
                    + " macOS will normally remount the volumes shortly.", from: .release)
            case .failure(let error):
                present(ok: false, "Release failed: \(error.localizedDescription)", from: .release)
            }
            refreshReadiness()
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
            Text(value)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Keeping a selection from being cleared during a run

/// Sets `allowsEmptySelection` on the `List`'s backing `NSTableView`.
///
/// ## Why this reaches into AppKit at all
///
/// The device list must not lose its selection while a run is active, because the helper's claim
/// follows the selection and dropping it would release the drive under an active write. The
/// *authoritative* guard for that is in `DeviceDiscovery.select`/`deselect`, which refuse outright
/// and are unit-tested; this is only about the picture agreeing with the model.
///
/// Three pure-SwiftUI attempts failed, each disproved by measurement rather than abandoned on a
/// hunch (see the call site). The table changes its own selection before the binding is consulted,
/// and nothing available in SwiftUI puts it back afterwards. `allowsEmptySelection` prevents the
/// change instead, and it is the real table's own behaviour — the selection stays genuine, with
/// keyboard navigation and VoiceOver semantics intact, which a hand-drawn highlight would have
/// cost.
///
/// ## What it depends on, and how it fails
///
/// That SwiftUI's `List` is backed by an `NSTableView`. True on macOS 26; not contractual, and a
/// future OS could change it.
///
/// **It fails safe.** If no table is found, nothing is set and the behaviour degrades to exactly
/// what shipped before this: a list that can *look* deselected during a run while the model holds
/// firm. It cannot fail into releasing a device, because it is not what prevents that.
private struct TableSelectionPolicy: NSViewRepresentable {

    let allowsEmptySelection: Bool

    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Deferred one turn: on the first layout pass this view exists before the list's table
        // does, so looking now would find nothing and silently do nothing — the same "ran too
        // early to see anything" shape as the focus fix earlier in this file.
        DispatchQueue.main.async {
            nsView.nearestTableView()?.allowsEmptySelection = allowsEmptySelection
        }
    }
}

private extension NSView {

    /// The closest `NSTableView`, searched by walking up the ancestor chain and looking down from
    /// each level. Returns the nearest match, so a second list elsewhere in the window cannot be
    /// picked up by accident.
    func nearestTableView() -> NSTableView? {
        var ancestor: NSView? = self
        while let current = ancestor {
            if let table = current.firstTableViewInSubtree() { return table }
            ancestor = current.superview
        }
        return nil
    }

    func firstTableViewInSubtree() -> NSTableView? {
        if let table = self as? NSTableView { return table }
        for subview in subviews {
            if let table = subview.firstTableViewInSubtree() { return table }
        }
        return nil
    }
}
