//
//  ContentView.swift
//  USBDriveTester
//
//  Step 1 placeholder UI: a single "Ping helper" button that exercises the XPC
//  round-trip and shows the result. This view is replaced by the real device
//  list / run-control UI in later steps (discovery in Step 5, controls in Step 11).
//

import SwiftUI

struct ContentView: View {
    @State private var status: String = "Not yet pinged."
    @State private var isPinging = false
    @State private var lastSucceeded: Bool? = nil

    private let helper = HelperConnection()

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.connected.to.line.below")
                .imageScale(.large)
                .font(.system(size: 40))
                .foregroundStyle(.tint)

            Text("USB Drive Tester")
                .font(.title2).bold()

            Text("Step 1 — helper plumbing check")
                .foregroundStyle(.secondary)

            Button {
                pingHelper()
            } label: {
                Label("Ping helper", systemImage: "wave.3.right")
            }
            .disabled(isPinging)

            // Status conveyed by text + symbol, never color alone (NFR-USE-8).
            HStack(spacing: 6) {
                if isPinging {
                    ProgressView().controlSize(.small)
                } else if let lastSucceeded {
                    Image(systemName: lastSucceeded
                          ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(lastSucceeded ? .green : .red)
                }
                Text(status)
                    .font(.callout)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: 360)
        }
        .padding(28)
        .frame(minWidth: 380, minHeight: 260)
    }

    private func pingHelper() {
        isPinging = true
        status = "Pinging…"
        lastSucceeded = nil
        helper.ping { result in
            isPinging = false
            switch result {
            case .success(let reply):
                lastSucceeded = (reply == "pong")
                status = "Helper replied: \"\(reply)\""
            case .failure(let error):
                lastSucceeded = false
                status = "Failed: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    ContentView()
}
