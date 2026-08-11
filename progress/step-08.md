# Step 8 — read → write-back → read-verify cycle

*Archived from `PROGRESS.md` on 2026-08-11, when the log was split. Nothing here has been
edited — statements carry the dates on which they were true.*

**Do not read this as current.** What still binds today's work is in
[CONSTRAINTS.md](../CONSTRAINTS.md); what is in progress is in [PROGRESS.md](../PROGRESS.md).
This file is here for the one question the other two cannot answer: *why was it done that way?*

---

## Step 8 — COMPLETE (2026-08-03)

Every gate item discharged. **The first bytes this project has ever written to real media were
written during this step, and the drive is byte-identical afterwards.**

**Delivered.** The cycle at the heart of the tool — read a chunk, write the *same* bytes back,
read them again, compare — over any `RawBlockDevice`, so the identical code path runs against the
simulated device and against `/dev/rdisk4`. With it: block-narrowed verify failures; a bounded,
coalescing failure log; a `LoadedChunk` token that makes "write after a failed read" unexpressible;
a per-chunk NFR-REL-3 guard that stops the *next* write when access goes away; FR-TEST-9's verdict
seeded at acquire and fed the run's own throughput; protocol **v7**; and a hardware gate that
fingerprints a terabyte either side of the write.

**Final state.** **403 tests, 0 failures.** Zero warnings from clean **Debug**, clean **Release**
*and* a clean **test-target** compile, DerivedData wiped before each.
`./scripts/ioctl-constants-check.sh` **11/11** (was 9/9).
`./scripts/retention-cycle-check.sh disk4` **15/15**.

**Requirements affected.** None added. Five BUILD-PLAN amendments (8.8's wording, the `F_NOCACHE`
risk line, gate items 4 and 5, plus new detailed steps 9–11), and a new Step 9 obligation to
measure helper CPU against throughput (NFR-PERF-3, which had never had a number attached).

### The hardware result

`retention-cycle-check.sh disk4`, placement block **277,372,928** — drawn at random from 238,212
chunk-aligned positions:

| | |
|---|---|
| chunks | **256** — 255 full + one short (FR-TEST-5 on real media) |
| failed ranges | **0** |
| cache bypass at end | **1 = `bypassed`** (FR-TEST-9 survived real I/O) |
| fastest read | **492,870,060 B/s** — transport-plausible, not RAM-plausible |
| buffers held | **8,388,608 B** = 2 × I/O size (NFR-PERF-1) |
| fingerprint coverage | **932 windows, 1,000,204,886,016 bytes — exactly the device's size** |
| before vs after | **byte-identical** |

Verified independently of the script: **0 of 932 windows are all-zero** and **932 of 932
fingerprints are distinct**, so a stray write anywhere on the drive would have moved a window.

### What this step cost, and what it bought

**Seven defects, all found before they could mislead.** Four in the code, three in the gate — and
the gate ones were the dangerous kind, because a gate that passes wrongly is worse than no gate.

1. The engine reset a **process-global** counter (`ChunkBuffers.peakAllocatedBytes`), clobbering a
   Step 7 suite running concurrently. Production code must not mutate shared instrumentation.
2. **Parallel testing made global-counter assertions unsound.** Three green runs after fixing (1)
   were not evidence. Loosening was rejected — *no* assertion on a global counter is immune to
   concurrent mutation — and the suite was serialised instead: 9.7 s → 18.8 s, measured.
3. The gate script planned a run at block **−893,534,208**: `od -N8 -tu8` yields 64 unsigned bits
   and **bash arithmetic is signed**. Caught by a dry run that aborts before unmounting.
4. The first hardware run failed on `EACCES`, and the check **reported it as `EBUSY`'s meaning** —
   asserting a conclusion its evidence did not support, the same conflation Step 6 untangled.
5. The content check parsed **`awk '{print $4}'` — the block count, not the fingerprint.** It
   would have reported "2 distinct values" on any drive, empty or full, forever.
6. `disk4` was **1% used**, so a random placement tested a region of pure zeros. Writing zeros
   over zeros is non-destructive however wrongly it is addressed.
7. The client's stdout was **block-buffered through `tee`**, so an hour-long run reported no
   progress at all. Invisible until a run lasted longer than ten seconds.

**One measurement changed the design.** `O_EXLOCK` held by the helper refuses a second
`O_RDONLY` open — `EBUSY`, even for root with Full Disk Access requesting no lock. Not in the
2026-07-30 matrix, which only tested `O_EXLOCK` against `O_EXLOCK`. It made the planned
"fingerprint from a separate process" impossible and moved the digest into the helper as protocol
v7. The pre-flight that caught it was written **before** the gate design was committed to;
assuming it would have produced a gate failing ~40 minutes in, immediately after the first write
to real media, with no way to tell "the digest could not be taken" from "the device changed".

**The lesson, in this step's own words.** Defects 5 and 6 are one failure wearing two faces: a
gate reported **15 checks, 0 failures** over a region of zeros, with a check that had never once
looked at a fingerprint. Both had been *anticipated* — the source comment said "an all-zero region
legitimately repeats" — and shipped anyway. **A comment acknowledging a hole is not a check; it
is a note explaining why the check does not work.** The replacement samples three chunks from
inside the tested range before anything is written and requires their fingerprints to differ, and
it reads its input from an unambiguous source rather than positionally from a file whose columns
must be remembered correctly.

**And the fix for the vacuity risk cost nothing on hardware.** With both fingerprints taken by one
process, a digest returning a constant would make "before == after" pass unconditionally. That was
closed entirely in simulation: `Core/DeviceDigest` is pinned against **externally computed**
SHA-256 vectors — every constant from Python's `hashlib` over the same bytes, never from running
the Swift code and recording its output.

**Carried into Step 9.**

- `RunObserver` already carries per-chunk `ChunkTiming`; Step 9 builds throughput and latency from
  it. Step 8 computes **no** statistics — it times reads only to feed FR-TEST-9's falsifier.
- `FailureDisposition` is the seam Step 10 fills with FR-FAIL-1/2/3's user-selectable modes.
  Step 8 ships one caller, which always continues.
- **Measure helper CPU against throughput (NFR-PERF-3).** Never numbered. The 36–39% of one core
  observed at ~500 MB/s during this gate is the *fingerprint*, which is not in the product; the
  cycle's per-chunk `memcmp` is expected to be far cheaper and is **unmeasured**.
- `runRetentionCycle` and `digestRange` are both capped at 1 GiB per call because there is no
  cancellation until Step 11. Step 11 replaces the first with real run control.

**Not discharged by this step, and not to be mistaken for covered:** the final chunk at the
**physical end** of the device, and a whole-device traversal. Neither is reachable under the
"1 GiB clear of the end" rule. Both belong to a later, separately agreed run — the `disk8`
precedent.

---

## Step 8 — scoping, decisions and authoring log

**AI-6 / satisfies FR-TEST-1/3/4/7/8; FR-FAIL-6/7; NFR-REL-1/2/4/8; and FR-TEST-9's caller.**
**Helper-side core** — runs identically against the simulated device.

Recorded here so a cold start has the state without re-deriving it from the log above.

### State this step begins from

- **Steps 1–7 complete.** Step 7 committed at `e0fdea2`, docs convention at `d1259d9`;
  `git` clean on `main`.
- **Protocol v5.** `ping`, `protocolVersion`, `validateRunParameters`, `prepareForShutdown`,
  `checkDeviceReadiness`, `acquireDevice`, `releaseDevice`, `deviceProfile`.
- **323 tests, 0 failures.** Zero warnings from clean Debug **and** clean Release builds.
- **The installed helper is v5**, registered from `/Applications`, with Full Disk Access
  granted. Re-registering does not prompt on this machine; a clean Mac will.
- Hardware gates passing: `geometry-check.sh disk4` 9/9, `large-address-check.sh disk8` 10/10,
  `claim-contention-test.sh disk4` 12/12. Guard scripts: `ioctl-constants-check.sh` 9/9,
  `usb-speed-check.sh` 3/3.

### What Step 7 hands over

- **`AcquiredDevice.blockDevice()`** — vends a `FileDescriptorBlockDevice` over the held
  descriptor using the **authoritative** (ioctl-derived, reconciled) geometry. Returns `nil`
  once released. Built on demand rather than stored, so it cannot outlive the descriptor.
- **`AcquiredDevice.deviceGeometry`** — the authority. `AcquiredDevice.geometry` is IOKit's
  and is **provisional**; it is kept only for comparison and the log.
- **`AcquiredDevice.cacheBypass`** — the FR-TEST-9 verdict established at acquire. Step 8
  seeds a `CacheBypassAssessment` from it *plus* `AcquiredDevice.usbLinkSpeed`, then feeds each
  chunk's throughput in via `observe(bytes:nanoseconds:)`. That can only ever downgrade.
- **`RetentionTestEngine.chunks()`** — the **lazy** plan, and what a run must iterate.
  `chunkPlan()` still exists but materialises: 9.1 MiB for `disk4`, 200.1 MiB for `disk8`. It
  is for tests and diagnostics only.
- **`ChunkBuffers`** — the two page-aligned buffers, allocated once and reused. `original` is
  buffer A and is the **only copy of the user's data** during the write, which is exactly what
  bounds NFR-REL-4's in-flight window to one chunk. `original(byteCount:)` / `verify(byteCount:)`
  give the short prefix the final chunk needs.
- **`WritePrecondition.check(_:writingTo:)`** — the NFR-REL-3 runtime guard. The compile-time
  half is that the write path takes an `AcquiredDevice`, which only a successful acquire can
  produce.
- **`InMemoryBlockDevice`** — fault injection (`injectReadFault`, `injectWriteFault`,
  `injectSilentCorruption`) and `snapshot()`, all from Step 2 and all still unused. Step 8's
  gate is what finally exercises them.

### Hazards that will bite Step 8 specifically

1. **This step writes the first byte to real media.** Everything before it was read-only.
   NFR-REL-1 requires non-destructiveness proven **in simulation first**, and the gate is
   ordered that way deliberately — the `disk4` run is the *last* item, not the first.
2. **A torn write to the GPT or a superblock can brick an otherwise-good drive.** `disk4`'s
   contents are expendable; the *time* spent re-creating a test volume is not, and the point
   generalises to a user's drive.
3. **The verify must not be vacuous.** If buffer A and buffer B ever alias, or the write does
   not truly precede the verify read, the comparison passes for every chunk of every drive.
   `ChunkBuffersTests.theTwoBuffersAreDistinctMemory` guards the first; ordering guards the
   second; FR-TEST-9 guards the third (host caching).
4. **FR-TEST-7 is absolute: write back the bytes that were read, never a pattern.** A
   known-value write would be a faster, easier test and would destroy user data.
5. **One chunk in flight (NFR-REL-4).** Never hold more than the current chunk's original.
   Anything that accumulates — a list of chunks processed, per-chunk timings kept for later —
   reintroduces the capacity-scaling NFR-PERF-2 forbids and Step 7 removed.

### The gate (from BUILD-PLAN)

- [ ] Non-destructiveness proven in simulation (NFR-REL-1): known random data, full cycle,
      backing store bit-for-bit identical afterwards.
- [ ] Verify-mismatch detection (NFR-REL-8): corruption injected on a range flags exactly
      that range and no other.
- [ ] Hard-error classification (FR-FAIL-6): read-error and write-error injection produce
      correctly-typed `BlockRangeFailure`s.
- [ ] One-chunk-in-flight (NFR-REL-4) confirmed by instrumentation.
- [ ] The cycle runs end-to-end against `disk4` and leaves its contents unchanged
      (checksum before == after). **Only after the simulation proof passes.**

### Scoping decisions (2026-08-02, user decisions) — APPROVED

Seven decisions were put to the user with recommendations; all seven were taken as
recommended, two with constraints the user supplied that changed the design.

**D1 — how the hardware gate drives the cycle: a bounded XPC method on the real helper**
(protocol **v5 → v6**), not a standalone `sudo` probe. A probe would compile the identical
engine but bring its own descriptor, its own acquire and its own geometry — a substitute for
the helper on the one run where the first byte is written to real media, which is the exact
mistake this project's standing lesson describes. The method is **capped by construction**
because there is no cancellation until Step 11 and no progress channel until Step 9: an
uncancellable privileged operation that a caller can start must be bounded, or a root daemon
can be wedged for hours with `prepareForShutdown` correctly refusing throughout.

**D2 — how much of `disk4` to write, and where. User constraints, which supersede the
three-segment proposal that was offered:**

> *"I really don't care about any data on disk4. If data corruption occurs, I'll reformat the
> drive. Since we are unable to cancel a test run until Step 11, for now I want the test to
> limit itself to 1 GiB worth of LBA's and then stop the test as if the test were completed.
> That's 3 GiB total of i/o's (R+W+R) with at least an average speed of 200 MiB/sec so the
> test run should complete in less than 15 seconds. Start at a random LBA (to minimize NAND
> wear) that is a multiple of 1024 and at least 1 GiB before the logical end of the drive so
> we don't hit the end of the drive during the test."* — user, 2026-08-02

Three consequences, none of them cosmetic:

1. **The bound is expressed as the plan, not as an early stop.** "Stop as if the test were
   completed" is exactly what happens when the engine is handed a plan covering only that
   range and runs it to the end. So `ChunkPlan` gains a `startBlock` and the engine keeps its
   single behaviour — *complete the plan you were given*. No stopped-early state is needed for
   the gate, and FR-TEST-1/4's whole-device traversal remains the default (`startBlock = 0`,
   the whole device) rather than becoming one option among several.
2. **A chunk-index range cannot express the requirement.** An arbitrary start LBA is not in
   general a multiple of 8,192 (one 4 MiB chunk at 512-byte blocks), so the earlier proposal —
   a range of chunk indices over the whole-device plan — was discarded before it was written.
   `ChunkPlan.startBlock` accepts **any** block-aligned start, so this constrains the design
   rather than the parameters.

**Start alignment revised to 8,192 blocks (user decision, same day).** The original instruction
said a multiple of 1,024. `ChunkPlan.startBlock` handles either, so this is not forced by the
code — it is chosen, for one reason: **8,192 blocks is where a real whole-device run's chunks
actually land.** A gate that writes at offsets production will never use is testing something
production does not do, and this project has already paid for substituting a nearly-right thing
for the real one. What it costs: a start that is *not* on a whole-device chunk boundary is no
longer exercised on hardware. That path is `ChunkPlan.startBlock`'s arithmetic, it is covered
exhaustively in simulation where it can be checked at every offset rather than one random one,
and it is not a property of the drive.

**The gate's numbers on `disk4`, computed rather than assumed:**

| | |
|---|---|
| Device | 1,953,525,168 blocks |
| Run length | **2,096,128 blocks** (1,023.5 MiB) — 255 full 4 MiB chunks + a final chunk of **7,168 blocks (3.5 MiB)** |
| Start | a multiple of **8,192**, chosen at random from **238,212** positions: 0 … **1,951,424,512** (238,211 × 8,192) |
| Ceiling | the user's rule — start no later than 1 GiB before the logical end (1,953,525,168 − 2,097,152 = 1,951,428,016), floored to the alignment |
| Margin at the latest start | run ends at 1,953,520,640, leaving **4,528 blocks** |

Note that block 0 is a legal draw, so a run may land on the GPT and the exFAT boot sector.
That is deliberate and is covered by the user's position that `disk4`'s contents are
expendable — it is also the one region where hazard 2 ("a torn write to the GPT can brick an
otherwise-good drive") is a live case rather than a hypothetical. The script prints the drawn
start before it writes anything, and says whether the run overlaps the first 34 blocks.
3. **The cap is 1 GiB**, and the `mount-guard-client` reply timeout goes from 30 s to 300 s.
   At the user's 200 MiB/s floor the call takes 3,072 MiB ÷ 200 MiB/s ≈ **15.4 s**, which is
   under the existing 30 s but not by enough to survive a struggling drive; at the measured
   475 MB/s it is ≈6.8 s.

**The range is 1 GiB − 512 KiB, not 1 GiB — a judgment call taken, and reversible.**
2,096,128 blocks: 255 full 4 MiB chunks **plus a final chunk of 7,168 blocks**. 1 GiB divides
by 4 MiB exactly, so a full 1 GiB range would contain no short final chunk, and the
"at least 1 GiB before the logical end" rule means the gate never reaches the end of the
device either. FR-TEST-5's short-chunk path — `original(byteCount:)` / `verify(byteCount:)`,
and whether the bridge accepts a **write** that is not a full I/O size — would then run only
in simulation. Shortening the range by 512 KiB exercises it on real media, stays inside the
user's 1 GiB ceiling, and stays 1,024-block aligned. Cost: nothing.

**What this gate deliberately does NOT discharge**, recorded so it is not mistaken for
covered: the final chunk **at the physical end of the device**, and the whole-device
traversal. Neither is reachable under the 1-GiB-clear-of-the-end rule. Both belong to a
later, separately agreed run — the `disk8` precedent from Step 7.

The start LBA is chosen by the **script**, not the helper — a root daemon has no business
owning a "pick somewhere to write" behaviour — and is printed and recorded, so a failure can
be re-run at the same place. Bounds on `disk4`: `blockCount` is 1,953,525,168, so the start
must be a multiple of 1,024 no greater than 1,951,427,584 (1,953,525,168 − 2,097,152, floored
to a multiple of 1,024), which leaves 432 blocks of margin beyond the user's rule.

**D3 — evidence that nothing changed: a per-1-GiB SHA-256 vector plus a whole-device digest,
taken twice, both inside the claim window.** The vector costs the same I/O as a single scalar
digest and localises any difference to a 1 GiB window instead of merely asserting one exists.
~35 min per pass on `disk4`, so ~70 min for the pair. Both digests must be taken while the
helper still holds the claim: release makes DiskArbitration remount ~4 ms later, and a mounted
exFAT volume writes to itself, so an "after" digest taken post-release would differ for
reasons that have nothing to do with this tool.

> *"if it is better to develop and run a test tool before deciding, let's do that"* — user

**So `tools/media-digest` is built and run BEFORE the gate design commits to it**, and its
first job is a fact this log does not contain: **can a second process
`open("/dev/rdisk4", O_RDONLY)` while the helper holds `O_EXLOCK`?** The 2026-07-30 matrix
records that two plain `O_RDWR` opens both succeed and that a second `O_EXLOCK` is refused —
but not that combination, and the whole digest ordering above rests on it. Read-only, nothing
unmounted, nothing written. If it fails, the fallback is for the helper to compute the digest
through its own descriptor, which is more work and is worth discovering now rather than at the
gate.

**D4 — verify mismatches narrow to contiguous failing block sub-ranges** within the chunk,
paid only on mismatch. Gate item 2 requires the injected range to be flagged "and no other";
at chunk granularity a 4-block injected corruption inside an 8,192-block chunk flags 8,192
blocks, which does not satisfy that wording and would make Step 10's report far less useful.
Hard read/write errors stay **chunk-granular**: the syscall failed for the whole request, and
narrowing there would invent precision the device never gave us.

**D5 — a minimal `.continueRun` / `.stopRun` disposition now.** Without a stop path, detailed
step 6 (NFR-REL-5, "on stop, issue no further writes") has nothing to test. Step 8 ships one
caller, which always continues. The user-selectable **modes** — FR-FAIL-1/2/3/4 and their
default — remain Step 10's.

**D6 — Step 8 times both reads and feeds both into `CacheBypassAssessment.observe()`.** The
**verify** read is the load-bearing one: it is the read a host cache would answer, so feeding
only the original read would systematically miss the very signal FR-TEST-9 exists to catch. No
min/max/p99 and no throughput averages — that is Step 9. The clock is injected
(`clock_gettime_nsec_np(CLOCK_UPTIME_RAW)` by default), which is what makes the falsifier
testable: a fake clock returning 0 ns must drive the run's verdict to `likelyCached`.

**D7 — `DKIOCGETMAXBYTECOUNTWRITE` (request 71) is added** alongside the existing read
constant, diagnostic only, with a line in `ioctl-constants-check.sh`. Step 7 established that
`disk4` advertises a 1 MiB maximum **read** and still answers a 4 MiB and an 8 MiB `pread`
whole. The write side is unmeasured and `shortTransfer` on the write path has never executed
anywhere, on any device, in any test. If a real write ever comes back short, this is the first
number anyone will want.

### Tooling note (2026-08-02) — `xcresulttool` reports TWO test counts

Found while taking a baseline before Step 8's tests were written, and recorded because it
produced a phantom regression: a run that had changed nothing appeared to gain 17 tests.

`xcrun xcresulttool get test-results summary` emits **two different counts**, and the
misleading one comes first:

| Where in the JSON | `disk4` baseline, 2026-08-02 | What it counts |
|---|---|---|
| `passedTests` **inside** `devicesAndConfigurations` | **340** | executed test *cases* |
| top-level `totalTestCount` / `passedTests` | **323** | `@Test` *declarations* |

Confirmed against the source: `grep -rh '@Test' USBDriveTesterTests/*.swift` counts exactly
**323**, of which **6** are parameterised — and those 6 expand to 23 executed cases, which is
the whole of the 17-case difference. The Step 7 run's bundle reports the identical 340/323
pair, so nothing had changed.

**Use the top-level `totalTestCount`.** That is the measure Step 7's "323" refers to and the
one to keep quoting.

⚠️ **Step 6's "235 test cases (226 `@Test` declarations)" is the *other* measure** — it
headlined executed cases. So 235 → 323 is not a like-for-like comparison, despite Step 6's note
claiming its figure was chosen to make exactly that comparison safe. Step 6's declaration count
(226) is what lines up with 323.

### A sixth hazard, added 2026-08-02 — stale buffer contents

The five hazards recorded above do not cover this one, and it is the worst thing this step can
do.

**The buffers are reused, so a failed original read must never be followed by a write.** If
chunk *n*'s read fails and control falls through to the write, `ChunkBuffers.original` still
holds **chunk *n−1*'s data**, and the engine writes the previous chunk's bytes to this chunk's
offset. That is silent, permanent corruption of a region the tool was asked to preserve, on a
drive whose every other block verifies clean — and it is one missing `continue` away. Hazard 3
does not cover it: that one is about aliasing and ordering, this one is about **staleness**.

Made structurally impossible rather than guarded by control flow: the read step returns a
`LoadedChunk` token, produced **only** on a successful read and carrying the chunk and its byte
count, and the write step takes that token. There is then no expressible path from a failed
read to a write. The test injects a read fault on chunk *n* and asserts the backing store at
chunk *n*'s offset is **untouched** — not merely that a failure was recorded.

The same shape one step later: **a failed write must not be followed by a verify read.**
Reading back after a failed write compares buffer A against the *old* data and reports a
spurious verify mismatch on a chunk whose actual fault was the write. A write failure ends the
chunk.

### Bounded failure accumulation (NFR-PERF-2, decided during scoping)

`RunSummary` cannot hold an unbounded `[BlockRangeFailure]`: a device with millions of bad
blocks would reintroduce exactly the capacity-scaling growth Step 7 removed from the chunk
plan. So failures are **coalesced on append** (same kind, contiguous blocks) and the retained
list is **capped**, with the total count and a `truncated` flag carried separately. The cap is
reported rather than silent — a truncated list that does not say so reads as a complete one,
which is the same class of defect as a report line that appears only on failure. Coalescing
also discharges part of Step 10's "coalesce contiguous failing chunks into ranges, but don't
lose a non-contiguous failure" risk note.

### Conflicts with Step 7's findings — RESOLVED (2026-08-02, user instruction)

> *"resolve Step 8 conflicts based upon Step 7 learnings"* — user

BUILD-PLAN Step 8 is amended in five places, all 2026-08-02:

1. **8.8 said "call the Step 7 mechanism" before the first chunk. There is nothing to call.**
   FR-TEST-9's check runs at **acquire**, inside `DeviceClaim`, and its verdict is already on
   `AcquiredDevice.cacheBypass`. Step 8 *seeds* from it; it does not invoke it. That is not a
   shortcut — the check is `fstat` plus the two `fcntl` results on the descriptor, and Step 7
   measured that opening the raw node speculatively to answer a query makes DiskArbitration
   remount the volume ~4 ms later. Amended to *performed at acquire, consumed at run start*,
   which is sound because the acquire holds the descriptor continuously between the two.
2. **The risks section said "Step 7's `F_NOCACHE` is what makes the verify meaningful".
   Step 7 measured that this is false.** `/dev/rdiskN` is the character device, the buffer
   cache belongs to the block node, and `F_NOCACHE` had nothing to suppress. What makes the
   verify meaningful is that the descriptor **is** the character device. Left as written, that
   line points the next reader at the wrong mechanism and would justify re-proposing the timing
   check the calibration probe already killed.
3. **Gate item 5 was under-specified for a 1 TB device** — replaced with the bounded
   random-placement run and the digest vector of D2/D3.
4. **Gate item 4's instrumentation half-exists.** `ChunkBuffers.peakAllocatedBytes` (Step 7)
   covers the *buffer* half. What it cannot see is the hazard NFR-REL-4 actually names — a
   second chunk's original being held, or per-chunk state accumulating beside bounded buffers.
   That needs an **ordering** proof, and by this project's rule the checker must be shown
   capable of failing before its passing is believed.
5. **`chunkPlan()` must not appear in the run path or in any many-chunk test** — it is the
   9.1 MiB / 200.1 MiB materialised path. Stated because it is still the more convenient API
   and the Step 2 tests use it.

### Approved file plan (2026-08-02) — NOT YET AUTHORED

Author in this order: pure logic and its tests first, then the privileged side, then the
tooling, then hardware. The Step 5/6/7 order, and also the gate's order — the simulation proof
comes before the first byte reaches real media.

**Core** — `com.arc3solutions.USBDriveTester.Helper/Core/`
- `RetentionRun.swift` *(new)* — the run's vocabulary: `BlockRangeFailure` +
  `FailureKind { readError, writeError, verifyMismatch }` (FR-FAIL-6); `RunSummary` with the
  bounded, coalesced failure list; `RunObserver` (so Core emits events and the **helper** does
  the `os_log`, keeping Core pure); `FailureDisposition`; `RunAbort` for engine faults that are
  **not** device failures; the injected monotonic clock.
  ⚠️ **Needs an Xcode target-membership tick** for `USBDriveTesterTests`, exactly as the
  Step 2/3/6/7 Core files did. It is the only GUI action Step 8 requires.
- `RetentionTestEngine.swift` *(edit)* — `ChunkPlan.startBlock`; `run(...)`: the per-chunk
  cycle over `chunks()`, the `LoadedChunk` token, per-chunk `WritePrecondition.check`,
  block-narrowed mismatch scanning, `CacheBypassAssessment` seeding and `observe()`.
- `DiskIOControl.swift` *(edit)* — `DKIOCGETMAXBYTECOUNTWRITE` (request 71), diagnostic.

**Helper** — `com.arc3solutions.USBDriveTester.Helper/`
- `RunCoordinator.swift` *(new)* — bridges `AcquiredDevice` → engine: allocates
  `ChunkBuffers`, seeds the assessment from `cacheBypass` + `usbLinkSpeed`, supplies the grant
  provider, enforces the 1 GiB cap, `os_log`s run start and each failed range — never contents
  (NFR-SEC-6) — and returns the summary.
- `main.swift` *(edit)* — the v6 method.

**Shared** — `USBDriveTester/Shared/`
- `TesterControl.swift` *(edit)* — protocol **v5 → v6**:
  `runRetentionCycle(startBlock:blockCount:ioSizeBytes:)`, replying with
  `(ok, chunksProcessed, failureCount, firstFailureSummary, cacheBypassCode,
  fastestBytesPerSecond, peakBufferBytes, message)` — every parameter ObjC-representable, as
  the rest of the protocol is.

**Tests** — `USBDriveTesterTests/` (auto-join; no ticks)
- `RetentionCycleTests.swift` — the four simulation gate items plus the stale-buffer, write-
  failure, grant-revocation, stop-path and falsifier cases.
- `ChunkCycleAudit.swift` — test support: a `RecordingBlockDevice` decorator and the **pure**
  checker over the recorded operation sequence.
- `ChunkCycleAuditTests.swift` — feeds the checker hand-built **bad** sequences (write before
  read, verify read before write, two chunks open at once, missing write) and asserts it
  rejects each. Without this file the audit is a check that cannot fail.

**Tooling** — `tools/`, `scripts/`
- `tools/media-digest/main.swift` *(new)* — one pass over an `O_RDONLY` descriptor emitting a
  SHA-256 per 1 GiB window plus a whole-device digest. It takes a path, so pointing it at a
  temporary file and flipping one byte is its canary — the same shape as Step 7's assertion
  that a temp file *accepts* the misaligned read the device refuses. **Built and run first**,
  for the `O_RDONLY`-under-`O_EXLOCK` measurement.
- `tools/mount-guard-client/main.swift` *(edit)* — a `cycle:<startBlock>:<blockCount>` command
  and a 300 s reply timeout for it.
- `scripts/retention-cycle-check.sh <disk>` *(new)* — the hardware gate.
- `scripts/ioctl-constants-check.sh` *(edit)* — the request-71 line.

### Authored so far (2026-08-02) — the simulation half is DONE

**Core, and its tests, complete and green. Nothing has touched real media.**

| Authored | State |
|---|---|
| `Core/RetentionRun.swift` | new; target-membership tick applied and verified in `project.pbxproj` |
| `Core/RetentionTestEngine.swift` | `ChunkPlan.startBlock` + `run(...)` |
| `Core/DiskIOControl.swift` | `getMaxByteCountWrite` (request 71) |
| `USBDriveTesterTests/ChunkCycleAudit.swift` | recorder, pure checker, `SplitMix64`, `TestPattern`, `firstDifference` |
| `USBDriveTesterTests/ChunkCycleAuditTests.swift` | 21 tests — every violation produced deliberately |
| `USBDriveTesterTests/RetentionCycleTests.swift` | the four gate items and the cases that make them mean something |

**386 tests, 0 failures** (up from 323; the number is the top-level `totalTestCount`, and
`grep -rh '@Test'` over the test sources agrees at 386). Debug builds with no warnings and no
errors from a forced recompile of every changed file. **The clean Debug + Release
zero-warning check of the Global DoD is still outstanding** and belongs at the end of the step.

**Gate items 1–4, plus the added read-fault item, are discharged in simulation:**

- **1 — non-destructive, bit-for-bit.** Whole-device runs at 512 B *and* 4,096 B geometry leave
  the backing store byte-identical, checked by first-differing-index rather than by comparing
  4 MB arrays inside `#expect`.
- **2 — verify mismatch flags exactly that range.** A 4-block fault inside a 128-block chunk
  reports 4 blocks, not 128; a single flipped bit in one block reports one block; a fault
  straddling a chunk boundary arrives as one coalesced range; separate faults stay separate.
- **3 — hard errors classified.** Read faults, write faults and corruption in one run produce
  three correctly-typed ranges, and adjacent ranges of *different* kinds are not merged.
- **4 — one chunk in flight.** The ordering audit is clean across every run, the cycles tile
  the device exactly once in order, and peak buffer memory is identical for a 65-chunk run and
  a 1-chunk run (2 × I/O size in both).
- **added — a failed read leaves the device untouched.** Asserted four ways, because "the
  device is unchanged" is also true of a clean run and would pass whether or not the guard
  exists: no write was attempted at that offset, the audit sees no write-after-failed-read, the
  range still holds its own pattern, and the bytes are missing from the accounting.

**Four checks were shown capable of failing before their passing was believed**, per the
project's standing rule:

1. `ChunkCycleAuditTests` produces **every** violation the audit can report from hand-built
   sequences — including `writeAfterFailedRead` (the sixth hazard) and
   `chunkOpenedWhilePreviousInFlight` (NFR-REL-4 itself) — with no device and no engine
   involved, which is only possible because the checker is a pure function of
   `[DeviceOperation]`. Four further tests assert it does **not** flag legitimate irregularity
   (a failed read, a failed write, a failed verify), because a checker that did would make
   every fault-injection test fail for the wrong reason and be trusted anyway for being strict.
2. `aMisdirectedWriteIsDetectedByTheSameAssertion` runs the cycle through a device that writes
   one block late; the bit-for-bit comparison must and does fail. Without it, a green
   non-destructiveness result is indistinguishable from a comparison that cannot fail.
3. `everyBlockHoldsItsOwnPatternAndNoTwoBlocksAreAlike` checks the *test data* can reveal a
   wrong-place write, rather than trusting that a PRNG produced distinct blocks.
4. **`theInMemoryDeviceIsItselfFlaggedAsCached` — the one with nothing rigged at all.** An
   `InMemoryBlockDevice` read is a `memcpy`, so a run against it genuinely *is* answered from
   RAM, and FR-TEST-9's falsifier says so under the **real** monotonic clock with no fake
   timings and no constructed rate. That is the strongest available evidence that the falsifier
   works, and it arrived as a consequence of the design rather than being contrived: tests that
   need the verdict to stay `bypassed` have to supply a slow clock, which is what the injected
   `MonotonicClock` is for.

**A finding worth carrying to Step 10.** The misdirected-write canary also demonstrates that a
wrong-place write is *not* reliably caught by the verify — the verify compares what was read at
the intended offset, so damage done elsewhere is only visible to a whole-device comparison.
That is precisely why gate item 5's evidence is a per-1-GiB digest vector over the whole device
and not the run's own "0 bad blocks" result. A run can report clean and still have moved data.

### Helper side and tooling authored (2026-08-02) — still nothing written to any drive

| Authored | State |
|---|---|
| `Shared/TesterControl.swift` | protocol **v6**: `runRetentionCycle`, plus `maximumCycleBytesPerCall` (1 GiB), `permittedIOSizes`, `defaultIOSizeBytes` |
| `Helper/RunCoordinator.swift` | new; validates, allocates, seeds FR-TEST-9, runs, logs. Auto-joined the helper target — no GUI action needed |
| `Helper/main.swift` | the v6 method; `HelperActivity.beginRun/endRun`; `releaseDevice` now refuses mid-cycle |
| `tools/media-digest/main.swift` | new; SHA-256 per window + whole-device, `O_RDONLY`, nothing unmounted |
| `tools/mount-guard-client/main.swift` | `version`, `wait:<path>`, `cycle:<start>:<count>[:<ioSize>]`; 300 s timeout for the cycle |
| `scripts/retention-cycle-check.sh` | new — the hardware gate |
| `scripts/ioctl-constants-check.sh` | request 71; **11/11**, and the SDK confirms `DKIOCGETMAXBYTECOUNTWRITE = 0x40086447` |
| `scripts/test.sh` | parallel testing disabled — see below |

**389 tests, 0 failures.** The count fell from 390 because `RunMemoryTests` was deleted, not because
anything regressed — see defect 1.

#### Three defects found in this step's own work, all before hardware

**1. The engine mutated process-global test instrumentation.** `run()` called
`ChunkBuffers.resetPeakAllocatedBytes()` so it could report a per-run high-water mark. That is a
process-global counter, and resetting it clobbered the baseline of
`ChunkBuffersInstrumentationTests` — a *Step 7* suite, running concurrently, which failed.
Production code has no business resetting instrumentation other code is using, and the figure it
bought was the weaker half of NFR-PERF-1 anyway. `RunSummary.peakBufferBytes` became
`bufferBytesHeld` (`buffers.totalAllocatedBytes`): exact, uncontaminated, and unable to vary with
capacity because capacity is not one of `ChunkBuffers`' inputs. `RunMemoryTests` was deleted with
it — its claim is Step 7's `reusingOnePairAcrossManyChunksDoesNotAccumulate`, which is the right
home for it.

**2. Parallel testing made global-counter assertions unsound — `scripts/test.sh` now disables it.**
Fixing defect 1 stopped the *reliable* clobber, and three consecutive full runs then passed. Three
greens are not evidence: Step 8's cycle tests allocate `ChunkBuffers` in forty-odd tests, and no
assertion on a global counter can be sound while another test may be mutating it. Step 7 saw this
exact case coming and wrote the instruction into the suite — *"if a future test does [allocate
`ChunkBuffers`], it must either live here or the assertions below must be loosened"* — and Step 8
is when the condition arrived.

Loosening was rejected: **there is no assertion on a global counter that is immune to concurrent
mutation**, so every loosening on offer traded away the thing being checked. Serialising was
measured instead — **9.7 s parallel, 18.8 s serialised** — and taken. Nine seconds removes a whole
class of results that depend on scheduling, and a green that depends on scheduling is not evidence.
Verified rather than assumed: the suite runs in a **single** process either way (so this is Swift
Testing's in-process parallelism, not xcodebuild workers), and disabling it doubles the wall clock.

**3. The gate script planned a run at block −893,534,208.** Caught by a dry run that aborts at the
confirmation prompt, before anything was unmounted or written. `od -An -N8 -tu8 < /dev/urandom`
yields a 64-bit unsigned value, and **bash arithmetic is signed 64-bit** — so any draw above 2⁶³
became negative, and `RAW % POSITIONS` then produced a negative start block. Fixed to 32 bits
(`-N4 -tu4`), whose modulo bias over ~238,000 positions is ~5×10⁻⁵ and irrelevant to spreading NAND
wear. `$RANDOM` was not an option either: 15 bits would confine every run to the first 32,768 chunk
positions.

Three explicit placement assertions were added with the fix and were then **shown to fire**: a
start past the legal maximum is refused, a misaligned start is refused, and the latest legal start
(1,951,424,512) is accepted and ends at block 1,953,520,639 — 4,528 blocks of margin, matching the
computation exactly. The arithmetic that produced a negative block number looked perfectly
reasonable in the source; only running it revealed it.

#### A gap in the project's "zero warnings" claim, found and closed

The clean-build discipline this project has followed since Step 4 runs `./scripts/build.sh` after
wiping DerivedData. **`build.sh` does not compile the test target** — only `test.sh` does — so
"zero warnings from clean Debug *and* Release builds" has never covered test sources. A clean
`test.sh` run on 2026-08-02 surfaced three warnings that had been present since Step 7, all in
`FileDescriptorBlockDeviceTests.swift` (lines 71, 295, 358): `variable 'source' was never mutated;
consider changing to 'let' constant`. Fixed.

They were invisible for the usual reason — incremental builds do not re-emit warnings — but the
deeper cause is that the *scope* of the check was narrower than the claim made of it. The
zero-warning check now means: **wipe DerivedData, then `build.sh Debug`, `build.sh Release`, and
`test.sh`.** Two of those three were already being done.

#### First hardware run of the gate — 2026-08-02, aborted at the pre-flight. **Nothing was written.**

The gate stopped exactly where it was designed to stop: at the measurement its own design rests
on, before either fingerprint and long before the cycle. Four checks passed on real hardware
first, which is worth recording because they were not certain either:

| Check | Result |
|---|---|
| the live daemon speaks protocol v6 | PASS |
| `disk4` unmounted | PASS |
| helper acquired `disk4` (claim + `O_EXLOCK`) | PASS |
| pre-flight: second process reads `/dev/rdisk4` while the helper holds `O_EXLOCK` | **FAIL — `errno 13`** |
| mount state restored on exit | PASS (`Test_Drive` remounted) |

Placement drawn: block 1,845,444,608 — chunk-aligned, well clear of both ends.

**`errno 13` is `EACCES`, not `EBUSY`, and the difference is the whole finding.** `/dev/rdisk4`
is `crw-r----- root:operator` (mode `0o20640`, measured in Step 7 and recorded in
`CacheBypassCheck`), and `media-digest` was being run as the ordinary user — who is neither root
nor in `operator`. The open was refused by plain Unix permissions and **never reached the
exclusive lock at all**. So the question the pre-flight exists to answer is still open, and the
run proved nothing about exclusivity in either direction.

**Two defects, and the second is the instructive one.**

1. The script ran the fingerprint unprivileged. Fixed: it now primes `sudo` **once, up front**,
   before anything is unmounted, and keeps the credential alive with a background refresher —
   the two fingerprint passes are ~35 minutes apart on a 1 TB drive, far beyond sudo's ~5-minute
   cache, and a password prompt appearing silently mid-run while the helper holds an exclusive
   claim is a trap rather than a safeguard. `sudo` from Terminal also supplies the Full Disk
   Access grant the raw open needs (NFR-INST-4) by inheriting Terminal's.

2. **The check reported a conclusion its evidence did not support.** It said *"a second process
   cannot read `/dev/rdisk4` while the helper holds `O_EXLOCK`"* — a statement about
   exclusivity — when all it had observed was that *an* open failed. That is the same conflation
   Step 6 spent a measurement session untangling: there, **both** of FR-SAFE-4's causes surfaced
   as an identical `EBUSY`, and only an independent fact could separate them. A check that
   converts any failure into its favourite explanation is worse than no check, because it is
   believed.

   The pre-flight now classifies the `errno` and says what was actually learned:

   | errno | what it means | what to do |
   |---|---|---|
   | success | the digest ordering this gate uses is sound | proceed |
   | 16 `EBUSY` | the `O_EXLOCK` genuinely does block a second reader | the fingerprints would have to be taken by the **helper**, through its own descriptor |
   | 13 `EACCES` | not root, not in `operator` — never reached the lock | a fault in the script, not a finding |
   | 1 `EPERM` | TCC refused; Terminal needs Full Disk Access | grant it; root alone is not sufficient |

**Still true after this run: nothing has ever been written to any drive.** The gate's
simulation-first ordering did its job — it refused to proceed on a check it could not honestly
pass, at the cost of one unmount and a remount.

#### Second run — MEASURED: `O_EXLOCK` blocks a plain `O_RDONLY` open (2026-08-02)

Re-run with the fingerprint under `sudo`, so the process was root **and** carried Terminal's Full
Disk Access grant. The only thing left in the way was the lock, and it refused:

```
open=failed
open.errno=16
open.errnoText=Resource busy
```

**This is a new measured fact, and it is not in the 2026-07-30 exclusivity matrix.** That session
established `O_EXLOCK` vs `O_EXLOCK` (second one fails `EBUSY`) and plain `O_RDWR` vs plain
`O_RDWR` (both succeed). It never tested a **held `O_EXLOCK` against an opener requesting no lock
at all** — and the answer turns out to be that the lock excludes it too. Added to the matrix:

| Question | Answer |
|---|---|
| `open(rdiskN, O_RDONLY)`, **no lock requested**, while another process holds `O_EXLOCK` | **fails `EBUSY`** — measured 2026-08-02 |

`disk4` was unmounted, acquired, and remounted cleanly around the failure. Placement drawn:
block 1,340,219,392. **Nothing was written.**

**Consequence: D3's digest ordering is impossible as designed, and BUILD-PLAN gate item 5 is
wrong as written.** It says both fingerprints are taken "by a separate process while the helper
still holds the claim". No separate process can read the device at all while the claim is held,
because the claim is accompanied by the exclusive open. Both digests must therefore come from
**the helper, through its own descriptor** — which is the branch the pre-flight's `EBUSY` case was
written to name, and the reason the pre-flight was built before the gate design was committed to.

That the pre-flight existed at all is the Step 7 lesson holding: `tools/media-digest` was written
and its canary proven *before* it was relied upon, and the one fact the design rested on was
measured rather than assumed. Assuming it would have produced a gate that failed at the "after"
fingerprint, ~40 minutes into a run, immediately after the first write this project has ever made
to real media — with no way to tell a digest that could not be taken from a device that had been
changed.

#### The redesign the `EBUSY` finding forced — protocol **v7** (2026-08-02, user decisions)

Two decisions taken:

- **The fingerprints move into the helper**, as a *bounded* `digestRange(startBlock:blockCount:)`
  capped by the same `TesterProtocol.maximumBytesPerCall` the cycle uses. A whole device is one
  call per gibibyte — ~932 of them for `disk4`, ~2.2 s each. Rejected: a single
  `digestWholeDevice()` call, because it would be a ~35-minute uncancellable privileged
  operation, exactly what the cap on `runRetentionCycle` exists to prevent. Rejected: taking the
  fingerprints outside the claim, because DiskArbitration remounts within ~4 ms of release and
  mounting an exFAT volume can dirty it — that would need its own measurement first.
- **No independence cross-check** against a separate reader. Recorded as a known residual: both
  fingerprints now come from the helper's own descriptor, so a fault in *that descriptor's*
  addressing would be invisible to them. What stands against it is indirect — geometry
  cross-checked against `diskutil` (`geometry-check.sh` 9/9) and addressing verified past 2³² on
  `disk8` (`large-address-check.sh` 10/10).

**A vacuity risk the second decision did not cover, and how it was closed.** With both
fingerprints taken by one process and nothing checking the digest against a known value, a digest
function that returned a **constant** would make `before == after` pass unconditionally — a check
that cannot fail, which is the defect this project has now caught four times in other guises. It
is a different question from the addressing one, and it is closed **in simulation, at no hardware
cost**: `Core/DeviceDigest.swift` is a pure function over `RawBlockDevice`, unit-tested against
known SHA-256 vectors and against a single flipped bit. The gate adds a cheap corroboration on
hardware too — a real device must not fingerprint to one repeated value across its windows.

`DeviceDigestTests` pins the digest against **externally computed** values — every constant came
from Python's `hashlib` over the identical byte sequence, never from running the Swift code and
recording what it said, which would pin the implementation to itself and prove nothing. Four
sequences at both supported geometries agree, and the flipped-bit case asserts not merely that
the digest *changed* but that it changed to the value an outside tool computes for the corrupted
bytes. Also pinned: the digest is independent of read size (a digest that varied with it would
produce spurious before/after differences, which is the only comparison it is used for), the
exact final block is legal, and a read failure is reported with its offset.

`Core/DeviceDigest.swift` adds **`CryptoKit`** to Core's import list, which was Foundation-only.
Deliberate: CryptoKit is unprivileged, hardware-free, deterministic and testable off-device, so it
weakens none of the reasons that rule exists. The rule is about keeping the algorithm pure and
provable, and hand-rolling SHA-256 to honour its letter would have been a far worse trade.

**The redesign made the gate script simpler, not more complex.** The helper doing the work on one
connection removed the sentinel files, the background client process, *and* `sudo` entirely — the
only reason `sudo` was ever needed was an external reader that turns out to be impossible.
`tools/media-digest` is no longer in the gate's path; it is kept because it is the tool that made
the `EBUSY` measurement (`--probe`) and because its file-based canary is what proved a per-window
digest detects and localises a one-byte change.

#### Third run — THE FIRST WRITE TO REAL MEDIA. 15/15, and it proved almost nothing (2026-08-02)

`./scripts/retention-cycle-check.sh disk4 --quick`, protocol v7, placement block 86,319,104.
Every check passed. **Gate item 5 is not discharged, and the 15/15 is misleading.**

**What the run genuinely established** — real, and not nothing:

| | |
|---|---|
| the live daemon speaks **v7**; acquire and release on real hardware | PASS |
| **256 chunks — 255 full + 1 short** — executed on real media | PASS |
| 4 MiB `pwrite`s completed with **no short transfers**; 0 failed ranges | PASS |
| FR-TEST-9's verdict **survived real I/O**: `bypassed` | PASS |
| fastest read **500,242,470 B/s** — transport-plausible, not RAM-plausible | PASS |
| buffers **8,388,608 B = 2 × I/O size** in the daemon | PASS |
| mount state restored | PASS |

The **mechanism** ran end to end on hardware. That is the first time the write path, the short
final chunk and the per-chunk guard have executed against a real device.

**What it did not establish, and why.** The three window fingerprints were:

```
window 0  84221952  2097152  49bc20df…
window 1  86319104  2097152  49bc20df…     <- the window containing the run
window 2  88416256  2096128  a2986c1d…
```

Computed independently afterwards: `sha256(bytes(1073741824))` **is** `49bc20df…`, and
`sha256(bytes(1073217536))` **is** `a2986c1d…`. **All three windows are entirely zeros.** The
cycle read 1 GiB of zeros, wrote zeros back, and verified zeros against zeros. Writing zeros over
zeros is non-destructive however wrongly the code addresses the device — a write landing at the
wrong offset anywhere inside that region would be invisible to the verify *and* to the
fingerprints. `disk4` is **1% used**, so a randomly placed run lands on unwritten space almost
every time.

**The defect is in the gate, not the engine — and it is the project's signature failure again.**
The check that was supposed to catch this read:

> `PASS  the fingerprints are content-dependent (2 distinct values across 3 windows)`

**It was parsing the wrong field.** The digest file's format is
`window <index> <startBlock> <blocks> <sha256>`, and the check ran `awk '{print $4}'` — which is
the **block count**, not the fingerprint. A 3-window `--quick` run always has exactly two distinct
block counts (2,097,152 for the full windows, 2,096,128 for the short one), so it reported "2
distinct values" **on any drive, empty or full, whatever the content**. It never examined a
fingerprint at all.

*(Corrected 2026-08-02. This was first recorded as "the all-zero digests differed by length",
which was wrong — that explanation was inferred from the output rather than from the code, and
the code was not doing what it appeared to be doing. The conclusion was unaffected: the check was
vacuous either way. The mechanism was not, and a wrong mechanism in the log is how the next
person mis-fixes it.)*

The weakness was also anticipated and then not acted on: the source comment said "an all-zero
region legitimately repeats", and the check was shipped anyway rather than being made to test the
property that mattered. A comment acknowledging a hole is not a check; it is a note explaining
why the check does not work.

The replacement reads its input from a different, unambiguous source — the `[digest] SHA256=`
lines the helper emits per probed chunk — rather than positionally from a file whose column
layout has to be remembered correctly.

**Replaced with the property that actually matters.** Before the cycle writes a byte, three whole
chunks from *inside* the tested range are fingerprinted and must be pairwise **distinct**. If they
are not, the region is uniform, no misdirected write within it could ever be detected, and the
gate **fails** rather than reporting a pass. Cost: 12 MiB of reads.

Plus an early warning before anything is unmounted, so a doomed run can be avoided rather than
merely failed afterwards: the script reads the volume's usage and says so when it is under 25%
full. Verified firing — `disk4 is only 1% used`.

**The precondition this exposed, which belongs with the test hardware.** `disk4` must hold **real
data**, not empty space, for any placement-random gate to mean anything. One-time fix: fill the
volume with high-entropy data and keep the file, because deleting it may let the drive discard
the blocks.

#### Fourth run — the mechanism proven over REAL DATA (2026-08-02)

`Test_Drive` filled with ~1 TB of `/dev/urandom` (file kept, so the blocks stay written), then
`./scripts/retention-cycle-check.sh disk4 --quick`, placement block 210,157,568. **15 checks,
0 failures — and this time the content is real.**

The check that decides whether the run means anything now has something to say:

```
PASS  the tested region holds distinguishable data (3 sampled chunks, 3 distinct fingerprints)
   block 210,157,568  8a624eb4…
   block 211,197,952  43852cb9…
   block 212,238,336  4393acef…
```

All three probes lie inside the run, and all three differ. Verified independently afterwards:
none of the three window fingerprints is the all-zero digest for its length, and all three
windows differ from one another.

| | before | after |
|---|---|---|
| window @208,060,416 (2,097,152 blocks) | `18531d1f…` | `18531d1f…` |
| window @210,157,568 (2,097,152 blocks) — **contains the run** | `52ea3b71…` | `52ea3b71…` |
| window @212,254,720 (2,096,128 blocks) | `3ecb14b4…` | `3ecb14b4…` |

Byte-identical. The cycle read 1,073,217,536 bytes of high-entropy data, wrote the same bytes
back, verified each chunk against its re-read, and left the region unchanged — with
`FASTEST_BYTES_PER_SECOND=504,229,135`, `CACHE_BYPASS=1`, `BUFFER_BYTES=8,388,608` and 256 chunks
of which the last is short.

**What is now discharged, and what is not.** The read → write-back → read-verify cycle is proven
non-destructive over real data on real hardware, at the offsets a real run would use, including
the short-final-chunk path. **Gate item 5 is still not fully discharged**: `--quick` fingerprinted
only 6,290,432 blocks (3 GiB) around the run, so a write that landed outside that window would not
have been seen — and detecting exactly that is the reason the fingerprint exists. The full run,
fingerprinting all 1,953,525,168 blocks either side of the cycle, is what closes it.

#### A tooling defect the first long run exposed — progress that never arrived

`mount-guard-client` set `setvbuf(stdout, nil, _IOLBF, 0)`, which does not reliably flush per
line when stdout is a **pipe** — and the gate script always pipes it through `tee`. During the
first full-device fingerprint pass, none of the per-50-window progress lines reached the
terminal: ~18 lines of ~40 bytes never fill a 4 KB buffer. Changed to `_IONBF`.

Invisible until now because every previous run finished in about ten seconds, so all output
arrived at once. The same shape as the warnings gotcha — a defect that only appears at a scale
nothing had yet reached.

The unified log was unaffected and turned out to be the better progress indicator anyway: the
helper emits one `digest for … blocks X–Y … = <hash>` line per window, so
`log show … | grep -c "digest for"` gives an exact window count against the 932 per pass, with no
buffering in the way.

#### Helper CPU — an observation from the full run, and what it does and does not mean

**Observed by the user during the full-device gate: the helper at 36–39% of one core on an M4
Mac Mini, at ~500 MB/s.**

**That figure is the gate's fingerprint, not the product.** `Core/DeviceDigest.sha256` exists so
the hardware gate can prove the cycle moved nothing; it is instrumentation, and nothing in the
FR/NFR set makes the shipping tool hash anything. The observation is of code that will never run
during a user's test.

**But the extrapolation is sound and worth having.** Linear in data rate, SHA-256 reaches one
full core at roughly **1.3 GB/s** on this machine — within reach of a USB4 enclosure. So the
*gate* stops being I/O-bound on faster hardware, which matters for how long a full fingerprint
pass takes on someone else's setup.

**What the product actually costs per chunk is a `memcmp`** — the block-by-block walk is paid only
on a mismatch — expected to be order 40–80 µs against ~25 ms of I/O per chunk at 500 MB/s, so a
fraction of a percent. **Expected, not measured**, and recorded as such: an unmeasured performance
claim is exactly the sort of thing this project has been caught by, and NFR-PERF-3
("device-bound, not host-bound … overhead shall remain negligible") is the requirement that says
it must not be assumed.

**Consequences recorded rather than acted on now**, because Step 9 owns metrics and NFR-PERF-3:

- **BUILD-PLAN Step 9 gains detailed step 5a and a gate item**: measure helper CPU as a
  percentage of one core against measured MB/s, and show the run is device-bound.
- **Carried to Step 16**: *if* that measurement shows the host becoming the limit at a transport
  speed the product plausibly meets, it belongs in the release notes. Conditional on the number,
  not assumed from this one — per the user's own framing, *"if the final product shows similar
  CPU consumption at a given data rate"*.

#### `tools/media-digest` was proven capable of failing before hardware use

Digest a 5 MB file, flip **one byte** at offset 3,000,000, digest again:

| | before | after |
|---|---|---|
| window 0, 1, 3, 4 | unchanged | unchanged |
| **window 2** (2,097,152–3,145,727) | `3061f141…` | **`15dc9412…`** |
| whole | `b78ca110…` | **`dfec406c…`** |

The single flipped byte changed exactly the window containing it, and nothing else. So the tool
detects a change *and* localises it — the reason the gate uses a per-window vector rather than one
scalar, at identical I/O cost.

**Simulation-proof details that are easy to get wrong, and are decided:**
- The in-memory device is filled from a **seeded** PRNG stream keyed by **block index**, so
  "block *k* contains block *k*'s pattern" is checkable and a mis-addressed write is detectable
  by content. Uniform random is not enough; an all-zero or repeating fill would let a
  wrong-offset write pass, which is the same family of vacuity as hazard 3.
- The non-destructiveness assertion finds the **first differing index** and asserts on that,
  never `#expect(before == after)` on a multi-MiB array — Swift Testing renders both operands.
  Same family as Step 7's `#expect` literal-promotion trap.

---
