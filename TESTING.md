# Testing Metra

`flutter analyze` and `flutter test` must pass before every commit. Tests live next to what they test (`test/audio`, `test/controller`, `test/model`, `test/storage`, `test/ui`, …). These notes are the traps that each cost a failed run once.

## Clocks and playback
- **The engine clock is yours.** `FakeClickOutput` (`test/audio/fake_click_output.dart`) has a settable `time`; scheduled clicks are in `output.live` / `output.liveTimes`, pulses in `livePulses`. Nothing advances it but you.
- **Scheduler tests:** advance in refill-sized steps (`runFor` in `click_scheduler_test.dart`: `time += 25ms; scheduler.refill()`). Started steps are pruned after `ClickScheduler.retention` (1 s), so look up `stepAt` within a second of now.
- **Controller tests without widgets:** `controller.didChangeAppLifecycleState(AppLifecycleState.resumed)` calls `refill()`, so a loop of `output.time += 25ms` plus that call drives the scheduler.
- **Widget tests while playing:** never `pumpAndSettle()` (the beat lights animate every frame, so it times out). Step `output.time` and `tester.pump(20ms)` together in a loop; the visuals smooth the engine clock, so jumping the clock in one pump lags.
- **Millisecond expectations:** `Duration.inMilliseconds` truncates; a step at 461.538 ms reads 461.

## Widgets
- **Reading a scale:** `Matrix4.getMaxScaleOnAxis()` includes the z axis (always 1); read `transform.storage[0]` for the x scale.
- **`find.ancestor(...).first`** is the nearest ancestor. A panel's layout box (outside its transforms) is the `Opacity` above it in `PanelMotion`.
- **Kept-mounted widgets still match finders:** the tempo line stays in the tree (invisible) under the count-in and progress line, so `findsNothing` on it is wrong; assert on the visible label instead.
- **Baselines:** `RenderParagraph.getDistanceToBaseline` asserts outside layout. Lay out a `TextPainter` with the paragraph's `text`, `strutStyle` and `textHeightBehavior` and use `computeDistanceToActualBaseline`.
- **Real fonts aren't loaded in tests** (glyphs are test boxes). For optical checks load the asset: `FontLoader(MetraFonts.condensed)..addFont(rootBundle.load('assets/fonts/SairaExtraCondensed-Bold.ttf'))` inside `tester.runAsync`.
- **Default test screen is 800×600:** a top panel reaches 16 px above the bottom, so a "tap outside" at y 580 hits the panel. Tap in the 12 px side margin, or set `tester.view.physicalSize` (and `devicePixelRatio = 1`, with `addTearDown(tester.view.reset)`). For insets set both `padding` and `viewPadding` (the code reads `viewPadding`).
- **Keys repeat across controls:** `segment-4` exists in two segmented controls; scope with `find.descendant(of: find.byKey(...))`.
- **Repeat buttons (hold to repeat):** the timer fires inside one long `pump`, but the button's callback only sees the new value after a rebuild. Pump in 16 ms frames when counting steps.
- **Drags and slop:** panels use `DragStartBehavior.down` so they move 1:1 from the touch; anything else loses ~18 px of slop in `moveBy` checks.
- **Static state survives between tests** in the same file (e.g. `TopPanel._open`). Code that keeps static route state must check `route.isActive`.
- **Semantics:** a `GestureDetector` used only to claim gestures adds an unlabelled tappable node; give it `excludeFromSemantics: true` or the accessibility guideline test fails.

## Platform messages
- **Predictive back:** send `startBackGesture` / `updateBackGestureProgress` / `commitBackGesture` / `cancelBackGesture` on `SystemChannels.backGesture` with `{'x', 'y', 'progress', 'swipeEdge'}` via `tester.binding.defaultBinaryMessenger.handlePlatformMessage` (see `metronome_screen_test.dart`, "panel motion").
- **Haptics and clipboard:** mock `SystemChannels.platform` and record `HapticFeedback.vibrate` / `Clipboard.setData`.
- **Accessibility features:** `tester.platformDispatcher.accessibilityFeaturesTestValue = FakeAccessibilityFeatures(disableAnimations: true)` (clear it in `addTearDown`).

## Saved data
- Golden fixtures in `test/fixtures/` (one per shipped format) must load and re-save losslessly; the schema guard compares a sample library with the current version's snapshot. Changing the format: the data-format-change skill.
- Files written on the fake clock inside `testWidgets` may never finish; persistence is covered in controller and storage tests (plain `test`), and `library.flush()` before deleting a temp folder.

## Stress tests
- `test/audio/scheduler_fuzz_test.dart` and `test/storage/load_fuzz_test.dart` run seeded random sessions (300 and 400 in CI). Before a release, or after touching the scheduler or the store, run more: `flutter test test/audio/scheduler_fuzz_test.dart --dart-define=FUZZ_SESSIONS=5000` and `flutter test test/storage/load_fuzz_test.dart --dart-define=LOAD_FUZZ=4000`. A failure prints what was asked and when; replay that seed alone (`--plain-name "random session N"`).
- The real engine: `flutter test integration_test/drift_test.dart -d macos` (add `--dart-define=DRIFT_SECONDS=300` for 5-minute runs) after any scheduler change. Run the long ones under `caffeinate -dimsu` with nothing else heavy running: when the Mac idles to sleep (or the app is throttled in the background), the click stops for a while and the run fails on missing beats (seen Oct 27: ~48 s lost at 30 and 300 BPM, both passing once rerun awake).

## Proving a test
Before trusting a new test for a fix, run it against the old code (`git stash push <file>`, run, `git stash pop`) and see it fail for the right reason.
