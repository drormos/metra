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
   - The offset is signed and user-adjustable, default 0 ms (measured on MacBook speakers).
   - The engine clock advances in mix-buffer steps (~46 ms at 2048 frames). Extrapolate between clock updates with the Ticker's (monotonic) frame time so the flash lands on the right frame.
6. **Tap Tempo:** `Stopwatch` intervals from the last 4 taps. Drop intervals more than 30% off the median. Reset after 2 s idle. Clamp to 30–300. Apply through the controller's tempo-change path.
7. **Acceptance Test (Drift Check):** `integration_test/drift_test.dart` runs the real engine on macOS, captures the mixer output, and checks every click against the ideal grid (±2 samples).
   - Automated: 30, 60, 120 and 300 BPM (`--dart-define=DRIFT_SECONDS=300` for the 5-minute runs), a mid-bar tempo change, stop/start, and a 1 s isolate stall (stands in for App Nap).
   - Manual: headphones plugged and unplugged during playback, and the macOS app hidden for 60 s. **Not yet run; revisit before release.**
   - Run: `flutter test integration_test/drift_test.dart -d macos`.

### Engine Decisions
- `playScheduled` + `getEngineTime()`, not `playClocked` (no 2 s window, known engine time per step for visuals and tempo changes).
- Render-ahead ring off (`renderAheadFrames` unset). Scheduled clicks don't need low reactive latency; the visual offset is user-calibrated.
- `bufferSize` stays at the default 2048: scheduling is sample-accurate regardless, larger buffers avoid dropouts, and visual jitter is handled by extrapolation (Phase 1 step 5).
- Max active voices raised to 32 for headroom at fast subdivisions.
- A pattern or song change while playing finishes the current bar, then switches tempo and pattern on the next bar line (`ClickScheduler.switchAtNextBar`). Plain ±BPM changes still apply at the next step.
- Visual offset defaults to 0 ms (measured by eye on macOS: 0 ms on built-in speakers, 20 ms on a USB-dongle wireless headset), adjustable in the settings sheet from −200 to +500 ms in 10 ms steps to cover Bluetooth output. Not persisted until Phase 2.
- The drift check captures the mixer output rather than recording the speakers. The engine clock is paced by the output device, so the mix timeline is what plays; capture must use the engine's channel count (it does not convert channels).
- No audio focus on Android: focus would pause the user's music, and playing along with a track is a core use. Instead the click stops when a personal output (headphones, Bluetooth, USB audio) disappears, so it never jumps to the speaker. (audio_session's "becoming noisy" event only fires with focus, so this watches device removal.)
- Android 13+ notification permission is requested once at first launch (`MainActivity`); declining only hides the Play/Stop notification, playback still works.
- Audio device failures trigger one automatic `startAudioDevice()` retry; if it fails, the controller exposes the error for the UI.

## Phase 2: Persistence, Setlists & Mobile Background
**Goal:** Quick-access songs and setlists, reliable mobile playback.
1. **Background Audio:** Integrate `audio_service` so playback continues with the Android screen off or the app in the background. The refill loop must keep running in the background; use a long lookahead while backgrounded.
   - `MetronomeAudioHandler` mirrors the controller into audio_service: playing starts a `mediaPlayback` foreground service with Play/Stop in the notification and lock screen; swiping the app away stops.
   - Verified on a real Android phone (speaker): keeps playing on the lock screen, when minimized, and alongside other music; stops when the app is swiped away. Unplugging headphones stops the click.
   - `MainActivity` must extend `AudioServiceActivity`. A plain `FlutterActivity` makes audio_service start a second engine that runs `main()` again and re-initializes SoLoud.
2. **Persistence:** Simple JSON file storage for songs, setlists, and the visual latency offset.
   - One `library.json` in the app support folder (`LibraryStore`): written to a temp file then renamed, so a crash mid-save can't corrupt it; an unreadable file is kept aside as `library.json.corrupt-<time>` and the app starts empty.
   - `LibraryController` owns songs and setlists (deleting a song removes it from setlists) and saves on every change.
   - Also restores the last session: tempo, pattern and flash offset.
3. **Setlist UI:** Side panel (macOS) or sheet (Android) for switching songs without stopping playback. A song switch applies tempo and pattern at the next bar boundary.
4. **Expanded Patterns:** UI for 3/4, 6/8, 7/8 and subdivisions (eighths, triplets, sixteenths), mapped to the Phase 1 `MetronomePattern` model (UI only; the model already supports these).

## Phase 3: Audio Assets & Polish
1. **Click Sounds:** Selectable click profiles (e.g. woodblock, digital beep, cowbell), all with zero leading silence.
2. **UI Polish:** Final high-contrast theme, animations, and responsive layouts for desktop and mobile.
