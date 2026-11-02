# 01 · Tuner + fixed-size time signature button

Spec: ui-spec.md › Main screen › 1. Top row (four 44×44 buttons, "Time signature button" (Nov 2026), "Tuner button"); › Tuner (new section); › Polyrhythm › Where it lives. Boards: "Detail · 4/4 button width" (option D), "Detail · Tuner: way in + fixed 4/4" (last column = the page).

1. Time signature button: a 44×44 square like the stopwatch and gear, showing only the time signature on one line ("4/4", "12/8"), Saira Extra Condensed 700 at 22px, centered, never changing size. Remove the subdivision note and " · 3" from it (subdivision shows as the beat ticks, polyrhythm as its lane). Update its accessibility name to keep saying the subdivision and polyrhythm ("Time signature 7/8, eighth notes, polyrhythm 3").
2. Top row: four equal buttons, 8px apart: stopwatch · time signature · tuner (tuning-fork vector icon, accessibility "Tuner") · settings. Check the title's shrink-to-fit still works at 115% text on a 360dp-wide phone.
3. Tuner page (full page, Settings-style page motion, ‹ / Back return): note name ~150px with small muted octave, "+12 cents · 111.2 Hz", −50…+50 cents meter with a smoothly eased red needle, "In tune" within ±3 cents (needle white and thicker), "–" / "Play a string" after ~1 s of silence, Reference A4 stepper 430–450 Hz (default 440, saved app-wide), and the muted line "The click pauses while the tuner is open".
4. Behavior: opening the page stops the click (no auto-restart on leaving); screen stays on; the microphone runs only while the page is visible (stop on leave/background).
5. Microphone permission: asked the first time the page opens, after the page's line "Metra listens only while the tuner is open. Nothing is recorded or sent." If refused: that line plus an "Allow microphone" button (re-ask, or open the app's settings if Android won't ask again).
6. Pitch detection: accurate to about ±1 cent on a steady guitar note, E2 (82 Hz) to E6, stable on the low strings. Pick a well-tested on-device method (e.g. YIN/MPM); no network. TalkBack announces the note and offset when it settles, at most once a second.
7. Not in stage mode.
8. Store/privacy: tell me what must change in the Play Data safety form and the privacy policy for microphone use (audio processed on the phone, never stored or sent); update store/listing.md with a TUNER line.

Tests: pitch detection on generated tones (and a few recorded guitar notes if available), cents math, silence handling, permission states, mic stops when leaving. Phone check at 115%: the top row, the tuner page tuning a real note if possible (or a tone from another device), the permission flow. Screenshots into docs/design/screens/.
