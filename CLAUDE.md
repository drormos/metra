# Metra Project Guidelines

See `PLAN.md` for phases and scope. Work one step at a time and stop for review when asked.

## Core Audio Rules (CRITICAL)
- **SOURCE OF TRUTH:** Click timing comes only from the `flutter_soloud` engine clock. Never trigger a click directly from a Dart Timer, `Future.delayed`, or the event loop.
- **SCHEDULING:** A Dart Timer may drive the scheduler's refill loop (e.g. wake every ~25–50 ms and schedule any beats that fall inside the next 100–200 ms of engine time). Jitter in this refill loop must not affect click timing.
- **VISUAL SYNC:** The visual indicator flashes when engine time reaches each beat's scheduled time, minus the user-adjustable latency offset. Do not poll a voice's playback position.
- **SAMPLE RULES:** Click samples must have zero leading silence.

## Verify, Don't Guess (CRITICAL)
- Before writing engine code, read the package's metronome example (`reference_soloud/example/lib/metronome/`) and the `flutter_soloud` skills in `.claude/skills/`.
- **READ-ONLY:** `reference_soloud/` is reference material. Never edit it or import from it; the app depends on the pub package only.
- Use only APIs confirmed in those sources. If cancelling or rescheduling already-scheduled sounds isn't supported, say so instead of inventing workarounds.

## Architecture Rules
- **STATE MANAGEMENT:** No metronome state inside `StatefulWidget`s. Use a decoupled `ChangeNotifier` (`MetronomeController`) from day one.
- **TIME MATH:** Beat times, pattern steps, and tap-tempo averaging live in pure Dart classes so they can be unit-tested.
- **TAP TEMPO:** Use `Stopwatch` (monotonic), not `DateTime`. Ignore outlier intervals; reset after 2 seconds of inactivity.

## Workflow
- **VERSION CONTROL:** Commit after every completed step.
- **RUN:** `flutter devices` to list device IDs, then `flutter run -d <id>`.
- **QUALITY GATES:** `flutter test` and `flutter analyze` must pass before a step is considered done.
