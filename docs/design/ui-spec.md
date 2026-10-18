# Metra UI Spec

Design references (design-tool files: read them for exact sizes and colors, don't port their markup):
- `main-screen.reference.html`: main screen with a setlist loaded.
- `free-play.reference.html`: main screen in Free play.
- `free-play-song.reference.html`: Single song mode (a library song loaded without a setlist; same bar as Free play, the title shows the song, no subtitle).
- `beat-states.reference.html`: the beat blocks at three moments in a bar.
- `setlist-picker.reference.html`: a set's page (its songs; also where the set is edited).
- `set-switcher.reference.html`: the picker's "What to play" view (Free play and switching sets).
- `set-switcher-select.reference.html`: What to play after "Delete setlists" (sets being marked).
- `song-editor-collapsed.reference.html`: the song editor as it opens (pattern collapsed).
- `song-editor.reference.html`: the song editor with the pattern section expanded, full scroll length.
- `setlist-drag.reference.html`: a set's page while dragging a song (lifted row and drop slot).
- `setlist-select.reference.html`: a set's page after "Remove songs" (songs being marked).
- `setlist-new.reference.html`: a set's page for a new, empty set.
- `song-library.reference.html`: the song library (browse).
- `library-select.reference.html`: the song library after "Delete songs" (songs being marked).
- `library-pick.reference.html`: the library in pick mode, adding songs to a set.
- `unsaved-song.reference.html`: main screen with unsaved changes to the loaded song.
- `save-as-new.reference.html`: the Save as new song dialog (in a setlist).
- `media-controls.reference.html`: lock-screen media card and compact notification (setlist, playing).
- `media-cover.reference.html`: media card in Free play (stopped) and the generated cover image.
- `time-signature.reference.html`: the time signature sheet.
- `menu.reference.html`: the Menu side panel open over the main screen.
- `settings.reference.html`: the Settings page at full scroll length.
- `drop-songs.reference.html`, `drop-sets.reference.html`, `drop-set.reference.html`: the quick-pick dropdowns on the main screen.

## Principles

Every feature, now and later, is checked against these before it's designed. If a feature breaks one, the feature changes, not the principle.

1. **Stage first.** Designed for a drummer on a stool, mid-song, with sweaty hands and a glance. Anything used while playing must work in one tap without reading.
2. **Nothing interrupts the click.** Opening a sheet, page, list, or editor never stops or changes playback. Only an explicit action (start/stop, tempo change, choosing a song) affects it; changes land on beat or bar lines, never mid-beat.
3. **Only what sounds lights up.** Visual feedback follows the audio exactly.
4. **Nothing moves.** Free play, Single song, and setlist mode share one layout; only content changes. Start/Tap, tempo controls, and the mode tabs never change position. Fixed slots for changing text and numbers (no jitter, no reflow).
5. **One screen to play, the Menu to manage.** Choosing and playing happens on the main screen (tabs switch at once; lists open from the context row's center button; quick choices like time signature are a sheet). Creating, editing, and organizing are full pages reached from the Menu (☰, a side panel of places to go).
6. **One way to do each thing, in one place.** No duplicate routes on the main screen; one concept per job (setlists group songs, no second grouping system).
7. **Nothing hidden that matters.** Every action has a visible control. Gestures (long-press, drag) are only shortcuts or direct manipulation, never the only way.
8. **Tap does, long-press edits.** A tap plays or switches; a long-press on a song or set opens its editor or page. Never on stage-critical buttons.
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

Across the app, long-press on a song or a set means "edit it" (song → song editor, set → its page), as a shortcut; the visible route is always the Menu or a pencil. Exception: on a set's page, long-press and drag reorders. Never on stage-critical buttons (Start/Stop, tempo, previous/next).

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

1. **Top row.** Current song title on the left (Saira Extra Condensed 700, one line). **Shrink to fit:** it starts at 34px and, if the name doesn't fit, shrinks step by step down to 22px; only if it still doesn't fit at 22px does it end with "…". That keeps around five words readable without ever wrapping. **Fixed lines:** the title has a fixed-height line box (sized for 34px) and the subtitle line is anchored to the bottom of the 54px block, so the subtitle never moves when the title shrinks; a smaller title sits at the bottom of its line box, right above the subtitle (aligned on the baseline). It shows the loaded song's name in setlist and Single song mode, and is empty in Free play. Under it, a small muted subtitle (Saira 14px, #8C8C8C, one line, ellipsis), like a song's artist line: the setlist's name in setlist mode; empty in Single song mode (it blends in; the subtitle line still reserves its height so the title sits in the same place). In Free play the title block is empty (saving lives in the context row: "+ New song from this"). The title block is a fixed 54px tall in every mode, so nothing shifts. The title has no buttons next to it. Long-press the title (medium haptic) to open the song editor for that song; long-press the setlist subtitle to open that set's page. Taps do nothing. These are small targets on purpose: shortcuts, not the main route. On the right, three outlined 44×44 buttons, 4px radius: subdivision, time signature ("4/4"; with a polyrhythm on it reads "4/4 · 3" and widens to fit), Menu (☰).
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
4. **BPM.** Large number (~172px, tabular figures). The number itself is centered on the screen; "bpm" (small, muted) hangs off its right side, near the baseline, and is not counted when centering. Below it, a fixed 44px-tall line that normally shows the Italian tempo name for the current BPM, muted, from the mechanical metronome scale: Largo (under 60), Larghetto (60–65), Adagio (66–75), Andante (76–107), Moderato (108–119), Allegro (120–167), Presto (168–199), Prestissimo (200+). When the loaded song has unsaved changes, this line shows three plain text buttons instead: "Revert · Save · Save as new", all the same grey (#8C8C8C, Saira 15px, 500), no borders or fills, separated by dim dots (#3A3A3A), each with a 44px tap area. "Save" saves to the song. They are optional, so none is highlighted and nothing looks required; see "Changes to a loaded song" under Behavior and `unsaved-song.reference.html`. Same size in both modes.
5. **Tempo ruler,** ~46px tall. Minor ticks every 1 bpm, labeled major ticks every 5, fixed red needle at the center, current value's label highlighted. Horizontal drag changes BPM. Clamp 30–300. Faster drags cover more bpm per pixel, up to 4× at full speed, so big jumps don't need long swipes.
   - **Snapping depends on release speed.** A slow drag moves in 1-bpm steps and stays exactly where it's released (so 123 is reachable). A fast swipe (fling) coasts with momentum and always comes to rest on a multiple of 5, regardless of the starting value (e.g. from 123 it settles on 130, 135...). Decide by finger velocity at release; start with roughly 300 px/s as the threshold and tune it on a real phone.
   - A light haptic tick each time the needle crosses a multiple of 5, during both drag and coast (see Haptics).
6. Flexible space.
7. **Tempo buttons:** −5, −1, +1, +5 in one row, 60px tall, filled. ±5 matches the ruler's labeled ticks; bigger jumps come from the ruler or from loading a song.
   - **Hold to repeat:** a tap changes the tempo once. Holding waits ~0.4 s (so a normal tap never repeats), then repeats at ~6 steps per second, accelerating to ~15 per second after 1.5 s of holding. Each repeat uses that button's own step (holding +5 climbs by fives). Releasing stops immediately. Reaching 30 or 300 stops the repeat with one medium haptic bump. While playing, every step applies, so the tempo audibly glides.
   - The same hold-to-repeat applies to the song editor's −5/−1/+1/+5, and to the beats −/+ in the song editor and time signature sheet (beats repeat at the slower ~6 per second without accelerating).
8. **Start/Stop** (2/3 width, 72px, primary color, icon + label) and **Tap** (1/3 width, outlined).
   - **Tap tempo:** a tap counts at the moment the finger touches the button (not on release). The tempo is the average of the last 4 taps; a tap that's far off from the others is ignored. Tapping resets after 2 seconds without a tap.
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
     - **Setlist mode:** Previous | narrow center (fixed 76px: setlist icon over "4/12 ⌄"; opens the set dropdown; long-press opens the set page) | Next. Previous/Next: the name on line 1 (18px semibold, using the full width, shrinking to fit), and on line 2 "‹ 98 BPM" / "168 BPM ›" (option 4: grey bold).
     - **Single song:** Previous | center | Next, the same shape as in a set. Previous/Next step through the song library in A–Z order. The center button (fixed 76px, outlined: the note icon over "Songs ⌄") opens the Songs list.
     - **The center button is always "the list":** in a set it opens the set's songs (with "Other setlists ›" to switch sets); in Single song it opens all songs. This is the one place lists open from.
     - **Free play:** a quiet centered text button "+ New song from this" (muted #8C8C8C, 15px, no border, 44px tap area) that opens the Save as new dialog titled "New song". This replaces the old "+ New song" in the title spot; the title block is empty in Free play.
   - **Vertical layout: two groups.** The *display* is the BPM number alone, centered in the free space between the beat blocks and the ruler, with equal space above and below it. The tempo-name line (Andante, or Revert / Save) hangs directly under the number and is not counted when centering, the same way "bpm" hangs off its right side; the free space must leave room for it. The *controls* (ruler, −5 −1 +1 +5, Start/Tap, source bar) stay together at the bottom, in thumb reach, with fixed spacing (6px + the normal gap between the ruler and the buttons). Spare height never opens gaps inside the controls.
   - **BPM size grows with the screen, never with the value:** the font size is computed once from the available area (about 172px minimum, up to ~240px), sized so that three digits fit. It never changes when the tempo goes from 100 to 99 or back: a two-digit tempo is simply narrower, centered, and nothing else on the screen moves.
   - **No jitter:** every digit of the BPM sits in a fixed-width slot (the width of the widest digit, about 0.52em in Saira Extra Condensed), centered in its slot. Same for the ruler labels and other changing numbers (tempo in the editor, set position). So 111 and 188 are exactly the same width and the number doesn't shake while it changes fast. Use the font's tabular figures if it has them; otherwise lay the digits out in slots. The font stays.
   - Saving is always one tap: "+ New song from this" in the context row in Free play; "Revert · Save as new · Save to song" under the BPM when a loaded song has unsaved changes. "Free play" is the middle mode tab.

## Quick-pick dropdowns (main screen)

Choosing what to play never leaves the main screen. The context row's center button ("4/12 ⌄" in a set, "Songs ⌄" in Single song) opens a dropdown panel just above the context row (it opens upward), over the dimmed main screen; the context row and tabs stays visible above the dim. Panel: #111111, 1px #2E2E2E border, 8px radius, full content width, up to ~470px tall, scrolls inside. Tap outside or the back gesture closes it. Playback continues. Opening one gives no haptic; choosing a row gives the same medium haptic as choosing a song. See `drop-songs.reference.html`, `drop-sets.reference.html`, `drop-set.reference.html`.
- **Songs list** (the "Songs ⌄" center button in Single song): a "Search songs" field at the top (only when there are more than about 8 songs), then one 52px row per song, A–Z: play icon (red and selected background for the loaded song), name, tempo, time signature. Tap = load it in Single song mode (same rules as the song library) and close. Bottom row: "Song library ›", which opens the library page.
- **Setlists list** (reached from "Other setlists ›" in a set's list, and when switching sets): one 52px row per set, recently played first: list icon, name, "12 songs". Tap = load it at song 1 and close. Last row: "Manage setlists ›", which opens the Setlists page.
- **Set ⌄** (setlist mode, the center "4/12" button): a small muted header line (set name, position), then the set's songs in order, the current one with the red play icon and selected background, scrolled into view. Tap = jump to that song (same rules as next/previous) and close. Bottom row: "Other setlists ›" (swaps the panel's content to the Setlists list, in place).
- **No "Free play" rows in the dropdowns:** Free play is the middle mode tab, always visible.
- **Panel structure:** the search field (when shown) is pinned at the top and the action rows ("Song library ›", "Manage setlists ›", "Other setlists ›") are pinned at the bottom; only the list between them scrolls. The pinned action group is separated from the list by a 2px #2E2E2E line, and its rows by 1px #1F1F1F lines, so actions never read as list items.
- **Long-press a row = edit it** (a shortcut; the Menu is still the main way in): a song opens the song editor, a set opens that set's page. In the set header dropdown, long-pressing the set itself (the header line "Friday set · 4 of 12" at the top of the panel, or the center "4/12" button on the main screen) opens that set's page. Medium haptic. The click keeps playing; back returns to the main screen. Tap stays "play this".
- Empty: with no songs, the Songs panel shows only "No songs yet" and "New song ›"; with no setlists, the Setlists panel shows "No setlists yet" and "New setlist ›" (each opens the matching page).

## Setlists (What to play and set pages)

Two full pages (not sheets), black background like the song library. Playback continues the whole time.
- **Navigation:** reached from Menu → Setlists, or "Manage setlists ›" in the Setlists dropdown. What to play is the parent; a set's page is below it (pencil on a set). "‹ Setlists", the back gesture, and the system back always agree: set page → What to play → where you came from (Menu or main screen).
- **Loading always lands on the main screen:** any action that loads something (tapping a set, a song row, or a "Free play" button) applies it and returns straight to the main screen, closing these pages (and the Menu, if you came from there).

**Set page** (the songs view; opens from a set's pencil in What to play; see `setlist-picker.reference.html`). One page both plays and edits the set; there is no separate setlist editor and no edit mode.
- Top bar: "‹ Setlists" on the left, a plain back link (left chevron and the word, 44px tall) that opens the "What to play" view, the parent level. On the right, a small outlined "Free play" button (the same fixed 128×40): it switches to Free play and returns to the main screen (see "Detaching a song" under Behavior). Two taps from the main screen to Free play.
- Below it: the set name as a plain title (22px, no chevron). Below that, "12 songs" in muted text.
- Chevrons have one meaning each: ⌄ opens a dropdown on the main screen; ‹ goes back a level; › opens a page.
- One 60px row per song: a play icon (outlined, muted) at the left, name, tempo (Saira Extra Condensed), time signature (muted), and a pencil button (52×60, muted icon) at the right edge. No position numbers: the order is visible from the list, and the position shows on the main screen. Play on the left and edit on the right make both actions visible.
- The current song's row has the selected-row background and its play icon is filled red (only on the loaded set's page).
- **Gestures on a row:**
  - **Tap the row** = load that song (and this set, if it isn't the loaded one), following the same rules as next/previous: while stopped, load only; while playing, restart on beat 1 at the new tempo. Then it returns to the main screen.
  - **Tap the pencil** = edit that song in the song editor.
  - **Long-press and drag** = reorder. The row lifts with a medium vibration. Saved immediately; playback is unaffected. Long-press does nothing else.
    - **While dragging, the row must clearly look picked up** for the whole drag (not just a flash): background #2A2A2A, a 2px white outline, 6px radius, a deep shadow, scaled to ~103%, following the finger. Where it will land, a dashed #4A4A4A outline slot of the same height opens and the other rows slide out of the way (animated, ~150 ms). On release it settles into the slot with a light haptic. See `setlist-drag.reference.html`.
  - Nothing is hidden: there is no swipe action on rows.
- **Removing songs:** the "Remove songs" button at the bottom switches the list into marking. Every row's left slot shows an empty circle; tapping a row checks it (filled red circle with a check, selected-row background) instead of loading it; pencils are hidden. The bottom bar becomes "N selected" (muted), "Cancel" (outlined), and "Remove" (red text). Cancel or the back gesture ends it. See `setlist-select.reference.html`.
- **Removing** takes songs out of this set only; they stay in the library and in other sets. No confirmation: a short "Removed" bar with Undo (about 5 s).
- The same song may appear more than once in a set; removing one row removes only that occurrence.
- **Bottom:** "Add songs" (opens the library in pick mode) and "Remove songs" (outlined), side by side. Everything on this page is about this set; the song library is reached from the Menu or the Songs dropdown.
- **End of the list** (after the last row, so it's never in the way on stage): "Rename setlist" and "Delete setlist" (red) as quiet text buttons. Rename turns the title into a text field with the name selected; Done on the keyboard saves. Delete asks for confirmation, never deletes the songs themselves, and returns to What to play.
- **New setlist** ("New setlist" in What to play) opens this page for a new set: the title is a text field, focused, with a unique default name already filled in and fully selected ("Setlist 5", using the next free number), highlighted with the accent color. Typing replaces it; leaving it untouched keeps it. The list shows an empty state: "No songs yet", a short hint, and a big filled red "Add songs" button right under it (where the eye lands when the keyboard closes). The bottom bar is hidden while the set is empty and appears with the first song (see "Empty lists" under Behavior). If the library itself is empty, the center button reads "New song" instead (creates a song and adds it to this set). A new set left with no songs is discarded when you leave the page. See `setlist-new.reference.html`.

**What to play view** (see `set-switcher.reference.html`):
- Top bar like the song library: ‹ (back to the main screen) and the centered title "What to play". It never leads to a set's page, so there's no loop with the set page's "‹ Setlists".
- **Free play** first, as its own framed button with a metronome icon and the line "No setlist, any tempo". It's a mode, not a setlist, so it's visually separate from the list. Tapping it always switches to Free play and detaches any loaded song (see "Detaching a song").
- Then a muted "Setlists" label (with "Recently played" muted on the right), a search field ("Search setlists", same style as the song library's; filters by name as you type), and one 64px row per set, built like the picker's song rows:
  - Left: a 22px slot with a muted list icon (the set's counterpart of a song row's play icon). Then the name and a muted "12 songs" line.
  - Right: a pencil button (52×64, muted icon) that opens that set's page (its songs, where it is also edited and renamed) without loading it.
  - No row is marked as the loaded set: the main screen already shows it, recently played puts it on top, and tapping any row does the same thing. Every row shows a pressed state on touch.
  - **Order: recently played first** (the set you load most recently goes to the top). Sets have no manual order, so there is no dragging here.
  - **Deleting sets** works like removing songs on a set's page: the "Delete setlists" button at the bottom switches the list into marking (empty circles in the left slot; tapping a row checks it; pencils hidden), and the bottom bar becomes "N selected" (muted), "Cancel" (outlined), and "Delete" (red text). Long-press a set opens its page (same as the pencil; see Long-press rule); swipe does nothing. See `set-switcher-select.reference.html`.
    - Delete asks for confirmation ("Delete Friday set? The songs stay in your library." / "Delete 2 setlists? …"). Deleting the loaded set switches to Free play, keeping the click as it sounds (see "Detaching a song").
- Tapping a set loads it at its first song (playback rules as above) and returns to the main screen. This is the same for every row, including the set that is already loaded. (While sets are marked, a tap marks instead.)
- At the bottom: "New setlist" and "Delete setlists" (outlined), side by side.

## Song editor

A full screen (not a sheet), used for setup rather than on stage. See `song-editor.reference.html` (shown at full scroll length).

- **Opening it:** long-press the song title on the main screen to edit the current song (a tap on the title does nothing, so a stray touch on stage never leaves the main screen); tap the pencil on a song row on a set's page; or tap the pencil on a song in the song library. New songs come from the song library ("New song").
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

## Song library

A full screen listing every song. See `song-library.reference.html`, `library-select.reference.html`, and `library-pick.reference.html`.

- **Browse mode** (from Menu → Song library, or "Song library ›" in the Songs dropdown):
  - Top bar: back chevron and "Song library" (centered).
  - Search field, then the song count with a small sort control on the right: A–Z (default) or Recently edited.
  - One 64px row per song: an outlined muted play icon at the left (filled red for the loaded song), name, a muted line saying which setlists use it ("Friday set, Rehearsal", "3 setlists", or "Not in a setlist"), tempo, time signature, and a pencil button (52×64, muted icon) at the right edge, the same as picker rows.
  - **Tap the row** = load that song and return to the main screen, following the picker's rules: while stopped it only loads; while playing it restarts on beat 1 at the new tempo. It always enters Single song mode, from any mode: the title shows the song's name and the box header reads "Single song". If a setlist was loaded, it is unloaded; to get back to it, choose it again in the picker.
  - **Tap the pencil** = open the song editor for that song.
  - **Bottom:** "New song" and "Delete songs" (outlined), side by side, the same shape as What to play ("New setlist · Delete setlists") and a set's page ("Add songs · Remove songs").
  - **Deleting songs:** "Delete songs" switches the list into marking (empty circles in the left slot; tapping a row checks it, filled red circle and selected-row background; pencils hidden), and the bottom bar becomes "N selected" (muted), "Cancel" (outlined), and "Delete" (red text). See `library-select.reference.html`. Long-press a song opens the song editor (same as the pencil; see Long-press rule).
    - Delete asks for confirmation and names the sets it affects, because a song is shared: "Delete Dead Weight? It will also be removed from Friday set and Rehearsal." (several: "Delete 2 songs? They will also be removed from 3 setlists."; none: "Delete Untitled riff?").
    - Deleting the loaded song switches to Free play, keeping the click as it sounds (see "Detaching a song").
  - **Empty library:** the center shows "No songs yet", a short hint, and a big filled red "New song"; the bottom bar is hidden until there's a song.
  - This is the way to play a single song without a setlist (the quick way is the Songs dropdown on the main screen; this page is for managing).
- **Pick mode** (from "Add songs" on a set's page):
  - Top bar: Cancel and "Add to <set name>".
  - Search field, then the list. Its first row is "Select all" with its own checkbox and the count on the right ("9 songs"); it checks or unchecks every song currently shown (respecting the search). Then one checkbox row per song. Songs already in the set show "Already in this set" in red, semi-bold (#FF3B30, the app's warning red) but can still be added again.
  - Empty library: the same empty state as browse, with a centered red "New song" (creates a song and adds it to the set).
  - Bottom: "New song" (outlined; creates a song and adds it to the set) and "Add N songs" (filled, primary color; disabled until something is checked).

## Time signature sheet

A bottom sheet opened from the "4/4" button on the main screen. See `time-signature.reference.html`.

- Title "Time signature".
- **Common:** eight one-tap buttons in a 4×2 grid: 2/4, 3/4, 4/4, 5/4, 6/8, 7/8, 9/8, 12/8. The current one is filled white with black text. Tapping one applies it and closes the sheet.
- **Custom:** beats with − / + (1–16), "/", and a 4 | 8 segmented control, same as the song editor. Applies as you change it; the sheet stays open.
- Changing the number of beats keeps existing beat states where possible (new beats are regular; beat 1 keeps its state).
- While playing, a new time signature takes effect on the next beat, which starts a new bar (beat 1). It doesn't wait for the current bar to finish.
- **Polyrhythm** (last row of the sheet): a segmented control "Off · 2 · 3 · 4 · 5 · 6 · 7". The number equal to the current beat count is dimmed and can't be chosen (4 against 4 is just the beat). Under it, one muted line in plain words, e.g. "3 against 4: three even clicks per bar, in their own sound"; with Off it reads "Add a second pulse across each bar". Applies as you change it; the sheet stays open. See "Polyrhythm".
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

The ☰ button at the top right of the main screen opens a **side panel** that slides in from the right (304px wide, #111111, 1px #2E2E2E left border) over the dimmed main screen. It's a list of places to go, which is what ☰ promises; settings have their own page. The click keeps playing. Tap outside, swipe it right, or use back to close it. Opening it gives no haptic. See `menu.reference.html`.

- **Title** "Menu" at the top.
- **Your music** (small muted heading): "Song library" (note icon, muted count, ›) and "Setlists" (note-queue icon, count, ›). This is where songs and setlists are created and edited; the main screen's lists are for choosing what to play.
- After a gap: **"Settings"** (gear icon, muted line "Sound, volume, theme", ›), **"Send feedback"** (muted line "Tell Dror what works and what doesn't"), **"About Metra"** (muted line "Why this app exists"). Rows without an icon keep the icon column empty so the labels line up.
- At the bottom of the panel, centered and muted: "Metra 1.0.0 (2)" (version and build). Long-pressing it copies it.
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
- **Detaching a song** (tapping the Free play tab, the set page's top bar, or the What to play view): the song is unloaded, but the click keeps exactly what it sounds like now: tempo, time signature, subdivision, and beat states, including any unsaved changes. While playing, the click carries on unchanged, with no restart. The title clears, Revert / Save to song disappear, and the tempo-name line returns. The song itself is untouched in the library; unsaved changes aren't saved to it. The app is then in Free play. Switching from a setlist to Free play works the same way.
- **Changes to a loaded song** (tempo, time signature, subdivision, beat states changed on the main screen while a song is loaded) are temporary: they play immediately but don't change the stored song. As soon as anything differs from the stored song, the tempo-name line under the BPM shows "Revert" and "Save to song". Save writes the current values to the song (in the shared library, so every set gets them); Revert restores the stored values. Loading another song or switching sets discards unsaved changes without asking. Detaching a song keeps them as Free play settings (see above). Closing the app detaches the song like Free play does: on the next fresh launch the click keeps those settings in Free play, and the song itself is unchanged (unsaved changes aren't written to it). In Free play with no song loaded there's nothing to save, so the line always shows the tempo name.
- **Empty lists** (a new set, an empty library, no setlists): the main action moves to the center of the empty list as a big filled red button ("Add songs", "New song", "New setlist"), and the bottom bar is hidden until the list has something in it. Once it appears, the bottom bar never moves.
- **Save as new song** ("Save as new" under the BPM when a song has unsaved changes, or "+ New song from this" in the context row in Free play) opens a dialog (see `save-as-new.reference.html`):
  - Title "Save as new song" (from Free play: "New song"), a Name field focused with a default already filled in and fully selected (the loaded song's name plus the next free number, "Dead Weight 2"; in Free play "Song 10", the next free number), highlighted with the accent color. Cancel / Save.
  - Only in setlist mode, a choice "In Friday set": **Replace Dead Weight** (default; the new song takes its place in the set, same position), **Add after Dead Weight** (both stay), **Don't add** (the app leaves the set and plays it in Single song mode).
  - Save creates the song in the library from the current tempo, time signature, subdivision, and beat states, and makes it the loaded song. The click carries on unchanged, no restart. The original song is untouched (in the library and in other sets). Nothing is unsaved anymore, so the tempo-name line returns.
  - From Free play or Single song there's no set question; the app is then in Single song mode with the new song.

## Haptics

Haptics confirm a touch, so you can trust a press on stage without looking. Use the platform's standard haptic types. Haptics play only when both the phone's system vibration setting and the app's "Vibrate on touch" setting (Settings, default on) allow it.

- **Medium** (important stage actions): Start/Stop; next/previous and choosing a song in the picker (the song changed); any "Free play" button (the song detached); choosing a set in What to play; long-press lifting a row to reorder.
- **Light tick** (small adjustments and selections): every −5/−1/+1/+5 step, whether tapped or produced by holding (a held button feels like a ratchet; a medium bump when a hold hits 30 or 300); the beats −/+ steps; each Tap tempo tap; the ruler crossing a multiple of 5 (only fives, since a drag passes values too fast to tick each one); tapping a beat block, the subdivision button, a time signature, or a cell in the song editor; Save to song, Save as new, and Revert; marking or unmarking a row (removing songs, deleting sets).
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
- **Volume keys** control Metra's volume in the app, outside it, and on the lock screen (already working).
- **Launch screen and system bars:** the launch screen is black (#000000; #F3F1EC in Daylight) with the app icon, so there's never a white flash. Status and navigation bars match the theme (dark bars and light icons in Stage Black, the reverse in Daylight). The app draws edge to edge and keeps all content clear of the status bar, notch, and gesture bar.
- **Backup:** Android's automatic backup is on for the library (songs, setlists, settings), so a reinstall or a new phone restores it from the user's Google backup. No permission or sign-in in the app.
- **Language and direction:** English only. The layout never mirrors, even on a Hebrew or Arabic phone (always left to right).
- **Quick Settings tile:** a "Metra" tile users can add to the pull-down panel. It shows Playing / Stopped and tapping it starts or stops the click with the current song and tempo. No permission needed. If Android doesn't allow starting audio from the tile without the app, the tile opens the app and starts.
- **Accessibility, light pass:** every button has a screen-reader label; with large system font sizes, text grows but the main screen layout stays intact (the BPM and button labels may cap their growth so nothing overlaps).

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
  - Segues are configurable per transition, not per set: on a set's page, a small link toggle between two rows ("Continue into next song") makes that one song flow straight into the next. Off by default.
  - No set-level "Play" button: Start always plays the current song, and linked pairs carry on by themselves.
- **Favorite setlists:** a star to pin sets above the recently-played order. Parked because recently played already keeps the active sets on top; revisit if people keep many sets.
- **Add songs to a set from the library:** the library's marking mode (today "Delete songs") could also offer "Add to setlist…" (choose an existing set) and "New setlist with these". Parked because the set-first path (a set's page → Add songs) already covers it; build it if songs-first turns out to be a common need.
