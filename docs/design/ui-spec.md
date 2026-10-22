# Metra UI Spec

Design references (design-tool files: read them for exact sizes and colors, don't port their markup):
- `main-screen.reference.html`: main screen with a setlist loaded.
- `free-play.reference.html`: main screen in Free play.
- `free-play-song.reference.html`: Single song mode (a library song loaded without a setlist; same bar as Free play, the title shows the song, no subtitle).
- `beat-states.reference.html`: the beat blocks at three moments in a bar.
- `song-editor-collapsed.reference.html`: the song editor as it opens (pattern collapsed).
- `song-editor.reference.html`: the song editor with the pattern section expanded, full scroll length.
- `unsaved-song.reference.html`: main screen with unsaved changes to the loaded song.
- `save-as-new.reference.html`: the Save as new song dialog (in a setlist).
- `media-controls.reference.html`: lock-screen media card and compact notification (setlist, playing).
- `media-cover.reference.html`: media card in Free play (stopped) and the generated cover image.
- `time-signature.reference.html`: the time signature sheet.
- `menu.reference.html`: the Menu side panel open over the main screen.
- `settings.reference.html`: the Settings page at full scroll length.
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
10. **Predictable memory.** The app remembers within a session; a fresh launch starts in Free play. It never guesses across launches.
11. **Plain, positive words.** Labels say what happens ("Free play", "New song"), never what's lost; the same word for the same action everywhere.
12. **Free, private, simple.** No ads, no accounts, no tracking; data stays on the phone. A new feature must not add a permission prompt.

## Theme

All colors live in one theme file. No hardcoded colors in widgets.

| Token | Stage Black (dark) | Daylight (light) |
|---|---|---|
| background | #000000 | #F3F1EC |
| sheet background (time signature sheet, dialogs) | #111111 | #ECE9E2 |
| surface (filled buttons) | #1A1A1A | #E3DFD6 |
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

Theme setting: System (default) / Dark / Light, persisted. System follows the OS. The Daylight values are a first pass; check them on a real screen.

## Long-press rule

Long-press means "edit it", as a shortcut. In a set's songs (an ordered list), editing means moving: long-press lifts the row and dragging reorders. In the Songs list and the sets view, long-press renames in place. Long-pressing the song title on the main screen opens the song editor. Never on stage-critical buttons (Start/Stop, tempo, previous/next, the context row's center button).

## Icons

- **Setlist:** "note queue": three lines (the last one short) with a music note at the lower right. Used on the Setlists button, the setlist header, set rows, and the Setlists dropdown. Distinct from the Menu icon.
- **Menu:** ☰, three equal lines.
- **Song:** a single music note (Songs button).
- **Free play:** the metronome (the Free play row in dropdowns, Free play buttons and rows).

## Fonts

Bundle as assets; don't fetch at runtime.
- Saira Extra Condensed 600/700: BPM numbers (including tempos in lists), song title, time signature, ±buttons.
- Saira 500/600: everything else.

Labels are sentence case ("Start", "Stop", "Tap"), not all caps. Every interactive element is at least 44×44.

## Main screen (phone portrait, 24px side padding)

Top to bottom:

1. **Top row.** Current song title on the left (Saira Extra Condensed 700, one line). **Shrink to fit:** it starts at 34px and, if the name doesn't fit, shrinks step by step down to 22px; only if it still doesn't fit at 22px does it end with "…". That keeps around five words readable without ever wrapping. **Fixed lines:** the title has a fixed-height line box (sized for 34px) and the subtitle line is anchored to the bottom of the 54px block, so the subtitle never moves when the title shrinks; a smaller title sits at the bottom of its line box, right above the subtitle (aligned on the baseline). It shows the loaded song's name in setlist and Single song mode, and is empty in Free play. Under it, a small muted subtitle (Saira 14px, #8C8C8C, one line, ellipsis), like a song's artist line: the setlist's name in setlist mode; empty in Single song mode (it blends in; the subtitle line still reserves its height so the title sits in the same place). In Free play the title block is empty (saving lives in the context row: "+ New song from this"). The title block is a fixed 54px tall in every mode, so nothing shifts. The title has no buttons next to it. Long-press the title (medium haptic) to open the song editor for that song. Taps do nothing. These are small targets on purpose: shortcuts, not the main route. On the right, three outlined 44×44 buttons, 4px radius: subdivision, time signature ("4/4"; with a polyrhythm on it reads "4/4 · 3" and widens to fit), Menu (☰).
   - **Subdivision button** shows the current value as a vector music-note icon: quarter note (1), beamed eighths (2), triplet (3, beamed with a small "3"), beamed sixteenths (4). Tapping cycles 1 → 2 → 3 → 4 → 1. No menu.
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
- **Delete asks, remove undoes.** One rule for every list: swiping something that deletes your own work (a song from the library, a whole set) asks first in a small dialog, because a song can hold real work (and later trainer settings) and is shared by sets; after confirming, the same Undo bar still appears as a second chance for a mistaken tap. Swiping that only takes something out of a list (a song out of a set) deletes nothing, so it's immediate with the Undo bar. See `delete-confirm.reference.html`.
- **No "Free play" rows in the dropdowns:** Free play is the middle mode tab, always visible.
- **Panel structure:** the search field (when shown) is pinned at the top and the action rows ("+ New song ›", "+ New setlist ›", "+ Add songs ›") are pinned at the bottom; only the list between them scrolls. The pinned action group is separated from the list by a 2px #2E2E2E line, and its rows by 1px #1F1F1F lines, so actions never read as list items.
- **Long-press a row:** in the Songs list and the sets view it renames in place; in a set's songs it reorders (see Set ⌄).
- **Empty lists:** the context row already says it ("No songs yet" / "No setlists yet" / "No songs in this set") with a "+" button: "+ New song" opens the Songs list with a new row in rename state; "+ New setlist" opens the sets view with a new set in rename state (then the song picker); "+ Add songs" opens the set panel's song picker. Inside an empty list, the pinned "+" button is the only row.

## Song editor

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

## Time signature sheet

A bottom sheet opened from the "4/4" button on the main screen. See `time-signature.reference.html`.

- **Sheet behavior (Android standard):** drag the sheet (or its handle) down to close; it follows the finger and closes past about a third of its height or on a downward flick, otherwise it springs back. Tapping the dimmed area above and Back also close it. The click keeps playing.
- Title "Time signature".
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
- Media controls, setlists, and the trainer are unchanged by it.

## Menu

The ☰ button at the top right of the main screen opens a **side panel** that slides in from the right (304px wide, #111111, 1px #2E2E2E left border) over the dimmed main screen. It's a short list of places to go: Settings, Send feedback, About. Songs and sets are managed in the lists on the main screen. The click keeps playing. Tap outside, swipe it right, or use back to close it. Opening it gives no haptic. See `menu.reference.html`.

- **Title** "Menu" at the top.
- **"Settings"** (gear icon, muted line "Sound, volume, theme", ›), **"Send feedback"** (muted line "Tell Dror what works and what doesn't"), **"About Metra"** (muted line "Why this app exists"). Rows without an icon keep the icon column empty so the labels line up.
- At the bottom of the panel, centered and muted: "Metra 1.0.0 (2)" (version and build). Long-pressing it copies it.
- **Panel behavior (Android standard):** swipe it toward the right edge to close (it follows the finger, closes past about a third or on a flick); tap outside or Back also close it. Max width 360dp. While it's open, a screen reader stays inside it and reads it as "Menu".
- Rows are 56px, separated by 1px #1F1F1F lines. Tapping a row closes the panel and opens that page; back from any of these pages returns to the main screen.
- "Send feedback" opens the phone's share/email with an email to metra.application@gmail.com, subject "Metra feedback (v1.0.0 build 2)", and a body that starts with the app version, phone model, and Android version, then an empty line for the message.
- "About Metra" opens a simple page with Dror's short note on why he made it (written by him), plus one line: "No ads, no account, no tracking. Your songs stay on your phone."

## Settings

A full page opened from Menu → Settings. See `settings.reference.html` (full scroll length).

- **Top bar:** back chevron and "Settings". Changes apply immediately; there's no Save.
- **Theme:** System / Dark / Light segmented control.
- **Click sound:** a 2×2 grid of buttons: Woodblock, Beep, Cowbell, Bell. Default Woodblock. (Classic was removed: it sounded almost the same as Woodblock. A saved "classic" setting loads as Woodblock.) The four are kept clearly apart by character and pitch range: Woodblock (wood, mid), Beep (pure tone), Cowbell (a high, clean agogo-style metal bell, not the drum-machine square-wave one), Bell (a small bright ding, highest of all). Cowbell and Bell are defined in `sounds/click_prototypes.py` (chosen by ear); Woodblock and Beep are unchanged. Selected = filled white. Tapping selects it and plays a short sample. Every tap plays the sample, including a tap on the sound that's already selected, so you can listen as many times as you like. A new tap restarts the sample.
- **Vibration:** one switch, "Vibrate on touch", default on, with the hint "Only when vibration is on in your phone's settings". It can only turn the app's haptics off; it never overrides the system setting.
- **Volume:** four sliders (Accent, Beat, Subdivision, Polyrhythm) with percentages, and a small "Reset" text button on the right of the section heading that resets only the volumes to their defaults: Accent 100%, Beat 80%, Subdivision 45%, Polyrhythm 70%.
- **Visual offset** (stored as `visualOffset`): a large block that flashes on every click, − / + buttons around the current value in ms, and a Start test / Stop test button (primary color). Range −200 to +500 ms, default 0 ms (right for built-in speakers; Bluetooth headsets typically need a positive value, e.g. about 20 ms on the user's headset). The test plays the click on this screen so you can adjust while listening until the flash lands on the sound; if the click is already playing, the test uses it instead of starting its own. Leaving the screen stops a test it started. A short hint explains it's for Bluetooth headphones and doesn't change the sound.
- No reset for the other settings.

## App icon

The tempo needle: the main screen's ruler ticks with the red needle through the middle, on black. Sources (vector, 1024×1024):
- `app-icon.svg`: the full icon, square with no rounded corners (the OS applies its own mask). Use for iOS and as the Android legacy icon.
- `app-icon-foreground.svg`: transparent foreground for Android adaptive icons, with the artwork scaled into the safe center area so any mask shape keeps it intact. The adaptive background is solid #000000.

Generate all platform sizes from these (e.g. with `flutter_launcher_icons`, after exporting the SVGs to 1024px PNGs). Check the result at small sizes on the real phone.

## Data model

- **Shared song library.** Each song exists once (name, tempo, time signature, subdivision, beat pattern). Setlists reference songs by id, in order, and the same song can appear in several sets. Editing a song changes it everywhere.
- Per song: tempo, time signature, subdivision (1–4), beat states (accent/regular/muted per beat), polyrhythm (0 = off, 2–7) and its pulse states. Older songs without these fields load as polyrhythm off.

## Behavior

- **Modes:** Free play (no song), Single song (a library song loaded without a setlist), or a setlist. The app always starts in Free play when it is launched fresh (first launch, or after it was closed or killed), stopped, with the tempo, time signature, subdivision, and beat states it last had. No song or setlist is loaded; getting back to one is a tap away in the dropdowns. Returning to the app while it's still running (from the background, the notification, or recents) keeps everything exactly as it was.
- Start always begins on beat 1.
- Subdivision clicks are quieter than beat clicks; accents are loudest. Changing the subdivision while playing takes effect at the next beat, without restarting the bar.
- Next/previous or choosing a song while stopped: load it (tempo, time signature, subdivision, pattern) without starting.
- Next/previous or choosing a song while playing: load it and restart immediately on beat 1 at the new tempo, using the same clear-and-reschedule mechanism as tempo changes.
- Keep the screen awake while playing.
- **Free play never holds a song.** Loading a song from the library outside a setlist enters Single song mode; Free play always means no song is attached.
- **Detaching a song** (tapping the Free play tab): the song is unloaded, but the click keeps exactly what it sounds like now: tempo, time signature, subdivision, and beat states, including any unsaved changes. While playing, the click carries on unchanged, with no restart. The title clears, Revert / Save to song disappear, and the tempo-name line returns. The song itself is untouched in the library; unsaved changes aren't saved to it. The app is then in Free play. Switching from a setlist to Free play works the same way.
- **Changes to a loaded song** (tempo, time signature, subdivision, beat states changed on the main screen while a song is loaded) are temporary: they play immediately but don't change the stored song. As soon as anything differs from the stored song, the tempo-name line under the BPM shows "Revert" and "Save to song". Save writes the current values to the song (in the shared library, so every set gets them); Revert restores the stored values. Loading another song or switching sets discards unsaved changes without asking. Detaching a song keeps them as Free play settings (see above). Closing the app detaches the song like Free play does: on the next fresh launch the click keeps those settings in Free play, and the song itself is unchanged (unsaved changes aren't written to it). In Free play with no song loaded there's nothing to save, so the line always shows the tempo name.
- **Save as new song** ("Save as new" under the BPM when a song has unsaved changes, or "+ New song from this" in the context row in Free play) opens a dialog (see `save-as-new.reference.html`):
  - Title "Save as new song" (from Free play: "New song"), a Name field focused with a default already filled in and fully selected (the loaded song's name plus the next free number, "Dead Weight 2"; in Free play "Song 10", the next free number), highlighted with the accent color. Cancel / Save.
  - Only in setlist mode, a choice "In Friday set": **Replace Dead Weight** (default; the new song takes its place in the set, same position), **Add after Dead Weight** (both stay), **Don't add** (the app leaves the set and plays it in Single song mode).
  - Save creates the song in the library from the current tempo, time signature, subdivision, and beat states, and makes it the loaded song. The click carries on unchanged, no restart. The original song is untouched (in the library and in other sets). Nothing is unsaved anymore, so the tempo-name line returns.
  - From Free play or Single song there's no set question; the app is then in Single song mode with the new song.

## Haptics

Haptics confirm a touch, so you can trust a press on stage without looking. Use the platform's standard haptic types. Haptics play only when both the phone's system vibration setting and the app's "Vibrate on touch" setting (Settings, default on) allow it.

- **Medium** (important stage actions): Start/Stop; next/previous and choosing a song in the picker (the song changed); any "Free play" button (the song detached); choosing a set in the sets view; long-press lifting a row to reorder.
- **Light tick** (small adjustments and selections): every −5/−1/+1/+5 step, whether tapped or produced by holding (a held button feels like a ratchet; a medium bump when a hold hits 30 or 300); the beats −/+ steps; each Tap tempo tap; the ruler crossing a multiple of 5 (only fives, since a drag passes values too fast to tick each one); tapping a beat block, the subdivision button, a time signature, or a cell in the song editor; Save to song, Save as new, and Revert; marking or unmarking a row (removing songs, deleting sets); a swipe crossing its commit point in a list, either way (none on release, so a swipe never buzzes twice).
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
- **Back (predictive back, Android 16 target):** Back always closes one level at a time, and the system's back preview shows that level, never the home screen while something is open. Order, innermost first: rename field (cancels the rename) → delete dialog (Cancel) → song picker or sets view (back to the set's songs) → the panel itself (closes) → time signature sheet / ☰ side panel (closes) → a page (back to where it was opened from). Only on the bare main screen does Back leave the app. Back never stops the click.

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
- Every control has a spoken name and state. Icon-only buttons: "Subdivision: eighth notes", "Time signature 4/4, polyrhythm 3", "Menu", "Start" / "Stop", "Tap tempo".
- Beat blocks: "Beat 1, accented" (regular / muted), with the hint "Double-tap to change". Polyrhythm cells the same ("Pulse 2 of 3, regular").
- BPM and ruler: one adjustable control, "Tempo, 120 BPM, Allegro"; swipe up/down changes by 1. The −5/−1/+1/+5 buttons announce the new tempo.
- Context row: "Previous song: Iron Lung, 98 BPM", "Friday set, song 4 of 12, opens song list", "Next song: …". Tabs announce as tabs with "selected".
- Lists: each row reads name, tempo, time signature, and "playing" for the current one; the swipe, reorder and rename gestures are also offered as actions ("Remove from set", "Delete song", "Delete set", "Move up", "Move down", "Rename").
- Nothing is announced on each click while playing (that would talk over the music); only Start/Stop and song changes are announced.

**4. Touch targets**
- Every tappable thing has at least a 48×48dp touch area (Android's minimum), even when it looks smaller: the 44px top-row buttons, "‹ Back", "Undo", ×, and the long-press title get invisible padding. Visuals don't change.

**5. Reduced motion**
- With Android's "Remove animations" on, list and sheet animations become instant and the one-time swipe hint is skipped (its flag is still set). The beat lights are not animations and stay as they are.

## Trainer (designed, not built yet)

Do not build this yet; it's here so the layout leaves room for it. One sheet, opened from a ramp icon button in the main screen's top row, with two independent parts, both off by default:
- **Tempo steps:** change by (+1 to +20, or negative to slow down) every (1–64) bars, with an optional "until" tempo. Starts from the tempo shown when you press Start. Each change lands exactly on a bar line. At the "until" tempo it holds and keeps playing. Changing the tempo by hand while it runs makes that the new current tempo; the steps continue from it.
- **Stop after:** N bars, or a time (mm:ss). The click stops at the next bar line after the limit, never mid-bar.
- **Combined:** both run together ("+5 every 8 bars until 160, stop after 10:00" climbs to 160, holds, stops at 10 minutes).
- **Reset:** Stop, or reaching the limit, resets: the tempo returns to the starting tempo, so the next Start replays the same exercise. Start always runs it from the beginning.
- **On screen:** the BPM and ruler follow the live tempo. The trainer icon is red while active. While playing, the line under the BPM shows progress ("↗ +5 every 8 bars · next in 3 · 4:12 left"); stopped, it shows the summary. Revert / Save to song take that line while stopped if the song has unsaved changes; progress takes it while playing.
- **In songs:** a song can save its trainer settings like its tempo; loading the song loads them; changing them is an unsaved change (Revert / Save). Free play can use a trainer without saving.
- **In a setlist:** when "Stop after" ends, the click stops and stays on the same song (it never advances by itself).
- **Open before building:** the top row is full (title + three buttons); adding a fourth button squeezes long titles. **Proposed direction (not sealed):** move subdivision into the time signature sheet (the "4/4" button opens one sheet for time signature and subdivision, and its label could show both, e.g. "4/4 ♪♪"), freeing a top-row slot for the trainer button. See the A3 board on the canvas.

## Parked ideas

- **Organizing a big library (folders):** parked. Setlists already group songs (a set can simply be "all of band X"), and search covers finding one song. If testers' libraries get unwieldy, the preferred next step is a filter row in the Songs list and library (All · each setlist as a chip) rather than a separate folder concept, so there's still only one way to group songs.

- **App shortcuts:** long-press the app icon for "Free play" or "Last setlist".
- **Crash reporting:** skipped for now (needs a third-party account and conflicts with "no tracking"); feedback comes through Send feedback.

- **Landscape layout:** for a phone clamped sideways on a drum stand. Parked; portrait-only for now.

Not planned; recorded so they aren't lost.
- **Gap trainer:** play N bars, then mute N bars, to practice keeping time without the click.
- **Song maps (sections):** a song made of sequential sections, each with its own bar count, tempo, time signature, subdivision, and pattern (e.g. intro: 8 bars at 140 in 4/4, then verse: 16 bars at 160 in 7/8), played automatically in order.
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
