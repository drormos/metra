# Metra UI Spec

Design reference for the main screen. `main-screen.png` shows the target; `main-screen.reference.html` is the design source with exact sizes and colors (a design-tool file, read it as a reference, don't port its markup).

## Theme

All colors live in one theme file. No hardcoded colors in widgets.

| Token | Stage Black (dark) | Daylight (light) |
|---|---|---|
| background | #000000 | #F3F1EC |
| surface (filled buttons) | #1A1A1A | #E3DFD6 |
| border (outlines, frames) | #2E2E2E | #CFCAC0 |
| text | #FFFFFF | #111111 |
| muted text | #8C8C8C | #5E5A52 |
| inactive beat | #1F1F1F | #CFCAC0 |
| downbeat | #FF3B30 | #D7261E |
| beat | #FFFFFF | #111111 |
| primary button | #FF3B30, label #000000 | #111111, label #F3F1EC |

Theme setting: System (default) / Dark / Light, persisted. System follows the OS.

Check every Daylight color on the real screen; values were picked for the dark theme first.

## Fonts

Bundle as assets; don't fetch at runtime.
- Saira Extra Condensed 600/700: BPM number, song title, time signature, ±buttons.
- Saira 500/600: everything else.

Labels are sentence case ("Start", "Stop", "Tap"), not all caps.

## Main screen (phone portrait, 24px side padding)

Top to bottom:

1. **Top row.** Current song title on the left (Saira Extra Condensed 700, ~38px, one line, ellipsis). On the right: time signature button ("4/4") and settings icon button, both at least 44×44, outlined, 4px radius.
2. **Beat blocks.** One block per beat in the bar, equal widths filling the row, 6px gaps, ~36px tall, 4px radius. Beats already played in the current bar are lit: downbeat in the downbeat color, the rest in the beat color. Unplayed beats use the inactive color. Must work from 2 to 12+ beats; for subdivisions, show small ticks inside each block rather than more blocks.
3. Flexible space.
4. **BPM.** Large number (~172px, tabular figures), centered, with "bpm" small and muted beside it. Below it, the Italian tempo name for the current BPM (Largo, Adagio, Andante, Moderato, Allegro, Presto), muted.
5. **Tempo ruler,** ~46px tall. Minor ticks every 1 bpm, major ticks with labels every 5, a fixed red needle at the center, the current value's label highlighted. Horizontal drag moves the ruler and changes BPM in 1-bpm steps. Clamp to 30–300.
6. Flexible space.
7. **Tempo buttons:** −10, −1, +1, +10 in one row, 60px tall, filled surface color.
8. **Start/Stop** (2/3 width, 72px, primary color, icon + label) and **Tap** (1/3 width, outlined).
9. **Setlist group,** inside a thin frame:
   - Header row: list icon and setlist name on the left; position ("4 of 12") and a down chevron on the right. Tapping it opens the setlist picker.
   - Two equal buttons: previous (left chevron, song name large, its bpm small and muted underneath) and next (mirrored, right chevron). No "Previous"/"Next" words. Disabled at the start/end of the list.
   - Hide the whole group when no setlist is loaded and give the space to the BPM area.

Every interactive element is at least 44×44, ideally 60+.

## Behavior

- Start always begins on beat 1.
- Next/previous while stopped: load that song (tempo, time signature, pattern) without starting.
- Next/previous while playing: load the song and restart immediately on beat 1 at the new tempo. Use the same clear-and-reschedule mechanism as tempo changes.
- Keep the screen awake while playing.

## Not designed yet

Setlist picker sheet, song and setlist editing, time signature / subdivision picker, settings screen, macOS wide layout, first-launch empty state, app icon. Don't invent final designs for these; build them plainly with the theme and fonts above, and they'll be designed next.
