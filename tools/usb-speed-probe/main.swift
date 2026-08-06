//
//  main.swift
//  usb-speed-probe — resolves a whole disk to the negotiated USB link speed behind it.
//
//  ## Why this exists as a separate tool
//
//  `ioreg` can list every USB device's "Device Speed", but it cannot answer the question the
//  helper actually asks: *what link is this disk behind?* A disk's IOMedia entry does not carry
//  the USB device's properties — they live several levels up the IOService plane, past the
//  block-storage driver and the SCSI peripheral. Reaching them needs an upward, recursive
//  registry search, which is code rather than a shell pipeline.
//
//  This probe performs exactly the search `HelperDeviceRegistry` performs, so the mechanism
//  is verified standalone before it is wired into a root daemon — the same reason
//  `nocache-probe` reads the geometry ioctls before `DeviceClaim` does.
//
//  ## What it is checking
//
//  FR-TEST-9's throughput falsifier derives its ceiling from the negotiated link speed. The
//  enum behind "Device Speed" is **not** declared in any SDK header — see
//  `Core/USBLinkSpeed.swift` for the full account — so the mapping is established by
//  evidence and has to stay checkable. This prints the raw code alongside the interpretation
//  and the ceiling that follows from it, so all three can be disagreed with.
//
//  NON-DESTRUCTIVE and unprivileged. Reads the IORegistry only: no device is opened, nothing
//  is unmounted, no root required. It is safe to run against any disk, including the one
//  holding the source tree.
//
//  Usage:
//      usb-speed-probe <bsdName> [<bsdName> ...]
//

import Foundation
import IOKit

// MARK: - The mapping under test
//
// Deliberately duplicated from Core/USBLinkSpeed.swift rather than imported: this tool is
// compiled standalone by swiftc, outside the Xcode project. The duplication is the point —
// if the two ever disagree, one of them is wrong, and this is the copy that can be run
// against real hardware without building the app.

func speedName(_ code: Int) -> String {
    switch code {
    case 0:  return "Low (1.5 Mb/s)"
    case 1:  return "Full (12 Mb/s)"
    case 2:  return "High (480 Mb/s)"
    case 3:  return "SuperSpeed (5 Gb/s)"
    case 4:  return "SuperSpeed+ (10 Gb/s)"
    case 5:  return "SuperSpeed+ (20 Gb/s)"
    default: return "UNRECOGNISED"
    }
}

/// Line rate, then physical-layer encoding: 8b/10b for USB 3.0, 128b/132b from 3.1, and no
/// block encoding at all below that.
func maximumPayloadBytesPerSecond(_ code: Int) -> Double? {
    switch code {
    case 0:  return 1_500_000 / 8
    case 1:  return 12_000_000 / 8
    case 2:  return 480_000_000 / 8
    case 3:  return 5_000_000_000 * 0.8 / 8
    case 4:  return 10_000_000_000 * (128.0 / 132.0) / 8
    case 5:  return 20_000_000_000 * (128.0 / 132.0) / 8
    default: return nil
    }
}

/// Small on purpose: the payload rate is a hard physical limit, not an estimate. Measured
/// block-storage throughput does not exceed the negotiated theoretical maximum, so 10% covers
/// timer granularity and scheduling jitter and nothing more.
let measurementMargin = 1.1

// MARK: - Registry search

/// The same upward, recursive search `HelperDeviceRegistry` uses for "Protocol
/// Characteristics" — the USB properties are ancestors of the media entry, not part of it.
func ancestorProperty(_ entry: io_object_t, _ key: String) -> Any? {
    let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
    return IORegistryEntrySearchCFProperty(entry, kIOServicePlane, key as CFString,
                                           kCFAllocatorDefault, options)
}

func emit(_ key: String, _ value: Any) { print("\(key)=\(value)") }

// MARK: - Arguments

let names = Array(CommandLine.arguments.dropFirst())
guard !names.isEmpty else {
    FileHandle.standardError.write(Data("""
        usage: usb-speed-probe <bsdName> [<bsdName> ...]
               e.g. usb-speed-probe disk8 disk4

        """.utf8))
    exit(2)
}

setvbuf(stdout, nil, _IOLBF, 0)

var exitStatus: Int32 = 0

for name in names {
    print("--- \(name) ---")

    guard name.hasPrefix("disk"),
          case let digits = name.dropFirst(4),
          !digits.isEmpty,
          digits.allSatisfy({ $0 >= "0" && $0 <= "9" }),
          let unit = UInt32(digits),
          "disk\(unit)" == name else {
        emit("\(name).error", "not a canonical whole-disk name")
        exitStatus = 1
        continue
    }

    guard let matching = IOBSDNameMatching(kIOMainPortDefault, 0, name) else {
        emit("\(name).error", "could not build a BSD name match")
        exitStatus = 1
        continue
    }
    let media = IOServiceGetMatchingService(kIOMainPortDefault, matching)
    guard media != 0 else {
        emit("\(name).error", "no such device is present")
        exitStatus = 1
        continue
    }
    defer { IOObjectRelease(media) }

    let interconnect = ancestorProperty(media, "Physical Interconnect") as? String
    emit("\(name).interconnect", interconnect ?? "<absent>")

    if let product = ancestorProperty(media, "USB Product Name") as? String {
        emit("\(name).product", product)
    }

    guard let raw = ancestorProperty(media, "Device Speed") else {
        emit("\(name).deviceSpeed", "<absent>")
        emit("\(name).ceiling", "none — the fixed fallback (8.00 GB/s) would be used")
        if interconnect == "USB" {
            emit("\(name).note",
                 "a USB device with no Device Speed property: the derived ceiling is "
               + "unavailable and FR-TEST-9's falsifier falls back")
        }
        continue
    }

    let code = (raw as? NSNumber)?.intValue ?? -1
    emit("\(name).deviceSpeed.code", code)
    emit("\(name).deviceSpeed.meaning", speedName(code))

    guard let payload = maximumPayloadBytesPerSecond(code) else {
        emit("\(name).ceiling", "none — code not recognised; the fixed fallback would be used")
        exitStatus = 1
        continue
    }

    let ceiling = payload * measurementMargin
    emit("\(name).maxPayloadBytesPerSecond", String(format: "%.0f", payload))
    emit("\(name).maxPayloadGBps", String(format: "%.3f", payload / 1_000_000_000))
    emit("\(name).ceilingGBps", String(format: "%.3f", ceiling / 1_000_000_000))
    emit("\(name).ceilingNote",
         "a read faster than this did not cross the link (payload max x \(measurementMargin))")
}

exit(exitStatus)
