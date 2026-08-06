//
//  USBSerialNumber.swift
//  USBDriveTester (app target — unprivileged)
//
//  Deciding whether a USB serial number is worth showing the user (added 2026-08-05).
//
//  ## Why this is a decision and not a string copy
//
//  The BSD name (`disk4`) is assigned at enumeration and changes on every replug, so it cannot
//  say *which drive* a run was performed on — the whole reason this type exists. The USB serial
//  can, but only when the device supplies a real one, and this ecosystem contains bridges that
//  supply something that merely looks like one.
//
//  Measured on this machine, 2026-08-05, through the same ancestor search the enumerator uses for
//  `Physical Interconnect`:
//
//  | drive | `USB Serial Number` | `INQUIRY Unit Serial Number` |
//  |---|---|---|
//  | Samsung Portable SSD T5 | `12345686DAA9` | `9AAD68654321` |
//  | Ugreen enclosure (990 EVO Plus) | `013117100578` | **`0000000000000000`** |
//  | Seagate Expansion HDD | `00000000NT17XBRA` | `00000000NT17XBRA` |
//
//  Two things follow, and both are why the sanitising exists.
//
//  **Sixteen zeros is not an identifier.** Every drive behind that bridge model would report it,
//  compare equal, and let the UI state with confidence that the last run was on the drive
//  currently selected. That is worse than the BSD-name problem it replaces: a wrong identity that
//  reads as authoritative, rather than a transient one everybody knows is transient.
//
//  **So `INQUIRY Unit Serial Number` is not used as a fallback.** A second source that can return
//  sixteen zeros is not a fallback, it is a trap. Only `USB Serial Number` is read, and an absent
//  one is reported as absent.
//
//  ## What a serial identifies, which is not always the drive
//
//  It identifies the **USB device presented to the host**. For the T5, enclosure and drive are one
//  unit, so it names the drive. For a bare caddy it names the *caddy* — `013117100578` is Ugreen's,
//  and swapping the NVMe inside leaves it unchanged. Accepted as a known limit (user decision
//  2026-08-05) and carried to Step 16's release notes, in the same spirit as FR-TEST-9's
//  acknowledgement that a verify cannot prove the data came from NAND.
//

import Foundation

/// Turns the raw `USB Serial Number` registry string into one that can be shown, or `nil`.
nonisolated enum USBSerialNumber {

    /// Shortest string accepted.
    ///
    /// Three characters is not an identifier anybody can distinguish two drives by, and a bridge
    /// reporting `"0"` or `"-"` is reporting a placeholder. Chosen as the smallest bound that
    /// rejects the placeholders seen in the wild without excluding a plausible real serial; the
    /// shortest genuine one measured here is twelve.
    static let minimumUsefulLength = 4

    /// The serial to display, or `nil` when the device did not supply a usable one.
    ///
    /// Rejects, in order:
    /// - `nil` — the property is absent. USB does not require a serial (`iSerialNumber` may be 0).
    /// - empty or whitespace-only.
    /// - shorter than ``minimumUsefulLength``.
    /// - **all one repeated character** — `0000000000000000`, `----`, all-spaces. This is the case
    ///   actually observed, and the one that would silently make two drives compare equal.
    static func sanitised(_ raw: String?) -> String? {
        guard let raw else { return nil }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count >= minimumUsefulLength,
              !isSingleRepeatedCharacter(trimmed) else { return nil }

        return trimmed
    }

    /// Whether every character is the same one.
    ///
    /// Deliberately not "is it all zeros": a bridge padding with `F`, `-` or spaces is making the
    /// identical claim, and singling out zero would catch one spelling of the defect and pass the
    /// others.
    private static func isSingleRepeatedCharacter(_ value: String) -> Bool {
        guard let first = value.first else { return false }
        return value.allSatisfy { $0 == first }
    }
}
