---
name: device-qa
description: Use when a Metra build needs checking on a real phone (before a release, after audio/timing, gesture, panel, theme or accessibility work) or when asked what to test on the device.
---

# On-device checks

Pick the sections the change touches; a release runs all of them. Install with `adb install -r` (never `flutter install`).

**Timing**
- 40, 120 and 300 bpm, quarters and 16ths: steady, no drift over 2 minutes; lights land on the click.
- Count-in then song: beat 1 right on the grid. Speed up: the change lands on beat 1 of the bar.
- Tempo drag and ±buttons while playing: no stumble, no double click.

**Audio routes**
- Bluetooth headphones: connect and disconnect while playing; wired headphones unplugged (stops, no blast from the speaker). Visual offset test with the headset.
- Phone call in and out: stops, resumes after.

**Background**
- Start, lock the screen, wait 10+ minutes: still on time; lock-screen card and Quick Settings tile start and stop it.
- macOS: hide the app for 60 s while playing; no gap or drift when it comes back.

**Gestures and panels**
- Every panel (Rhythm, When I press Start, set list, sets view, Songs list, picker): opens from its button, closes on dim tap, Back, swipe (no pause) and predictive back.
- Lists: tap plays, long-press renames or moves, swipe removes with Undo.

**Accessibility**
- System font at the largest size and display size: nothing clipped or overlapping; TalkBack reads controls; "Remove animations" makes motion instant.

**Theme**
- Daylight (light) and Stage Black: contrast outdoors-bright and in the dark; no stray hardcoded colors.

**Data**
- Update over the previous build: songs, sets and settings all there. After a Play update, the What's new dot shows once.
