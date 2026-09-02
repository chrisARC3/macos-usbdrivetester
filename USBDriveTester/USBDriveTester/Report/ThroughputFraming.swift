//
//  ThroughputFraming.swift
//  USBDriveTester (app target — unprivileged)
//
//  What the throughput figures mean, and what they must not be read as. **One definition, two
//  surfaces**: the report window and the exported Markdown.
//
//  ## Why this file exists rather than two string literals
//
//  Because the two literals had already drifted, twice, in the same week.
//
//  `RunReportMarkdown` carries a note about exactly this: until 2026-08-10 it held its own
//  wording and the result screen held a second set, and the screen had lost the clause explaining
//  why a matching verify does not prove retention. `HonestFraming` was written to end that, and it
//  worked — for the claims it covers.
//
//  It did not cover throughput, and on 2026-08-18 the same defect happened again in one day. The
//  advertised-rate comparison was removed from the exported report and left on screen, so the
//  window told the reader to judge the figures against a manufacturer's sequential rating while
//  the exported file said they were not comparable to one. Then the new definition paragraph was
//  added to the export only, so the screen explained nothing at all. **Found by the human
//  checklist, not by the 962 tests** — nothing asserts that two surfaces agree.
//
//  The lesson is the one `HonestFraming` already learned: a sentence a user reads must exist in
//  exactly one place, and every surface must derive from it. `HonestFramingClaim` is reused rather
//  than copied, so `plain` is derived here too.
//

import Foundation

/// The throughput figures' meaning, stated once.
nonisolated enum ThroughputFraming {

    /// What both rates divide by — the thing that makes them checkable against anything else.
    ///
    /// Said "the three rates" until 2026-09-02, one day after increment 10 deleted `Covering` and
    /// rewrote the string below from "All three rates" to "Both rates". Found by a reader asking
    /// whether the "twice Write" clause was a solid-state claim. **It is not, and the ratio is not
    /// a hardware property at all**: both rates share this denominator, and the cycle reads every
    /// byte twice and writes it once, so a clean run gives 2 on any medium. Failures are what move
    /// it — a chunk failing its read contributes no `bytesRead`, one failing its write contributes
    /// a read and no write. See `TesterControl.version`'s v12 note.
    ///
    /// A rate whose denominator is unstated cannot be reproduced by the reader, and this app spent
    /// a week showing figures 1.5x and 3.4x what Activity Monitor showed for the same drive with
    /// nothing on either surface to reveal the mismatch.
    static let definition = HonestFramingClaim(
        "Both rates are measured over **the time the run spent working** — time paused, and "
        + "time between one call and the next, is excluded. While a run is going they are "
        + "therefore directly comparable to Activity Monitor or any other tool watching this "
        + "drive, and a pause does not make the drive look slower than it is. Read counts the "
        + "verify read as well as the original read, because both are reads: every byte is read, "
        + "written back and read again, so Read runs at about twice Write.")

    /// D9 (user decision 2026-08-04): this tool measures, and does not judge.
    ///
    /// It deliberately does **not** name the manufacturer's advertised figure as the comparison
    /// basis, which it did until 2026-08-18. These rates describe a mixed read-write-verify
    /// workload; an advertised rating is a pure sequential read or write. Inviting that comparison
    /// invites the exact bias the FR document warns about — "a systematic bias toward *this
    /// drive looks worn*, on a tool whose output is a judgement about somebody's hardware".
    ///
    /// **"May not be", not "is not" (user correction 2026-08-18).** The flat denial was an
    /// overclaim. At the I/O sizes this tool uses — 1 to 8 MiB — a solid-state drive will
    /// likely show no discernible difference between a read to write-back to read pattern and
    /// purely sequential access, because there is no seek to pay for. The difference that
    /// would justify an absolute is a spinning-disk argument. The honest statement is that the
    /// comparison may not hold, not that it cannot.
    ///
    /// A sentence spelling out the consequence — that reading these as a fraction of an
    /// advertised figure makes a healthy drive look worn — was removed on the same day
    /// (user correction). The sentence before it already says the comparison may not
    /// hold; drawing the inference for the reader is commentary, not information, and a
    /// report that argues its own point is longer without being clearer.
    static let notGraded = HonestFramingClaim(
        "Throughput is **reported, not graded**. These figures describe a mixed "
        + "read-write-verify workload, so they **may not be** comparable to a manufacturer's "
        + "sequential-read or sequential-write rating, which is measured doing one thing at a "
        + "time. It measures; it does not diagnose.")
}
