# 04 · Release: tuner, square 4/4, louder click, panel closing

Prepare the next closed-testing release (use the release skill).

1. Version: the next minor version after the one currently in closed testing (check what's there; if 1.8.0 was never uploaded, this release includes its features too, and the notes below should add its two lines: "Send a whole setlist or song to a bandmate: Share › Export, they copy it and tap Share › Import." and "Practice speed climbs in smaller steps: +1%, +2%, +2.5% and up.").
2. In-app What's new and Play release notes (max 4 lines in the app; tell me if they don't fit):
   - New: a tuner for guitar and bass. Tap the tuning fork at the top.
   - The click is louder at full volume.
   - The time signature button is now a small square that never changes size.
   - Tap anywhere outside a panel to close it.
3. Privacy: the online privacy policy must match the app before the release. Push PRIVACY.md (with the microphone paragraph) now, and tell me if anything else must change in Play Console (Data safety stays "No data collected", per your earlier check).
4. Store: confirm store/listing.md has the TUNER section and the character count; no new screenshots needed.
5. Upgrade check from the build in closed testing (settings format changed for Reference A4) on an **Android emulator**, not the phone: install the closed-testing build, add songs, a set, Free play, a Practice speed song, then install the new release build over it and confirm everything survived and Reference A4 is 440.
6. Build the signed AAB. Don't upload. Report the AAB path, version, and the exact Play release notes to paste.

7. **Don't use Dror's phone at all for this release** (he needs it). Tuner check in code instead: synthesize plucked-guitar notes (e.g. Karplus-Strong) for the six open strings E2 A2 D3 G3 B3 E4, plus slightly sharp/flat versions and some background noise, run them through the real pitch detector in tests, and confirm note and cents (low E especially). If an emulator is running, a quick look at the tuner page there is enough for the UI; its microphone isn't needed.

Note for Dror in the report: say how the detector did on the synthesized guitar notes; a real guitar is the final proof, whenever he wants.
