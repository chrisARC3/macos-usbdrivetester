//
//  DeviceListView.swift
//  USBDriveTester (app target — unprivileged)
//
//  The device list and the selected-device detail (FR-DEV-1/3/4/6, NFR-USE-3).
//
//  ## What left in Step 11 increment 5, and what that means for this file
//
//  The `Unmount All` / `Acquire exclusive access` / `Release` controls are **gone**, along with
//  everything that served them: the mount/acquire actions, the in-flight flags, the outcome pane
//  and the alert attached to it. Start owns unmount → acquire → run → release now, and the run
//  controls live in `ContentView` (FR-SAFE-5 withdrawn, FR-SAFE-6 reversed, FR-SAFE-7 moot).
//
//  Two consequences worth stating, because both remove a class of defect rather than moving it:
//
//    * **The claim no longer follows the selection.** That rule existed only because the claim did
//      not belong to a run; a run-owned claim removes the ambiguity at its source. This view no
//      longer releases anything, and `AppModel.helperHoldsDevice` — a *per-device* answer read
//      everywhere as an *any-device* one — is deleted rather than fixed. Do not reintroduce a
//      selection-scoped flag.
//    * **The failure alert moved with the sequence it reports on**, to `RunControlsView`. An alert
//      attached to a deleted view is an error path with nowhere to surface.
//
//  What is left here is what this view was always for: *which drives are there, which one is
//  chosen, and what is true about it.* Nothing in it acts on a drive any more.
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

struct DeviceListView: View {

    let discovery: DeviceDiscovery

    /// Shared with every other window rather than opened again here: one `NSXPCConnection` to the
    /// daemon per app, so a connection dropping means one thing and the helper sees one client.
    /// The helper releases a claim when the connection that took it goes away, so two connections
    /// would mean two different owners of the same device.
    let helper: HelperConnection

    /// Approximate height of one two-line device row, scaled with the user's text size.
    ///
    /// `@ScaledMetric` rather than a constant because the list's height is derived from
    /// it (see `deviceList`): a hard-coded row height would clip rows at larger Dynamic
    /// Type settings, which is a worse outcome than the dead space it is there to
    /// remove (NFR-USE-8).
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 46

    /// What the helper last said about the selected device. `nil` before the first check,
    /// or when the helper could not be reached.
    @State private var readiness: DeviceReadiness?

    /// Why the helper could not be asked, if it could not. Shown rather than swallowed:
    /// "no banner" and "the helper says everything is fine" must not look the same.
    @State private var readinessError: String?

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
        //
        // **It no longer releases anything.** Until increment 5 the claim followed the selection,
        // because the claim did not belong to a run; now it does, and the rule is gone with the
        // controls that needed it.
        .onChange(of: discovery.selectedDeviceID) { _, _ in
            readiness = nil
            readinessError = nil
            refreshReadiness()
        }
        // The mounted-volume set changing is the other input the banner depends on, and
        // it changes without the selection changing — the user unmounts in Disk Utility,
        // or macOS remounts after a run releases the drive.
        .onChange(of: discovery.selectedDevice?.mountedVolumeNames ?? []) { _, _ in
            refreshReadiness()
        }
        .onAppear { refreshReadiness() }
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
                        // Frozen during a run (FR-DEV-7). The *reason* changed in increment 5 —
                        // it used to be "a selection change would release the device", and is now
                        // simply that **the run owns the device**. The refusal is still wanted.
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
                // the time.
                .background(TableSelectionPolicy(allowsEmptySelection: !discovery.isRunActive))
            }
        }
        // **A range, not a height** (Step 11 increment 7). `listHeight` is now the *ideal* and the
        // ceiling rather than a fixed size, so this pane can give up height when the window is
        // shorter than the content wants — and it is the pane that gives up height **first**, ahead
        // of the selected-device detail below (user decision 2026-08-19).
        //
        // The order is the point. A rigid list meant every squeeze landed on the detail, which is
        // the block that stands between the user and testing the wrong drive (NFR-USE-3); the list
        // is a picker they have finished with by the time height is scarce. The ordering is not
        // asked for with `layoutPriority` — it falls out of the ranges. This pane's is bounded
        // (`deviceListFloor`…`listHeight`) and the detail's is not (`deviceDetailFloor`…∞), and a
        // `VStack` sizes its least flexible child first. `scripts/window-fit-check.sh` and the
        // `devices-*` renders check that this holds rather than trusting the reasoning.
        .frame(minHeight: WindowMetrics.deviceListFloor,
               idealHeight: listHeight,
               maxHeight: listHeight)
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

    /// The selected-device panel.
    ///
    /// The safety controls that used to be pinned below this are gone (increment 5). The run
    /// controls that replace them live in `ContentView`, outside every scroll region — see that
    /// file's header for why that placement is structural rather than a measured constant.
    private var detail: some View {
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
        // The floor this pane never had (Step 11 increment 7). It was already a `ScrollView`, so it
        // could always compress — with nothing saying how far, which is why it was the only thing
        // absorbing every squeeze in the window and why the identity block could be reduced to
        // nothing. `deviceDetailFloor` keeps the line that says *which drive this is* on screen at
        // any window height; the rest scrolls.
        .frame(minHeight: WindowMetrics.deviceDetailFloor, maxHeight: .infinity)
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

    /// What the helper says about the given device, or why it could not be asked.
    ///
    /// - Parameter device: the drive this answer is about. Taking it as a parameter rather than
    ///   reading `discovery.selectedDevice` is what makes the no-selection case *unrepresentable*
    ///   rather than merely handled: there is no longer a code path that renders a readiness
    ///   answer with nothing selected, so none can be left stale by a deselection.
    @ViewBuilder
    private func readinessBanner(for device: DiscoveredDevice) -> some View {
        if let readinessError {
            Label("""
                  The helper could not be asked whether this drive is ready: \
                  \(readinessError) Install and enable it in the Privileged Helper & \
                  Diagnostics window (Window menu, or ⇧⌘D) — only the helper can permit a run.
                  """, systemImage: "questionmark.circle")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        } else if let readiness {
            VStack(alignment: .leading, spacing: 8) {
                // **`readiness.helperHoldsThisDevice`, read directly.** It is a *per-device*
                // answer, and this banner is rendered for exactly that device — which is the use
                // it was always correct for. What was deleted in increment 5 is the model property
                // it used to be copied into, because every *other* site read that copy as "the
                // helper holds some device". The answer was never wrong; storing it was.
                Label(readiness.message,
                      systemImage: readiness.needsFullDiskAccess ? "hand.raised.fill"
                                 : readiness.helperHoldsThisDevice ? "lock.fill"
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
            case .failure(let error):
                readiness = nil
                readinessError = error.localizedDescription
            }
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
/// The device list must not lose its selection while a run is active. The *authoritative* guard for
/// that is in `DeviceDiscovery.select`/`deselect`, which refuse outright and are unit-tested; this
/// is only about the picture agreeing with the model.
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
/// **It fails safe.** If no table is found, nothing is set and the behaviour degrades to a list
/// that can *look* deselected during a run while the model holds firm. It cannot fail into
/// releasing a device, because it is not what prevents that.
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
