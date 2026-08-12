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
//  ## Nothing here clears itself, and that is what makes a stale value harmless
//
//  The app owns the state (BUILD-PLAN Step 11: *"state owned GUI-side"*) and sets ``proceed``
//  before every run and on every resume. So a value left over from a previous run can only make the
//  next one do **less** than it was asked to — and the run it would shorten has not started, so the
//  app's own state machine refuses to issue it anyway. The failure direction is the safe one.
//
//  Clearing it here instead would be the unsafe direction: a pause issued in the gap between two of
//  a run's bounded calls would be discarded, and the user would watch a Pause they had pressed do
//  nothing.
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
