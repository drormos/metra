# 01 · Tuner + fixed-size time signature button: report

Build 1.8.0+105. `flutter analyze` is clean and `flutter test` passes (1654 tests).

## What changed
1. **Time signature button:** now a 44×44 square like the stopwatch and gear. It shows only "4/4" / "12/8" (Saira Extra Condensed 700, 22px, optically centred). A FittedBox shrinks it rather than grow the box at large text. The subdivision note and " · 3" are gone. Its accessibility name is "Time signature 7/8, eighth notes, polyrhythm 3".
2. **Top row:** stopwatch · time signature · tuner · settings. They are four equal 44px boxes, 8px apart, with 48dp touch targets. A test checks this at 100%, 130% and 200% text with 12/8, and the title's shrink-to-fit tests still pass. The tuning fork is a vector icon (`TuningForkIcon`) with the accessibility name "Tuner".
3. **Tuner page** (`lib/src/ui/tuner_page.dart`). It uses the Settings page motion; ‹ and Android Back return. It has:
   - the note at 150px with a small muted octave;
   - the line "+12 cents · 110.8 Hz";
   - a −50…+50 meter (ticks every 5, longer every 25, a white centre tick) with a red needle that eases toward each reading;
   - "In tune" within ±3 cents (the needle turns white and thicker);
   - "–" and "Play a string" after 1 s of silence (the needle rests at 0, dimmed);
   - a Reference A4 stepper, 430–450 Hz, default 440, saved app-wide;
   - the muted line "The click pauses while the tuner is open".
   The page scrolls only if large text makes it taller than the screen.
4. **Behavior:** opening the tuner stops the click, and nothing restarts it. The screen stays on while the tuner is open. The microphone runs only while the page is visible: it stops on leaving and when the app is hidden, and restarts on return.
5. **Microphone permission:** asked the first time the page opens, with the line "Metra listens only while the tuner is open. Nothing is recorded or sent." on the page behind Android's dialog. If refused, the page shows that line and "Allow microphone". The button asks again, or opens the app's settings if Android won't ask any more. The page checks the permission again when you come back from settings.
6. **Pitch detection:** the McLeod Pitch Method (MPM) in pure Dart, on the phone, with no network. In tests it is within 1 cent from E2 to E6, on pure tones and on low-string-like tones (overtones louder than the fundamental, plus noise), at 44.1 and 48 kHz. TalkBack says "A, 12 cents sharp" / "A, in tune" once a reading has held for 0.5 s, at most once a second.
7. **Stage mode:** has no tuner (stage mode has its own screen without the top row).

## Decisions I made
- **Native microphone code instead of new packages:** `MicBridge.kt` uses `AudioRecord`, unprocessed input where the phone supports it. No new dependency, and it gives exactly the permission states the spec needs.
- **Sharps and flats are drawn:** ♯ / ♭ are small vector icons (in the note, and in "♭ −50 … +50 ♯"). Our fonts have no ♯/♭, and the app bans symbol glyphs because Android may draw them as emoji. Note names use sharps only (A♯, never B♭).
- **"In tune" replaces the whole cents line,** as the spec says, so the Hz isn't shown while in tune.
- **Off Android** (Mac, iPhone) the tuner opens but never hears anything ("Play a string"). It's Android-only for now.
- **Saved data:** format version 10 adds `referenceA4`; older files migrate to 440.

## Screenshots (docs/design/screens/)
These are rendered in a widget test (real fonts, 360dp, 115% text), **not captured on the phone**: no phone was connected.
`tuner-top-row-12-8-115.png`, `tuner-sharp-115.png`, `tuner-in-tune-115.png`, `tuner-sharp-115-daylight.png`, `tuner-in-tune-115-daylight.png`, `tuner-a-sharp-flat-115.png`, `tuner-silent-115.png`, `tuner-refused-115.png`.

For the designer: at 115% on 360dp, "Reference A4" wraps onto two lines next to the stepper. With a sharp, the octave digit sits a little lower and further right than without one.

## Store and privacy (for Dror)
- **Play Data safety form:** keep "Does your app collect or share user data?" as **No**. Play doesn't count audio that is processed only on the device and never sent as collected, so don't tick "Audio". (RELEASING.md now says this.)
- **Permissions:** the app now declares `RECORD_AUDIO`. It isn't a restricted permission, so there's no extra declaration form. The Play Console will show "Microphone" on the listing's permissions.
- **Privacy policy:** I updated `PRIVACY.md` (effective 2 November 2026). It has a new "The tuner and the microphone" paragraph (it listens only while the tuner page is open; the sound is analysed on the phone and never recorded, stored or sent), and the Permissions paragraph now says the microphone is the only permission you approve. **Push it before the release goes out,** so the hosted policy matches the build.
- `store/listing.md` has a TUNER section (the full description is 3033 / 4000).

## Please check on the phone (text at 115%)
- The top row: four equal squares; "12/8" fits; the title still shrinks.
- The first time you open the tuner: the line shows, then Android's dialog. Refuse, then tap "Allow microphone": it asks again. Refuse twice ("don't ask again"): the button opens Metra's settings, and allowing it there and coming back starts the tuner.
- Tune a real string (or a tone from another device): the low E reads steadily, the needle moves smoothly, and "In tune" shows at ±3 cents.
- Open the tuner while the click plays: it stops and stays stopped after Back. Leave the app with the tuner open: the microphone indicator (green dot) goes off.
- Check the screen stays on while the tuner is open.
