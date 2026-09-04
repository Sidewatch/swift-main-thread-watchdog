# Swift Main Thread Watchdog

The beach ball, as evidence. A watchdog thread pings the main queue every 100 ms; when a ping goes unanswered for 250 ms it writes a stall record: how long, which named operation was running, what the app was showing, and the main thread's stack at that moment (and two seconds later if it is still stuck). An app that never stalls never writes a byte.

Built for Sidewatch after three headless floods cleared the obvious suspect and the real stalls turned out to be somewhere nobody had guessed. Every stall a user feels is the main thread not answering; this writes down what it was doing so the next one can be fixed instead of theorised about.

## Features

- 🐕 **Watchdog** — `MainThreadWatchdog.start()` on the main thread; decides on elapsed time, not on the timer firing, so kernel timer leeway cannot hide a stall
- 🏷️ **Named brackets** — `let t = MainActivity.enter("disk changes 1,240"); … t.done()`; nesting keeps the OUTERMOST name, and any bracket over 100 ms is logged on its own
- 🧭 **Standing context** — `MainActivity.context = "Str.php 6,396 lines wrap on"`; carried on every record
- 🧵 **Stack sampler** — `MainThreadSampler.sample()` suspends the main thread, walks its frame pointers without allocating, resumes, then symbolicates with Swift names demangled (arm64)
- 📝 **Stall log** — `~/Library/Logs/<YourApp>/stalls.log`, written off the caller's thread; an environment variable can redirect it for harnesses
- 🪶 **Zero dependencies** — Foundation and Darwin only

## Requirements

- macOS 14+ (Apple silicon for stack samples; other architectures log the stall without a stack)
- Swift 6.2+ (Swift 6 language mode)

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/Sidewatch/swift-main-thread-watchdog.git", from: "0.1.0")
]
```

## Usage

```swift
import MainThreadWatchdog

// At launch, on the main thread.
StallLog.configure(directoryName: "MyApp", environmentVariable: "MYAPP_STALL_LOG")
MainThreadWatchdog.start()

// Around the paths you suspect. The name should say what and how much.
let token = MainActivity.enter("editor reload 2.8 MB")
reloadEditor()
token.done()

// Whatever the front window holds — read from the watchdog thread when a stall lands.
MainActivity.context = "Str.php 6,396 lines wrap on"
```

A record looks like:

```
2026-09-02 20:27:41.118  stall 447 ms  during: editor reload 2.8 MB  editor: Str.php 6,396 lines wrap on
    main thread at +250 ms:
      MyApp  EditorViewController.rehighlightAll() + 212
      …
```

## For agents

Read `CONTRIBUTING.md` first: the folder layout and the PR rules. `swift test` is the whole
check, and a new test must fail before the change it covers. `CLAUDE.md` / `AGENTS.md` carry a
module map.

## License

MIT © 2026 David Sherlock (ArrayPress)
