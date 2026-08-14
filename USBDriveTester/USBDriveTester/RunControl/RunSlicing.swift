//
//  RunSlicing.swift
//  USBDriveTester (app target — unprivileged)
//
//  Step 11, increment 4. Where each of a whole-device run's bounded privileged calls begins and
//  how much it covers (FR-TEST-4, FR-TEST-10).
//
//  ## The rule, and where it is actually enforced
//
//  All test I/O begins on a **1 MiB boundary** and covers a **whole number of MiB**, the sole
//  exception being a range that ends at the device's final block (FR-TEST-5's short final chunk).
//  The helper enforces both in `Core/RunPlacement` and **refuses otherwise** — shown refusing on
//  hardware, twice, not assumed. So this type is not the guard; it is the app's arithmetic for
//  staying inside a guard somebody else holds.
//
//  That is why it takes app-side primitives rather than Core's `DeviceGeometry`: `Core/` compiles
//  into the helper and the test target but deliberately **not** into the app module. The two
//  expressions of the rule are therefore independent, and `RunSlicingTests` is the only place both
//  are visible at once — which is what lets it cross-check every slice this produces against
//  `RunPlacement.validate` instead of restating this file's own arithmetic back at it. Same
//  arrangement as `RunControlWireTests` and `DeviceAccessPreconditionTests.causeCodesMatchTheWireEnum`,
//  for the same reason. ``boundaryBytes`` and ``supportedBlockSizes`` are duplicated from Core on
//  those terms, and a test pins each.
//
//  ## A documented justification for this rule was measured and found wrong (2026-08-14)
//
//  CONSTRAINTS section 1 and BUILD-PLAN Step 11 both say a sequencer advancing by *"1 GiB or
//  whatever is left"* is **"refused on its last-but-one call"** against a device whose size is not
//  a whole number of MiB. Checked against `RunPlacement.validate` rather than believed, over the
//  1 TB T5 (1,953,525,168 blocks), the 4 TB T5 EVO (7,814,037,168), the 22 TB Seagate
//  (42,970,644,479) and a 4,096-byte geometry: that sequencer produces **0 refusals** on all four,
//  and slices identical to this file's.
//
//  It is safe for one unstated reason — `TesterProtocol.maximumBytesPerCall` is itself a whole
//  multiple of 1 MiB, so `min(cap, remaining)` is always either a whole 1 GiB or the final
//  remainder, which is exempt. **Give it a cap that is not a whole number of MiB and it is refused
//  on call 2**, not last-but-one. What *is* refused on its last-but-one call is a different
//  sequencer — one that backs the final call up so it is a full 1 GiB — which fails at exactly
//  #931/#932 on the 1 TB T5 and #3726/#3727 on the 4 TB EVO. The recorded symptom belongs to that
//  algorithm; the documents are corrected in increment 7's docs pass.
//
//  **This changes what the test has to do, not what this file does.** Rounding down to a whole MiB
//  is correct for *any* cap where the naive form is correct only for this one — but the two agree
//  on every real geometry, so a suite that only ever sliced real devices could not tell them apart
//  and a mutation deleting the rounding would survive. That is why ``nextCall(from:logicalBlockSize:deviceBlockCount:maximumBytesPerCall:)``
//  takes the cap as a **required parameter with no default** and the suite slices with a
//  deliberately ragged one. Required rather than defaulted for the same reason the engine's
//  `control:` is: a call site that can quietly not say which cap it means is a call site where the
//  answer stops being checked.
//
//  `nonisolated` throughout: the app target compiles with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor,
//  which would otherwise make these value types main-actor-isolated and unusable from the
//  non-isolated test target.
//

import Foundation

// MARK: - One bounded call

/// The range of one bounded privileged call — one `runRetentionCycle`.
nonisolated struct RunCall: Equatable {

    /// First block, in the device's logical blocks. Always on a 1 MiB boundary.
    let startBlock: UInt64

    /// How many blocks this call covers. A whole number of MiB unless this is the final call.
    let blockCount: UInt64

    /// One past the last block this call covers.
    var endBlock: UInt64 { startBlock + blockCount }
}

/// What the slicer has to say about a position in a run.
///
/// Three cases rather than an optional, and the third is the reason. An optional would make
/// *"the run has covered the device"* and *"this geometry cannot be sliced at all"* the same
/// answer — and a sequencer reading that answer would report a **completed run that covered
/// nothing**. An empty result is not a finding; this makes the difference impossible to collapse.
nonisolated enum RunSliceOutcome: Equatable {

    /// Issue this call next.
    case call(RunCall)

    /// The run has reached the device's last block. There is no next call.
    case deviceCovered

    /// No call can be issued from here, and `reason` names why — never a generic failure
    /// (NFR-USE-5). Reachable through the injected cap and through geometry the helper would
    /// itself refuse.
    case cannotSlice(reason: String)
}

// MARK: - The slicer

/// Where a whole-device run's calls fall (FR-TEST-10).
nonisolated enum RunSlicing {

    /// The boundary every call begins on. **1 MiB.**
    ///
    /// Duplicated from `RunPlacement.boundaryBytes`, which is where the rule is enforced, for the
    /// reason in this file's header: Core is not visible to the app module.
    /// `RunSlicingTests.theBoundaryMatchesTheHelpersOwn` pins the two.
    static let boundaryBytes: UInt64 = 1 << 20

    /// Block sizes this tool accepts (NFR-COMPAT-5).
    ///
    /// Duplicated from `DeviceGeometry.supportedBlockSizes` on the same terms, and pinned by
    /// `RunSlicingTests.theSupportedBlockSizesMatchTheHelpersOwn`. Rejected rather than
    /// accommodated: BUILD-PLAN Step 7 is explicit that some USB bridges report impossible
    /// geometry and that the answer is to refuse it.
    static let supportedBlockSizes: Set<UInt32> = [512, 4096]

    /// Blocks per 1 MiB boundary: 2,048 at 512 B, 256 at 4,096 B.
    static func blocksPerBoundary(logicalBlockSize: UInt32) -> UInt64 {
        boundaryBytes / UInt64(logicalBlockSize)
    }

    /// The call to issue from `position`, if there is one.
    ///
    /// A function of the position rather than a precomputed list of every call, and that is
    /// deliberate: a run resumed after a pause continues from the helper's `interruptedAtBlock`,
    /// which is not a call boundary. A list computed at the start would be invalidated by exactly
    /// the thing this step exists to build; a function of the position handles it for free.
    ///
    /// - Parameters:
    ///   - position: first untested block. `0` at the start of a run (FR-TEST-4 — runs always
    ///     start at block 0), or a paused run's resume block. Must be on a 1 MiB boundary, which
    ///     a resume point always is: a run starts on one and every chunk is 1, 2, 4 or 8 MiB
    ///     (measured 1 MiB-aligned in all four pre-flight cases, 2026-08-12).
    ///   - maximumBytesPerCall: the per-call cap. **Required, with no default** — see the header.
    static func nextCall(from position: UInt64,
                         logicalBlockSize: UInt32,
                         deviceBlockCount: UInt64,
                         maximumBytesPerCall: UInt64) -> RunSliceOutcome {

        guard supportedBlockSizes.contains(logicalBlockSize) else {
            let supported = supportedBlockSizes.sorted().map(String.init).joined(separator: " or ")
            return .cannotSlice(reason: "Unsupported logical block size \(logicalBlockSize) bytes; "
                                      + "this tool supports \(supported).")
        }
        guard deviceBlockCount > 0 else {
            return .cannotSlice(reason: "The device reports zero addressable blocks.")
        }

        let blockSize = UInt64(logicalBlockSize)
        let blocksPerBoundary = blocksPerBoundary(logicalBlockSize: logicalBlockSize)

        // Rounded DOWN to a whole number of MiB. This is the line the header is about: with a cap
        // that is already a whole multiple of 1 MiB it changes nothing, and with one that is not
        // it is the difference between every call after the first being aligned and none of them
        // being.
        let blocksPerCall = (maximumBytesPerCall / blockSize / blocksPerBoundary) * blocksPerBoundary
        guard blocksPerCall > 0 else {
            return .cannotSlice(reason: "A per-call cap of \(maximumBytesPerCall) bytes is below "
                                      + "the \(boundaryBytes)-byte (1 MiB) boundary every call "
                                      + "must cover a whole number of, so no call can be issued.")
        }

        guard position <= deviceBlockCount else {
            return .cannotSlice(reason: "Position \(position) is past the device's last block "
                                      + "(\(deviceBlockCount)).")
        }
        guard position < deviceBlockCount else { return .deviceCovered }

        guard position % blocksPerBoundary == 0 else {
            return .cannotSlice(reason: "Block \(position) is byte offset "
                                      + "\(position * blockSize), which is not a multiple of "
                                      + "\(boundaryBytes) (1 MiB). Every call must begin on a "
                                      + "1 MiB boundary (FR-TEST-10).")
        }

        // The only call allowed to be short is the one that reaches the device's last block.
        let remaining = deviceBlockCount - position
        return .call(RunCall(startBlock: position,
                             blockCount: remaining <= blocksPerCall ? remaining : blocksPerCall))
    }
}
