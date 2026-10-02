#!/usr/bin/env bash
# Render one Omascayl screen offscreen, without a Wayland window:
#
#   tests/snapshot.sh OUT.png ['{"tab":"settings"}'] [EXTRA_ENV=value ...]
#
# The state JSON is applied by AppWindow.applySnapshotState (see shell.qml).
# State and cache go to a scratch dir and notifications are off, so a run
# never touches the real settings or the desktop.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
out=$(realpath -m -- "$1")
state=${2:-"{}"}
shift $(( $# >= 2 ? 2 : 1 ))

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/config" "$work/state" "$work/cache"
for f in "$root"/src/*; do ln -s -- "$f" "$work/config/"; done

# The app runs every tool by absolute path (Core.BIN, /usr/bin/), never through
# PATH. A test that needs fake tools passes OMASCAYL_TEST_FAKEBIN: this run
# then gets its own Core.js whose BIN is a scratch folder of links to /usr/bin
# with the fakes laid over them. The shipped Core.js is never changed.
if [[ -n ${OMASCAYL_TEST_FAKEBIN:-} ]]; then
  mkdir -p "$work/bin"
  ln -s /usr/bin/* "$work/bin/" 2>/dev/null || true
  for f in "$OMASCAYL_TEST_FAKEBIN"/*; do ln -sfn -- "$f" "$work/bin/"; done
  rm -- "$work/config/Core.js"
  sed "s|^var BIN = \"/usr/bin/\"$|var BIN = \"$work/bin/\"|" "$root/src/Core.js" > "$work/config/Core.js"
  grep -q "^var BIN = \"$work/bin/\"$" "$work/config/Core.js" || { echo "snapshot.sh: Core.js BIN seam not found" >&2; exit 1; }
fi
omarchy=${OMARCHY_PATH:-/usr/share/omarchy}
ln -s -- "$omarchy/shell/Commons" "$work/config/Commons"
ln -s -- "$omarchy/shell/Ui" "$work/config/Ui"
printf '%s\n' "${OMASCAYL_TEST_SETTINGS:-"{\"notifications\": false}"}" > "$work/state/settings.json"

# Real upscales use whatever backend Omascayl itself would find (a system
# Upscayl, or one bin/omascayl-setup downloaded), unless OMASCAYL_BIN and
# OMASCAYL_MODELS say otherwise.
mapfile -t backend < <("$root/bin/omascayl-backend" 2>/dev/null)

# The app opens its setup through $OMARCHY_PATH/bin/omarchy. Point that at a
# recorder, so no snapshot can ever start a real terminal on the desktop
# (a test can still pass its own OMARCHY_PATH).
mkdir -p "$work/fake-omarchy/bin"
printf '#!/bin/sh\necho "$*" >> "%s/fake-omarchy/calls"\n' "$work" > "$work/fake-omarchy/bin/omarchy"
chmod +x "$work/fake-omarchy/bin/omarchy"

env -u WAYLAND_DISPLAY -u DISPLAY \
  QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= QT_FORCE_STDERR_LOGGING=1 \
  OMASCAYL_STATE_DIR="$work/state" OMASCAYL_CACHE_DIR="$work/cache" \
  OMASCAYL_BIN="${OMASCAYL_BIN:-${backend[0]}}" \
  OMASCAYL_MODELS="${OMASCAYL_MODELS:-${backend[1]}}" \
  OMASCAYL_SNAPSHOT="$out" OMASCAYL_SNAPSHOT_STATE="$state" \
  OMASCAYL_TOOLS="${OMASCAYL_TOOLS:-$work/no-tools}" \
  OMARCHY_PATH="$work/fake-omarchy" \
  "$@" \
  timeout 60 qs -p "$work/config"
