# Drive identity moved to serial numbers (2026-08-06)

*Archived from `PROGRESS.md` on 2026-08-11, when the log was split. Nothing here has been
edited — statements carry the dates on which they were true.*

**Do not read this as current.** What still binds today's work is in
[CONSTRAINTS.md](../CONSTRAINTS.md); what is in progress is in [PROGRESS.md](../PROGRESS.md).
This file is here for the one question the other two cannot answer: *why was it done that way?*

---

## Drive identity moved to serial numbers (2026-08-06) — READ THIS BEFORE ANY BSD NAME BELOW

**A reboot renumbered this machine's drives, and every `disk4` written anywhere in this project
became wrong on the same morning.** The designated scratch device — Samsung Portable SSD T5,
serial **`12345686DAA9`** — is now **`disk8`**. And `disk4` is now the **Seagate 22 TB holding
Backup and Time Machine**. The two swapped.

| role | drive | **serial** | was | is now |
|---|---|---|---|---|
| scratch (every write gate) | Samsung Portable SSD T5, 1 TB | **`12345686DAA9`** | `disk4` | **`disk8`** |
| bulk (read-only, by agreement) | Seagate Expansion HDD, 22 TB | **`00000000NT17XBRA`** | `disk8` | **`disk4`** |
| source tree (never tested) | Samsung 990 EVO Plus, Ugreen enclosure | **`013117100578`** | `disk6` | `disk6` |

### What that would have cost, stated plainly

`./scripts/retention-cycle-check.sh disk4` — the command written in this file, in BUILD-PLAN, and
in a dozen shell histories — would have unmounted the backup drive and written a gibibyte to it.
And `metrics-check.sh` carried a guard that **refused any drive but `disk4`**: a safety check that
the renumbering turned exactly inside out, so it would have refused the correct drive and admitted
the backup one. A guard whose premise has silently expired is worse than no guard, because it is
still trusted.

The product has identified drives by USB serial number since 2026-08-05, for precisely this
reason. The decision had been implemented in the app and **not** in the apparatus around it.

### What changed (user decision 2026-08-06)

- **`tools/device-id`** — resolves serial ↔ BSD name by compiling the **app's own** enumerator, so
  "this drive's serial" has one definition in the project rather than two. It inherits the IOKit
  ancestor search and `USBSerialNumber.sanitised`'s placeholder rejection for free.
- **`scripts/lib/device-identity.sh`** — every hardware script now resolves its target by serial,
  cross-checks the block count, and **refuses** anything else. A stale `diskN` on the command line
  is not ignored: it is checked and refused, naming both serials and what the other drive is.
- **The scripts' own name-based guards are gone**, replaced rather than weakened — `resolve_target`
  establishes identity before any of that code runs, and by 2026-08-06 those guards were inverted.
- **Shown refusing, on the real machine**, which is the only evidence that counts here:
  `metrics-check.sh disk4` and `retention-cycle-check.sh disk4` both refuse, before touching
  anything, and say why.

### One consequence inside the product, found by rendering

**The app now default-selects the backup drive.** FR-DEV-2 sorts the list by BSD name and FR-DEV-3
selects the first usable device; after the renumbering the first in that order is `disk4` — the
Seagate, with Backup and Time Machine mounted. `scripts/render-ui.sh devices` shows it selected,
with its 22 TB detail filled in. Both requirements are satisfied exactly as written; what changed
is which physical drive "first" names.

Nothing is done about it here, and nothing needs to be *today*: no run can start without an
explicit unmount and acquire, and the panel already says "Testing a drive you are using is not
advisable." It matters at **Step 11**, where Start owns unmount → acquire → run and the default
selection is one deliberate click from a write — which is precisely why that step's removal of the
explicit unmount is gated on Step 14's warnings existing. Recorded as an inherited note on both.

**FR-DEV-3 stands as written — settled 2026-08-06, user decision**, put to the user with the
render above and kept unchanged.

> *"FR-DEV-3 is perfect as written. I do not want to go down the road of trying to divine user
> intentions."* — user, 2026-08-06

It is the same policy as D9's refusal to grade throughput, and worth seeing as one rule rather
than two: the tool reports what it measured and declines the judgements it is not entitled to
make. A default that guessed which drive its owner considers expendable would be exactly such a
judgement, and a worse one than a graded throughput figure — it would look like the app knowing
something about the user's hardware, at the moment that belief is most expensive. "The first
device in a stated order" says only what is true.

The consequence is that **the entire mitigation sits in Step 14's warnings**, which must name the
drive by model and USB serial rather than by BSD name. Recorded on Step 14, and it is why Step 11's
removal of the explicit unmount is gated on that step existing rather than merely sequenced after
it.

### The rule is two-sided, and the test is lifetime (clarified by the user, 2026-08-06)

Everything above states one half, and read alone it would justify stripping the BSD name out of
the UI. That would be a regression, and it is not what was decided.

> *"I like the idea of showing the BSD name anywhere live drive data is being displayed because it
> offers one more piece of identity disambiguation information. I just don't ever want to refer to
> drives by their BSD name for any purpose that might become stale upon unplug/re-plugs or reboots
> (like build plans, scripts, previous test results, etc.)."* — user, 2026-08-06

So the question is never "is a BSD name allowed here?" but **does this statement outlive the
enumeration that produced it?**

- **Live** — the device list, the selected-device detail, `/dev/rdiskN`, a metrics heading, a log
  line about work in flight: **show it**, beside the serial. It answers *which of the things in
  front of me right now?*, and two identifiers a user can cross-check beat one.
- **Persisted** — this file, BUILD-PLAN, gate scripts and their command lines, the exported report,
  release notes: **never as the identity**; use the serial. If a BSD name appears at all it is
  labelled as the locator it was at the time.

Recorded canonically in the FR document's 2026-08-06 entry, with the rule stated at
`BSDDeviceName` where a developer meets it, and applied to Step 10's report (identity = serial)
and Step 14's warnings (identify by model + serial, locator beside it).

### About the BSD names still in this file

**They stay.** Everything below this entry is a historical record — what a drive was called on the
day a thing was measured — and rewriting it would falsify the audit trail this file exists to be.
`disk4` in an entry dated 2026-08-03 correctly names the drive that was `disk4` on 2026-08-03.
Forward-looking text has been corrected; BUILD-PLAN, the FR and NFR documents and every script
name drives by serial now, because those are read as instructions.

**The lesson, which this project has now learned in four different costumes:** an identifier that
is assigned rather than intrinsic will eventually name something else, and nothing will announce
it. It was the same shape as the BSD name in a device list, the same shape as a placeholder serial
of sixteen zeros, and the same shape as a probe reporting `0.0 ms` for a reply that never came.
Here it had teeth, because the identifier was being handed to something that writes.

---
