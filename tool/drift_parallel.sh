#!/usr/bin/env bash
# The drift suite with every tempo at once (TESTING.md, "Stress tests").
# Each job runs from its own copy of the working tree (parallel builds
# can't share build/). Each test app says it's built and waits; "go" comes
# once all are built and $root/hold is gone (tool/release.sh --drift holds
# it while the AAB builds), so no timed run overlaps heavy work.
# Usage: tool/drift_parallel.sh [seconds] (default 300)
set -euo pipefail
cd "$(dirname "$0")/.."

seconds=${1:-300}
root=${DRIFT_ROOT:-${TMPDIR:-/tmp}/metra-drift}

# name|test name regex: the four long tempos, then everything else.
jobs=(
  "30|^30 BPM for"
  "60|^60 BPM for"
  "120|^120 BPM for"
  "300|^300 BPM for"
  "short|^(?![0-9]+ BPM for)"
)

mkdir -p "$root"
rm -f "$root"/*.ready "$root/go"
pids=()
for job in "${jobs[@]}"; do
  name=${job%%|*}
  dir=$root/$name
  rsync -a --delete --exclude build --exclude .git ./ "$dir/"
  # Its own bundle ID (macOS may not launch a second running copy of one
  # app), and no sandbox, so the app can see $root.
  sed -i '' "s/^PRODUCT_BUNDLE_IDENTIFIER = .*/&.drift$name/" \
    "$dir/macos/Runner/Configs/AppInfo.xcconfig"
  sed -i '' '/app-sandbox/{n;s/<true\/>/<false\/>/;}' \
    "$dir/macos/Runner/DebugProfile.entitlements"
  (cd "$dir" && caffeinate -dimsu flutter test integration_test/drift_test.dart \
    -d macos --name "${job#*|}" \
    --dart-define=DRIFT_SECONDS="$seconds" \
    --dart-define=DRIFT_BARRIER="$root" \
    --dart-define=DRIFT_JOB="$name" >"$root/$name.log" 2>&1) &
  pids+=($!)
done
echo "Building ${#jobs[@]} copies. Logs: $root/*.log"

# Go once every app is built (or a job died) and nothing holds.
while true; do
  ready=$(find "$root" -maxdepth 1 -name '*.ready' | wc -l)
  running=0
  for pid in "${pids[@]}"; do kill -0 "$pid" 2>/dev/null && running=$((running + 1)); done
  if (( ready >= running )) && [[ ! -e $root/hold ]]; then break; fi
  sleep 1
done
touch "$root/go"
echo "All built; the runs started at $(date +%T)."

failed=0
for i in "${!jobs[@]}"; do
  name=${jobs[$i]%%|*}
  if wait "${pids[$i]}"; then
    echo "$name: passed"
  else
    echo "$name: FAILED (see $root/$name.log)"
    failed=1
  fi
done
exit $failed
