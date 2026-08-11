//
//  RunReport.swift
//  USBDriveTester (app target — unprivileged)
//
//  Step 10 (AI-7), BUILD-PLAN 10.2/10.3/10.5. What a run produced, assembled from measured
//  values and nothing else. `RunReportMarkdown` renders it; this file decides what a report
//  *is*.
//
//  Pure Foundation, no view, no XPC, no clock of its own — so every claim it makes is testable
//  without a drive, which matters because these claims outlive the session that produced them.
//
//  ## The one rule that shapes this whole file
//
//  **The exported report outlives the enumeration that produced it.** A BSD name is assigned at
//  enumeration and names a different drive after a replug or a reboot — this project watched a
//  single reboot renumber every drive on the machine and turn a documented gate command into one
//  that would have written a gibibyte to a live Time Machine disk. So the drive a report is
//  *about* is identified by its **USB serial number**. The BSD name may appear, labelled as the
//  locator it was at run time, and never as the answer to "which drive was tested?"
//  (user decision 2026-08-06; FR document's entry of that date.)
//
//  ## What this report is not allowed to say
//
//  - **No health verdict.** "Completed clean" means *no currently-unreadable blocks were found*,
//    which is not the same as a healthy drive: degrading-but-still-correctable blocks are
//    invisible at the USB block level, and the drive's own DRAM/SLC cache sits below every host
//    mechanism, so a verify proves the data round-tripped through the device's I/O path and not
//    that the medium retained it (BUILD-PLAN 10.5, FR-WARN-3, NFR-USE-6).
//  - **No grade on throughput.** The rate is reported for the reader to judge against the
//    manufacturer's advertised sustained figure; this tool measures and does not diagnose
//    (user decision 2026-08-04).
//  - **No p99 as a point.** The histogram knows the answer to within one bucket, so it travels
//    and prints as an **upper bound**. "p99 = x" would dress a bracketing interval as a
//    measurement.
//  - **No device contents, in any form** (NFR-SEC-6). Block addressing only.
//

import Foundation

// MARK: - Which drive, and how sure can anyone be

/// The drive a report is about.
///
/// Identity is ``usbSerialNumber``. Everything else is context.
nonisolated struct ReportedDevice: Equatable {

    /// Vendor and product as the enumerator reported them, e.g. "Samsung Portable SSD T5".
    let modelDescription: String

    /// **The identity.** `nil` when the drive reported no usable serial — which is a real case,
    /// not a lookup failure: some USB bridges answer with a placeholder such as sixteen zeros,
    /// and this app rejects those rather than letting every drive behind one bridge model share
    /// an identifier. See ``identificationCaveat``.
    let usbSerialNumber: String?

    /// What the drive was called at run time — `disk8`, and so on. **A locator, never the
    /// identity.** Carried so a reader can tie the report to a `diskutil` transcript or a log
    /// line from the same session, and labelled as such wherever it is shown.
    let bsdNameAtRunTime: String?

    let capacityBytes: UInt64
    let logicalBlockSize: UInt32

    /// What a reader must be told when the drive could not identify itself.
    ///
    /// `nil` when there is a serial. Otherwise the report has to say plainly that it cannot be
    /// told apart from a report about an identical drive — because the model name, the capacity
    /// and the block size are all shared by every unit of the same product, and the BSD name is
    /// not an identity. Required by the 2026-08-06 decision, and it is the honest form of a
    /// limit rather than a warning about a defect.
    var identificationCaveat: String? {
        guard usbSerialNumber == nil else { return nil }
        return "This drive reported no usable USB serial number, so it cannot be identified "
             + "here. These results cannot be told apart from results for a different drive of "
             + "the same model and capacity."
    }

    /// How the drive is named in a heading. Model plus serial; model alone when there is none.
    var identification: String {
        guard let usbSerialNumber else { return modelDescription }
        return "\(modelDescription) (serial \(usbSerialNumber))"
    }

    /// Take the identity from the enumeration, at the moment a device is claimed.
    ///
    /// **At claim time, not at report time**, and that is the point of capturing it here: the
    /// enumeration that produced this record can be gone by the time a report is written — the
    /// drive may have been unplugged, or the list rebuilt — and the report is *about* the drive
    /// the run touched, not about whatever is present afterwards.
    init(_ device: DiscoveredDevice) {
        self.modelDescription = device.modelDescription
        self.usbSerialNumber = device.usbSerialNumber
        self.bsdNameAtRunTime = device.bsdName.rawValue
        self.capacityBytes = device.sizeBytes
        self.logicalBlockSize = device.logicalBlockSize
    }

    /// Memberwise, for tests and for the probe.
    init(modelDescription: String,
         usbSerialNumber: String?,
         bsdNameAtRunTime: String?,
         capacityBytes: UInt64,
         logicalBlockSize: UInt32) {
        self.modelDescription = modelDescription
        self.usbSerialNumber = usbSerialNumber
        self.bsdNameAtRunTime = bsdNameAtRunTime
        self.capacityBytes = capacityBytes
        self.logicalBlockSize = logicalBlockSize
    }
}

// MARK: - How the run ended (FR-RPT-4)

/// The run's outcome.
///
/// ## Why there are four cases and not the five BUILD-PLAN lists
///
/// "Stopped by user" needs FR-CTRL-4's stop control, which is **Step 11's**; "terminated by
/// device loss" needs FR-DEV-8's detection, which is **Step 12's**. Neither is here, by decision
/// (2026-08-06): a mechanism behind a trigger that never fires looks exactly like a broken
/// mechanism, so nothing untriggerable ships. Both steps add their case when they add its cause.
///
/// ``incomplete`` is a different kind of thing and is **not** an untriggerable mechanism. It is
/// how this report refuses to lie about a reply it cannot rule out: the helper is a separately
/// installed artefact, and a run that did not cover its range while recording no failure is not
/// something the app can classify as either "completed" or "stopped on error". Naming it costs
/// one case and keeps a wrong claim out of a persisted file.
// `CaseIterable` so a test can assert a property over EVERY outcome rather than over the four
// somebody remembered to list — added 2026-08-11 for `RunReportPresentationTests`, which checks
// that no two results are told apart by their tint alone (NFR-USE-8). A hand-written list is how a
// fifth outcome would arrive uncovered.
nonisolated enum RunReportOutcome: Equatable, CaseIterable {

    /// Every planned chunk was processed and nothing failed.
    ///
    /// **Not "healthy".** See ``headline``.
    case completedClean

    /// Every planned chunk was processed, and some failed (FR-FAIL-3).
    case completedWithFailures

    /// Halted at the first failure, in stop-on-first-error mode (FR-FAIL-2). Everything past the
    /// offending range is untested — not passed.
    case stoppedOnError

    /// The run ended before covering its range, and recorded no failure that would explain it.
    case incomplete

    /// Did the run cover everything it set out to?
    var didCoverTheRequestedRange: Bool {
        self == .completedClean || self == .completedWithFailures
    }

    /// Whether anything failed. Distinct from ``didCoverTheRequestedRange``: a run can complete
    /// with failures, and a run can stop with them.
    var foundFailures: Bool {
        self == .completedWithFailures || self == .stoppedOnError
    }

    /// The one-line result, worded so a clean pass cannot be read as a health certificate
    /// (BUILD-PLAN 10.5, FR-WARN-3, NFR-USE-6).
    ///
    /// The wording is deliberate on both sides. "No currently-unreadable blocks were found" says
    /// what was observed and when; "the drive is healthy" would be a claim about the future,
    /// about wear this tool cannot see, and about a medium it cannot reach past the drive's own
    /// cache. And *"were found"* rather than *"exist"*, because a whole-device pass at one moment
    /// is evidence about that moment.
    var headline: String {
        switch self {
        case .completedClean:
            return "Completed — no currently-unreadable blocks were found"
        case .completedWithFailures:
            return "Completed with failures — some blocks could not be read, written, or verified"
        case .stoppedOnError:
            return "Stopped on the first error — the rest of the requested range was not tested"
        case .incomplete:
            return "Incomplete — the run ended before covering the requested range"
        }
    }

    /// What the reader should take from it, in the report's own voice.
    var explanation: String {
        switch self {
        case .completedClean:
            return "Every block in the range below was read, written back unchanged, and read "
                 + "again, and every comparison matched. That is a statement about this range at "
                 + "this moment. It is **not** a clean bill of health: blocks that are degrading "
                 + "but still correctable by the drive's own error correction are invisible at "
                 + "the USB block level, and this test cannot see them."
        case .completedWithFailures:
            return "The whole range was processed. The blocks listed below failed; everything "
                 + "else read, wrote and verified correctly."
        case .stoppedOnError:
            return "The run was started in **stop on first error** mode, so it halted at the "
                 + "first failure and issued no further work. **The range beyond that point was "
                 + "not tested** — it has not passed, it was not reached. Re-run in *log and "
                 + "continue* mode to cover the whole range."
        case .incomplete:
            return "The run did not cover the requested range, and no failure was recorded that "
                 + "would account for it. The part that was not reached has not been tested."
        }
    }
}

// MARK: - The report

/// Everything a finished run is reported as (FR-RPT-1/2/3/4).
///
/// Assembled from what the helper measured — nothing here is re-derived from anything else, which
/// is why the figures are optionals rather than defaulted numbers: a rate this run did not
/// measure is absent, not zero.
nonisolated struct RunReport: Equatable {

    // MARK: What was tested

    let device: ReportedDevice

    /// First block of the range this run covered.
    let startBlock: UInt64

    /// How many blocks the run was asked to cover.
    let blockCount: UInt64

    /// Chunks the run got through, including any that failed.
    let chunksProcessed: UInt64

    // MARK: How it was configured

    /// The I/O sizes the run used, in the order they were used, **without deduplication**.
    ///
    /// A list rather than a single value because FR-CTRL-8 permits the size to change while a run
    /// is paused, and the read-latency statistics deliberately keep accumulating across such a
    /// change — which makes the distribution bimodal. A report showing one latency figure over
    /// two populations, without saying so, invites the reader to compare it with a
    /// single-size run. Today a run is one call and this holds one element; Step 11 is where it
    /// holds more, and the renderer already says so when it does.
    let ioSizesUsed: [Int]

    /// FR-FAIL-1's mode, **as the helper reported having run in** — not as the app asked for it.
    /// The distinction is the point: it is the only evidence available on a healthy drive that
    /// the mode reached the run at all.
    let failureMode: FailureModeCode

    // MARK: When

    let startedAt: Date
    let finishedAt: Date

    var duration: TimeInterval { max(0, finishedAt.timeIntervalSince(startedAt)) }

    // MARK: What happened

    let outcome: RunReportOutcome

    /// The failed ranges the helper retained (FR-RPT-1).
    ///
    /// `nil` means **the list could not be read**, which is not the same as an empty list. A
    /// report that printed "no bad blocks" because it failed to decode the list would be the
    /// worst available way to be wrong. ``failureListIsUnavailable`` is what the renderer keys on.
    let failedRanges: [FailedBlockRange]?

    /// Ranges the helper coalesced, retained **plus** any its cap dropped.
    let totalFailedRangeCount: Int

    /// Every failing block, including blocks in ranges the cap dropped. Never approximate.
    let failedBlockCount: UInt64

    // MARK: What was measured (FR-RPT-2/3)

    let readBytesPerSecond: Double?
    let writeBytesPerSecond: Double?
    let readLatencySampleCount: UInt64
    let readLatencyMinimum: Duration?
    let readLatencyMaximum: Duration?

    /// FR-RPT-3's p99, as the **upper bound** it is.
    let readLatencyP99UpperBound: Duration?

    /// The negotiated USB link speed, so a reader can judge the throughput above against
    /// something. `nil` when the registry reported none. Reported, never graded.
    let usbLinkSpeedDescription: String?

    // MARK: FR-TEST-9

    /// The cache-bypass verdict at the end of the run. **Printed in every report, in every
    /// state** — see ``cacheBypassStatement``.
    let cacheBypass: CacheBypassOutcome

    // MARK: - Derived

    /// Could the failure list not be read at all?
    var failureListIsUnavailable: Bool { failedRanges == nil }

    /// How many retained ranges the helper's cap dropped, or `nil` when the list is unavailable.
    ///
    /// **Must be shown wherever the list is.** A truncated list that does not say it is truncated
    /// reads exactly like a complete one.
    var droppedRangeCount: Int? {
        failedRanges.map { max(0, totalFailedRangeCount - $0.count) }
    }

    var listIsTruncated: Bool { (droppedRangeCount ?? 0) > 0 }

    /// Bytes the run's range covers, counted once — not the three times the cycle moves them.
    var rangeByteCount: UInt64 { blockCount * UInt64(device.logicalBlockSize) }

    /// Did the run use more than one I/O size? If so the latency distribution spans them.
    var latencySpansMultipleIOSizes: Bool { Set(ioSizesUsed).count > 1 }

    /// **FR-TEST-9's line, and it is present in every report whatever the verdict.**
    ///
    /// Mandatory rather than conditional on having failed, because a line that appears only on
    /// failure is indistinguishable from a missing one — and this file outlives the session, the
    /// UI banner, and any memory of which runs were qualified. A report saying "0 bad blocks"
    /// that has outlived its qualification reproduces the exact silent failure FR-TEST-9 exists
    /// to prevent.
    var cacheBypassStatement: String {
        switch cacheBypass {
        case .bypassed:
            return "**Cache bypass verified.** Reads were issued to the raw character device "
                 + "with caching disabled, so the verify step compared data that came back from "
                 + "the drive. The fault-detection result below means what it says."
        case .likelyCached:
            return "**Cache bypass NOT verified — the fault-detection result below may be "
                 + "unreliable.** Something could answer a read without the drive, so a "
                 + "comparison that matched may have compared a buffer against a cached copy of "
                 + "itself. The read and write-back still reached the drive, so the charge "
                 + "refresh this run performed remains valid; what cannot be relied on is the "
                 + "comparison that looks for faults."
        case .inconclusive:
            return "**Cache bypass could not be confirmed — the fault-detection result below "
                 + "may be unreliable.** The refresh this run performed remains valid; the fault "
                 + "comparison is the part in doubt."
        case .unrecognised:
            return "**Cache bypass verdict not recognised — treat the fault-detection result "
                 + "below as unverified.** The privileged helper reported a verdict this build "
                 + "does not know, which usually means it is a newer version. An unrecognised "
                 + "verdict is never read as success."
        }
    }

    /// Does the verdict qualify the fault-detection result? `.bypassed` alone does not.
    var verifyResultIsQualified: Bool { cacheBypass.qualifiesVerifyResult }

    /// The bold line at the top of the report — the outcome, **carrying its qualification**.
    ///
    /// ## Why the qualification is in the headline and not only in the paragraph below it
    ///
    /// Found by rendering, 2026-08-06. With the qualification a paragraph lower, a qualified
    /// clean run read:
    ///
    /// > **Completed — no currently-unreadable blocks were found**
    ///
    /// …in bold, followed by prose saying that finding may be worthless. Every word of it was
    /// true and the document was correctly ordered. But a reader skimming a report for its
    /// verdict takes the bold line, and FR-TEST-9 does not ask for the qualification to be
    /// *present* — it asks for it to be impossible to read past. A qualification one paragraph
    /// below the conclusion it undermines is a footnote to a conclusion already drawn.
    ///
    /// So the headline carries it. This costs a clause on the four reports in a hundred that are
    /// qualified, and it removes the one way this document could mislead at a glance.
    ///
    /// It applies to **every** outcome, not only the clean one. A cached read cannot invent a
    /// mismatch, but it can hide one — so "2 ranges failed" under an unverified bypass is a
    /// floor, not a count.
    var headline: String {
        guard verifyResultIsQualified else { return outcome.headline }
        switch outcome {
        case .completedClean:
            return outcome.headline + " — but this result is NOT VERIFIED (see below)"
        case .completedWithFailures, .stoppedOnError, .incomplete:
            return outcome.headline
                 + " — and fault detection was NOT VERIFIED, so there may be more (see below)"
        }
    }

    /// A file name for the export, keyed on **identity and time** (FR-RPT-5).
    ///
    /// The serial and not the BSD name, for this file's governing rule: the name outlives the
    /// enumeration, and a folder of reports called `disk4-…` would be a folder of files that no
    /// longer say which drive each is about. `unidentified-drive` when there is no serial —
    /// visibly not an identifier, rather than a plausible-looking one.
    ///
    /// - Parameter timeZone: injected so the name is reproducible in a test.
    func suggestedFileName(timeZone: TimeZone = .current) -> String {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd-HHmm"
        stamp.timeZone = timeZone
        stamp.locale = Locale(identifier: "en_US_POSIX")

        let identity = device.usbSerialNumber.map(RunReport.fileNameSafe) ?? "unidentified-drive"
        return "usb-drive-test-\(identity)-\(stamp.string(from: startedAt)).md"
    }

    /// Reduce a serial to characters that are safe in a file name on any platform the file may
    /// be copied to. A serial is normally alphanumeric; this exists so an unusual one cannot
    /// produce a path separator.
    private static func fileNameSafe(_ text: String) -> String {
        let cleaned = text.map { character -> Character in
            character.isASCII && (character.isLetter || character.isNumber) ? character : "-"
        }
        let result = String(cleaned)
        return result.isEmpty ? "unidentified-drive" : result
    }
}

// MARK: - Building one from a finished run

extension RunReport {

    /// Assemble a report from what the helper replied, or `nil` if **no run happened**.
    ///
    /// ## Why a refused call has no report
    ///
    /// FR-FAIL-5 requires every *run* to conclude with a report. A request the helper refused —
    /// a bad I/O size, a misplaced range, no device held, an unrecognised failure mode — is not a
    /// run: nothing was read, nothing was written, and there is nothing to report about the
    /// drive. Producing a report for one would put a file on disk describing a test that never
    /// touched the hardware.
    ///
    /// The discriminator is ``RunCycleOutcome/failureModeUsed``, not the chunk count. That field
    /// exists precisely because it is the helper stating what it did rather than the app
    /// inferring it, and `unrecognised` is what a refusal replies. The chunk count would give the
    /// same answer today and would be an inference about an implementation detail.
    ///
    /// - Parameters:
    ///   - reply: the helper's `runRetentionCycle` reply, decoded.
    ///   - startBlock: the range the run was asked for. Held by the app, which issued the call.
    ///   - blockCount: likewise.
    ///   - ioSizesUsed: the sizes the run used, in order.
    ///   - device: identity, from the app's own enumeration at the time of the run.
    ///   - startedAt / finishedAt: taken by the app around the call.
    ///   - usbLinkSpeedDescription: from `deviceProfile`, for context only.
    init?(reply: RunCycleOutcome,
          startBlock: UInt64,
          blockCount: UInt64,
          ioSizesUsed: [Int],
          device: ReportedDevice,
          startedAt: Date,
          finishedAt: Date,
          usbLinkSpeedDescription: String? = nil) {

        guard reply.failureModeUsed.isRunnable else { return nil }

        let foundFailures = reply.failedBlockCount > 0 || reply.totalFailedRangeCountIsNonZero
        let outcome: RunReportOutcome
        if reply.didComplete {
            outcome = foundFailures ? .completedWithFailures : .completedClean
        } else if foundFailures {
            outcome = .stoppedOnError
        } else {
            outcome = .incomplete
        }

        self.device = device
        self.startBlock = startBlock
        self.blockCount = blockCount
        self.chunksProcessed = reply.chunksProcessed
        self.ioSizesUsed = ioSizesUsed
        self.failureMode = reply.failureModeUsed
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.outcome = outcome
        self.failedRanges = reply.failedRanges
        self.totalFailedRangeCount = reply.failedRangeCount
        self.failedBlockCount = reply.failedBlockCount
        self.readBytesPerSecond = reply.readBytesPerSecond
        self.writeBytesPerSecond = reply.writeBytesPerSecond
        self.readLatencySampleCount = reply.readLatencySampleCount
        self.readLatencyMinimum = reply.readLatencyMinimum
        self.readLatencyMaximum = reply.readLatencyMaximum
        self.readLatencyP99UpperBound = reply.readLatencyP99UpperBound
        self.usbLinkSpeedDescription = usbLinkSpeedDescription
        self.cacheBypass = reply.cacheBypass
    }
}

private extension RunCycleOutcome {
    /// Failures may be known from the block count, from the range count, or from a range list
    /// that arrived — any one of them is enough to say the run found something. Three sources
    /// because a report must not read as clean on the strength of one field the helper happened
    /// to send as zero.
    var totalFailedRangeCountIsNonZero: Bool {
        failedRangeCount > 0 || (failedRanges?.isEmpty == false)
    }
}
