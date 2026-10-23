---
name: data-format-change
description: Use whenever a change touches what Metra saves - any toJson/fromJson in lib/src/model/, a field added, renamed or removed on Library, Song, Setlist, MetronomePattern, OnStart or ClickVolumes, or the files LibraryStore writes - and when the schema guard test fails.
---

# Changing the saved data format

Saved files must load forever: testers only ever move up, and an Auto Backup can restore any old version.

1. **Migration step.** In `lib/src/model/library_migrations.dart` add `_vNToVN1` working on raw JSON maps (never on model classes), append it to `_steps`, bump `latestVersion` (that is `Library.version`), and add a line to the version history at the top. Fill new fields with defaults, rename keys, convert values. Never drop user data silently.
2. **Parser.** Update `toJson`/`fromJson` for the new shape only. No fallbacks for old shapes there: that's the migration's job. Value checks (clamps, unknown enum names) belong in `fromJson` or `Library.repaired()`.
3. **Snapshot of the new format.** Give the new field a non-default value in `test/storage/sample_library.dart`, then run `WRITE_SNAPSHOT=1 flutter test test/storage/schema_guard_test.dart`: it writes `test/fixtures/library_v<N>/` (`library.json` + `settings.json`) for the new version and refuses to overwrite an existing one. Keep every older fixture as it is.
4. **Golden tests.** `test/storage/library_migrations_test.dart` loads every fixture through the store and re-saves it losslessly; add assertions that the migrated values are right for the new field.
5. **Store / backup.** If files are added or renamed, update `LibraryStore` and both rules files in `android/app/src/main/res/xml/` (the backup rules test checks they match).
6. `flutter analyze`, `flutter test`, commit, and note the format change in PLAN.md.

The schema guard (`test/storage/schema_guard_test.dart`) fails when the sample's JSON differs from the snapshot for the current version: that means steps 1–4 are due.
