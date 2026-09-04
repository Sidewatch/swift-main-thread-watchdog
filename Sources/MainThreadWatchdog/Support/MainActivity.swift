import Foundation

/// A named bracket around main-thread work. Nesting keeps the OUTERMOST name current, so a
/// stall is attributed to the operation the user asked for, not the helper it was inside.
///
/// `enter` a bracket on the main thread, `done()` it when the work ends. Brackets slower than
/// ``slowOp`` are logged even when no stall was detected; ``snapshot`` is what the watchdog
/// thread reads when a ping goes unanswered.
public enum MainActivity {
    /// Brackets slower than this are logged even when no stall was detected.
    public static let slowOp: TimeInterval = 0.10

    /// The open bracket. Call ``done()`` on the same thread that entered it.
    public struct Token {
        public let name: String
        public let start: Date
        /// Closes the bracket; logs it if it was slow.
        public func done() {
            let elapsed = Date().timeIntervalSince(start)
            MainActivity.close()
            if elapsed >= MainActivity.slowOp {
                StallLog.write("slow  \(Int(elapsed * 1000)) ms  \(name)")
            }
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var current: String?
    nonisolated(unsafe) private static var depth = 0

    /// Opens a bracket. `name` should say what and how much ("disk changes 1,240").
    public static func enter(_ name: String) -> Token {
        lock.lock()
        depth += 1
        if depth == 1 { current = name }
        lock.unlock()
        return Token(name: name, start: Date())
    }

    private static func close() {
        lock.lock()
        depth = max(0, depth - 1)
        if depth == 0 { current = nil }
        lock.unlock()
    }

    /// Whatever bracket is open right now, or "no marker" — read from any thread.
    public static var snapshot: String {
        lock.lock(); defer { lock.unlock() }
        return current ?? "no marker"
    }

    /// Standing context, not a bracket: what the app is showing ("Str.php 6,396 lines wrap
    /// on"). Written by the host whenever that changes; carried on every stall record.
    public static var context: String {
        get { lock.lock(); defer { lock.unlock() }; return _context }
        set { lock.lock(); _context = newValue; lock.unlock() }
    }
    nonisolated(unsafe) private static var _context = ""
}
