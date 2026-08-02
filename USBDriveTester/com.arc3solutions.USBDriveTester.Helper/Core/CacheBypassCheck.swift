//
//  CacheBypassCheck.swift
//  Core — is the verify read actually reaching the device, or could the host answer it?
//
//  Step 7 (AI-5) builds this; **Step 8 calls it at run start** and gates the verify result on
//  it; Step 10 carries its verdict into the exported report; Step 11 surfaces it in the UI.
//  Satisfies FR-TEST-9 (added 2026-08-02), and protects FR-TEST-3 / FR-TEST-8 / NFR-REL-8
//  from being silently inert.
//
//  Pure — Foundation only, no `fstat`, no `fcntl`, no descriptor. The helper performs the
//  syscalls and passes the *facts* in, which is what makes the whole classification testable
//  with no hardware and no root (NFR-MAINT-2).
//
//  ## The failure this exists to prevent
//
//  FR-TEST-3's cycle reads a chunk, writes it back, reads it again, and compares. If the
//  second read can be satisfied by the host's buffer cache, it returns a copy of what was
//  just written — from RAM — and the comparison succeeds **unconditionally**. The tool would
//  then report every drive as clean, including a failing one, with no error raised anywhere.
//  FR-TEST-8 and NFR-REL-8 would both be present in the code and inert in effect.
//
//  ## Why this is not a timing test, though it was designed as one
//
//  The original design read one chunk twice and compared durations. `scripts/nocache-calibration.sh`
//  measured that on `disk4` (2026-08-02) and it **does not work**:
//
//  | phase | read 0 | read 1 | read 2 | read 3 |
//  |---|---|---|---|---|
//  | `F_NOCACHE` unset | 12,295 µs | 8,829 | 8,786 | 8,737 |
//  | `F_NOCACHE` set   |  8,903 µs | 8,872 | 8,846 | 8,887 |
//
//  A 4 MiB copy from RAM on the same machine takes **58 µs**, so a real cache hit would be
//  ~150× faster than any of those. The small first-read difference is warm-up: repeated at
//  8 MiB, the *absolute* overhead barely moved (≈3.6 ms → ≈4.1 ms) while the transfer
//  doubled, so the ratio *fell* (1.41 → 1.23) — the signature of a fixed start-up cost, and
//  the opposite of what caching would do.
//
//  The cause: `/dev/rdiskN` is the **character** device (`crw-`), and the unified buffer
//  cache belongs to the **block** device (`/dev/diskN`, `brw-`). The raw path was never
//  cached, so `F_NOCACHE` had nothing to suppress, and its `rc == 0` meant as little as the
//  `/dev/null` measurement suggested it would.
//
//  ## The asymmetry that shapes everything below
//
//  > **Timing can falsify, but it cannot verify.** A read returning far faster than the
//  > transport allows *proves* the host answered it. Two similar timings prove nothing at
//  > all, because they are identical whether caching was suppressed or was never possible.
//
//  So ``CacheBypassState/bypassed`` never rests on timing. It rests on a **structural** fact
//  — the descriptor is the character device — which is checkable, is not a heuristic, and
//  catches the failure that can realistically occur: opening `/dev/diskN` instead of
//  `/dev/rdiskN`. That is a one-character bug that would make every verify in every run
//  vacuous, and nothing else in the system would notice it.
//
//  Timing is kept only as a falsifier, where it is sound.
//
//  ## What none of this can establish
//
//  That the verify read came from **NAND**. The drive's own DRAM/SLC cache sits below every
//  host mechanism, and a read-back moments after a write may legitimately be served from it.
//  This check proves the data round-tripped through the device's I/O path; it does not prove
//  the medium retained it. That limit is real, is not fixable from here, and belongs with
//  Step 14's honest framing (FR-WARN-3, "a clean pass is not a healthy drive") rather than
//  being carried silently.
//

import Foundation

// MARK: - What kind of node was actually opened

/// The kind of file the run's descriptor refers to.
///
/// Derived from `fstat`'s `st_mode` by the helper, classified here. The distinction is the
/// whole basis of the check: on macOS the buffer cache is a property of the **block** device.
public enum DeviceNodeKind: Equatable, CustomStringConvertible {

    /// `/dev/rdiskN` — the raw, unbuffered character device. **Required** (FR-TEST-6).
    /// Measured: `/dev/rdisk4` is mode `0o20640`.
    case character

    /// `/dev/diskN` — the buffered block device. Reads through it may be served from the
    /// unified buffer cache, which would make the verify vacuous. Measured: `/dev/disk4` is
    /// mode `0o60640`.
    case block

    /// Anything else — a regular file, a pipe, a socket. Reached in tests (a temporary file
    /// stands in for a device) and never expected in a run.
    case other(mode: UInt32)

    /// Classify `fstat`'s `st_mode`.
    ///
    /// Pure bit arithmetic, so the classification is unit-testable without a device — the
    /// helper supplies the mode, this decides what it means.
    public static func from(statMode: mode_t) -> DeviceNodeKind {
        switch statMode & S_IFMT {
        case S_IFCHR: return .character
        case S_IFBLK: return .block
        default:      return .other(mode: UInt32(statMode & S_IFMT))
        }
    }

    public var description: String {
        switch self {
        case .character:      return "character device (raw, unbuffered)"
        case .block:          return "block device (buffered)"
        case .other(let m):   return "not a device node (mode 0o\(String(m, radix: 8)))"
        }
    }
}

/// The facts the helper gathered when it configured the descriptor for uncached I/O.
///
/// A plain value type with no descriptor attached, so the same classification runs against
/// real syscall results in the helper and against constructed ones in tests.
public struct UncachedIOConfiguration: Equatable {

    /// The path that was opened, for the message. Not itself the check — what matters is
    /// what the descriptor *is*, not what it was asked to be.
    public let devicePath: String

    /// What `fstat` says the descriptor refers to. **This is the verifier.**
    public let nodeKind: DeviceNodeKind

    /// `fcntl(fd, F_NOCACHE, 1)`'s return value; 0 on success.
    public let noCacheResult: Int32

    /// `fcntl(fd, F_GLOBAL_NOCACHE, 1)`'s return value; 0 on success.
    public let globalNoCacheResult: Int32

    public init(devicePath: String,
                nodeKind: DeviceNodeKind,
                noCacheResult: Int32,
                globalNoCacheResult: Int32) {
        self.devicePath = devicePath
        self.nodeKind = nodeKind
        self.noCacheResult = noCacheResult
        self.globalNoCacheResult = globalNoCacheResult
    }
}

// MARK: - The verdict

/// Whether the run's reads can be trusted to have reached the device.
///
/// Three states rather than a `Bool`, matching ``FullDiskAccessState`` and
/// `HelperShutdownReadiness`: the check can be conclusive in two directions, and anything
/// else must not be reported as either.
public enum CacheBypassState: Equatable, CustomStringConvertible {

    /// The descriptor is the character device and both no-cache calls succeeded. Reads reach
    /// the device; the verify means what it says.
    case bypassed

    /// Something can answer a read without the device. **The verify result is not
    /// trustworthy** — but the run's read → write-back still refreshes the medium, so the
    /// run continues and the result is qualified (FR-TEST-9).
    case likelyCached(reason: String)

    /// The question could not be settled. Never reported as either of the above.
    case inconclusive(detail: String)

    /// Wire value for the XPC boundary, so the app can branch rather than parse prose.
    ///
    /// - Important: duplicated by the app-side enum in `Shared/TesterControl.swift`, exactly
    ///   as `DeviceAccessRefusal.causeCode` is — Core cannot be shared with the app module.
    ///   A test pins the two together; it is the only place both are visible at once.
    public var wireCode: Int {
        switch self {
        case .bypassed:     return 1
        case .likelyCached: return 2
        case .inconclusive: return 3
        }
    }

    /// Does this verdict qualify the run's verify result (FR-TEST-9)?
    public var qualifiesVerifyResult: Bool { self != .bypassed }

    /// The line that goes in the run report — **always present, in every state.**
    ///
    /// Mandatory rather than conditional, because a line that appears only on failure is
    /// indistinguishable from a missing one, and the exported Markdown outlives the session.
    /// A report saying "0 bad blocks" that has outlived its qualification reproduces the
    /// exact silent failure this whole file exists to prevent (Step 10.3).
    public var reportLine: String {
        switch self {
        case .bypassed:
            return "Cache bypass verified: reads were issued to the raw character device "
                 + "with caching disabled, so the verify compared data read back from the "
                 + "drive."
        case .likelyCached(let reason):
            return "CACHE BYPASS NOT VERIFIED — the verify result below may be unreliable. "
                 + "\(reason) The read and write-back still reached the drive, so the "
                 + "refresh this run performed remains valid; what cannot be relied on is "
                 + "the comparison that looks for faults."
        case .inconclusive(let detail):
            return "Cache bypass could not be confirmed — the verify result below may be "
                 + "unreliable. \(detail) The refresh this run performed remains valid; the "
                 + "fault comparison is the part in doubt."
        }
    }

    /// What to show the user while the run is live, or `nil` when there is nothing to say.
    ///
    /// `bypassed` returns `nil` deliberately — the same reasoning as
    /// ``FullDiskAccessState/explanation``: a banner that is always on screen is one nobody
    /// reads by the time it matters.
    public var userWarning: String? {
        switch self {
        case .bypassed:
            return nil
        case .likelyCached, .inconclusive:
            return reportLine
        }
    }

    public var description: String {
        switch self {
        case .bypassed:                 return "bypassed"
        case .likelyCached(let reason): return "likelyCached(\(reason))"
        case .inconclusive(let detail): return "inconclusive(\(detail))"
        }
    }
}

// MARK: - The check

public enum CacheBypassCheck {

    /// The fallback ceiling, used **only** when the device's link speed is unavailable or
    /// unrecognised.
    ///
    /// **8 GB/s.** No USB link of any current generation carries this, so a read above it did
    /// not cross a wire, whatever the registry says the wire is. That property is what makes
    /// it safe as a backstop: it cannot be wrong in the dangerous direction.
    ///
    /// | anchor | rate | source |
    /// |---|---|---|
    /// | `disk4`, 4 MiB reads over USB 3.1 Gen 2 | 0.475 GB/s | measured 2026-08-02 |
    /// | fastest USB mass storage that exists (USB4 / 3.2 Gen 2×2) | ~2–3.8 GB/s | published limits |
    /// | 4 MiB copy from RAM on this machine | **71.3 GB/s** | measured 2026-08-02 |
    ///
    /// Prefer ``USBLinkSpeed/implausibleThroughputBytesPerSecond``, which is derived from the
    /// negotiated link and is 3–8× tighter. This exists so an unknown link degrades to a
    /// loose-but-sound check rather than to no check.
    public static let fallbackImplausibleThroughputBytesPerSecond: Double = 8_000_000_000

    /// Classify the descriptor the run will use. This is the run-start check (FR-TEST-9).
    ///
    /// Order matters: the node kind is decided first, because it is the only *verifying*
    /// evidence available and because a block device makes the rest moot.
    public static func evaluate(_ configuration: UncachedIOConfiguration) -> CacheBypassState {

        switch configuration.nodeKind {
        case .block:
            // The failure this check exists for. `/dev/diskN` goes through the unified buffer
            // cache, so the verify read could be answered without the drive.
            return .likelyCached(reason:
                "\(configuration.devicePath) is a buffered block device, not the raw "
              + "character device. Reads through it can be answered from the host's buffer "
              + "cache, which would make the verify comparison meaningless.")

        case .other(let mode):
            return .inconclusive(detail:
                "\(configuration.devicePath) is not a device node (mode 0o\(String(mode, radix: 8))), "
              + "so whether reads reach real media cannot be established.")

        case .character:
            break
        }

        // A character device is structurally uncached — that is the finding the calibration
        // established. But FR-TEST-6 also *requires* the flags to be set, and a required step
        // that failed is not a clean bypass even when it is harmless. Reported as
        // inconclusive rather than as either extreme.
        if configuration.noCacheResult != 0 || configuration.globalNoCacheResult != 0 {
            var failed: [String] = []
            if configuration.noCacheResult != 0 { failed.append("F_NOCACHE") }
            if configuration.globalNoCacheResult != 0 { failed.append("F_GLOBAL_NOCACHE") }
            return .inconclusive(detail:
                "\(configuration.devicePath) is the raw character device, which is not "
              + "buffered by the host — but \(failed.joined(separator: " and ")) could not be "
              + "set on it, so FR-TEST-6's requirement was not fully met.")
        }

        return .bypassed
    }
}

// MARK: - Falsification during the run

/// The run-start verdict, plus whatever the run's own throughput later reveals.
///
/// Separate from ``CacheBypassCheck/evaluate(_:)`` because the two kinds of evidence arrive
/// at different times and carry different weight: the structural check runs once and can
/// *verify*; throughput observations arrive per chunk and can only *falsify*.
///
/// ## Two ceilings, and why the tight one has to earn its place
///
/// The preferred ceiling is derived from the device's negotiated link speed — a hard physical
/// limit, 3–8× tighter than the fixed fallback. But that derivation rests on a registry enum
/// that is **not** documented in any SDK header (see ``USBLinkSpeed``), and a mapping that
/// shifted by one in the wrong direction would put the ceiling below every legitimate read
/// and flag every run as cached.
///
/// So the derived ceiling is treated as a claim that must be **confirmed**: it is trusted
/// only once a read has actually come in at or below it. Until then, exceeding it is read as
/// evidence against *the ceiling*, not against the drive — because a bad speed code makes
/// every read exceed from the very first, whereas caching appears against a background of
/// normal reads. Exceeding the *fallback* ceiling is unambiguous either way and always
/// counts, since no USB link of any generation reaches it.
public struct CacheBypassAssessment: Equatable {

    /// The current verdict. Only ever moves toward ``CacheBypassState/likelyCached(reason:)``.
    public private(set) var state: CacheBypassState

    /// The fastest read seen so far, in bytes per second. Recorded so the report can say what
    /// was actually observed rather than only that a threshold was or was not crossed.
    public private(set) var fastestObservedBytesPerSecond: Double = 0

    /// The link-derived ceiling, or `nil` once it has been abandoned as not credible (or if
    /// there never was one).
    public private(set) var derivedCeilingBytesPerSecond: Double?

    /// Whether a read has come in at or below ``derivedCeilingBytesPerSecond``, which is what
    /// makes it credible.
    public private(set) var derivedCeilingConfirmed = false

    /// Set if the derived ceiling was abandoned, saying why — so a run that fell back to the
    /// loose ceiling explains itself rather than silently becoming less sensitive.
    public private(set) var derivedCeilingAbandonedReason: String?

    /// How the link speed was established, for the report.
    public let linkSpeed: USBLinkSpeed?

    /// Reads smaller than this are not fed to the falsifier.
    ///
    /// At small sizes the measured rate is dominated by fixed per-operation latency and by
    /// timer granularity, so a single fast small read could clear a tight ceiling without any
    /// caching involved. Step 8 reads whole chunks (1–8 MiB), so this excludes nothing real.
    public static let minimumBytesForThroughputJudgement = 64 * 1024

    public init(_ configuration: UncachedIOConfiguration, linkSpeed: USBLinkSpeed? = nil) {
        self.state = CacheBypassCheck.evaluate(configuration)
        self.linkSpeed = linkSpeed
        self.derivedCeilingBytesPerSecond = linkSpeed?.implausibleThroughputBytesPerSecond
    }

    /// The ceiling currently in force.
    public var effectiveCeilingBytesPerSecond: Double {
        derivedCeilingBytesPerSecond
            ?? CacheBypassCheck.fallbackImplausibleThroughputBytesPerSecond
    }

    /// Feed one completed read into the falsifier.
    ///
    /// **Only ever downgrades.** A plausible rate is not evidence of anything — it is exactly
    /// what an uncached read looks like *and* what a slow cache hit would look like — so it
    /// never promotes a verdict. An implausible rate is proof the host answered, so it
    /// overrides even `bypassed`: the structural check can be right about the node and still
    /// be wrong about the outcome, and measured behaviour beats inferred structure.
    ///
    /// - Returns: `true` if this observation changed the verdict.
    @discardableResult
    public mutating func observe(bytes: Int, nanoseconds: UInt64) -> Bool {
        guard bytes >= Self.minimumBytesForThroughputJudgement else { return false }

        // A read of real bytes that took no measurable time did not reach a USB device.
        // Treated as infinitely fast rather than skipped, so it cannot slip past the check.
        let rate = nanoseconds == 0
            ? Double.infinity
            : Double(bytes) / (Double(nanoseconds) / 1_000_000_000)

        if rate > fastestObservedBytesPerSecond { fastestObservedBytesPerSecond = rate }

        // Above the fallback ceiling is unambiguous: no USB link of any generation carries
        // this, so no reading of any enum could make it legitimate.
        if rate > CacheBypassCheck.fallbackImplausibleThroughputBytesPerSecond {
            return flagCached(rate: rate,
                              bytes: bytes,
                              ceiling: CacheBypassCheck.fallbackImplausibleThroughputBytesPerSecond)
        }

        guard let derived = derivedCeilingBytesPerSecond else { return false }

        if rate <= derived {
            // The link has demonstrably been operated below this ceiling, so the ceiling is
            // credible from here on.
            derivedCeilingConfirmed = true
            return false
        }

        guard derivedCeilingConfirmed else {
            // Never yet seen a read below it, so the ceiling itself is the doubtful part.
            // Abandon it rather than accuse the drive; the fallback still applies.
            derivedCeilingAbandonedReason =
                "the first qualifying read ran at \(Self.rate(rate)), above the "
              + "\(Self.rate(derived)) ceiling implied by \(linkSpeed?.description ?? "the link speed"). "
              + "A link cannot be exceeded, so the reported link speed is not credible; the "
              + "check fell back to \(Self.rate(CacheBypassCheck.fallbackImplausibleThroughputBytesPerSecond))."
            derivedCeilingBytesPerSecond = nil
            return false
        }

        return flagCached(rate: rate, bytes: bytes, ceiling: derived)
    }

    private mutating func flagCached(rate: Double, bytes: Int, ceiling: Double) -> Bool {
        if case .likelyCached = state { return false }      // already there; do not restate
        state = .likelyCached(reason:
            "A \(bytes)-byte read completed at \(Self.rate(rate)), above the "
          + "\(Self.rate(ceiling)) this link can carry"
          + (linkSpeed.map { " (\($0))" } ?? "")
          + ". The host answered that read, so the verify comparison cannot be trusted.")
        return true
    }

    private static func rate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite else { return "an immeasurably short time" }
        if bytesPerSecond >= 1_000_000_000 {
            return String(format: "%.2f GB/s", bytesPerSecond / 1_000_000_000)
        }
        return String(format: "%.0f MB/s", bytesPerSecond / 1_000_000)
    }
}
