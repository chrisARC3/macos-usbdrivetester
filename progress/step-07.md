# Step 7 — Raw I/O core

*Archived from `PROGRESS.md` on 2026-08-11, when the log was split. Nothing here has been
edited — statements carry the dates on which they were true.*

**Do not read this as current.** What still binds today's work is in
[CONSTRAINTS.md](../CONSTRAINTS.md); what is in progress is in [PROGRESS.md](../PROGRESS.md).
This file is here for the one question the other two cannot answer: *why was it done that way?*

---

## Step 7 — COMPLETE (2026-08-02)

Every gate item discharged, 0 failures on hardware. Summary of what the step delivered and
what it cost.

**Delivered.** The real `RawBlockDevice` over the descriptor Step 6 already holds — uncached,
block-aligned `pread`/`pwrite` with short-transfer resumption and `errno` diagnosis; geometry
from the `DKIOC*` ioctls, reconciled against the helper's own IOKit reading and preferred over
it; a chunk plan that no longer scales with capacity; a buffer pair that *cannot* scale
because capacity is not one of its inputs; a run-start cache-bypass check that verifies
structurally and falsifies against a ceiling derived from the negotiated USB link speed; and
protocol v5.

**Requirements changed by this step.** **FR-TEST-9 added (M, 2026-08-02)** — run-start
verification that reads are not served from the host buffer cache, reported to the user and in
the run report, qualifying the verify result rather than preventing the run. Proposed by the
user in response to the finding that `fcntl(F_NOCACHE)`'s return value proves nothing.

**BUILD-PLAN amended in five places**, all 2026-08-02: 7.1 (Step 7 opens nothing — Step 6
already did, and a second descriptor would remount the volume on close); 7.3 (reconcile against
the *helper's* IOKit reading, not the app's Step 5 discovery, which would re-cross the trust
boundary Step 6 closed); 7.6 and gate item 3 (bounded memory binds every run-state structure,
not only the buffers); gate item 4 (a checked `fcntl` is not sufficient evidence); "Test
hardware" (`disk4` only, `disk8` by prior agreement per step).

**The measurement that changed the design.** `scripts/nocache-calibration.sh` was built as a
prerequisite rather than as polish, and it killed the mechanism FR-TEST-9 was going to use.
Re-read timing **cannot discriminate** on a raw device: with `F_NOCACHE` unset, repeated reads
of one region took 12,295 then ~8,800 µs; with it set, ~8,900 µs throughout — while a 4 MiB
copy from RAM takes **58 µs**, so a real cache hit would be ~150× faster than either. The cause
is that `/dev/rdisk4` is the **character** device and the buffer cache belongs to the block
node, so there was never anything to suppress. Shipping the timing check would have produced a
test that cannot fail — the precise defect FR-TEST-9 exists to prevent, reproduced inside
FR-TEST-9.

**The trap that nearly shipped.** Deriving the falsifier's ceiling from the USB link speed
required reading the IORegistry's `Device Speed`, whose enum **is not the one the SDK
documents**: `IOUSBHostFamilyDefinitions.h` describes a different property. Ten attached
devices resolved the question — a connected keyboard reports 0, which under the SDK enum means
"no device connected". Being wrong in the slow direction would have set the ceiling at
~0.2 MB/s and flagged every read of every run as cached.

**Defects found in this step's own work, all before they reached hardware:** a probe that would
have raced DiskArbitration's remount by opening and closing three times; a write-path guard
that fired on its own documentation and would have had to be silenced to run; a guard that
reported "assertion deleted" when it simply could not find the file; and a `#expect` comparison
whose compound integer literal was silently not promoted to `Double`.

**The thread running through all of it.** Every one was caught by insisting a check be shown to
*fail* before its passing was believed — the calibration probe written before the classifier,
the canary in the constants guard, the corrupted-copy run, the assertion that a temp file
accepts the misaligned read the device refuses. The project's standing lesson held again, in a
new form: it is not enough to avoid substituting for the real thing; a check must also be
capable of failing, or it is a substitute for a test.

**Carried into Step 8.**

- `AcquiredDevice.blockDevice()` vends a `FileDescriptorBlockDevice` on the held descriptor,
  using the authoritative geometry. The write path takes the `AcquiredDevice`, so NFR-REL-3's
  compile-time half still holds, and `WritePrecondition.check(_:writingTo:)` is the runtime half.
- `RetentionTestEngine.chunks()` is the lazy plan a run iterates. `chunkPlan()` remains for
  tests and diagnostics only — it is the 200 MiB path for a 22 TB device.
- `ChunkBuffers` is the two-buffer pair; `original` is the only copy of the user's data during
  the write, which is what bounds NFR-REL-4's in-flight window to one chunk.
- FR-TEST-9's verdict is on `AcquiredDevice.cacheBypass`; Step 8 seeds a
  `CacheBypassAssessment` from it plus the link speed and feeds per-chunk throughput in.
- **Step 8 writes the first byte to real media.** NFR-REL-1 requires non-destructiveness proven
  in simulation *before* that, and Step 8's own gate is where that proof lives. Nothing in
  Step 7 wrote to `disk4`.

**NFR-COMPAT-6 — DISCHARGED ON HARDWARE (2026-08-02), on user instruction, before Step 8.**
Carried out of the main gate because `disk4` is 1,953,525,168 blocks — below 2³² — where a
bridge truncating its block count to 32 bits would be invisible, and the failure is silent: the
tool would test the first portion of a larger drive and report a clean pass.

`./scripts/large-address-check.sh disk8` closes it, **10 PASS / 0 failures**:

| Check | Result |
|---|---|
| `DKIOCGETBLOCKCOUNT` | **42,970,644,479** — matches `diskutil`, and is *not* the 20,971,519 (10.7 GB) a 32-bit truncation would report |
| read at block 0 | ok |
| read at block 4,294,967,295 (last 32-bit-addressable) | ok |
| read at block **4,294,967,296** (first needing >32 bits) | ok |
| read at block 4,295,967,296 | ok |
| read at block 42,970,644,478 (the last block) | ok |
| read one block **past** the end | **correctly refused** (0 bytes) |
| last block vs its 32-bit-wrapped twin (20,971,518) | **distinct**, and neither all-zero |

The decisive pair is the last two rows but one: succeeding at the final block *and* being
refused one block past it brackets the device exactly, which is only possible if 64-bit
addressing holds end to end — a truncated size or wrapped addressing would have made the
past-the-end read land on a valid low block and succeed. The aliasing check then confirmed it
directly, and did **not** hit the all-zeroes ambiguity it was written to tolerate: both blocks
held real, different data.

**How it was done safely, since `disk8` is not the expendable scratch device.** It carries a
live HFS volume, `/Volumes/Backup`. So `tools/large-address-probe` departs from
`DeviceClaim`'s flags deliberately and opens **`O_RDONLY`** with no `O_EXLOCK`: the descriptor
physically cannot write, nothing had to be unmounted, and with no exclusive lock there was no
release to trigger DiskArbitration's remount. The volume stayed mounted throughout and was
verified still mounted afterwards. The fidelity cost is acceptable because of what was asked —
whether the ioctls report a 64-bit count and whether `pread` reaches a block above 2³² are
properties of the device, bridge and kernel, not of the open mode.

`scripts/large-address-check.sh` **refuses `disk4`** for being at or below 2³², so it cannot be
run against hardware that would pass it vacuously.

**State at completion.** Protocol v5. **323 tests, 0 failures. Zero warnings from clean Debug
and clean Release builds**, DerivedData wiped before each. Release bundle re-audited and
confirmed to embed the *Release* helper (identical byte-for-byte with signatures stripped).
`./scripts/geometry-check.sh disk4` passes 9/9. `./scripts/ioctl-constants-check.sh` passes
9/9. `./scripts/usb-speed-check.sh` passes 3/3.

---

## Step 7 — Raw I/O core — scoping and authoring log

**AI-5 / satisfies FR-TEST-2/5/6; FR-DEV-5; NFR-PERF-1/2, NFR-COMPAT-5/6.**
**Helper-side only** (FR-ARCH-6).

Recorded here so a cold start has the state without re-deriving it.

### State this step begins from

- **Steps 1–6 complete.** Step 6 committed at `81e7485`; `git` clean on `main`.
- **Protocol v4.** `ping`, `protocolVersion`, `validateRunParameters`,
  `prepareForShutdown`, `checkDeviceReadiness`, `acquireDevice`, `releaseDevice`.
- **247 test cases** (238 `@Test` declarations), 0 failures, zero warnings from clean
  Debug **and** Release builds.
- **Helper installed from `/Applications` and registered**, with **Full Disk Access
  granted** to `USBDriveTester`. Re-registering no longer prompts for approval on this
  machine (stable `BTM uuid`) — a clean Mac still will.
- `./scripts/claim-contention-test.sh disk4` passes 12/12.

### What Step 6 hands over

- **`AcquiredDevice`** (`…Helper/DeviceClaim.swift`) — constructible only by a successful
  `DeviceClaim.acquire(_:)`. Carries:
  - `fileDescriptor` — the raw node **already open** `O_RDWR | O_EXLOCK | O_NONBLOCK`.
    Step 7 adds `F_NOCACHE`, `F_GLOBAL_NOCACHE` and the geometry ioctls to *this* fd; it
    must not open its own.
  - `geometry: EligibleDevice` — IOKit's `sizeBytes` and `logicalBlockSize`, explicitly
    **provisional**. BUILD-PLAN Step 7.3 says to reconcile and prefer the ioctl values.
    Already logged at acquire time (`1000204886016 bytes in 512-byte blocks` for `disk4`),
    so the two can be compared directly in the log.
  - `grant: DeviceAccessGrant` — recomputed, not stored, so it reads incomplete after
    `release()`.
- **`WritePrecondition.check(_:writingTo:)`** (Core) — the NFR-REL-3 runtime guard. Step 8's
  write path calls it; Step 7 need only keep the descriptor honest.
- **`RunParameterValidator`** (Core, Step 3) — alignment and range, overflow-checked. From
  Step 7 it is fed ioctl-derived geometry instead of caller-supplied.
- **`RetentionTestEngine.chunkPlan()`** (Core, Step 2) — the exact-remainder final chunk,
  already tested for 512 B and 4096 B.

### Hazards that will bite Step 7 specifically

1. **The helper needs Full Disk Access** (NFR-INST-4) or the raw open fails `EPERM`. Root
   is not sufficient. Granted on this machine; a clean Mac is not.
2. **Opening and closing the raw device outside a held acquire remounts the volume within
   milliseconds.** Measured: releasing an `O_EXLOCK` open makes DiskArbitration re-probe and
   auto-mount ~4 ms later. Any Step 7 probe, geometry check or experiment that opens the
   node on its own will undo the user's unmount. Use the descriptor `AcquiredDevice`
   already holds.
3. **Disk images are not a test target** — discovery excludes them by design. All
   real-hardware I/O is `disk4`, whose contents are expendable. `disk6` holds the source
   tree and must never be tested.
4. **Raw devices reject misaligned offsets/lengths with `EINVAL`.** Alignment is the
   device's contract, not a style preference.
5. **`F_NOCACHE` is what makes Step 8's verify read meaningful.** Reading through a cached
   path would let the buffer cache satisfy the verify and make the whole test vacuous.

### The gate (from BUILD-PLAN, amended 2026-08-01)

- [x] Against `disk4`, geometry reads correctly and matches `diskutil info`.
      **`./scripts/geometry-check.sh disk4`, 0 failures (2026-08-02):** 512 / 1,953,525,168 /
      1,000,204,886,016 from the ioctls on the held descriptor, matching `diskutil` on all
      three, and matching the helper's own IOKit reading.
- [x] Chunk plan correct for awkward sizes, both 512 B and 4096 B, via unit tests — including
      a block count that is **not** a multiple of `blocksPerChunk`. `RetentionTestEngineTests`
      (7 cases, unchanged from Step 2) plus `ChunkPlanTests` (12), which adds `disk4`'s and
      `disk8`'s **real** geometries and full-traversal tiling over 5,245,440 chunks.
- [x] Peak buffer memory ≈ 2×`ioSize` regardless of device size (NFR-PERF-1) — **and no
      other run-state structure scales with capacity either** (NFR-PERF-2; amended
      2026-08-02, see decision 4 below). `ChunkBuffers` cannot scale because capacity is not
      one of its inputs; the chunk plan is now a lazily-computed `Sequence`.
- [x] `F_NOCACHE` / `F_GLOBAL_NOCACHE` set — both `fcntl` results checked, acquire fails if
      either is non-zero — **and** the FR-TEST-9 mechanism built on the calibrated finding
      that re-read timing cannot discriminate. Hardware: `CACHE_BYPASS=1` (bypassed).

- [x] **NFR-COMPAT-6, added to this gate 2026-08-02 by user instruction** — not discharged by
      anything run on `disk4`, which is below 2³². `./scripts/large-address-check.sh disk8`
      passes 10/10: 42,970,644,479 blocks reported, reads succeed at and beyond the boundary
      and at the last block, a read one block past the end is refused, and the last block is
      not an alias of its 32-bit-wrapped twin. Read-only; `/Volumes/Backup` never unmounted.

### Facts established headlessly during scoping (2026-08-02)

Measured before any code was written, with no drive touched and nothing added to the
project. They change the file plan, so they are recorded rather than left in a transcript.

1. **`DKIOCGETBLOCKSIZE` / `DKIOCGETBLOCKCOUNT` cannot be imported into Swift.** The SDK
   is explicit: `macro 'DKIOCGETBLOCKSIZE' unavailable: structure not supported`. They are
   `_IOR(…)` macros, not plain integer `#define`s — the same class of problem as the IOKit
   registry-key `#define`s that `DeviceClaim.swift` spells out by hand.
2. **The Swift re-derivation is correct, checked against C rather than reasoned about.**
   A `_IOR` written in Swift produces `0x40046418` and `0x40086419`; compiling
   `<sys/disk.h>` in C and printing the macros produces the same two values.
3. **No C shim and no bridging header are needed.** `ioctl(fd, UInt, &value)` and
   `fcntl(fd, F_NOCACHE, 1)` both compile and link from Swift; `F_NOCACHE` (48) and
   `F_GLOBAL_NOCACHE` (55) import normally. This removes what would have been the largest
   Xcode GUI task of the step.
4. **`fcntl(fd, F_NOCACHE, 1)` returns 0 on `/dev/null`.** A zero return therefore proves
   almost nothing on its own — it is not evidence that caching was suppressed on a device.
   This is what makes the `F_NOCACHE` gate item's "verified by code path" wording weak.
5. **Geometry and chunk arithmetic for the real hardware** (`diskutil`, read-only):

   | Device | Bytes | Blocks (512 B) | Chunks @ 4 MiB | Final chunk |
   |---|---|---|---|---|
   | `disk4` — 1.0 TB | 1,000,204,886,016 | 1,953,525,168 | 238,468 | 3,504 blocks (1,794,048 B) |
   | `disk8` — 22 TB | 22,000,969,973,248 | 42,970,644,479 | 5,245,440 | 8,191 blocks (4,193,792 B) |

   Both are genuine FR-TEST-5 remainder cases, so `disk4` alone does exercise the
   exact-remainder final chunk on hardware. `MemoryLayout<Chunk>.stride` is 40 bytes and
   the page size is 16,384.

### Authoring log — the calibration probe (2026-08-02)

`tools/nocache-probe/main.swift` + `scripts/nocache-calibration.sh`. Neither is in the Xcode
project (standalone `swiftc` + shell), so no GUI work was needed. Two defects found and
fixed before either touched hardware.

**1. Open/close/open would have raced DiskArbitration.** The first draft ran each phase in
its own `open` … `close`. Measured 2026-08-01: releasing an exclusive open makes
DiskArbitration re-probe (~4 ms) and remount (~230 ms). A second open racing that can fail
`EBUSY` for reasons unrelated to caching — and the failure would have read as a caching
result. Restructured to **one descriptor for the whole probe**, which also matches what
`DeviceClaim.acquire(_:)` does and removes the race entirely.

**2. The script's write-path guard fired on its own documentation.** The guard greps the
probe's source to prove it contains no device write before handing it a raw exclusive
descriptor. It matched line 31 of the probe — the header sentence *"no `pwrite`, no `write`,
no `O_TRUNC`"* — and refused to run.

It **failed closed**, which was the right direction, and it was caught on the first real
invocation. But the guard was wrong: it could not tell code from prose, so the only way to
run at all would have been to silence it, and silencing a guard is how a guard stops
guarding. Fixed by stripping comments before matching, and by allowing `.write(`
(`FileHandle.standardError.write` is how the tool reports errors) while still rejecting a
bare `write(` or any `pwrite(`.

**A canary was added with the fix.** The guard now also asserts it still fires against a
deliberate `pwrite(fd, …)` string. Without that, a pattern matching *nothing* would report
the same `PASS` as a genuinely clean file — which is exactly the shape of the inverted
`pipefail` guard in `negative-test.sh` that could not fire for three steps.

### Authored 7/7 — the helper wiring, protocol v5 (2026-08-02)

All Step 7 code is now written. **No GUI work** — every new file is helper-only or a script,
and both auto-join.

**Tests: 321 → 323, 0 failures.** **Zero warnings from clean Debug *and* clean Release
builds**, DerivedData wiped before each (the incremental-build warnings gotcha).

| File | Change |
|---|---|
| `Helper/RawDeviceGeometry.swift` | **NEW.** The syscalls: `F_NOCACHE`/`F_GLOBAL_NOCACHE`, `fstat` for the node kind, the four `DKIOC*` ioctls, and reconciliation against the helper's own IOKit reading. |
| `Helper/DeviceClaim.swift` | `EligibleDevice` gains `usbLinkSpeed`; `eligibility(of:)` reads `Device Speed` via a new **ancestor-searching** numeric lookup; `acquire` runs step 5 (configure + geometry) and **fails closed**, releasing fd, claim and session, if geometry cannot be established; `AcquiredDevice` carries the authoritative geometry, reconciliation, uncached-I/O configuration and cache-bypass verdict, and vends a `FileDescriptorBlockDevice` on demand. |
| `Shared/TesterControl.swift` | `deviceProfile` added, `CacheBypassOutcome` wire enum added, **v4 → v5**. |
| `Helper/main.swift` | Implements `deviceProfile`; new `io` log category. |
| `tools/mount-guard-client` | `profile` command. |
| `scripts/geometry-check.sh` | **NEW.** The hardware gate. |

**Geometry is established at acquire, not on first use**, so `AcquiredDevice` carries
authoritative numbers from birth and there is no window in which a caller could address the
device using IOKit's provisional ones.

**`Device Speed` needed a new registry helper.** The existing `number(_:_:)` reads the entry
itself, but the USB properties sit several levels up past the block-storage driver and the SCSI
peripheral — the same reason `ioreg -n disk4` cannot answer this. Added `ancestorNumber`,
alongside the existing `ancestorDictionary`.

**One method, not two (user decision).** `deviceProfile` returns both geometries, the
cache-bypass verdict, the raw link-speed code and the advertised maximum read. They were
originally to be split because the cache-bypass check would perform timed reads; the
calibration made it structural and passive, so a second privileged method would have bought
nothing (NFR-SEC-3). The **raw** `Device Speed` code crosses the wire rather than an
interpreted speed, so the app is not forced to trust this build's reading of an enum no SDK
header declares.

**v5 is purely additive** — a v4 client's existing calls decode identically — but bumped
anyway, because an app needing the profile must be able to tell a helper that cannot provide it
from one that can, and a missing method surfaces as a transport failure rather than as "too
old". `cacheBypassCodesMatchTheWireEnum` pins `CacheBypassOutcome` against
`CacheBypassState.wireCode`, and asserts an unrecognised code still **qualifies** the verify
result rather than clearing it.

#### Release-bundle audit (the defect that hid for five steps)

The Step 6 finding was that Release embedded the *Debug* helper. Re-checked here rather than
assumed: the standalone Release helper and the one inside the Release app bundle have different
SHA-256 hashes but identical sizes. Stripping both signatures makes them **byte-identical**, so
the difference is re-signing at embed time and the Release bundle does embed the Release helper.
(Debug's helper is 998,064 bytes; Release's is 866,976 — they are not interchangeable by size
either.)

### Authored 6/7 — the lazy chunk plan, in `Core/RetentionTestEngine.swift` (2026-08-02)

Discharges **decision 4**. No GUI work — an existing Core file.

**Tests: 309 → 321, 0 failures.** The seven existing `RetentionTestEngineTests` cases pass
**verbatim, unmodified**, which was the constraint on this change.

`ChunkPlan` is now a `Sequence` computed on demand, storing four integers. `chunks()` is what a
run iterates; `chunkPlan()` survives unchanged, returning `Array(chunks())`, and is documented
as **for tests and diagnostics only** — it is the 9.1 MiB / 200.1 MiB path.

Built from geometry rather than from a device, which is what makes the scale cases testable at
all: `InMemoryBlockDevice` allocates its whole backing store, so it cannot represent `disk8` at
any price, while a plan over that geometry costs four integers.

**The laziness proof is a plan that could not be materialised.** `aPlanTooLargeToMaterialiseIsStillFullyUsable`
builds an 18-exabyte plan — 4,398,046,511,104 chunks, ~176 TB as an array — then reads its
first chunk, its last chunk and its size, instantly. If `ChunkPlan` ever goes back to storing
its chunks, that test fails by exhausting memory rather than by reporting a wrong value.

Both real geometries are now asserted against their measured numbers rather than invented
awkward sizes:

| Device | blocks | chunks @ 4 MiB | final chunk |
|---|---|---|---|
| `disk4` | 1,953,525,168 | 238,468 | 3,504 blocks (1,794,048 B) |
| `disk8` | 42,970,644,479 | 5,245,440 | **8,191 blocks** — one short of full |

`disk8PlanTilesTheWholeDeviceWithoutGapsOrOverlaps` walks all 5,245,440 chunks accumulating
counters only, asserting exact coverage first block to last and that **exactly one** chunk is
short. It is the slowest case in the suite at ~1 s, which is the cost of proving tiling at
22 TB scale and is worth it.

Two small things found while doing it:

- `min` inside a `Sequence` conformance resolves to `Sequence.min()` rather than the global
  function — including inside the nested `Iterator`, by enclosing-scope lookup. Qualified to
  `Swift.min`.
- `chunkCount` is `UInt64` and is computed as `full + (remainder == 0 ? 0 : 1)` rather than
  `(blockCount + blocksPerChunk - 1) / blocksPerChunk`, which overflows near `UInt64.max` —
  reachable by the 18-exabyte test above.

### Authored 5/7 — `Core/FileDescriptorBlockDevice.swift` (2026-08-02)

The real `RawBlockDevice`: block-aligned `pread`/`pwrite` over a borrowed descriptor, with
short-transfer resumption, `EINTR` retry, and `errno` mapped onto `DeviceIOError`. Alignment
and range are delegated to `RunParameterValidator` rather than restated next to the syscalls.
Ticked into `USBDriveTesterTests` and verified in `project.pbxproj` (ten Core files; app target
still has no exception set).

**Tests: 294 → 309, 0 failures** — 15 new cases.

**It borrows the descriptor and has no `deinit`, deliberately.** `AcquiredDevice` owns the fd.
Closing it here would be worse than a leak: measured 2026-08-01, releasing an exclusive open
makes DiskArbitration remount the volume ~4 ms later — silently undoing the user's unmount
*while a run is writing*. `theDescriptorSurvivesTheDeviceBeingDeallocated` is what fails if a
`deinit` is ever added as tidiness.

**`errno` is kept apart from the thrown error.** `DeviceIOError` carries what Step 8 needs to
classify a chunk failure (FR-FAIL-6) and not the `errno`, which the engine has no use for. But
"the read failed" and nothing else is the message that sent us hunting for a cable when the
answer was a checkbox (NFR-INST-4). So `lastFailure` records operation, offset, length,
bytes-transferred and `errno` for the helper to log — addressing only, never data (NFR-SEC-6).
It also distinguishes the two failures that look alike: a partial transfer with `errno == 0` is
not the same event as an outright refusal.

#### A claim I had to make more precise

The file header first said that no file-backed test can distinguish a working alignment guard
from a missing one. **That was overstated**, and the tests forced the correction. A regular
file *would* accept a misaligned read — so a test showing the request throws does prove this
guard fired, precisely because the backing store would not have objected. What no file-backed
test can show is that the guard is **necessary**: that `/dev/rdiskN` would have refused with
`EINVAL`. Correctness is testable here; necessity is a fact about hardware and is on the gate.
`aMisalignedOffsetIsRefusedEvenThoughAFileWouldAllowIt` asserts both halves — the device
refuses, and the same `pread` straight to the file succeeds.

#### NFR-COMPAT-6 gets real evidence after all

`offsetsBeyondThirtyTwoBitsAddressCorrectly` writes and reads at a **5 GiB** offset through an
actual `pread`/`pwrite` on a *sparse* temp file — past the 4.295 GB where a 32-bit byte offset
wraps, at no disk cost. It then asserts nothing landed at the wrapped offset, which is where a
truncated offset would have written.

This does not discharge the NFR-COMPAT-6 limit recorded against the gate — that limit is about
a *USB bridge* reporting a >2³² block count, which only `disk8` can show. But the 64-bit
arithmetic and syscall path through this project's own code are now exercised against real
syscalls rather than only in-memory, which is more than was previously true.

Also covered: agreement with `InMemoryBlockDevice` over a sequence of operations (the engine is
written once and runs against both, so a divergence would mean Step 8's simulation proof does
not describe the hardware path); zero-length requests matching the in-memory device exactly;
geometry validated once at construction rather than per transfer; and short-transfer detection
via a file deliberately shorter than its declared geometry.

### Authored 4/7 — `Core/ChunkBuffers.swift` (2026-08-02)

The original-read and verify-read buffer pair (BUILD-PLAN 7.6, NFR-PERF-1 and the buffer half
of NFR-PERF-2). Named for the type rather than the `IOBuffer.swift` of the scoping plan,
because it owns a *pair* and every other Core file is named for its primary type. Ticked into
`USBDriveTesterTests` and verified in `project.pbxproj` (nine Core files; app target still has
no exception set).

**Tests: 282 → 294, 0 failures** — 10 cases plus a 2-case serialised instrumentation suite.

**The guarantee is structural, not measured.** `ChunkBuffers` has **no parameter through which
a device's size could reach it** — the initialiser takes an I/O size and nothing else. So
"memory must not scale with capacity" is not a property to be checked and hoped for; it is
unrepresentable. A test states the contrast: at 4 MiB, `disk4` is 238,468 chunks and `disk8` is
5,245,440 — 22× the work — and the memory held while doing it is byte-for-byte identical.

That framing is deliberate, because the *other* half of NFR-PERF-2 was not written this way
and quietly failed: Step 2's materialised `[Chunk]` is 200.1 MiB for `disk8`. Bounded buffers
beside an unbounded plan satisfied the gate's wording and missed its intent. Item 6 fixes it.

**The case that matters most is `theTwoBuffersAreDistinctMemory`.** If `original` and `verify`
ever aliased, FR-TEST-3's cycle would compare a buffer against itself and pass for every chunk
of every drive, including a failing one — the same vacuous-pass shape FR-TEST-9 guards against
at the caching layer, arriving instead through a pointer, and nothing else in the system would
notice. Asserted both by base address and behaviourally (fill one 0xAA, the other 0x55, check
the far end of each), because an address comparison alone would still pass for views that
overlapped without sharing a base.

Also covered: page alignment (16,384 on Apple Silicon, asserted rather than assumed — a
silently unhelpful alignment produces correct results and slower I/O, which is the kind of
thing that never gets noticed); prefix views for the short final chunk, using `disk4`'s real
3,504-block and `disk8`'s 8,191-block remainders; and BUILD-PLAN 7.6's "instrument and
confirm" via process-wide `peakAllocatedBytes`, with a 1,000-chunk loop asserting the peak
never rises above one chunk's worth.

Two hygiene decisions recorded in the file: the buffers are wiped with `memset_s` before
`free` (they hold the contents of somebody's drive and this runs as root — hygiene rather
than a boundary, but cheap and once), and the type is deliberately not thread-safe, matching
`InMemoryBlockDevice` and the one-chunk-in-flight model (NFR-REL-4).

### Authored 2–3/7 — `Core/CacheBypassCheck.swift`, `Core/USBLinkSpeed.swift` (2026-08-02)

FR-TEST-9's classifier and the link-speed mapping its falsifier derives its ceiling from. Both
pure; both ticked into `USBDriveTesterTests` and verified in `project.pbxproj` (all eight Core
files present, app target still has no exception set).

**Tests: 253 → 282, 0 failures.** 29 new cases in four suites — `USBLinkSpeedTests` (7),
`DeviceNodeKindTests` (2), `CacheBypassCheckTests` (9), `CacheBypassAssessmentTests` (11).

The cases worth naming, because they are the ones that would have to fail for the check to be
worthless: a block device is reported as `likelyCached` (the one-character bug that would make
every verify vacuous); a *bad speed code abandons its own ceiling instead of flagging a healthy
drive*; after abandoning it, the fixed fallback still catches a RAM-speed read; a confirmed
ceiling catches a 2 GB/s read that the fallback alone would have missed; the verdict never
improves, including after a structural failure; and `code 0` is asserted to be Low Speed
rather than the SDK enum's "no device connected", so the mapping cannot be quietly "corrected"
into the wrong enum.

The authoring list grew from 6 to 7 items: the derived-ceiling design added one Core file.

#### GOTCHA: a compound integer literal inside `#expect` is not promoted to `Double`

New, and in the same family as the `pipefail` inversion — a test mechanism that silently
changes meaning.

```swift
#expect(USBLinkSpeed.high.maximumPayloadBytesPerSecond == 480_000_000 / 8)   // FAILS
```

It failed reporting `60000000.0 == 60000000` — two renderings of the same number. The same
comparison is `true` when evaluated normally. `#expect` captures each operand separately for
reporting, and a **compound** integer-literal expression (`480_000_000 / 8`) takes its default
type, `Int`, instead of being promoted to `Double`. A **bare** literal (`500_000_000`) infers
correctly from context — which is why the very next line in the same test passed, for no
visible reason.

This instance produced a false *fail*, which is harmless. The identical mechanism can produce
a false *pass*, which is not. **Write every expected `Double` as an explicit `Double`
literal** (`60_000_000.0`, `< 1.0`, `> 2.0`) in `#expect`, and prefer
`try #require(...)` into a local over inlining an optional.

### Design change during authoring: the falsifier's ceiling is derived, not chosen (2026-08-02)

**User proposal**, during file 2's GUI tick: *"If you are able to query what the highest USB
standard of both the USB host device and the USB Unit Under Test, then you can actually derive
the theoretical max i/o rate for the currently selected drive and use that as the threshold."*

Adopted. It replaces a number chosen by judgement (8 GB/s) with one the hardware states, and
it does not age as USB gets faster. **The host half turns out to be unnecessary**, which is a
simplification rather than a limitation: the registry reports the *negotiated* connection
speed, already the minimum of device, every intervening hub, and host port. Querying the host
separately would re-derive a minimum negotiation has already taken.

**Margin: ×1.1, corrected by the user from the ×2 first proposed.** *"I spent decades of my
career measuring block storage speeds, and I don't recall ever getting a measured result above
the negotiated theoretical max."* Correct — the payload rate after encoding is a hard physical
limit, not an estimate to pad, and a doubled ceiling concedes far more than measurement error
needs. 10% covers timer granularity and scheduling jitter.

Result, all confirmed on hardware 2026-08-02:

| Disk | code | link | payload max | ceiling ×1.1 | measured | headroom |
|---|---|---|---|---|---|---|
| `disk4` | 4 | 10 Gb/s | 1.212 GB/s | **1.333 GB/s** | 0.475 GB/s | 2.8× below |
| `disk8` | 3 | 5 Gb/s | 0.500 GB/s | **0.550 GB/s** | — | — |
| `disk0` | — | not USB | — | fallback 8 GB/s | — | — |

**6× tighter than the fixed threshold for `disk4`, 14.5× for `disk8`**, and a RAM-served cache
hit (71.3 GB/s measured) now sits 53× above `disk4`'s ceiling rather than 9×.

#### THE TRAP: two USB speed enums, and the SDK documents the wrong one

Nearly shipped a serious bug. `IOUSBHostFamilyDefinitions.h` defines
`tIOUSBHostConnectionSpeed` as `None=0, Full=1, Low=2, High=3, Super=4, SuperPlus=5,
SuperPlusBy2=6` — but that documents **`kUSBHostMatchingPropertySpeed`, a different
property**. The registry key actually present is `"Device Speed"`, a legacy `IOUSBFamily`
name whose enum is `Low=0, Full=1, High=2, Super=3, SuperPlus=4, SuperPlusBy2=5`, and which
the SDK does not declare at all — the same class of problem as the registry `#define`s
`DeviceClaim.swift` spells out by hand, and as the `_IOR` macros earlier this step.

Resolved by evidence, not by picking one. `scripts/usb-speed-check.sh` dumped every attached
USB device — **ten devices, zero anomalies** under the legacy mapping, four absurdities under
the SDK one:

| Device | code | legacy | SDK enum would say |
|---|---|---|---|
| USB keyboard, optical mouse | 0 | Low 1.5 Mb/s ✓ | **"no device connected"** ✗ |
| USB2 / USB2.1 Hub | 2 | High 480 Mb/s ✓ | **Low 1.5 Mb/s** ✗ |
| Expansion HDD (USB 3.0), USB3.1 Hub | 3 | Super 5 Gb/s ✓ | **High 480 Mb/s** ✗ |
| Portable SSD T5 (USB 3.1 Gen 2), USB3/3.2 Hubs, Ugreen | 4 | SuperPlus 10 Gb/s ✓ | Super 5 Gb/s |

The single decisive observation: **a connected keyboard reports 0**, which under the SDK enum
means "no device is connected". Independently, `disk4`'s measured 475 MB/s is 3.8 Gb/s of
payload and therefore impossible on a 480 Mb/s link, so code 3 cannot be High Speed.

**The consequence of being wrong is not symmetric**, which is what makes this dangerous rather
than merely untidy. Reading a 10 Gb/s link as 5 Gb/s only loosens the ceiling. Reading it as
Low Speed would set the ceiling at ~0.2 MB/s and flag **every read of every run** as cached.

#### Two guards, because the mapping is evidence-derived and can drift

1. **An unrecognised or absent code yields no ceiling** — the check falls back to the fixed
   8 GB/s and says so in the report. No code is ever guessed at.
2. **The derived ceiling must be confirmed before it is trusted.** It becomes credible only
   once a read arrives at or below it. Until then, exceeding it is evidence against *the
   ceiling*, not against the drive — a bad speed code makes every read exceed from the very
   first, whereas caching appears against a background of normal reads. The ceiling is then
   abandoned, with the reason recorded, and the fallback applies. Exceeding the *fallback*
   always counts, since no USB link of any generation reaches 8 GB/s.

Also added: reads below 64 KiB are not judged at all — at small sizes the measured rate is
dominated by fixed per-operation latency and timer granularity. Step 8 reads whole chunks of
1–8 MiB, so this excludes nothing real.

#### Added with it

- `tools/usb-speed-probe/main.swift` — resolves a whole disk to its link speed using the same
  upward recursive registry search `HelperDeviceRegistry` performs. Needed because `ioreg -n`
  **cannot** answer this: a disk's IOMedia entry does not carry the USB device's properties,
  which sit several levels up past the block-storage driver and SCSI peripheral. Verifying
  the real mechanism standalone before wiring it into a root daemon, exactly as `nocache-probe`
  did for the geometry ioctls.
- `scripts/usb-speed-check.sh` — dumps every attached device's code and checks the mapping
  still holds, including the keyboard-reports-0 test that discriminates the two enums. Run it
  after a macOS update, or whenever the cache-bypass check reports something surprising. 3
  PASS / 0 failures on macOS 26.5.2 (25F84).

### Authored 1/6 — `Core/DiskIOControl.swift` (2026-08-02)

The `ioctl` request numbers and the geometry-reconciliation policy. Pure Foundation; the
syscalls that use these constants land later, in the helper's `RawDeviceGeometry.swift`.
Same split as `DeviceAccessPrecondition` (pure decision) against `DeviceClaim` (impure
doing).

**Also edited, no GUI work needed:** `Core/RunParameterValidator.swift` gained
`validateGeometry(_:)`, factored out of `validate(byteOffset:byteLength:geometry:)`. From
Step 7 geometry arrives from two provenances — caller-supplied over XPC, and the helper's own
ioctls — and both must reject the same impossible values. Two copies of that rule would
eventually disagree, and the copy that mattered would be the looser one. Behaviour is
unchanged; the existing suite confirmed it.

**GUI operation done and verified (2026-08-02).** `Core/DiskIOControl.swift` added to
`USBDriveTesterTests` membership. Confirmed by reading `project.pbxproj`: it appears in the
test target's `membershipExceptions` set, the app target gained no exception set, and
`USBDriveTesterUITests` is untouched — exactly the two intended ticks.

**Tests: 238 → 253, 0 failures.** All 15 new `DiskIOControlTests` cases pass. Notable ones:
the four request numbers pinned against the C-measured literals; the `_IOR` encoding asserted
field by field so a failure says *which* part drifted; a test that a `UInt32` out-parameter
produces a *different, unrecognised* request rather than a truncated block count; decision
3a's power-of-two invariant made executable; and `disk8`'s real 42,970,644,479-block geometry
as the NFR-COMPAT-6 fixture, asserting the value a 32-bit truncation would have produced is
**not** the answer.

**`scripts/ioctl-constants-check.sh` added.** The tests guard the *code* against drifting
from the literals; they cannot guard the *literals* against drifting from the SDK, because a
Swift test cannot see a C macro — which is the whole reason this problem exists. This script
compiles `<sys/disk.h>` against the selected SDK and diffs. 9/9 pass on SDK 26.5.

Its own guards were then verified rather than assumed, in all three classes: the SDK
comparison fires when an expected value is corrupted; the assertion check fires when a
literal is deleted from the test file; and a missing source file now reports *"source not
found"* and refuses to report at all. That last one was a real defect found while testing the
guard — grepping a path that does not exist returns no hits, which was being reported as "the
assertion was deleted", sending a reader to the wrong file (NFR-USE-5).

### THE CALIBRATION RESULT: re-read timing cannot discriminate (2026-08-02, `disk4`)

`./scripts/nocache-calibration.sh disk4`, 4 MiB I/O, 4 reads per phase, 0 failures.
**The mechanism FR-TEST-9 was going to use does not work.** Measured, not predicted.

| phase | read 0 | read 1 | read 2 | read 3 |
|---|---|---|---|---|
| unflagged (`F_NOCACHE` not set) | 12,295 µs | 8,829 | 8,786 | 8,737 |
| flagged (`F_NOCACHE` + `F_GLOBAL_NOCACHE`, both `rc=0`) | 8,903 µs | 8,872 | 8,846 | 8,887 |

Reported speed-ups: unflagged **1.41**, flagged **1.01**.

**Why 1.41 is not a cache hit.** A 4 MiB copy from RAM on this machine takes **58 µs**
(71.3 GB/s, measured the same day). A genuine cache hit would therefore have been **~150×**
faster than an 8,800 µs read, not 1.4×. All eight reads sit at ~475 MB/s, which is real
USB 3.1 Gen 2 throughput for a T5 — every one of them went to the device.

**What 1.41 actually is: one-time warm-up.** It is read 0 of the whole process — USB
pipeline spin-up plus first-touch faults on 256 freshly `posix_memalign`'d 16 KiB pages. The
proof is in the second phase: its read 0 targets a **different, never-touched region** and
returns in 8,903 µs with no penalty, because the process was already warm. Had read 0 been a
cold miss followed by cache hits, the flagged phase's first read would have been ~12,300 µs
too. It was not.

**Root cause, now confirmed rather than suspected.** `/dev/rdisk4` is `crw-` — a
**character** device; `/dev/disk4` is `brw-`. The unified buffer cache is a property of the
*block* node. Reads through the raw node were never cached, so `F_NOCACHE` had nothing to
suppress, and its `rc=0` meant exactly as little as the `/dev/null` measurement suggested.

**This is the outcome the probe was written to be able to report.** Shipping a check that
returned `bypassed` on this evidence would have been a check that cannot fail — the precise
defect FR-TEST-9 exists to prevent, reproduced inside FR-TEST-9. Found before a line of the
classifier was written, which is the whole reason the calibration was made a prerequisite.

**The 8 MiB run corroborates the warm-up reading independently, and this is the part that
makes it conclusive rather than merely consistent.** A second run at 8 MiB gave read 0 =
21,686 µs against a steady 17,566–17,765 µs, i.e. a speed-up of **1.23** where 4 MiB gave
**1.41**. The *absolute* first-read overhead barely moved (≈3,560 µs at 4 MiB, ≈4,120 µs at
8 MiB) while the transfer doubled — which is the signature of a roughly fixed start-up cost,
and is why the ratio *fell* as the I/O grew. Caching cannot produce that: a cache hit is
~150× faster irrespective of size (8 MiB from RAM is 117 µs against the 17,566 µs measured).
Two different I/O sizes, the same conclusion, reached from the direction of the ratio moving
the *wrong way* for the caching hypothesis.

#### Two further findings from the same run

1. **`DKIOCGETMAXBYTECOUNTREAD` = 1,048,576 (1 MiB) — smaller than the I/O size, and it does
   not matter.** `extraIterations=0` in every phase of both runs: `pread` returned all
   4 MiB, and then all **8 MiB**, in a single call. The kernel splits the transfer
   internally at up to 8× the device's reported maximum. So `DeviceIOError.shortTransfer` is
   **not a live path on this bridge at either the default or the largest FR-CTRL-8 option**
   (a second run, 2026-08-02, at 8 MiB, confirmed it at the largest). Smaller sizes are
   strictly less demanding. The read loop and its iteration counter stay regardless — this
   is one bridge, and a short transfer remains legal.
2. **Throughput saturates at or before 4 MiB — 8 MiB buys nothing on this device.**
   ~477 MB/s at 4 MiB against ~474 MB/s at 8 MiB, i.e. identical within noise, and both are
   normal USB 3.1 Gen 2 figures for a T5. Relevant to Steps 9 and 11: FR-CTRL-8's 4 MiB
   default is well chosen, and a user selecting 8 MiB should not expect it to be faster —
   it only doubles the buffer pair (NFR-PERF-1) and the in-flight window (NFR-REL-4). Worth
   remembering when Step 9's metrics invite the conclusion that a bigger I/O size is better.
3. **Geometry confirmed on real hardware, pre-validating Step 7's first gate item.** The
   re-derived ioctls returned `logicalBlockSize=512`, `blockCount=1953525168`,
   `byteCount=1000204886016` — matching `diskutil` exactly, and matching the IOKit values
   Step 6 already logged. The `_IOR` derivation is correct through a real USB bridge, not
   merely correct as arithmetic. `DKIOCGETPHYSICALBLOCKSIZE` also returned 512, so this
   drive is not 512e.

#### The replacement mechanism for FR-TEST-9

The **requirement stands unchanged** — its text specifies *what* to verify, never *how*, and
protecting the verify from a vacuous pass is still right. Only the mechanism changes, and the
change is forced by an asymmetry the calibration exposed:

> **Timing can falsify, but it cannot verify.** A read returning 150× faster than the
> transport allows *proves* a cache hit. Two similar timings prove nothing at all, because
> they are identical whether caching was suppressed or was never possible.

So `bypassed` may never rest on timing. It rests on structure:

- **Primary — structural, and checkable.** `fstat(fd)` and assert `S_ISCHR`: the descriptor
  is the **character** device, not the block device. This catches the failure mode that can
  actually occur — opening `/dev/disk4` instead of `/dev/rdisk4`, a one-character bug that
  would silently make every verify vacuous — and it is a fact about the file, not a
  heuristic. Plus: the path opened is the raw node, and both `fcntl` calls returned 0.
- **Secondary — behavioural, falsification only.** During the run, flag `likelyCached` if any
  chunk read returns at a rate the transport cannot produce. Calibrated by this run: RAM is
  71.3 GB/s, the device is 0.475 GB/s — a 150× gap, so a threshold near **2 GB/s** sits ~4×
  above the fastest plausible USB device and ~35× below RAM. Wide and unambiguous.
- Three states as already decided: `bypassed` (structural checks pass, no implausible read
  seen), `likelyCached` (a structural check fails, or an implausible read is seen),
  `inconclusive` (the checks could not be performed).

#### A limit this exposed that belongs to Step 14, not Step 7

None of the above — and nothing available on the host — can establish that the verify read
came from **NAND**. The drive's own DRAM/SLC cache sits below every host mechanism, and a
read-back moments after a write may legitimately be served from it. The verify therefore
proves the data round-tripped through the device's I/O path; it does not prove the medium
retained it. That is a real limit on what a clean pass means, it is not fixable from here,
and it belongs with Step 14's honest framing (FR-WARN-3, "a clean pass is not a healthy
drive") rather than being quietly carried as if the tool proved more than it does.

### Decisions taken (2026-08-02) — all six

Numbered as in the scoping conflict list.

**1. BUILD-PLAN 7.1 reworded: Step 7 opens nothing.** The step instructed Step 7 to open
the raw device; Step 6 already does, in `DeviceClaim.acquire(_:)`, because the open is half
of the mount guard. Followed literally Step 7 would open a *second* descriptor, and closing
it is the hazard — measured 2026-08-01, releasing an exclusive open makes DiskArbitration
re-probe and remount ~4 ms later. "Fail with a precise error if it can't be opened
exclusively" was already discharged by `DeviceAccessPrecondition`.

**2. BUILD-PLAN 7.3 reworded: reconcile against the helper's own IOKit reading**
(`AcquiredDevice.geometry`), not "the values discovered in Step 5". Step 5's discovery runs
in the **app**. Step 6 gave the helper an independent registry read specifically so a root
daemon need not take the app's word about the device it is about to write to (NFR-REL-7);
reconciling against a Step 5 value would re-cross that boundary and let a GUI bug influence
what the helper believes. The comparison is ioctl vs. helper-IOKit, and both are logged.

**3. `validateRunParameters` keeps its caller-supplied geometry; the comments change
instead.** Option A of the two offered. The method's own documentation in
`Shared/TesterControl.swift` and `main.swift` promised that *"from Step 7 the caller-supplied
values are dropped entirely"*. That promise is retired, not kept.

The reason it is safe to retire: **this method authorises nothing.** No I/O passes through
it, no device is touched, nothing is acquired — it answers "would these numbers be
accepted?". It is a calculator, not a gate. The validation NFR-REL-7 is actually about is
the one on the write path, and that uses ioctl-derived geometry under either option, because
the helper's run path never receives geometry over XPC at all: it reads it off
`AcquiredDevice`.

What keeping it buys, and what changing it would have cost:

- The Diagnostics panel keeps demonstrating the validator **with no drive attached** —
  four presets driving the misaligned-offset, out-of-range and overflow rejections against
  a synthetic 2,048-block × 512-byte device (`HelperDiagnosticsView.demoBlockSize` /
  `demoBlockCount`). Making the method device-dependent would have required a drive
  attached *and* claimed before any of that could be shown.
- Step 7's protocol change stays **purely additive**, and Step 7 stays **helper-side only**
  as FR-ARCH-6 requires — no app-target source changes. Option B would have pulled
  `HelperConnection.swift` and `HelperDiagnosticsView.swift` into the step.

**Action:** rewrite both doc comments to state what the method actually is — a diagnostic
that validates against *caller-supplied* geometry — with a pointer to where the real
write-path validation happens. A stale comment claiming otherwise is worse than none.

**3a. Supported logical block sizes stay the explicit allowlist `{512, 4096}`.** Raised
during this decision: should the rule instead be "any even multiple of 512"? No — that rule
is **not sufficient**, which is the point that settles it. The design needs
`ioSize % blockSize == 0` for every offered I/O size, and those are 1/2/4/8 MiB, all powers
of two. A 1536-byte block size is an even multiple of 512 and divides none of them: every
run would fail deep inside `ChunkPlanError.ioSizeNotBlockAligned` instead of being refused
cleanly at the geometry check. The true structural invariant is **a power of two between
512 B and 1 MiB**.

The allowlist is kept even so, in preference to that broader invariant, because it is
exactly NFR-COMPAT-5's floor and the only two values that can be tested. BUILD-PLAN Step 7's
risks say to *"trust the ioctl and reject impossible values"*; a bridge reporting 1024 is far
likelier to be broken than to be a genuine 1024-byte-sector device, and accepting a geometry
never validated against is the substitute-for-the-real-thing pattern in requirement form.

Two consequences to implement:

- The power-of-two invariant becomes an **executable test**, not a comment: every member of
  `DeviceGeometry.supportedBlockSizes` must be a power of two dividing all four offered I/O
  sizes. A careless future `1536` then fails a test rather than shipping.
- **Physical** block size (`DKIOCGETPHYSICALBLOCKSIZE`, `0x4004644d`) is read and **logged
  only — never branched on.** Correctness depends solely on the *logical* size, which is
  what the kernel enforces alignment against; physical size affects performance only (on a
  512e drive, logical 512 / physical 4096, a write unaligned to 4096 forces a
  read-modify-write inside the drive). It costs one ioctl and would explain an otherwise
  baffling Step 9 throughput result.

**No FR/NFR amendment is required for 3a** — NFR-COMPAT-5 already says "at least 512-byte
and 4096-byte", and this is an implementation invariant beneath it.

**4. Bounded memory is the final design, and it binds more than the buffers.** User
decision, verbatim: *"peak buffer memory ≈ 2×ioSize is the correct and final design. I do
not want memory to scale with capacity."*

The buffers were never the problem. `RetentionTestEngine.chunkPlan()` returns a
materialised `[Chunk]`, which is **9.1 MiB for `disk4` and 200.1 MiB for `disk8`** — memory
scaling linearly with capacity, straight past NFR-PERF-2, and it survived because the gate
item says "peak *buffer* memory" and the buffers genuinely were bounded. The gate wording
in BUILD-PLAN and above is now widened to *no run-state structure scales with capacity*,
which also constrains Step 9's metrics and Step 10's bad-block report to bounded summaries
rather than per-chunk records. The plan becomes a lazily-computed `Sequence`; the array
survives as a test convenience. **This also settles the "lazy plan now?" question — yes.**

*Also confirmed, because it was queried:* the I/O-size control is **unchanged and not
lost**. FR-CTRL-8 specifies a dropdown of 1 / 2 / 4 / 8 MiB, default 4 MiB, set before a run
and fixed for its duration; BUILD-PLAN Step 11.2 builds that control. Step 7 only *consumes*
`ioSizeBytes` as a parameter, exactly as BUILD-PLAN 7.5 says ("passed in"), which is what
lets the unit tests drive deliberately awkward sizes the dropdown will never offer.

**5. The `F_NOCACHE` check becomes a run-start self-check that qualifies the result, not a
gate artefact — and it becomes a requirement (FR-TEST-9, M, added 2026-08-02).**

Offered as three options (checked `fcntl` only / timed double-read / double-read plus a
calibration control). The user chose the double-read and then **improved it**: rather than
proving the mechanism once at gate time, run the check *at the start of every run*, and if
it fails, have the app report and warn that the compare function may be compromised —
letting the run proceed, because the read → write-back still refreshes the medium, which is
a key project goal.

That is strictly better than what was proposed, for two reasons worth recording. It proves
the property on **every run, on the actual device, at the actual I/O size**, rather than once
on one drive. And it converts a binary pass/fail into a *qualification of the result*, which
is more honest than either blocking the run or proceeding silently — the two halves of the
product fail independently, and a cached read does not stop the write-back reaching the
device. Requirement text, rationale and consequences: FR doc, Amendments, 2026-08-02.

**Two corrections applied to the proposal as stated.**

1. **The polarity was inverted.** `F_NOCACHE` *working* means both reads reach the device and
   take **similar** times; `F_NOCACHE` *not* working means the second read is served from RAM
   and is much **faster**. So a large speed-up on the re-read is the warning condition, and
   similar durations are the healthy result. As originally worded the warning would have
   fired exactly backwards.
2. **The check's discriminating power is unproven, and may be nil.** `/dev/rdiskN` is the
   **character** device and is inherently unbuffered — which is precisely why FR-TEST-6
   specifies it over `/dev/diskN`. `F_NOCACHE` / `F_GLOBAL_NOCACHE` are belt-and-braces on a
   path that is probably already uncached, so the two timings may match *whether or not the
   fcntls did anything*, and the check would pass vacuously. That is the same defect shape it
   exists to catch. Stated as a prediction, not a measurement.

**Consequence: the calibration probe is a prerequisite, not optional polish.** It was offered
as optional (option C) and is now required, because it is the only thing that answers both
open questions at once — whether the timing test can discriminate at all, and what the
numeric thresholds for "similar" versus "much faster" actually are on this hardware.
Approved by the user 2026-08-02: *"I am willing to run a calibration probe on `disk4` as
needed to establish thresholds based on real world testing."* Thresholds will be recorded
with their provenance; none are to be invented.

**Build order this forces.** `tools/nocache-probe` + `scripts/nocache-calibration.sh` are
authored **first**, before `Core/CacheBypassCheck.swift`, so the classifier is written
against measured numbers rather than adjusted to them afterwards.

**Design notes settled with it.**

- The classifier has **three** states — `bypassed` / `likelyCached` / `inconclusive` —
  matching `FullDiskAccessState` and `HelperShutdownReadiness`. "Could not tell" must never
  collapse into either answer, and a device fast enough that timing noise dominates must
  report `inconclusive` rather than a verdict.
- The self-check reads a chunk from the **middle of the device, not chunk 0**. Block 0 is
  the GPT and partition table — the region the OS has most recently touched, so its "first"
  read is the least likely to be genuinely cold.
- Step split: **Step 7** builds the pure classifier and the helper-side timing harness;
  **Step 8** calls it at run start and gates the verify result on it; **Step 10** carries the
  qualification into the exported Markdown report; **Step 11** surfaces it in the UI.

**5a. The XPC surface does grow — protocol v4 → v5, purely additive.** This was left open
during scoping. The hesitation was NFR-SEC-3: a privileged method whose only caller is the
gate harness is not "necessary to perform its function". FR-TEST-9 dissolves that — the
result is now a product signal the app is *required* to display. Two methods, both requiring
a held device and refusing cleanly otherwise:

- `deviceGeometry(reply:)` — **passive.** Reports what acquire already established: the
  ioctl geometry and the helper's IOKit geometry, so the gate compares each against
  `diskutil info` and the reconciliation of decision 2 is directly observable.
- `checkCacheBypass(reply:)` — **active.** Performs the two timed reads on the held
  descriptor and returns the classifier's state plus both durations.

Two methods rather than one because mixing a passive accessor with an operation that
performs I/O reads fine now and confuses badly by Step 11.

**6. `disk4` only.** User decision: *"I only want to use `disk4` for testing for now, unless
there is an important test case that cannot be satisfied with `disk4`."* `disk8` is not part
of this gate.

One case that genuinely cannot be satisfied by `disk4` was identified and carried: NFR-COMPAT-6.
`disk4` is below 2³² blocks, so a bridge truncating its block count to 32 bits would be
invisible there, and the failure mode is silent — the tool would test the first portion of a
larger drive and report a clean pass. Unit tests cover the 64-bit arithmetic at full scale
using `disk8`'s real geometry as a fixture; what had no evidence was a real bridge reporting a
>2³² count.

> **CLOSED later the same day (2026-08-02), on user instruction: "verify on disk8 that we can
> address above the 32-bit boundary… before we begin Step 8."** `scripts/large-address-check.sh
> disk8` passed 10/10 — read-only, nothing unmounted. See the Step 7 COMPLETE summary. `disk8`
> remains outside every other gate; a specific case still has to be named and agreed before it
> is used again.

---
