## **My Background:**

I’m a former MacOS developer with extensive experience writing code to manage mass storage devices on the Mac platform, especially USB hard disk drives. 

## **Goal:**

All of my external direct attach storage devices today connect via USB. Therefore, I want:

* To keep the data stored on them as reliable as possible and  
* To detect if a USB storage device is experiencing hard i/o failures.

## **Data Retention and Hard Reliability Testing Targets:** 

Solve the main data storage, retrieval and retention problems of the two different common storage media, NAND flash and Rotational Magnetic Media (used in Hard Disk Drives \- HDD) with one testing application:

* NAND flash data retention. Data written to NAND flash memory degrades over time. Especially when left to sit unplugged for a long period of time or subjected to thermal cycling, the data written to NAND-based block storage devices will eventually become un-retrievable.   
* HDD data retention. Problems like adjacent track interference, thermal cycling, Superparamagnetic Effect, etc., can interfere with a hard disk drive’s ability to retrieve data over time.

## **Project Objective:** 

I would like to develop Apple Silicon native executables for MacOS Tahoe and later using XCode and Swift programming language that address the two problems through storage media exercise and testing. At least one executable must have a graphical user interface which allows the user to control and monitor the progress of the application.

## **Software Architecture:**

Due to MacOS security protocols, direct access to storage media can only be accomplished through privileged escalation. Apple encourages developers to use at least two separate executables \- typically using a command line tool to perform the privileged operations and GUI executable to control and communicate with the privileged command line tool.

## **Software Design:**

### Upon launch

The software should locate and display in a list view all the connected USB mass storage devices currently connected to the computer. The first device discovered should be the default selection in the list view. Only one device is tested at a time; a new run cannot be started while another run is in progress.

### Strategy to Solve Data Retention and Reliability Problems

The best approach to solve both problems is to read all the data on the storage device and write it back in place, sequentially. By re-writing data currently in place, the data is refreshed in the storage medium and more likely to stay retrievable in the future than before the operation. 

### Managing Mounted Volumes

A test that reads and writes block level data must never be run when there are mounted volumes belonging to the device. The software must check to make sure that any and all volumes belonging to the device are not mounted by the MacOS file system. An appropriate error message should be shown informing the user that the volumes must be unmounted prior to running the test.

### The Test Algorithm

I want the software to try and be non-destructive to the data currently on the device. I propose to have the software enable raw, uncached, block-level read and write access across the entire addressable storage medium. The software will read a chunk of data sized by a user-selectable **I/O size** (a dropdown offering 1, 2, 4, or 8 MiB, defaulting to 4 MiB, to balance speed and memory usage), write it back to the same location and then read the freshly written data back again into a second buffer and compare the data in two read buffers for differences. The test will begin at the first addressable block of the drive and end at the last addressable block of the drive, proceeding sequentially. The last iteration will likely need to be less than a full chunk and should be sized instead to match exactly the remaining number of blocks (rounded up to the device's logical block size, never an arbitrary byte remainder).

### Interruptions and Errors — No Resume

The only volatile copy of a chunk's original data exists in RAM during the read → write-back → verify cycle. If the process dies mid-write, that chunk can be left torn, and on a whole-device test a torn write to partition tables, the GPT, or filesystem superblocks can make an otherwise-good drive appear blank. The software does not journal in-flight chunks and does not support resuming an interrupted run. If the test encounters a data transfer error — or is otherwise interrupted (e.g., the device is removed, see below) — it reports the error only and the test must be restarted from the beginning. This residual in-flight data-loss window is accepted and is the reason for the mandatory "back up first" warning.

### Device Removal During a Test

If the device under test is hot-unplugged or de-enumerates from the USB bus while a test is running, the software must immediately terminate the test, present a suitable error message, and re-run the initial USB device discovery routine.

### Handling I/O Failures

The software must support two failure-handling modes, user-selectable before the run:

* **Stop on first error** — halt immediately on any i/o failure and report the offending block range. Useful for a quick pass/fail health check.
* **Log and continue** — record the offending block range to a bad-block list and continue refreshing the rest of the device. This is the safer default for a marginal drive, since stopping on the first bad sector would leave the remaining (often vast) majority of the device un-refreshed and arguably worsen its retention.

In both modes the run ends with a report listing every block range that failed, along with the throughput and latency statistics described below. The user must be able to export this report to a file in Markdown format for their records. The software does not retain a history of previous test runs; each run is standalone.

### Features

The user interface should warn users that even though the test is intended to be non-destructive, it is still possible to lose or corrupt data and that the unit under test should be backed up before testing. Further, this type of testing should only be performed infrequently on NAND devices.  
I also want the software to maintain a measurement of the average throughput of both the reads and the writes because slow i/o can also be important information. This information should be easily readable from the user interface. In addition to average throughput, the software should capture per-chunk read latency (at least min, max, and a high percentile such as p99), because a sector that still reads successfully but takes dramatically longer than its neighbors is a strong early-warning sign of a failing block even when no hard i/o error occurs.   
Further, once started the test should be able to be paused, resumed from pause, stopped or restarted from the beginning.

### What the Test Does and Does Not Prove

The user interface must be honest about what a clean pass means so users do not mistake it for a clean bill of health. This tool is two things at once:

* A **retention refresher** — by reading and rewriting every block in place it re-programs NAND cells into fresh pages (via the device's FTL) and re-magnetizes HDD sectors, making the existing data more likely to remain retrievable.
* A **hard-fault detector** — it surfaces blocks that are already unreadable (beyond the device's own ECC), reporting them as i/o failures.

What it **cannot** detect at the USB block level is a block that is *degrading but still correctable* — a NAND page the controller silently ECC-corrects, or an HDD sector that succeeds only after heavy retries. Those reads return clean data, so a passing run means "no currently-unreadable blocks were found," **not** "this drive is healthy." The latency statistics above are the only block-level proxy available for impending-failure signal; the richer signal (reallocated/pending sectors, raw error rates) lives in SMART/NVMe telemetry, which we have deliberately excluded (see below).

### What’s Not Included

Ideally the tool should also check whether the device supports SMART/nVME health polling. However, these commands are not typically supported by SATA to USB bridging devices so it would be very rarely of value and not worth the extra complexity.

