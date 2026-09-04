import XCTest
@testable import MainThreadWatchdog

/// Burns CPU on the calling thread for `seconds`; never inlined so the sampled stack names it.
@inline(never) func watchdogProbeBlock(_ seconds: TimeInterval) -> Int {
    let deadline = Date().addingTimeInterval(seconds)
    var acc = 0.0
    while Date() < deadline { acc += sin(acc + 1) }
    return acc.isNaN ? 0 : Int(seconds * 1000)
}

final class MainActivityTests: XCTestCase {
    func testOutermostBracketIsTheSnapshotAndItClears() {
        XCTAssertEqual(MainActivity.snapshot, "no marker")
        let outer = MainActivity.enter("outer")
        let inner = MainActivity.enter("inner")
        XCTAssertEqual(MainActivity.snapshot, "outer", "nesting keeps the outermost name")
        inner.done()
        XCTAssertEqual(MainActivity.snapshot, "outer")
        outer.done()
        XCTAssertEqual(MainActivity.snapshot, "no marker")
    }

    func testContextIsReadableFromAnotherThread() {
        MainActivity.context = "Str.php 6,396 lines"
        let e = expectation(description: "read off-main")
        Thread { XCTAssertEqual(MainActivity.context, "Str.php 6,396 lines"); e.fulfill() }.start()
        wait(for: [e], timeout: 2)
        MainActivity.context = ""
    }
}

final class StallLogTests: XCTestCase {
    func testWritesTimestampedLinesToTheConfiguredFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("stall-\(UUID().uuidString).log")
        StallLog.configure(url: url)
        StallLog.write("slow  120 ms  probe")
        StallLog.flush()
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.hasSuffix("  slow  120 ms  probe\n"), text)
        XCTAssertNotNil(text.range(of: #"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3}  "#, options: .regularExpression), "timestamp prefix")
        try? FileManager.default.removeItem(at: url)
    }
}

/// The watchdog itself, end to end: XCTest runs on the main thread, so blocking here is a
/// real stall, and `RunLoop.main.run(until:)` answers the pings the way an app's loop does.
final class WatchdogTests: XCTestCase {
    static let log = FileManager.default.temporaryDirectory.appendingPathComponent("watchdog-\(getpid()).log")

    override class func setUp() {
        StallLog.configure(url: log)
        MainThreadWatchdog.start()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))   // let the first pings land
    }

    private func logText() -> String {
        StallLog.flush()
        return (try? String(contentsOf: Self.log, encoding: .utf8)) ?? ""
    }

    func testABlockedMainThreadIsLoggedWithTheOuterBracketAndItsStack() {
        let outer = MainActivity.enter("probe block outer")
        let inner = MainActivity.enter("probe block inner")
        _ = watchdogProbeBlock(MainThreadWatchdog.threshold + 0.2)   // the main thread stops answering
        inner.done(); outer.done()
        // The watchdog samples, waits for main, symbolicates, THEN writes: poll rather than sleep.
        var log = ""
        let until = Date(timeIntervalSinceNow: 3)
        repeat {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            log = logText()
        } while !log.contains("stall ") && Date() < until
        let lines = log.split(separator: "\n").map(String.init)
        XCTAssertTrue(lines.contains { $0.contains("stall") && $0.hasSuffix("during: probe block outer") }, "names the OUTERMOST bracket\n\(log)")
        XCTAssertFalse(lines.contains { $0.contains("during: probe block inner") }, "the nested bracket never replaces the outer name")
        XCTAssertTrue(lines.contains { $0.contains("slow") && $0.hasSuffix("probe block outer") }, "a slow bracket is logged with its own duration")
        XCTAssertTrue(lines.contains { $0.contains("main thread at +") }, "a stall carries the main thread's stack")
        XCTAssertTrue(lines.contains { $0.contains("watchdogProbeBlock") }, "the sampled stack names the function the main thread was inside\n\(log)")
        XCTAssertEqual(MainActivity.snapshot, "no marker")
    }

    func testAResponsiveMainThreadLogsNothing() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        let before = logText().split(separator: "\n").count
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
        XCTAssertEqual(logText().split(separator: "\n").count, before, "the log is only stalls")
    }
}
