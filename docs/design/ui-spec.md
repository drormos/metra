# Metra UI Spec

Design references (design-tool files: read them for exact sizes and colors, don't port their markup):
- `main-screen.reference.html`: main screen with a setlist loaded (stopwatch, 4/4 with subdivision, gear).
- `free-play.reference.html`: main screen in Free play.
- `free-play-song.reference.html`: Single song mode (a library song loaded without a setlist; same bar as Free play, the title shows the song, no subtitle).
- `beat-states.reference.html`: the beat blocks at three moments in a bar.
- `song-editor-collapsed.reference.html`: the song editor as it opens (pattern collapsed).
- `song-editor.reference.html`: the song editor with the pattern section expanded, full scroll length.
- `unsaved-song.reference.html`: main screen with unsaved changes to the loaded song.
- `save-as-new.reference.html`: the Save as new song dialog (in a setlist).
- `media-controls.reference.html`: lock-screen media card and compact notification (setlist, playing).
- `media-cover.reference.html`: media card in Free play (stopped) and the generated cover image.
- `time-signature.reference.html`: the Rhythm sheet (time signature, subdivision, polyrhythm).
- `settings.reference.html`: the Settings page at full scroll length (What's new on top, About at the bottom).
- `set-panel.reference.html`, `sets-view.reference.html`, `sets-search.reference.html`, `add-songs-panel.reference.html`, `songs-panel.reference.html`, `delete-confirm.reference.html`: the lists on the main screen, where songs and sets are chosen and managed.
- `drop-songs.reference.html`, `drop-sets.reference.html`, `drop-set.reference.html`: older versions of those lists (layout and sizes only; the newer references win).

## Principles

Every feature, now and later, is checked against these before it's designed. If a feature breaks one, the feature changes, not the principle.

1. **Stage first.** Designed for a drummer on a stool, mid-song, with sweaty hands and a glance. Anything used while playing must work in one tap without reading.
2. **Nothing interrupts the click.** Opening a sheet, page, list, or editor never stops or changes playback. Only an explicit action (start/stop, tempo change, choosing a song) affects it; changes land on beat or bar lines, never mid-beat.
3. **Only what sounds lights up.** Visual feedback follows the audio exactly.
4. **Nothing moves.** Free play, Single song, and setlist mode share one layout; only content changes. Start/Tap, tempo controls, and the mode tabs never change position. Fixed slots for changing text and numbers (no jitter, no reflow).
5. **Edit where you choose.** Choosing and playing happens on the main screen (tabs switch at once; lists open from the context row's center button; quick choices like time signature are a sheet). The same lists are where you manage what they show: tap plays, long-press edits (reorder in ordered lists, rename in the others), swipe takes it out (removing from a list is instant with Undo; deleting your own work, a song or a set, asks first), and the pinned bottom button adds or creates. A song's sound is edited on the main screen itself (change it, then Save). There are no separate pages for managing songs or sets; the only full page for a song is the song editor (long-press the title), kept for song-level settings that don't fit the main screen.
6. **One way to do each thing, in one place.** No duplicate routes on the main screen; one concept per job (setlists group songs, no second grouping system). 
7. **Nothing hidden that matters.** Every action has a visible control. Gestures (long-press, drag, swipe) are shortcuts or direct manipulation, never the only way. Before a Menu page is removed, each gesture it backs up needs a visible control or a one-time hint in the list.
8. **Tap does, long-press edits.** A tap plays or switches; a long-press edits: in an ordered list it lifts the row to move it, elsewhere it opens the editor or page. Never on stage-critical buttons.
9. **Size follows use and risk.** Frequent stage actions are large and filled; rare or optional ones are small, outlined, or quiet grey text. Optional things never look required.
10. **Predictable memory.** The app remembers within a session; a fresh launch starts in Free play. It never guesses across launches. One deliberate exception: stage mode is remembered until you exit it (a crash or relaunch mid-gig returns to stage mode on the same song).
11. **Plain, positive words.** Labels say what happens ("Free play", "New song"), never what's lost; the same word for the same action everywhere.
12. **Free, private, simple.** No ads, no accounts, no tracking; data stays on the phone. A new feature must not add a permission prompt.

## Theme

All colors live in one theme file. No hardcoded colors in widgets.

| Token | Stage Black (dark) | Daylight (light) |
|---|---|---|
| background | #000000 | #F3F1EC |
| sheet background (time signature sheet, dialogs) | #111111 | #ECE9E2 |
| surface (filled buttons) | #1A1A1A | #E3DFD6 |
| surface on a sheet or card (filled buttons such as − / + on #111 sheets and part cards; #1A1A1A almost disappears there) | #2A2A2A | #D8D3C9 |
| selected row (current song, current set) | #242424 | #DAD5CB |
| border (outlines, frames) | #2E2E2E | #CFCAC0 |
| divider (list rows) | #1F1F1F | #DCD8CF |
| text | #FFFFFF | #111111 |
| muted text | #8C8C8C | #5E5A52 |
| disabled text (only for things you can't use, e.g. "In this set") | #5A5A5A | #A39E94 |
| control outline (checkboxes, focused-off fields: must be seen to be used) | #6E6E6E | #8A857C |
| beat: regular, resting | #3A3A3A | #B9B4AA |
| beat: regular, sounding | #FFFFFF | #111111 |
| beat: accent, resting | #8E2620 | #E9B0AA |
| beat: accent, sounding | #FF4A3D | #D7261E |
| beat: muted (fill) | #1A1A1A | #E3DFD6 |
| beat: muted (diagonal line) | #7A7A7A | #8A857C |
| subdivision tick, resting | #2A2A2A | #D8D3C9 |
| subdivision tick, sounding | #D0D0D0 | #5E5A52 |
| accent (tempo needle, current-song marker, checkmarks) | #FF3B30 | #D7261E |
| primary button | #FF3B30, label #000000 | #111111, label #F3F1EC |

**Steppers, everywhere (one look):** − and + (and a stepper's ✕) are drawn 40px squares, each centered in a 48dp touch cell, cells edge to edge (the touch padding makes the gap); the value box sits between them. Fill: "surface" on the black background, "surface on a sheet or card" on sheets and cards. Built on the parts page (build 75); the "When I press Start" steppers were still drawn 48px then and follow this rule next.

Theme setting: System (default) / Dark / Light, persisted. System follows the OS. The Daylight values are a first pass; check them on a real screen.

## Long-press rule

Long-press means "edit it", as a shortcut. In a set's songs (an ordered list), editing means moving: long-press lifts the row and dragging reorders. In the Songs list and the sets view, long-press renames in place. Long-pressing the song title on the main screen opens the song editor. Never on stage-critical buttons (Start/Stop, tempo, previous/next, the context row's center button).

## Motion

Things never pop in or vanish; they arrive and leave quickly and softly, and nothing waits for an animation (see "Never wait for an animation"). One set of values, defined once in the theme next to the colors:

| Token | Duration | Curve | Used for |
|---|---|---|---|
| swap | 90ms | ease-out | "snap in, soft brighten" for all text that changes in place (see below) |
| leave | 220ms | ease-in (fade) + ease-in-out (height) | things that go away: hints, the Undo bar, removed rows |
| arrive | 200ms | ease-out | things that appear: hints, the Undo bar, the panel's content swapping in place |

- **Text that changes in place: snap in, soft brighten (one rule everywhere).** The BPM number, the title and set name, the tempo-name line (tempo name ↔ Revert · Save · Save as new ↔ hints ↔ "✓ Saved"), the context row's Previous/Next names and tempos, and "4/12". Only the characters that change are touched (unchanged ones in the same position stay still at full opacity; if a name's shrink-to-fit size changes, the whole name counts as changed). The old text disappears instantly; the new appears in the same frame at ~60% opacity and rises to 100% over ~90ms ease-out. Never two texts at once, never an empty gap, no movement. If the next change comes less than ~250ms after the previous one, it shows instantly at full opacity, so fast tapping never pulses. Instant at full opacity while a ±button is held, the ruler moves, or with Remove animations on. Animate only on a real change (keyed by the text). (This replaced earlier cross-fades and dissolves: those either dimmed unchanged parts or showed two big shapes at once.)
- **Hints and the Undo bar leaving (leave):** they fade out while their height smoothly closes, so the list "flows down" into the space instead of jumping. A hint over empty space (the line under the BPM) just fades.
- **Arriving (arrive):** fade in plus a 6px rise.
- **Beat lights: a short pulse, not a flash.** Each sounding light (beat block, subdivision tick, polyrhythm cell) goes up, stays lit, and comes down, timed against the gap until that light's next click (its own interval: beat, subdivision, or pulse):
  - **Up:** a very quick rise, ~30ms ease-out, started ~15ms *before* the click so it's at full brightness right on the sound (the scheduler knows click times in advance; the visual offset setting still applies on top). Fast enough to feel exact, soft enough not to look like a strobe.
  - **Lit:** stays at full for ~35% of the interval, capped at 250ms.
  - **Down:** fades to its resting color over ~35% of the interval (ease-in-out), capped at 250ms.
  - The remaining ~30% it rests, so every light visibly returns to rest before its next click, even at 300 bpm with 16ths.
  - Examples: 60 bpm quarters ≈ 30ms up, 250ms lit, 250ms down. 120 bpm eighths (250ms apart) ≈ 30ms up, ~85ms lit, ~85ms down.
- **Reduced motion** (Android "Remove animations"): swaps and arrive/leave become instant; beat lights switch fully on at the click, stay lit for the same time, and switch off with no ramp.

## Icons

- **Setlist:** "note queue": three lines (the last one short) with a music note at the lower right. Used on the Setlists button, the setlist header, set rows, and the Setlists dropdown. Distinct from the Menu icon.
- **Settings:** a gear (the top row's right button). There is no ☰ menu.
- **Song:** a single music note (Songs button).
- **Free play:** the metronome (the Free play row in dropdowns, Free play buttons and rows).

## Fonts

Bundle as assets; don't fetch at runtime.
- Saira Extra Condensed 600/700: BPM numbers (including tempos in lists), song title, time signature, ±buttons.
- Saira 500/600: everything else.

Labels are sentence case ("Start", "Stop", "Tap"), not all caps. Every interactive element is at least 44×44.

## Main screen (phone portrait, 24px side padding)

Top to bottom:

1. **Top row.** Current song title on the left (Saira Extra Condensed 700, one line). **Shrink to fit:** it starts at 34px and, if the name doesn't fit, shrinks step by step down to 22px; only if it still doesn't fit at 22px does it end with "…". That keeps around five words readable without ever wrapping. **Fixed lines:** the title has a fixed-height line box (sized for 34px) and the subtitle line is anchored to the bottom of the 54px block, so the subtitle never moves when the title shrinks; a smaller title sits at the bottom of its line box, right above the subtitle (aligned on the baseline). It shows the loaded song's name in setlist and Single song mode, and is empty in Free play. Under it, a small muted subtitle (Saira 14px, #8C8C8C, one line, ellipsis), like a song's artist line: the setlist's name in setlist mode; empty in Single song mode (it blends in; the subtitle line still reserves its height so the title sits in the same place). In Free play the title block is empty (saving lives in the context row: "+ New song from this"). The title block is a fixed 54px tall in every mode, so nothing shifts. The title has no buttons next to it. Long-press the title (medium haptic) to open the song editor for that song. Taps do nothing. These are small targets on purpose: shortcuts, not the main route. On the right, three outlined 44×44 buttons, 4px radius: the stopwatch ("When I press Start"), time signature ("4/4"; with a polyrhythm on it reads "4/4 · 3" and widens to fit), Settings (gear).
   - **Stopwatch button** (replaces the old subdivision button) opens the "When I press Start" sheet (see that section). Outlined white when everything in it is off; red outline and red icon when anything is on (count-in, speed up or stop after), so Start never does something you can't see.
   - **Time signature button** shows the time signature and the subdivision note next to it ("4/4 ♪♪"; quarter-note subdivision shows no note), plus " · 3" when a polyrhythm is on. It widens to fit, but its height is exactly the same as the other two buttons (44px visible, same 2px border and 4px radius, vertically centered on the same line); the 48dp touch area comes from invisible padding, never from a bigger box. Subdivision is now chosen in its sheet (see "Rhythm sheet"). Subdivision icons as before: quarter (1), beamed eighths (2), triplet (3, small "3"), beamed sixteenths (4).
2. **Beat blocks.** One whole block per beat, equal widths filling the row, 6px gaps, ~36px tall, 4px radius. Never split. Must work from 2 to 12+ beats.
   - Each block always shows its type in its resting color, so the pattern is visible even when stopped. Only the sounding block switches to its sounding color, for the duration of that beat, then returns to resting. Nothing stays lit.
   - **Beat types** (tapping a block cycles regular → accent → muted → regular; stored per song; the change is heard from the very next click):
     - Accent: resting dark red, sounding light red. Louder main click; subdivisions unchanged. Default for beat 1.
     - Regular: resting grey, sounding white.
     - Muted: the main click is silent; its subdivisions keep playing, so the grid is never lost. Drawn as a dark block with one thin diagonal line, bottom-left to top-right. Never lights, because it never sounds. With subdivision 1, a muted beat is fully silent.
   - **Subdivision strip:** 5px under each block, a ~5px-tall row of 1–4 ticks with 3px gaps, one per subdivision (the first tick is the beat itself). Each tick lights only while its click sounds, so on a muted beat the first tick stays dark and the later ticks still light. With subdivision 1 the strip can be hidden.
   - Muting individual subdivisions (e.g. gallop patterns) is not on the main screen; it will live in the song editor.
   - **Polyrhythm lane** (only when a polyrhythm is on; see "Polyrhythm"): a second, thinner row right under the subdivision strip. See `polyrhythm.reference.html`.
3. Flexible space.
4. **BPM.** Large number (~172px, tabular figures). The number itself is centered on the screen; "bpm" (small, muted) hangs off its right side, near the baseline, and is not counted when centering. Below it, a fixed 44px-tall line that normally shows the Italian tempo name for the current BPM, muted, from the mechanical metronome scale: Largo (under 60), Larghetto (60–65), Adagio (66–75), Andante (76–107), Moderato (108–119), Allegro (120–167), Presto (168–199), Prestissimo (200+). When the loaded song has unsaved changes, this line shows three plain text buttons instead: "Revert · Save · Save as new", all the same grey (#8C8C8C, Saira 15px, 500), no borders or fills, separated by dim dots (#3A3A3A), each with a 44px tap area. "Save" saves to the song. They are optional, so none is highlighted and nothing looks required; see "Changes to a loaded song" under Behavior and `unsaved-song.reference.html`.
   - **Teaching "edit right here"** (see `edit-on-main.reference.html`). The main screen is the song editor; the tempo-name line says so at three moments, without new buttons and without moving anything:
     - **A · First load (once):** the first time ever a song is loaded, and the first time a song is loaded right after "+ New song", the line shows "Change anything here, then Save" (white, 15px) for ~4 s, then the tempo name. Any change during it switches straight to Revert · Save · Save as new. Two stored flags (first load, first new song); never again after that. Not in Free play.
     - **B · First change (once):** the first time Revert · Save · Save as new appears, "Save" is white (semibold) and one muted 13px line floats just below, "Playing your changes. Save keeps them in this song.", over the empty space above the ruler (absolutely positioned: nothing moves). It disappears on the first Save, Revert or Save as new, or after ~8 s; from then on the line looks as usual (all grey). Stored flag.
     - **C · Every save:** after Save, the line shows "✓ Saved to the song" (muted, small check) for ~1.5 s; after Save as new, "✓ Saved as a new song". Then the tempo name. Revert shows no message.
     - Screen readers announce A, B and C the same way (polite announcement). Same size in both modes.
5. **Tempo ruler,** ~46px tall. Minor ticks every 1 bpm, labeled major ticks every 5, fixed red needle at the center, current value's label highlighted. Horizontal drag changes BPM. Clamp 30–300. Faster drags cover more bpm per pixel, up to 4× at full speed, so big jumps don't need long swipes.
   - **Snapping depends on release speed.** A slow drag moves in 1-bpm steps and stays exactly where it's released (so 123 is reachable). A fast swipe (fling) coasts with momentum and always comes to rest on a multiple of 5, regardless of the starting value (e.g. from 123 it settles on 130, 135...). Decide by finger velocity at release; start with roughly 300 px/s as the threshold and tune it on a real phone.
   - A light haptic tick each time the needle crosses a multiple of 5, during both drag and coast (see Haptics).
6. Flexible space.
7. **Tempo buttons:** −5, −1, +1, +5 in one row, 60px tall, filled. ±5 matches the ruler's labeled ticks; bigger jumps come from the ruler or from loading a song.
   - **Hold to repeat:** a tap changes the tempo once. Holding waits ~0.4 s (so a normal tap never repeats), then repeats at ~6 steps per second, accelerating to ~15 per second after 1.5 s of holding. Each repeat uses that button's own step (holding +5 climbs by fives). Releasing stops immediately. Reaching 30 or 300 stops the repeat with one medium haptic bump. While playing, every step applies, so the tempo audibly glides.
   - The same hold-to-repeat applies to the song editor's −5/−1/+1/+5, and to the beats −/+ in the song editor and time signature sheet (beats repeat at the slower ~6 per second without accelerating).
8. **Start/Stop** (2/3 width, 72px, primary color, icon + label) and **Tap** (1/3 width, outlined).
   - **Tap tempo:** a tap counts at the moment the finger touches the button (not on release). The tempo is the average of the last 4 taps; a tap that's far off from the others (more than 30% from their median) is ignored. Tapping resets after 2 seconds without a tap, or after twice the last interval if that's longer (so slow tempos near 30 bpm don't reset between taps). The BPM shows from the 2nd tap.
9. **Mode tabs and context row** (bottom of the screen; the same layout in every mode, so Start/Tap never move). See `main-screen.reference.html` (setlist), `free-play.reference.html`, `free-play-song.reference.html`.
   - **Mode tabs** (the very bottom, full width, 58px, a thin #1F1F1F line above, edge to edge): three equal tabs, in this order: **Songs · Free play · Setlists**. Each is an icon over a 12px label. The current mode's tab is white with a 2px red (#FF3B30) line on its top edge; the others are muted grey. Free play sits in the middle: it's the home mode, the easiest to see and reach with either thumb; Songs and Setlists are the two "pick something" destinations around it, with Setlists (the stage mode) on the right, under a right-hand thumb.
     - **Free play tab:** switches to Free play at once (see "Detaching a song"). No list.
     - **Every tab switches immediately and never opens a popup.** Tabs behave like tabs in any app: tap = you're there. Choosing *which* set or song happens on the page, with the center button of the context row (below).
       - **Setlists tab:** returns to the set you were in this session, at the same song. If you haven't used a set this session, it loads the most recently used set at song 1 (or the first set). With no sets yet, the context row shows "No setlists yet" and a "+ New setlist" button instead of Previous/Next.
       - **Songs tab:** returns to the song you were on this session; otherwise the most recently played song (or the first A–Z). With no songs yet, the context row shows "No songs yet" and "+ New song".
       - A session runs from launch until the app is closed; a fresh launch always starts in Free play.
       - Tapping the tab you're already on does nothing.
     - Icons: Songs = a single note; Free play = the metronome; Setlists = the note-queue icon.
   - **Context row** (64px, directly above the tabs; same height in every mode):
     - **Setlist mode:** Previous | narrow center (fixed 76px: setlist icon over "4/12 ⌄"; opens the set dropdown) | Next. Previous/Next: the name on line 1 (18px semibold, using the full width, shrinking to fit), and on line 2 "‹ 98 BPM" / "168 BPM ›" (option 4: grey bold).
     - **Single song:** Previous | center | Next, the same shape as in a set. Previous/Next step through the song library in A–Z order. The center button (fixed 76px, outlined: the note icon over "Songs ⌄") opens the Songs list.
     - **The center button is always "the list":** in a set it opens the set's songs (with "Change set" at the top to switch sets); in Single song it opens all songs. This is the one place lists open from.
     - **Free play:** a quiet centered text button "+ New song from this" (muted #8C8C8C, 15px, no border, 44px tap area) that opens the Save as new dialog titled "New song". This replaces the old "+ New song" in the title spot; the title block is empty in Free play.
   - **Vertical layout: two groups.** The *display* is the BPM number alone, centered in the free space between the beat blocks and the ruler, with equal space above and below it. The tempo-name line (Andante, or Revert / Save) hangs directly under the number and is not counted when centering, the same way "bpm" hangs off its right side; the free space must leave room for it. The *controls* (ruler, −5 −1 +1 +5, Start/Tap, source bar) stay together at the bottom, in thumb reach, with fixed spacing (6px + the normal gap between the ruler and the buttons). Spare height never opens gaps inside the controls.
   - **BPM size grows with the screen, never with the value:** the font size is computed once from the available area (about 172px minimum, up to ~240px), sized so that three digits fit. It never changes when the tempo goes from 100 to 99 or back: a two-digit tempo is simply narrower, centered, and nothing else on the screen moves.
   - **No jitter:** every digit of the BPM sits in a fixed-width slot (the width of the widest digit, about 0.52em in Saira Extra Condensed), centered in its slot. Same for the ruler labels and other changing numbers (tempo in the editor, set position). So 111 and 188 are exactly the same width and the number doesn't shake while it changes fast. Use the font's tabular figures if it has them; otherwise lay the digits out in slots. The font stays.
   - Saving is always one tap: "+ New song from this" in the context row in Free play; "Revert · Save as new · Save to song" under the BPM when a loaded song has unsaved changes. "Free play" is the middle mode tab.

## Quick-pick dropdowns (main screen)

Choosing what to play never leaves the main screen. The context row's center button ("4/12 ⌄" in a set, "Songs ⌄" in Single song) opens a dropdown panel just above the context row (it opens upward), over the dimmed main screen; the context row and tabs stays visible above the dim. Panel: #111111, 1px #2E2E2E border, 8px radius, full content width, up to ~470px tall, scrolls inside. Tap outside or the back gesture closes it. Playback continues. Opening one gives no haptic; choosing a row gives the same medium haptic as choosing a song. See `drop-songs.reference.html`, `drop-sets.reference.html`, `drop-set.reference.html`.
- **Songs list** (the "Songs ⌄" center button in Single song). See `songs-panel.reference.html` (several states at once). Same rules as the set panel; nothing to reorder because it's A–Z.
  - **Top (pinned):** "Search songs" field, only with more than about 8 songs (same style as the sets view search).
  - **Rows:** one 52px row per song, A–Z: play icon (red, with the selected background, for the loaded song), name, tempo, time signature. Tap = load it in Single song mode (same rules as the song library) and close.
  - **Rename (long-press):** the name turns into a text field in place, selected, keyboard up, "Done" on the right. Done/Enter saves and the row moves to its new A–Z place; outside/Back cancels. Empty keeps the old name; duplicates allowed. Medium haptic. Tempo, time signature, beats and the rest are edited on the main screen (change them, then Save), so the panel only needs the name.
  - **Swipe to delete:** either direction, red background "Delete song", ~40% threshold (feel: see "Swipe feel"). Past the threshold the row stays open and a dialog asks, naming the sets it affects : "Delete Glass Harbor?" / "It will also be removed from Friday set and Rehearsal." (in no sets: no second line) / Cancel · Delete (red, filled). Cancel slides the row back. After Delete, the Undo bar appears ('Deleted "Glass Harbor"' + Undo; restores the song and its place in each set). Deletes the song from the library and from every set. The loaded song can be deleted too; see "Removing what's loaded".
  - **One-time hint:** same nudge as the set panel, shown once for this list (its own flag), the first time it opens with at least 2 songs.
  - **Bottom (pinned):** "+ New song ›": creates a song from the click as it is now (tempo, time signature, subdivision, beat states, polyrhythm), shown as a row at the top in rename state with "Song N" selected (next free number). Done saves it into A–Z order, loads it in Single song mode (same as Save as new), and closes the panel; outside/Back cancels and creates nothing. Replaces "Song library ›" (the library stays in the Menu as the fallback).
- **Setlists list** (reached from "Change set" in a set's panel, and when switching sets): one 52px row per set, recently played first: list icon, name, "12 songs". Tap = load it at song 1 and close. Same rows and behavior as the sets view (below), which replaces it.
- **Set ⌄** (setlist mode, the center "4/12" button). See `set-panel.reference.html` (shows several states at once: a lifted row, a row mid-swipe, and the Undo bar).
  - **Header** (56px): set name (16px, 600) with "Song 4 of 12" muted under it on the left; on the right a small outlined button with the setlist icon and the words "Change set" (40px tall, 2px #2E2E2E border). Plain words, no arrow: an arrow inside a panel that was opened by an arrow would read as "more songs". Tapping it swaps the panel's content in place to the **sets view** (see "Sets view" below).
  - **Rows:** the set's songs in order, the current one with the red play icon and selected background, scrolled into view. Tap = jump to that song (same rules as next/previous) and close.
  - **Reorder:** long-press a row (medium haptic) lifts it; drag to move, the list auto-scrolls near the edges; drop puts it there. Saved immediately, no Save or confirm (any order is easy to put back). The song that's playing can be moved too; the sound doesn't change, only the position updates ("4/12" may become "6/12") and Previous/Next follow the new order. The panel stays open.
  - **Swipe to remove:** swipe a row left or right; a red background with "Remove" shows behind it. Released past ~40% of the row width, the row is removed from this set (never from the library); released earlier, it springs back. The current song can be removed too; see "Removing what's loaded". Haptics: see "Swipe feel" (one tick at the threshold, none on release).
  - **Position after a removal:** removing a song before the current one shifts the position ("4/12" becomes "3/11") and the current song doesn't change. Removing the current song itself: see "Removing what's loaded".
  - **Undo bar:** after a removal, a bar appears at the bottom of the panel, just above the pinned actions: "Removed from Friday set" and an "Undo" text button on the right (white, 600). It stays ~6 s, or until the panel closes, or is replaced by the next removal. Undo puts the song back in its old position.
  - **One-time hint:** the first time ever the panel opens on a set with at least 2 songs, one row that isn't playing slides ~56px to the side, showing the red "Remove", then springs back (~0.8 s total, no haptic). Never again after that (stored flag). Long-press to reorder needs no hint: it's the standard Android list behavior, and the set page keeps its visible controls.
  - **Stage mode:** next to "Add songs" in the pinned bottom row, an outlined "Stage mode" button (stage icon + text) enters stage mode for this set (see "Stage mode"). "Add songs" and "Stage mode" share the row, half width each, 48px. See `set-panel-stage.reference.html`.
  - **Bottom (pinned):** "+ Add songs ›" turns the panel into the **song picker** for this set, in place (see below). The click keeps playing; the main screen is never left.
- **Song picker** (inside the set panel, from "+ Add songs" or after creating a set with "+ New setlist"). See `add-songs-panel.reference.html`.
  - **Top:** quiet "‹ Back" on the left (returns to the set's songs without adding anything; Android Back does the same) and a muted "Add to Friday set" on the right, then a pinned "Search songs" field (only with more than about 8 songs).
  - **Rows:** all your songs A–Z, 52px: a checkbox (20px, 2px border in "control outline"; ticked = white fill with a black check), name, tempo, time signature. Tapping anywhere on the row ticks or unticks it (light haptic); the ticked row gets a #1A1A1A background. Songs already in the set are greyed (#5A5A5A) with a small "In this set" line and a disabled checkbox; tapping them does nothing. No swipe, no long-press here: picking is the only job.
  - **Bottom (pinned):** a full-width 52px button. Nothing ticked: grey "Choose songs to add" (disabled). One or more: red filled "Add 3 songs to Friday set" ("Add 1 song…" for one).
  - **Adding:** the songs go to the end of the set in the order you ticked them; the panel returns to the set's songs, scrolled to the end, with the new rows marked "Added" (small muted label, faint background) for ~2 s. Reorder them right away by dragging. The current song and position don't change, only the total ("4/12" → "4/15"). No Undo bar: each added row can be swiped away.
  - **New set:** after "+ New setlist" → name → Done, the picker opens for the new set ("Add to Setlist 5"); "‹ Back" or adding returns to the sets view.
- **Sets view** (inside the Set ⌄ panel, after "Change set"; also the Setlists list shown when no set is loaded). See the "Changing set from the 4/12 list" board, steps 2 and 3.
  - **Top line:** a quiet "‹ Back" (14px, #8C8C8C, no border, 44px tap area) that returns to the set's songs; Android Back does the same. Just "Back": the loaded set is highlighted right below, so naming it again adds nothing. No title: the list explains itself. Shown only when a set is loaded.
  - **Rows:** your sets, most recently played first (no sort control: tonight's set is usually on top). "Played" means loaded: a set moves to the top when you load it, not when you rename it, and a new set starts at the top. The order is re-read each time the view opens, never while you're looking at it, so rows don't jump. With more than about 8 sets, a "Search setlists" field (40px, magnifier, 2px #2E2E2E border, white border while focused, × to clear) is pinned under "‹ Back"; only the sets scroll. It filters by name as you type, keeping the same order. While the keyboard is up, the panel sits directly above the keyboard (the context row is under it) and drops back when the keyboard closes; the same applies to rename fields and the Songs list search. See the "Sets view: search" board. The loaded set is highlighted like the current song (selected background, red play icon in place of the set icon). Tap = load it at song 1 and close.
  - **Rename (long-press):** the row's name turns into a text field with the name selected and the keyboard up, "Done" on the right. Done or Enter saves; tapping outside or Back cancels. An empty name keeps the old one; duplicate names are allowed. Medium haptic on long-press. This is the long-press "edit" for a set here; its songs are edited in its own songs view.
  - **Swipe to delete:** like removing a song, but the background reads "Delete set". Past the threshold the row stays open and a dialog asks (see "Delete asks, remove undoes" below): "Delete Rehearsal?" / "Its 9 songs stay in your library." / Cancel · Delete. Cancel slides the row back. After Delete, the Undo bar appears ('Deleted set "Rehearsal"' + Undo, restores it in place). The loaded set can be deleted too; see "Removing what's loaded". If the deleted set was the one the Setlists tab would return to, the tab's normal fallback applies (most recently used set, else the first).
  - **Bottom (pinned):** "+ New setlist ›": adds a new set at the top of the list, already in rename state with "Setlist 5" selected; Done saves it and opens the song picker for it (inside the panel), returning here after. Cancelling the name keeps the default name.
- **Long-press vs swipe (all lists).** A long-press must survive a slightly moving finger:
  - A swipe only starts after the finger moves more than 32dp horizontally, and mostly sideways (horizontal movement at least twice the vertical). Below that, the row doesn't move at all.
  - Long-press timing: **200ms to lift a row for reordering** (a set's songs), 400ms for rename (the Songs list and sets view), where an accidental trigger would open the keyboard. While waiting, sideways movement under 32dp doesn't cancel it.
  - Scroll vs reorder is told apart by movement, not by time: a finger that moves vertically past the normal scroll slop (~8dp) before the long-press fires is a scroll, and the long-press is cancelled. A finger that stays put for 200ms is a reorder; after that, vertical movement drags the row (auto-scrolling near the edges) instead of scrolling.
  - Once the long-press fires (haptic), swiping is off for that touch: the gesture is a reorder drag (set songs) or opens rename (other lists).
  - Once a swipe has started, long-press is off for that touch.
  - Vertical movement past the normal scroll slop scrolls the list and cancels both.
- **Swipe feel (all lists).** Modeled on Gmail and Android's standard swipe-to-dismiss:
  - **Follows the finger 1:1** from the moment the swipe starts (after the 32dp start distance), no lag.
  - **Commit by distance or speed:** releasing past 40% of the row width commits; so does a quick flick in the swipe direction (faster than ~1000dp/s) even if shorter. A flick back toward the start cancels.
  - **The threshold is felt and seen:** crossing 40% gives one light haptic tick (the only haptic of a swipe; nothing extra on release), the red background deepens (#8E2620 → #FF3B30) and the label ("Remove" / "Delete song" / "Delete set") and its trash icon grow slightly (scale 1 → 1.1). Moving back under 40% reverses all of it (a second tick), so you always know what letting go will do.
  - **Label on the revealed side:** swiping left shows the icon and label on the right; swiping right shows them on the left.
  - **Commit animation:** the row slides the rest of the way off (~120ms), then the gap closes (~150ms) as the rows below move up. The data change is immediate (see "Never wait for an animation").
  - **Cancel animation:** a quick spring back (~180ms, ease-out, no bounce).
  - **Delete dialogs:** for deletes that ask, the row holds open at the threshold position while the dialog is up; Delete continues it off-screen, Cancel springs it back.
  - **One at a time:** starting a scroll, another swipe, or a long-press anywhere settles any row that is still moving.
  - **Off while busy:** no swiping during a reorder drag or while a row is in rename.
  - **Accessibility:** each row also offers the action as a TalkBack custom action ("Remove from set", "Delete song", "Delete set"), since a swipe can't be performed by screen-reader users.
- **Search (all search fields).** Matches anywhere in the name ("crown" finds "Hollow Crown"), ignoring case and accents. The matching part of each name is shown in white semibold while the rest stays regular. Nothing matches: one muted line in the list, "No songs match "xyz"" / "No sets match "xyz"". The keyboard's search key closes the keyboard and keeps the results. Clearing (×) shows the full list again.
- **Undo bar (all lists).** Only one at a time: a new one replaces the old (the old action stays done). It can be swiped sideways to dismiss. It stays ~6 s, longer if the phone's accessibility setting "Time to take action" asks for more. Screen readers announce it.
- **Reorder polish.** Auto-scroll near the top or bottom edge speeds up the closer the dragged row is to the edge. The other rows slide smoothly to open the gap where the row will land. Screen readers get "Move up" and "Move down" actions on each row of a set's songs.
- **Never wait for an animation.** Animations (a dropped row settling, a swipe springing back, a removed row collapsing, a renamed row moving to its A–Z place, Undo restoring a row) never block touches. The data changes at once when the action happens; the animation only shows it. If a new touch lands while one is running, the running animation finishes in a quick ~80ms catch-up (not a hard jump) and the new touch is handled immediately, with no tap or long-press lost. Keep these animations short to begin with (~150–200ms).
- **Removing what's loaded.** You can remove or delete the song or set you're on; the app never refuses. Its place is taken by the next one, and the mode stays the same (never a switch to Free play):
  - **Current song removed from the set** (set panel): the song now in its position becomes current (4/12 removed → the old 5th song plays as 4/11). If it was the last song, the new last song becomes current. If the set is now empty, you stay in setlist mode with the empty set: the title shows the set name with no song, the context row shows "No songs in this set" and "+ Add songs" instead of Previous/Next, and the click keeps what it sounds like (tempo, time signature, beats).
  - **Loaded set deleted** (sets view): the most recently used other set loads at song 1, and the sets view stays open with it highlighted. If there's no other set, you stay in setlist mode with no set: the context row shows "No setlists yet" and "+ New setlist" (the same as the Setlists tab with no sets), and the click keeps what it sounds like.
  - **Loaded song deleted** (Songs list): in Single song mode the next song A–Z loads (the previous one if it was last). In setlist mode it's removed from the set too, so the current-song rule above applies. If it was the last song in the library, you stay in Single song mode with the "No songs yet" / "+ New song" context row, and the click keeps what it sounds like.
  - **Loading the replacement** follows the normal rules: stopped, it just loads; playing, it restarts on beat 1 at the new song's tempo (same as Next). Unsaved changes on the removed song are discarded, as when loading another song.
  - **Undo** puts everything back as it was: the song or set returns to its place and becomes current again, at the same song, using the same loading rules.
- **Adding songs to sets (Omer's feedback, Oct 22: "exhausting and not clear").** A new song can go straight into a set, and the set-first way is easier to see and shorter:
  - **From the New song dialog** ("+ New song from this" in Free play, and "Save as new" in Single song): under the name, a row "Add to a setlist" set to **None** by default. Ignored, the dialog is still just a name and Save. Tapped, it opens in place: None ("Just save the song"), the 3 most recently played sets ("Added at the end · 12 songs"), "More setlists ⌄" for the rest, and "+ New setlist" (created on Save, named "Setlist N"). With no sets yet, the row still shows, with only None and "+ New setlist", so a first song and a first set can be made together. The song goes to the end of the chosen set; the app doesn't switch into the set. In setlist mode, Save as new keeps its own choices (Replace / Add after / Don't add). See `new-song-dialog.reference.html`.
  - **From the set (set-first), easier to see:** the pinned "+ Add songs" at the bottom of the set panel becomes an outlined button (48px, 2px border, setlist icon + "Add songs") instead of a plain row, so it reads as the panel's main action. After "+ New setlist" → name → picking songs → Add: if the click is stopped, the new set **loads** at song 1 (you just built it to play it) and the panel shows its songs; if it's playing, nothing switches (the click is never interrupted by creating something) and you're back in the sets view with the new set on top.
- **One-time hints (Principle 7).** Long-press and swipe have no visible button, so each list teaches them once. After the swipe nudge (see Set ⌄), a small muted line appears under the list for ~3 s: "Hold a song to move it · Swipe to remove" (set panel), "Hold a set to rename it · Swipe to delete" (sets view), "Hold a song to rename it · Swipe to delete" (Songs list). Once per list (stored flag), skipped with Remove animations. Screen readers get the same actions as custom actions (see Accessibility).
- **Delete asks, remove undoes.** One rule for every list: swiping something that deletes your own work (a song from the library, a whole set) asks first in a small dialog, because a song can hold real work (and its Start settings: count-in, speed up, stop after) and is shared by sets; after confirming, the same Undo bar still appears as a second chance for a mistaken tap. Swiping that only takes something out of a list (a song out of a set) deletes nothing, so it's immediate with the Undo bar. See `delete-confirm.reference.html`.
- **Taller panel (drag to expand):** every list panel (set panel, sets view, Songs list, song picker) has a small grab handle at its top edge (36×4px, #3A3A3A, centered, inside a 24px tall drag area). Dragging it up expands the panel to the full space above the context row (top: just under the status bar), for longer editing; it follows the finger and snaps to whichever height is nearer on release, or by flick direction. Two heights only: normal (as today) and tall. Dragging down from normal closes the panel, like tapping outside. Each panel opens at normal height every time (it never remembers tall), so on stage it always looks the same. Back from tall closes the panel (one level, not "back to normal"). With the keyboard up, the panel is already as tall as it can be; the handle does nothing. The context row and tabs stay visible below in both heights. See the "Taller panel" board.
- **No "Free play" rows in the dropdowns:** Free play is the middle mode tab, always visible.
- **Panel structure:** the search field (when shown) is pinned at the top and the action rows ("+ New song ›", "+ New setlist ›", "+ Add songs ›") are pinned at the bottom; only the list between them scrolls. The pinned action group is separated from the list by a 2px #2E2E2E line, and its rows by 1px #1F1F1F lines, so actions never read as list items.
- **Long-press a row:** in the Songs list and the sets view it renames in place; in a set's songs it reorders (see Set ⌄).
- **Empty lists:** the context row already says it ("No songs yet" / "No setlists yet" / "No songs in this set") with a "+" button: "+ New song" opens the Songs list with a new row in rename state; "+ New setlist" opens the sets view with a new set in rename state (then the song picker); "+ Add songs" opens the set panel's song picker. Inside an empty list, the pinned "+" button is the only row.

## Song parts

A song is a list of **parts**, each a "little song" with its own length, tempo and rhythm, played in order. This is how a song gets tempo changes, odd bars (a one-bar 2/4 break), gradual accelerando/ritardando, and a structure (intro, verse, chorus…). See `song-parts.reference.html` (the parts page, an open part, the main screen with parts).

**The rule that protects the app:** a song with one part looks and works exactly as today. Every existing song becomes a one-part song on upgrade, and nothing in this section appears on the main screen (the song map and the parts line) unless the song has 2+ parts, a Gradual part, or ends with Stop or Loop song. A song with one steady part set to Loop last part plays exactly like a plain song (Speed up included), whatever its length.

### A part
- **Name:** from a dropdown of common names (Intro, Verse, Pre-chorus, Chorus, Bridge, Break, Solo, Outro) or "Custom name…" (typed). New parts get the next sensible name ("Part 3" if nothing fits).
- **Length:** always in bars (1–999), with the same tap-to-type stepper as the stopwatch panel. (The earlier "Until you stop" length was replaced by "Loop last part" under "When the song ends", so every part, including a Gradual one, has a length.)
- **Tempo (no mode chips, so the card never changes shape):** a steady part shows "BPM" (stepper) and under it a full-width dashed button **"↗ Gradual tempo change"** that says what it does (not "Speed up", which is already the practice feature in "When I press Start"; "gradual" says it's a smooth change, not a jump). Tapping it turns the same two rows into **"Starts at"** (the same value, untouched) and **"Ends at"** (✕ · − value +; the ✕ is a square with a 2px white border and white ✕, the same size as − / +). **The row fits on one line:** ✕, − and + are drawn 40px (the app-wide stepper rule, see below) inside 48dp touch cells that sit edge to edge, so the 8px between them comes from the touch padding, not extra gaps; the value box stays 92px so all rows line up. − / + use "surface on a sheet or card" (#2A2A2A) so they read as buttons at a glance. That leaves room for "Ends at" on one line on a 360dp-wide phone at default text size (only very large text may wrap the label)., with Ends at = Starts at + 10 (− 10 if that would pass 300) so the change is visible at once; an end set back equal to the start keeps "Ends at" while the card stays open and shows the button again when reopened; ✕ goes back to one tempo. Same rows, same height in both states; only the words in them change (swap motion). Wording: "BPM" is the number, "Gradual tempo change" names the action (like "Speed up" / "Change by" elsewhere); "Starts at" replaces "BPM" when there is an end, because "BPM" next to "Ends at" would read as the whole part's tempo. A part whose end equals its start is saved as steady and shows the button again. Internally still Steady/Gradual (start and end tempo). A gradual part: the tempo changes a little on every beat across the part (linear in tempo, beat by beat), reaching To on the part's last beat; the next part starts at its own tempo.
- **Rhythm:** time signature, subdivision and polyrhythm, edited in the same Rhythm panel (opened from the part's "Rhythm" row, showing e.g. "7/8 ♪♪").
- **Accents:** the part's beat blocks, tapped to cycle accent / regular / muted, as on the main screen.
- **Duration** is shown, computed ("≈ 0:26"); length is always set in bars.

- **Plain songs and the default:** a song with one part and "Loop last part" plays its bar until Stop, exactly like a song always did. Existing songs migrate to that (one part, 1 bar, Loop last part). New songs start the same way; adding parts never changes the end choice by itself.

### The parts page
- **Getting there:** a visible row "Song parts ›" (with the count, "1 part" / "6 parts") at the bottom of the Rhythm panel; long-pressing the title also opens it (shortcut). **The long-press is used up by opening the page:** the finger that is still down, and its lift, never count as a tap on the new page (the parts page's own title, tap to rename, sits under that finger). In Free play the row reads "Save as a song to add parts" and opens the Save as new dialog first, then the page.
- **Top:** ‹ back, the song name (tap to rename; shrinks to fit like the main-screen title, down to 22px, before "…"), and Save / Discard when there are unsaved changes (see "Saving on the parts page"). Play/Stop is a full-width button at the bottom.
- **Summary line:** under the top bar, full width, muted 13px: "6 parts · 45 bars · ≈ 1:38, then loops Outro". It has its own line because beside the name it was cut to "2 parts · 5 bars · ≈ …" by Save / Discard (build 77).
- **The strip:** the whole song to scale (blocks proportional to bars, names inside when they fit). Tap a block = scroll to and open that part's card. **Which block is white:** while playing, the part that's playing (it moves along with the music); while stopped, the open card's part (none if no card is open). No sliding or reordering in the strip (reordering is done with the cards: one way).
- **Cards:** one per part: number, name, "8 bars · 7/8 · ≈ 0:26", tempo ("128" or "128 → 140"). Tap = open it in place (one open at a time). **An opened card scrolls into view, only as far as needed:** if it's already fully visible, nothing scrolls; if it fits in the visible list area (between the pinned top and the pinned Play button), the list scrolls just until the card's bottom sits 8px above the Play button; if it's taller than that area, the list scrolls until its header row is at the top of the area (so you always see what you opened, then scroll on yourself). The scroll runs together with the card's opening (same 200ms arrive motion, using the card's final position after any other card closes), never after it; a touch on the list stops it at once; "Remove animations" jumps. Closing a card never scrolls. Same rule for a card opened from the strip and for the new card from "+ Add part". The open card's height doesn't change with Steady / Gradual, but it can with the time signature (more accent blocks) and text size, so it's measured, not assumed. Long-press = lift and reorder. Swipe = remove the part, instant with the Undo bar ("Removed Bridge · Undo"): no dialog, because it's part of an unsaved change (Revert brings it back too) and Undo is there. The last remaining part can't be removed.
- **An open card:** Name (dropdown), Length, Tempo (BPM + "Gradual tempo change", or Starts at / Ends at), Rhythm ›, the accent blocks, then "▶ Play from here" and "Duplicate".
- **"+ Add part"** (dashed, after the last card) adds a part with the last part's rhythm (time signature, subdivision, accents, polyrhythm) and length, the next name, opened, **Steady at the tempo the previous part ends on** (its To if it was Gradual, else its BPM). The music continues where it left off.
- **"When the song ends":** one row: the label **"At the end"** on the left (renamed from "When the song ends", which wrapped to two lines at 115% text next to "Loop last part ⌄"; "At the end · Loop last part" reads as one sentence) and a dropdown on the right showing the current choice ("Loop last part ⌄"), the same control as the part's Name. Tapping it opens a menu of Stop / Loop song / Loop last part with the current one ticked; picking one closes it. (Builds 68–71 used chips: [Stop] [Loop song] on one line in two halves and [Loop last part] centered below, because three chips don't fit in a row on a phone; they read as scattered, so the dropdown replaces them: one line at any text size.) Stop: the click stops at the end. Loop song: starts over from part 1, again and again, until Stop. **Loop last part:** the last part plays again and again, as it is, until you press Stop (a Gradual last part restarts its ramp each time); this is how a song ends in an open groove, or how one part is practised on a loop. The strip and the main-screen song map draw the Material "repeat" icon (vector, two arrows in a loop) after the last part's name when the song is set to Loop last part, and nothing otherwise (never a text glyph such as ⟲: those can render as emoji on Android); the summary reads "45 bars, then loops Outro". (Words: "loop" means until you stop; "repeat" is kept for a counted repeat, like the parked "repeat a part ×N", so the two never blur.)
- **Saving:** everything here is an ordinary unsaved change to the song; on this page it's saved with the top-right Save (see "Saving on the parts page"), and the main screen keeps its Revert · Save · Save as new line.
- **While playing, the playing card fills like a progress bar:** the "selected row" color (#242424) grows from the card's left edge to its right across the part, so you see where you are inside it, even in a 1-bar part. It moves smoothly, driven by the engine's beat position (so it speeds up and slows down with a Gradual part), and is empty again when the part starts (each loop of Loop last part too). Only the card's header row (the 60px row with name and tempo) fills: an open card's controls below it keep their normal background, so nothing moves behind the steppers. Text and tempo stay on top, unchanged. The strip at the top still shows which part is playing in the whole song; the card shows how far into that part: one is the map, the other the detail.
  - With "Remove animations" on, the fill steps once per bar instead of gliding.
  - **It follows what you hear, like the beat lights:** position = the audible time (engine clock minus output latency, the same offset the beat lights use), so on Start it begins at 0 on the first audible beat and never jumps forward (build 77 jumped ~15% on the first part after Start; later parts were fine).
- **Saving on the parts page (replaces the Revert · Save · Save as new line here):**
  - **Top bar, right side:** when the song has unsaved changes, a filled white **"Save"** button (black text, 38px) and, left of it, a quiet grey **"Discard"** text button. With nothing unsaved, neither is shown (the space stays empty; nothing moves in the title).
  - **Discard asks first**, because it throws away work: "Discard changes to Dead Weight?" / "The song goes back to how it was last saved." / Keep editing · Discard (red). It's named "Discard", never "Revert" or an undo-style arrow, so it can't be mistaken for Undo (Undo stays the bar that appears after removing a part).
  - **No "Save as new" on this page** (it stays on the main screen's line, where it belongs).
  - **Leaving the page with unsaved changes** keeps them as the song's unsaved changes, as everywhere (the main screen shows Revert · Save · Save as new); no prompt on Back.
  - Built (build 61): the Save/Discard space is always reserved; at very large text the two buttons cap at 1.3× and may shrink slightly on narrow phones. The shared confirm dialog wraps its buttons when labels are long.
  - **Play / Stop moves to the bottom:** a full-width 56px button pinned at the bottom of the page (Play outlined white; Stop filled red with black icon and label), fixed size in both states.
- **Motion on the parts page** (uses the app's Motion rules; the goal is "never annoying"):
  - **Opening / closing a card:** ~180ms, one smooth height change (ease-out). The tapped card's header **stays exactly where your finger is** (the list keeps that header anchored), so nothing jumps under the finger. When another card was open, it closes **at the same time** with the same timing, so the list doesn't bounce. The body's contents fade in quickly as the card opens (start ~40ms in, 120ms), and fade out at once when closing. Scroll only if the opened card would end below the screen, and only as far as needed (~200ms).
  - **Never wait:** a tap during the animation is handled immediately (open another card, close, tap a field); the running animation just finishes fast (see "Never wait for an animation").
  - **Add part:** the new card grows in at the end (arrive: height + fade, ~200ms) already open, and the list scrolls to it only if needed.
  - **Remove part:** the card leaves (slide off, then the gap closes, ~150ms) as in every list; Undo grows it back in place.
  - **Reorder:** lifting is instant feedback (~100ms scale to 1.02 + shadow); other cards slide smoothly out of the way; drop settles in ~150ms.
  - **The strip:** blocks resize smoothly (~180ms) when a length changes, and the highlighted block cross-fades when the open or playing part changes. Tapping a block scrolls to its card (~250ms ease-in-out) and opens it.
  - **Text that changes** (tempos, bar counts, durations, the summary) uses snap in, soft brighten. Save / Discard fade in (~120ms) in their reserved space.
  - **The song map on the main screen** moves continuously with the music (no easing while playing); after a slide it snaps to the part start with a quick decelerate (~220ms), like the tempo ruler's coast.
  - All of it becomes instant with Remove animations on.
- **Fixes after the first phone check (step 2):**
  - **Reorder only from the card's header** (its summary row). On an open card, long-pressing the header first closes the card, then lifts it for dragging, in one gesture. Long-pressing anywhere inside an open card's body does nothing.
  - **Open card order:** Name, then **Tempo** (BPM + "Gradual tempo change", or Starts at / Ends at) right under it, then Length, Rhythm ›, accents, Play from here / Duplicate. Tempo is what people change most.
  - **Every −/+ stepper on this page** uses the app's one stepper: tap = one step, hold = repeat and accelerate (same feel as the main screen's tempo buttons), tap the value to type. One shared component everywhere in the app.
  - **No text glyphs for icons anywhere** (▶ ■ ✓ ∞ ⌄ › etc. can render as colored emoji on Android, e.g. an orange ▶): every icon is a vector icon in the theme's colors.
- **Settled while building (step 2):** "+ Add part" names the copy with the next common name (Intro → Verse → Pre-chorus → …), else "Part N"; Duplicate keeps the name. "+ Add part" copies the last part's length. **One exception, the first add on a plain song:** when the song is a single part of 1 bar (every migrated or new song), adding a part sets both the existing part and the new one to 8 bars, so the first result is a real starting point instead of two 1-bar parts (that 1 bar was never really chosen; it only made the song loop like a plain metronome). After that, Add part copies the last part as usual. (The old "an open part that stops being last gets 8 bars" rule is gone with "Until you stop".) (Superseded: choosing Gradual no longer moves From to the previous part's end; "Gradual tempo change" keeps the start and sets the end +10, see Tempo above.) Start and end are always freely editable afterwards (steppers, typing, hold), like any value. A Steady part's tempo stepper is labelled "BPM". The part's "Rhythm ›" opens the Rhythm controls as a bottom sheet (top panels only drop from the top row). Chip rows wrap under their label at large text sizes (also in "When I press Start").

### Main screen for a song with parts
- **The ruler becomes the song map,** working like the tempo ruler: the red needle stays in the middle, and the parts strip moves under it as the song plays (a few parts visible at a time, edges fading). Slide it to scroll; on release it snaps to the start of the part under the needle and goes there. Tap a part to go there. Going there: stopped, it just moves the start point; **playing, it jumps at once, exactly like changing songs** (and the jumped-to part also becomes where Start begins, so Stop then Start returns there, as "Play from here" does): the part restarts immediately on its beat 1 at its tempo, with the same clear-and-reschedule as Next/Previous (no count-in, since you're mid-song). The map, the line and the parts-page card move at the same moment. (Was "on the next bar line", then briefly "on the next beat"; decided Oct 2026 that a tap you choose should act now and match song changes.) Stage mode and "Play from here" work the same.
- **The line under the BPM** shows where you are: "Chorus · bar 3 of 8 · next: Break" (the last part with Loop last part: "Outro · bar 3 of 8 · looping"; with Stop after on it stays "Outro · bar 3 of 8 · 4:12 left", without "looping", to keep one short line: the time left already says how it ends) (unsaved changes still use this line while stopped, as today).
- **Heads-up before a part changes** (main screen and stage mode, the same line, no new controls): the line warns you, so you never miss a short break after a long verse.
  - **2 bars before the part ends:** "**Break in 2 bars** · 2/4 · 128" (bold). After the name it adds only what changes: the time signature and/or tempo when they differ from the current part ("Chorus in 2 bars" alone if nothing else changes; a Gradual part shows its start tempo). **Short parts (up to 4 bars) show the heads-up from their first bar:** "Part 2 in 3 bars", "in 2 bars", then the beat countdown, so the normal line never flashes for a moment and gets replaced (on Midnight Engine's 3-bar part it showed for one bar after Start and looked like a glitch). In a 1-bar part only the countdown shows. Longer parts keep the normal line until 2 bars before the end.
  - **Last bar:** the name becomes a small white tag (white fill, black text, 4px radius) counting the beats left, starting from the bar's full beat count: "Break in 4", "in 3", "in 2", "in 1" in 4/4 (the number swaps each beat with the swap motion). The tag counts beats of the current part's time signature, on the beat, following what you hear (same offset as the beat lights).
  - **The new part:** the line goes back to normal ("Break · bar 1 of 1 · next: Bridge").
  - **Not shown:** before the song's end (Stop shows nothing; Loop song warns "Intro in 2 bars" like any change; Loop last part never warns, since it doesn't change). Not during count-in.
  - **Optional sound:** Settings › "Sound on part changes" (switch, off by default): the first beat of a new part plays the accent sound a little higher, so you hear the change without looking.
  - Stage mode shows the same text in its larger line.
- **The BPM** shows the live tempo (Gradual parts update it every beat, instantly, no animation).
- **−5 −1 +1 +5 and Tap change the current part only** (a Gradual part shifts its From and To together). These are unsaved changes to the song; they stay while you move between its parts, and Save / Revert / Save as new work as usual. Leaving the song discards them, as today.
- **Beat blocks** follow the current part's time signature (they change at the part's first beat).
- **Stage mode:** the same map under the BPM; tap a part to go there; no sliding (stage mode has no gestures besides taps).
- **Stop after on a song with parts:** the line under the BPM shows both, part first: "Chorus · bar 3 of 8 · 4:12 left" (or "· 12 bars left").
- **Free play while a song with parts is loaded:** the click carries on as a plain click on the part it was on, and the map goes away (Free play never holds a song).

### With the rest of the app
- **Count-in:** before the part playback starts from (the first part, or the part chosen on the map while stopped), in that part's tempo and time signature. Only when starting from stopped: Loop runs straight back into part 1 without a new count-in.
- **Song end in a set:** when the last part finishes (Stop), the click stops and the next song is loaded and ready. **Except while the parts page is open** (however playback was started): there the song you're editing stays loaded when it ends; the click stops and the start point returns to part 1. Advancing to the next song is a performance behavior and never happens while you're editing. Stop after (a practice tool) still stays on the same song.

- **Speed up** (in "When I press Start") isn't offered for songs with parts: the row shows "Not for songs with parts", because the parts already decide the tempo. Count-in and Stop after work as usual.
- **In a set:** at the song's end the click stops and the next song is loaded and ready (it never runs into the next song by itself). Loop song starts over from part 1 until Stop.
- Media controls, pedals and the lock screen keep moving between songs, not parts.

### Data and building order
- Song = list of parts + "when the song ends" (stop | loop song | loop last part). Each part: name, length (bars), tempo start and end (equal when Steady), and its pattern (time signature, subdivision, beat states, polyrhythm). Existing songs migrate to one part of 1 bar with "loop last part" (numbered migration + fixture, per the data-format-change skill).
- **Build in three steps, each shippable on its own:** (1) data + engine (parts playback, gradual tempo per beat), no visible change; (2) the parts page; (3) the main screen map and stage mode.

## Song editor (replaced by the parts page)

**Replaced:** the parts page (see "Song parts") is the song editor now. A one-part song shows one card on it, holding everything this page used to edit (tempo, time signature, subdivision, accents); the song's name is edited by tapping it in the page's top bar (or renamed in the Songs list). Long-pressing the title opens the parts page. The old text below is kept only as history.


A full screen (not a sheet), used for setup rather than on stage. See `song-editor.reference.html` (shown at full scroll length).

- **Opening it:** long-press the song title on the main screen to edit the current song (a tap on the title does nothing, so a stray touch on stage never leaves the main screen). It's the only way in, and it's a shortcut: everything it edits today can also be changed on the main screen and saved, and renamed in the Songs list. New songs come from "+ New song" in the Songs list or "+ New song from this" in Free play.
- **Top bar:** "Cancel" (text) on the left, "Song" title in the middle, "Save" (small primary button) on the right. Cancel with unsaved changes asks to discard them.
- **Name:** outlined text field, Saira Extra Condensed. For a new song, the field opens focused with a unique default name pre-selected ("Song 10", next free number), same behavior as a new setlist: typing replaces it, leaving it keeps it. A new song starts at the main screen's current tempo (not a fixed 120), so a tempo you just found becomes the song's tempo; everything else starts from the defaults.
- **Tempo:** the same controls as the main screen, smaller: the number (~84px, centered, "bpm" hanging off its right), the tempo ruler (same look and behavior: velocity snapping, acceleration, ticks on fives), a row of four filled buttons −5 −1 +1 +5 (52px tall, hold to repeat with the same acceleration), and the outlined "Tap tempo" button below. In x/8, the tempo counts eighth notes. See `song-editor-collapsed.reference.html`.
- **Time signature:** beats with − / + (1–16), a "/" separator, and a two-option segmented control for 4 or 8. The selected option is filled white with black text.
- **Pattern and subdivision (collapsed by default):** below the time signature, one outlined 72px row titled "Pattern and subdivision" with a chevron and a muted summary line: the subdivision plus "accent on 1" for the default pattern, or "custom pattern" when anything differs (e.g. "Quarter notes, accent on 1", "Sixteenths, custom pattern"). Tapping expands it in place to show the two controls below; tapping the header again collapses it. Always opens collapsed. See `song-editor-collapsed.reference.html` (default) and `song-editor.reference.html` (expanded).
- **Subdivision** (inside the collapsed section): four equal options with the vector note icons (quarter, eighths, triplet, sixteenths); the selected one is filled white with a black icon.
- **Pattern** (inside the collapsed section): one row per beat, stacked vertically so targets stay large for any meter:
  - Beat number (muted), then the beat button (64×48, same colors as the main screen: regular grey, accent dark red, muted dark with a diagonal line). Tapping cycles regular → accent → muted → regular.
  - Then one cell per remaining subdivision of that beat (48px tall, filling the row). On = #2E2E2E filled; off = muted style (dark with the diagonal line). Tapping toggles on/off. This is how gallops and other patterns are built: it maps directly to the per-step levels in `MetronomePattern` (soft ↔ silent).
  - With subdivision 1 there are no cells, only beat buttons.
  - Changing beats or subdivision keeps existing beat states where possible; new subdivision cells start on.
- **Preview:** a sticky outlined "Preview" button at the bottom (becomes "Stop" while previewing). Preview is live: every change (tempo, pattern, subdivision) is heard immediately.
  - Starting Preview takes over the click with the song being edited; the main click pauses while it plays.
  - Stop ends the preview at once and brings the main click back immediately, with its own tempo and pattern, while you stay in the editor. If the main click was stopped before, it stays silent.
  - Leaving the editor always ends any preview and restores the main click the same way. If you saved the loaded song, the saved changes then apply as described below.
- **Saving the loaded song** (the one on the main screen) while it's playing never restarts the bar. Each kind of change behaves exactly as if it had been made on the main screen:
  - Nothing changed: nothing happens.
  - Tempo: applies from the next click, keeping your place in the bar (like the ± buttons).
  - Accents, muted beats, or subdivision cells: heard from the next click.
  - Subdivision: from the next beat, keeping your place in the bar.
  - Time signature: the next beat starts beat 1 of a bar in the new meter.
  - Saving any other song, or just opening the editor, never touches the click.
- **Usage note:** below the pattern, muted text listing which setlists use the song ("In 2 setlists: Friday set, Rehearsal. Changes apply to both."), since songs are shared.
- **Delete song:** red text button at the very bottom, far from everything else. Always asks for confirmation, naming the setlists it will be removed from.

## Top panels (things open from where you tap)

The two top-row buttons (stopwatch and "4/4") open a **panel that drops down from the top row**, not a sheet from the bottom of the screen. Lists opened from the context row (bottom) open upward from there; settings opened from the top row open downward from there. Your eye and finger stay in the same place.
- **Shape:** 12px from the screen edges, its top edge just under the top row (the top row stays visible and sharp above it), 14px radius, #111111, 1px #2E2E2E border, a soft shadow. Height fits the content (never fixed), and it may grow all the way down to 16px above the bottom of the screen (above the gesture bar), covering the dimmed context row and tabs: nothing down there is needed while you adjust. Only content taller than that scrolls inside.
- **Behind it:** the main screen below the top row is dimmed (60% black). The click keeps playing.
- **Open and close from the button (all panels):** a panel grows out of the button that opened it: it starts at 96% size with its transform origin at that button (the stopwatch, "4/4", or the context row's center button) and opacity 0, and reaches full size and opacity in ~200ms (ease-out). Closing by tap on the dim, tapping the button again, or Back plays the reverse (shrinks slightly toward the button while fading, ~180ms). Closing by swipe follows the swipe instead (below), because the motion should go where the finger pushes. Not a full morph into the button: a large panel collapsing into a 44px button looks slow and heavy.
- **The grab handle has a generous grab area (all panels):** the whole width of the panel, from ~24dp inside the edge with the handle to ~24dp outside it, onto the dim (below the bottom edge for top panels, above the top edge for bottom panels). A drag that starts anywhere in that strip grabs the panel and it follows the finger, even if the finger is a little outside the panel. Taps in the outside part still close as a dim tap does.
- **Predictive back (all panels):** during an Android back gesture, the open panel follows the gesture's progress, scaling 1 → 0.9 toward its button and dimming slightly; on commit it finishes closing (as above), on cancel it springs back to full size. With Remove animations on, all panel motion is instant.
- **Swipe to close never pauses (all panels):** while dragging, the panel follows the finger 1:1. On release past the threshold (or on a flick), it keeps moving in the same direction from exactly where it is, at least as fast as the finger was moving, until it's off the edge (up for top panels, down for bottom ones), fading out as it travels (opacity follows the distance left, reaching 0 as it leaves); ~180ms, ease-in. No stop, no separate fade afterwards. Released before the threshold, it springs back (~180ms ease-out). The dim fades out together with the panel.
- **The dimmed area closes it (all panels, top and bottom):** any touch that *starts* on the dim (a tap, or a swipe in any direction) closes the panel on touch-up, exactly like Back. Touches on the dim never reach the main screen underneath (so a swipe there can't move the ruler or tap a button).
- **Closing:** tap or swipe on the dim, tap the same top-row button again, Back, or swipe the panel up (a 40×4px handle sits at its bottom edge). It opens with the arrive motion downward (fade + 6px drop) and leaves with the leave motion.
- **Contents** are unchanged: "When I press Start" (see `on-start-sheet.reference.html`, `on-start-sheet-off.reference.html`) and Rhythm (time signature, subdivision, polyrhythm). Wherever this spec says "sheet" for these two, it means this top panel.

## Rhythm sheet (time signature, subdivision, polyrhythm)

A top panel (see "Top panels") opened from the "4/4" button on the main screen, titled "Rhythm". See `on-start.reference.html` (column 1; it supersedes `time-signature.reference.html`).

- **Subdivision** (between Custom and Polyrhythm): a 4-part segmented control with the note icons (quarter · eighths · triplet · sixteenths). Applies as you change it; the sheet stays open. While playing, it takes effect at the next beat (as before).

- **Panel behavior:** see "Top panels" (it drops from the top row; swipe up, tap outside, tap 4/4 again, or Back to close).
- Title "Rhythm".
- **Common:** eight one-tap buttons in a 4×2 grid: 2/4, 3/4, 4/4, 5/4, 6/8, 7/8, 9/8, 12/8. The current one is filled white with black text. Tapping one applies it and closes the sheet.
- **Custom:** beats with − / + (1–16), "/", and a 4 | 8 segmented control, same as the song editor. Applies as you change it; the sheet stays open.
- Changing the number of beats keeps existing beat states where possible (new beats are regular; beat 1 keeps its state).
- While playing, a new time signature takes effect on the next beat, which starts a new bar (beat 1). It doesn't wait for the current bar to finish.
- **Polyrhythm** (last row of the sheet): a segmented control "Off · 2 · 3 · 4 · 5 · 6 · 7". The number equal to the current beat count is dimmed and can't be chosen (4 against 4 is just the beat). Under it, one muted line in plain words, e.g. "3 against 4: three even clicks per bar, in their own sound"; with Off it reads "Add a second pulse across each bar". Applies as you change it; the sheet stays open on purpose, because you hear each choice and often try another (3, then 5). Only the common time signatures close the sheet: picking one is a finished choice. See "Polyrhythm".
- In setlist mode this is a change to the loaded song and follows "Changes to a loaded song".

## Polyrhythm

A second pulse that divides each bar evenly, against the main beats (e.g. 3 against 4). See `polyrhythm.reference.html` (main screen, 3 against 4, pulse 2 sounding) and `time-signature.reference.html` (the sheet with the Polyrhythm row).

- **Where it lives:** only in the time signature sheet (tap "4/4"), because it's part of the bar's shape. No new button on the main screen. When on, the time signature button reads "4/4 · 3", so it's never hidden.
- **Choices:** Off, 2, 3, 4, 5, 6, 7 pulses per bar; the one equal to the beat count is dimmed. Default Off. If you change the beats so they equal the chosen number (3 against 4, then pick 3/4), the polyrhythm turns Off.
- **Timing:** pulse k (0-based) of n sits at beat position k × beats ÷ n inside the bar, so pulse 1 lands with beat 1 and the pulses are perfectly even across the bar. Positions are stored in beats, not milliseconds, so tempo changes, the ruler, and Tap tempo carry the pulses along exactly like subdivisions (same clear-and-reschedule). Works for any time signature, including /8.
- **Sound:** the chosen click sound (Woodblock, Beep, Cowbell, Bell) played higher, so it's clearly a separate voice without any new sound files (e.g. ~1.5× playback speed, a fifth up; tune by ear). Accented pulses are louder. Subdivisions keep playing on the main beats only; the polyrhythm has no subdivisions.
- **Lane on the main screen:** shown only when a polyrhythm is on. One row, 22px tall, 3px radius, right under the subdivision strip (2px gap). The n cells are placed by time, not squeezed into the beat grid: each cell starts exactly where its pulse falls across the bar's width (with the same 6px gaps), so cell 1 lines up with beat 1 and you can see 3 against 4 at a glance. Its height comes from the flexible space; the BPM, ruler, and buttons never move.
- **Cell states** work like beat blocks, in a quieter palette: tapping a cell cycles regular → accent → muted → regular (light haptic); all regular by default. Resting: regular #262626, accent #5A1A16, muted dark with a thin dashed outline. Only the sounding cell lights (regular white, accent red #FF3B30) for the length of its pulse, then returns to resting. Muted cells never light.
- **While playing:** turning it on or changing the number starts the new pulses at the next beat, in the bar's own grid (the rest of that bar's pulses play, so there's no wait for beat 1). Turning it Off stops the pulses at once. Cell taps are heard from the next pulse.
- **Saved in songs** like the rest of the bar: song fields `polyrhythm` (0 = off, 2–7) and `polyStates` (one state per pulse). Changing it while a song is loaded follows "Changes to a loaded song" (Revert / Save / Save as new). Free play keeps it across launches with the other click settings.
- **Volume:** a fourth slider "Polyrhythm" in Settings → Volume, default 70%; "Reset" includes it.
- **Visual offset** applies to the lane exactly as to the beat blocks.
- Media controls, setlists, and the "When I press Start" settings are unchanged by it (a count-in plays beats only, without the polyrhythm).

## Settings

A full page opened from the **gear button** at the top right of the main screen (it replaced the ☰ menu: with the song and set pages gone, the menu only held Settings, Send feedback and About, so they're one page now). See `settings.reference.html` (full scroll length). The click keeps playing; back returns to the main screen.

- **What's new block** (top of the page, only after an update): see "First launch and updates".

- **Top bar:** back chevron and "Settings". Changes apply immediately; there's no Save.
- **Theme:** System / Dark / Light segmented control.
- **Click sound:** a 2×2 grid of buttons: Woodblock, Beep, Cowbell, Bell. Default Woodblock. (Classic was removed: it sounded almost the same as Woodblock. A saved "classic" setting loads as Woodblock.) The four are kept clearly apart by character and pitch range: Woodblock (wood, mid), Beep (pure tone), Cowbell (a high, clean agogo-style metal bell, not the drum-machine square-wave one), Bell (a small bright ding, highest of all). Cowbell and Bell are defined in `sounds/click_prototypes.py` (chosen by ear); Woodblock and Beep are unchanged. Selected = filled white. Tapping selects it and plays a short sample. Every tap plays the sample, including a tap on the sound that's already selected, so you can listen as many times as you like. A new tap restarts the sample.
- **Sound on part changes:** one switch, default off, with the hint "For songs with parts: a higher click on the first beat of each new part". See Song parts › Heads-up.
- **Vibration:** one switch, "Vibrate on touch", default on, with the hint "Only when vibration is on in your phone's settings". It can only turn the app's haptics off; it never overrides the system setting.
- **Volume:** four sliders (Accent, Beat, Subdivision, Polyrhythm) with percentages, and a small "Reset" text button on the right of the section heading that resets only the volumes to their defaults: Accent 100%, Beat 80%, Subdivision 45%, Polyrhythm 70%.
- **Visual offset** (stored as `visualOffset`): a large block that flashes on every click, − / + buttons around the current value in ms, and a Start test / Stop test button (primary color). Range −200 to +500 ms, default 0 ms (right for built-in speakers; Bluetooth headsets typically need a positive value, e.g. about 20 ms on the user's headset). The test plays the click on this screen so you can adjust while listening until the flash lands on the sound; if the click is already playing, the test uses it instead of starting its own. Leaving the screen stops a test it started. A short hint explains it's for Bluetooth headphones and doesn't change the sound.
- No reset for the other settings.
- **About** (last section, muted heading): rows "Send feedback" (muted line "Tell Dror what works and what doesn't"), "All updates", "About Metra" (muted line "Why this app exists"), "Privacy policy" (opens the policy, as built for the Play listing), 56px each with ›; then a centered muted version line "Metra 1.0.0 (2)" (long-press copies it).
  - "Send feedback" opens the phone's share/email with an email to metra.application@gmail.com, subject "Metra feedback (v1.0.0 build 2)", and a body that starts with the app version, phone model, and Android version, then an empty line for the message.
  - "About Metra" opens a simple page with Dror's short note on why he made it (written by him), plus one line: "No ads, no account, no tracking. Your songs stay on your phone."

## App icon

The tempo needle: the main screen's ruler ticks with the red needle through the middle, on black. Redrawn Oct 2026 to work at real home-screen size (48px): 9 thick ticks (6/240 wide, majors #B0B0B0 every 4th, minors #5A5A5A), a bold 14/240-wide red needle, all inside the circular mask, filling most of the icon. Sources (vector, 1024×1024):
- `app-icon.svg`: the full icon, square with no rounded corners (the OS applies its own mask). Use for iOS and as the Android legacy icon.
- `app-icon-foreground.svg`: transparent foreground for Android adaptive icons, with the artwork scaled into the safe center area so any mask shape keeps it intact. The adaptive background is solid #000000.

Generate all platform sizes from these (e.g. with `flutter_launcher_icons`, after exporting the SVGs to 1024px PNGs). Check the result at small sizes on the real phone.

## Data model

- **Shared song library.** Each song exists once (name, tempo, time signature, subdivision, beat pattern). Setlists reference songs by id, in order, and the same song can appear in several sets. Editing a song changes it everywhere.
- Per song: tempo, time signature, subdivision (1–4), beat states (accent/regular/muted per beat), polyrhythm (0 = off, 2–7) and its pulse states. Older songs without these fields load as polyrhythm off.

## Behavior

- **Modes:** Free play (no song), Single song (a library song loaded without a setlist), or a setlist. The app always starts in Free play when it is launched fresh (first launch, or after it was closed or killed), stopped, with the tempo, time signature, subdivision, and beat states it last had. **"When I press Start" starts all off in Free play on a fresh launch** (Count-in, Speed up, Stop after), so the first Start after opening the app is always a plain click; a tempo that climbs by itself or a click that stops after 10 minutes is too easy to miss when you didn't just set it. Their values are kept, so switching one back on brings back what you had. Songs keep their own saved settings (those are deliberate, saved with the song). Returning from the background keeps them as they were, like everything else. No song or setlist is loaded; getting back to one is a tap away in the dropdowns. Returning to the app while it's still running (from the background, the notification, or recents) keeps everything exactly as it was. **Swiping Metra away from recent apps closes it:** the click stops, any save in progress finishes, and the app fully closes (otherwise Android keeps it alive for the sound), so the next open is a fresh launch.
- Start always begins on beat 1.
- Subdivision clicks are quieter than beat clicks; accents are loudest. Changing the subdivision while playing takes effect at the next beat, without restarting the bar.
- Next/previous or choosing a song while stopped: load it (tempo, time signature, subdivision, pattern) without starting.
- Next/previous or choosing a song while playing: load it and restart immediately on beat 1 at the new tempo, using the same clear-and-reschedule mechanism as tempo changes.
- **Keep the screen on** while Metra is open and in front (not only while playing), so it never locks between songs at a rehearsal. Settings → "Keep screen on": While Metra is open (default) · Only while playing. Leaving the app lets the phone lock normally. Stage mode always keeps it on.
- **Free play never holds a song.** Loading a song from the library outside a setlist enters Single song mode; Free play always means no song is attached.
- **Detaching a song** (tapping the Free play tab): the song is unloaded, but the click keeps exactly what it sounds like now: tempo, time signature, subdivision, and beat states, including any unsaved changes. While playing, the click carries on unchanged, with no restart. The title clears, Revert / Save to song disappear, and the tempo-name line returns. The song itself is untouched in the library; unsaved changes aren't saved to it. The app is then in Free play. Switching from a setlist to Free play works the same way.
- **Changes to a loaded song** (tempo, time signature, subdivision, beat states changed on the main screen while a song is loaded) are temporary: they play immediately but don't change the stored song. As soon as anything differs from the stored song, the tempo-name line under the BPM shows "Revert" and "Save to song". Save writes the current values to the song (in the shared library, so every set gets them); Revert restores the stored values. Loading another song or switching sets discards unsaved changes without asking. Detaching a song keeps them as Free play settings (see above). Closing the app detaches the song like Free play does: on the next fresh launch the click keeps those settings in Free play, and the song itself is unchanged (unsaved changes aren't written to it). In Free play with no song loaded there's nothing to save, so the line always shows the tempo name.
- **Save as new song** ("Save as new" under the BPM when a song has unsaved changes, or "+ New song from this" in the context row in Free play) opens a dialog (see `save-as-new.reference.html`):
  - Title "Save as new song" (from Free play: "New song"), a Name field focused with a default already filled in and fully selected (the loaded song's name plus the next free number, "Dead Weight 2"; in Free play "Song 10", the next free number), highlighted with the accent color. Cancel / Save.
  - Only in setlist mode, a choice "In Friday set": **Replace Dead Weight** (default; the new song takes its place in the set, same position), **Add after Dead Weight** (both stay), **Don't add** (the app leaves the set and plays it in Single song mode).
  - Save creates the song in the library from the current tempo, time signature, subdivision, and beat states, and makes it the loaded song. The click carries on unchanged, no restart. The original song is untouched (in the library and in other sets). Nothing is unsaved anymore, so the tempo-name line returns.
  - From Free play or Single song there's no set question; the app is then in Single song mode with the new song.

## First launch and updates

- **Example content (first launch only):** a fresh install with an empty library gets 4 example songs and 1 example set, so every list, gesture and hint has something to show on. The app still opens in Free play.
  - Songs: "Example · Rock" (120, 4/4, beat 1 accented), "Example · Waltz" (90, 3/4), "Example · Shuffle" (100, 4/4, triplet subdivision), "Example · Odd" (140, 7/8, accents on 1, 3, 5).
  - Set: "Try me" with all four, in that order.
  - They're ordinary songs and sets: play, rename, reorder, delete. Never re-created once deleted (stored flag), and never added to a library that already has songs (an update or a restore from backup doesn't add them).
- **What's new (after each update):** the first time the app opens after an update, the gear button shows a small red dot (8px, top-right corner of the button). Settings then shows, at the top, a muted block: "New in 1.0.3", up to 3 short lines ("Add a new song straight to a set", …), and two quiet text buttons: "All updates ›" and "Got it" (hides the block and the dot until the next update). Opening Settings also clears the dot. A fresh install shows no block. Never a popup.
  - **All updates:** a simple page, newest version first: each version as a small heading ("1.0.3 · Oct 2026") with its lines under it. Reached from "All updates ›" in the block and from the "All updates" row in Settings → About, so it's always findable after "Got it".
  - **One source:** `assets/whats_new.md` holds every version, newest first (a "## 1.0.3 · Oct 2026" heading, then "- " lines). The block shows the top version; the page shows all of it; the top version's lines are also the Play Store release notes.

## Stage mode

A full-screen, play-only view of the loaded set, for gigs. Nothing on it can edit anything, and leaving it takes a deliberate hold. See the board "Stage mode" (`stage-mode.reference.html`).

- **Entering:** only from a set: the outlined "Stage mode" button in the set panel ("4/12 ⌄"), next to "Add songs". Two deliberate taps, visible, never a hidden gesture. The click keeps playing; the current song stays.
- **Screen:** always on; full immersive (status and navigation bars hidden), so a stray edge swipe or pull from the top only reveals the bars. Portrait as everywhere.
- **Shown, top to bottom:** a small "Hold to exit" control (left) and the time of day (right, muted); the song title large (44px, shrink to fit, centered); "Friday set · 4 of 12" (muted); the beat blocks, larger (64px tall) with the same lights; the BPM, large and read-only, with a muted line "4/4 · count-in 1 bar" (time signature plus anything on in "When I press Start"); then Previous and Next side by side (104px tall, each with "‹ Previous" / "Next ›", the song name and its BPM), and a full-width Start/Stop (96px).
- **Not shown:** the ruler, −5/−1/+1/+5, Tap, the top-row buttons, the tabs, the Revert/Save line, every long-press and swipe. Changes can't happen here.
- **Taps:** Previous, Next and Start/Stop are plain taps, playing or not (same rules as on the main screen: playing, a new song restarts on beat 1 with its count-in). Rapid tapping is allowed, so you can skip several songs quickly: only a second tap within ~0.12 s is ignored (a finger bounce or double contact, faster than anyone taps on purpose). While playing and tapping several times in a row, the song shown moves with every tap, but the click restarts only once, ~0.3 s after the last tap, on the song you landed on (with its count-in), instead of restarting for every song you pass. On the first song Previous reads "Start of set" and does nothing; on the last, Next reads "End of set".
- **Jumping:** tapping "Friday set · 4 of 12" opens the set's list read-only (tap a song to jump to it, like Next; no swipe, no reorder, no "Change set", no "Add songs").
- **Leaving (the only hold):** the exit control looks different on purpose: a pill with a dashed outline, a lock icon and "Hold to exit". Holding it 1 s fills it left to right and exits; releasing early resets it. A tap shows the hint "Hold to exit stage mode" in the line above the buttons. **Android Back:** in full screen Android itself swallows the first back swipe (it reveals the bars and says "swipe again to go back"); a second back gesture then **leaves stage mode**, as the system message promises. Two back swipes in a row are deliberate, so this is safe, and it behaves the way Android users expect. The hold stays as the visible way out. Exiting returns to the normal main screen, same song, click unchanged.
- **Unchanged:** pedals, keyboard shortcuts, lock-screen and notification controls, the Quick Settings tile, count-in / speed up / stop after (as saved in each song).
- **Remembered:** stage mode stays on across a crash or relaunch until you exit it (the one exception to Principle 10).
- **One-time tip** on first entry, in the line above the buttons for ~5 s: "Tip: turn on Do Not Disturb so calls don't interrupt the show." (Metra never changes Do Not Disturb itself: that would need a new permission.)
- **Haptics:** medium on song change and Start/Stop, as usual; a light tick when the exit hold completes.
- **Details:**
  - The "Stage mode" button is disabled (dimmed, with the hint "Add songs first") when the set is empty.
  - Colors follow the app's theme like everywhere else (no separate setting): Stage Black is the default and right for dark stages, and someone who chose Daylight usually did it for bright rooms or outdoor daytime gigs, where a dark screen is hard to read in sunlight.
  - With Speed up or Stop after on, the muted line under the BPM shows the same progress as the main screen while playing ("↗ +5 every 8 bars · next in 3 · 4:12 left"); the BPM follows the live tempo.
  - **Unsaved changes when entering:** stage mode always plays songs exactly as saved. If the current song has unsaved changes, entering reverts them (an accidental change on stage is worse than losing a deliberate one that wasn't saved). No question; the line above the buttons says "Playing the saved version of Dead Weight" for ~3 s. If the click is playing, the saved values apply like any tempo/pattern change (no restart). Inside stage mode there's no Revert/Save.
  - TalkBack: the exit control is labelled "Exit stage mode, double-tap and hold"; Android's own double-tap-and-hold triggers the hold.

## Haptics

Haptics confirm a touch, so you can trust a press on stage without looking. Use the platform's standard haptic types. Haptics play only when both the phone's system vibration setting and the app's "Vibrate on touch" setting (Settings, default on) allow it.

- **Medium** (important stage actions): Start/Stop; next/previous and choosing a song in the picker (the song changed); any "Free play" button (the song detached); choosing a set in the sets view; long-press lifting a row to reorder.
- **Light tick** (small adjustments and selections; also a swipe crossing its commit point): every −5/−1/+1/+5 step, whether tapped or produced by holding (a held button feels like a ratchet; a medium bump when a hold hits 30 or 300); the beats −/+ steps; each Tap tempo tap; the ruler crossing a multiple of 5 (only fives, since a drag passes values too fast to tick each one); tapping a beat block, the subdivision button, a time signature, or a cell in the song editor; Save to song, Save as new, and Revert; marking or unmarking a row (removing songs, deleting sets); a swipe crossing its commit point in a list, either way (none on release, so a swipe never buzzes twice).
- **None:** never on the beat itself or any automatic event; not for scrolling, opening sheets, volume sliders, or ordinary navigation.

## Media controls (notification and lock screen)

The system media card (Android media notification / lock screen, iPhone Now Playing). Minimal: no new controls, just enough content that it doesn't look empty. See `media-controls.reference.html` and `media-cover.reference.html`.
- **Cover image** (the card's artwork and the notification thumbnail; recent Android versions also use it as the card background): style "Tempo ruler", a mini main screen. A generated square, 512×512, black (#000000):
  - The current BPM in white Saira Extra Condensed 700, ~48% of the height, tabular figures, centered horizontally and sitting a little above center.
  - Under it, a full-width slice of the tempo ruler: a thin #1F1F1F top line, minor ticks (#4A4A4A, short) and every fifth tick longer (#8C8C8C), and the red needle (#FF3B30) at the center, slightly taller than the long ticks. No numbers on the ruler.
  - Regenerated whenever the tempo changes. Always dark, in both themes.
- **Title:** the song name, or "Free play".
- **Subtitle:** "120 bpm · 4/4"; in setlist mode add " · Friday set 4/12".
- **One Start/Stop toggle only:** ▶ when stopped, ❚❚ (the system pause icon) when playing. On the card it uses the standard play/pause icons, which recent Android versions draw themselves and everyone recognizes; inside the app the button stays "■ Stop". Either way it behaves as Stop. There is no separate Pause and no separate Stop action (a metronome has nothing to resume; Stop always means "stop, ready to start again from beat 1"). Don't expose ACTION_PAUSE or ACTION_STOP as their own buttons; map system pause/stop requests (headset, car, watch) to the same toggle. Stopping from the card never removes the card (see "When it's shown").
- **Controls depend on the mode** (Android's media card has five slots: Start/Stop plus four):
  - **Setlist mode:** Previous song · Start/Stop · Next song. No tempo buttons: in a set the song's tempo is the song's. Headphone double/triple-press, car, and watch controls change songs.
  - **Free play and Single song:** −5 · −1 · Start/Stop · +1 · +5, as custom actions (small icons drawn as the numbers). The cover shows the BPM, so you see each change. They change the tempo exactly like the main screen's buttons (no hold-to-repeat here). In Single song mode a change is an unsaved change to the song, as on the main screen. No Previous/Next: headphone double/triple-press does nothing in these modes.
  - Where Android shows a compact version (collapsed notification, some lock screens), it keeps Start/Stop and the two nearest buttons (−1 / +1, or Previous / Next).
- **No progress bar / seek bar:** a metronome has no duration (declare no duration so Android doesn't draw an empty bar).
- Title, subtitle, and cover stay in sync with the main screen (tempo, song, time signature, set position).
- **When it's shown:** the media card (notification shade, lock screen, and the system's playing indicator in the status bar, e.g. OnePlus's Live Alert pill) appears whenever the click is playing. If the click was stopped from outside the app (the card's Stop, the Quick Settings tile, headphones, a watch), the card stays, in its stopped state with Start, so you can restart it; it can be swiped away then. Stopping from inside the app removes it. Closing the app removes it.
- It's a real media session (MediaStyle notification tied to the foreground media service), which is what makes Android show it in the media area, the status-bar pill, and the lock screen, and it doesn't need the notification permission.

## Keyboard and foot pedals

Most Bluetooth page-turner pedals send keys, so these work with them as well as with a keyboard:
- Space: Start/Stop. T: Tap.
- ↑ / ↓: tempo ±1; with Shift, ±5.
- Page Up / Page Down and ← / →: previous / next song.

## Platforms

- **Orientation:** phones are locked to portrait (Android and iPhone, including upside-down off). No landscape layout. On iPad, if it's ever shipped there, set "Requires full screen" so portrait-only is allowed. The Mac window is unaffected.

- **Android:** plays alongside other audio (doesn't take audio focus away from music apps). Stops when headphones are unplugged. Media controls on the lock screen and in the notification (see Media controls). Swiping the app away from recents stops it.
- **iPhone:** plays with the silent switch on and with the screen locked, alongside other audio. Lock-screen controls and stop-on-headphone-unplug aren't built for iPhone yet.
- **Mac:** runs the phone layout in a phone-shaped window that can be resized. No dedicated wide layout.

## Android basics

- **Calls and other audio:** the click keeps playing alongside music. A phone call pauses it and it resumes after the call (current behavior, kept on purpose).
- **Background:** the click must keep going with the screen off and the app in the background for a full set (test 10+ minutes, especially on OnePlus). It runs as a foreground media service with the media notification.
- **Volume keys** control Metra's volume in the app, outside it, and on the lock screen (already working). Inside the app they change media volume even while the click is stopped (the activity's volume control stream is media), so pressing them before Start never changes the ringer.
- **Launch screen and system bars:** the launch screen is black (#000000; #F3F1EC in Daylight) with the app icon, so there's never a white flash. Status and navigation bars match the theme (dark bars and light icons in Stage Black, the reverse in Daylight). The app draws edge to edge and keeps all content clear of the status bar, notch, and gesture bar.
- **Backup:** Android's automatic backup is on for the library (songs, setlists, settings), so a reinstall or a new phone restores it from the user's Google backup. No permission or sign-in in the app.
- **Language and direction:** English only. The layout never mirrors, even on a Hebrew or Arabic phone (always left to right).
- **Quick Settings tile:** a "Metra" tile users can add to the pull-down panel. It shows Playing / Stopped and tapping it starts or stops the click with the current song and tempo. No permission needed. If Android doesn't allow starting audio from the tile without the app, the tile opens the app and starts.
- **Back (predictive back, Android 16 target):** Back always closes one level at a time, and the system's back preview shows that level, never the home screen while something is open. Order, innermost first: rename field (cancels the rename) → delete dialog (Cancel) → song picker or sets view (back to the set's songs) → the panel itself (closes) → Rhythm sheet / When I press Start sheet (closes) → a page (back to where it was opened from). Only on the bare main screen does Back leave the app. Back never stops the click.

## Accessibility

Target: Android's own accessibility checks and WCAG AA, without changing the stage look.

**1. Large text (system font size up to 200%)**
- Lists, the Menu, Settings, dialogs, the sheets and the panels follow the system size fully. Rows keep their minimum height and grow taller when text needs it; names stay one line with "…".
- Main screen: the BPM number doesn't scale (it's already huge and its size is fixed per screen). Everything else on the main screen (title, tempo name, button labels, context row, tabs) scales up to 1.3×, then stops, so the layout never breaks or overlaps.
- Test at 100%, 130% and 200%, and at the largest "Display size".

**2. Contrast**
- Readable text uses only the "text" or "muted text" tokens (muted #8C8C8C passes AA on every dark surface up to #1F1F1F). The darker greys used today for small text (song numbers, time signature columns, hints, "‹ Back") move up to muted text; hierarchy comes from size and weight instead.
- "Disabled text" is allowed only for things you can't use (songs "In this set" in the picker, the dimmed polyrhythm number); disabled items are exempt from contrast rules.
- Outlines that you need to see in order to use something (unchecked checkboxes, the search field) use "control outline" (3:1 or better). Decorative borders and dividers stay as they are.
- Check Daylight the same way.

**3. Screen reader (TalkBack)**
- Every control has a spoken name and state. Icon-only buttons: "Time signature 4/4, eighth notes, polyrhythm 3", "When I press Start (count-in on)", "Settings", "Start" / "Stop", "Tap tempo".
- Beat blocks: "Beat 1, accented" (regular / muted), with the hint "Double-tap to change". Polyrhythm cells the same ("Pulse 2 of 3, regular").
- BPM and ruler: one adjustable control, "Tempo, 120 BPM, Allegro"; swipe up/down changes by 1. The −5/−1/+1/+5 buttons announce the new tempo.
- Context row: "Previous song: Iron Lung, 98 BPM", "Friday set, song 4 of 12, opens song list", "Next song: …". Tabs announce as tabs with "selected".
- Lists: each row reads name, tempo, time signature, and "playing" for the current one; the swipe, reorder and rename gestures are also offered as actions ("Remove from set", "Delete song", "Delete set", "Move up", "Move down", "Rename").
- Nothing is announced on each click while playing (that would talk over the music); only Start/Stop and song changes are announced.

**4. Touch targets**
- Every tappable thing has at least a 48×48dp touch area (Android's minimum), even when it looks smaller: the 44px top-row buttons, "‹ Back", "Undo", ×, and the long-press title get invisible padding. Visuals don't change.

**5. Reduced motion**
- With Android's "Remove animations" on, list and sheet animations become instant and the one-time swipe hint is skipped (its flag is still set). The beat lights are not animations and stay as they are.

## When I press Start (count-in, speed up, stop after)

Everything that happens over time after Start, in one top panel (see "Top panels") opened from the stopwatch button. See `on-start.reference.html` (columns 2 and 3).

**Premise: these belong to the song, like its tempo.** Everything on the main screen, including this sheet, describes the current song. Changing count-in, speed up or stop after while a song is loaded is an ordinary change: Revert / Save / Save as new appear, and Save stores it in the song. In Free play they're Free play's own settings and are remembered like its tempo. There is no separate global setting, so "what will Start do?" always has one answer: whatever this song (or Free play) says, shown by the red stopwatch.

Sheet title "When I press Start", three parts, all off by default.

**Every part looks the same when off:** one 56px row, the part's name on the left (18px, semibold, white: these are the sheet's main headings) and a switch on the right. **Off is not disabled:** an off switch is a clear outlined control in white (2px white border, white knob, transparent track), never greyed out; the row's name stays white. On: white track, black knob. Switching it on opens the part's controls under the row (arrive motion); switching it off folds them away (leave motion) and keeps the values for next time. When a part is on, a muted one-line summary sits under its name ("1 bar", "+5 every 8 bars, up to 160", "10:00"). So the closed sheet is three equal rows, and only what's on takes space.

**Choices inside a part are quiet chips, not big white blocks,** laid out like the stepper rows: a label on the left, the chips on the right ("Length  [1 bar] [2 bars]" in Count-in, "Count by  [Bars] [Time]" in Stop after). 36px pill chips sized to their text. Selected: #2A2A2A fill, 2px white border, white 600 text. Not selected: transparent, 2px #2E2E2E border, muted text. Nothing in this sheet is filled solid white except an on switch, so no single control shouts.
- **Count-in** (switch; when on: a "Length" row with 1 bar · 2 bars chips, default 1 bar). Plays the song's own click sound, **beats only** (no subdivisions, no polyrhythm), beat 1 accented, at the song's tempo and time signature. Then the song starts on beat 1. Hint: "Beats only, before the song. Not counted in the steps or the limit."
  - **On screen:** the beat blocks show their numbers (1 2 3 4) in the block, muted, and light as they sound; subdivision ticks stay dark; the line under the BPM reads "Count-in · 3 of 4" (bar 2 of 2: "Count-in · 2 · 3 of 4"). When the song starts, the numbers disappear and everything is normal. Nothing moves.
  - **Shown from the moment you press Start:** the ~300 ms before the first click sounds already counts as the count-in, so the line reads "Count-in · 1 of 4" at once (beat 1's block lights only when it sounds). It never shows a generic "Count-in" first and then jumps to the count (seen in build 81; same fix as the heads-up).
  - **The button you pressed shows the count, on every page:** the count-in belongs to the whole song, so during it the red Stop button reads "■ Stop · Count-in 3 of 4" ("Stop" semibold, the count regular) on the main screen, the parts page and in stage mode, then just "■ Stop" when the song starts. Same button size; tapping it still stops. The button shows the beat only; in a 2-bar count-in the bar number stays on the line under the BPM (built 81–87). If it doesn't fit on one line (narrow phone, large text), it becomes two lines inside the same button size: "■ Stop" on the first, "Count-in 3 of 4" under it (smaller); "Count-in 3 of 4" is never split and the word is never dropped.
  - **On the parts page, the summary line becomes a small count-in tag that fills:** during the count-in, the line under the title shows a small tag, left-aligned, sized to its text (24px tall, 2px white border, 4px radius, bold 14px "Count-in · 3 of 4", fixed width so it never jumps as the numbers change). It fills white from left to right across the **whole** count-in, smoothly and timed to what you hear (a 2-bar count-in is one slower fill, not two); where it's filled the text is black. The text counts the beats of the current bar; the fill shows how much of the whole count-in is left. When the song starts it turns back into the summary and the first card's fill takes over. The summary line always takes the tag's height (24px, text centered), so nothing moves. "Remove animations": steps once per beat. (Rejected: the count in the first part's card, since the count-in isn't part of Intro; a full-width bar, too heavy. Board "Detail · Count-in on the parts page".)
  - On the main screen and in stage mode, the line under the BPM and the numbered beat blocks stay as they are; the button adds the same count where your finger is.
  - **When it plays:** every time playback starts from stopped (Start, media controls, the Quick Settings tile), and when a song is loaded while playing (Next/Previous, choosing a song), if **that** song has a count-in. A song without one starts right away, as today.
  - Stop during a count-in stops; Start again counts in again.
- **Speed up** (switch, then three steppers): "Change by" (+1 to +20, or negative to slow down), "Every" (1–64 bars; bars only, never beats: a change mid-bar would break "changes land on bar lines", and +1 every bar is already a smooth climb), "Up to" ("Down to" when Change by is negative; a tempo, or "No limit"). Starts from the tempo when Start is pressed. **Timing:** the new tempo starts exactly on beat 1 of the new bar: the last beat of the old bar keeps the old tempo all the way to the bar line (the interval from the last beat to the next beat 1 is the old tempo); the first interval at the new tempo is beat 1 → beat 2. At "Up to" it holds and keeps playing. **Up to vs Stop after:** they work together: Up to is how fast, Stop after is how long ("climb to 160, then keep playing there until 10:00"). Up to must be beyond the starting tempo: when editing, it can't be set at or below the current tempo (above it for Down to); if the tempo is later changed past it, at Start the progress line says "Up to 160 · already there" and no steps happen. Changing the tempo by hand while it runs makes that the new current tempo; the steps continue from it. Hint: "Each change lands on a bar line."
- **Stop after** (switch; when on: a "Count by" row with Bars · Time chips, default Time), then the "Length" stepper (bars 1–999, or mm:ss), so it reads "Stop after · Length 10:00". The click stops at the next bar line after the limit, never mid-bar. In a set it stays on the same song (never advances by itself). Hint: "Stops at the next bar line after the limit."
- **Editing the values (all steppers in this sheet):** three ways, from fastest to finest, so no value ever takes many taps:
  - **Tap the value to type it.** The value sits in an outlined field between − and + (looks editable). Tapping opens the number keyboard with the value selected; type and press Done (or tap outside). Out-of-range values snap to the nearest allowed one. Time fills from the right like a microwave: typing 1, 2, 3, 0 gives 12:30.
  - **− / + with steps that fit the unit:** Change by ±1. Every: ±1 up to 16 bars, then ±4. Up to: ±5 (the ruler's grid), between the current tempo + 1 and 300 (Down to: 30 to the current tempo − 1), and the first tap from "No limit" starts at the current tempo + 20 (− 20 for Down to). Stop after, bars: ±1 up to 16, ±4 up to 64, then ±8. Stop after, time: ±15 s up to 2:00, ±30 s up to 10:00, then ±1 min.
  - **Hold − / + to repeat, accelerating** (the same feel as the main screen's tempo buttons): ~0.4 s before repeating, then faster the longer you hold; one medium haptic at a limit.
  - No drag-to-scrub on values: it's hidden, and it would fight the panel's own swipe to close.
  - **Up to** shows "No limit" by default; − from its lowest allowed value or clearing the field returns to "No limit".
- **Engine requirement (for later):** the click scheduler must be able to change tempo on any beat, not only on bar lines, so a future smooth ramp in song sections needs no timing rework. Speed up itself still changes only on bar lines.
- **Together:** "+5 every 8 bars up to 160, stop after 10:00" climbs to 160, holds, stops at 10 minutes.
- **Reset:** Stop, or reaching the limit, returns the tempo to where it started, so the next Start replays the same exercise.
- **While playing:** the line under the BPM shows progress when speed up or stop after is on ("↗ +5 every 8 bars · next in 3 · 4:12 left"). Unsaved changes still show Revert / Save there while stopped; progress takes the line while playing.
- **Build order:** step 1 = Rhythm sheet with subdivision, stopwatch button, sheet with Count-in only (Speed up and Stop after not shown yet). Step 2 = Speed up and Stop after.
- **Later (parked, see "Song maps"):** a song made of sections (tempo, time signature, subdivision and bar count per part). Speed up and Stop after are the first, simple form of that; the full version needs a real song editor.

## Parked ideas

- **Organizing a big library (folders):** parked. Setlists already group songs (a set can simply be "all of band X"), and search covers finding one song. If testers' libraries get unwieldy, the preferred next step is a filter row in the Songs list and library (All · each setlist as a chip) rather than a separate folder concept, so there's still only one way to group songs.

- **App shortcuts:** long-press the app icon for "Free play" or "Last setlist".
- **Crash reporting:** skipped for now (needs a third-party account and conflicts with "no tracking"); feedback comes through Send feedback.

- **Landscape layout:** for a phone clamped sideways on a drum stand. Parked; portrait-only for now.

Not planned; recorded so they aren't lost.
- **Gap trainer:** play N bars, then mute N bars, to practice keeping time without the click.
- **Song maps (sections):** now designed as "Song parts" (see that section). Original notes: a song made of sequential sections, each with its own bar count, tempo, time signature, subdivision, and pattern (e.g. intro: 8 bars at 140 in 4/4, then verse: 16 bars at 160 in 7/8), played automatically in order.
  - Data: a song becomes a list of sections. Today's song is one section with no bar limit, so existing songs carry over unchanged.
  - Main screen: show the current section's name and a bar countdown ("Verse, bar 5 of 16"), plus the next section's tempo, the way Next shows the next song.
  - Song editor: a section list; a song with no sections looks and works exactly as today.
  - Playback: Start runs the map from the top; starting from a chosen section is a useful extra.
  - End of a map: by default the click stops and the next song in the set is loaded and ready, so the band starts it with one tap on Start. Songs don't run into each other automatically.
  - Segues are configurable per transition, not per set: in a set's songs, a small link toggle between two rows ("Continue into next song") makes that one song flow straight into the next. Off by default.
  - No set-level "Play" button: Start always plays the current song, and linked pairs carry on by themselves.
- **Favorite setlists:** a star to pin sets above the recently-played order. Parked because recently played already keeps the active sets on top; revisit if people keep many sets.
- **Share a setlist as text** (ideas from Oct 2026, ranked): one button sends the set through the phone's share sheet as plain text, e.g. "Friday set: 1. Iron Lung (98) 2. Dead Weight (120)…", so bandmates get the running order with tempos (no accounts, no new permissions). The reverse fits too: paste a list of song names to create a set and its songs at once.
- **Count-in per song:** one or two bars of click before the song starts, saved with the song. Small to build, used constantly by drummers.
- **Duplicate a set:** copy a set (e.g. "Weddings · standard") as the start of a new one, then reorder or remove songs in the panel.
- **One-line note per song:** a short note ("start on hi-hat, 2 bars", "capo 3") shown quietly under the title on the main screen.
- **Removed (Oct 2026):** the set page, the Setlists ("What to play") page and the song library page. Everything they did lives in the main-screen lists. Bulk delete and the library's sort went with them; bring them back to the lists if people miss them.
- **Add an existing song to a set from the Songs list** (swipe right = "Add to a set" with a set chooser; designed Oct 2026, board "Songs list: swipe right…"). Parked: the set-first picker already adds existing songs (several at once), the New song dialog covers new ones, and a second swipe meaning would break the "both directions do the same" rule. Revisit if testers still look for a song-first way.
- **Smooth tempo ramps in song sections** (accelerando / ritardando): "from 120 to 140 over 8 bars", easing the tempo a little on every beat. Belongs to Song maps (needs a real song editor). The engine already supports per-beat tempo changes for it.
- **Song parts, later:** looping the current part from the main screen (a loop button on the parts line; drawn on the "Detail · Song parts ideas" board; decided Oct 2026 it's not worth another main-screen button, since practising one part has other ways); repeat a part ×N (Length covers identical repeats and Duplicate covers repeated ramps for now); duplicating several parts at once (e.g. a verse + chorus block, needs multi-select); a count-in per part; continuing straight into the next song in a set (segues); a whole-song tempo shift.
