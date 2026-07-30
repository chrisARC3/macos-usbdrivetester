//
//  AllWholeMediaProbe.swift
//  device-probe — an independent view of what the system considers a whole disk.
//
//  This deliberately **shares no code** with `IOKitDeviceEnumerator`. Its job is to
//  answer "what did discovery leave out, and was it right to?", and it cannot do that
//  honestly through the same filters it is checking: a bug that excluded everything
//  would look identical to a correct exclusion if both views came from the same query.
//
//  So this asks IOKit the broadest question — every `IOMedia` with `Whole = true`,
//  with no filtering at all — and reports the two properties the filters turn on.
//  Cross-referencing that against the discovered list is what turns "internal and
//  non-USB disks are excluded" (Step 5 gate item 1) into a positive observation.
//
//  Tool-only. Not part of the app target.
//

import Foundation
import IOKit

enum AllWholeMediaProbe {

    struct Line {
        let bsdName: String
        let reason: String
    }

    /// Every whole media object in the registry, with the facts the filters use.
    static func describeAll() -> [Line] {
        let matching = IOServiceMatching("IOMedia") as NSMutableDictionary
        matching["Whole"] = true

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           matching as CFMutableDictionary,
                                           &iterator) == KERN_SUCCESS else {
            return [Line(bsdName: "?", reason: "IOServiceGetMatchingServices failed")]
        }
        defer { IOObjectRelease(iterator) }

        var lines: [Line] = []
        while case let media = IOIteratorNext(iterator), media != 0 {
            defer { IOObjectRelease(media) }
            lines.append(describe(media))
        }
        return lines.sorted { $0.bsdName < $1.bsdName }
    }

    private static func describe(_ media: io_object_t) -> Line {
        let bsdName = string(media, "BSD Name") ?? "(unnamed)"

        var objectClass = [CChar](repeating: 0, count: 128)
        IOObjectGetClass(media, &objectClass)

        var parent: io_object_t = 0
        var parentClass = "(none)"
        var parentIsDriver = false
        if IORegistryEntryGetParentEntry(media, kIOServicePlane, &parent) == KERN_SUCCESS,
           parent != 0 {
            var buffer = [CChar](repeating: 0, count: 128)
            IOObjectGetClass(parent, &buffer)
            parentClass = String(cString: buffer)
            parentIsDriver = IOObjectConformsTo(parent, "IOBlockStorageDriver") != 0
            IOObjectRelease(parent)
        }

        let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        let characteristics = IORegistryEntrySearchCFProperty(media,
                                                              kIOServicePlane,
                                                              "Protocol Characteristics" as CFString,
                                                              kCFAllocatorDefault,
                                                              options) as? [String: Any]
        let interconnect = characteristics?["Physical Interconnect"] as? String ?? "unknown"

        let size = number(media, "Size") ?? 0
        let blockSize = number(media, "Preferred Block Size") ?? 0

        let verdict: String
        switch (parentIsDriver, interconnect == "USB") {
        case (false, _): verdict = "not a physical disk (provider \(parentClass))"
        case (true, false): verdict = "not USB (\(interconnect))"
        case (true, true): verdict = "physical USB disk"
        }

        return Line(bsdName: bsdName,
                    reason: "\(String(cString: objectClass).padding(toLength: 16, withPad: " ", startingAt: 0))"
                          + "\(String(blockSize).padding(toLength: 6, withPad: " ", startingAt: 0))"
                          + "\(String(size).padding(toLength: 16, withPad: " ", startingAt: 0))"
                          + verdict)
    }

    private static func string(_ entry: io_object_t, _ key: String) -> String? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }

    private static func number(_ entry: io_object_t, _ key: String) -> UInt64? {
        (IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber)?.uint64Value
    }
}
