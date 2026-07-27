//
//  ContentView.swift
//  USBDriveTester
//
//  INTERIM Step 3 panel — a harness for this step's Verification Gate, not product
//  UI. It exists so the four gate items can be exercised by hand:
//
//    1. Register the daemon, approve it, and see `.status` reach `.enabled`.
//    2. Complete a live XPC round-trip through the *registered* daemon (this also
//       discharges the ping deferred out of Step 1).
//    3. (Gate item 3, the foreign-client rejection, is driven from the CLI by
//       scripts/negative-test.sh — it needs an adhoc-signed binary, which cannot be
//       produced from inside this signed app.)
//    4. Have the helper reject misaligned / out-of-range parameters with a clear
//       message.
//
//  The real UI — device list, run controls, metrics, and the mandatory pre-run
//  warnings — arrives in Steps 5, 11, 9 and 14. Nothing here is meant to survive.
//

import SwiftUI

struct ContentView: View {

    /// Simulated geometry for the parameter-validation demo: a 1 MiB device with
    /// 512-byte blocks. Real geometry comes from device discovery in Step 5 and is
    /// confirmed by the helper's own ioctls in Step 7.
    private static let demoBlockSize: UInt32 = 512
    private static let demoBlockCount: UInt64 = 2048
    private static var demoByteCount: UInt64 { demoBlockCount * UInt64(demoBlockSize) }

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
        }
        .formStyle(.grouped)
        .frame(minWidth: 560, minHeight: 620)
        .onAppear { registration.refresh() }
    }

    // MARK: - Registration (gate item 1)

    private var registrationSection: some View {
        Section("1 — Helper registration") {
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
                // Development affordance — Step 4 productises teardown with a
                // mid-run guard and device release (NFR-INST-3).
                Button("Unregister (dev)", role: .destructive) {
                    helper.invalidate()
                    registration.unregister()
                }
            }
            .disabled(registration.isBusy)

            Text(registration.lastActionMessage)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Live XPC round-trip (gate item 2)

    private var connectionSection: some View {
        Section("2 — Live XPC round-trip") {
            Text("""
                 Exercises the connection through the registered daemon. The helper accepts \
                 this app only because it is signed under Team ID \
                 \(HelperIdentity.expectedTeamID); an adhoc-signed caller is invalidated on \
                 its first message.
                 """)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Ping helper") { ping() }
                Button("Check protocol version") { checkVersion() }
                Spacer()
            }
            .disabled(isCalling || !registration.isEnabled)

            if !registration.isEnabled {
                Text("Enable the helper above before calling it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            resultRow(pingResult)
            resultRow(versionResult)
        }
    }

    // MARK: - Boundary parameter validation (gate item 4)

    private var parameterSection: some View {
        Section("4 — Parameter validation at the trust boundary") {
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

#Preview {
    ContentView()
}
