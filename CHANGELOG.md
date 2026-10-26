# Changelog

All notable changes to Metra. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow the app's `version:` in `pubspec.yaml` (`X.Y.Z+build`). The top released version's What's new lines live in `assets/whats_new.md` (they are also the Play Store notes); see [RELEASING.md](RELEASING.md).

## [Unreleased]

## [1.6.0] - 2026-10-26

### Added
- Stage mode: a full-screen, play-only view of the set for gigs (from the set panel's "Stage mode" button). Big Previous / Next / Start, hold to exit, remembered across a restart.
- Settings → Keep screen on: while Metra is open (new default) or only while playing.
- Song parts: a song can be a list of parts, each with its own length, tempo (steady or gradual) and rhythm, for tempo changes, odd bars and song structure. Edited on the new parts page ("Song parts ›" in the Rhythm panel, or long-press the title), which replaces the song editor.
- For a song with parts, the main screen shows the song map in place of the tempo ruler (slide or tap to go to a part) and "Chorus · bar 3 of 8 · next: Break" under the BPM; stage mode shows the map too (tap only).

### Changed
- The song editor is replaced by the parts page.
- Every −/+ stepper repeats while held, speeding up, and its value can be typed (also the Rhythm panel's beats and Settings' visual offset).
- Vector icons everywhere instead of text symbols (some showed as colored emoji on Android).

## [1.5.3] - 2026-10-23

### Changed
- A bolder app icon that reads at home-screen size, with a themed (monochrome) version for Android 13+.

### Fixed
- A polyrhythm cell could stay lit after Stop.

## [1.5.2] - 2026-10-23

### Added
- Settings → About → Privacy policy (Google Play requires the link in the app too).

### Fixed
- A stray click from the old bar could play next to the new beat 1, or the rest of a bar could switch pattern early, when a tempo change, beat tap or song change came just before a bar-line change (a speed-up step, a count-in's end, a time signature or subdivision change).
- Changing the time signature and tapping a beat within a fraction of a second, with a polyrhythm on, could stop the click with an error.
- A damaged settings file could stop the app from loading; now the damaged file is kept aside and the other one still loads.

## [1.5.1] - 2026-10-23

### Changed
- Saved data is versioned: older files are migrated step by step on load, and songs and setlists (`library.json`) are stored apart from settings (`settings.json`). The original single file is kept until the first successful save.
- Android Auto Backup carries only the library and settings files.

### Fixed
- Loading repairs inconsistent data instead of failing: set entries for missing songs, duplicate ids, out-of-range tempos and time signatures, and a saved session that points at nothing.
- Unreadable files are kept in a `corrupt/` folder (the newest three).

## [1.5.0] - 2026-10-23

1.4.0 was never published; its changes are part of this release.

### Added
- "When I press Start" from the stopwatch button: count-in (1 or 2 bars, beats only), speed up (change by, every N bars, up to or down to a tempo) and stop after (bars or time), saved with each song.
- The Rhythm panel ("4/4") holds time signature, subdivision and polyrhythm; the button shows the subdivision note.
- Add a new song straight to a set; change a song on the main screen, then Save.
- Example songs and a set on a fresh install; What's new after each update.
- A taller list panel when its handle is dragged up.
- Large text, TalkBack and "Remove animations" support.

### Changed
- Settings replaces the menu (gear, top right), with What's new at the top and About at the bottom.
- The stopwatch and "4/4" open panels that drop down from the top row; every panel grows out of its button, closes with one continuous swipe, follows Android's predictive back gesture and has a wide grab area.
- Beat lights pulse (up, lit, down) instead of flashing; text that changes in place snaps in and brightens.
- Songs and sets are managed in the lists; the old pages are gone.

### Fixed
- The "4/4" button matches the other top-row buttons and its label is centred.
- Speed-up tempo is shown when its bar line plays.

## [1.3.0] - 2026-10-22

### Added
- Add songs to a set inside its panel, with search.
- Accessibility pass: large text, contrast, TalkBack labels, touch targets, reduced motion.

### Changed
- The old song and setlist pages are removed; each list teaches its gestures once.
- Search, the Undo bar, reorder access and sheet drags polished; standard Android behaviours (volume keys, predictive back).

## [1.2.0] - 2026-10-22

### Added
- Manage songs and sets in the dropdown lists: tap plays, long-press renames or moves, swipe removes (with Undo) or deletes (after asking).

### Changed
- Removing the song or set that's loaded hands over to the next one instead of refusing.
- Swipe feels like Android's standard; list gestures never wait for an animation.

## [1.1.0] - 2026-10-19

### Added
- Polyrhythm: a second pulse across each bar, with its own lane and sound.
- Mode tabs (Songs · Free play · Setlists) with a context row; lists open from its center button.
- Click sounds Woodblock, Beep, Cowbell and Bell.
- Tempo names on the full metronome scale.

### Changed
- Menu side panel; the old Menu page became Settings.
- BPM sized from the screen with fixed-width digits; shrink-to-fit song names.

### Removed
- The Classic click sound (saved choices load as Woodblock).

### Fixed
- Voice limit, a start race, phone calls and tolerant loading (pre-release review).

## [1.0.0] - 2026-10-16

### Added
- A sample-accurate metronome on the flutter_soloud engine clock, with background playback, lock-screen and media controls.
- Time signatures, subdivisions, tap-to-accent beats and tap tempo.
- Songs and setlists with next / previous from the screen, keyboard, pedals and lock screen.
- Speed-sensitive tempo ruler, ±1 / ±5 buttons with hold to repeat, haptics.
- Song editor with live preview; Revert / Save for changes to a loaded song.
- Stage Black and Daylight themes, per-level click volumes, visual offset.

[Unreleased]: https://github.com/drormos/metra/compare/v1.5.3...HEAD
[1.5.3]: https://github.com/drormos/metra/compare/v1.5.2...v1.5.3
[1.5.2]: https://github.com/drormos/metra/compare/v1.5.1...v1.5.2
[1.5.1]: https://github.com/drormos/metra/compare/v1.5.0...v1.5.1
[1.5.0]: https://github.com/drormos/metra/compare/v1.3.0...v1.5.0
[1.3.0]: https://github.com/drormos/metra/compare/687e31e...v1.3.0
[1.2.0]: https://github.com/drormos/metra/compare/v1.1.0...687e31e
[1.1.0]: https://github.com/drormos/metra/releases/tag/v1.1.0
[1.0.0]: https://github.com/drormos/metra/commits/b930bcf
