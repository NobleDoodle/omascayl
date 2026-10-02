#!/usr/bin/bash
# Install Omascayl for the current user (no root needed):
#
#   ./install.sh              standalone app: copy to ~/.local/share/omascayl/app
#   ./install.sh --plugin     omarchy-shell plugin, installed with `omarchy plugin
#                             add` from this checkout and enabled
#   ./install.sh --uninstall  remove either (settings in ~/.local/state/omascayl
#                             are kept)
#
# Both add the omascayl command, an app launcher entry and an icon. In plugin
# mode they open the plugin's window; there is no bar widget.
set -euo pipefail
# Commands come from the system's own folders only, never the inherited PATH.
PATH=/usr/bin:/usr/share/omarchy/bin
export PATH

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
app_id=io.github.nobledoodle.omascayl
data=${XDG_DATA_HOME:-$HOME/.local/share}
standalone_dest="$data/omascayl/app"
plugin_dest="$HOME/.config/omarchy/plugins/$app_id"
bin_dir="$HOME/.local/bin"
desktop="$data/applications/$app_id.desktop"
icon="$data/icons/hicolor/scalable/apps/$app_id.svg"
mode=${1:-standalone}

refresh() {
  command -v update-desktop-database >/dev/null && update-desktop-database -q "$data/applications" || true
  command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -t "$data/icons/hicolor" 2>/dev/null || true
}

# Command, launcher entry and icon, all pointing at the installed copy in $1.
link_launcher() {
  local app_root=$1
  mkdir -p -- "$bin_dir" "$(dirname "$desktop")" "$(dirname "$icon")"
  ln -sfn -- "$app_root/bin/omascayl" "$bin_dir/omascayl"
  # Written to a random temporary and renamed over the target, so a symlink
  # already sitting there is replaced rather than written through.
  local tmp
  tmp=$(mktemp -p "$(dirname -- "$desktop")" ".$app_id.XXXXXXXX")
  sed "s|^Exec=omascayl |Exec=$bin_dir/omascayl |" "$app_root/share/$app_id.desktop" > "$tmp"
  chmod 644 -- "$tmp" && mv -fT -- "$tmp" "$desktop"
  tmp=$(mktemp -p "$(dirname -- "$icon")" ".$app_id.XXXXXXXX")
  cat -- "$app_root/share/omascayl.svg" > "$tmp"
  chmod 644 -- "$tmp" && mv -fT -- "$tmp" "$icon"
  refresh
}

case "$mode" in
  --uninstall)
    if [[ -d $plugin_dest ]]; then
      omarchy plugin remove "$app_id" --yes
    fi
    rm -f -- "$bin_dir/omascayl" "$desktop" "$icon"
    rm -rf -- "$data/omascayl"
    refresh
    echo "Omascayl removed. Settings stay in ${XDG_STATE_HOME:-$HOME/.local/state}/omascayl."
    exit 0 ;;

  --plugin)
    command -v omarchy >/dev/null || { echo "install.sh: the omarchy command is required for --plugin" >&2; exit 1; }
    if [[ -d $plugin_dest ]]; then
      omarchy plugin update "$app_id" --yes
    else
      # Clone this checkout (so its current branch is what gets installed),
      # then point origin at the main repository, which outlives worktrees.
      # Note: `omarchy plugin update` fetches origin's HEAD, i.e. whatever
      # branch the main repository has checked out, so it only picks up new
      # commits once they are on that branch.
      omarchy plugin add "$here" --enable --yes
      common=$(git -C "$here" rev-parse --path-format=absolute --git-common-dir)
      repo=$(dirname -- "$common")
      [[ $common == */.git ]] || repo=$here
      git -C "$plugin_dest" remote set-url origin "$repo"
    fi
    # A standalone install from an earlier ./install.sh is replaced: its copy,
    # launcher entry and command make way for the plugin's own.
    if [[ -d $standalone_dest ]]; then
      rm -rf -- "$standalone_dest"
      rm -f -- "$desktop" "$bin_dir/omascayl"
    fi
    # The plugin installs its launcher entry, icon and command itself when the
    # shell loads it; run that now too, so they exist when this script ends.
    "$plugin_dest/bin/omascayl-integrate" install "$plugin_dest"
    echo "Omascayl $(cat "$plugin_dest/VERSION") installed as an omarchy-shell plugin. Open it from the app launcher or run: omascayl [image]"
    exit 0 ;;

  standalone) ;;

  *)
    sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
    exit 1 ;;
esac

missing=()
command -v qs >/dev/null || command -v quickshell >/dev/null || missing+=("quickshell")
"$here/bin/omascayl-backend" >/dev/null || missing+=("upscayl-bin (AUR) or an upscayl-ncnn release")
command -v wl-paste >/dev/null || missing+=("wl-clipboard (for Ctrl+V)")
if ((${#missing[@]})); then
  printf 'Note: not found: %s\n' "${missing[@]}" >&2
fi

rm -rf -- "$standalone_dest"
mkdir -p -- "$standalone_dest"
cp -r -- "$here/bin" "$here/src" "$here/share" "$here/VERSION" "$here/LICENSE" "$standalone_dest/"
link_launcher "$standalone_dest"

echo "Omascayl $(cat "$here/VERSION") installed. Start it from the app launcher or run: omascayl [image]"
