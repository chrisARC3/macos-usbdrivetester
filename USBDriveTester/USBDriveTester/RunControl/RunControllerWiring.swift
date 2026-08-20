//
//  RunControllerWiring.swift
//  USBDriveTester (app target — unprivileged)
//
//  Step 11, increment 5. Where ``RunController``'s injected operations are joined to the real
//  DiskArbitration and the real privileged helper.
//
//  ## Why this is a file and not eight closures inside a view
//
//  Because it is the one place in the app where "the run" meets the machine, and it is worth being
//  able to grep for. Everything above it is decided by types the suite can reach —
//  `RunControlPolicy`, `DevicePreparation`, `RunSequencer`, `RunSlicing` — and everything below it
//  needs a drive. Keeping the seam in a named file makes it obvious which side any future edit
//  falls on.
//
//  It also keeps the closures out of a SwiftUI `View`. A `View` is a **struct**, and an escaping
//  closure created inside one captures what the view was built with rather than what the model
//  holds when the closure runs — the defect that headed every first-run report "Unidentified
//  drive". Every closure below captures exactly one long-lived class, `AppModel`.
//

import Foundation
import SwiftUI

/// The helper accepted the connection but refused the request itself.
///
/// Distinct from a transport failure, and both are failures here: a run-control level this app
/// cannot confirm is one it must not assume.
private struct RunControlRefused: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

extension RunController {

    /// The real controller: DiskArbitration for the volumes, the privileged helper for the claim,
    /// the run and the control signal.
    ///
    /// - Parameters:
    ///   - model: the app's shared state. Captured by every closure below, and the **only** thing
    ///     they capture.
    ///   - openReport: brings the report window forward when a run produces one. A closure because
    ///     `openWindow` is a SwiftUI environment value and this is not a view.
    @MainActor
    static func live(model: AppModel, openReport: @escaping () -> Void) -> RunController {
        RunController(
            preconditions: {
                RunPreconditions(
                    // FR-DEV-3/4. A drive whose geometry this tool cannot read cannot be tested,
                    // and `DiscoveredDevice.isSelectable` is where that is decided.
                    hasUsableSelection: model.discovery.selectedDevice?.isSelectable ?? false,
                    mayIssueNewWork: model.mayIssueNewWork)
            },
            selectedDevice: { model.discovery.selectedDevice },
            prepare: { device, finished in
                prepare(device, model: model, completion: finished)
            },
            makeSequencer: { emit in
                RunSequencer(caller: model.helper,
                             // A closure, not a value: this goes false underneath a
                             // run already in flight, which is the whole point of it.
                             mayContinueRun: { model.mayContinueRun },
                             maximumBytesPerCall: TesterProtocol.maximumBytesPerCall,
                             onEvent: emit)
            },
            setRunControl: { code, finished in
                model.helper.setRunControl(code) { result in
                    finished(result.flatMap { accepted, message in
                        // **A refusal is a failure.** The helper refuses a control code it does not
                        // recognise rather than defaulting it, for the reason recorded on
                        // `RunControlCode` — answering a caller asking to STOP A WRITE with a run
                        // that keeps writing is the one direction that must never be taken.
                        accepted ? .success(()) : .failure(RunControlRefused(message: message))
                    })
                }
            },
            release: { finished in
                model.helper.releaseDevice { _ in finished() }
            },
            // One size for the whole run (FR-CTRL-8), from the dropdown increment 6 put in the
            // pre-run controls. A closure like the rest, but read **once** — `RunController`
            // captures it onto the pending start when the gate is answered, so the size the log
            // names and the size the run uses are one value read at one instant.
            ioSizeBytes: { model.ioSizeBytes },
            failureMode: { model.failureMode },
            onReport: { report in
                model.lastRunReport = report
                // A refused call is not a run: no report, and the log says why so that its absence
                // is explicable rather than looking like a lost one. Nothing is opened for it
                // either — a window saying "no run has finished yet" immediately after a run would
                // be worse than no window.
                guard let report else {
                    RunReportLog.noReportForRefusedCall("the request did not become a run")
                    return
                }
                RunReportLog.reportProduced(report)
                openReport()
            },
            onRunBegan: {
                // The previous run's report is not this run's, and leaving it on screen while a new
                // run is in flight is the stale-pane defect Step 9 was reported for.
                model.lastRunReport = nil
            },
            onRunSettled: { model.runSettled() },
            onFailure: { model.runFailure = $0 })
    }

    /// Unmount → verify → acquire → geometry → clear the level, with the real machinery behind each
    /// step. The sequencing, and every rollback, is `DevicePreparation`'s.
    @MainActor
    private static func prepare(_ device: DiscoveredDevice,
                                model: AppModel,
                                completion: @escaping (DevicePreparationOutcome) -> Void) {

        let mounter = VolumeMounter()

        // **Captured before anything is unmounted.** The restore puts back exactly these and
        // nothing else — EFI is absent from this list precisely because it was not mounted, which
        // is what a whole-disk mount got wrong and put on the desktop. Index-aligned by
        // construction: both arrays come from one mount-table snapshot and one IOKit subtree walk.
        let before = Array(zip(device.mountedVolumeNames, device.mountedVolumeBSDNames))
            .map { (name: $0.0, bsdName: $0.1) }

        let operations = DevicePreparationOperations(
            selectionStillNamesTheDrive: {
                // By **registry entry ID**, not by BSD name. The name is a locator assigned at
                // enumeration, and the pre-run dialog can sit unanswered long enough for a replug
                // to renumber the machine's drives — this is the one place a locator is about to be
                // used to *act*, so the identity behind it is re-confirmed first.
                model.discovery.selectedDevice?.registryEntryID == device.registryEntryID
            },
            unmount: { finished in mounter.unmountAll(device, completion: finished) },
            volumesStillMounted: {
                // Read from the **mount table alone**, not by re-enumerating. `before` already
                // holds this device's volume nodes, so the attribution question is answered and
                // `getfsstat` is the whole remaining one. Calling `discovery.refresh()` here — as
                // an earlier version of this did — rebuilds the device list underneath the `List`
                // up to a dozen times during the settle.
                let mountedNodes = Set(MountTable.current().compactMap(\.bsdName))
                return before.filter { mountedNodes.contains($0.bsdName) }.map(\.name)
            },
            // 150 ms × 12 ≈ 1.8 s of grace for the table to catch up with the callback.
            retry: { again in
                // Wrapped rather than passed as `execute:`. `again` is a plain main-actor closure
                // and `asyncAfter(execute:)` wants a `@Sendable` one; the wrapper is what is
                // handed across, and it does nothing but call back on the queue it was scheduled
                // on. Everything here is main-queue only — `DevicePreparation`'s whole sequence
                // runs there, as does DiskArbitration's callback.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { again() }
            },
            acquire: { finished in
                model.helper.acquireDevice(bsdName: device.bsdName.rawValue, completion: finished)
            },
            profile: { finished in model.helper.deviceProfile(completion: finished) },
            clearRunControl: { finished in
                model.helper.setRunControl(.proceed) { result in
                    finished(result.flatMap { accepted, message in
                        accepted ? .success(()) : .failure(RunControlRefused(message: message))
                    })
                }
            },
            release: { finished in model.helper.releaseDevice { _ in finished() } },
            restore: { nodes, finished in
                mounter.mount(volumeBSDNames: nodes, completion: finished)
            })

        DevicePreparation.prepare(mountedBefore: before,
                                  operations: operations,
                                  completion: completion)
    }
}
