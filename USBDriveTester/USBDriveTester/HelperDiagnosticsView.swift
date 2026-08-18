//
//  HelperDiagnosticsView.swift
//  USBDriveTester (app target — unprivileged)
//
//  INTERIM panel — the harness that closed the Step 3 and Step 4 Verification Gates,
//  moved out of `ContentView` in Step 5 and demoted behind its own window in Step 9.
//
//  What it covers:
//    * Registration  — register, approve, watch `.status` reach `.enabled` (Step 3),
//                      and remove the helper again (Step 4).
//    * Round-trip    — live XPC through the *registered* daemon; also discharged the
//                      ping deferred out of Step 1.
//    * Parameters    — the helper rejecting misaligned / out-of-range requests.
//    * Pre-run       — the failure mode (FR-FAIL-1) and the way back from a suppressed warning.
//
//  ## What Step 11 increment 5 took out of here
//
//  **The bounded-cycle button is gone**, and with it the whole Step 9 scaffolding: the run, the
//  report assembly, and the pre-run dialog it raised. Start owns unmount → acquire → run → release
//  now, in the main window, and the gate moved with it.
//
//  It could not have stayed. Its precondition was `AppModel.helperHoldsDevice`, which this
//  increment deletes, and the only control that could satisfy it — `Acquire exclusive access` —
//  went at the same time. Leaving it would have meant either a button that can never be enabled or,
//  worse, a second path able to issue privileged work on the owning connection while a run holds
//  it.
//
//  **The run-state stand-in toggle is gone too.** It existed because there was no run engine; there
//  is one now, so uninstall and the device-list freeze read the real state
//  (`AppModel.runIsActive`) instead of a switch that stood in for it.
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

    /// Shared with the main window and owned by `AppModel` (Step 6). One connection
    /// per app: the helper ties a device claim to the connection that took it, so a
    /// second connection here would be a second owner.
    let helper: HelperConnection

    /// Whether a run is happening (`AppModel.runIsActive`), for the uninstall guard.
    ///
    /// The real thing since increment 5. It used to be the stand-in toggle that lived in this very
    /// panel — which meant NFR-REL-5's app-side guard was wired to a switch and **not** to the
    /// bounded cycle running beside it. The helper's own refusal was the only thing covering that,
    /// exactly as it covers a wrong mount belief; the collapse fixes it at the source.
    let runIsActive: Bool

    /// FR-FAIL-1's mode for the next run, chosen **before** it starts.
    ///
    /// A binding into `AppModel` rather than local state: the run is issued from the main window
    /// and the report that names the mode is shown in a third one. **Increment 6 relocates this
    /// control** to the pre-run controls beside the I/O-size dropdown, where FR-CTRL-7 wants it; it
    /// stays here until then so `stopOnFirstError` remains reachable, and a run outcome nobody can
    /// trigger is one nobody has checked.
    @Binding var failureMode: FailureModeCode

    /// Whether the user has suppressed the pre-run **warning text** (Step 14, decision 5).
    ///
    /// A binding into `AppModel`, which writes it through to `UserDefaults`. It is here rather than
    /// in the main window because it is the **way back** from a preference set elsewhere — the
    /// checkbox that sets it lives in the pre-run dialog, and a setting with no way back is one the
    /// user cannot undo without editing a plist (decision 7).
    @Binding var warningsSuppressed: Bool

    @State private var registration = HelperRegistration()

    @State private var pingResult: ActionResult?
    @State private var versionResult: ActionResult?
    @State private var validationResult: ActionResult?

    @State private var versionMismatch = false
    @State private var isCalling = false

    var body: some View {
        Form {
            registrationSection
            connectionSection
            preRunControlsSection
            preRunWarningsSection
            parameterSection
        }
        .formStyle(.grouped)
        .onAppear { registration.refresh() }
    }

    // MARK: - Registration & removal

    private var registrationSection: some View {
        Section("Helper registration") {
            LabeledContent("Status") {
                HStack(spacing: 6) {
                    // Decorative. `statusName` beside it states the same thing in words, so
                    // leaving the glyph in the accessibility tree announces the status twice —
                    // once as a symbol name nobody asked for. Marked hidden across all seven such
                    // sites on 2026-08-11; the words are the content, the symbol is reinforcement.
                    Image(systemName: registration.statusSymbolName)
                        .accessibilityHidden(true)
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
                    // NFR-REL-5 / NFR-INST-3. The **real** run state since increment 5. The helper
                    // is asked independently and has the final say; if it cannot be reached,
                    // removal proceeds anyway so an unreachable privileged daemon never becomes
                    // unremovable.
                    registration.uninstall(using: helper, runIsActive: runIsActive)
                }
                // Deliberately NOT disabled on a protocol-version mismatch. An older
                // registered daemon is exactly a case where removal must stay
                // available (NFR-INST-3) — see UninstallPrecondition.
            }
            .disabled(registration.isBusy)

            if runIsActive {
                Label("A run is in progress, so uninstalling the helper will be refused.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(registration.lastActionMessage)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Pre-run controls (FR-FAIL-1; relocating in increment 6)

    private var preRunControlsSection: some View {
        Section("Pre-run controls") {
            Text("""
                 Chosen before a run starts and fixed for its duration. The Start control itself is \
                 in the main window, beside the drive it acts on.
                 """)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // FR-FAIL-1: the mode is chosen **before** the run, and FR-FAIL-4 makes log-and-continue
            // the default. Disabled while a run is in flight — the mode is fixed for the run's
            // duration, and a control that looks changeable mid-run would imply otherwise.
            Picker("On failure", selection: $failureMode) {
                Text("Log and continue").tag(FailureModeCode.logAndContinue)
                Text("Stop on first error").tag(FailureModeCode.stopOnFirstError)
            }
            .pickerStyle(.radioGroup)
            .disabled(runIsActive)
            .onChange(of: failureMode) { _, mode in RunReportLog.modeSelected(mode) }

            Text(failureMode == .stopOnFirstError
                 ? """
                   The run halts at the first failed block range. **Everything past it is left \
                   untested** — which is not the same as passed.
                   """
                 : """
                   Every failed block range is recorded and the rest of the drive is still \
                   refreshed. The default, and the safer choice for a drive already suspected of \
                   failing.
                   """)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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

    // MARK: - Pre-run warnings (Step 14, decision 7)

    /// The way back from "Don't show this warning again".
    ///
    /// It states the current setting **in words** rather than only offering a button, because the
    /// two states are otherwise indistinguishable from this window: a user who does not remember
    /// ticking the box has no way to find out what the app will do next run. NFR-USE-8 also asks
    /// that meaning never rest on colour alone, and a lone enabled/disabled button rests on
    /// dimming.
    ///
    /// The button is disabled when there is nothing to undo, and says so — the same rule as every
    /// other refusal in this app: name the reason rather than leave the user to infer it from a
    /// greyed control (FR-SAFE-4, NFR-USE-5). *Prose is not a precondition*, so the precondition is
    /// the disable and the prose is the explanation.
    private var preRunWarningsSection: some View {
        Section("Pre-run warnings") {
            Text("""
                 The three mandatory warnings (FR-WARN-1/2/3) appear when a run is started. \
                 Suppressing them removes the **text**, never the confirmation: a run always asks \
                 first, naming the drive by model and USB serial.
                 """)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Label(warningsSuppressed
                  ? "The warning text is currently suppressed for this user account."
                  : "The warning text is shown before every run.",
                  systemImage: warningsSuppressed ? "eye.slash" : "eye")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Show pre-run warnings again") { warningsSuppressed = false }
                    .disabled(!warningsSuppressed)
                Spacer()
            }

            if !warningsSuppressed {
                Text("Nothing to restore — the warnings are already being shown.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
                // Decorative — `result.message` carries the outcome in words.
                Image(systemName: result.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .accessibilityHidden(true)
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
