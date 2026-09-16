#!/bin/bash
# qs-webapp-install.sh — install the borderless web-app creator for Noctalia/Hyprland.
#
#   --check        verify dependencies (no changes)
#   --install-deps install missing dependencies via sudo pacman
#   --link-bin     symlink the qs-webapp-* commands into ~/.local/bin
#   --uninstall    remove what this installer created
#   (no args)      install the web-app tooling
set -euo pipefail

WEBAPPS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/webapps"
BIN_DIR="$WEBAPPS_DIR/bin"
FLAGS_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/chromium-flags.conf"
DESKTOP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
LAUNCHER_ENTRY="$DESKTOP_DIR/Install Web App.desktop"

usage() {
cat <<'USAGE'
qs-webapp-install — borderless web-app creator for Noctalia/Hyprland

Installs into ~/.config/webapps/bin/ plus a chromium-flags.conf and a
"Install Web App" entry in the launcher. The setup TUI prompts for a name and
URL, auto-fetches the site icon, and writes a .desktop launcher that opens the
site as a borderless Chromium app window (--app= strips tabs/toolbar/omnibox).

Options:
  --check         list missing dependencies and exit (no changes)
  --install-deps  run: sudo pacman -S --needed chromium curl jq
  --link-bin      symlink qs-webapp-* into ~/.local/bin so you can type them
                  in a terminal (also: fish_add_path ~/.local/bin)
  --uninstall     remove the webapp tooling (bin dir, flags, launcher entry)
                  installed web apps themselves are left in place
USAGE
}

HARD_DEPS=(chromium curl file jq)
SOFT_DEPS=(fzf)

check_deps() {
  local missing=() soft_missing=() cmd
  for cmd in "${HARD_DEPS[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  for cmd in "${SOFT_DEPS[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || soft_missing+=("$cmd")
  done
  command -v noctalia >/dev/null 2>&1 || missing+=("noctalia")
  command -v hyprctl >/dev/null 2>&1 || missing+=("hyprctl")

  if ((${#missing[@]})) || ((${#soft_missing[@]})); then
    if ((${#missing[@]})); then
      printf 'Missing (required): %s\n' "${missing[*]}"
      echo "Install with:  sudo pacman -S --needed chromium curl jq"
    fi
    if ((${#soft_missing[@]})); then
      printf 'Missing (optional): %s\n' "${soft_missing[*]}"
      echo "  fzf: prettier picker in qs-webapp-remove (falls back to numbered prompt)"
    fi
    ((${#missing[@]})) && exit 1
  else
    echo "All dependencies present."
  fi
}

install_deps() {
  sudo -v
  sudo pacman -S --needed --noconfirm chromium curl jq
}

link_bin() {
  mkdir -p "$HOME/.local/bin"
  local s
  for s in qs-webapp-install qs-webapp-launch qs-webapp-focus qs-webapp-remove qs-webapp-open-tui; do
    ln -sf "$BIN_DIR/$s" "$HOME/.local/bin/$s"
  done
  echo "Linked qs-webapp-* into ~/.local/bin"
  echo 'Add it to your shell PATH, e.g. in fish:  fish_add_path ~/.local/bin'
}

install() {
  mkdir -p "$BIN_DIR"

  emit_install > "$BIN_DIR/qs-webapp-install"
  emit_launch > "$BIN_DIR/qs-webapp-launch"
  emit_focus  > "$BIN_DIR/qs-webapp-focus"
  emit_remove > "$BIN_DIR/qs-webapp-remove"
  emit_open   > "$BIN_DIR/qs-webapp-open-tui"
  emit_flags  > "$FLAGS_FILE"

  chmod +x "$BIN_DIR"/*

  mkdir -p "$DESKTOP_DIR"
  cat > "$LAUNCHER_ENTRY" <<EOF
[Desktop Entry]
Version=1.0
Name=Install Web App
Comment=Add a web app launcher (opens the setup TUI)
Exec=$BIN_DIR/qs-webapp-open-tui
Terminal=false
Type=Application
Icon=applications-internet
StartupNotify=true
EOF
  chmod +x "$LAUNCHER_ENTRY"
  update-desktop-database "$DESKTOP_DIR" &>/dev/null || true

  echo "Installed web-app tooling."
  echo "  scripts     -> $BIN_DIR"
  echo "  flags       -> $FLAGS_FILE"
  echo "  launcher    -> $LAUNCHER_ENTRY"
  echo
  echo "Open the setup TUI from the launcher (SUPER + SPACE -> \"Install Web App\"),"
  echo "or run:  $BIN_DIR/qs-webapp-install"
  echo
  echo "For a web-app hotkey, add to customconfig/bindings.lua (dynamic path):"
  echo '  local wab = os.getenv("HOME") .. "/.config/webapps/bin"'
  echo "  hl.bind(mainMod .. \" + SHIFT + Y\", hl.dsp.exec_cmd(wab .. \"/qs-webapp-focus 'YouTube' 'https://youtube.com/'\"))"
  echo
  echo "Hint: run with --link-bin to also put qs-webapp-* on your PATH."
}

uninstall() {
  if [[ -d $WEBAPPS_DIR ]]; then rm -rf "$WEBAPPS_DIR" && echo "Removed: $WEBAPPS_DIR"; fi
  if [[ -f $FLAGS_FILE ]]; then rm -f "$FLAGS_FILE" && echo "Removed: $FLAGS_FILE"; fi
  if [[ -f $LAUNCHER_ENTRY ]]; then rm -f "$LAUNCHER_ENTRY" && echo "Removed: $LAUNCHER_ENTRY"; fi
  local s
  for s in qs-webapp-install qs-webapp-launch qs-webapp-focus qs-webapp-remove qs-webapp-open-tui; do
    rm -f "$HOME/.local/bin/$s"
  done
  update-desktop-database "$DESKTOP_DIR" &>/dev/null || true
  echo "Installed web apps (~/.local/share/applications/*.desktop) were left in place."
}

# ---- embedded assets (base64) ----

emit_install() {
base64 -d <<'EOAINSTALL'
IyEvYmluL2Jhc2gKCiMgQ3JlYXRlIGEgZGVza3RvcCBsYXVuY2hlciBmb3IgYSB3ZWIgYXBwOiBwcm9tcHRzIGZvciBhIG5hbWUgYW5kIFVSTCwgcHVsbHMKIyB0aGUgc2l0ZSdzIGljb24gYXV0b21hdGljYWxseSAoYXBwbGUtdG91Y2gtaWNvbiwgL2FwcGxlLXRvdWNoLWljb24ucG5nLCB0aGVuCiMgR29vZ2xlJ3MgZmF2aWNvbiBzZXJ2aWNlKSwgYW5kIHdyaXRlcyBhIC5kZXNrdG9wIGVudHJ5IHNvIHRoZSBhcHAgc2hvd3MgdXAgaW4KIyB0aGUgTm9jdGFsaWEgbGF1bmNoZXIuIENocm9taXVtJ3MgLS1hcHA9IHdpbmRvdyBzdHJpcHMgdGhlIGJyb3dzZXIgY2hyb21lIGZvcgojIGEgYm9yZGVybGVzcyBhcHAgbG9vay4KCnNldCAtZQoKSUNPTl9ESVI9IiRIT01FLy5sb2NhbC9zaGFyZS9pY29ucy9oaWNvbG9yLzI1NngyNTYvYXBwcyIKREVTS1RPUF9ESVI9IiRIT01FLy5sb2NhbC9zaGFyZS9hcHBsaWNhdGlvbnMiCkxBVU5DSEVSX1NDUklQVD0iJChjZCAiJChkaXJuYW1lICIkMCIpIiAmJiBwd2QpL3FzLXdlYmFwcC1sYXVuY2giCgpzYWZlX2ljb25fbmFtZSgpIHsKICBwcmludGYgJyVzXG4nICIkMSIgXAogICAgfCB0ciAnWzp1cHBlcjpdJyAnWzpsb3dlcjpdJyBcCiAgICB8IHNlZCAncy9bXls6YWxudW06XV1cKy8tL2c7IHMvXi0vLzsgcy8tJC8vJwp9CgpyZXF1aXJlX3BsYWluX25hbWUoKSB7CiAgaWYgW1sgJDEgPT0gKi8qIF1dOyB0aGVuCiAgICBlY2hvICJBcHAgbmFtZSBjYW5ub3QgY29udGFpbiAnLyc6ICQxIiA+JjIKICAgIGV4aXQgMQogIGZpCiAgaWYgW1sgLXogJDEgXV07IHRoZW4KICAgIGVjaG8gIkFwcCBuYW1lIGNhbm5vdCBiZSBlbXB0eS4iID4mMgogICAgZXhpdCAxCiAgZmkKfQoKIyBDaHJvbWl1bSAtLWFwcD0gdHJlYXRzIGphdmFzY3JpcHQ6LCBmaWxlOiwgYW5kIGRhdGE6IGFzIGEgZG9jdW1lbnQgdG8gcnVuLgojIFByZWZpeCBzY2hlbWVsZXNzIGlucHV0IHdpdGggaHR0cHMgYW5kIHJlZnVzZSBhbnl0aGluZyB0aGF0IGlzIG5vdCBodHRwKHMpLgpub3JtYWxpemVfd2ViYXBwX3VybCgpIHsKICBsb2NhbCB1cmw9JDEKICBpZiBbWyAhICR1cmwgPX4gXlthLXpBLVpdW2EtekEtWjAtOSsuLV0qOiBdXTsgdGhlbgogICAgdXJsPSJodHRwczovLyR1cmwiCiAgZmkKICBwcmludGYgJyVzJyAiJHVybCIKfQoKcmVxdWlyZV9odHRwX3VybCgpIHsKICBsb2NhbCB1cmw9JDEKICBpZiBbWyAkdXJsID1+IFtbOnNwYWNlOl1dIF1dOyB0aGVuCiAgICBlY2hvICJFcnJvcjogd2ViIGFwcCBVUkwgbXVzdCBub3QgY29udGFpbiB3aGl0ZXNwYWNlLiIgPiYyCiAgICBleGl0IDEKICBmaQogIGlmIFtbICEgJHt1cmwsLH0gPX4gXmh0dHBzPzovLyBdXTsgdGhlbgogICAgZWNobyAiRXJyb3I6IHdlYiBhcHAgVVJMIG11c3QgYmUgaHR0cCBvciBodHRwcy4iID4mMgogICAgZXhpdCAxCiAgZmkKfQoKZG93bmxvYWRfaWNvbigpIHsKICBjdXJsIC1mc1NMIC0tbWF4LXRpbWUgMTAgLW8gIiQyIiAiJDEiIDI+L2Rldi9udWxsICYmCiAgICBbWyAtcyAkMiAmJiAkKGZpbGUgLWIgLS1taW1lLXR5cGUgIiQyIikgPT0gaW1hZ2UvKiBdXQp9CgpmZXRjaF9zaXRlX2ljb24oKSB7CiAgbG9jYWwgc2l0ZV91cmw9IiQxIiBkZXN0PSIkMiIKICBsb2NhbCBvcmlnaW4gcGFnZSBpY29uX3VybAogIG9yaWdpbj0kKHNlZCAtRSAnc3xeKGh0dHBzPzovL1teL10rKS4qfFwxfCcgPDw8IiRzaXRlX3VybCIpCgogICMgUHJlZmVyIHRoZSBzaXRlJ3Mgb3duIGhpZ2gtcmVzIGljb24gKGFwcGxlLXRvdWNoLWljb24pLCB0aGVuIHRoZSB3ZWxsLWtub3duCiAgIyBwYXRoLCB0aGVuIEdvb2dsZSdzIGZhdmljb24gc2VydmljZSBhcyBhIGxhc3QgcmVzb3J0LgogIHBhZ2U9JChjdXJsIC1mc1NMIC0tbWF4LXRpbWUgNSAiJHNpdGVfdXJsIiAyPi9kZXYvbnVsbCB8IGhlYWQgLWMgMTAwMDAwIHwgdHIgJ1xuJyAnICcpCiAgaWNvbl91cmw9JChncmVwIC1vaUUgIjxsaW5rW14+XSpyZWw9W1wiJ11bXlwiJ10qYXBwbGUtdG91Y2gtaWNvblteXCInXSpbXCInXVtePl0qPiIgPDw8IiRwYWdlIiB8CiAgICBncmVwIC1vaUUgImhyZWY9W1wiJ11bXlwiJ10rIiB8IGhlYWQgLTEgfCBzZWQgLUUgInMvXmhyZWY9W1wiJ10vLyIpCgogIGNhc2UgJGljb25fdXJsIGluCiAgaHR0cDovLyogfCBodHRwczovLyopIDs7CiAgLy8qKSBpY29uX3VybD0iaHR0cHM6JGljb25fdXJsIiA7OwogIC8qKSBpY29uX3VybD0iJG9yaWdpbiRpY29uX3VybCIgOzsKICA/KikgaWNvbl91cmw9IiRvcmlnaW4vJGljb25fdXJsIiA7OwogIGVzYWMKCiAgeyBbWyAtbiAkaWNvbl91cmwgXV0gJiYgZG93bmxvYWRfaWNvbiAiJGljb25fdXJsIiAiJGRlc3QiOyB9IHx8CiAgICBkb3dubG9hZF9pY29uICIkb3JpZ2luL2FwcGxlLXRvdWNoLWljb24ucG5nIiAiJGRlc3QiIHx8CiAgICBkb3dubG9hZF9pY29uICJodHRwczovL3d3dy5nb29nbGUuY29tL3MyL2Zhdmljb25zP2RvbWFpbj0ke3NpdGVfdXJsfSZzej0yNTYiICIkZGVzdCIKfQoKIyBGcmVlZGVza3RvcCBEZXNrdG9wIEVudHJ5ICJzdHJpbmciIGVzY2FwaW5nOiBhIHJhdyBuZXdsaW5lIHdvdWxkIG9wZW4gYSBuZXcKIyBrZXksIGFuZCBldmVyeSBFeGVjIGFyZ3VtZW50IHRoYXQgaXMgbm90IHRoZSBVUkwgaXMgbGl0ZXJhbCB0ZXh0LCBzbyBlc2NhcGUKIyBiYWNrc2xhc2ggZmlyc3QsIHRoZW4gdGFiL0NSL0xGIGFuZCBhIGxlYWRpbmcgc3BhY2UuCmRlc2t0b3Bfc3RyaW5nX2VzY2FwZSgpIHsKICBsb2NhbCB2YWx1ZT0iJDEiCiAgdmFsdWU9JHt2YWx1ZS8vXFwvXFxcXH0KICB2YWx1ZT0ke3ZhbHVlLy8kJ1x0Jy9cXHR9CiAgdmFsdWU9JHt2YWx1ZS8vJCdccicvXFxyfQogIHZhbHVlPSR7dmFsdWUvLyQnXG4nL1xcbn0KICBbWyAkdmFsdWUgPT0gIiAiKiBdXSAmJiB2YWx1ZT0iXFxzJHt2YWx1ZSMgfSIKICBwcmludGYgJyVzJyAiJHZhbHVlIgp9CgojIE9uZSBxdW90ZWQgRXhlYyBhcmd1bWVudCBwZXIgdGhlIGZyZWVkZXNrdG9wIEV4ZWMgc3BlYzogaW5zaWRlIHF1b3RlcwojICIgYCAkIFwgdGFrZSBhIGJhY2tzbGFzaCBhbmQgYSBsaXRlcmFsICUgYmVjb21lcyAlJS4KZGVza3RvcF9leGVjX2FyZygpIHsKICBwcmludGYgJyIlcyInICIkKHByaW50ZiAnJXMnICIkMSIgXAogICAgfCBzZWQgLWUgJ3MvXFwvXFxcXC9nJyAtZSAncy8iL1xcIi9nJyAtZSAncy9gL1xcYC9nJyAtZSAncy9cJC9cXCQvZycgLWUgJ3MvJS8lJS9nJykiCn0KCklOVEVSQUNUSVZFX01PREU9ZmFsc2UKaWYgKCggJCMgPCAzICkpOyB0aGVuCiAgSU5URVJBQ1RJVkVfTU9ERT10cnVlCiAgZWNobyAtZSAiXG5MZXQncyBjcmVhdGUgYSB3ZWIgYXBwIHlvdSBjYW4gc3RhcnQgZnJvbSB0aGUgbGF1bmNoZXIuXG4iCiAgcmVhZCAtcnAgIk5hbWU+ICIgQVBQX05BTUUKICByZXF1aXJlX3BsYWluX25hbWUgIiRBUFBfTkFNRSIKICByZWFkIC1ycCAiVVJMPiAiIEFQUF9VUkwKICBBUFBfVVJMPSQobm9ybWFsaXplX3dlYmFwcF91cmwgIiRBUFBfVVJMIikKICByZXF1aXJlX2h0dHBfdXJsICIkQVBQX1VSTCIKICBJQ09OX1JFRj0iIgplbHNlCiAgQVBQX05BTUU9IiQxIgogIEFQUF9VUkw9JChub3JtYWxpemVfd2ViYXBwX3VybCAiJDIiKQogIHJlcXVpcmVfaHR0cF91cmwgIiRBUFBfVVJMIgogIElDT05fUkVGPSIkMyIKICBFWFRSQV9BUkdTPSIkezQ6LX0iICMgT3B0aW9uYWwgZXh0cmEgY2hyb21pdW0gYXJncywgYXBwZW5kZWQgdG8gRXhlYwpmaQpyZXF1aXJlX3BsYWluX25hbWUgIiRBUFBfTkFNRSIKCm1rZGlyIC1wICIkSUNPTl9ESVIiICIkREVTS1RPUF9ESVIiCklDT05fVkFMVUU9JChzYWZlX2ljb25fbmFtZSAiJEFQUF9OQU1FIikKCmlmIFtbIC16ICRJQ09OX1JFRiBdXTsgdGhlbgogIGlmIGZldGNoX3NpdGVfaWNvbiAiJEFQUF9VUkwiICIkSUNPTl9ESVIvJElDT05fVkFMVUUucG5nIjsgdGhlbgogICAgZ3RrLXVwZGF0ZS1pY29uLWNhY2hlICIkSE9NRS8ubG9jYWwvc2hhcmUvaWNvbnMvaGljb2xvciIgJj4vZGV2L251bGwgfHwgdHJ1ZQogIGVsaWYgW1sgJElOVEVSQUNUSVZFX01PREUgPT0gInRydWUiIF1dOyB0aGVuCiAgICByZWFkIC1ycCAiSWNvbiBVUkwvbmFtZT4gIiBJQ09OX1JFRgogICAgaWYgW1sgLXogJElDT05fUkVGIF1dOyB0aGVuCiAgICAgIGVjaG8gIk5vIGljb24gcHJvdmlkZWQ7IHRoZSBhcHAgd2lsbCB1c2UgdGhlIGZhbGxiYWNrIGljb24uIiA+JjIKICAgIGZpCiAgZWxzZQogICAgZWNobyAiRXJyb3I6IGZhaWxlZCB0byBmZXRjaCBhIHNpdGUgaWNvbjsgcGFzcyBhbiBpY29uIFVSTCBvciBuYW1lIGV4cGxpY2l0bHkuIiA+JjIKICAgIGV4aXQgMQogIGZpCmZpCgppZiBbWyAtbiAkSUNPTl9SRUYgXV07IHRoZW4KICBpZiBbWyAkSUNPTl9SRUYgPX4gXmh0dHBzPzovLyBdXTsgdGhlbgogICAgZG93bmxvYWRfaWNvbiAiJElDT05fUkVGIiAiJElDT05fRElSLyRJQ09OX1ZBTFVFLnBuZyIgXAogICAgICB8fCB7IGVjaG8gIkVycm9yOiBmYWlsZWQgdG8gZG93bmxvYWQgaWNvbi4iID4mMjsgZXhpdCAxOyB9CiAgICBndGstdXBkYXRlLWljb24tY2FjaGUgIiRIT01FLy5sb2NhbC9zaGFyZS9pY29ucy9oaWNvbG9yIiAmPi9kZXYvbnVsbCB8fCB0cnVlCiAgZWxpZiBbWyAtZiAkSUNPTl9SRUYgXV07IHRoZW4KICAgIGV4dD0iJHtJQ09OX1JFRiMjKi59IgogICAgW1sgJGV4dCA9PSAiJElDT05fUkVGIiBdXSAmJiBleHQ9InBuZyIKICAgIGNwICIkSUNPTl9SRUYiICIkSUNPTl9ESVIvJElDT05fVkFMVUUuJGV4dCIKICAgIGd0ay11cGRhdGUtaWNvbi1jYWNoZSAiJEhPTUUvLmxvY2FsL3NoYXJlL2ljb25zL2hpY29sb3IiICY+L2Rldi9udWxsIHx8IHRydWUKICBlbHNlCiAgICBJQ09OX1ZBTFVFPSIkSUNPTl9SRUYiICMgRXhpc3RpbmcgaWNvbiBuYW1lIGluIHRoZSB0aGVtZQogIGZpCmZpCgpERVNLVE9QX0ZJTEU9IiRERVNLVE9QX0RJUi8kQVBQX05BTUUuZGVza3RvcCIKZXhlY19saW5lPSIkTEFVTkNIRVJfU0NSSVBUICQoZGVza3RvcF9leGVjX2FyZyAiJEFQUF9VUkwiKSR7RVhUUkFfQVJHUzorICRFWFRSQV9BUkdTfSIKCnsKICBwcmludGYgJ1tEZXNrdG9wIEVudHJ5XVxuVmVyc2lvbj0xLjBcbk5hbWU9JXNcbkNvbW1lbnQ9JXNcbkV4ZWM9JXNcbicgXAogICAgIiQoZGVza3RvcF9zdHJpbmdfZXNjYXBlICIkQVBQX05BTUUiKSIgXAogICAgIiQoZGVza3RvcF9zdHJpbmdfZXNjYXBlICIkQVBQX05BTUUiKSIgXAogICAgIiQoZGVza3RvcF9zdHJpbmdfZXNjYXBlICIkZXhlY19saW5lIikiCiAgcHJpbnRmICdUZXJtaW5hbD1mYWxzZVxuVHlwZT1BcHBsaWNhdGlvblxuSWNvbj0lc1xuU3RhcnR1cE5vdGlmeT10cnVlXG4nIFwKICAgICIkKGRlc2t0b3Bfc3RyaW5nX2VzY2FwZSAiJElDT05fVkFMVUUiKSIKfSA+IiRERVNLVE9QX0ZJTEUiCgpjaG1vZCAreCAiJERFU0tUT1BfRklMRSIKdXBkYXRlLWRlc2t0b3AtZGF0YWJhc2UgIiRERVNLVE9QX0RJUiIgJj4vZGV2L251bGwgfHwgdHJ1ZQoKZWNobyAtZSAiXG4kQVBQX05BTUUgaW5zdGFsbGVkLiBMYXVuY2ggaXQgZnJvbSB0aGUgbGF1bmNoZXIgKFNVUEVSICsgU1BBQ0UpLiI=
EOAINSTALL
}

emit_launch() {
base64 -d <<'EOALAUNCH'
IyEvYmluL2Jhc2gKCiMgTGF1bmNoIGEgVVJMIGFzIGEgYm9yZGVybGVzcyB3ZWItYXBwIHdpbmRvdyBpbiBDaHJvbWl1bSAoLS1hcHA9IGhpZGVzIHRoZQojIHRhYiBzdHJpcCwgdG9vbGJhciwgYW5kIG9tbmlib3gpLiBVc2VkIGFzIHRoZSBFeGVjIHRhcmdldCBvZiB0aGUgZ2VuZXJhdGVkCiMgLmRlc2t0b3AgbGF1bmNoZXJzIGFuZCBieSB0aGUgZm9jdXMtb3ItcmVsYXVuY2ggaGVscGVyLgoKc2V0IC1lCgppZiAoKCAkIyA9PSAwICkpOyB0aGVuCiAgZWNobyAidXNhZ2U6IHFzLXdlYmFwcC1sYXVuY2ggPHVybD4gW2V4dHJhIGNocm9taXVtIGFyZ3MuLi5dIiA+JjIKICBleGl0IDEKZmkKCnVybD0iJDEiCnNoaWZ0CgpleGVjIHNldHNpZCBjaHJvbWl1bSAtLWFwcD0iJHVybCIgIiRAIg==
EOALAUNCH
}

emit_focus() {
base64 -d <<'EOAFOCUS'
IyEvYmluL2Jhc2gKCiMgRm9jdXMgYW4gZXhpc3Rpbmcgd2ViLWFwcCB3aW5kb3cgd2hvc2UgY2xhc3Mgb3IgdGl0bGUgbWF0Y2hlcyA8cGF0dGVybj4sIG9yCiMgcmVsYXVuY2ggaXQgdmlhIHFzLXdlYmFwcC1sYXVuY2ggd2hlbiBub25lIGlzIG9wZW4uIFBhdHRlcm4gaXMgbWF0Y2hlZCBhcyBhCiMgd29yZCBvbiB0aGUgY2xhc3MvdGl0bGUsIGNhc2UtaW5zZW5zaXRpdmVseSwgbGlrZSBvbWFyY2h5J3MgaGVscGVyLgoKc2V0IC1lCgppZiAoKCAkIyA8IDIgKSk7IHRoZW4KICBlY2hvICJ1c2FnZTogcXMtd2ViYXBwLWZvY3VzIDx3aW5kb3ctcGF0dGVybj4gPHVybD4gW2V4dHJhIGNocm9taXVtIGFyZ3MuLi5dIiA+JjIKICBleGl0IDEKZmkKCnBhdHRlcm49IiQxIgpzaGlmdAp1cmw9IiQxIgpzaGlmdAoKYWRkcmVzcz0kKGh5cHJjdGwgY2xpZW50cyAtaiB8IGpxIC1yIC0tYXJnIHAgIiRwYXR0ZXJuIiBcCiAgJy5bXSB8IHNlbGVjdCgoLmNsYXNzIHwgdGVzdCgiXFxiIiArICRwICsgIlxcYiI7ICJpIikpIG9yICgudGl0bGUgfCB0ZXN0KCJcXGIiICsgJHAgKyAiXFxiIjsgImkiKSkpIHwgLmFkZHJlc3MnIFwKICB8IGhlYWQgLW4xKQoKaWYgW1sgLW4gJGFkZHJlc3MgXV07IHRoZW4KICBoeXByY3RsIGRpc3BhdGNoIGZvY3Vzd2luZG93ICJhZGRyZXNzOiRhZGRyZXNzIiA+L2Rldi9udWxsCmVsc2UKICBleGVjICIkKGRpcm5hbWUgIiQwIikvcXMtd2ViYXBwLWxhdW5jaCIgIiR1cmwiICIkQCIKZmk=
EOAFOCUS
}

emit_remove() {
base64 -d <<'EOAREMOVE'
IyEvYmluL2Jhc2gKCiMgUmVtb3ZlIGEgd2ViLWFwcCBsYXVuY2hlciBpbnN0YWxsZWQgYnkgcXMtd2ViYXBwLWluc3RhbGwuIEluZGV4ZXMgdGhlCiMgLmRlc2t0b3AgZmlsZXMgdGhhdCBhY3R1YWxseSBwb2ludCBhdCBxcy13ZWJhcHAtbGF1bmNoIChyYXRoZXIgdGhhbgojIHJlY29uc3RydWN0aW5nIGEgcGF0aCBmcm9tIGEgbmFtZSkgYW5kIG9mZmVycyB0aGVtIHRocm91Z2ggZnpmLgoKc2V0IC1lCgpJQ09OX0RJUj0iJEhPTUUvLmxvY2FsL3NoYXJlL2ljb25zL2hpY29sb3IvMjU2eDI1Ni9hcHBzIgpERVNLVE9QX0RJUj0iJEhPTUUvLmxvY2FsL3NoYXJlL2FwcGxpY2F0aW9ucyIKCldFQl9BUFBTPSgpCldFQl9BUFBfUEFUSFM9KCkKd2hpbGUgSUZTPSByZWFkIC1yIC1kICcnIGZpbGU7IGRvCiAgaWYgZ3JlcCAtcSAnXkV4ZWM9Lipxcy13ZWJhcHAtbGF1bmNoLionICIkZmlsZSI7IHRoZW4KICAgIFdFQl9BUFBTKz0oIiQoYmFzZW5hbWUgIiR7ZmlsZSUuZGVza3RvcH0iKSIpCiAgICBXRUJfQVBQX1BBVEhTKz0oIiRmaWxlIikKICBmaQpkb25lIDwgPChmaW5kICIkREVTS1RPUF9ESVIiIC1uYW1lICcqLmRlc2t0b3AnIC1wcmludDAgMj4vZGV2L251bGwpCgppZiAoKCAkeyNXRUJfQVBQU1tAXX0gPT0gMCApKTsgdGhlbgogIGVjaG8gIk5vIHdlYiBhcHBzIGluc3RhbGxlZC4iCiAgZXhpdCAwCmZpCgppZiAoKCAkIyA9PSAwICkpOyB0aGVuCiAgY2hvaWNlPSQocHJpbnRmICclc1xuJyAiJHtXRUJfQVBQU1tAXX0iIHwgc29ydCB8IGZ6ZiAtLWhlaWdodCAxMiAtLXByb21wdD0iU2VsZWN0IHdlYiBhcHAgdG8gcmVtb3ZlPiAiKQogIFtbIC1uICRjaG9pY2UgXV0gfHwgZXhpdCAwCiAgQVBQX05BTUU9IiRjaG9pY2UiCmVsc2UKICBBUFBfTkFNRT0iJCoiCmZpCgpwYXRoX2Zvcl93ZWJfYXBwKCkgewogIGxvY2FsIHdhbnRlZD0iJDEiIGkKICBmb3IgaSBpbiAiJHshV0VCX0FQUFNbQF19IjsgZG8KICAgIGlmIFtbICR7V0VCX0FQUFNbJGldfSA9PSAiJHdhbnRlZCIgXV07IHRoZW4KICAgICAgcHJpbnRmICclc1xuJyAiJHtXRUJfQVBQX1BBVEhTWyRpXX0iCiAgICAgIHJldHVybiAwCiAgICBmaQogIGRvbmUKICByZXR1cm4gMQp9CgpkZXNrdG9wX2ZpbGU9JChwYXRoX2Zvcl93ZWJfYXBwICIkQVBQX05BTUUiKQpbWyAtbiAkZGVza3RvcF9maWxlIF1dIHx8IHsgZWNobyAiTm8gbWF0Y2hpbmcgd2ViIGFwcDogJEFQUF9OQU1FIiA+JjI7IGV4aXQgMTsgfQoKcm0gLWYgIiRkZXNrdG9wX2ZpbGUiCmljb25fbmFtZT0kKHByaW50ZiAnJXNcbicgIiRBUFBfTkFNRSIgfCB0ciAnWzp1cHBlcjpdJyAnWzpsb3dlcjpdJyB8IHNlZCAncy9bXls6YWxudW06XV1cKy8tL2c7IHMvXi0vLzsgcy8tJC8vJykKcm0gLWYgIiRJQ09OX0RJUi8kaWNvbl9uYW1lLnBuZyIgIiRJQ09OX0RJUi8kQVBQX05BTUUucG5nIgp1cGRhdGUtZGVza3RvcC1kYXRhYmFzZSAiJERFU0tUT1BfRElSIiAmPi9kZXYvbnVsbCB8fCB0cnVlCgplY2hvICJSZW1vdmVkICRBUFBfTkFNRS4i
EOAREMOVE
}

emit_open() {
base64 -d <<'EOAOPEN'
IyEvYmluL2Jhc2gKCiMgT3BlbiB0aGUgd2ViLWFwcCBzZXR1cCBUVUkgaW4gYSB0ZXJtaW5hbC4gVXNlZCBhcyB0aGUgRXhlYyB0YXJnZXQgb2YgdGhlCiMgIkluc3RhbGwgV2ViIEFwcCIgbGF1bmNoZXIgZW50cnkgc28gY2hhbmdpbmcgdGVybWluYWxzIG5ldmVyIHRvdWNoZXMgdGhlCiMgLmRlc2t0b3AgZmlsZS4gT3ZlcnJpZGUgdGhlIHRlcm1pbmFsIHdpdGggVEVSTUlOQUw9PGNtZD4uCgpjbWQ9IiQoY2QgIiQoZGlybmFtZSAiJDAiKSIgJiYgcHdkKS9xcy13ZWJhcHAtaW5zdGFsbDsgZWNobzsgcmVhZCAtciAtcCAnUHJlc3MgRW50ZXIgdG8gY2xvc2UnIgoKdGVybWluYWw9IiR7VEVSTUlOQUw6LX0iCmlmIFtbIC16ICR0ZXJtaW5hbCBdXTsgdGhlbgogIGZvciB0IGluIGtpdHR5IGFsYWNyaXR0eSBmb290IHhmY2U0LXRlcm1pbmFsIGtvbnNvbGUgZ25vbWUtdGVybWluYWwgeC10ZXJtaW5hbC1lbXVsYXRvciB4ZGctdGVybWluYWwtZXhlYzsgZG8KICAgIGlmIGNvbW1hbmQgLXYgIiR0IiA+L2Rldi9udWxsIDI+JjE7IHRoZW4gdGVybWluYWw9IiR0IjsgYnJlYWs7IGZpCiAgZG9uZQpmaQoKaWYgW1sgLXogJHRlcm1pbmFsIF1dOyB0aGVuCiAgZWNobyAiTm8gdGVybWluYWwgZm91bmQuIEluc3RhbGwgb25lIG9yIHNldCBURVJNSU5BTD0vcGF0aC90by95b3VyLXRlcm1pbmFsLiIgPiYyCiAgZXhpdCAxCmZpCgpjYXNlICIkKGJhc2VuYW1lICIkdGVybWluYWwiKSIgaW4KICBraXR0eSkgICAgICAgICAgZXhlYyAiJHRlcm1pbmFsIiAtLXRpdGxlICJBZGQgV2ViIEFwcCIgLWUgYmFzaCAtYyAiJGNtZCIgOzsKICBhbGFjcml0dHkpICAgICAgZXhlYyAiJHRlcm1pbmFsIiAtLXRpdGxlICJBZGQgV2ViIEFwcCIgLWUgYmFzaCAtYyAiJGNtZCIgOzsKICBmb290KSAgICAgICAgICAgZXhlYyAiJHRlcm1pbmFsIiAtLXRpdGxlICJBZGQgV2ViIEFwcCIgLWUgYmFzaCAtYyAiJGNtZCIgOzsKICB4ZmNlNC10ZXJtaW5hbCkgZXhlYyAiJHRlcm1pbmFsIiAtLXRpdGxlICJBZGQgV2ViIEFwcCIgLS1leGVjdXRlIGJhc2ggLWMgIiRjbWQiIDs7CiAga29uc29sZSkgICAgICAgIGV4ZWMgIiR0ZXJtaW5hbCIgLS10aXRsZSAiQWRkIFdlYiBBcHAiIC1lIGJhc2ggLWMgIiRjbWQiIDs7CiAgZ25vbWUtdGVybWluYWwpIGV4ZWMgIiR0ZXJtaW5hbCIgLS10aXRsZSAiQWRkIFdlYiBBcHAiIC0tIGJhc2ggLWMgIiRjbWQiIDs7CiAgeC10ZXJtaW5hbC1lbXVsYXRvcikgZXhlYyAiJHRlcm1pbmFsIiAtZSBiYXNoIC1jICIkY21kIiA7OwogIHhkZy10ZXJtaW5hbC1leGVjKSAgZXhlYyAiJHRlcm1pbmFsIiBiYXNoIC1jICIkY21kIiA7OwogICopIGV4ZWMgIiR0ZXJtaW5hbCIgLWUgYmFzaCAtYyAiJGNtZCIgOzsKZXNhYw==
EOAOPEN
}

emit_flags() {
base64 -d <<'EOAFLAGS'
LS1vem9uZS1wbGF0Zm9ybT13YXlsYW5kCi0tb3pvbmUtcGxhdGZvcm0taGludD13YXlsYW5kCi0tcGFzc3dvcmQtc3RvcmU9Z25vbWUtbGlic2VjcmV0Ci0tZW5hYmxlLWZlYXR1cmVzPVRvdWNocGFkT3ZlcnNjcm9sbEhpc3RvcnlOYXZpZ2F0aW9u
EOAFLAGS
}

case "${1:-}" in
  --check) check_deps ;;
  --install-deps) check_deps; install_deps ;;
  --link-bin) install; link_bin ;;
  --uninstall) uninstall ;;
  --help|-h) usage ;;
  *) if (( $# == 0 )); then install; else echo "Unknown option: $1" >&2; usage >&2; exit 1; fi ;;
esac