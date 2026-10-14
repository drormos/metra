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
- Timing of changes while playing, chosen for responsiveness while staying on the pulse:
  - Beat accent taps: from the next click (`replaceLevels`).
  - Subdivision: from the next beat, bar position kept (`switchAtNextBeat`).
  - Time signature: the next beat starts a bar in the new meter (`switchAtNextBeat(restartBar: true)`).
  - Song switch: at the next bar line (`switchAtNextBar`), so a new song starts on beat 1.
  - ±BPM: at the next step.
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
   - `LibraryPanel`: setlist picker (or all songs), tap a song to load it, save current settings as a song (added to the selected setlist), reorder by drag, rename, add/remove from setlists, delete with confirmation. The loaded song's name shows above the beat dots.
   - Next/previous song through the selected setlist (or all songs), stopping at the ends rather than wrapping: ◀ ▶ around the song name, Page Up/Down and ←/→ keys (Bluetooth page-turner pedals), and previous/next in the Android notification and lock screen.
   - Layout by width, not platform: from 800 px wide the panel sits beside the metronome; narrower windows open it as a sheet from the app bar.
4. **Expanded Patterns:** UI for 3/4, 6/8, 7/8 and subdivisions (eighths, triplets, sixteenths), mapped to the Phase 1 `MetronomePattern` model.
   - Time signatures 2/4, 3/4, 4/4, 5/4, 6/8, 7/8, 9/8, 12/8. In x/8 every eighth clicks and the BPM counts eighths; `beatUnit` is display-only.
   - Subdivisions 1–4 per beat, played as a new `soft` level (normal click at 40% volume) so the beat stays clear.
   - One dot per beat; tapping cycles normal → accent → silent, for groupings like 7/8 as 2+2+3. Changing the subdivision keeps custom accents; changing the time signature resets them. See the change-timing decision below.
   - Drift test covers triplets on the real engine.

## Phase 3: Audio Assets & Polish
1. **Click Sounds:** Selectable click profiles (e.g. woodblock, digital beep, cowbell), all with zero leading silence.
   - Classic, Woodblock, Beep, Cowbell: synthesized by `tool/generate_clicks.dart` (no licensing), peak-normalized (accent 0.9, normal 0.7), first sample at full level; a test checks every file.
   - Picked in the settings sheet (plays a sample while stopped), saved with the library, applies to clicks scheduled from then on.
2. **UI Polish:** Superseded by Phase 4.

## Phase 4: UI Redesign
**Goal:** Apply the main-screen design in `docs/design/ui-spec.md` (target: `docs/design/main-screen.png`; exact sizes and colors: `docs/design/main-screen.reference.html`, a design-tool file used as reference only, not ported). Screens the spec lists as "not designed yet" are built plainly with the new theme and fonts. One commit per step.

1. **Theme + fonts:** Color tokens for Stage Black (dark) and Daylight (light) in one theme file (`ThemeExtension`), no hardcoded colors in widgets (including the current sheet color). Bundle Saira Extra Condensed 600/700 and Saira 500/600 as assets with their OFL license. Theme setting System (default) / Dark / Light, saved with the library. Sentence-case labels ("Start", "Stop", "Tap", "bpm").
2. **Main screen layout:** Top row (song title; subdivision button with vector note icons cycling 1→2→3→4; time-signature button opening a plain picker; settings), BPM with "bpm" and the Italian tempo name, filled ±10/±1 row, Start/Stop (2/3) + Tap (1/3), flexible space above and below the BPM. Fits small phones (the BPM shrinks first). Removes the old dropdowns and the ◀ song ▶ row.
3. **Beat blocks:** One block per beat, one cell per subdivision; cells light as each step plays and stay lit until the bar ends (downbeat / beat / subdivision / inactive colors), driven by the existing engine-clock ticker and flash offset. Works from 2 to 12+ beats. Tapping a block cycles that beat normal → accent → silent (kept from Phase 2); accented beats use the downbeat color, silent beats show as an empty outline.
4. **Tempo ruler:** 14 px per bpm, minor tick per bpm, labeled major tick every 5, fixed red needle, highlighted current label. Horizontal drag in 1-bpm steps, clamped to 30–300; no momentum, it stops where the finger lifts. Tempo names: Largo < 66, Adagio 66–75, Andante 76–107, Moderato 108–119, Allegro 120–167, Presto ≥ 168. Saving to disk is debounced so a drag doesn't write a file per bpm.
5. **Setlist group:** Framed group with header (setlist name, "4 of 12", chevron → setlist picker sheet built from the current song panel) and previous/next buttons showing the neighbouring song's name and bpm, disabled at the ends. When no setlist is loaded the group is replaced by a small "Choose a setlist" button (the spec hides the group, which would leave no way to reach songs). The loaded setlist and position are saved, so reopening the app returns to them.
6. **Behaviors:** Next/previous while playing restarts immediately on beat 1 at the new song's tempo (engine change, below); while stopped it only loads. Keep the screen awake while playing. Keyboard and pedal shortcuts keep working.
7. **Daylight check + wide layout:** Check every Daylight color on a real screen. macOS wide layout built plainly (not designed yet).

