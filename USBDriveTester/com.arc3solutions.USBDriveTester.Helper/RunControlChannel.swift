//
//  RunControlChannel.swift
//  Helper — making the app's current wish readable by a run that is already in flight.
//
//  Step 11, increment 2. This is the concurrency half of FR-CTRL-2/3/4; the decision half is
//  `Core/RetentionTestEngine.interruption(_:atBlock:)`, which is unit-tested with no locks.
//
//  ## Why this file has no logic in it
//
//  The same rule `MetricsChannel` follows, and for the same reason: everything that could be
//  decided in Core already was. What is left here is a lock and a slot, because that is the part
//  Core cannot have — the run reads this on the thread XPC delivered `runRetentionCycle` on, and
//  `setRunControl` writes it on a different thread entirely, from a different connection.
//
//  Anything with a decision in it that ends up here is in the wrong file.
//
//  ## Why it has to be process-wide rather than connection-scoped
//
//  Measured 2026-08-04 (`scripts/xpc-concurrency-check.sh`): while the helper is inside a blocking
//  privileged call, **a second message on that same connection is not delivered until the call
//  returns**, while a second connection is answered concurrently in 0.2–0.3 ms. So a pause cannot
//  arrive on the connection running the cycle — by construction, not by contention — and there is
//  therefore nowhere connection-scoped to put it. Same conclusion `MetricsChannel` reached from the
//  same measurement, arrived at from the other direction: that one is *read* from another
//  connection, this one is *written* from another connection.
//
//  ## Any accepted caller can stop a run, and that is deliberate
//
//  `prepareForShutdown` deliberately **refuses** while busy rather than releasing, precisely so that
//  no caller — even one correctly signed under our Team ID — can use it to abort a run in progress.
//  This method does the opposite, and the difference is what the two would leave behind.
//
//  A teardown mid-write can leave a half-written device (NFR-REL-5), so refusing is the safe
//  direction there. A stop cannot: the engine settles at a chunk boundary with the previous chunk's
//  full read → write-back → verify complete, which is the entire guarantee NFR-REL-10 asks for. And
//  stopping is a capability FR-CTRL-4 *requires* the user to have. Nothing is granted here that a
//  caller did not already have — one that wanted to keep this drive claimed could simply call
//  `acquireDevice` and hold it.
//
//  ## Nothing here clears itself, and every client must clear it for itself
//
//  Clearing it here would be the unsafe direction: a pause issued in the gap between two of a run's
//  bounded calls would be discarded, and the user would watch a Pause they had pressed do nothing.
//  So the obligation sits with the caller, and the app discharges it — it sets ``proceed`` before
//  every run and on every resume (BUILD-PLAN Step 11: *"state owned GUI-side"*), **awaits** the
//  confirmation, and abandons with a visible message if it does not arrive. See
//  `RunController.resume()`.
//
//  ### This heading used to end "…and that is what makes a stale value harmless". That was wrong.
//
//  The argument ran: the app owns the state and always clears it, so a value left over from a
//  previous run can only make the next one do **less** than it was asked to — and the app's own
//  state machine would refuse to issue that run anyway, so the failure direction is the safe one.
//
//  Every step of that is true **of the app**. The slot is not the app's. It is process-wide on the
//  daemon and shared by every client that connects, and **every gate script in this project is a
//  client that is not the app.** The conclusion was drawn about one caller and stated about all of
//  them.
//
//  Measured 2026-08-23. The app set `stop` at 09:11:29 during a GUI session and nothing set it
//  back. `scripts/metrics-check.sh` then acquired the drive and issued four bounded calls; each
//  returned `stoppedByUser` after 0.5 ms having processed zero chunks, and forty assertions failed
//  off that one stale value without a single one of them naming it. `metrics-probe` predates this
//  channel and had never cleared the level; `run-control-probe`, written after it, always has.
//
//  **The probe was fixed, not this class** — the design above is right, and the caller does own the
//  level. What was wrong was a comment that reasoned about one client and concluded something about
//  every client.
//

import Foundation
import os

private let controlLog = Logger(subsystem: HelperIdentity.loggingSubsystem, category: "io")

/// The process-wide slot holding what the app currently wants the run in flight to do.
///
/// A singleton for the same reason `HelperActivity` and `MetricsChannel` are: the writer and the
/// reader are on different connections, so there is nowhere else for it to live.
///
/// It holds no device, takes no device-operation slot, and blocks nothing. `HelperActivity` remains
/// the authority on what the helper is *doing*; this only remembers what it has been asked for.
final class RunControlChannel: @unchecked Sendable {

    static let shared = RunControlChannel()

    private let lock = NSLock()

    /// Defaults to ``RunControlSignal/proceed``, so a daemon that has never been told anything runs
    /// exactly as it did before this existed.
    private var signal: RunControlSignal = .proceed

    private init() {}

    /// What the run should do at its next chunk boundary.
    ///
    /// Read once per chunk from inside the cycle. One uncontended lock acquisition against a chunk
    /// that is ~27 ms of device I/O at the 4 MiB default, so it cannot appear in NFR-PERF-3's
    /// figures — but it is per-chunk, so it stays a lock acquisition and nothing more.
    var current: RunControlSignal {
        lock.withLock { signal }
    }

    /// Record what the app wants (FR-CTRL-2/3/4).
    ///
    /// Logged at `notice` rather than `info`: this is the durable record that a pause request
    /// *reached the daemon*, which is the half of the handshake the app cannot observe for itself.
    /// The other half — that the run settled — is logged by `RunLogger.runFinished` with the
    /// outcome, and the two timestamps together are what the pre-flight measures the latency
    /// between (NFR-OBS-1, NFR-REL-10).
    func request(_ signal: RunControlSignal, from peer: String) {
        lock.withLock { self.signal = signal }
        controlLog.notice("""
                          run control set to \(String(describing: signal), privacy: .public) \
                          by \(peer, privacy: .public)
                          """)
    }
}
