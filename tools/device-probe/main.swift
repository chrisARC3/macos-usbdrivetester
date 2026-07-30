//
//  main.swift
//  device-probe — run the app's real device discovery from the command line.
//
//  Why this exists
//  ---------------
//  Step 5 is the first step whose Verification Gate needs real hardware. Most of that
//  gate, though, is about *what discovery returns* — which drives are listed, which are
//  excluded, what order they come back in, what geometry is read — and none of that
//  actually needs a GUI. It needs the enumeration code and a drive.
//
//  So this compiles the app target's **real** discovery sources (not a copy of them)
//  and prints what they produce. That moves four of the five gate items off the "needs
//  a person at the machine" list and onto the "verifiable from a terminal" list,
//  leaving only the parts that genuinely require hands: physically plugging a drive in
//  and out, and looking at the finished UI.
//
//  It is the discovery counterpart to tools/ui-probe, which does the same for layout.
//
//  Usage (via scripts/device-probe.sh):
//      device-probe            enumerate once and print the table
//      device-probe --watch    enumerate, then keep printing as devices come and go
//      device-probe --all      also list what was excluded, and why
//

import Foundation

let arguments = Set(CommandLine.arguments.dropFirst())
let watching = arguments.contains("--watch")
let showExcluded = arguments.contains("--all")

// Line-buffer stdout. `print` block-buffers when stdout is not a terminal, so a
// redirected `--watch` session shows nothing at all until the process is killed —
// which is exactly when the output is wanted live.
setvbuf(stdout, nil, _IOLBF, 0)

let enumerator = IOKitDeviceEnumerator()

func timestamp() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter.string(from: Date())
}

func printDevices(_ devices: [DiscoveredDevice], selection: UInt64?) {
    guard !devices.isEmpty else {
        print("  (no USB mass-storage whole disks connected)")
        return
    }

    for device in devices {
        let marker = device.registryEntryID == selection ? "->" : "  "
        let usable = device.isSelectable ? "" : "  [NOT SELECTABLE]"
        print("\(marker) \(device.displayTitle)\(usable)")
        print("     capacity   \(device.capacityDescription)  (\(device.exactCapacityDescription))")
        print("     geometry   \(device.geometryDescription)")
        if let medium = device.mediumType {
            print("     medium     \(medium)")
        }
        if let volumes = device.mountedVolumesDescription {
            print("     mounted    \(volumes)")
        }
        print("     registry   0x\(String(device.registryEntryID, radix: 16))")
        if let problem = device.geometryProblem {
            print("     PROBLEM    \(problem)")
        }
    }
}

/// Cross-check: everything the system calls a whole disk, and what discovery did with
/// it. This is what makes "internal and non-USB disks are excluded" a positive
/// observation rather than an absence of evidence — a filter that excluded
/// *everything* would look identical in the list above.
func printExcluded(included: [DiscoveredDevice]) {
    print("\nAll whole media in the registry (what the filters saw):")
    let includedNames = Set(included.map(\.bsdName.rawValue))

    for line in AllWholeMediaProbe.describeAll() {
        let verdict = includedNames.contains(line.bsdName) ? "LISTED  " : "excluded"
        print("  \(verdict)  \(line.bsdName.padding(toLength: 8, withPad: " ", startingAt: 0))"
              + "  \(line.reason)")
    }
}

/// Carried across refreshes so the probe exercises the same selection policy the GUI
/// does — including the part that matters most, that a hot-plug elsewhere in the list
/// does not move the selection (FR-DEV-4/7).
var currentSelection: UInt64?

func report(_ label: String) {
    let devices = enumerator.enumerateDevices()
    let selection = DeviceSelectionPolicy.selection(in: devices, previousSelection: currentSelection)
    currentSelection = selection

    print("\n[\(timestamp())] \(label) — \(devices.count) device(s); "
          + "'->' marks the default selection")
    printDevices(devices, selection: selection)
    if showExcluded {
        printExcluded(included: devices)
    }
}

report("initial enumeration")

if watching {
    print("\nWatching for device changes. Plug or unplug a USB drive. Ctrl-C to stop.")
    enumerator.startObserving {
        report("device set changed")
    }
    RunLoop.main.run()
}
