//
//  CacheBypassCheckTests.swift
//  FR-TEST-9: is the verify read reaching the device, or could the host answer it?
//
//  Two things are under test and they fail in different directions, so they are kept apart
//  below:
//
//    * `USBLinkSpeed` — a mapping established by *evidence* rather than from any SDK header.
//      Its risk is silent drift, and being wrong by one step in the slow direction would flag
//      every read of every run as cached.
//    * `CacheBypassCheck` / `CacheBypassAssessment` — the classification. Its risk is
//      reporting `bypassed` on evidence that would say `bypassed` regardless, which is the
//      exact defect FR-TEST-9 exists to prevent.
//
//  Hardware anchors used throughout, all measured 2026-08-02 (see PROGRESS):
//
//    | quantity | value |
//    |---|---|
//    | `disk4` link | Device Speed 4 -> 10 Gb/s -> ceiling 1.333 GB/s |
//    | `disk8` link | Device Speed 3 -> 5 Gb/s -> ceiling 0.550 GB/s |
//    | `disk4` real read | 4 MiB in ~8,800 us -> ~476 MB/s |
//    | 4 MiB copy from RAM | 58 us -> ~72.3 GB/s |
//    | `/dev/rdisk4` mode | 0o20640 (character) |
//    | `/dev/disk4` mode | 0o60640 (block) |
//

import Testing
import Foundation
@testable import USBDriveTester

// MARK: - The link-speed mapping

struct USBLinkSpeedTests {

    /// The codes actually observed on this machine, each checked against the standard the
    /// device is known to implement (ten devices, zero anomalies — `scripts/usb-speed-check.sh`).
    @Test func observedDeviceSpeedCodesMapToTheStandardsThoseDevicesImplement() {
        #expect(USBLinkSpeed.from(deviceSpeedCode: 0) == .low)          // keyboard, mouse
        #expect(USBLinkSpeed.from(deviceSpeedCode: 2) == .high)         // USB2 / USB2.1 hubs
        #expect(USBLinkSpeed.from(deviceSpeedCode: 3) == .superSpeed)   // Expansion HDD (USB 3.0)
        #expect(USBLinkSpeed.from(deviceSpeedCode: 4) == .superSpeedPlus) // T5 (USB 3.1 Gen 2)
    }

    /// **The finding this whole mapping rests on, encoded so it cannot be quietly undone.**
    ///
    /// `IOUSBHostFamilyDefinitions.h` defines `tIOUSBHostConnectionSpeed` with `None = 0`,
    /// but that documents a *different* registry property. Under that enum a connected USB
    /// keyboard — which reports 0 — would mean "no device is connected". If someone ever
    /// "corrects" `USBLinkSpeed` to match the SDK header, this fails.
    @Test func codeZeroIsLowSpeedNotTheSDKEnumsNoDeviceConnected() {
        #expect(USBLinkSpeed.from(deviceSpeedCode: 0) == .low)
        #expect(USBLinkSpeed.from(deviceSpeedCode: 0).lineRateBitsPerSecond == 1_500_000.0)

        // Under tIOUSBHostConnectionSpeed these three would be Low, High and Super. They are
        // not, and a connected keyboard reporting 0 is the observation that proves it.
        #expect(USBLinkSpeed.from(deviceSpeedCode: 2) != .low)
        #expect(USBLinkSpeed.from(deviceSpeedCode: 3) != .high)
        #expect(USBLinkSpeed.from(deviceSpeedCode: 4) != .superSpeed)
    }

    /// An unknown code is never guessed at — it yields no ceiling, and the caller falls back.
    @Test func unrecognisedCodesYieldNoCeiling() {
        let future = USBLinkSpeed.from(deviceSpeedCode: 9)
        #expect(future == .unrecognised(code: 9))
        #expect(future.lineRateBitsPerSecond == nil)
        #expect(future.maximumPayloadBytesPerSecond == nil)
        #expect(future.implausibleThroughputBytesPerSecond == nil)
    }

    /// Physical-layer encoding is not a rule of thumb — it is how many bits of the wire carry
    /// data. 8b/10b for USB 3.0, 128b/132b from 3.1, no block encoding below that.
    ///
    /// - Note: every expected value here is written as an explicit `Double`. Inside `#expect`
    ///   the macro captures each operand separately, and a *compound* integer-literal
    ///   expression such as `480_000_000 / 8` takes its default type (`Int`) rather than
    ///   being promoted — which made this assertion fail against a value that was in fact
    ///   equal. A bare literal infers correctly, so the two behave differently for no visible
    ///   reason. The same mechanism could as easily produce a false pass.
    @Test func payloadCeilingsApplyTheCorrectLineEncoding() throws {
        let highSpeed = try #require(USBLinkSpeed.high.maximumPayloadBytesPerSecond)
        #expect(highSpeed == 60_000_000.0)                   // 480 Mb/s / 8, no block encoding

        let superSpeed = try #require(USBLinkSpeed.superSpeed.maximumPayloadBytesPerSecond)
        #expect(superSpeed == 500_000_000.0)                 // 5 Gb/s x 8b/10b / 8

        let tenGigabit = try #require(USBLinkSpeed.superSpeedPlus.maximumPayloadBytesPerSecond)
        #expect(abs(tenGigabit - 1_212_121_212.0) < 1.0)     // 10 Gb/s x 128b/132b / 8

        let twentyGigabit = try #require(USBLinkSpeed.superSpeedPlusBy2.maximumPayloadBytesPerSecond)
        #expect(abs(twentyGigabit - 2_424_242_424.0) < 1.0)
    }

    /// The margin is small on purpose: the payload rate is a hard physical limit, not an
    /// estimate to pad. A generous margin would only blunt the check.
    @Test func measurementMarginIsTenPercent() throws {
        #expect(USBLinkSpeed.measurementMargin == 1.1)

        let ceiling = try #require(USBLinkSpeed.superSpeedPlus.implausibleThroughputBytesPerSecond)
        #expect(abs(ceiling - 1_333_333_333.0) < 2.0)
    }

    /// `disk4`'s measured throughput must sit comfortably below its own derived ceiling —
    /// otherwise the check would fire on a healthy drive on every run.
    @Test func measuredHardwareThroughputSitsWellBelowItsDerivedCeiling() throws {
        let ceiling = try #require(USBLinkSpeed.superSpeedPlus.implausibleThroughputBytesPerSecond)
        let measured = Double(4 << 20) / (8_800_000.0 / 1_000_000_000.0)   // 4 MiB in 8.8 ms

        #expect(measured < ceiling)
        #expect(ceiling / measured > 2.0, "at least 2x headroom over what the drive really does")

        // And a RAM-served read must be far above it — that is the thing being caught.
        let fromRAM = Double(4 << 20) / (58_000.0 / 1_000_000_000.0)       // 4 MiB in 58 us
        #expect(fromRAM > ceiling * 50.0)
    }

    /// A faster link never yields a lower ceiling.
    @Test func ceilingsIncreaseWithLinkSpeed() {
        let ordered: [USBLinkSpeed] = [.low, .full, .high, .superSpeed,
                                       .superSpeedPlus, .superSpeedPlusBy2]
        let ceilings = ordered.compactMap(\.implausibleThroughputBytesPerSecond)
        #expect(ceilings.count == ordered.count)
        #expect(ceilings == ceilings.sorted())
    }
}

// MARK: - Node classification

struct DeviceNodeKindTests {

    /// The real modes, read from the live device nodes 2026-08-02.
    @Test func realDeviceNodeModesClassifyCorrectly() {
        #expect(DeviceNodeKind.from(statMode: 0o20640) == .character)   // /dev/rdisk4
        #expect(DeviceNodeKind.from(statMode: 0o60640) == .block)       // /dev/disk4
    }

    @Test func aRegularFileIsNeitherKindOfDevice() {
        let kind = DeviceNodeKind.from(statMode: 0o100644)              // S_IFREG
        #expect(kind != .character)
        #expect(kind != .block)
        if case .other = kind {} else {
            Issue.record("a regular file should classify as .other, got \(kind)")
        }
    }
}

// MARK: - The run-start structural check

struct CacheBypassCheckTests {

    private func configuration(_ kind: DeviceNodeKind,
                               noCache: Int32 = 0,
                               globalNoCache: Int32 = 0,
                               path: String = "/dev/rdisk4") -> UncachedIOConfiguration {
        UncachedIOConfiguration(devicePath: path,
                                nodeKind: kind,
                                noCacheResult: noCache,
                                globalNoCacheResult: globalNoCache)
    }

    @Test func rawCharacterDeviceWithBothFlagsSetIsBypassed() {
        #expect(CacheBypassCheck.evaluate(configuration(.character)) == .bypassed)
    }

    /// **The failure this check exists for.** Opening `/dev/diskN` instead of `/dev/rdiskN`
    /// is a one-character bug that would make every verify in every run vacuous, and nothing
    /// else in the system would notice.
    @Test func aBlockDeviceIsReportedAsLikelyCached() {
        let state = CacheBypassCheck.evaluate(configuration(.block, path: "/dev/disk4"))
        guard case .likelyCached(let reason) = state else {
            Issue.record("a block device must be reported as likelyCached, got \(state)")
            return
        }
        #expect(reason.contains("buffer cache"))
        #expect(state.qualifiesVerifyResult)
    }

    /// A character device is structurally uncached, but FR-TEST-6 also *requires* the flags
    /// to be set. A required step that failed is not a clean bypass even when it is harmless.
    @Test func aFailedFcntlOnACharacterDeviceIsInconclusiveNotBypassed() {
        let state = CacheBypassCheck.evaluate(configuration(.character, noCache: -1))
        guard case .inconclusive(let detail) = state else {
            Issue.record("expected inconclusive, got \(state)")
            return
        }
        #expect(detail.contains("F_NOCACHE"))
        #expect(state != .bypassed)
    }

    @Test func aFailedGlobalFcntlIsAlsoInconclusive() {
        let state = CacheBypassCheck.evaluate(configuration(.character, globalNoCache: -1))
        if case .inconclusive(let detail) = state {
            #expect(detail.contains("F_GLOBAL_NOCACHE"))
        } else {
            Issue.record("expected inconclusive, got \(state)")
        }
    }

    @Test func somethingThatIsNotADeviceNodeIsInconclusive() {
        let state = CacheBypassCheck.evaluate(configuration(.other(mode: 0o100000)))
        if case .inconclusive = state {} else {
            Issue.record("expected inconclusive, got \(state)")
        }
    }

    // MARK: Reporting obligations (FR-TEST-9, Step 10.3)

    /// The report line is **mandatory in every state**, including success: a line that appears
    /// only on failure is indistinguishable from a missing one, and the exported Markdown
    /// outlives the session.
    @Test func everyStateProducesAReportLine() {
        let states: [CacheBypassState] = [.bypassed,
                                          .likelyCached(reason: "r"),
                                          .inconclusive(detail: "d")]
        for state in states {
            #expect(!state.reportLine.isEmpty, "\(state) produced no report line")
        }
    }

    /// A qualified result must say *both* things: the verify is doubtful, and the refresh
    /// still happened. Dropping the second half would overstate the damage and imply the run
    /// was worthless.
    @Test func aQualifiedReportSaysTheRefreshRemainsValid() {
        #expect(CacheBypassState.likelyCached(reason: "r").reportLine.contains("refresh"))
        #expect(CacheBypassState.inconclusive(detail: "d").reportLine.contains("refresh"))
    }

    /// Live UI warning only when there is something to say — a banner that is always on
    /// screen is one nobody reads by the time it matters.
    @Test func onlyNonBypassedStatesWarnTheUser() {
        #expect(CacheBypassState.bypassed.userWarning == nil)
        #expect(CacheBypassState.likelyCached(reason: "r").userWarning != nil)
        #expect(CacheBypassState.inconclusive(detail: "d").userWarning != nil)
        #expect(!CacheBypassState.bypassed.qualifiesVerifyResult)
    }

    @Test func wireCodesAreStableAndDistinct() {
        #expect(CacheBypassState.bypassed.wireCode == 1)
        #expect(CacheBypassState.likelyCached(reason: "r").wireCode == 2)
        #expect(CacheBypassState.inconclusive(detail: "d").wireCode == 3)
    }

    // MARK: - Wire-code agreement
    //
    // The one place both representations are visible at once: Core arrives in this target as
    // source, `CacheBypassOutcome` through @testable import. They are separate types because
    // Core is deliberately not compiled into the app module, so nothing but this test stops
    // them drifting — the same arrangement as `causeCodesMatchTheWireEnum`.

    @Test func cacheBypassCodesMatchTheWireEnum() {
        let pairs: [(CacheBypassState, CacheBypassOutcome)] = [
            (.bypassed, .bypassed),
            (.likelyCached(reason: "x"), .likelyCached),
            (.inconclusive(detail: "x"), .inconclusive),
        ]

        for (state, outcome) in pairs {
            #expect(state.wireCode == outcome.rawValue)
            #expect(CacheBypassOutcome(wireValue: state.wireCode) == outcome)
            #expect(state.qualifiesVerifyResult == outcome.qualifiesVerifyResult,
                    "both sides must agree on whether the verify result is qualified")
        }
    }

    /// A helper newer than the app must never have an unknown outcome read as success — the
    /// same rule as `DeviceAccessRefusalCause`, and for the same reason.
    @Test func anUnknownCacheBypassCodeDegradesToUnrecognisedAndStillQualifies() {
        #expect(CacheBypassOutcome(wireValue: 99) == .unrecognised)
        #expect(CacheBypassOutcome(wireValue: -1) == .unrecognised)
        #expect(CacheBypassOutcome.unrecognised.qualifiesVerifyResult,
                "an outcome this build cannot interpret must qualify the result, not clear it")
    }
}

// MARK: - The falsifier, and its guards

struct CacheBypassAssessmentTests {

    private let fourMiB = 4 << 20

    private var healthyConfiguration: UncachedIOConfiguration {
        UncachedIOConfiguration(devicePath: "/dev/rdisk4",
                                nodeKind: .character,
                                noCacheResult: 0,
                                globalNoCacheResult: 0)
    }

    /// Nanoseconds needed for `bytes` to be delivered at `bytesPerSecond`.
    private func nanoseconds(for bytes: Int, at bytesPerSecond: Double) -> UInt64 {
        UInt64(Double(bytes) / bytesPerSecond * 1_000_000_000)
    }

    // MARK: The ordinary case

    /// `disk4` doing exactly what it really does: 4 MiB in 8.8 ms. Must confirm the ceiling
    /// and leave the verdict alone.
    @Test func realWorldThroughputConfirmsTheCeilingAndChangesNothing() {
        var assessment = CacheBypassAssessment(healthyConfiguration, linkSpeed: .superSpeedPlus)
        #expect(assessment.state == .bypassed)

        let changed = assessment.observe(bytes: fourMiB, nanoseconds: 8_800_000)

        #expect(!changed)
        #expect(assessment.state == .bypassed)
        #expect(assessment.derivedCeilingConfirmed)
        #expect(assessment.derivedCeilingAbandonedReason == nil)
        #expect(assessment.fastestObservedBytesPerSecond > 400_000_000.0)
    }

    /// Once the ceiling has proved itself, a read above it is a genuine finding.
    @Test func aConfirmedCeilingCatchesAnImplausiblyFastRead() {
        var assessment = CacheBypassAssessment(healthyConfiguration, linkSpeed: .superSpeedPlus)
        assessment.observe(bytes: fourMiB, nanoseconds: 8_800_000)      // confirms
        #expect(assessment.derivedCeilingConfirmed)

        // 2 GB/s: above disk4's 1.333 GB/s ceiling, below the 8 GB/s fallback. Only the
        // derived ceiling can catch this, which is the whole point of deriving it.
        let changed = assessment.observe(bytes: fourMiB,
                                          nanoseconds: nanoseconds(for: fourMiB, at: 2_000_000_000))

        #expect(changed)
        if case .likelyCached(let reason) = assessment.state {
            #expect(reason.contains("10 Gb/s"), "names the link it exceeded")
        } else {
            Issue.record("expected likelyCached, got \(assessment.state)")
        }
    }

    // MARK: Guard 1 — an unconfirmed ceiling is the suspect, not the drive

    /// The misread-enum scenario. If a 10 Gb/s link were read as Low Speed, the ceiling would
    /// be ~0.2 MB/s and **every** read would exceed it from the very first. That must abandon
    /// the ceiling, not accuse the drive.
    @Test func aCeilingExceededBeforeItIsConfirmedIsAbandonedNotEnforced() {
        var assessment = CacheBypassAssessment(healthyConfiguration, linkSpeed: .low)
        #expect(assessment.state == .bypassed)

        let changed = assessment.observe(bytes: fourMiB, nanoseconds: 8_800_000)  // 476 MB/s

        #expect(!changed)
        #expect(assessment.state == .bypassed, "a bad speed code must not flag a healthy drive")
        #expect(assessment.derivedCeilingBytesPerSecond == nil, "the ceiling was abandoned")
        #expect(assessment.derivedCeilingAbandonedReason != nil, "and said why")
        #expect(assessment.effectiveCeilingBytesPerSecond
                == CacheBypassCheck.fallbackImplausibleThroughputBytesPerSecond)
    }

    /// Having fallen back, the check must still work — just less tightly.
    @Test func afterAbandoningTheCeilingTheFallbackStillCatchesCaching() {
        var assessment = CacheBypassAssessment(healthyConfiguration, linkSpeed: .low)
        assessment.observe(bytes: fourMiB, nanoseconds: 8_800_000)       // abandons
        #expect(assessment.state == .bypassed)

        // 4 MiB from RAM: 58 us, ~72 GB/s — above the 8 GB/s fallback.
        let changed = assessment.observe(bytes: fourMiB, nanoseconds: 58_000)

        #expect(changed)
        #expect(assessment.state.qualifiesVerifyResult)
    }

    // MARK: Guard 2 — the fallback is unconditional

    /// No USB link of any generation carries 8 GB/s, so exceeding the fallback is unambiguous
    /// however the enum is read — it counts even before any ceiling has been confirmed.
    @Test func exceedingTheFallbackCeilingCountsEvenWithAnUnconfirmedCeiling() {
        var assessment = CacheBypassAssessment(healthyConfiguration, linkSpeed: .superSpeedPlus)
        #expect(!assessment.derivedCeilingConfirmed)

        let changed = assessment.observe(bytes: fourMiB, nanoseconds: 58_000)   // ~72 GB/s

        #expect(changed)
        #expect(assessment.state.qualifiesVerifyResult)
    }

    /// A read of real bytes that took no measurable time did not reach a USB device.
    @Test func aZeroDurationReadIsTreatedAsInfinitelyFast() {
        var assessment = CacheBypassAssessment(healthyConfiguration, linkSpeed: .superSpeedPlus)
        let changed = assessment.observe(bytes: fourMiB, nanoseconds: 0)
        #expect(changed)
        #expect(assessment.state.qualifiesVerifyResult)
    }

    // MARK: Direction of travel

    /// A plausible rate is not evidence of anything — it is what an uncached read *and* a slow
    /// cache hit both look like. The verdict must never improve.
    @Test func theVerdictOnlyEverDowngrades() {
        var assessment = CacheBypassAssessment(healthyConfiguration, linkSpeed: .superSpeedPlus)
        assessment.observe(bytes: fourMiB, nanoseconds: 8_800_000)
        assessment.observe(bytes: fourMiB, nanoseconds: 58_000)          // -> likelyCached
        #expect(assessment.state.qualifiesVerifyResult)

        for _ in 0 ..< 5 {
            assessment.observe(bytes: fourMiB, nanoseconds: 8_800_000)   // perfectly normal
        }
        #expect(assessment.state.qualifiesVerifyResult, "a normal read must not clear a flag")
    }

    /// A structural failure is not repaired by plausible throughput either.
    @Test func plausibleThroughputDoesNotRepairAStructuralFailure() {
        let onTheBlockDevice = UncachedIOConfiguration(devicePath: "/dev/disk4",
                                                        nodeKind: .block,
                                                        noCacheResult: 0,
                                                        globalNoCacheResult: 0)
        var assessment = CacheBypassAssessment(onTheBlockDevice, linkSpeed: .superSpeedPlus)
        #expect(assessment.state.qualifiesVerifyResult)

        assessment.observe(bytes: fourMiB, nanoseconds: 8_800_000)
        #expect(assessment.state.qualifiesVerifyResult)
    }

    // MARK: Small reads

    /// At small sizes the measured rate is dominated by fixed per-operation latency and timer
    /// granularity, so a fast small read could clear a tight ceiling with no caching involved.
    /// Step 8 reads whole chunks of 1–8 MiB, so nothing real is excluded.
    @Test func readsBelowTheMinimumSizeAreNotJudged() {
        var assessment = CacheBypassAssessment(healthyConfiguration, linkSpeed: .superSpeedPlus)

        // A single 512-byte block returned in 100 ns is 5.1 GB/s — over the derived ceiling.
        let changed = assessment.observe(bytes: 512, nanoseconds: 100)

        #expect(!changed)
        #expect(assessment.state == .bypassed)
        #expect(assessment.fastestObservedBytesPerSecond == 0.0, "it was not even recorded")
    }

    // MARK: No link speed at all

    /// A device whose link speed could not be read still gets the fallback check.
    @Test func anAbsentLinkSpeedFallsBackToTheFixedCeiling() {
        var assessment = CacheBypassAssessment(healthyConfiguration)
        #expect(assessment.derivedCeilingBytesPerSecond == nil)
        #expect(assessment.effectiveCeilingBytesPerSecond
                == CacheBypassCheck.fallbackImplausibleThroughputBytesPerSecond)

        let normalRead = assessment.observe(bytes: fourMiB, nanoseconds: 8_800_000)
        #expect(!normalRead)
        let ramSpeedRead = assessment.observe(bytes: fourMiB, nanoseconds: 58_000)
        #expect(ramSpeedRead)
    }

    /// An unrecognised code behaves exactly as an absent one — never guessed at.
    @Test func anUnrecognisedLinkSpeedFallsBackToo() {
        let assessment = CacheBypassAssessment(healthyConfiguration,
                                                linkSpeed: .unrecognised(code: 9))
        #expect(assessment.derivedCeilingBytesPerSecond == nil)
        #expect(assessment.effectiveCeilingBytesPerSecond
                == CacheBypassCheck.fallbackImplausibleThroughputBytesPerSecond)
    }
}
