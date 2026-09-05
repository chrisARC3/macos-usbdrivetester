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
/// ## Why there are five cases and not BUILD-PLAN's five, nor Step 10's four
///
/// Step 10 shipped four. "Stopped by user" needed FR-CTRL-4's stop control and "terminated by
/// device loss" needs FR-DEV-8's detection, so neither was built in advance (decision 2026-08-06):
/// a mechanism behind a trigger that never fires looks exactly like a broken mechanism. **Step 11
/// increment 8 is where the stop control finally gives the fourth its trigger**, so ``stoppedByUser``
/// arrives here with its cause. Step 12's remains outstanding and is deliberately still absent.
///
/// ``incomplete`` is a different kind of thing and is **not** an untriggerable mechanism. It is
/// how this report refuses to lie about a reply it cannot rule out: the helper is a separately
/// installed artefact, and a run that did not cover its range while recording no failure is not
/// something the app can classify as either "completed" or "stopped on error". Naming it costs
/// one case and keeps a wrong claim out of a persisted file.
// `CaseIterable` so a test can assert a property over EVERY outcome rather than over the four
// somebody remembered to list — added 2026-08-11 for `RunReportPresentationTests`, which checks
// that no two results are told apart by their tint alone (NFR-USE-8). A hand-written list is how a
// fifth outcome would arrive uncovered. It did arrive, in increment 8, and the design paid for
// itself: `stoppedByUser` was picked up by that test without being named in it.
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

    /// **FR-RPT-4, and FR-CTRL-4's outcome.** The user ended the run — by pressing Stop, or by
    /// choosing to quit, which cancels it (decision 2026-08-20). Everything past the point it
    /// reached is untested, and an interrupted run cannot be continued (FR-FAIL-7).
    ///
    /// One case for both routes on purpose. The report's job is to say what happened to the drive,
    /// and "the user ended it" is the same fact whichever control they used; splitting it would put
    /// a distinction in a persisted file that answers no question anybody asks of one.
    case stoppedByUser

    /// The run ended before covering its range, and recorded no failure that would explain it.
    case incomplete

    /// Did the run cover everything it set out to?
    var didCoverTheRequestedRange: Bool {
        self == .completedClean || self == .completedWithFailures
    }

    /// Whether **this outcome, on its own, means failures were found.**
    ///
    /// Distinct from ``didCoverTheRequestedRange``: a run can complete with failures, and a run can
    /// stop with them.
    ///
    /// - Important: it is `false` for ``stoppedByUser``, and that is a statement about the *outcome*
    ///   rather than about the run. A user can stop a run that has already logged bad blocks, so
    ///   this case implies nothing either way — which is why the wording above changed in increment
    ///   8 from "whether anything failed". **``RunReport/failedRanges`` and
    ///   ``RunReport/failedBlockCount`` are the authority on what a stopped run found**, and the
    ///   report renders them for every outcome. Reading this property as "the run was clean" is the
    ///   error it is now worded to prevent.
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
        case .stoppedByUser:
            return "Stopped by the user — the rest of the drive was not tested"
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
        case .stoppedByUser:
            return "The run was stopped before it covered the whole drive. What it did reach was "
                 + "read, written back unchanged, and read again. **The rest was not tested** — it "
                 + "has not passed, it was not reached. An interrupted run cannot be continued, so "
                 + "testing the rest means a new run from the beginning. Any blocks that did fail "
                 + "before it stopped are listed below."
        case .incomplete:
            return "The run did not cover the requested range, and no failure was recorded that "
                 + "would account for it. The part that was not reached has not been tested."
        }
    }

    /// **How the run ended, decided from the RUN and not from its last reply** (FR-RPT-4).
    ///
    /// ## Why this exists, and what it fixes rather than adds
    ///
    /// Until increment 8 the outcome was inferred inside ``RunReport/init(reply:startBlock:blockCount:ioSizesUsed:device:startedAt:finishedAt:usbLinkSpeedDescription:)``
    /// from the last **reply** alone. A run is a *sequence* of bounded calls (CONSTRAINTS section 2,
    /// Shape A), so how the run ended is not a fact any single reply holds, and inferring it from
    /// one was wrong in three distinct ways — one of them badly:
    ///
    ///   * Stop from `running` left a reply saying `stoppedByUser`, which read as ``incomplete``:
    ///     *"the run ended before covering the requested range, and no failure was recorded that
    ///     would account for it"* — an anomaly, for something the user did on purpose.
    ///   * Stop from `paused` left a reply saying `pausedByUser`, and read the same way.
    ///   * **A stop that raced a completing call left a reply saying `completed`** — the helper
    ///     finished that call normally and `RunSequencer` declined to issue the next one — so the
    ///     report read *"Completed — no currently-unreadable blocks were found"* against a
    ///     ``RunReport/blockCount`` of the **whole device**, for a run that may have covered 2% of
    ///     it. A false clean pass, in a file that outlives the session. That is the one this
    ///     function exists for.
    ///
    /// ## Why it takes the sequencer's own vocabulary
    ///
    /// ``RunSequenceOutcome`` rather than some intermediate of this layer's own, so the `switch`
    /// below is **exhaustive over the thing that actually decides**. When Step 12 adds device loss
    /// to that enum, this is a compile error at the one place that has to say what the report
    /// reads — the same mechanism `RunSequencer.callReturned` uses on the wire vocabulary, and the
    /// reason neither can fall through to a silent wrong answer.
    ///
    /// - Parameters:
    ///   - ending: how the **run** ended, from `RunSequenceResult.outcome`.
    ///   - replyDidComplete: whether the last reply says its own call covered its range. Consulted
    ///     only where `ending` is ``RunSequenceOutcome/completed``, and only as a cross-check.
    ///   - foundFailures: whether the run recorded any failed range. The reply is cumulative over
    ///     the whole run (protocol v11), so this is the run's answer and not one call's.
    static func forRun(endedBy ending: RunSequenceOutcome,
                       replyDidComplete: Bool,
                       foundFailures: Bool) -> RunReportOutcome {
        switch ending {
        case .completed:
            // `RunSequencer` says this only once `RunSlicing` reports the device covered, which it
            // reaches by advancing on replies that completed — so the two agreeing is the ordinary
            // case and a disagreement is a wiring defect. ``incomplete`` is the safe answer to a
            // contradiction because it is the one that claims least; a report must not read as a
            // clean pass on the strength of a fact two sources disagree about.
            guard replyDidComplete else { return .incomplete }
            return foundFailures ? .completedWithFailures : .completedClean

        case .stoppedOnFailure:
            // FR-FAIL-2 at run scope: the mode stopped the *run*, not just the call.
            //
            // **The guard is not redundant, and removing it would delete a refusal to guess.** The
            // helper is a separately installed artefact; a reply saying "I stopped because of a
            // failure" while reporting no failed range is a contradiction the app cannot resolve,
            // and ``incomplete`` exists precisely to name it rather than pick a side. That is what
            // the reply-only inference did before increment 8, and it is preserved here on
            // purpose — `aRunThatEndedEarlyWithNoFailureIsCalledIncompleteRatherThanGuessedAt` is
            // the test that would have caught its loss.
            guard foundFailures else { return .incomplete }
            return .stoppedOnError

        case .stoppedByUser, .haltedForQuit:
            // Both are the user ending the run — Stop, or choosing to quit, which the confirmation
            // says outright cancels it (decision 2026-08-20). One outcome, because the report's
            // job is what happened to the drive and that is the same fact either way.
            return .stoppedByUser

        case .deviceLost:
            // **INTERIM, and chunk 5 is what replaces it** with a `RunReportOutcome` of its own.
            //
            // `incomplete` is the honest answer available at v15: the run did not cover the drive,
            // its own explanation already says the part not reached was not tested, and — the part
            // that matters — it makes **no claim about the drive's condition**. Every other
            // existing outcome would: `stoppedOnError` accuses the drive of the failure this whole
            // step exists to stop reporting, and `stoppedByUser` credits a person with something
            // they did not do.
            //
            // What it costs until chunk 5, stated so it is not left: the report says the run was
            // incomplete without saying the device was removed, and `HonestFraming` adds no
            // sentence of its own because `incomplete` already carries one.
            return .incomplete

        case .callFailed:
            // A call could not be made or was refused. Where no call ever returned there is no
            // report at all; where an earlier one did, this says what is true — the range was not
            // covered and nothing recorded explains it.
            return .incomplete
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
    /// A list rather than a single value because FR-CTRL-8 once permitted the size to change while
    /// a run was paused, with the read-latency statistics accumulating across the change — which
    /// made the distribution bimodal, and a report showing one latency figure over two populations
    /// without saying so invites comparison with a single-size run.
    ///
    /// **FR-CTRL-8 was revised again on 2026-08-14: a size change now ENDS the run.** So this
    /// permanently holds exactly one element and ``latencySpansMultipleIOSizes`` is permanently
    /// `false` — correctly, because the product can no longer produce a run that spans two sizes.
    /// Kept as a list rather than collapsed to an `Int`: the renderer's multi-size wording is the
    /// only thing that would have to come back if the requirement moves again, and a type that can
    /// still express the truth costs nothing.
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

    /// **The device's read speed** — original reads and verify reads together, over the time
    /// spent on both (v14).
    ///
    /// Divided by phase time, so a reader **cannot** reproduce it with a tool that watches the
    /// drive from outside, and it reads about 1.5× what one shows. That was treated as a defect
    /// from v12 to v13 and is the requirement from 2026-09-02: this tool reports what the device
    /// did while it was working. The exported document says so in as many words —
    /// `ThroughputFraming.definition` reaches this file's Markdown and the report sheet alike.
    let deviceReadBytesPerSecond: Double?

    /// **The device's write speed**: bytes written ÷ time spent writing (v14). About 3.4× what an
    /// outside observer sees, and above the read rate on a drive that writes faster than it reads.
    let writeBytesPerSecond: Double?

    /// How fast the run covered the drive, **against running time** — the one rate here that did
    /// not move to phase time in v14, because it is the ETA's denominator. About a third of the
    /// two above and not directly comparable to them.
    ///
    /// **Neither the report sheet nor the exported Markdown shows this, since Step 11 increment
    /// 10** — see `RunProgressSnapshot.coverageBytesPerSecond` for why the row went and why the
    /// field stayed. Kept on the report rather than dropped so that a `.md` file exported before
    /// the change and one exported after differ by a row rather than by what the type can carry.
    let coverageBytesPerSecond: Double?

    /// **`R-W-R-C speed`** (v14): bytes read, written back, read again and **matched**, per second
    /// of successful phase time — the successful-work counterpart of the attempted work above.
    ///
    /// Shown on both report surfaces and on the live panel. It equalled ``writeBytesPerSecond``
    /// on a clean run until v14; it is now roughly a third of it, and what a reader should check
    /// instead is `1/completed = 2/deviceRead + 1/write`. Below that prediction means bytes were
    /// written and never confirmed good, and the failed-range table above says which.
    let completedBytesPerSecond: Double?

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
    ///
    /// **The range the run ASKED FOR**, which after FR-CTRL-4's Stop control is not the same as the
    /// range it reached. That distinction is why the report's row is labelled *"Range requested"*
    /// from increment 8; it read *"Range tested"* before, and for a stopped run that was a false
    /// claim sitting three inches under a headline saying the rest was not tested.
    var rangeByteCount: UInt64 { blockCount * UInt64(device.logicalBlockSize) }

    /// Whether the run asked for the whole device (FR-TEST-4) rather than a bounded diagnostic
    /// range.
    ///
    /// Named here because both renderers were computing it inline, in two different spellings of
    /// the same arithmetic. One name, one comparison.
    var requestedRangeIsWholeDrive: Bool { rangeByteCount >= device.capacityBytes }

    /// What has to be said about this run's coverage, from the one place that decides it.
    ///
    /// Empty for a whole-device run that finished — which is the only case with nothing to qualify.
    var rangeCaveats: [HonestFramingClaim] {
        HonestFraming.rangeCaveats(rangeIsWholeDrive: requestedRangeIsWholeDrive,
                                   coveredTheRange: outcome.didCoverTheRequestedRange)
    }

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
        case .completedWithFailures, .stoppedOnError, .stoppedByUser, .incomplete:
            // "There may be more" is true even where the count shown is zero — an unverified read
            // cannot invent a mismatch but it can hide one, so every non-clean outcome takes the
            // same clause. `stoppedByUser` joined them in increment 8, and this `switch` being
            // exhaustive is what required an answer rather than letting it fall through.
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
    /// ## The outcome comes from the RUN, and `endedBy` has no default
    ///
    /// It is the run's own ending that decides ``RunReport/outcome`` — see
    /// ``RunReportOutcome/forRun(endedBy:replyDidComplete:foundFailures:)`` for the three ways the
    /// old reply-only inference was wrong, and for the one that produced a **false clean pass** over
    /// a partly-covered device.
    ///
    /// **Required, with no default**, at the cost of editing every call site — the same judgement
    /// increment 2 made about the engine's `control:` closure, for the same reason. A default would
    /// mean a caller that forgot it still compiled, still produced a report, and still put a
    /// plausible sentence in an exported file; the failure would be invisible until somebody
    /// stopped a run and read what it said afterwards. There is no value it could safely default
    /// to, because the safe answer differs per caller.
    ///
    /// - Parameters:
    ///   - reply: the helper's `runRetentionCycle` reply, decoded. Cumulative over the run
    ///     (protocol v11), so its figures are the run's and not the last call's.
    ///   - endedBy: how the **run** ended, from `RunSequenceResult.outcome`. Not derivable from
    ///     `reply`, which knows only how one call ended.
    ///   - startBlock: the range the run was asked for. Held by the app, which issued the call.
    ///   - blockCount: likewise.
    ///   - ioSizesUsed: the sizes the run used, in order.
    ///   - device: identity, from the app's own enumeration at the time of the run.
    ///   - startedAt / finishedAt: taken by the app around the call.
    ///   - usbLinkSpeedDescription: from `deviceProfile`, for context only.
    init?(reply: RunCycleOutcome,
          endedBy ending: RunSequenceOutcome,
          startBlock: UInt64,
          blockCount: UInt64,
          ioSizesUsed: [Int],
          device: ReportedDevice,
          startedAt: Date,
          finishedAt: Date,
          usbLinkSpeedDescription: String? = nil) {

        guard reply.failureModeUsed.isRunnable else { return nil }

        let foundFailures = reply.failedBlockCount > 0 || reply.totalFailedRangeCountIsNonZero
        let outcome = RunReportOutcome.forRun(endedBy: ending,
                                              replyDidComplete: reply.didComplete,
                                              foundFailures: foundFailures)

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
        self.deviceReadBytesPerSecond = reply.deviceReadBytesPerSecond
        self.writeBytesPerSecond = reply.writeBytesPerSecond
        self.coverageBytesPerSecond = reply.coverageBytesPerSecond
        self.completedBytesPerSecond = reply.completedBytesPerSecond
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
