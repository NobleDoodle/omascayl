#!/usr/bin/bash
# Tests bin/omascayl-setup the way Omarchroma tests its setup: run a probe copy
# whose PATH line puts a fake sudo (and pacman) first, whose dependency check
# answers from a file, and whose pinned download points at a local file://
# mirror of small fake files (with their hashes written in). Scratch HOME;
# nothing real is installed or downloaded.
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
export HOME="$work/home"
unset XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME
mkdir -p "$HOME" "$work/fake" "$work/tools" "$work/mirror/models" "$work/engine-src/upscayl-bin-TEST-linux"
log="$work/calls.log"

# Fakes: sudo records what would have run; pacman says every package is
# already installed when asked (-Qq).
printf '#!/bin/sh\necho "sudo $*" >> "%s"\nexit 0\n' "$log" > "$work/fake/sudo"
printf '#!/bin/sh\n[ "$1" = "-Qq" ] && exit 0\necho "pacman $*" >> "%s"\n' "$log" > "$work/fake/pacman"
# The dependency check answers from $work/deps.txt.
printf '#!/usr/bin/env bash\ncat "%s/deps.txt"\n' "$work" > "$work/tools/omascayl-deps"
chmod +x "$work/fake/"* "$work/tools/"*
# The real file writer, next to the fake dependency check.
ln -s "$here/bin/omascayl-store" "$here/bin/omascayl_fs.py" "$work/tools/"

# A fake engine release and models, and their hashes.
printf '#!/bin/sh\necho fake engine\n' > "$work/engine-src/upscayl-bin-TEST-linux/upscayl-bin"
(cd "$work/engine-src" && zip -qr "$work/mirror/engine.zip" .)
models_block=""
for m in a-4x b-4x; do
  for ext in param bin; do
    echo "$m.$ext data" > "$work/mirror/models/$m.$ext"
    models_block+="  \"$m.$ext $(sha256sum "$work/mirror/models/$m.$ext" | cut -d' ' -f1)\""$'\n'
  done
done

probe="$work/omascayl-setup"
python3 - "$here/bin/omascayl-setup" "$probe" "$work" "$models_block" \
  "$(sha256sum "$work/mirror/engine.zip" | cut -d' ' -f1)" \
  "$(sha256sum "$work/engine-src/upscayl-bin-TEST-linux/upscayl-bin" | cut -d' ' -f1)" <<'PY'
import re, sys
src, dst, work, models, zip_sha, bin_sha = sys.argv[1:]
s = open(src).read()
def sub(pattern, repl):
    global s
    s, n = re.subn(pattern, lambda m: repl, s, count=1, flags=re.M)
    assert n == 1, pattern
sub(r'^PATH=\$\(omascayl_trusted_path\)$', 'PATH="%s/fake:$(omascayl_trusted_path)"' % work)
sub(r'^here=.*$', 'here="%s/tools"' % work)
sub(r'^ENGINE_URL=.*$', 'ENGINE_URL="file://%s/mirror/engine.zip"' % work)
sub(r'^ENGINE_ZIP_SHA256=.*$', 'ENGINE_ZIP_SHA256=' + zip_sha)
sub(r'^ENGINE_BIN_SHA256=.*$', 'ENGINE_BIN_SHA256=' + bin_sha)
sub(r'^MODELS_URL=.*$', 'MODELS_URL="file://%s/mirror/models"' % work)
sub(r'^CURL_PROTO=.*$', 'CURL_PROTO="=https,file"')
sub(r'^MODELS=\(\n(?:  ".*"\n)+\)$', 'MODELS=(\n' + models + ')')
open(dst, 'w').write(s)
PY
chmod +x "$probe"

pass=0; fail=0
expect() { if eval "$2"; then echo "  ok   $1"; pass=$((pass+1)); else echo "  FAIL $1"; fail=$((fail+1)); fi; }
backend="$HOME/.local/share/omascayl/backend"
marker="$HOME/.local/state/omascayl/setup-finished"
T=$'\t'
dep() { printf '%s\t%s\t%s\tlabel %s\t%s\twhy\n' "$1" "$2" "$3" "$2" "$4"; }
all_ok() { dep ok backend required -; dep ok vulkan required -; dep ok picker recommended -; dep ok clipboard recommended -; dep ok notify recommended -; dep ok open recommended -; }
deps() {  # key=state:packages ... over the all-ok baseline
  all_ok > "$work/deps.txt"
  local kv key st pk
  for kv in "$@"; do
    key=${kv%%=*}; st=${kv#*=}; pk=${st#*:}; st=${st%%:*}
    sed -i "s/^ok${T}${key}${T}\([a-z]*\)${T}\(label [a-z]*\)${T}-/${st}${T}${key}${T}\1${T}\2${T}${pk}/" "$work/deps.txt"
  done
}
run() { rm -f "$log" "$marker"; printf "$1" | timeout 60 "$probe" > "$work/out.txt" 2>&1; echo $?; }

echo "== the real script parses, and the probe only changes its test seams"
expect "bash -n" 'bash -n "$here/bin/omascayl-setup"'
expect "probe differs only where intended" '[[ $(diff "$here/bin/omascayl-setup" "$probe" | grep -c "^>") -le 12 ]]'
expect "no menu, no AUR option, no typed consent" '! grep -qE "Choose 1|aur add|I understand" "$here/bin/omascayl-setup"'

echo "== nothing missing"
deps
rc=$(run '')
expect "says so, exit 0, asks nothing" '[[ $rc == 0 ]] && grep -q "Everything Omascayl needs is installed" "$work/out.txt" && ! grep -q "Proceed" "$work/out.txt"'
expect "leaves the finished marker for the window" '[[ -f $marker ]]'

echo "== backend missing, answered n"
deps backend=missing:upscayl-bin
rc=$(run 'n\n')
expect "shows the plan and one question" 'grep -q "This will install:" "$work/out.txt" && grep -q "engine and AI models" "$work/out.txt" && [[ $(grep -c "Proceed? \[Y/n\]" "$work/out.txt") == 1 ]]'
expect "nothing changed, exit 1" '[[ $rc == 1 ]] && grep -q "Nothing was changed" "$work/out.txt" && [[ ! -e $backend && ! -s $log ]]'
expect "marker written" '[[ -f $marker ]]'

echo "== backend missing, Enter (the default is yes)"
rc=$(run '\n')
expect "exit 0" '[[ $rc == 0 ]]'
expect "engine installed and executable" '[[ -x $backend/upscayl-bin && $("$backend/upscayl-bin") == "fake engine" ]]'
expect "all models installed" '[[ $(ls "$backend/models" | wc -l) == 4 ]]'
expect "VERSION recorded" 'grep -q "^engine " "$backend/VERSION" && grep -q "^models " "$backend/VERSION"'
expect "no sudo needed" '[[ ! -s $log ]]'
expect "download scratch removed" '[[ -z $(ls -A "$HOME/.cache/omascayl" 2>/dev/null) ]]'

echo "== y works too"
rm -rf "$backend"
rc=$(run 'y\n')
expect "downloads" '[[ $rc == 0 && -x $backend/upscayl-bin ]]'

echo "== backend and packages missing: one question covers both"
rm -rf "$backend"
deps backend=missing:upscayl-bin clipboard=missing:wl-clipboard notify=missing:libnotify
rc=$(run '\n')
expect "plan lists the packages" 'grep -q "wl-clipboard libnotify (from the Arch repositories" "$work/out.txt"'
expect "pacman installs them without asking again" 'grep -qx "sudo pacman -S --needed --noconfirm -- wl-clipboard libnotify" "$log"'
expect "and the backend is downloaded" '[[ -x $backend/upscayl-bin ]]'
expect "still only one question" '[[ $(grep -c "Proceed?" "$work/out.txt") == 1 ]]'

echo "== only recommended packages missing"
deps picker=missing:"python-gobject xdg-desktop-portal-gtk"
rc=$(run '\n')
expect "installs them, no download" 'grep -qx "sudo pacman -S --needed --noconfirm -- python-gobject xdg-desktop-portal-gtk" "$log" && ! grep -q "Downloading" "$work/out.txt"'

echo "== Vulkan loader missing"
deps vulkan=missing:vulkan-icd-loader
rc=$(run '\n')
expect "installs the loader" 'grep -qx "sudo pacman -S --needed --noconfirm -- vulkan-icd-loader" "$log"'

echo "== a tampered file is refused and nothing is kept"
rm -rf "$backend"
deps backend=missing:upscayl-bin
echo tampered > "$work/mirror/models/b-4x.bin"
rc=$(run '\n')
expect "checksum mismatch reported" 'grep -q "Checksum mismatch: b-4x.bin" "$work/out.txt"'
expect "nothing kept, exit 1" '[[ $rc == 1 && ! -e $backend ]]'
expect "reported as not done" 'grep -q "Not done:.*nothing was kept" "$work/out.txt"'

echo "== a failed update keeps the previous backend"
mkdir -p "$backend/models" && echo old > "$backend/VERSION"
rc=$(run '\n')
expect "previous backend untouched" '[[ $(cat "$backend/VERSION") == old ]]'

# Faults reported against Omarchroma's setup, replayed: the sudo command line
# takes only fixed package names, and the user-writable files setup writes are
# not redirected by planted symlinks.
echo "== a package name outside the fixed list never reaches sudo"
deps clipboard=missing:"wl-clipboard --overwrite=*" notify=missing:evil-package
rc=$(run '\n')
expect "refused, exit 1, nothing run" '[[ $rc == 1 ]] && grep -q "unexpected package names:.*--overwrite=\* evil-package" "$work/out.txt" && [[ ! -s $log ]]'
expect "asks nothing" '! grep -q "Proceed?" "$work/out.txt"'

echo "== a symlinked marker is replaced, not written through"
deps
echo keep > "$work/victim"
rm -f "$marker"
ln -s "$work/victim" "$marker"
printf '' | timeout 60 "$probe" > "$work/out.txt" 2>&1
expect "target unchanged" '[[ $(cat "$work/victim") == keep ]]'
expect "marker is a plain file now" '[[ -f $marker && ! -L $marker ]]'

echo "== a symlinked backend folder is replaced, not written into"
rm -rf "$backend"
mkdir -p "$work/precious" && touch "$work/precious/file"
ln -s "$work/precious" "$backend"
echo "b-4x.bin data" > "$work/mirror/models/b-4x.bin"
deps backend=missing:upscayl-bin
rc=$(run '\n')
expect "installed" '[[ $rc == 0 && -x $backend/upscayl-bin && ! -L $backend ]]'
expect "link target untouched" '[[ $(ls -A "$work/precious") == file ]]'

echo "== a staged file swapped after setup checked it is refused by the copy"
mkdir -p "$work/stage/models" && echo engine > "$work/stage/upscayl-bin" && echo swapped > "$work/stage/models/x.bin"
good=$(sha256sum "$work/stage/upscayl-bin" | cut -d' ' -f1)
before=$(cat "$backend/VERSION")
"$here/bin/omascayl-store" place-backend "$work/stage" "v" "upscayl-bin=$good" "models/x.bin=$good" 2> "$work/err.txt"; rc=$?
expect "refused" '[[ $rc == 1 ]] && grep -q "checksum mismatch: models/x.bin" "$work/err.txt"'
expect "previous backend kept" '[[ $(cat "$backend/VERSION") == "$before" ]]'
"$here/bin/omascayl-store" place-backend "$work/stage" "v" "upscayl-bin=$good" "../escape=$good" 2>/dev/null; rc=$?
expect "names outside the backend refused" '[[ $rc == 1 ]]'

echo "== no temporaries left behind"
expect "none" '[[ -z $(find "$HOME/.local" -name ".backend-*" -o -name ".setup-finished.*") ]]'

echo "passed $pass, failed $fail"
[[ $fail == 0 ]]
