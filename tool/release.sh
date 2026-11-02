#!/usr/bin/env bash
# The mechanical release steps (see RELEASING.md and the release skill).
# Run after bumping pubspec.yaml and writing assets/whats_new.md and
# CHANGELOG.md. Builds the signed AAB (Play) and APK (sideload copy),
# prints the Play release notes, and with --tag tags the release locally.
# With --drift it also runs tool/drift_parallel.sh: the drift copies build
# alongside the gates and the AAB, and their runs start once those are done.
# It never pushes: the commands to publish are printed at the end.
set -euo pipefail
cd "$(dirname "$0")/.."

tag=false
drift=false
for arg in "$@"; do
  case $arg in
    --tag) tag=true ;;
    --drift) drift=true ;;
    *) echo "Unknown option $arg" >&2; exit 1 ;;
  esac
done

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

# The exact Flutter pinned in pubspec.yaml (environment: flutter).
pinned=$(grep -E '^  flutter: [0-9]+\.[0-9]+\.[0-9]+$' pubspec.yaml | awk '{print $2}')
installed=$(flutter --version --machine | python3 -c "import json,sys;print(json.load(sys.stdin)['frameworkVersion'])")
if [[ "$pinned" != "$installed" ]]; then
  echo "Flutter $installed is installed; pubspec.yaml pins $pinned." >&2
  exit 1
fi

if $drift; then
  export DRIFT_ROOT=${TMPDIR:-/tmp}/metra-drift
  mkdir -p "$DRIFT_ROOT" && touch "$DRIFT_ROOT/hold"
  tool/drift_parallel.sh >"$DRIFT_ROOT/summary.log" 2>&1 &
  drift_pid=$!
  trap 'rm -f "$DRIFT_ROOT/hold"' EXIT
fi

flutter analyze
flutter test
flutter build appbundle --release
flutter build apk --release
$drift && rm -f "$DRIFT_ROOT/hold"

# PRIVACY.md promises no network access and one permission prompt (the
# tuner's microphone): no dependency may add internet or notifications.
merged=build/app/intermediates/merged_manifests/release/processReleaseManifest/AndroidManifest.xml
for permission in INTERNET POST_NOTIFICATIONS; do
  if grep -q "android.permission.$permission" "$merged"; then
    echo "The release build requests $permission: update PRIVACY.md and Play's Data safety first." >&2
    exit 1
  fi
done
# A permission implies a required feature on Play (RECORD_AUDIO: a
# microphone), which drops devices without it (1.9.0 build 108: 17 devices).
if ! grep -A1 'android.hardware.microphone' "$merged" | grep -q 'required="false"'; then
  echo "The release build requires a microphone: declare android.hardware.microphone required=\"false\"." >&2
  exit 1
fi

if $drift; then
  echo "Waiting for the drift runs (~5 minutes, keep the Mac idle)..."
  if wait "$drift_pid"; then drift_ok=true; else drift_ok=false; fi
  cat "$DRIFT_ROOT/summary.log"
  $drift_ok || { echo "Drift failed: re-run a failed tempo alone before trusting it (TESTING.md)." >&2; exit 1; }
fi

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
