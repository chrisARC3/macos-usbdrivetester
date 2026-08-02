//
//  USBLinkSpeed.swift
//  Core — how fast the link to the device under test can possibly be.
//
//  Step 7 (AI-5), supporting FR-TEST-9. Pure — Foundation only, no IOKit. The helper reads
//  the registry and passes the raw code in; everything here is arithmetic, so the whole
//  mapping is unit-testable with no hardware (NFR-MAINT-2).
//
//  ## Why this exists
//
//  FR-TEST-9's falsifier needs a rate above which a read cannot have come from the device.
//  The first draft used a fixed 8 GB/s — a number chosen by judgement, which ages badly as
//  USB gets faster and is far looser than physics allows.
//
//  The link's payload rate is a *hard physical ceiling*: data that crossed the wire cannot
//  have arrived faster than the wire carries it. Deriving the threshold from the negotiated
//  link speed therefore replaces a judgement with a measurement, and adapts to any device.
//
//  ## The negotiated speed already accounts for the host
//
//  Only the *device's* speed is needed, not the host controller's. The registry reports the
//  **negotiated** connection speed, which is already the minimum of what the device, every
//  intervening hub, and the host port can sustain — a 10 Gb/s drive in a 5 Gb/s port reports
//  5 Gb/s. Querying the host separately would re-derive a minimum that negotiation has
//  already taken.
//
//  ## THE MAPPING IS DERIVED FROM EVIDENCE, NOT FROM A HEADER. READ THIS BEFORE CHANGING IT.
//
//  There are two USB speed enumerations in macOS, they differ by more than an offset, and
//  **the one documented in the SDK is not the one this property uses.**
//
//  `IOUSBHostFamilyDefinitions.h` defines `tIOUSBHostConnectionSpeed` as
//  `None=0, Full=1, Low=2, High=3, Super=4, SuperPlus=5, SuperPlusBy2=6` — but that
//  documents `kUSBHostMatchingPropertySpeed`, a *different* property. The registry key
//  actually present on these devices is `"Device Speed"`, a legacy `IOUSBFamily` name, and
//  the SDK defines neither that string nor its enum: they are kernel-side runtime
//  properties, the same class of thing as the registry `#define`s `DeviceClaim.swift` spells
//  out by hand.
//
//  The mapping below is the legacy one, established by reading the live registry
//  (2026-08-02) and checking each device against the standard it is known to implement:
//
//  | Device observed | code | this mapping | `tIOUSBHostConnectionSpeed` would say |
//  |---|---|---|---|
//  | USB keyboard; optical mouse | 0 | Low, 1.5 Mb/s ✓ | "no device connected" ✗ |
//  | USB2.1 Hub | 2 | High, 480 Mb/s ✓ | Low, 1.5 Mb/s ✗ |
//  | USB3.1 Hub | 3 | Super, 5 Gb/s ✓ | High, 480 Mb/s ✗ |
//  | USB3.2 Hub | 4 | SuperPlus, 10 Gb/s ✓ | Super, 5 Gb/s |
//  | `disk4` — Samsung T5, USB 3.1 Gen 2 | 4 | **10 Gb/s** ✓ | 5 Gb/s |
//  | `disk8` — Seagate Expansion, USB 3.0 | 3 | **5 Gb/s** ✓ | High, 480 Mb/s ✗ |
//
//  Six fit; four are absurd under the SDK enum. An independent measurement closes it:
//  `disk4` sustained **475 MB/s** (2026-08-02), which is 3.8 Gb/s of payload and therefore
//  impossible on a 480 Mb/s link — so code 3 cannot mean High Speed.
//
//  **The consequence of getting this wrong is not symmetric.** Reading a 10 Gb/s link as
//  5 Gb/s merely loosens the ceiling. Reading it as Low Speed would set the ceiling at
//  ~0.2 MB/s and flag *every read of every run* as cached. `CacheBypassAssessment` guards
//  against that directly — the derived ceiling has to prove itself before it is trusted —
//  and `scripts/usb-speed-check.sh` re-dumps the observed codes so this table can be
//  re-checked if a macOS release shifts them.
//

import Foundation

/// A negotiated USB link speed, and what it implies about the fastest possible transfer.
public enum USBLinkSpeed: Equatable, CustomStringConvertible {

    case low                       // USB 1.0    1.5 Mb/s
    case full                      // USB 1.1     12 Mb/s
    case high                      // USB 2.0    480 Mb/s
    case superSpeed                // USB 3.0      5 Gb/s
    case superSpeedPlus            // USB 3.1     10 Gb/s
    case superSpeedPlusBy2         // USB 3.2     20 Gb/s

    /// A code the registry reported that this build does not recognise — a newer USB
    /// generation, or a mapping that has shifted. **Never guessed at**: an unrecognised code
    /// yields no ceiling, and the caller falls back.
    case unrecognised(code: Int)

    /// Map the registry's `"Device Speed"` value. See the file header for how this mapping
    /// was established and why it is not taken from the SDK header of the same shape.
    public static func from(deviceSpeedCode code: Int) -> USBLinkSpeed {
        switch code {
        case 0:  return .low
        case 1:  return .full
        case 2:  return .high
        case 3:  return .superSpeed
        case 4:  return .superSpeedPlus
        case 5:  return .superSpeedPlusBy2
        default: return .unrecognised(code: code)
        }
    }

    /// Raw signalling rate in bits per second, or `nil` if unrecognised.
    public var lineRateBitsPerSecond: Double? {
        switch self {
        case .low:                return 1_500_000
        case .full:              return 12_000_000
        case .high:             return 480_000_000
        case .superSpeed:      return 5_000_000_000
        case .superSpeedPlus: return 10_000_000_000
        case .superSpeedPlusBy2: return 20_000_000_000
        case .unrecognised:      return nil
        }
    }

    /// The greatest payload throughput this link can carry, in bytes per second.
    ///
    /// Line rate less the physical-layer encoding, which is not a rule of thumb — it is how
    /// many bits of the wire carry data:
    ///
    /// - USB 1.x / 2.0 (`low`, `full`, `high`) use NRZI with bit stuffing and no block
    ///   encoding, so the ceiling is simply the signalling rate over 8. (Real throughput is
    ///   far lower once protocol overhead is counted — but this is a *ceiling*, not a
    ///   prediction, and it must never be lower than something achievable.)
    /// - USB 3.0 (`superSpeed`) uses **8b/10b**: 80% of the wire carries data.
    /// - USB 3.1 and later use **128b/132b**: ~97% does.
    public var maximumPayloadBytesPerSecond: Double? {
        guard let lineRate = lineRateBitsPerSecond else { return nil }
        switch self {
        case .low, .full, .high:
            return lineRate / 8
        case .superSpeed:
            return lineRate * 0.8 / 8                        // 8b/10b
        case .superSpeedPlus, .superSpeedPlusBy2:
            return lineRate * (128.0 / 132.0) / 8            // 128b/132b
        case .unrecognised:
            return nil
        }
    }

    /// Margin applied to the payload ceiling to absorb measurement error.
    ///
    /// **1.1 — deliberately small.** The payload rate is a hard physical limit, not an
    /// estimate: measured block-storage throughput does not exceed the negotiated theoretical
    /// maximum. A generous margin would only blunt the check. (An earlier draft used 2×; the
    /// user, from decades of measuring block storage, corrected it — a doubled ceiling
    /// concedes far more than measurement error ever needs.)
    ///
    /// The 10% covers timer granularity, scheduling jitter inside a timed read, and any small
    /// imprecision in the encoding arithmetic above.
    public static let measurementMargin = 1.1

    /// The rate above which a read cannot have come from this device — or `nil` when the link
    /// speed is unknown and the caller must fall back.
    public var implausibleThroughputBytesPerSecond: Double? {
        guard let ceiling = maximumPayloadBytesPerSecond else { return nil }
        return ceiling * Self.measurementMargin
    }

    public var description: String {
        switch self {
        case .low:                return "USB Low Speed (1.5 Mb/s)"
        case .full:               return "USB Full Speed (12 Mb/s)"
        case .high:               return "USB High Speed (480 Mb/s)"
        case .superSpeed:         return "USB SuperSpeed (5 Gb/s)"
        case .superSpeedPlus:     return "USB SuperSpeed+ (10 Gb/s)"
        case .superSpeedPlusBy2:  return "USB SuperSpeed+ 20 Gb/s"
        case .unrecognised(let c): return "an unrecognised link speed (Device Speed = \(c))"
        }
    }
}
