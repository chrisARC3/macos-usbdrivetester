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

    @State private var registration = HelperRegistration()
    @State private var helper = HelperConnection()

    @State private var pingResult: ActionResult?
    @State private var versionResult: ActionResult?
    @State private var validationResult: ActionResult?

    @State private var versionMismatch = false
    @State private var isCalling = false

    var body: some View {
        Form {
            registrationSection
            connectionSection
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
