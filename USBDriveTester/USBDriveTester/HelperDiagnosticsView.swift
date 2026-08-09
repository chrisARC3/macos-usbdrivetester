//
//  HelperDiagnosticsView.swift
//  USBDriveTester (app target — unprivileged)
//
//  INTERIM panel — the harness that closed the Step 3 and Step 4 Verification Gates,
//  moved out of `ContentView` in Step 5 and demoted behind a disclosure so the device
//  list can be the primary UI.
//
//  It is kept rather than deleted for a practical reason: Step 6 needs a registered,
//  enabled helper again, and Step 11 needs the mid-run guard. Throwing away the
//  register / uninstall / round-trip controls now would mean rebuilding them to get
//  through the next gate. It still is not product UI, and Steps 11 and 14 replace it.
//
//  What it covers:
//    * Registration  — register, approve, watch `.status` reach `.enabled` (Step 3),
//                      and remove the helper again (Step 4).
//    * Round-trip    — live XPC through the *registered* daemon; also discharged the
//                      ping deferred out of Step 1.
//    * Parameters    — the helper rejecting misaligned / out-of-range requests.
//    * Teardown      — the mid-run guard that refuses an uninstall.
//
//  The simulated-run toggle now has a second consumer: from Step 5 it also freezes
//  device discovery (FR-DEV-7), so the binding is owned by `ContentView` rather than by
//  this view. Step 11 replaces it with the real run-control state machine, at which
//  point both consumers read the same authoritative state.
//
//  Not covered here: the foreign-client rejection (Step 3) is driven from the CLI by
//  scripts/negative-test.sh, because it needs an adhoc-signed binary that cannot be
//  produced from inside this signed app.
//

import SwiftUI

struct HelperDiagnosticsView: View {

    /// Simulated geometry for the parameter-validation demo: a 1 MiB device with
    /// 512-byte blocks. Deliberately still simulated — the point of this section is the
    /// helper's *own* validation of values it is handed, so feeding it a real device's
    /// geometry would make the rejections harder to read, not more meaningful.
    private static let demoBlockSize: UInt32 = 512
    private static let demoBlockCount: UInt64 = 2048
    private static var demoByteCount: UInt64 { demoBlockCount * UInt64(demoBlockSize) }

    /// Stand-in for the run-control state machine built in Step 11. Owned by
    /// `ContentView` because discovery reads it too.
    @Binding var simulatedRunActive: Bool

    /// Shared with `DeviceListView` and owned by `ContentView` (Step 6). One connection
    /// per app: the helper ties a device claim to the connection that took it, so a
    /// second connection here would be a second owner.
    let helper: HelperConnection

    @State private var registration = HelperRegistration()

    @State private var pingResult: ActionResult?
    @State private var versionResult: ActionResult?
    @State private var validationResult: ActionResult?

    @State private var versionMismatch = false
    @State private var isCalling = false

    /// Step 9's bounded-cycle scaffolding.
    ///
    /// `cycleIsRunning` and `linkSpeedCode` are **bindings** rather than local state because the
    /// metrics panel lives in `ContentView`, above this disclosure: it needs to know a run is in
    /// flight (the app knows its own run's lifecycle, so the helper is never asked) and it needs
    /// the negotiated link speed to show beside measured throughput. Step 11 owns both properly
    /// when the run-control state machine becomes the single source of run state.
    @Binding var cycleIsRunning: Bool
    @Binding var linkSpeedCode: Int

    /// FR-FAIL-1's mode for the next run, chosen **before** it starts.
    ///
    /// A binding into `AppModel` rather than local state, for the same reason as the two above:
    /// the run is issued here and the report that names the mode is shown in a third window.
    /// Step 11 moves this control to the main window's pre-run controls beside the I/O-size
    /// dropdown, where FR-CTRL-7 requires it; the value it sets does not move with it.
    @Binding var failureMode: FailureModeCode


    /// Whether the helper holds a device — the bounded cycle's precondition. Acquired in the
    /// *main* window, needed here, so it lives in `AppModel`.
    let deviceIsHeld: Bool

    /// Whether new privileged work may still be issued (`AppModel.mayIssueNewWork`).
    ///
    /// False once a quit is pending. "Cancel and Quit" promises to issue no further work, and this
    /// control is the only thing in the app that issues any — so the promise is kept here or it is
    /// not kept at all. The confirmation is a sheet on the *main* window, which leaves this window
    /// clickable underneath it, so the disable is doing real work rather than guarding an
    /// unreachable state.
    let mayIssueNewWork: Bool

    /// Hands the finished run's report to the app. Called with `nil` when the helper **refused**
    /// the call, which is not a run and gets no report.
    ///
    /// A closure rather than a direct write, so `tools/ui-probe` can host this view with no model
    /// behind it and so the assembly stays visible at the one call site that has all the pieces.
    var reportProduced: (RunReport?) -> Void = { _ in }

    /// The drive the run is on, captured when the claim was taken (`AppModel.lastRunDevice`).
    var reportedDevice: ReportedDevice?

    @State private var cycleResult: ActionResult?

    var body: some View {
        Form {
            registrationSection
            connectionSection
            boundedCycleSection
            parameterSection
            teardownSection
        }
        .formStyle(.grouped)
        .onAppear { registration.refresh() }
    }

    // MARK: - Registration & removal

    private var registrationSection: some View {
        Section("Helper registration") {
            LabeledContent("Status") {
                HStack(spacing: 6) {
                    Image(systemName: registration.statusSymbolName)
                    Text(registration.statusName).bold()
                }
            }

            Text(registration.statusExplanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let warning = registration.locationWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LabeledContent("Running from") {
                Text(registration.bundlePath)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }

            HStack {
                Button("Register helper") { registration.register() }
                Button("Refresh") { registration.refresh() }
                if registration.needsApproval {
                    Button("Open Login Items…") { registration.openLoginItemsSettings() }
                        .buttonStyle(.borderedProminent)
                }
                Spacer()
                Button("Uninstall helper", role: .destructive) {
                    registration.uninstall(using: helper, runIsActive: simulatedRunActive)
                }
                // Deliberately NOT disabled on a protocol-version mismatch. An older
                // registered daemon is exactly a case where removal must stay
                // available (NFR-INST-3) — see UninstallPrecondition.
            }
            .disabled(registration.isBusy)

            Text(registration.lastActionMessage)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Teardown guard

    private var teardownSection: some View {
        Section("Run-state stand-in") {
            Text("""
                 There is no run engine yet — Step 11 builds the state machine — so this \
                 toggle stands in for one. It does two things: uninstalling the helper is \
                 refused while it is on (NFR-REL-5), and device discovery stops \
                 refreshing (FR-DEV-7). The helper is asked independently about uninstall \
                 and has the final say; if it cannot be reached, removal proceeds anyway \
                 so an unreachable privileged daemon never becomes unremovable.
                 """)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Simulate an active run", isOn: $simulatedRunActive)

            if simulatedRunActive {
                Label("""
                      Uninstall will be refused and the device list is frozen while this \
                      is on.
                      """, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Step 9's bounded cycle (scaffolding — Step 11 deletes this)

    /// Starts one bounded pass so the live metrics panel has something to display.
    ///
    /// ## Everything about this is deliberately not configurable
    ///
    /// * **Block 0**, always. FR-TEST-4 says a run begins at the first addressable block, and
    ///   FR-TEST-10 says every I/O begins on a 1 MiB boundary — block 0 satisfies both, and a
    ///   start the user could influence would satisfy neither by construction.
    /// * **4 MiB**, the FR-CTRL-8 default, hard-coded. The real dropdown is Step 11's, because
    ///   its whole behaviour is defined in terms of pause and resume, which do not exist yet.
    /// * **1 GiB**, `TesterProtocol.maximumBytesPerCall` — the most one uncancellable privileged
    ///   call may cover. A whole-device run is a *sequence* of these, and sequencing them is
    ///   Step 11's job, not something to improvise here.
    ///
    /// So this covers the first gibibyte and stops. It is not a run in the product's sense and
    /// the wording says so, because a control that looks like Start on a tool that writes to
    /// drives must not be mistaken for one.
    private var boundedCycleSection: some View {
        Section("Bounded cycle (Step 9 scaffolding)") {
            // "above" until Step 9 moved this panel into its own window — the metrics are now in
            // the main window, which is the whole reason this is not a modal sheet. Same class of
            // stale spatial reference as the device panel's "diagnostics below".
            Text("""
                 Runs the read → write-back → verify cycle over the **first 1 GiB** of the held \
                 device, at the 4 MiB default I/O size, so the metrics panel in the main window \
                 has a live run to display — keep that window visible while this runs. This is \
                 not the product's run: that covers the whole device and arrives with the run \
                 controls in Step 11.
                 """)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Label("""
                  This writes to the drive. The cycle writes back exactly the bytes it read, \
                  which is proven non-destructive in simulation and verified byte-for-byte on \
                  hardware — but it is still a write, and it needs the device already acquired.
                  """, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            // FR-FAIL-1: the mode is chosen **before** the run, and FR-FAIL-4 makes log-and-continue
            // the default. Disabled while a run is in flight — the mode is fixed for the run's
            // duration, and a control that looks changeable mid-run would imply otherwise.
            //
            // Step 11 moves this to the main window's pre-run controls beside the I/O-size
            // dropdown, where FR-CTRL-7 requires the choice before Start is enabled.
            Picker("On failure", selection: $failureMode) {
                Text("Log and continue").tag(FailureModeCode.logAndContinue)
                Text("Stop on first error").tag(FailureModeCode.stopOnFirstError)
            }
            .pickerStyle(.radioGroup)
            .disabled(cycleIsRunning)
            .onChange(of: failureMode) { _, mode in RunReportLog.modeSelected(mode) }

            Text(failureMode == .stopOnFirstError
                 ? """
                   The run halts at the first failed block range. **Everything past it is left \
                   untested** — which is not the same as passed.
                   """
                 : """
                   Every failed block range is recorded and the rest of the range is still \
                   refreshed. The default, and the safer choice for a drive already suspected of \
                   failing.
                   """)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                // Disabled until a device is actually held, rather than pressable-and-failing.
                //
                // Reported 2026-08-04 as "the button appears to do nothing": it was working
                // exactly as written — the helper answered "no device is held" in 25 ms, the
                // spinner flashed for a single frame, and a failure message was the only trace.
                // Every other control here disables itself and names the corrective step
                // (FR-SAFE-4, NFR-USE-5); this one stated its precondition in prose and then
                // looked live. **Prose is not a precondition.**
                Button("Run one bounded cycle") { runBoundedCycle() }
                    .disabled(isCalling || cycleIsRunning || !deviceIsHeld || !mayIssueNewWork)
                if cycleIsRunning {
                    ProgressView().controlSize(.small)
                    Text("running…").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }

            // Named rather than left to the dimming, like every other refusal in this app
            // (NFR-USE-5). Checked before the no-device message because it is the more specific
            // reason: with a quit pending, acquiring a device would not make this pressable.
            if !mayIssueNewWork {
                Label("""
                      The app has been asked to quit, so no new work can be started. Choose \
                      “Continue Testing” in the main window to carry on.
                      """, systemImage: "hourglass")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !deviceIsHeld {
                Label("""
                      No device is held. Select a drive in the main window, unmount its volumes, \
                      then use “Acquire exclusive access” — only the helper can permit a run, and \
                      it derives the geometry this needs from the descriptor it holds.
                      """, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            resultRow(cycleResult)
        }
    }

    /// The drive the report is about, as it was when the claim was taken.
    ///
    /// `AppModel.lastRunDevice` and not the current selection: the report is about the drive the
    /// run touched, and by the time it is written the list may have been rebuilt or the drive
    /// unplugged. `nil` only if a run somehow began with nothing held, which the disabled Start
    /// makes unreachable — reported as an unidentified drive rather than guessed at, because a
    /// report that invented an identity would be worse than one that admits it has none.
    private func makeReport(_ outcome: RunCycleOutcome,
                            blockCount: UInt64,
                            ioSize: Int,
                            startedAt: Date,
                            linkSpeedCode: Int) -> RunReport? {
        let device = reportedDevice ?? ReportedDevice(modelDescription: "Unidentified drive",
                                                      usbSerialNumber: nil,
                                                      bsdNameAtRunTime: nil,
                                                      capacityBytes: 0,
                                                      logicalBlockSize: 512)
        return RunReport(reply: outcome,
                         startBlock: 0,
                         blockCount: blockCount,
                         // One size today. FR-CTRL-8's mid-run change is Step 11's, and the model
                         // and renderer already handle a list of them.
                         ioSizesUsed: [ioSize],
                         device: device,
                         startedAt: startedAt,
                         finishedAt: Date(),
                         usbLinkSpeedDescription: MetricsFormatting.linkSpeed(code: linkSpeedCode))
    }

    /// Ask for the device's geometry, then run one bounded pass over its first gibibyte.
    ///
    /// The profile call is not optional politeness: 1 GiB is a byte figure and the request is in
    /// **blocks**, so converting it needs the device's logical block size. Assuming 512 would be
    /// wrong on 4,096-byte geometry (NFR-COMPAT-5) and would silently ask for eight times the
    /// intended range — which the helper would then refuse as over the per-call cap, reporting a
    /// size error for what was really an assumption. The same call yields the negotiated link
    /// speed the metrics panel shows beside measured throughput.
    private func runBoundedCycle() {
        cycleResult = nil
        cycleIsRunning = true

        // Taken here, before the profile call, so the report's elapsed figure covers the whole
        // operation the user waited through rather than only the privileged call inside it.
        let startedAt = Date()
        let ioSize = TesterProtocol.defaultIOSizeBytes
        let mode = failureMode

        helper.deviceProfile { profileResult in
            guard case .success(let profile) = profileResult, profile.isAvailable,
                  profile.logicalBlockSize > 0 else {
                cycleIsRunning = false
                cycleResult = ActionResult(
                    ok: false,
                    message: "Could not read the device's geometry. Acquire a device first — the "
                           + "helper derives geometry from ioctls on the descriptor it holds, and "
                           + "will not open one speculatively to answer a query.")
                return
            }

            linkSpeedCode = profile.usbLinkSpeedCode

            let blockCount = TesterProtocol.maximumBytesPerCall / UInt64(profile.logicalBlockSize)
            helper.runRetentionCycle(startBlock: 0,
                                     blockCount: blockCount,
                                     ioSizeBytes: ioSize,
                                     failureMode: mode) { result in
                cycleIsRunning = false

                // FR-RPT-1..5. `RunReport.init?` returns `nil` for a call the helper refused —
                // which is not a run, and gets no report rather than a file describing a test
                // that never touched the drive. The transport-failure case below likewise:
                // there is no reply to build one from.
                if case .success(let outcome) = result {
                    reportProduced(makeReport(outcome,
                                              blockCount: blockCount,
                                              ioSize: ioSize,
                                              startedAt: startedAt,
                                              linkSpeedCode: profile.usbLinkSpeedCode))
                } else {
                    reportProduced(nil)
                }

                switch result {
                case .success(let outcome):
                    // "Completed" means every planned chunk was processed — NOT that they all
                    // passed. A run that finds bad blocks and keeps going still completes
                    // (FR-FAIL-3), so the failure count is what decides how this reads.
                    var text = outcome.message
                    if let overhead = outcome.hostOverheadFraction {
                        text += String(format: "\n\nHost overhead: %.3f%% of device I/O time.",
                                       overhead * 100)
                    }
                    if let core = outcome.helperCoreFraction {
                        text += String(format: " Helper CPU: %.1f%% of one core.", core * 100)
                    }
                    cycleResult = ActionResult(
                        ok: outcome.didComplete && outcome.failedRangeCount == 0,
                        message: text)
                case .failure(let error):
                    cycleResult = ActionResult(ok: false,
                                               message: "The cycle could not be run: "
                                                   + error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Live XPC round-trip

    private var connectionSection: some View {
        Section("Live XPC round-trip") {
            Text("""
                 Exercises the connection through the registered daemon. The helper accepts \
                 this app only because it is signed under Team ID \
                 \(HelperIdentity.expectedTeamID); an adhoc-signed caller is invalidated on \
                 its first message.
                 """)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // One action per row. Two buttons side by side in a single Form row
            // rendered as a pair of faint, low-contrast pills once disabled — easy to
            // scan straight past, and indistinguishable from a control that is not
            // there at all.
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Button("Ping helper") { ping() }
                        .frame(minWidth: 160, alignment: .leading)
                    Text("liveness round-trip through the registered daemon")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Button("Check protocol version") { checkVersion() }
                        .frame(minWidth: 160, alignment: .leading)
                    Text("this app expects v\(TesterProtocol.version) (NFR-MAINT-1)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(isCalling || !registration.isEnabled)

            if !registration.isEnabled {
                // Paired with a symbol, not conveyed by dimming alone (NFR-USE-8):
                // "greyed out" is not a message.
                Label("These are disabled until the helper is enabled above.",
                      systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            resultRow(pingResult)
            resultRow(versionResult)
        }
    }

    // MARK: - Boundary parameter validation

    private var parameterSection: some View {
        Section("Parameter validation at the trust boundary") {
            Text("""
                 The helper runs as root and re-checks every request itself (NFR-REL-7). These \
                 send deliberately bad parameters against a simulated \
                 \(Self.demoBlockCount)-block, \(Self.demoBlockSize)-byte device \
                 (\(Self.demoByteCount) bytes) and show the helper's verdict verbatim.
                 """)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                parameterRow("Valid request",
                             detail: "offset 0, length 4096 — block-aligned and in range",
                             offset: 0, length: 4096)
                parameterRow("Misaligned offset",
                             detail: "offset 513 — not a multiple of 512",
                             offset: 513, length: 512)
                parameterRow("Runs past the end",
                             detail: "offset \(Self.demoByteCount - 512), length 4096",
                             offset: Self.demoByteCount - 512, length: 4096)
                parameterRow("Overflowing length",
                             detail: "length chosen so offset + length wraps past 2⁶⁴",
                             offset: 512, length: 0xFFFF_FFFF_FFFF_FE00)
            }
            .disabled(isCalling || !registration.isEnabled || versionMismatch)

            if versionMismatch {
                Label("Protocol version mismatch — further commands are refused.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
            }

            resultRow(validationResult)
        }
    }

    private func parameterRow(_ title: String,
                              detail: String,
                              offset: UInt64,
                              length: UInt64) -> some View {
        GridRow {
            Button(title) { validate(offset: offset, length: length) }
                .frame(minWidth: 160, alignment: .leading)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Result presentation

    /// Outcome of one action. Success/failure is carried by symbol *and* text, never
    /// by colour alone (NFR-USE-8) — a habit worth keeping from the start, since
    /// Step 14 makes it a gate.
    private struct ActionResult {
        let ok: Bool
        let message: String
    }

    @ViewBuilder
    private func resultRow(_ result: ActionResult?) -> some View {
        if let result {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: result.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                Text(result.message)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
        }
    }

    // MARK: - Actions

    private func ping() {
        isCalling = true
        pingResult = nil
        helper.ping { result in
            isCalling = false
            switch result {
            case .success(let reply):
                pingResult = ActionResult(ok: reply == "pong",
                                          message: "Helper replied: \"\(reply)\"")
            case .failure(let error):
                pingResult = ActionResult(ok: false, message: "Ping failed: \(error.localizedDescription)")
            }
        }
    }

    private func checkVersion() {
        isCalling = true
        versionResult = nil
        helper.checkProtocolVersion { result in
            isCalling = false
            switch result {
            case .success(let check):
                versionMismatch = !check.isMatch
                versionResult = ActionResult(ok: check.isMatch, message: check.description)
            case .failure(let error):
                versionResult = ActionResult(ok: false,
                                             message: "Version check failed: \(error.localizedDescription)")
            }
        }
    }

    private func validate(offset: UInt64, length: UInt64) {
        isCalling = true
        validationResult = nil
        helper.validateRunParameters(byteOffset: offset,
                                     byteLength: length,
                                     logicalBlockSize: Self.demoBlockSize,
                                     deviceBlockCount: Self.demoBlockCount) { result in
            isCalling = false
            switch result {
            case .success(let verdict):
                // A rejection is the *expected* outcome for three of the four
                // presets, so the symbol tracks "the helper answered as intended",
                // not "accepted".
                validationResult = ActionResult(
                    ok: true,
                    message: verdict.accepted ? "ACCEPTED — \(verdict.message)"
                                              : "REJECTED — \(verdict.message)")
            case .failure(let error):
                validationResult = ActionResult(ok: false,
                                                message: "Call failed: \(error.localizedDescription)")
            }
        }
    }
}
