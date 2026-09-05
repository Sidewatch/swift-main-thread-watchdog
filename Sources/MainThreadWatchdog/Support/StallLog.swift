//
//  StallLog.swift
//  MainThreadWatchdog
//
//  Append-only log of stalls and slow brackets, written off the caller's thread.
//
//  Created by David Sherlock on 9/5/26.
//

import Foundation

/// Append-only log of stalls and slow brackets, written off the caller's thread. An app
/// that never stalls never writes a byte.
///
/// Configure once at launch, before the watchdog starts:
/// `StallLog.configure(directoryName: "MyApp", environmentVariable: "MYAPP_STALL_LOG")`.
/// The file is `~/Library/Logs/<directoryName>/stalls.log`; the environment variable, when
/// set, overrides the path (a harness points it at a temp file).
public enum StallLog {
    nonisolated(unsafe) private static var directoryName = ProcessInfo.processInfo.processName
    nonisolated(unsafe) private static var environmentVariable: String? = nil
    nonisolated(unsafe) private static var resolved: URL?
    private static let configLock = NSLock()

    /// Where the log goes. Call before the first write; later calls are ignored once a
    /// write has resolved the path.
    public static func configure(directoryName: String, environmentVariable: String? = nil) {
        configLock.lock(); defer { configLock.unlock() }
        guard resolved == nil else { return }
        self.directoryName = directoryName
        self.environmentVariable = environmentVariable
    }

    /// Points the log at an exact file — for tests and harnesses.
    public static func configure(url: URL) {
        configLock.lock(); resolved = url; configLock.unlock()
    }

    /// The log file, resolved on first use.
    public static var url: URL {
        configLock.lock(); defer { configLock.unlock() }
        if let resolved { return resolved }
        if let name = environmentVariable, let p = ProcessInfo.processInfo.environment[name], !p.isEmpty {
            resolved = URL(fileURLWithPath: p); return resolved!
        }
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/\(directoryName)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        resolved = dir.appendingPathComponent("stalls.log")
        return resolved!
    }

    private static let queue = DispatchQueue(label: "main-thread-watchdog.stall-log", qos: .utility)
    private static let stamp: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"; return f
    }()

    /// Blocks until every queued line is on disk — for tests and harnesses.
    public static func flush() { queue.sync {} }

    /// Appends one timestamped line (multi-line records are fine).
    public static func write(_ line: String) {
        let text = "\(stamp.string(from: Date()))  \(line)\n"
        let target = url
        queue.async {
            if let h = try? FileHandle(forWritingTo: target) {
                h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close()
            } else {
                try? text.write(to: target, atomically: true, encoding: .utf8)
            }
        }
    }
}
