#!/bin/bash
# sail-cachy-setup -- deploy: machine -> working state.
# Idempotent. Safe to re-run after a `git pull`; never destructive beyond a
# timestamped backup of files it replaces.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

PICKER_DIR="$CONFIG_HOME/quickshell/picker"
WEBAPPS_BIN="$CONFIG_HOME/webapps/bin"
BIN_LINK_DIR="$HOME/.local/bin"

DEPS=(quickshell libvips imagemagick ffmpegthumbnailer jq file chromium curl fzf)
CMDS=(quickshell vipsthumbnail magick ffmpegthumbnailer jq file chromium curl fzf)

usage() {
    cat <<EOF
usage: setup.sh [options]

  --check           verify environment and dependencies, then exit
  --install-deps    install packages via pacman (sudo), then continue
  --no-auto         do not install systemd automation units
  --no-link-bin     do not symlink qs-* commands into ~/.local/bin
  --no-reload       do not run hyprctl reload at the end
  --uninstall       remove files this repo manages (bindings untouched, see notes)
EOF
}

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mERR\033[0m %s\n' "$*" >&2; exit 1; }

CHK=0; INSTALL_DEPS=0; LINK_BIN=1; RELOAD=1; UNINSTALL=0; AUTO=1
for a in "$@"; do
    case "$a" in
        --check) CHK=1 ;;
        --install-deps) INSTALL_DEPS=1 ;;
        --no-auto) AUTO=0 ;;
        --no-link-bin) LINK_BIN=0 ;;
        --no-reload) RELOAD=0 ;;
        --uninstall) UNINSTALL=1 ;;
        *) die "unknown flag: $a" ;;
    esac
done

gate() {
    command -v noctalia >/dev/null 2>&1 || die "noctalia not found: this setup targets Noctalia + Hyprland"
    command -v hyprctl  >/dev/null 2>&1 || die "hyprctl not found: this setup targets Noctalia + Hyprland"
}

check_deps() {
    local missing=()
    for c in "${CMDS[@]}"; do
        command -v "$c" >/dev/null 2>&1 || missing+=("$c")
    done
    if ((${#missing[@]} > 0)); then
        warn "missing commands: ${missing[*]} (run: sudo pacman -S ${DEPS[*]})"
        return 1
    fi
    return 0
}

install_deps() {
    say "installing packages (additive; nothing removed)"
    sudo pacman -S --needed "${DEPS[@]}"
}

deploy_picker() {
    local src="$REPO_DIR/files/quickshell-picker"
    say "deploying wallpaper picker -> $PICKER_DIR"
    mkdir -p "$PICKER_DIR/bin"
    install -m 644 "$src/shell.qml"     "$PICKER_DIR/shell.qml"
    install -m 755 "$src/build-rows.sh" "$PICKER_DIR/build-rows.sh"
    for f in qs-picker qs-folder-pick qs-wallpaper-pick; do
        install -m 755 "$src/bin/$f" "$PICKER_DIR/bin/$f"
    done
}

deploy_webapps() {
    local src="$REPO_DIR/files/webapps/bin"
    say "deploying web app tooling -> $WEBAPPS_BIN"
    mkdir -p "$WEBAPPS_BIN"
    for f in qs-webapp-install qs-webapp-launch qs-webapp-focus qs-webapp-remove qs-webapp-open-tui; do
        install -m 755 "$src/$f" "$WEBAPPS_BIN/$f"
    done
}

deploy_flags() {
    say "deploying chromium-flags.conf"
    install -m 644 "$REPO_DIR/config/chromium-flags.conf" "$CONFIG_HOME/chromium-flags.conf"
}

deploy_webapp_launcher() {
    local dst="${XDG_DATA_HOME:-$HOME/.local/share}/applications/Install Web App.desktop"
    say "deploying launcher entry -> $dst"
    mkdir -p "${dst%/*}"
    install -m 644 /dev/stdin "$dst" <<EOF
[Desktop Entry]
Version=1.0
Name=Install Web App
Comment=Add a web app launcher (opens the setup TUI)
Exec=$HOME/.config/webapps/bin/qs-webapp-open-tui
Terminal=false
Type=Application
Icon=applications-internet
StartupNotify=true
EOF
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "${dst%/*}" || true
}

deploy_bindings() {
    local dst="$CONFIG_HOME/hypr/customconfig/bindings.lua"
    say "deploying bindings.lua"
    mkdir -p "${dst%/*}"
    if [[ ! -f "$dst" ]]; then
        cp "$REPO_DIR/hypr/customconfig/bindings.lua" "$dst"
    elif ! diff -q "$REPO_DIR/hypr/customconfig/bindings.lua" "$dst" >/dev/null 2>&1; then
        local bak="$dst.$(date +%Y%m%d.%H%M%S.%N).bak"
        cp -p "$dst" "$bak"
        say "previous bindings.lua backed up to $bak"
        cp "$REPO_DIR/hypr/customconfig/bindings.lua" "$dst"
    fi
}

deploy_fish_line() {
    local fish="$CONFIG_HOME/fish/config.fish"
    local line; line="$(cat "$REPO_DIR/config/fish.path.line")"
    say "ensuring '$line' in $fish"
    mkdir -p "${fish%/*}"
    [[ -f "$fish" ]] || touch "$fish"
    if ! grep -Fxq "$line" "$fish"; then
        printf '\n%s\n' "$line" >> "$fish"
    fi
}

link_bin() {
    local dir="$BIN_LINK_DIR"
    say "symlinking qs-* commands -> $dir"
    mkdir -p "$dir"
    ln -sf "$PICKER_DIR/bin/qs-picker"          "$dir/qs-picker"
    ln -sf "$PICKER_DIR/bin/qs-folder-pick"     "$dir/qs-folder-pick"
    ln -sf "$PICKER_DIR/bin/qs-wallpaper-pick"  "$dir/qs-wallpaper-pick"
    for f in qs-webapp-install qs-webapp-launch qs-webapp-focus qs-webapp-remove qs-webapp-open-tui; do
        ln -sf "$WEBAPPS_BIN/$f" "$dir/$f"
    done
    ln -sf "$REPO_DIR/qs-loop.sh" "$dir/qs-loop"
}

install_auto_units() {
    local unit_dir="$CONFIG_HOME/systemd/user"
    say "installing systemd automation units -> $unit_dir"
    mkdir -p "$unit_dir"
    for f in qs-loop.timer qs-loop.service qs-apply.service qs-save.service; do
        sed "s|__REPO__|$REPO_DIR|g" "$REPO_DIR/systemd/$f.in" > "$unit_dir/$f"
    done
    systemctl --user daemon-reload
    systemctl --user enable --now qs-loop.timer qs-apply.service qs-save.service
}

remove_auto_units() {
    local unit_dir="$CONFIG_HOME/systemd/user"
    systemctl --user disable --now qs-loop.timer qs-apply.service qs-save.service 2>/dev/null || true
    rm -f "$unit_dir"/qs-loop.timer "$unit_dir"/qs-loop.service \
          "$unit_dir"/qs-apply.service "$unit_dir"/qs-save.service
    systemctl --user daemon-reload 2>/dev/null || true
}

uninstall() {
    warn "removing picker, web app tooling, flags, launcher entry, automation, and qs-* symlinks"
    remove_auto_units
    rm -rf "$PICKER_DIR" "$WEBAPPS_BIN"
    rm -f "$CONFIG_HOME/chromium-flags.conf"
    rm -f "${XDG_DATA_HOME:-$HOME/.local/share}/applications/Install Web App.desktop"
    rm -f "$BIN_LINK_DIR"/qs-picker "$BIN_LINK_DIR"/qs-folder-pick "$BIN_LINK_DIR"/qs-wallpaper-pick \
          "$BIN_LINK_DIR"/qs-webapp-install "$BIN_LINK_DIR"/qs-webapp-launch "$BIN_LINK_DIR"/qs-webapp-focus \
          "$BIN_LINK_DIR"/qs-webapp-remove "$BIN_LINK_DIR"/qs-webapp-open-tui "$BIN_LINK_DIR"/qs-loop
    rm -rf "$STATE_HOME/qs-loop"
    say "bindings.lua untouched. Previous versions are kept as bindings.lua.*.bak"
    say "to restore one: mv $CONFIG_HOME/hypr/customconfig/bindings.lua.<stamp>.bak $CONFIG_HOME/hypr/customconfig/bindings.lua"
}

gate

if ((UNINSTALL)); then uninstall; exit 0; fi

if ((CHK)); then
    gate
    check_deps
    say "environment OK"
    exit 0
fi

if ((INSTALL_DEPS)); then install_deps; fi
check_deps || die "dependencies missing (rerun with --install-deps)"

deploy_picker
deploy_webapps
deploy_flags
deploy_webapp_launcher
deploy_bindings
deploy_fish_line
((LINK_BIN)) && link_bin
((AUTO)) && install_auto_units

if ((RELOAD)); then
    say "reloading Hyprland"
    hyprctl reload || warn "hyprctl reload failed (launching first time?)"
fi

say "done."
cat <<EOF

What you have now:
  SUPER+CTRL+SPACE      random wallpaper from current folder
  SUPER+SHIFT+CTRL+SPACE choose folder, random wallpaper
  qs-webapp-install      add a web app (launched borderless via chromium --app)
  qs-loop                one-swoop sync: save (push my changes) + apply (pull + deploy)

Automation $( ((AUTO)) && printf 'installed: qs-loop.timer (every 10 min), qs-apply (login), qs-save (shutdown)' || printf 'skipped (--no-auto)' ).
EOF