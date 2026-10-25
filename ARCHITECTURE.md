# Metra architecture

A one-page map for anyone (or any agent) about to change the code. Rules that must hold are in [CLAUDE.md](CLAUDE.md); decisions and their reasons in [PLAN.md](PLAN.md) and [docs/history.md](docs/history.md); the product design in `docs/design/ui-spec.md` (the designer's, read-only for us).

## Layers

```
flutter_soloud engine clock
  └─ audio/      ClickOutput (interface) ← SoloudClickOutput; ClickScheduler (lookahead)
       └─ controller/  MetronomeController (ChangeNotifier: tempo, pattern, transport, runs)
                       LibraryController (songs, sets, session, saving) ── storage/LibraryStore
            └─ ui/    MetronomeScreen and its panels; widgets read the controllers, hold no metronome state
model/ (pure Dart, no Flutter UI): MetronomePattern, Library/Song/Setlist, OnStart, ClickVolumes, migrations
timing/ (pure Dart): BeatGrid, TapTempo, EngineClockSmoother
platform/: AndroidBridge (MainActivity, Quick Settings tile, calls)
```

Timing never comes from Dart timers: the scheduler hands every click to the engine ahead of time (`playScheduled` at engine times), a 25 ms timer only tops it up, and visuals read the engine clock once per frame. Tests replace the engine with `test/audio/fake_click_output.dart` (a clock you set).

## Startup (`lib/main.dart`)
1. iOS audio session; `SoLoud.init()` once; `MetronomeController(SoloudClickOutput)`; lifecycle listener (longer lookahead in the background).
2. `LibraryController.load(LibraryStore(<app support>/library.json))`: migrates old files, repairs, restores settings into the controller (`attach`).
3. `WhatsNew.load()`; on a fresh install `addExamples()`; `detachSong()` (a fresh launch always starts in Free play).
4. Android: `audio_service` media session (lock screen, notification), headphone guard, Quick Settings tile, call pause.
5. `runApp` → `MetronomeScreen`.

## Where things are

| Area | Files | Notes |
|---|---|---|
| Click scheduling | `audio/click_scheduler.dart`, `timing/beat_grid.dart` | Steps are absolute indices; `BeatGrid` maps them to engine times (doubles, re-anchored on tempo changes). Pending switches (`switchAtNextBar/Beat`), count-in (`_begin`), runs (`RunPlan`: tempo on any beat, end at a bar line), polyrhythm pulses. |
| Transport and state | `controller/metronome_controller.dart` | `play/stop/loadSong/applyEdit`; `onStart` (count-in, speed up, stop after); `startBpm` (the tempo outside a run: what songs compare and save). |
| Library and session | `controller/library_controller.dart` | Modes (Free play, Single song, setlist), next/previous, unsaved changes (`songChanged`, Revert, Save, Save as new), one-time tips (`tipSeen`). Every change saves (coalesced). |
| Saved data | `model/library.dart`, `model/library_migrations.dart`, `storage/library_store.dart` | Two files (`library.json`, `settings.json`), versioned; migrations on raw JSON; `Library.repaired()`. Any change: the data-format-change skill. |
| Main screen | `ui/metronome_screen.dart` | Top row (title, stopwatch, "4/4", gear), beat blocks, BPM, tempo line (`_TempoLine`, `_RunLine`), ruler, ±buttons, Start/Tap, `SetlistGroup`. |
| Beat lights | `ui/beat_indicator.dart`, `ui/poly_lane.dart` | Per-frame from the engine clock; `beatPulse` (up, lit, down). |
| Bottom lists | `ui/setlist_group.dart` (tabs, context row), `ui/quick_pick.dart` (set panel, sets view, Songs list, picker), `ui/swipe_row.dart` (swipe / long-press / reorder) | Opened from the context row's center button. |
| Top panels | `ui/top_panel.dart`, `ui/time_signature_sheet.dart` (Rhythm), `ui/on_start_sheet.dart` (When I press Start), `ui/value_stepper.dart` | A `PopupRoute` whose barrier only blocks semantics, so the top row stays usable. |
| Panel motion | `ui/panel_motion.dart` | Shared by top and bottom panels: grow from the button, 1:1 drag, continuous fling, grab strip, predictive back. |
| Text and motion | `ui/motion.dart` (`BrightenSwap`, `ArriveLeave`, `Arrive`), `ui/fit_text.dart`, `ui/tabular_text.dart` | "Snap in, soft brighten"; fixed digit slots. |
| Theme | `ui/theme.dart` (`MetraColors`, `MetraMotion`, `MetraFonts`) | Every color is a token; a test forbids hardcoded colors in widgets. |
| Stage mode | `ui/stage_screen.dart`, `controller/keep_awake.dart` | Shown instead of the main screen while `LibraryController.stageMode`; taps settle into one restart. |
| Settings, About | `ui/settings_screen.dart`, `ui/about.dart`, `model/whats_new.dart` (`assets/whats_new.md`) | |
| Android | `android/app/src/main/kotlin/.../MainActivity.kt`, `PlaybackTile.kt`, `res/xml/` (backup rules) | |

## Glossary (spec words → code)

| Spec | Code |
|---|---|
| Free play / Single song / setlist mode | `LibraryController`: no song / `singleSong` / `activeSetlist` |
| Mode tabs, context row, center button | `SetlistGroup` |
| Set panel, sets view, Songs list, song picker | `QuickPick` (`QuickPickKind.set` / `sets` / `songs`, `_pickerPanel`) |
| Top panel, Rhythm panel, When I press Start | `TopPanel.toggle`, `TimeSignatureSheet`, `OnStartSheet` |
| Count-in, speed up, stop after ("a run") | `OnStart` (`countIn`, `speedUp`, `stopAfter`; `runs`), scheduler `RunPlan` |
| Up to / Down to | `OnStart.upTo`, `limitLabel` |
| Step, beat, bar, pulse | `ScheduledStep` (index, `barPosition`, `bar`), `ScheduledPulse` |
| Visual offset | `MetronomeController.visualOffset` |
| Beat types accent / regular / muted | `StepLevel.accent` / `normal` / `silent` (subdivisions `soft`) |
| Stage mode | `StageScreen`, `LibraryController.stageMode` / `enterStageMode` / `exitStageMode` |
| One-time hints and tips | `Library.tipsSeen` |
| Tempo line (under the BPM) | `_TempoLine` (tempo name, Revert · Save · Save as new, tips), `_RunLine` (count-in, progress) |

## Tests
`test/` mirrors `lib/src/` (audio, controller, model, storage, timing, ui, platform); fixtures in `test/fixtures/`. Pitfalls and patterns: [TESTING.md](TESTING.md). `integration_test/drift_test.dart` measures real engine drift on macOS.
