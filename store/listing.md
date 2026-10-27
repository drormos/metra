# Google Play store listing (default: English)

App name (30): **Metra**

## Short description (74 / 80)

A precise metronome with tempo changes, setlists and a stage mode. No ads.

## Full description (2522 / 4000)

Metra is a metronome for every hour you play: practice, rehearsal and the stage. The click stays exactly on time, the screen reads at a glance, and a whole song, tempo changes and all, plays from one tap.

ON TIME, EVERY TIME
• The click comes from the audio engine's own clock, so it doesn't drift, from 30 to 300 bpm.
• Beat lights follow the sound exactly, with an adjustable offset for Bluetooth headphones.
• Keeps playing with the screen off, from the lock screen and notification, and from a Quick Settings tile.

SONGS THAT CHANGE
• Build a song from parts: intro, verse, chorus, a one-bar 2/4 break. Each part has its own length, tempo, time signature and accents.
• Gradual tempo changes: speed up or slow down smoothly across a part, from one tempo to another.
• A heads-up before every change: "Break in 2 bars", then a beat-by-beat countdown, so you never miss a short break after a long verse.
• Optional higher click on the first beat of each new part.
• Tap any part on the song map to jump there.
• At the end: stop, loop the song, or loop the last part.

SETLISTS AND STAGE MODE
• Save songs with their tempo, rhythm, accents and polyrhythm, and build setlists.
• Step through a set with Previous / Next, the lock screen, or a Bluetooth page-turner pedal.
• Stage mode: a large, simple screen with only what you need on stage: big Previous, Next and Start, and a hold to leave, so a stray touch never takes you out.
• Change anything on the main screen while it plays, then Save, Revert, or Save as a new song.

PRACTICE
• Count-in of 1 or 2 bars, shown on screen as it counts.
• Speed up: add a few bpm every few bars, up to a target tempo.
• Stop after a number of bars or a length of time.
• Tap tempo, a fast tempo ruler, and ±1 / ±5 buttons.

RHYTHM
• Any time signature, 2/4 to 12/8 and custom.
• Quarters, eighths, triplets and sixteenths; tap a beat to accent or mute it.
• Polyrhythms from 2 to 7 against the beat, in their own sound.
• Four click sounds (Woodblock, Beep, Cowbell, Bell), with volumes for accents, beats, subdivisions and polyrhythm.

EASY ON THE EYES
• High-contrast Stage Black theme, plus a Daylight theme for bright rooms.
• Every control is big enough for a quick tap; nothing jumps around while you play.
• Large text, TalkBack and "Remove animations" are supported.

PRIVATE AND FREE
No ads, no account, no tracking. Metra has no internet access: your songs stay on your phone.

Made by a drummer who wanted a metronome that just works, in the practice room and on stage.

## Release notes (332 / 500)

The What's new lines of the release (`assets/whats_new.md`), as printed by `tool/release.sh`:

- Song parts: tempo, time-signature and gradual changes inside a song. Open the 4/4 button › Song parts, or hold the song's name.
- Stage mode: your set full screen, for gigs
- The screen stays on while Metra is open (Settings)
- The song map: slide or tap to jump to a part
- Every stepper repeats when held and takes typed numbers

## Graphics
- App icon (512×512): `store/icon-512.png` (from `tool/icon/app-icon.png`)
- Feature graphic (1024×500): `store/feature-graphic.png` (source `store/feature-graphic.html`, rendered with headless Chrome)
- Phone screenshots (9:16, 1560×2772, in this order): `store/screenshots/`
  1. `01-heads-up.png`: Glass Harbor playing in "Fri · The Blue Room", the song map, the last-bar heads-up "Break in 2 · 2/4 · 128"
  2. `02-parts-page.png`: the parts page playing, Intro's card filling, Chorus open (Gradual, Starts at 128 / Ends at 140)
  3. `03-stage-mode.png`: stage mode playing Glass Harbor, "Break in 2 bars · 2/4 · 128" over the map
  4. `04-set-list.png`: the set list open at 4/12
  5. `05-when-i-press-start.png`: count-in and speed up on
  6. `06-count-in-parts-page.png`: the parts page counting in, the tag filling, "Stop · Count-in 3 of 4"
  7. `07-rhythm-panel.png`: 7/8, eighths, polyrhythm 3
  8. `08-daylight.png`: Glass Harbor playing in Daylight, Verse bar 2 of 8

## Redoing the screenshots
Real captures from a phone (see the phone skill), with the demo library in `store/demo/`:
1. `flutter test tool/store/gen_demo_test.dart` regenerates `store/demo/` (edit the songs there).
2. Push it into the debug app: `adb shell am force-stop com.dror.metra.debug`, then for `library` and `settings`: `adb exec-in run-as com.dror.metra.debug sh -c "cat > files/<name>.json" < store/demo/<name>.json`. This replaces the debug app's songs: copy `files/library.json` and `files/settings.json` off first (`adb exec-out run-as com.dror.metra.debug cat files/<name>.json`) and push them back afterwards.
3. Clean status bar: `adb shell settings put global sysui_demo_allowed 1`, then `am broadcast -a com.android.systemui.demo -e command enter` (and `clock -e hhmm 1200`, `notifications -e visible false`); `-e command exit` afterwards. If the clock doesn't change, send the commands again once the app is open. Turn off overlays such as edge-panel handles (OnePlus Smart Sidebar). Capture at the default text size (`settings put system font_scale 1.0`, then put the phone's own value back).
4. Capture with `adb exec-out screencap -p`, then pad to 9:16 (Play rejects sides more than ~2:1): `sips --padToHeightWidth 2772 1560 --padColor 000000` (Daylight: `F3F1EC`).
