# Releasing Metra

The step-by-step runbook is the release skill: [.agents/skills/release/SKILL.md](.agents/skills/release/SKILL.md). In short:

1. Bump `version: X.Y.Z+N` in `pubspec.yaml` (always the build number; the version name for anything users see). Never reuse or lower a build number.
2. Add the version's lines at the top of `assets/whats_new.md` (the in-app What's new and the Play release notes) and move `[Unreleased]` in `CHANGELOG.md` under the new version.
3. Commit, then run `tool/release.sh` (checks, `flutter analyze`, `flutter test`, signed AAB and APK, prints the Play notes; `--tag` tags locally). It never pushes.
4. Check the build on a phone: [device checklist](.agents/skills/device-qa/SKILL.md).
5. Push, push the tag, create the GitHub release, and upload `build/app/outputs/bundle/release/app-release.aab` to Play Console with the printed notes.

Signing needs `android/key.properties` and the keystore in `~/keys/` (never in git; details in PLAN.md "Release builds"). The release tests (`test/platform/release_consistency_test.dart`, `test/storage/schema_guard_test.dart`) fail if the notes don't match the version or the saved data format changed without a migration.

Phones that installed Metra from Play can only be updated through Play (Google signs those builds); the debug app `com.dror.metra.debug` ("Metra dev") installs beside it with `adb install -r`.

## Play Console answers
- **Privacy policy URL:** https://github.com/drormos/metra/blob/main/PRIVACY.md
- **Data safety:** no data collected, no data shared (the app has no internet permission; feedback is an email the user sends from their own email app). Data is not encrypted in transit because none is transmitted.
- **Foreground service:** `mediaPlayback` (the click keeps playing with the screen off; declared with a short video).
- **Ads:** none. **Target audience:** not directed at children.

If a dependency ever adds the internet permission (check the merged release manifest: `build/app/intermediates/merged_manifests/release/processReleaseManifest/AndroidManifest.xml`), PRIVACY.md and the Data safety answers must change before release.
