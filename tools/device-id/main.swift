//
//  main.swift
//  device-id — resolve a drive by USB SERIAL NUMBER rather than by BSD name.
//
//  Why this exists
//  ---------------
//  Written 2026-08-06, immediately after a reboot renumbered this machine's drives and the
//  designated scratch device stopped being `disk4`. It became `disk8` — and `disk4` became the
//  22 TB Seagate holding Backup and Time Machine. Every gate script in this repo took a BSD name
//  on the command line, and the write-capable ones would have written a gibibyte to whatever that
//  name now pointed at.
//
//  The product settled this question on 2026-08-05: **drives are identified by USB serial number,
//  never by BSD name**, because the BSD name is assigned at enumeration and names a different
//  drive after any replug. That decision was implemented in the app and not in the apparatus
//  around it. This closes that gap.
//
//  Why it compiles the app's own sources
//  ------------------------------------
//  It reports the serial by calling `IOKitDeviceEnumerator` — the *app's* enumerator, not a second
//  implementation of it. Two definitions of "this drive's serial" are two things that can drift,
//  and the one that would drift silently is the one used only by scripts. In particular this
//  inherits, for free:
//
//    * the ancestor search — `USB Serial Number` lives on the USB device node several levels above
//      the media, and is found with `kIORegistryIterateParents` rather than by parsing indentation
//      out of `ioreg`;
//    * `USBSerialNumber.sanitised`, so a bridge reporting sixteen zeros is reported as having **no**
//      serial rather than as an identifier every drive behind that bridge model would share;
//    * the same exclusions the device list applies, so a disk image cannot be resolved as a target.
//
//  Usage
//  -----
//      device-id list                 every external USB whole disk, one per line
//      device-id find <serial>        the line for that serial; exit 3 none, 4 ambiguous
//      device-id serial-of <diskN>    that disk's serial; exit 3 if it has none
//
//  Line format is tab-separated and fixed, for `read`:
//      <serial>\t<bsdName>\t<blockCount>\t<blockSize>\t<model>
//  A drive with no usable serial prints `-` in the first field, and can therefore never be
//  matched by `find` — which is the intended behaviour, not a limitation: an unidentifiable drive
//  must not become a write target.
//

import Foundation

let noSerial = "-"

func line(for device: DiscoveredDevice) -> String {
    [device.usbSerialNumber ?? noSerial,
     device.bsdName.rawValue,
     device.blockCount.map(String.init) ?? "0",
     String(device.logicalBlockSize),
     device.modelDescription].joined(separator: "\t")
}

func fail(_ message: String, _ code: Int32) -> Never {
    FileHandle.standardError.write(Data("device-id: \(message)\n".utf8))
    exit(code)
}

let arguments = Array(CommandLine.arguments.dropFirst())
let devices = IOKitDeviceEnumerator().enumerateDevices()

switch arguments.first {

case "list", nil:
    for device in devices { print(line(for: device)) }

case "find":
    guard arguments.count == 2 else { fail("usage: device-id find <serial>", 2) }
    let wanted = arguments[1]
    // Deliberately an exact match. A prefix or case-insensitive match would be friendlier and
    // would also be a way for one drive to answer to another drive's name.
    let matches = devices.filter { $0.usbSerialNumber == wanted }
    switch matches.count {
    case 0:
        fail("no connected USB drive reports serial number '\(wanted)'", 3)
    case 1:
        print(line(for: matches[0]))
    default:
        // Two drives claiming one serial is exactly the placeholder case `USBSerialNumber`
        // rejects, so this should be unreachable — and if it ever happens, refusing is the only
        // safe answer, because neither drive can be told from the other.
        fail("""
             \(matches.count) connected drives report serial number '\(wanted)' \
             (\(matches.map(\.bsdName.rawValue).joined(separator: ", "))) — refusing to choose
             """, 4)
    }

case "serial-of":
    guard arguments.count == 2 else { fail("usage: device-id serial-of <diskN>", 2) }
    let wanted = arguments[1]
    guard let device = devices.first(where: { $0.bsdName.rawValue == wanted }) else {
        fail("no external USB whole disk is currently named '\(wanted)'", 3)
    }
    guard let serial = device.usbSerialNumber else {
        fail("'\(wanted)' (\(device.modelDescription)) reports no usable serial number", 3)
    }
    print(serial)

default:
    fail("unknown command '\(arguments[0])'; expected list, find or serial-of", 2)
}
