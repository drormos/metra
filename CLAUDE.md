# Metra Project Guidelines

See `PLAN.md` for phases and scope. Work one step at a time and stop for review when asked. Make technical decisions yourself and record them in `PLAN.md`; ask the user only about product behavior, in plain terms.

## Core Audio Rules (CRITICAL)
- **SOURCE OF TRUTH:** Click timing comes only from the `flutter_soloud` engine clock. Never trigger a click directly from a Dart Timer, `Future.delayed`, or the event loop.
- **SCHEDULING:** Use `playScheduled` against `getEngineTime()`; do not use `playClocked`. A Dart Timer may drive the scheduler's refill loop (wake every ~25 ms and schedule any steps that fall inside the next ~150 ms of engine time). Jitter in this refill loop must not affect click timing.
  - Compute step times as `anchor + n * interval` in doubles; never accumulate rounded `Duration`s.
  - Never schedule a step whose time is already before `now + guard`. Skip it and keep the grid (past times play "as soon as possible", which is off-grid).
  - Keep every pending handle. Cancel with `stop(handle)` only for steps later than `now + guard`, so a sounding click is never cut. Tempo changes re-anchor at the last committed step and keep the bar position.
  - While playing, call `setAudioDeviceIdleTimeout(null)` and `await startAudioDevice()` before anchoring; restore the default on stop. The default 500 ms idle stop freezes the engine clock between slow beats.
- **VISUAL SYNC:** Read `getEngineTime()` once per frame (a `Ticker`). Flash when engine time ≥ step time + visual offset. Engine time is the mix clock, which runs ahead of the speakers, so the user-adjustable offset is signed and defaults to a positive value. `getOutputLatency()` is zero unless render-ahead is enabled. Do not poll a voice's playback position.
- **ENGINE LIFECYCLE:** `SoLoud.instance.init()` runs once in `main()`; calling it again unloads every sound. Listen to `audioDeviceStartFailures` and recover with `startAudioDevice()`. Headphone/route-change events are not in the public API; don't rely on them.
- **SAMPLE RULES:** Click samples must have zero leading silence.

## Verify, Don't Guess (CRITICAL)
- Before writing engine code, read the package's metronome example (`reference_soloud/example/lib/metronome/`) and the `flutter_soloud` skills in `.claude/skills/`.
- **READ-ONLY:** `reference_soloud/` is reference material. Never edit it or import from it; the app depends on the pub package only.
- Use only APIs confirmed in those sources. If cancelling or rescheduling already-scheduled sounds isn't supported, say so instead of inventing workarounds.

## Architecture Rules
- **STATE MANAGEMENT:** No metronome state inside `StatefulWidget`s. Use a decoupled `ChangeNotifier` (`MetronomeController`) from day one.
- **AUDIO BOUNDARY:** Access SoLoud only through a `ClickOutput` interface, so the scheduler and controller can be tested with a fake clock.
- **TIME MATH:** Beat times, pattern steps, and tap-tempo averaging live in pure Dart classes so they can be unit-tested.
- **TAP TEMPO:** Use `Stopwatch` (monotonic), not `DateTime`. Ignore outlier intervals; reset after 2 seconds of inactivity.

## Workflow
- **VERSION CONTROL:** Commit after every completed step.
- **RUN:** `flutter devices` to list device IDs, then `flutter run -d <id>`.
- **QUALITY GATES:** `flutter test` and `flutter analyze` must pass before a step is considered done. Each step ships its own tests; there is no separate testing step.
