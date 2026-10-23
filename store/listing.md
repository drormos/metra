# Google Play store listing (default: English)

App name (30): **Metra**

## Short description (79 / 80)

A precise metronome for practice, rehearsal and the stage. No ads, no tracking.

## Full description (1809 / 4000)

Metra is a metronome for every hour you play: practice, rehearsal and the stage. The click stays exactly on time, the screen reads at a glance, and changing songs takes one tap.

ON TIME, EVERY TIME
• The click comes from the audio engine's own clock, so it doesn't drift, from 30 to 300 bpm.
• Beat lights follow the sound exactly, with an adjustable offset for Bluetooth headphones.
• Keeps playing with the screen off, from the lock screen and notification, and from a Quick Settings tile.

PRACTICE
• Count-in of 1 or 2 bars before the song.
• Speed up: add a few bpm every few bars, up to a target tempo.
• Stop after a number of bars or a length of time.
• Tap tempo, a fast tempo ruler, and ±1 / ±5 buttons.

SONGS AND SETLISTS
• Save each song with its tempo, time signature, subdivision, accents and polyrhythm.
• Build setlists, reorder them, and step through a set with Previous / Next, the lock screen, or a Bluetooth page-turner pedal.
• Change anything right on the main screen while it plays, then Save, Revert, or Save as a new song.

RHYTHM
• Any time signature, 2/4 to 12/8 and custom.
• Quarters, eighths, triplets and sixteenths; tap a beat to accent or mute it.
• Polyrhythms from 2 to 7 against the beat, in their own sound.
• Four click sounds (Woodblock, Beep, Cowbell, Bell), with volumes for accents, beats, subdivisions and polyrhythm.

MADE FOR THE STAGE
• Large, high-contrast Stage Black theme, plus a Daylight theme for bright rooms.
• Every control is big enough for a quick tap; nothing moves while you play.
• Large text, TalkBack and "Remove animations" are supported.

PRIVATE AND FREE
No ads, no account, no tracking. Metra has no internet access: your songs stay on your phone.

Made by a drummer who wanted a metronome that just works, in the practice room and on stage.

## Graphics
- App icon (512×512): `store/icon-512.png` (from `tool/icon/app-icon.png`)
- Feature graphic (1024×500): `store/feature-graphic.png` (source `store/feature-graphic.html`, rendered with headless Chrome)
- Phone screenshots (9:16, 1560×2772, in this order): `store/screenshots/`
  1. `01-playing-in-a-set.png`: Northbound playing in "Fri · The Blue Room", beat 2 lit, 120 bpm
  2. `02-set-list.png`: the set list open at 4/12
  3. `03-when-i-press-start.png`: count-in and speed up on
  4. `04-rhythm-panel.png`: 7/8, eighths, polyrhythm 3
  5. `05-polyrhythm-playing.png`: 3 against 4 playing, both lanes lit
  6. `06-daylight.png`: the main screen in Daylight

## Redoing the screenshots
Real captures from a phone (see the phone skill), with the demo library in `store/demo/`:
1. `flutter test tool/store/gen_demo_test.dart` regenerates `store/demo/` (edit the songs there).
2. Push it into the debug app: `adb shell am force-stop com.dror.metra.debug`, then for `library` and `settings`: `adb exec-in run-as com.dror.metra.debug sh -c "cat > files/<name>.json" < store/demo/<name>.json`. This replaces the debug app's songs.
3. Clean status bar: `adb shell settings put global sysui_demo_allowed 1`, then `am broadcast -a com.android.systemui.demo -e command enter` (and `clock -e hhmm 1200`, `notifications -e visible false`); `-e command exit` afterwards. Turn off overlays such as edge-panel handles.
4. Capture with `adb exec-out screencap -p`, then pad to 9:16 (Play rejects sides more than ~2:1): `sips --padToHeightWidth 2772 1560 --padColor 000000` (Daylight: `F3F1EC`).
