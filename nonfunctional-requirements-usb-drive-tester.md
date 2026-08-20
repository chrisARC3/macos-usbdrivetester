# Non-Functional Requirements: USB Drive Retention & Hard-Fault Tester

**Status:** Baselined
**Date:** 2026-06-25
**Baselined:** 2026-06-25
**Last amended:** 2026-08-01 (NFR-INST-4 added — Full Disk Access)
**Source documents:** [USBDriveTester.md](USBDriveTester.md), [ADR-001-usb-drive-tester.md](ADR-001-usb-drive-tester.md)
**Companion document:** [Functional Requirements](functional-requirements-usb-drive-tester.md) (Baselined 2026-06-25)

## Purpose & Scope

This document specifies the **non-functional requirements** — the quality attributes and constraints the system must satisfy (how well it does what the functional spec defines). It deliberately does **not** restate behaviors; those live in the functional spec, which is referenced here by ID (e.g., `FR-ARCH-5`).

## Conventions

- Each requirement has a unique ID of the form `NFR-<AREA>-<n>`.
- "**shall**" denotes a mandatory requirement; "**should**" a recommended one.
- **Priority** uses MoSCoW: **M** (Must have for first release), **S** (Should have), **C** (Could have / later).
- **Source** cites the originating statement in the product brief (PB), the ADR, the functional spec (FR), or a noted decision.

## Quality Attribute Areas

| Area code | Description |
|-----------|-------------|
| PERF   | Performance & efficiency |
| REL    | Reliability & data integrity |
| SEC    | Security & privilege model |
| USE    | Usability & honest presentation |
| COMPAT | Platform & device compatibility |
| MAINT  | Maintainability & testability |
| OBS    | Observability & logging |
| INST   | Installation & distribution |

---

## NFR-PERF — Performance & Efficiency

| ID | Requirement | Priority | Source |
|----|-------------|----------|--------|
| NFR-PERF-1 | Peak buffer memory for a run shall be bounded to approximately 2× the selected I/O size (one original-read buffer + one verify-read buffer) and shall **not** scale with device capacity. | M | PB Test Algorithm; ADR Scalability |
| NFR-PERF-2 | The helper shall process the device as a bounded-memory stream of chunks so that arbitrarily large (multi-terabyte) devices can be tested without proportional memory growth. | M | ADR Option A Scalability |
| NFR-PERF-3 | Throughput shall be **device-bound, not host-bound**: the per-chunk compare, metrics, and bookkeeping overhead shall remain negligible relative to the wall-clock time of the underlying raw read → write → read I/O, such that overall run time is dominated by device I/O rather than host processing. | S | ADR Trade-off Analysis (serialized I/O) |
| NFR-PERF-4 | The GUI shall remain responsive (no UI thread blocking) throughout a run; all privileged I/O and heavy work shall run off the main thread / in the helper. | M | PB Project Objective (monitor progress); ADR Decision |
| NFR-PERF-5 | Live metrics (throughput, latency, progress, ETA) shall refresh at least once per second during an active run. | S | FR-METR-2/4/5 (presentation cadence) |
| NFR-PERF-6 | The displayed ETA shall be derived from measured throughput and shall update continuously, converging toward the actual remaining time as the run progresses. | S | ADR Trade-off Analysis (real ETA); FR-METR-5 |
| NFR-PERF-7 | Capturing per-chunk read-latency statistics (min/max/p99) shall be performed with constant memory (e.g., streaming/approximate percentile) and shall not materially reduce throughput. | S | FR-METR-3 |

## NFR-REL — Reliability & Data Integrity

| ID | Requirement | Priority | Source |
|----|-------------|----------|--------|
| NFR-REL-1 | Under uninterrupted operation, the tool shall be **logically non-destructive**: every successfully processed block shall contain, after the run, exactly the bytes it contained before the run (bit-for-bit). | M | PB Test Algorithm; FR-TEST-7; ADR Trade-off Analysis |
| NFR-REL-2 | The write-back for each chunk shall write exactly the bytes read from that chunk; correctness of the write shall be confirmed by the read-verify comparison before the chunk is considered complete. | M | PB Test Algorithm; FR-TEST-3 |
| NFR-REL-3 | The tool shall never issue block writes unless all of the device's volumes are unmounted **and** exclusive whole-disk access is held. | M | PB Managing Mounted Volumes; FR-SAFE-1/2/3 |
| NFR-REL-4 | The in-flight data-loss window shall be bounded to at most one chunk — the chunk currently being written — consistent with the no-journaling decision. | M | ADR Decision; FR-FAIL-7 |
| NFR-REL-5 | On stop, halting error, or device loss, the helper shall terminate cleanly, issue no further writes, and release the device node without leaving the helper in an inconsistent state. | M | FR-DEV-8; FR-FAIL-7 |
| NFR-REL-6 | A device-side error, device removal, or malformed condition shall not crash the GUI; the GUI shall surface the error and return to a usable state (re-running discovery where applicable). | M | FR-DEV-8 |
| NFR-REL-7 | The helper shall validate all parameters received from the GUI (device identity, offset, length, alignment) and reject any request that is out of range or misaligned before performing privileged I/O. | M | ADR Cons (client validation) |
| NFR-REL-8 | The verify comparison shall detect any single-bit difference between the written and re-read buffers. | M | PB Test Algorithm |
| NFR-REL-9 | While a run is actively executing, the app shall prevent idle system sleep (e.g., via an `NSProcessInfo` idle-system-sleep power assertion) so that long-running runs — which cannot be resumed (FR-FAIL-7) and may take many hours — are not interrupted by the Mac sleeping. The assertion shall be released when the run pauses, stops, completes, or fails. | M | ADR Trade-off Analysis (multi-hour runs); FR-FAIL-7; user decision 2026-06-25 |
| NFR-REL-10 | When the user pauses a run (FR-CTRL-2/3), the helper shall settle at a chunk boundary with no write in flight, leaving the device in a consistent state before the pause is acknowledged. | M | FR-CTRL-2/3; NFR-REL-4; user decision 2026-06-25 |

## NFR-SEC — Security & Privilege Model

| ID | Requirement | Priority | Source |
|----|-------------|----------|--------|
| NFR-SEC-1 | Elevated privileges shall be confined to the helper; the GUI shall run wholly unprivileged (principle of least privilege). | M | ADR Decision; FR-ARCH-2 |
| NFR-SEC-2 | The helper shall accept privileged commands only over the authenticated XPC connection and only after validating that the calling client's code signature was issued under the expected **Team ID**. (Bundle identifier and Apple anchor are not separately pinned; Team-ID match is the accepted bar.) | M | ADR Cons; FR-ARCH-4/5; user decision 2026-06-25 |
| NFR-SEC-3 | The helper shall expose the minimum XPC interface necessary to perform its function and shall reject unrecognized or malformed messages. | M | ADR Cons; NFR-REL-7 |
| NFR-SEC-4 | The application and helper shall be code-signed, notarized, and run under the macOS hardened runtime. | M | ADR Pros (notarizable) |
| NFR-SEC-5 | The helper shall be installed, updated, and removed solely via `SMAppService`; the design shall not rely on setuid binaries or deprecated privileged-helper mechanisms. | M | ADR Decision; Option C rejection |
| NFR-SEC-6 | The tool shall operate entirely locally; device contents shall never be transmitted off the host nor written to logs or reports. | M | Derived (privacy of user data) |
| NFR-SEC-7 | The application and helper shall request only the entitlements required for their function. | S | ADR Pros (least privilege) |

## NFR-USE — Usability & Honest Presentation

| ID | Requirement | Priority | Source |
|----|-------------|----------|--------|
| NFR-USE-1 | Throughput and latency shall be presented in an easily readable form, with clear units (e.g., MB/s, ms) and human-friendly formatting. | M | PB Features ("easily readable"); deferred from FR-METR (user decision 2026-06-25) |
| NFR-USE-2 | Progress shall be conveyed clearly during a run, including percent complete, current position, and the live ETA. | M | FR-METR-5/6 |
| NFR-USE-3 | The currently selected device shall be unambiguously identified (e.g., BSD name, model, capacity) so the user cannot accidentally test the wrong device. | M | PB Upon launch; FR-DEV-6 |
| NFR-USE-4 | Pre-run warnings (back up first; infrequent on NAND; clean pass ≠ healthy drive) shall be presented prominently before a run starts, and the user shall be required to act deliberately before any run begins. The user may suppress the **warning text** for subsequent runs; the **deliberate act may not be suppressed** — where the text is suppressed, a confirmation identifying the device by model and USB serial number shall stand in its place. Suppression shall be recorded per logged-in user and shall be reversible from within the application. | M | PB Features; FR-WARN-1/2/3; **qualified 2026-08-09** |
| NFR-USE-5 | Error messages shall be specific and actionable, naming the actual cause and the corrective step (e.g., which volume to unmount, or that the device node is claimed). | M | FR-SAFE-4; FR-DEV-8 |
| NFR-USE-6 | The honest-framing messaging shall be presented such that a clean pass cannot reasonably be mistaken for a health certificate. | M | PB What the Test Does and Does Not Prove; FR-WARN-3/4 |
| NFR-USE-7 | The exported Markdown report shall be well-structured and human-readable (headings, a clear pass/fail outcome, and tabulated bad-block ranges and statistics). | S | FR-RPT-5 |
| NFR-USE-8 | The GUI should follow macOS accessibility expectations on a best-effort basis — leveraging SwiftUI's built-in accessibility (Dynamic Type, sufficient color contrast) and, in particular, never conveying pass/fail status by color alone. A full accessibility audit is not a v1 release gate. **Screen-reader (VoiceOver) support is out of scope — removed 2026-08-11; see Amendments.** | S | Derived (macOS HIG); user decision 2026-06-25; **VoiceOver removed 2026-08-11** |
| NFR-USE-9 | The main window shall fit a 13.3-inch Apple Silicon Mac at **1280x800 with the Dock showing** — a 700 pt window — without clipping content and without requiring the user to resize it. Its minimum size shall be **derived by measuring the laid-out view hierarchy**, rather than asserted as a constant or taken from a declared minimum that a control may not honour. | S | user decisions 2026-08-19 and 2026-08-20; Step 11 increment 7; see Amendments |

## NFR-COMPAT — Platform & Device Compatibility

| ID | Requirement | Priority | Source |
|----|-------------|----------|--------|
| NFR-COMPAT-1 | The executables shall be Apple-Silicon-native (arm64). | M | PB Project Objective; ADR Context |
| NFR-COMPAT-2 | The application shall target macOS Tahoe (macOS 26) and later as its minimum supported OS. | M | PB Project Objective; ADR Context |
| NFR-COMPAT-3 | The application shall be built with Xcode and Swift, with the GUI implemented in SwiftUI. | M | PB Project Objective; ADR Decision |
| NFR-COMPAT-4 | The tool shall support USB mass-storage-class devices, covering both NAND-flash media and rotational HDDs (including SATA-to-USB bridged drives). | M | PB Goal; ADR Context |
| NFR-COMPAT-5 | The tool shall use the device-reported logical block size and shall correctly support at least 512-byte and 4096-byte logical blocks. | M | PB Test Algorithm; FR-DEV-5; FR-TEST-5 |
| NFR-COMPAT-6 | The tool shall support large-capacity devices (multi-terabyte) using 64-bit block offsets and counts, with no capacity-related limits short of the device's own. | M | ADR Scalability |
| NFR-COMPAT-7 | The tool should operate correctly across USB link speeds (e.g., USB 2.0 and USB 3.x), deriving timing and ETA from measured throughput rather than assumed speed. | S | ADR Trade-off Analysis (measured ETA) |

## NFR-MAINT — Maintainability & Testability

| ID | Requirement | Priority | Source |
|----|-------------|----------|--------|
| NFR-MAINT-1 | The GUI and helper shall be cleanly separated by a well-defined, versioned XPC protocol so each can evolve independently. | M | ADR Decision |
| NFR-MAINT-2 | Core test-algorithm logic (chunking, final-chunk sizing, verify, metrics, failure classification) should be unit-testable independently of privileged hardware access, via an abstraction over the raw device (e.g., a simulated/in-memory device). | S | Derived (testability of FR-TEST/FR-FAIL) |
| NFR-MAINT-3 | The project shall build reproducibly from the Xcode workspace, producing both the unprivileged app and the privileged helper targets. | M | ADR Action Item 1 |
| NFR-MAINT-4 | The codebase should follow idiomatic Swift conventions and be organized so the trust boundary (privileged vs. unprivileged code) is obvious in the source layout. | S | Derived (ADR trust boundary) |

## NFR-OBS — Observability & Logging

| ID | Requirement | Priority | Source |
|----|-------------|----------|--------|
| NFR-OBS-1 | The application and helper shall log significant events (run start/stop, failure-mode selection, failed block ranges, device connect/loss, helper registration) to the macOS unified logging system (`os_log`). | S | Derived (diagnosability) |
| NFR-OBS-2 | Logs shall be sufficient to diagnose an interrupted or failed run after the fact, while never recording device contents. | S | NFR-SEC-6; FR-FAIL-7 |

## NFR-INST — Installation & Distribution

| ID | Requirement | Priority | Source |
|----|-------------|----------|--------|
| NFR-INST-1 | The helper shall register via `SMAppService`, and the GUI shall report registration status clearly, including guiding the user when approval is required (e.g., Login Items in System Settings). | M | ADR Decision; Action Item 2 |
| NFR-INST-2 | The application shall be distributable as a notarized, hardened-runtime build that launches without Gatekeeper warnings on a clean supported system. | M | ADR Pros (distribution) |
| NFR-INST-3 | The tool shall provide a clean way to unregister/remove the privileged helper. | S | Derived (lifecycle of SMAppService daemon) |
| NFR-INST-4 | The application shall require **Full Disk Access** for its privileged helper in order to open a USB device's raw node, and shall **detect** whether that permission has been granted, report its absence before a run is attempted rather than as a run failure, and guide the user to System Settings › Privacy & Security › Full Disk Access. | M | **Measured 2026-08-01** — see Amendments |

---

## Amendments to the Baseline

Changes made after the 2026-06-25 baseline. Recorded here so the delta is auditable
rather than silently absorbed into the tables above.

### 2026-08-01 — NFR-INST-4 added (Full Disk Access)

**Trigger.** Measured on real hardware during Step 6, not anticipated by the ADR, the
build plan or either requirements set.

**What was found.** The privileged helper's
`open("/dev/rdiskN", O_RDWR | O_EXLOCK | O_NONBLOCK)` on an **unmounted, uncontended**
external drive failed with `EPERM`. `tccd` logged, at that instant:

```
Handling access request to kTCCServiceSystemPolicyAllFiles,
  from Sub:{com.arc3solutions.USBDriveTester}
  Resp:{…USBDriveTester.Helper, euid=0}
  ReqResult(Auth Right: Denied (Service Policy))
kTCCServiceSystemPolicyRemovableVolumes denied by TCC
```

**Running as root is not sufficient.** Raw access to a removable device is gated by TCC,
and a LaunchDaemon has no grant of its own. TCC attributes the request to the **app**
bundle, so the grant belongs to the containing application and travels with it.

**Why nothing caught it sooner.** Step 6 is the first step in which the helper opens a
device at all — Steps 1–5 never did. The exclusivity semantics measured on 2026-07-30 were
obtained with `sudo` from Terminal, which inherits **Terminal's** TCC grant; those
measurements remain valid for what they measured (exclusivity), but they never established
that a *daemon* could open the device, because a daemon was never the thing being tested.

**Why it is M, not S.** Without it the tool cannot perform its primary function at all: no
raw open means no read, no write-back and no verify. It is a hard prerequisite, not a
degradation.

**Why detection is part of the requirement, not just documentation.** The failure surfaces
as `EPERM` from a privileged process, whose natural reading is that the drive or the cable
is at fault — the user is sent to diagnose hardware when the fix is a checkbox. NFR-USE-5
already requires errors to name the actual cause; NFR-INST-4 additionally requires the
condition to be surfaced *before* a run is attempted, in the same spirit as NFR-INST-1's
guidance for helper approval.

**Consequences elsewhere.** Step 16's clean-machine test must include it — a fresh Mac
denies this by default, so a machine that has already been granted access would give a
false pass, exactly the hazard NFR-INST-2's clean-system clause exists to avoid.

---

### 2026-08-05 — NFR-PERF-3 measured (no wording change)

**Not an amendment to the requirement.** NFR-PERF-3's text is unchanged and remains qualitative —
"device-bound, not host-bound", with no fixed percentage (resolved 2026-06-25, Open Question 1).
Recorded here because *"NFR-PERF-3 has never had a number"* was true from the baseline until Step 9
and is written into several places in the build plan; anyone reading this document should know it
is no longer true, and what the numbers are.

Measured on the designated scratch device (Samsung T5, serial `12345686DAA9`) in the
**product's own run path** — not from an external CPU observation, and
not from the gate's SHA-256 fingerprint, which is what the 36–39% figure quoted during Step 8
actually was. Swept across all four I/O sizes of FR-CTRL-8 (`scripts/metrics-check.sh`, 0
failures). At the 4 MiB default with the device moving ~470 MB/s:

| | |
|---|---|
| per-chunk compare + metrics + bookkeeping, ÷ device I/O wall-clock | **2.55%** → the run is **97.4% device-bound** |
| whole daemon's CPU | **4.22% of one core**, cross-checked by an independent `ps` sampler peaking at 8.5% |

**Host cost follows bytes moved, not chunk count.** Across an 8× range of I/O size, µs/MiB varied
1.32× while µs/chunk varied 8.65×. A larger I/O size therefore does **not** reduce it.

**The requirement is satisfied on every transport this product is likely to meet, and the margin
shrinks as transports get faster.** Because the cost is per-byte, its share of run time rises in
proportion to throughput: ~10.9% at USB 3.2 Gen 2×2 and ~20.6% at USB4/Thunderbolt. Host work would
equal device time near 18.4 GB/s; the daemon would saturate one core near 11.1 GB/s. Neither is
reachable over USB mass storage today. This is carried as a **release-note item** for Step 16 —
BUILD-PLAN Step 16, detailed step 7 — because "device-bound" is a claim that weakens with faster
hardware and the notes should say so rather than imply it is unconditional.

---

### 2026-08-09 — NFR-USE-4 qualified: the warning text becomes suppressible, the deliberate act does not

**Trigger.** User decision during Step 14's scoping, taken before a line was written.

> *"This tool may be utilized by people who test drives professionally and the warning could really
> get annoying."* — user, 2026-08-09

**What changed.** The three mandatory warnings are now shown in a **modal raised by pressing Start**
(Proceed / Cancel) rather than occupying the main window, and that modal carries a **"Don't show
this warning again"** checkbox recorded **per logged-in user**. NFR-USE-4 previously required the
warnings before every run with no exception, and BUILD-PLAN Step 14 said so twice — once in its
gate and once in a risks note reading *"they must gate the Start action each run (the spec says
'before a run starts,' not 'once')."* Both are rewritten rather than left standing beside code that
contradicts them.

**What did NOT change, and it is the half that carries the safety property.** Suppressing the text
does not suppress the act: Start then raises a one-line confirmation naming the drive by **model and
USB serial** (Proceed / Cancel). This is deliberate and it is the reason the requirement is
*qualified* rather than *weakened*.

**Why that distinction is load-bearing here of all places.** FR-DEV-3 selects the first usable
device in FR-DEV-2's BSD-name order, confirmed under challenge on 2026-08-06 and unchanged. The FR
document's entry for that decision concludes that **"the entire mitigation sits in Step 14's
warnings"**, and BUILD-PLAN Step 11's removal of the explicit `Unmount All` / `Acquire` controls is
gated on this step for the same reason: after it, the default selection is one deliberate click from
a write. **Re-measured on 2026-08-09, that default is the 22 TB Seagate with Backup and Time Machine
mounted** (serial `00000000NT17XBRA`), rendered through the app's own enumerator rather than
reasoned about. A warning that could be switched off to nothing would hand that hazard back. A
warning that can be switched down to *"Start testing 22.00 TB Seagate Expansion HDD, S/N
00000000NT17XBRA?"* does not — and identifies the drive by the axis that survives a renumbering,
which the paragraphs themselves did not.

**NFR-USE-6 is untouched by the suppression, and that is checkable rather than asserted.** Step 10
already put the honest framing in the report (`RunReportMarkdown.whatThisDoesNotProve`) and on the
result screen (`RunReportView`), and those are not suppressible. A user who never sees a pre-run
warning again still cannot read a clean pass as a health certificate, because the copy that outlives
the session is the one that carries it.

**Scope of the suppression.** Per logged-in user, global across drives — the stated case is somebody
who tests many drives, so a per-drive flag would leave the dialog appearing on exactly the runs they
want it gone for. It lives in the **app's** `UserDefaults`, never the helper's: the helper runs as
root, so anything it persisted would be system-wide and would silently apply to every account on the
machine. Reversible from the Privileged Helper & Diagnostics window — a setting with no way back is
one the user cannot undo without editing a plist.

---

### 2026-08-11 — NFR-USE-8: screen-reader (VoiceOver) support removed from scope

**Trigger.** User decision, 2026-08-11, given during Step 14's accessibility audit (increment 6) and
before that increment's keyboard session was run. **The instruction was to remove the requirement;
no rationale was given, and none is invented here.** What follows records the effect.

**What changed.** NFR-USE-8 no longer asks for VoiceOver labels, and the product makes **no claim to
work with a screen reader**. Nothing about VoiceOver is verified, and no gate depends on it.
BUILD-PLAN Step 14's detailed step 4 and its Verification Gate both named VoiceOver; both are
rewritten rather than left standing beside a requirement that no longer says it — the same treatment
the 2026-08-09 entry gave the two places that contradicted the suppression decision.

**What did NOT change, and it is most of the requirement.** NFR-USE-8's absolute — *never convey
pass/fail status by colour alone* — is untouched, and so is Dynamic Type and colour contrast. That
absolute is the half with a v1 gate behind it, and it was **audited and passed on 2026-08-11**
across every status-bearing surface in both appearances, by rendering each one and converting it to
greyscale. It is also now the only part of NFR-USE-8 with a test behind it
(`RunReportPresentationTests`, six mutations, six caught).

**Accessibility code already in the app is kept, and that is deliberate.** Removing a requirement is
not a reason to make the product worse at something it already does. What remains:

- Seven decorative glyphs marked `.accessibilityHidden(true)` (2026-08-11) — they duplicate adjacent
  text, so exposing them was noise either way.
- The device row's combined element and spoken label, and `MountControlState.accessibilityLabel`.
- `DeviceListView`'s use of a real `List` rather than a hand-drawn one, which keeps ↑/↓ keyboard
  navigation as well as screen-reader semantics. **Keyboard navigation is not affected by this
  amendment** and remains a reason that choice stands.

These are retained voluntarily and are no longer requirement-driven, so nothing needs to verify
them and no future step inherits an obligation to.

**What this costs, stated rather than discovered later.** A blind or low-vision user cannot be told
this tool works for them, and if that is ever revisited the work is larger than re-adding a line to
this table: it would need the audit this amendment cancels, on every surface, with a person at the
keyboard each time.

### 2026-08-20 — NFR-USE-9 corrected: the instrument was wrong, and the budget with it

**The gate was answering "does it fit" with a height at which it demonstrably does not.**
`window-fit-check.sh` read `NSWindow.contentMinSize` — what SwiftUI *declares* — and that number is
built from the `.frame(minHeight:)` each pane asks for. `WindowMetrics.deviceListFloor` asks the
drive list for **46 pt**, one row, and **the AppKit table backing that pane will not lay out below
about 104 whatever it is told**. SwiftUI believed the 46, so the declared total described a height
the content cannot occupy, and it was short by **58 pt** in every state.

Found by driving the shipped window with accessibility scripting: the real app clamps at **575 pt**
where the gate reported 517. Confirmed two further ways — a render at the declared minimum clips its
header, and raising `deviceListFloor` to 104 moves the declared number to 543 exactly, which is what
the app enforces.

**The gate now measures the layout instead of the declaration.** `--limits` reports the larger of
the declared minimum and the smallest height at which the laid-out content stops overflowing the
space it is given. Each can be too small — a declared floor a control ignores, or a view whose whole
body is a scroll region and so never overflows — and neither can be too large. This is why the
requirement above now constrains *how* the minimum is measured and not only that it is derived.

**Two consequences, and the second is the reason this amendment exists.**

First, the run controls' duplicate refusals were finally collapsed — the fix the 2026-08-19
amendment described as worth ~80 pt and deferred. It was worth exactly that: `starting` went from
718 to **638**. In the four transient states (`starting`, `pausing`, `stopping`, `finishing`) the
run state is itself the reason every control refuses, and the status line already names it, so one
sentence draws where three did. Each sentence measures 40 pt.

Second, **the committed budget moves from 620 to 700** (user decision, 2026-08-20) — a 13.3-inch at
**1280x800** with the Dock showing, rather than at every scaling it offers.

That is not a retreat from a met commitment. The 620 target was chosen on 2026-08-19 *from the
broken numbers*, which showed every state but one fitting it. None of them did: corrected, `running`
and `paused` miss 620 by 4 pt with six drives attached, and `starting` missed it by 98. 700 is where
the decision started before the wrong figures made a tighter target look free, and against it every
state fits with at least **62 pt to spare** — with `scripts/.window-fit-exceptions` empty for the
first time since it was created. A user at 1152x720 gets a window that fits at rest and grows behind
the Dock for the few seconds a run spends starting.

**The drive-count dependency is back, and it is small.** Increment 7 recorded the window's minimum
as independent of how many drives are attached. That was an artefact of the declared number, which
ignored drive count too. Measured honestly it swings **11 pt** between one drive and six, because
the list's real floor tracks its content where its declared floor does not. The gate checks both
ends, so the worst case is the one reported.

### 2026-08-19 — NFR-USE-9 added: the main window has to fit the smallest supported Mac

**Why this is a new requirement rather than a bug fix.** The window opened at screen height and its
minimum did not fit a 13.3-inch Mac, and when that was investigated it turned out **nothing in
either requirements document said what it had to fit**. There was no requirement to be in breach
of. Step 11 increment 7 was built against a user decision, and a commitment with no requirement
behind it is one nobody can check later — so the decision is written down here.

**The correction the decision turned on: points, not pixels.** A 13.3-inch Apple Silicon Mac has a
2560x1600 **pixel** panel, and the first framing of this question used 1600 as the vertical budget.
macOS lays windows out in **points**, and that machine is **1440x900 points** at its default
scaling. Reasoning from the pixel number makes every figure look comfortable by a factor of 1.8,
and would have closed this question with the window still not fitting.

Measured on the development Mac rather than recalled: the title bar costs **32 pt**, the menu bar
takes **30 pt** out of `NSScreen.visibleFrame`, and a bottom Dock at the default tile size takes
roughly **70** more. So:

| scaling offered by a 13.3-inch Mac | points tall | budget for a window |
|---|---|---|
| 1440x900 (default) | 900 | 800 |
| 1280x800 | 800 | 700 |
| 1152x720 | 720 | 620 |

**What the requirement asks for beyond fitting.** That the minimum be *derived*. The number this
replaced was a literal in `ContentView` that expired **three times**, silently each time, because
nothing recomputes a literal and nothing was watching. The requirement therefore constrains how the
answer is arrived at and not only what it is — which is unusual for an NFR and is deliberate.
`scripts/window-fit-check.sh` is the check: it asks the real view hierarchy, through
`ui-probe --limits`, for the limits it hands a window.

**Known and recorded as not yet met.** The `starting` state needs a 631 pt window against the 620 pt
budget of the tightest scaling — over by **41 pt**. Every other state fits every scaling.

> **Superseded 2026-08-20, and every figure in the paragraph above is wrong.** The gate producing
> them was reading a declared minimum that was 58 pt short in every state; `starting` really needed
> 718. The scaling this amendment committed to was never met by any state. See the amendment
> below.

## Assumptions

- This is a **single-user, single-host desktop tool**; multi-user concurrency, networked operation, and high-availability/service-uptime requirements are not applicable.
- The product is **English-only**; no localization infrastructure (string catalogs, translation) is built for the first release (decision 2026-06-25).
- "Performance" targets are about overhead and responsiveness, not absolute throughput — absolute speed is bounded by the device and USB link, which the tool measures rather than controls.

## Out of Scope (Non-Functional)

- **SMART/NVMe-derived health metrics** as a quality signal — excluded with the functional feature (USB-to-SATA SAT pass-through unreliability). — *ADR Telemetry sub-decision*
- **Throughput-optimizing pipelined I/O** — the first release accepts serialized-I/O runtimes; pipelining is a later optimization. — *ADR Trade-off Analysis*
- **Localization / internationalization** — English-only for v1; no translation infrastructure. — *user decision 2026-06-25*
- **Screen-reader (VoiceOver) support** — the GUI is not required to work with a screen reader, and no VoiceOver behaviour is verified. The rest of NFR-USE-8 (never pass/fail by colour alone, Dynamic Type, contrast) is unaffected. — *user decision 2026-08-11; see Amendments*

## Open Questions (to resolve during iteration)

1. ~~**Performance overhead target (NFR-PERF-3):**~~ **Resolved 2026-06-25** — qualitative "device-bound, not host-bound"; no fixed percentage.
2. ~~**Metrics refresh cadence (NFR-PERF-5)** and **ETA accuracy tolerance (NFR-PERF-6):**~~ **Resolved 2026-06-25** — refresh at least once per second; ETA qualitative (measured-throughput-derived, converges over time).
3. ~~**Code-signature validation strictness (NFR-SEC-2):**~~ **Resolved 2026-06-25** — Team-ID match only (bundle identifier / Apple anchor not separately pinned).
4. ~~**Accessibility commitment (NFR-USE-8):**~~ **Resolved 2026-06-25** — Should / best-effort; not a v1 release gate.
5. ~~**Localization:**~~ **Resolved 2026-06-25** — English-only for v1; no localization infrastructure (now in Out of Scope).
6. ~~**Logging verbosity/retention (NFR-OBS):**~~ **Resolved 2026-06-25** — `os_log` events as specified in NFR-OBS-1/2 are sufficient; no user-visible activity log or formal level/retention rules for v1.
7. ~~**Minimum deployment target:**~~ **Resolved 2026-06-25** — minimum deployment target is macOS 26 (Tahoe); Xcode/Swift versions are not pinned in the spec (left to build config).
