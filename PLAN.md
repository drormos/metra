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
**Goal:** Apply `docs/design/ui-spec.md` and its references (`main-screen`, `free-play`, `beat-states`, `setlist-picker`, `set-switcher` `.reference.html`; design-tool files used for sizes and colors, not ported). Screens the spec lists as "not designed yet" (song editor, setlist editor, song library, time-signature picker, settings) are built plainly with the theme and fonts. macOS runs the phone layout (no dedicated wide layout). Principle: opening any sheet or editor never stops or changes the click. One commit per step. Steps 1–4 are done.

1. **Theme + fonts (done):** Color tokens for Stage Black (dark) and Daylight (light) in one theme file (`ThemeExtension`), including the per-type beat colors (resting/sounding), muted fill and line, subdivision ticks and tempo needle, no hardcoded colors in widgets (including the current sheet color). Bundle Saira Extra Condensed 600/700 and Saira 500/600 as assets with their OFL license. Theme setting System (default) / Dark / Light, saved with the library. Sentence-case labels ("Start", "Stop", "Tap", "bpm").
2. **Main screen layout (done):** Top row (song title; subdivision button with vector note icons cycling 1→2→3→4; time-signature button opening a plain picker; settings), BPM with "bpm" and the Italian tempo name, filled ±10/±1 row, Start/Stop (2/3) + Tap (1/3), flexible space above and below the BPM. Fits small phones (the BPM shrinks first; tested at 360×640 and 320×568). Removes the old dropdowns and the app bar. Until step 5 replaces it, the ◀ song ▶ row with a "Songs & setlists" button stays as a stand-in.
3. **Beat blocks (done):** One whole block per beat (never split), with a thin subdivision strip under it (one tick per click of that beat; hidden at subdivision 1). Only what is sounding lights: a block shows its type in its resting color and switches to its sounding color for the duration of its beat; a tick lights only while its click sounds. Types: accent (red), regular (grey/white), muted (dark with one diagonal line; never lights; its subdivision ticks still light). Tapping a block cycles regular → accent → muted → regular (as today; the spec still lists accent → regular → muted; regular → accent → muted was chosen so the first tap on a plain beat accents it). Driven by the existing engine-clock ticker and flash offset. Works from 2 to 12+ beats. Reference: `docs/design/beat-states.reference.html`. The whole beat column (block + strip, padded) is the tap target, so it meets the 44 px minimum.
4. **Tempo ruler (done):** 14 px per bpm, minor tick per bpm, labeled major tick every 5, fixed red needle, highlighted current label. Horizontal drag in 1-bpm steps, clamped to 30–300. Speed-sensitive (changed after trying it): slow moves are 1 bpm per 14 px for precise picking, faster moves cover up to 4× more; a fast swipe glides on and slows to a stop, a slow drag stops where the finger lifts, touching the ruler stops a glide. Tempo names: Largo < 66, Adagio 66–75, Andante 76–107, Moderato 108–119, Allegro 120–167, Presto ≥ 168. Saving to disk is coalesced (one write at a time, always of the latest state; no timers), so a drag doesn't write a file per bpm.
5. **Modes, data and tokens (done):**
   - Two modes, Free play and a setlist. First launch opens in Free play; afterwards the app reopens in the last-used state (same setlist at the same song, or Free play): save the active setlist id and position with the library.
   - Shared song library (already the model: songs once, setlists reference ids in order). "All songs" stops being a stepping list: previous/next and the pedal keys only work inside a setlist.
   - Theme tokens added/renamed per the updated spec: sheet background, divider, selected row (#242424 / #DAD5CB, for the current row in the picker views) and "accent" (needle, current-song marker, checkmarks; replaces the needle token). Sheets use the sheet background; the ruler's rules use the divider.
   - Decisions: loading a library song in Free play shows its name as the title but stays in Free play; with a setlist loaded, a song in the set jumps to its position, one outside it shows "– of 12" and next returns into the set. Switching to Free play while playing changes only the mode, never the click. macOS opens as a phone-sized window (resizable).
   - Remove the wide side panel: macOS runs the phone layout.
6. **Setlist group (done):** Framed (2px border, 4px radius), identical size and position in both modes: a 44px header, a 14px gap, a 68px button row.
   - Setlist mode: header is an outlined dropdown control (list icon, set name; "4 of 12" muted and a chevron) that opens the picker; previous/next filled buttons with the neighbouring song's name and bpm, disabled at the ends.
   - Free play: header is plain text "Free play"; row holds an outlined "Choose a setlist" button with chevron (opens the picker) and a 52×52 outlined "+" ("New setlist", opens the setlist editor), content vertically centred. With no setlists at all: one outlined full-width "Create your first setlist".
   - Replaces the ◀ song ▶ stand-in and the "Songs & setlists" button. Until steps 7–8: the header and "Choose a setlist" open the old song panel, and "+" / "Create your first setlist" ask for a name and load the new (empty) set.
7. **Setlist picker sheet (done):** Bottom sheet leaving the top ~104px of the main screen visible and dimmed; drag handle; swipe down or tap outside to close. Playback continues throughout.
   - Songs view (`setlist-picker.reference.html`): set name as a button with chevron (to "What to play"), outlined "Edit" (setlist editor), "12 songs" muted, 60px rows (position, name, tempo in Saira Extra Condensed, time signature muted; current song on a highlighted row with a red play marker), "Song library" at the bottom. Tapping a row loads the song (see step 9) and closes the sheet.
   - What to play view (`set-switcher.reference.html`): back chevron, "What to play", a framed Free play button ("No setlist, any tempo"), a "Setlists" label, 72px rows (name, song count; current set highlighted with a red check). Tapping a set loads its first song and returns to the songs view. "New setlist" (filled) and "Song library" (outlined) at the bottom.
   - Opens on the songs view with a setlist loaded, on What to play in Free play (no back button then). Free play closes the sheet. Until Phase 5, "Song library" opens the old song panel.
8. **Setlist editor + library pick mode (done)** (`setlist-editor.reference.html`, `library-pick.reference.html`):
   - Setlist editor, a full screen opened from "Edit" in the picker, "+" (New setlist) and "New setlist" in What to play. Top bar Cancel / "Setlist" / Save. Name field, song count and a muted "Drag to reorder". 60px rows: ✕ (removes from this set only; no confirmation, a short "Removed" message with Undo), position, name, tempo, time signature, drag handle. The same song may appear more than once. Bottom: "Add songs" (filled, opens pick mode) and red "Delete setlist" (confirms; never deletes songs). "Start with all songs" when creating a set stays as a shortcut.
   - Library pick mode, a full screen: Cancel and "Add to <set>", search field, the song list with a checkbox per row ("Already in this set" shown but still addable). Bottom: "New song" (outlined; creates a song and adds it; until the song editor exists, it saves the current settings under a name) and "Add N songs" (filled primary, disabled until something is checked).
9. **Behaviors:** BPM centring fix: the number alone is centred on the screen and "bpm" hangs off its right side near the baseline, not counted in the centring (today the pair is centred). Next/previous or choosing a song while playing restarts immediately on beat 1 at the new tempo (engine change: re-anchor on the next safe click instead of the next bar line); while stopped it only loads. Keep the screen awake while playing. Opening sheets/editors never changes the click.
10. **Daylight check:** Check every Daylight color on a real screen.

## Phase 5: Song Editor
**Goal:** The designed song editor (`docs/design/ui-spec.md` "Song editor", `docs/design/song-editor.reference.html`): a full screen for setup, not a sheet. One commit per step.

1. **Model:** The pattern rows map directly to `MetronomePattern.steps`: beat steps cycle normal → accent → silent; subdivision cells toggle soft ↔ silent. Add per-step editing (`toggleCell`) and builders that keep existing beat and cell states where possible when the beat count or subdivision changes (new cells start on). Fix the main screen's beat-dot tap (`cycleBeat`), which currently rebuilds the bar and would wipe single-cell mutes.
2. **Screen:** Top bar (Cancel, "Song", Save as a small primary button; Cancel with unsaved changes asks to discard). Name field (Saira Extra Condensed). Tempo (~84px) with filled −/+ (long-press repeats) and an outlined "Tap tempo"; in x/8 the tempo counts eighths. Time signature: beats −/+ (1–16), "/", a 4 | 8 segmented control (selected = filled white, black text). Subdivision: four options with the vector note icons (selected = filled white). Pattern: one row per beat (number, 64×48 beat button in main-screen colors, then one 48px cell per remaining subdivision: on = border color, off = muted fill with the diagonal line). Usage note naming the setlists that use the song; red "Delete song" at the very bottom, confirming and naming those setlists.
3. **Opening and saving:** Tap the song title on the main screen to edit the current song; long-press a row in the setlist picker to edit that song. Saving changes the song everywhere (shared library) and, if it is the loaded song, applies to the click immediately.
4. **Live preview:** A sticky outlined "Preview" button (becomes "Stop"). While previewing, every edit is heard immediately. Leaving the editor stops the preview and restores whatever the main screen was doing (same tempo, pattern and playing state). There is one engine, so preview temporarily takes over the scheduler; opening the editor alone never changes the click.
5. **Song library, browse mode** (`song-library.reference.html`), after the editor since rows open it: a full screen from "Song library" in the picker and What to play. Top bar: back chevron, "Song library", outlined "New song" (opens the editor on a new song). Search field; song count with a sort control (A–Z default, or Recently edited). 64px rows: name, a muted line naming the setlists that use it ("Friday set, Rehearsal", "3 setlists", "Not in a setlist"), tempo, time signature. Tapping a row opens the song editor. Data: songs gain an "edited at" time for the Recently edited sort (older files: treated as oldest).

