//
//  MainThreadWatchdog.swift
//  MainThreadWatchdog
//
//  Pings the main queue from its own thread every 100 ms; when a ping goes unanswered for
//  ``threshold`` it writes a stall record to ``StallLog``: how long, which ``MainActivity``
//  bracket was open, the host's standing ``MainActivity/context``, and the main thread's STACK
//  at that moment (and again two seconds on, if it is still there) — so a stall names its
//  function, not just the operation that happened to be running.
//
//  Created by David Sherlock on 9/5/26.
//

import Foundation

/// Pings the main queue from its own thread every 100 ms; when a ping goes unanswered for
/// ``threshold`` it writes a stall record to ``StallLog``: how long, which ``MainActivity``
/// bracket was open, the host's standing ``MainActivity/context``, and the main thread's
/// STACK at that moment (and again two seconds on, if it is still there) — so a stall names
/// its function, not just the operation that happened to be running.
///
/// The beach ball, as evidence: every stall a user feels is the main thread not answering,
/// and this writes down what it was doing so the next one can be fixed rather than
/// theorised about. One wake-up per 100 ms at `.userInitiated` costs nothing measurable.
public enum MainThreadWatchdog {
    /// A ping unanswered this long is a stall worth writing down.
    public static let threshold: TimeInterval = 0.25
    nonisolated(unsafe) private static var started = false

    /// Starts the watchdog thread. Call once, on the main thread, after ``StallLog/configure(directoryName:environmentVariable:)``.
    /// `trace` prints every ping and its round trip to stderr.
    public static func start(trace: Bool = false) {
        guard !started else { return }
        started = true
        MainThreadSampler.captureMainThreadIdentity()
        let thread = Thread {
            while true {
                let sent = Date()
                let answered = DispatchSemaphore(value: 0)
                DispatchQueue.main.async { answered.signal() }
                let outcome = answered.wait(timeout: .now() + threshold)
                let waited = Date().timeIntervalSince(sent)
                if trace { fputs("watchdog ping \(sent.timeIntervalSinceReferenceDate) -> \(outcome == .timedOut ? "TIMEOUT" : "ok") after \(Int(waited * 1000)) ms\n", stderr) }
                // Decide on ELAPSED time, not on the timeout firing: the kernel gives timers
                // leeway, and a wait that wakes late finds the main thread already answered.
                // That is still a stall; it just went unsampled.
                if outcome == .timedOut || waited >= threshold {
                    let during = MainActivity.snapshot
                    let first = outcome == .timedOut ? MainThreadSampler.sample() : []
                    var second: [UInt] = []
                    if outcome == .timedOut, answered.wait(timeout: .now() + 2.0) == .timedOut {
                        second = MainThreadSampler.sample()
                        answered.wait()
                    }
                    let stall = Date().timeIntervalSince(sent)
                    let context = MainActivity.context
                    var lines = ["stall \(Int(stall * 1000)) ms  during: \(during)" + (context.isEmpty ? "" : "  editor: \(context)")]
                    if first.isEmpty {
                        lines.append("    main thread answered before the sampler woke (\(Int(waited * 1000)) ms)")
                    } else {
                        lines.append("    main thread at +\(Int(threshold * 1000)) ms:")
                        lines += MainThreadSampler.symbolicate(first).prefix(24).map { "      " + $0 }
                    }
                    if !second.isEmpty {
                        lines.append("    main thread at +\(Int(threshold * 1000) + 2000) ms:")
                        lines += MainThreadSampler.symbolicate(second).prefix(24).map { "      " + $0 }
                    }
                    StallLog.write(lines.joined(separator: "\n"))
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        thread.name = "main-thread-watchdog"
        // NOT .utility: utility timers get ~50–100 ms of kernel leeway, so a 250 ms wait woke
        // at ~300 ms — after a 450 ms block had already been answered — and a self-test missed
        // the stall three runs in ten.
        thread.qualityOfService = .userInitiated
        thread.start()
    }
}
