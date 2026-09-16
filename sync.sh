#!/bin/bash
# sail-cachy-setup -- capture: this machine's live files -> repo.
# Pulls the files this repo manages back into the mirror structure, and
# regenerates the two single-file installers from install-src templates.
# Never commits or pushes; stage and commit yourself after reviewing.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN\033[0m %s\n' "$*"; }

# --- 1. live files into the mirror structure -------------------------------

say "capturing wallpaper picker files"
install -m 644 "$CONFIG_HOME/quickshell/picker/shell.qml"     "$REPO_DIR/files/quickshell-picker/shell.qml"
install -m 755 "$CONFIG_HOME/quickshell/picker/build-rows.sh" "$REPO_DIR/files/quickshell-picker/build-rows.sh"
for f in qs-picker qs-folder-pick qs-wallpaper-pick; do
    install -m 755 "$CONFIG_HOME/quickshell/picker/bin/$f" "$REPO_DIR/files/quickshell-picker/bin/$f"
done

say "capturing web app tooling"
for f in qs-webapp-install qs-webapp-launch qs-webapp-focus qs-webapp-remove qs-webapp-open-tui; do
    install -m 755 "$CONFIG_HOME/webapps/bin/$f" "$REPO_DIR/files/webapps/bin/$f"
done

say "capturing chromium-flags.conf"
install -m 644 "$CONFIG_HOME/chromium-flags.conf" "$REPO_DIR/config/chromium-flags.conf"

say "capturing bindings.lua"
find "$CONFIG_HOME/hypr/customconfig" -maxdepth 1 -name 'bindings.lua' -not -name '*.bak' -exec \
    cp {} "$REPO_DIR/hypr/customconfig/bindings.lua" \;

# --- 2. regenerate the single-file installers ------------------------------

b64() { base64 -w0 "$1"; }

fill_installer() {
    local tmpl="$1" out="$2"
    say "regenerating $out"
    : > "$out"
    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            '@@SHELL_QML@@')        b64 "$REPO_DIR/files/quickshell-picker/shell.qml" ;;
            '@@BUILD_ROWS@@')       b64 "$REPO_DIR/files/quickshell-picker/build-rows.sh" ;;
            '@@QS_PICKER@@')        b64 "$REPO_DIR/files/quickshell-picker/bin/qs-picker" ;;
            '@@QS_FOLDER_PICK@@')   b64 "$REPO_DIR/files/quickshell-picker/bin/qs-folder-pick" ;;
            '@@QS_WALLPAPER_PICK@@') b64 "$REPO_DIR/files/quickshell-picker/bin/qs-wallpaper-pick" ;;
            '@@QS_WEBAPP_INSTALL@@') b64 "$REPO_DIR/files/webapps/bin/qs-webapp-install" ;;
            '@@QS_WEBAPP_LAUNCH@@') b64 "$REPO_DIR/files/webapps/bin/qs-webapp-launch" ;;
            '@@QS_WEBAPP_FOCUS@@')  b64 "$REPO_DIR/files/webapps/bin/qs-webapp-focus" ;;
            '@@QS_WEBAPP_REMOVE@@') b64 "$REPO_DIR/files/webapps/bin/qs-webapp-remove" ;;
            '@@QS_WEBAPP_OPEN_TUI@@') b64 "$REPO_DIR/files/webapps/bin/qs-webapp-open-tui" ;;
            '@@CHROMIUM_FLAGS@@')   b64 "$REPO_DIR/config/chromium-flags.conf" ;;
            *)                      printf '%s' "$line" ;;
        esac >> "$out"
        printf '\n' >> "$out"
    done < "$tmpl"
    if [[ "$(tail -c1 "$tmpl")" != $'\n' ]]; then
        truncate -s -1 "$out"
    fi
    chmod +x "$out"
}

# Always regenerate into this repo's dist/ (single-file handouts live here too).
mkdir -p "$REPO_DIR/dist"
fill_installer "$REPO_DIR/install-src/qs-picker-install.sh.tmpl"  "$REPO_DIR/dist/qs-picker-install.sh"
fill_installer "$REPO_DIR/install-src/qs-webapp-install.sh.tmpl"  "$REPO_DIR/dist/qs-webapp-install.sh"

# Mirror into the standalone repos if present (keeps them fresh; optional).
if [[ -d "$HOME/qs-wallpaper-picker" ]]; then
    cp "$REPO_DIR/dist/qs-picker-install.sh" "$HOME/qs-wallpaper-picker/qs-picker-install.sh"
else
    warn "skipping ~/qs-wallpaper-picker mirror (repo not present)"
fi

if [[ -d "$HOME/qs-webapp-creator" ]]; then
    cp "$REPO_DIR/dist/qs-webapp-install.sh" "$HOME/qs-webapp-creator/qs-webapp-install.sh"
else
    warn "skipping ~/qs-webapp-creator mirror (repo not present)"
fi

# --- 3. hand off -----------------------------------------------------------

say "done."
cat <<EOF

Review the changes, then stage and commit from this repo:
    git add -A && git commit -m "sync from this machine" && git push

To apply on another machine:
    git pull && ./setup.sh
EOF