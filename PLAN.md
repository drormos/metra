# Metra: Cross-Platform Precision Metronome

## Overview
A sample-accurate metronome for Android and macOS, built with Flutter and `flutter_soloud`. Click timing comes from the C++ engine clock, so playback doesn't drift.

## Phase 1: Core Engine & MVP Controls
**Goal:** Sample-accurate playback, decoupled architecture, verified timing.
1. **Data Model:** A `MetronomePattern` class defining a sequence of steps (accented, normal, silent). Default: 4/4 quarters.
2. **Audio Engine:** Lookahead scheduler using `flutter_soloud`. A Dart Timer tops up the scheduling window; the engine clock handles exact playback.
3. **State Controller:** A `MetronomeController` (`ChangeNotifier`) for BPM (30–300), Play/Stop, and pattern state.
4. **UI Shell:** High-contrast numeric BPM display, `±1` / `±10` buttons. Tempo changes apply at the next beat boundary (clear and reschedule the lookahead window).
5. **Visual Sync:** Beat indicator driven by each beat's scheduled time minus a user-adjustable latency offset.
6. **Tap Tempo:** `Stopwatch`-based interval averaging over the last 4 taps.
7. **Unit Tests:** Pure Dart tests for timing math, pattern generation, and tap-tempo intervals.
8. **Acceptance Test (Drift Check):** Record 5 minutes of output at 120 and 300 BPM into a DAW and verify no drift against the grid.

## Phase 2: Persistence, Setlists & Mobile Background
**Goal:** Quick-access songs and setlists, reliable mobile playback.
1. **Background Audio:** Integrate `audio_service` so playback continues with the Android screen off or the app in the background.
2. **Persistence:** Simple JSON file storage for songs and setlists.
3. **Setlist UI:** Side panel (macOS) or sheet (Android) for switching songs without stopping playback.
4. **Expanded Patterns:** UI for 3/4, 6/8, 7/8 and subdivisions (eighths, triplets, sixteenths), mapped to the Phase 1 `MetronomePattern` model.

## Phase 3: Audio Assets & Polish
1. **Click Sounds:** Selectable click profiles (e.g. woodblock, digital beep, cowbell), all with zero leading silence.
2. **UI Polish:** Final high-contrast theme, animations, and responsive layouts for desktop and mobile.
