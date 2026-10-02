#!/usr/bin/env bash
# End-to-end: drives the real app offscreen through real upscayl-bin runs
# (single, cached, double, custom width, 8x resize, batch, GPU error, stop,
# folder detection, clipboard paste). Needs upscayl-bin, ImageMagick and jq,
# and a Vulkan GPU. Takes about a minute.
set -u
W=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
E=$(mktemp -d)
trap 'rm -rf -- "$E"' EXIT
mkdir -p "$E"/{single,double,width,scale8,batch,stop,error,fakebin}
magick rose: -resize 200% "$E/rose.png"
for d in single double width scale8 error; do cp "$E/rose.png" "$E/$d/rose.png"; done
cp "$E/rose.png" "$E/batch/a.png"
magick "$E/rose.png" -rotate 90 "$E/batch/b.jpg"
echo notes > "$E/batch/notes.txt"
magick rose: -resize 1600x1050! "$E/stop/big.png"
cat > "$E/fakebin/wl-paste" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *--list-types*) tr ',' '\n' <<<"$FAKE_CLIP_TYPES" ;;
  *text/uri-list*) printf '%s' "$FAKE_CLIP_DATA" ;;
  *image/*) cat -- "$FAKE_CLIP_DATA" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$E/fakebin/wl-paste"
cd "$W"

pass=0; fail=0
check() {  # description, jq expression, case name
  if jq -e "$2" "$E/$3.png.json" >/dev/null 2>&1; then echo "  ok   $1"; pass=$((pass+1))
  else echo "  FAIL $1"; fail=$((fail+1)); fi
}
run() {  # name delay state [env...]
  local name=$1 delay=$2 state=$3; shift 3
  echo "== $name"
  tests/snapshot.sh "$E/$name.png" "$state" OMASCAYL_SNAPSHOT_DELAY="$delay" "$@" > "$E/$name.log" 2>&1
  grep -E "ERROR|qml:.*(TypeError|ReferenceError)" "$E/$name.log" | head -5
}
size() { magick identify -format '%wx%h' "$1" 2>/dev/null; }
LITE='"model":"upscayl-lite-4x"'

run single 8000 "{\"image\":\"$E/single/rose.png\",\"settings\":{$LITE},\"run\":true}"
check "result path" '.result | endswith("single/rose_upscayl_4x_upscayl-lite-4x.png")' single
check "finished cleanly" '.running == false and .error == null' single
check "input size" '.inputSize == [140,92]' single
check "stats" '.stats.total == 1 and .stats.image == 1' single
check "gpu list" '(.gpus | length) >= 1' single
[[ $(size "$E/single/rose_upscayl_4x_upscayl-lite-4x.png") == 560x368 ]] && check "4x is 560x368" true single || check "4x is 560x368" false single

run cached 5000 "{\"image\":\"$E/single/rose.png\",\"settings\":{$LITE},\"run\":true}"
check "existing result reused" '.toast | test("Already upscayled")' cached

run double 12000 "{\"image\":\"$E/double/rose.png\",\"settings\":{$LITE,\"scale\":\"2\"},\"doubleUpscayl\":true,\"run\":true}"
check "double result" '.result | endswith("rose_upscayl_2x_upscayl-lite-4x.png")' double
check "two passes" '[.logs[] | select(test("Upscayl command"))] | length == 2' double
[[ $(size "$E/double/rose_upscayl_2x_upscayl-lite-4x.png") == 560x368 ]] && check "2x twice is 560x368" true double || check "2x twice is 560x368" false double

run width 8000 "{\"image\":\"$E/width/rose.png\",\"settings\":{$LITE,\"useCustomWidth\":true,\"customWidth\":500,\"format\":\"jpg\",\"compression\":20},\"run\":true}"
[[ $(size "$E/width/rose_upscayl_500px_upscayl-lite-4x.jpg") == 500x328 ]] && check "custom width jpg 500x328" true width || check "custom width jpg 500x328" false width

run scale8 8000 "{\"image\":\"$E/scale8/rose.png\",\"settings\":{$LITE,\"scale\":\"8\",\"format\":\"webp\"},\"run\":true}"
[[ $(size "$E/scale8/rose_upscayl_8x_upscayl-lite-4x.webp") == 1120x736 ]] && check "8x webp 1120x736" true scale8 || check "8x webp 1120x736" false scale8

run batch 12000 "{\"batch\":\"$E/batch\",\"settings\":{$LITE},\"run\":true}"
check "batch output folder" '.batchResult | endswith("batch/upscayl_png_upscayl-lite-4x_4x")' batch
check "batch 2/2" '.batchDone == 2 and .batchTotal == 2' batch

run openfolder 2500 "{\"open\":\"$E/batch/\"}"
check "a folder switches to batch mode" '.batchMode == true and (.folder | endswith("/batch"))' openfolder

run error 6000 "{\"image\":\"$E/error/rose.png\",\"settings\":{$LITE,\"gpuId\":\"7\"},\"run\":true}"
check "GPU error" '.error.title == "GPU Error" and .result == ""' error

run stop 6000 "{\"image\":\"$E/stop/big.png\",\"settings\":{\"model\":\"upscayl-standard-4x\",\"tta\":true},\"run\":true,\"stopAfter\":2000}"
check "stopped quietly" '.running == false and .error == null and .result == ""' stop
sleep 1
if pgrep -f "[u]pscayl-bin -i $E/stop" >/dev/null; then check "backend killed" false stop; else check "backend killed" true stop; fi

OMASCAYL_TEST_FAKEBIN="$E/fakebin" run paste-uri 2500 '{"paste":true}' FAKE_CLIP_TYPES="text/uri-list" FAKE_CLIP_DATA="file://$E/rose.png"
check "paste a copied file" ".image == \"$E/rose.png\"" paste-uri
OMASCAYL_TEST_FAKEBIN="$E/fakebin" run paste-raw 2500 '{"paste":true}' FAKE_CLIP_TYPES="image/png" FAKE_CLIP_DATA="$E/rose.png" OMASCAYL_PICTURES="$E/Pictures"
check "paste image data" ".image | test(\"/clipboard/pasted-.*png$\")" paste-raw
check "pasted output goes to Pictures" ".output == \"$E/Pictures\"" paste-raw

# Pickers, with a fake bin/omascayl-pick (the real one would open a dialog):
# it logs its arguments, prints $FAKE_PICK and exits with $FAKE_PICK_RC.
mkdir -p "$E/tools" "$E/models"
cat > "$E/tools/omascayl-pick" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$E/pick.\$\$.args"
[[ -n \${FAKE_PICK_ERR:-} ]] && echo "\$FAKE_PICK_ERR" >&2
[[ -n \${FAKE_PICK:-} ]] && echo "\$FAKE_PICK"
exit "\${FAKE_PICK_RC:-0}"
EOF
chmod +x "$E/tools/omascayl-pick"
touch "$E/models/my-model-2x.param" "$E/models/my-model-2x.bin"
pick_args() { cat "$E"/pick.*.args 2>/dev/null | paste -sd'|'; }
pick() {  # name state rc path [env...]
  local name=$1 state=$2 rc=$3 path=$4; shift 4
  rm -f "$E"/pick.*.args
  run "$name" 2500 "$state" OMASCAYL_TOOLS="$E/tools" OMASCAYL_PICTURES="$E/Pictures" FAKE_PICK_RC="$rc" FAKE_PICK="$path" "$@"
}

pick pick-image '{"choose":"image"}' 0 "$E/rose.png"
check "picked image opens" ".image == \"$E/rose.png\" and .batchMode == false" pick-image
[[ $(pick_args) == "image|Select an Image|$E/Pictures" ]] && check "image picker args" true pick-image || check "image picker args ($(pick_args))" false pick-image

pick pick-batch '{"choose":"batch"}' 0 "$E/batch"
check "picked folder starts batch mode" ".batchMode == true and .folder == \"$E/batch\"" pick-batch
[[ $(pick_args) == "folder|Select a Folder|$E/Pictures" ]] && check "batch picker args" true pick-batch || check "batch picker args ($(pick_args))" false pick-batch

pick pick-output "{\"image\":\"$E/rose.png\",\"choose\":\"output\"}" 0 "$E/out"
check "picked output folder" ".output == \"$E/out\"" pick-output
[[ $(pick_args) == "folder|Set Output Folder|$E" ]] && check "output picker starts at current output" true pick-output || check "output picker args ($(pick_args))" false pick-output

pick pick-models '{"choose":"models"}' 0 "$E/models"
check "picked models folder imports models" '[.models[].value] | index("my-model-2x") != null' pick-models

pick pick-cancel "{\"image\":\"$E/rose.png\",\"choose\":\"output\"}" 1 ""
check "cancel changes nothing, no error" ".output == \"$E\" and .error == null" pick-cancel

pick pick-fail '{"choose":"image"}' 2 "" FAKE_PICK_ERR="omascayl-pick: no file picker available"
check "picker failure is reported" '.error.title == "Could not open the file picker" and (.error.description | test("no file picker available"))' pick-fail

pick pick-busy '{"progress":{"percent":10},"choose":"image"}' 0 "$E/rose.png"
[[ -z $(pick_args) ]] && check "no image picker during an upscayl" true pick-busy || check "no image picker during an upscayl" false pick-busy
pick pick-busy-models '{"progress":{"percent":10},"choose":"models"}' 0 "$E/models"
[[ -n $(pick_args) ]] && check "models picker still works during an upscayl" true pick-busy-models || check "models picker during an upscayl" false pick-busy-models

# Dependency prompt and setup, with fake helpers: omascayl-deps answers from
# $E/deps.txt, and a fake `omarchy` (found through OMARCHY_PATH) records the
# launch and plays the setup by changing the answers and touching the marker.
mkdir -p "$E/deptools" "$E/omarchy/bin"
cat > "$E/deptools/omascayl-deps" <<EOF
#!/usr/bin/env bash
cat "$E/deps.txt"
grep -q "^missing.*required" "$E/deps.txt" && exit 1 || exit 0
EOF
cat > "$E/deptools/omascayl-backend" <<EOF
#!/usr/bin/env bash
printf '/usr/bin/upscayl-ncnn\n/usr/share/upscayl/models\n%s/Pictures\n' "\$HOME"
! grep -q "^missing	backend" "$E/deps.txt"
EOF
printf '#!/bin/sh\ntrue\n' > "$E/deptools/omascayl-setup"
cat > "$E/omarchy/bin/omarchy" <<EOF
#!/usr/bin/env bash
echo "\$*" > "$E/omarchy.args"
sleep 1
sed -i 's/^missing/ok/' "$E/deps.txt"
date +%s > "\$OMASCAYL_STATE_DIR/setup-finished"
EOF
chmod +x "$E/deptools/"* "$E/omarchy/bin/omarchy"
deps_ok=$'ok\tbackend\trequired\tUpscayl engine and models\t-\tx\nok\tvulkan\trequired\tVulkan GPU driver\t-\tx'
deps_req=$'missing\tbackend\trequired\tUpscayl engine and models\tupscayl-bin\tx\nok\tvulkan\trequired\tVulkan GPU driver\t-\tx'
deps_rec=$'ok\tbackend\trequired\tUpscayl engine and models\t-\tx\nmissing\tclipboard\trecommended\tClipboard\twl-clipboard\tx'
drun() {  # name delay state deps-text [env...]
  local name=$1 delay=$2 state=$3; printf '%s\n' "$4" > "$E/deps.txt"; shift 4
  run "$name" "$delay" "$state" OMASCAYL_TOOLS="$E/deptools" OMARCHY_PATH="$E/omarchy" "$@"
}

drun deps-none 2500 '{}' "$deps_ok"
check "nothing missing: no prompt" '.depsPromptOpen == false and .missingDeps == []' deps-none

drun deps-required 2500 '{}' "$deps_req"
check "required missing: prompt on first open" '.depsPromptOpen == true and .missingDeps == ["backend"]' deps-required

drun deps-recommended 2500 '{}' "$deps_rec"
check "recommended missing: prompt on first open" '.depsPromptOpen == true and .missingDeps == ["clipboard"]' deps-recommended

OMASCAYL_TEST_SETTINGS='{"notifications": false, "depsPromptDeclined": true}' drun deps-declined 2500 '{}' "$deps_rec"
check "a declined recommended prompt stays declined" '.depsPromptOpen == false and .missingDeps == ["clipboard"]' deps-declined

OMASCAYL_TEST_SETTINGS='{"notifications": false, "depsPromptDeclined": true}' drun deps-declined-required 2500 '{}' "$deps_req"
check "but anything required is still offered" '.depsPromptOpen == true' deps-declined-required

rm -f "$E/omarchy.args"
drun deps-setup 6000 '{"openSetup":true}' "$deps_req"
[[ $(cat "$E/omarchy.args" 2>/dev/null) == "launch floating terminal with presentation $E/deptools/omascayl-setup" ]] \
  && check "setup runs in Omarchy's presented terminal" true deps-setup || check "setup runs in Omarchy's presented terminal ($(cat "$E/omarchy.args" 2>/dev/null))" false deps-setup
check "after setup: checked again, nothing missing, prompt closed" '.missingDeps == [] and .depsPromptOpen == false and .setupRunning == false' deps-setup
check "and says so" '.toast | test("Everything Omascayl needs is installed")' deps-setup

drun deps-upscayl 3000 "{\"image\":\"$E/rose.png\",\"noDepsPrompt\":true,\"run\":true}" "$deps_req" OMASCAYL_BIN=/nonexistent/upscayl-bin
check "Upscayl without a backend offers setup instead of failing" '.depsPromptOpen == true and .error == null and .running == false' deps-upscayl

echo "passed $pass, failed $fail"
[[ $fail == 0 ]]
