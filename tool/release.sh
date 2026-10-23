#!/usr/bin/env bash
# The mechanical release steps (see RELEASING.md and the release skill).
# Run after bumping pubspec.yaml and writing assets/whats_new.md and
# CHANGELOG.md. Builds the signed AAB (Play) and APK (sideload copy),
# prints the Play release notes, and with --tag tags the release locally.
# It never pushes: the commands to publish are printed at the end.
set -euo pipefail
cd "$(dirname "$0")/.."

tag=false
[[ "${1:-}" == "--tag" ]] && tag=true

version_line=$(grep -E '^version: [0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$' pubspec.yaml)
version=${version_line#version: }
name=${version%%+*}
build=${version##*+}
echo "Releasing Metra $name (build $build)"

# Uncommitted work would not be in the release (the designer's
# docs/design/ drafts are fine).
if [[ -n "$(git status --porcelain -- . ':!docs/design')" ]]; then
  echo "Commit or stash your changes first:" >&2
  git status --short -- . ':!docs/design' >&2
  exit 1
fi
if git rev-parse -q --verify "refs/tags/v$name" >/dev/null; then
  echo "Tag v$name already exists: bump the version name." >&2
  exit 1
fi
[[ -f android/key.properties ]] || {
  echo "android/key.properties is missing: release builds can't be signed." >&2
  exit 1
}

flutter analyze
flutter test
flutter build appbundle --release
flutter build apk --release

if $tag; then
  git tag "v$name"
  echo "Tagged v$name (not pushed)."
fi

echo
echo "=== Play Console release notes ($name) ==="
awk -v v="$name" '
  $0 ~ "^## " v " " { on = 1; next }
  on && /^## / { exit }
  on && /^- / { print }
' assets/whats_new.md
echo
echo "AAB: build/app/outputs/bundle/release/app-release.aab"
echo "APK: build/app/outputs/flutter-apk/app-release.apk"
echo
echo "To publish (after the device checks in .agents/skills/device-qa/SKILL.md):"
echo "  git push && git push origin v$name"
echo "  gh release create v$name --title \"Metra $name\" --notes-file <notes.md>"
