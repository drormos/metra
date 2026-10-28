# Queued prompt: Export / Import of full sets and songs

Status: designed and specced (Oct 29, 2026), not built yet. Send to Claude Code when ready.
Spec: ui-spec.md › "Sharing sets and songs", › Set ⌄ › Stage mode (bottom row), › Songs list › Bottom.
Board: "Detail · Sharing full sets and songs" (its Songs list column still shows Share in a header; the spec wins: Share is in the bottom row).

---

```
Sharing full sets and songs, per ui-spec.md › "Sharing sets and songs", › Set ⌄ (Share is in the bottom row), and › Songs list › Bottom; canvas board "Detail · Sharing full sets and songs". Use the data-format-change skill for the export format.

1. Share menus (same dropdown style as "At the end", name + muted line per item):
   - Set panel's Share button (bottom row): "Send song list" (the running-order text already built), "Export set", "Import a set".
   - Songs list: Share joins "+ New song" in the pinned bottom row (two equal buttons, icon above label, labels wrap and never cut, same style as the set panel's row). Menu: "Export a song…" → pick mode (top bar "Tap the song to export" + Cancel; tapping a row exports it and leaves pick mode; Cancel/Back/close also leave), and "Import a song".
   - Parts page: "Share this song" outlined button under "At the end" (exports it; not in unsaved Free play).
   - Sets view: "Paste shared" next to "+ New setlist".
2. Export message: readable part, then "To import this into Metra: share this message to Metra, or copy it and tap Import in Metra.", then one "metra1:" data line (versioned, compressed, URL-safe). Song data = name + music only: parts (name, length, tempos incl. Gradual, time signature, subdivision, accents, polyrhythm) and "At the end". When I press Start (Count-in, Speed up, Practice speed, Stop after) is NOT exported.
3. Receiving: Metra as an Android share target for text; Import/Paste read the clipboard only when tapped; nothing Metra-shaped → "Nothing to add. Copy the whole Metra message, then try again."
4. Check dialog before adding ("10 songs you already have, 2 new"), then load the new set (song 1) or song.
   Matching: same name + same music = the existing song (also an earlier "(shared)" copy); the imported set points at it, nothing copied, and the receiver's own When I press Start stays. Same name, different music → added as "(shared)", "(shared 2)"; yours never changed. New songs arrive with When I press Start all off. Identical set → opens with "You already have this set"; different same-name set → "(shared)". Older/newer versions: read what's understood, skip unreadable songs and say so.
Tests: round-trip of every music feature, a future-version payload, importing the same set twice, a second set sharing songs with the first (no duplicates), mixed identical/different songs. Phone check: export a set from the phone to itself through WhatsApp and import it back.
```
