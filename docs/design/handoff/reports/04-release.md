# 04 · Release: tuner, square 4/4, louder click, panel closing: report

Metra **1.9.0 (build 108)**, signed AAB built, not uploaded. `flutter analyze` is clean and `flutter test` passes (1700 tests). Dror's phone wasn't touched; every device check ran on an Android emulator (API 37).

## Version
Dror confirmed 1.8.0 (build 103) is in the closed test, so this is **1.9.0** with only the four new lines (1.8.0's two lines are not repeated).

## Play release notes (paste as is, 224 / 500 characters)
```
- New: a tuner for guitar and bass. Tap the tuning fork at the top.
- The click is louder at full volume.
- The time signature button is now a small square that never changes size.
- Tap anywhere outside a panel to close it.
```
All four lines show in the app's What's new block (the limit is 4). `assets/whats_new.md`, `CHANGELOG.md` (`[1.9.0] - 2026-11-03`) and `store/listing.md` (release notes section) match.

## AAB
`build/app/outputs/bundle/release/app-release.aab` (62.4 MB), versionName 1.9.0, versionCode 108, signed with the upload key. A sideload copy is at `build/app/outputs/flutter-apk/app-release.apk`. The merged release manifest requests neither INTERNET nor POST_NOTIFICATIONS (the release script checks).

## Privacy
- PRIVACY.md already has the microphone paragraph and the permissions line (committed with the tuner, 530d12a). **It is not online yet:** pushing `main` was blocked by Claude Code's permission check (a push to the public repo). Dror: run `! git push origin main` (20 local commits, including this release). Once pushed, https://github.com/drormos/metra/blob/main/PRIVACY.md shows the microphone paragraph. Do this before you send the build for review.
- Play Console: **Data safety stays "No data collected"** (audio is processed on the phone, never stored or sent; RELEASING.md records this). The one Play Console item to check: the release now asks for **RECORD_AUDIO**. If Play asks you to explain a sensitive permission, it is the tuner, used only while the tuner page is open. Nothing else changes.

## Store listing
`store/listing.md` has the TUNER section, and the full description is 3033 / 4000 characters (recounted). The release notes section now holds the 1.9.0 lines (224 / 500). No new screenshots.

## Upgrade check (emulator, 1.8.0 build 103 → 1.9.0 build 108)
- I built 1.8.0 from its release commit (46f1473) with the same upload key and installed it on a fresh emulator. Then I added data the way a user would:
  - **Songs and a set:** I imported the 12-song demo set "Fri · The Blue Room" (one song with parts) through Metra's share target, using 1.8.0's own export code.
  - **Practice speed:** on Glass Harbor, 75%, +2.5% each loop, up to 100%, then Save.
  - **Free play:** 96 BPM, 4/4 with eighths.
- I installed 1.9.0 over it with `adb install -r`. After the upgrade:
  - **Survived:** Free play 96 with eighths; the set with 12 songs at 1/12; Glass Harbor's Practice speed (75%, +2.5%, 100%); the tuning-fork button in the top row.
  - **Tuner:** Reference A4 = 440 Hz; the microphone prompt appears on first open; with access allowed, the tuner shows "Play a string".
- My first try left Practice speed unsaved: in 1.8.0, turning it on is a song edit that needs Save, and I moved to another song without saving. That is not an upgrade bug. I redid the check from a clean 1.8.0 install with Save.

## Tuner check without a guitar
New test `test/controller/tuner_guitar_test.dart`:
- **The sound:** plucked strings synthesized with Karplus-Strong, tuned exactly (0.00 cents error before noise), mixed with 50 Hz mains hum and white noise.
- **The strings:** the six open strings E2 A2 D3 G3 B3 E4, each in tune, −15, +8 and +30 cents.
- **The path:** the samples go through the real `TunerController` (the detector plus the 5-reading median), in 1024-sample chunks as the microphone delivers them.
- **Right after the pluck (0.3 s), on every string:** the right note, and within 0.1 cent of the true offset.
- **Low E:** within 0.1 cent the whole 2 seconds (e.g. +30 reads 30.07, then 29.96).
- **Late in the ring:** the treble strings fade faster, and their readings wobble once the string is only ~15 dB above the noise: up to 1.4 cents at 1 s (E4), and 2.4 cents at 2 s (G3 +8 read 10.4).
- **When the string dies into the noise:** the tuner holds the last reading for 1 second and then shows nothing. It never showed a wrong note.

**For Dror:** on synthesized guitar notes the detector is spot on while the string rings clearly, low E included. The final proof is a real guitar (real strings are slightly inharmonic, and a phone mic colours the sound), whenever you want.

## Gates and stress
- `flutter analyze` and `flutter test` (1700) pass.
- Scheduler fuzz: 5,000 sessions pass. Load fuzz: 4,000 runs pass.
- Drift suite (5 minutes per tempo): the first run overlapped the Gradle build and the emulator and lost beats (126 of 150 at 30 BPM, 253 of 300 at 60 BPM). That is the busy-Mac failure TESTING.md describes. I re-ran it alone, and all 12 tests passed (30, 60, 120 and 300 BPM for 5 minutes each, plus the short tests; 20:45 in total).
- To make the drift suite less of a wait, `tool/release.sh --drift` now runs it through the new `tool/drift_parallel.sh`. All tempos run at once, and only after every build is done, Trial: all passed in 12:33, against 20:45 one by one. That run included cold builds of the five copies (~7 min); the copies are kept, so later runs build faster. See TESTING.md and the release skill.

## Not done (needs Dror)
- `git push origin main` (publishes PRIVACY.md), then upload the AAB to the closed test.
- Tag after upload: `git tag v1.9.0 && git push origin v1.9.0`, plus `gh release create v1.9.0 --title "Metra 1.9.0"`. v1.8.0 isn't tagged yet either (commit 46f1473).

## Screenshots (emulator)
These live in the session scratchpad (not committed):
- `/private/tmp/claude-501/-Users-dror-Developer-metra/1f7e935d-37d5-4b22-9dbb-3649795d5e24/scratchpad/u1.png`: Free play after the upgrade.
- `/private/tmp/claude-501/-Users-dror-Developer-metra/1f7e935d-37d5-4b22-9dbb-3649795d5e24/scratchpad/u2.png`: Glass Harbor's Practice speed after the upgrade.
- `/private/tmp/claude-501/-Users-dror-Developer-metra/1f7e935d-37d5-4b22-9dbb-3649795d5e24/scratchpad/u4.png`: the tuner, A4 440, listening.

## Update: build 109
When Dror uploaded build 108, Play warned that it no longer supported 17 devices (7 phones, 10 tablets) that 1.8.0 supported.
- **Why:** the tuner's RECORD_AUDIO permission makes Play require a microphone (`android.hardware.microphone`) unless the app says it's optional.
- **Fix:** the manifest now declares the microphone `required="false"`. On a device without one, the tuner page just keeps saying "Play a string"; the rest of the app is unaffected.
- **Guard:** `tool/release.sh` now refuses a build that requires a microphone.
- **New build:** 1.9.0 (build 109), same release notes. The AAB is at the same path.
