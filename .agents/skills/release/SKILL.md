---
name: release
description: Use when shipping a Metra build to testers or the Play Store (a new version or build number, "make a release", "cut 1.6.0", "build the AAB"). Bumps pubspec, updates assets/whats_new.md and CHANGELOG.md, checks the data snapshot, runs the quality gates, builds the AAB, tags, and prints the Play notes and the device checklist.
---

# Release

Mechanical steps are in `tool/release.sh`; this is the full order. Ask before pushing, tagging or publishing anything (the repo is public).

1. **Version.** In `pubspec.yaml` bump `version: X.Y.Z+N`: always `+N` (every shared build), and `X.Y.Z` for anything users will see. Never reuse or lower a build number (Play refuses it; testers can't downgrade, see the data-format-change skill).
2. **Notes.** Add `## X.Y.Z · Mon YYYY` at the top of `assets/whats_new.md` with 3–5 short "- " lines in plain words (the first 3 show in the app's What's new block; all of them are the Play release notes). In `CHANGELOG.md`, move `## [Unreleased]` items under `## [X.Y.Z] - YYYY-MM-DD` (Added / Changed / Fixed).
3. **Data snapshot.** `flutter test test/storage/` must pass. If the schema guard fails, stop and follow the data-format-change skill before releasing.
4. **Gates.** `flutter analyze` and `flutter test` clean; if the scheduler or the store changed since the last release, also the long stress runs and the drift suite (TESTING.md, "Stress tests") (the release-consistency test checks pubspec, What's new and CHANGELOG agree).
5. **Build.** `tool/release.sh` (or by hand: `flutter build appbundle --release`, plus `flutter build apk --release` for a sideload copy). Signing needs `android/key.properties` (gitignored; see PLAN.md "Release builds").
6. **Record and tag.** Update PLAN.md's Status (and a "Recent decisions" line if anything was decided), commit `release: X.Y.Z (build N)`, then with the user's go-ahead: `git push`, `git tag vX.Y.Z && git push origin vX.Y.Z`, `gh release create vX.Y.Z --title "Metra X.Y.Z" --notes-file <notes>`.
7. **Hand over.** Print the Play Console notes (the What's new lines) and the path `build/app/outputs/bundle/release/app-release.aab`. Print the device-qa checklist sections touched by this release.

Installing on the user's phone: `adb install -r` only (never `flutter install`, it wipes data). A Play-installed Metra can't be sideloaded over (different signing key); the debug app `com.dror.metra.debug` installs beside it.
