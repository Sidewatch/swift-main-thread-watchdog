# Swift Main Thread Watchdog

The beach ball, as evidence: a watchdog thread that logs every main-thread stall with the operation that was running and the main thread's stack.

- Module `MainThreadWatchdog` in `Sources/MainThreadWatchdog`; tests in `Tests`; `swift test` is the whole check.
- Swift 6 language mode, tools 6.2, macOS 14+, no dependencies.
- Part of the Sidewatch package family; every package follows the same layout and PR rules.

## Module map

- `Core/` — the engine: MainThreadWatchdog (the ping thread), MainThreadSampler (suspend / walk frames / resume; NEVER allocates while the thread is suspended)
- `Support/` — MainActivity (named brackets + standing context), StallLog (append-only, off-thread)

## Rules of this package

- The sampler must not allocate between `thread_suspend` and `thread_resume`: the main thread may hold the malloc lock.
- The watchdog decides on elapsed time, not on the timeout firing (kernel timer leeway hid stalls otherwise).
- The watchdog thread is `.userInitiated`, not `.utility`, for the same reason.

## Rules

Read `CONTRIBUTING.md` before changing anything: it is the layout and PR rulebook for this package.
