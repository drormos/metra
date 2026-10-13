# Metra: Cross-Platform Precision Metronome

## Overview
A sample-accurate metronome for Android and macOS, built with Flutter and `flutter_soloud`. Click timing comes from the C++ engine clock, so playback doesn't drift.

## Phase 1: Core Engine & MVP Controls
**Goal:** Sample-accurate playback, decoupled architecture, verified timing. Each step ships with its own unit tests.

1. **Data Model & Grid Math (pure Dart):**
   - `MetronomePattern`: `beatsPerBar`, `stepsPerBeat`, and a list of steps (`accent` / `normal` / `silent`). Default: 4/4 quarters, accent on beat 1.
   - `BeatGrid`: step `n` time = `segmentAnchor + n * stepInterval`, computed in doubles (never accumulate rounded Durations).
   - A tempo change starts a new segment anchored at the last committed step, keeping the bar position.
2. **Audio Engine:**
   - Init `SoLoud` once in `main()` (try/catch, expose a failure state). Load accent and normal click WAVs (zero leading silence, checked by a test).
   - `ClickOutput` interface (`now`, `schedule`, `cancel`, `cancelAll`) with a SoLoud implementation using `getEngineTime` / `playScheduled` / `stop` / `stopAudioSource`.
   - `Scheduler`: a Dart Timer (~25 ms) schedules steps inside the lookahead window (~150 ms). Skip steps already past `now + guard`. Track pending handles.
   - While playing: `setAudioDeviceIdleTimeout(null)` and `await startAudioDevice()` before anchoring; restore on stop. Listen to `audioDeviceStartFailures`.
   - Scheduler tests run against a fake `ClickOutput`.
3. **State Controller:** `MetronomeController` (`ChangeNotifier`) for BPM (30–300, clamped), Play/Stop, and pattern.
   - Tempo change: cancel pending steps later than `now + guard`, re-anchor at the last committed step, continue the bar.
   - Stop: cancel the timer, `stopAudioSource`, clear handles. Start: anchor at `getEngineTime() + lead`, step 0.
   - Lifecycle: when the app is `hidden`/`inactive`/`paused`, extend the lookahead (~2 s) to survive timer throttling (macOS App Nap). Android background playback is not guaranteed until Phase 2.
4. **UI Shell:** High-contrast numeric BPM display, `±1` / `±10` buttons, Play/Stop, engine-failure message.
5. **Visual Sync:**
   - A `Ticker` reads `getEngineTime()` once per frame. Flash when engine time ≥ step time + visual offset.
   - The offset is signed and user-adjustable, default positive (the engine clock leads audible output).
   - The engine clock advances in mix-buffer steps (~46 ms at 2048 frames). Extrapolate between clock updates with a `Stopwatch` so the flash lands on the right frame.
6. **Tap Tempo:** `Stopwatch` intervals from the last 4 taps. Drop intervals more than 30% off the median. Reset after 2 s idle. Clamp to 30–300. Apply through the controller's tempo-change path.
7. **Acceptance Test (Drift Check):**
   - Record 5 minutes at 30, 60, 120 and 300 BPM (DAW via loopback, or mixer output capture). Verify no drift against the grid.
   - Also verify: a mid-bar tempo change, stop/start, headphones plugged and unplugged during playback, and the macOS app hidden for 60 s.

### Engine Decisions
- `playScheduled` + `getEngineTime()`, not `playClocked` (no 2 s window, known engine time per step for visuals and tempo changes).
- Render-ahead ring off (`renderAheadFrames` unset). Scheduled clicks don't need low reactive latency; the visual offset is user-calibrated.
- `bufferSize` stays at the default 2048: scheduling is sample-accurate regardless, larger buffers avoid dropouts, and visual jitter is handled by extrapolation (Phase 1 step 5).
- Max active voices raised to 32 for headroom at fast subdivisions.
- A pattern change while playing restarts from the downbeat. Switching at the bar boundary comes with setlists (Phase 2 step 3).
- Audio device failures trigger one automatic `startAudioDevice()` retry; if it fails, the controller exposes the error for the UI.

## Phase 2: Persistence, Setlists & Mobile Background
**Goal:** Quick-access songs and setlists, reliable mobile playback.
1. **Background Audio:** Integrate `audio_service` so playback continues with the Android screen off or the app in the background. The refill loop must keep running in the background; use a long lookahead while backgrounded.
2. **Persistence:** Simple JSON file storage for songs, setlists, and the visual latency offset.
3. **Setlist UI:** Side panel (macOS) or sheet (Android) for switching songs without stopping playback. A song switch applies tempo and pattern at the next bar boundary.
4. **Expanded Patterns:** UI for 3/4, 6/8, 7/8 and subdivisions (eighths, triplets, sixteenths), mapped to the Phase 1 `MetronomePattern` model (UI only; the model already supports these).

## Phase 3: Audio Assets & Polish
1. **Click Sounds:** Selectable click profiles (e.g. woodblock, digital beep, cowbell), all with zero leading silence.
2. **UI Polish:** Final high-contrast theme, animations, and responsive layouts for desktop and mobile.
