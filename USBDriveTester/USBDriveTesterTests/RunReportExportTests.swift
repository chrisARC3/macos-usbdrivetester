//
//  RunReportExportTests.swift
//  FR-RPT-5's export, the part of it that is not a save panel. Step 10, increment 5.
//
//  `NSSavePanel.runModal()` cannot be driven from a test, so `RunReportExport` is split: the
//  panel picks a URL, and `write(_:to:)` does everything after that. This suite covers the
//  second half — which is the half that can silently do nothing.
//
//  **An export that reports success and writes no file is the failure worth guarding against.**
//  Each run stands alone and no history is kept (FR-RPT), so the exported file is not one copy of
//  something recoverable; it is the only copy that will ever exist. A user who exports, sees no
//  error, and finds nothing has lost the run, not a convenience.
//

import Testing
import Foundation
// `MemberImportVisibility` is on: `UTType.conforms(to:)` and `.plainText` come from a
// transitively-imported module, and that is not enough — the module must be imported directly.
import UniformTypeIdentifiers
@testable import USBDriveTester

struct RunReportExportTests {

    private static func report(serial: String? = "12345686DAA9",
                               cacheBypassCode: Int = 1) -> RunReport {
        let reply = RunCycleOutcome(runOutcomeCode: RunOutcomeCode.completed.rawValue,
                                    interruptedAtBlock: 0,
                                    chunksProcessed: 256,
                                    failedRangeCount: 1,
                                    failureSummary: "",
                                    cacheBypassCode: cacheBypassCode,
                                    bufferBytesHeld: 8 << 20,
                                    hostOverheadFraction: 0.0255,
                                    helperCoreFraction: 0.0422,
                                    failureModeUsedCode: 2,
                                    failedRangesEncoded: "200:2:3",
                                    failedBlockCount: 2,
                                    deviceReadBytesPerSecond: 517_000_000,
                                    writeBytesPerSecond: 491_000_000,
                                    coverageBytesPerSecond: 245_000_000,
                                    completedBytesPerSecond: 238_000_000,
                                    readLatencySampleCount: 256,
                                    readLatencyMinimumNanoseconds: 1_100_000,
                                    readLatencyMaximumNanoseconds: 9_900_000,
                                    readLatencyP99UpperBoundNanoseconds: 2_195_000,
                                    message: "",
                                    deviceLossPhaseCode: DeviceLossPhaseCode.unrecognised.rawValue)
        return RunReport(reply: reply,
                         endedBy: .completed,
                         removalCallbackSaid: nil,
                         startBlock: 0,
                         blockCount: 2_097_152,
                         ioSizesUsed: [4 << 20],
                         device: ReportedDevice(modelDescription: "Samsung Portable SSD T5",
                                                usbSerialNumber: serial,
                                                bsdNameAtRunTime: "disk8",
                                                capacityBytes: 1_000_204_886_016,
                                                logicalBlockSize: 512),
                         startedAt: Date(timeIntervalSince1970: 1_785_000_000),
                         finishedAt: Date(timeIntervalSince1970: 1_785_000_007),
                         usbLinkSpeedDescription: "10 Gb/s (USB 3.1 Gen 2)")!
    }

    private static func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("usbdrivetester-export-test-\(UUID().uuidString).md")
    }

    /// The file exists, and it is **not empty**. Both halves: a zero-byte file at the right path
    /// is what a write that opened and failed leaves behind, and it satisfies "does the file
    /// exist?" perfectly.
    @Test func exportingWritesANonEmptyFile() throws {
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try RunReportExport.write(Self.report(), to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))

        let written = try String(contentsOf: url, encoding: .utf8)
        #expect(written.isEmpty == false)
        #expect(written.count > 1_500)
    }

    /// **The file is exactly what the renderer produces** — not a summary of it, not a
    /// re-derivation. The screen and the file read from one model and the file is written from
    /// one renderer, so there is nowhere for a third version of the truth to appear.
    @Test func theWrittenFileIsExactlyTheRenderedReport() throws {
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let report = Self.report()
        try RunReportExport.write(report, to: url)

        let written = try String(contentsOf: url, encoding: .utf8)
        #expect(written == RunReportMarkdown.render(report))
    }

    /// The claims that must survive the trip to disk. A report is read again months later with no
    /// memory of the session, so the qualification and the identity have to be *in the file*.
    @Test func theWrittenFileCarriesTheQualificationAndTheIdentity() throws {
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try RunReportExport.write(Self.report(cacheBypassCode: 2), to: url)
        let written = try String(contentsOf: url, encoding: .utf8)

        #expect(written.contains("NOT VERIFIED"), "the headline's qualification")
        #expect(written.contains("12345686DAA9"), "the drive's identity")
        #expect(written.contains("a locator, not an identity"), "the BSD name, labelled")
        #expect(written.contains("| 200 | 201 | 2 | verify mismatch |"), "the failed range")
    }

    /// UTF-8 explicitly, because the report contains an em-dash, an en-dash and a `≤` — and a
    /// file written in an encoding that mangles them is a file whose p99 no longer says it is a
    /// bound.
    @Test func theFileIsUtf8AndKeepsItsNonAsciiCharacters() throws {
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try RunReportExport.write(Self.report(), to: url)
        let data = try Data(contentsOf: url)
        let decoded = String(data: data, encoding: .utf8)

        #expect(decoded != nil, "the file is not valid UTF-8")
        #expect(decoded?.contains("≤") == true, "the p99's bound survived")
        #expect(decoded?.contains("–") == true, "the block range's en-dash survived")
    }

    /// A write that cannot happen must **throw**, not report success. This is the path that
    /// decides whether a user who saw no error actually has a file.
    ///
    /// It is also the test that found the design defect: `write` used to present an `NSAlert` on
    /// failure, and running this hung the test runner on a modal dialog. A function that writes a
    /// file and also puts a window on screen cannot be exercised where a window would be wrong —
    /// which is exactly the failure path. The alert moved to `presentSavePanel`, where the UI is.
    @Test func anImpossibleWriteThrowsRatherThanReportingSuccess() {
        let unwritable = URL(fileURLWithPath:
            "/System/usbdrivetester-this-directory-does-not-exist/report.md")
        #expect(throws: (any Error).self) {
            try RunReportExport.write(Self.report(), to: unwritable)
        }
        #expect(FileManager.default.fileExists(atPath: unwritable.path) == false)
    }

    /// Re-exporting over an existing file replaces it rather than appending — a report that
    /// accreted copies of itself would be unreadable and would grow without bound.
    @Test func exportingTwiceReplacesRatherThanAppends() throws {
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let report = Self.report()
        try RunReportExport.write(report, to: url)
        let once = try String(contentsOf: url, encoding: .utf8)
        try RunReportExport.write(report, to: url)
        let twice = try String(contentsOf: url, encoding: .utf8)

        #expect(once == twice)
    }

    /// The type offered in the save panel. `.md` if the system knows it, plain text otherwise —
    /// never nothing, which would leave the panel refusing every name.
    @Test func theExportTypeIsAMarkdownOrPlainTextFile() {
        let type = RunReportExport.markdownType
        #expect(type.conforms(to: .text) || type.conforms(to: .plainText))
    }

    /// The suggested name is what lands in the panel, and it is keyed on identity and time —
    /// never on the BSD name, which will name a different drive after a replug.
    @Test func theSuggestedNameIsUsableAsAFileName() {
        let name = Self.report().suggestedFileName(timeZone: TimeZone(identifier: "UTC")!)
        #expect(name.hasSuffix(".md"))
        #expect(name.contains("/") == false)
        #expect(name.contains(":") == false, "a colon is a path separator in some contexts")
        #expect(name.contains("12345686DAA9"))
        #expect(name.contains("disk8") == false)
    }

    /// A drive with no serial still produces a usable name, and one that is visibly not an
    /// identifier rather than a plausible-looking one.
    @Test func aDriveWithNoSerialStillProducesAWritableName() throws {
        let name = Self.report(serial: nil)
            .suggestedFileName(timeZone: TimeZone(identifier: "UTC")!)
        #expect(name.contains("unidentified-drive"))

        // And it really is writable — the point of a file name is that a file can have it.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defer { try? FileManager.default.removeItem(at: url) }
        try RunReportExport.write(Self.report(serial: nil), to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}
