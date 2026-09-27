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
  --install-deps  run: sudo pacman -S --needed chromium curl file jq fzf
  --link-bin      symlink qs-webapp-* into ~/.local/bin so you can type them
                  in a terminal (also: fish_add_path ~/.local/bin)
  --uninstall     remove the webapp tooling (bin dir, flags, launcher entry)
                  installed web apps themselves are left in place
USAGE
}

HARD_DEPS=(chromium curl file jq fzf)
SOFT_DEPS=()

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
      echo "Install with:  sudo pacman -S --needed chromium curl file jq fzf"
    fi
    if ((${#soft_missing[@]})); then
      printf 'Missing (optional): %s\n' "${soft_missing[*]}"
    fi
    if ((${#missing[@]})); then return 1; fi
  else
    echo "All dependencies present."
  fi
}

install_deps() {
  sudo -v
  sudo pacman -S --needed --noconfirm chromium curl file jq fzf
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
  local launcher_exec
  launcher_exec="$(desktop_exec_path "$BIN_DIR/qs-webapp-open-tui")"
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
Exec=$launcher_exec
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

desktop_exec_path() {
  local arg="$1"
  arg=${arg//\\/\\\\}
  arg=${arg//\"/\\\"}
  arg=${arg//\`/\\\`}
  arg=${arg//\$/\\\$}
  arg=${arg//%/%%}
  arg=${arg//\\/\\\\}
  printf '"%s"' "$arg"
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
IyEvYmluL2Jhc2gKCiMgQ3JlYXRlIGEgZGVza3RvcCBsYXVuY2hlciBmb3IgYSB3ZWIgYXBwOiBwcm9tcHRzIGZvciBhIG5hbWUgYW5kIFVSTCwgcHVsbHMKIyB0aGUgc2l0ZSdzIGljb24gYXV0b21hdGljYWxseSAoYXBwbGUtdG91Y2gtaWNvbiwgL2FwcGxlLXRvdWNoLWljb24ucG5nLCB0aGVuCiMgR29vZ2xlJ3MgZmF2aWNvbiBzZXJ2aWNlKSwgYW5kIHdyaXRlcyBhIC5kZXNrdG9wIGVudHJ5IHNvIHRoZSBhcHAgc2hvd3MgdXAgaW4KIyB0aGUgTm9jdGFsaWEgbGF1bmNoZXIuIENocm9taXVtJ3MgLS1hcHA9IHdpbmRvdyBzdHJpcHMgdGhlIGJyb3dzZXIgY2hyb21lIGZvcgojIGEgYm9yZGVybGVzcyBhcHAgbG9vay4KCnNldCAtZQoKREFUQV9ESVI9IiR7WERHX0RBVEFfSE9NRTotJEhPTUUvLmxvY2FsL3NoYXJlfSIKSUNPTl9ESVI9IiREQVRBX0RJUi9pY29ucy9oaWNvbG9yLzI1NngyNTYvYXBwcyIKREVTS1RPUF9ESVI9IiREQVRBX0RJUi9hcHBsaWNhdGlvbnMiCkxBVU5DSEVSX1NDUklQVD0iJChkaXJuYW1lICIkKHJlYWRsaW5rIC1mICIkMCIpIikvcXMtd2ViYXBwLWxhdW5jaCIKCnJlcXVpcmVfcGxhaW5fbmFtZSgpIHsKICBpZiBbWyAkMSA9PSAqLyogfHwgJDEgPX4gW1s6Y250cmw6XV0gXV07IHRoZW4KICAgIGVjaG8gIkFwcCBuYW1lIGNhbm5vdCBjb250YWluICcvJyBvciBjb250cm9sIGNoYXJhY3RlcnMuIiA+JjIKICAgIGV4aXQgMQogIGZpCiAgaWYgW1sgLXogJDEgXV07IHRoZW4KICAgIGVjaG8gIkFwcCBuYW1lIGNhbm5vdCBiZSBlbXB0eS4iID4mMgogICAgZXhpdCAxCiAgZmkKfQoKIyBDaHJvbWl1bSAtLWFwcD0gdHJlYXRzIGphdmFzY3JpcHQ6LCBmaWxlOiwgYW5kIGRhdGE6IGFzIGEgZG9jdW1lbnQgdG8gcnVuLgojIFByZWZpeCBzY2hlbWVsZXNzIGlucHV0IHdpdGggaHR0cHMgYW5kIHJlZnVzZSBhbnl0aGluZyB0aGF0IGlzIG5vdCBodHRwKHMpLgpub3JtYWxpemVfd2ViYXBwX3VybCgpIHsKICBsb2NhbCB1cmw9JDEKICBpZiBbWyAhICR1cmwgPX4gXlthLXpBLVpdW2EtekEtWjAtOSsuLV0qOiBdXTsgdGhlbgogICAgdXJsPSJodHRwczovLyR1cmwiCiAgZmkKICBwcmludGYgJyVzJyAiJHVybCIKfQoKcmVxdWlyZV9odHRwX3VybCgpIHsKICBsb2NhbCB1cmw9JDEKICBpZiBbWyAkdXJsID1+IFtbOnNwYWNlOl1dIF1dOyB0aGVuCiAgICBlY2hvICJFcnJvcjogd2ViIGFwcCBVUkwgbXVzdCBub3QgY29udGFpbiB3aGl0ZXNwYWNlLiIgPiYyCiAgICBleGl0IDEKICBmaQogIGlmIFtbICEgJHt1cmwsLH0gPX4gXmh0dHBzPzovL1teLz8jXSsgXV07IHRoZW4KICAgIGVjaG8gIkVycm9yOiB3ZWIgYXBwIFVSTCBtdXN0IGJlIGh0dHAgb3IgaHR0cHMuIiA+JjIKICAgIGV4aXQgMQogIGZpCn0KCmRvd25sb2FkX2ljb24oKSB7CiAgY3VybCAtZnNTTCAtLW1heC10aW1lIDEwIC1vICIkMiIgIiQxIiAyPi9kZXYvbnVsbCAmJgogICAgW1sgLXMgJDIgJiYgJChmaWxlIC1iIC0tbWltZS10eXBlICIkMiIpID09IGltYWdlLyogXV0KfQoKZmV0Y2hfc2l0ZV9pY29uKCkgewogIGxvY2FsIHNpdGVfdXJsPSIkMSIgZGVzdD0iJDIiCiAgbG9jYWwgb3JpZ2luIHBhZ2UgaWNvbl91cmwKICBvcmlnaW49JChzZWQgLUUgJ3N8XihodHRwcz86Ly9bXi9dKykuKnxcMXwnIDw8PCIkc2l0ZV91cmwiKQoKICAjIFByZWZlciB0aGUgc2l0ZSdzIG93biBoaWdoLXJlcyBpY29uIChhcHBsZS10b3VjaC1pY29uKSwgdGhlbiB0aGUgd2VsbC1rbm93bgogICMgcGF0aCwgdGhlbiBHb29nbGUncyBmYXZpY29uIHNlcnZpY2UgYXMgYSBsYXN0IHJlc29ydC4KICBwYWdlPSQoY3VybCAtZnNTTCAtLW1heC10aW1lIDUgIiRzaXRlX3VybCIgMj4vZGV2L251bGwgfCBoZWFkIC1jIDEwMDAwMCB8IHRyICdcbicgJyAnKQogIGljb25fdXJsPSQoZ3JlcCAtb2lFICI8bGlua1tePl0qcmVsPVtcIiddW15cIiddKmFwcGxlLXRvdWNoLWljb25bXlwiJ10qW1wiJ11bXj5dKj4iIDw8PCIkcGFnZSIgfAogICAgZ3JlcCAtb2lFICJocmVmPVtcIiddW15cIiddKyIgfCBoZWFkIC0xIHwgc2VkIC1FICJzL15ocmVmPVtcIiddLy8iKQoKICBjYXNlICRpY29uX3VybCBpbgogIGh0dHA6Ly8qIHwgaHR0cHM6Ly8qKSA7OwogIC8vKikgaWNvbl91cmw9Imh0dHBzOiRpY29uX3VybCIgOzsKICAvKikgaWNvbl91cmw9IiRvcmlnaW4kaWNvbl91cmwiIDs7CiAgPyopIGljb25fdXJsPSIkb3JpZ2luLyRpY29uX3VybCIgOzsKICBlc2FjCgogIHsgW1sgLW4gJGljb25fdXJsIF1dICYmIGRvd25sb2FkX2ljb24gIiRpY29uX3VybCIgIiRkZXN0IjsgfSB8fAogICAgZG93bmxvYWRfaWNvbiAiJG9yaWdpbi9hcHBsZS10b3VjaC1pY29uLnBuZyIgIiRkZXN0IiB8fAogICAgZG93bmxvYWRfaWNvbiAiaHR0cHM6Ly93d3cuZ29vZ2xlLmNvbS9zMi9mYXZpY29ucz9kb21haW49JHtzaXRlX3VybH0mc3o9MjU2IiAiJGRlc3QiCn0KCiMgRnJlZWRlc2t0b3AgRGVza3RvcCBFbnRyeSAic3RyaW5nIiBlc2NhcGluZzogYSByYXcgbmV3bGluZSB3b3VsZCBvcGVuIGEgbmV3CiMga2V5LCBhbmQgZXZlcnkgRXhlYyBhcmd1bWVudCB0aGF0IGlzIG5vdCB0aGUgVVJMIGlzIGxpdGVyYWwgdGV4dCwgc28gZXNjYXBlCiMgYmFja3NsYXNoIGZpcnN0LCB0aGVuIHRhYi9DUi9MRiBhbmQgYSBsZWFkaW5nIHNwYWNlLgpkZXNrdG9wX3N0cmluZ19lc2NhcGUoKSB7CiAgbG9jYWwgdmFsdWU9IiQxIgogIHZhbHVlPSR7dmFsdWUvL1xcL1xcXFx9CiAgdmFsdWU9JHt2YWx1ZS8vJCdcdCcvXFx0fQogIHZhbHVlPSR7dmFsdWUvLyQnXHInL1xccn0KICB2YWx1ZT0ke3ZhbHVlLy8kJ1xuJy9cXG59CiAgW1sgJHZhbHVlID09ICIgIiogXV0gJiYgdmFsdWU9IlxccyR7dmFsdWUjIH0iCiAgcHJpbnRmICclcycgIiR2YWx1ZSIKfQoKIyBPbmUgcXVvdGVkIEV4ZWMgYXJndW1lbnQgcGVyIHRoZSBmcmVlZGVza3RvcCBFeGVjIHNwZWM6IGluc2lkZSBxdW90ZXMKIyAiIGAgJCBcIHRha2UgYSBiYWNrc2xhc2ggYW5kIGEgbGl0ZXJhbCAlIGJlY29tZXMgJSUuCmRlc2t0b3BfZXhlY19hcmcoKSB7CiAgcHJpbnRmICciJXMiJyAiJChwcmludGYgJyVzJyAiJDEiIFwKICAgIHwgc2VkIC1lICdzL1xcL1xcXFwvZycgLWUgJ3MvIi9cXCIvZycgLWUgJ3MvYC9cXGAvZycgLWUgJ3MvXCQvXFwkL2cnIC1lICdzLyUvJSUvZycpIgp9CgpJTlRFUkFDVElWRV9NT0RFPWZhbHNlCmlmICgoICQjID09IDAgKSk7IHRoZW4KICBJTlRFUkFDVElWRV9NT0RFPXRydWUKICBlY2hvIC1lICJcbkxldCdzIGNyZWF0ZSBhIHdlYiBhcHAgeW91IGNhbiBzdGFydCBmcm9tIHRoZSBsYXVuY2hlci5cbiIKICByZWFkIC1ycCAiTmFtZT4gIiBBUFBfTkFNRQogIHJlcXVpcmVfcGxhaW5fbmFtZSAiJEFQUF9OQU1FIgogIHJlYWQgLXJwICJVUkw+ICIgQVBQX1VSTAogIEFQUF9VUkw9JChub3JtYWxpemVfd2ViYXBwX3VybCAiJEFQUF9VUkwiKQogIHJlcXVpcmVfaHR0cF91cmwgIiRBUFBfVVJMIgogIElDT05fUkVGPSIiCmVsc2UKICBpZiAoKCAkIyA8IDIgKSk7IHRoZW4KICAgIGVjaG8gInVzYWdlOiBxcy13ZWJhcHAtaW5zdGFsbCA8bmFtZT4gPHVybD4gW2ljb25dIFtleHRyYSBjaHJvbWl1bSBhcmdzLi4uXSIgPiYyCiAgICBleGl0IDEKICBmaQogIEFQUF9OQU1FPSIkMSIKICBBUFBfVVJMPSQobm9ybWFsaXplX3dlYmFwcF91cmwgIiQyIikKICByZXF1aXJlX2h0dHBfdXJsICIkQVBQX1VSTCIKICBJQ09OX1JFRj0iJHszOi19IgpmaQpyZXF1aXJlX3BsYWluX25hbWUgIiRBUFBfTkFNRSIKCm1rZGlyIC1wICIkSUNPTl9ESVIiICIkREVTS1RPUF9ESVIiCiMgTmFtZXMgbGlrZSAiRXhhbXBsZSEiIGFuZCAiRXhhbXBsZT8iIG11c3Qgbm90IG92ZXJ3cml0ZSBlYWNoIG90aGVyJ3MgaWNvbnMuCklDT05fVkFMVUU9InFzLXdlYmFwcC0kKHByaW50ZiAnJXMnICIkQVBQX05BTUUiIHwgc2hhMjU2c3VtIHwgY3V0IC1kJyAnIC1mMSkiCgppZiBbWyAteiAkSUNPTl9SRUYgXV07IHRoZW4KICBpZiBmZXRjaF9zaXRlX2ljb24gIiRBUFBfVVJMIiAiJElDT05fRElSLyRJQ09OX1ZBTFVFLnBuZyI7IHRoZW4KICAgIGd0ay11cGRhdGUtaWNvbi1jYWNoZSAiJERBVEFfRElSL2ljb25zL2hpY29sb3IiICY+L2Rldi9udWxsIHx8IHRydWUKICBlbGlmIFtbICRJTlRFUkFDVElWRV9NT0RFID09ICJ0cnVlIiBdXTsgdGhlbgogICAgcmVhZCAtcnAgIkljb24gVVJML25hbWU+ICIgSUNPTl9SRUYKICAgIGlmIFtbIC16ICRJQ09OX1JFRiBdXTsgdGhlbgogICAgICBlY2hvICJObyBpY29uIHByb3ZpZGVkOyB0aGUgYXBwIHdpbGwgdXNlIHRoZSBmYWxsYmFjayBpY29uLiIgPiYyCiAgICBmaQogIGVsc2UKICAgIGVjaG8gIkVycm9yOiBmYWlsZWQgdG8gZmV0Y2ggYSBzaXRlIGljb247IHBhc3MgYW4gaWNvbiBVUkwgb3IgbmFtZSBleHBsaWNpdGx5LiIgPiYyCiAgICBleGl0IDEKICBmaQpmaQoKaWYgW1sgLW4gJElDT05fUkVGIF1dOyB0aGVuCiAgaWYgW1sgJElDT05fUkVGID1+IF5odHRwcz86Ly8gXV07IHRoZW4KICAgIGRvd25sb2FkX2ljb24gIiRJQ09OX1JFRiIgIiRJQ09OX0RJUi8kSUNPTl9WQUxVRS5wbmciIFwKICAgICAgfHwgeyBlY2hvICJFcnJvcjogZmFpbGVkIHRvIGRvd25sb2FkIGljb24uIiA+JjI7IGV4aXQgMTsgfQogICAgZ3RrLXVwZGF0ZS1pY29uLWNhY2hlICIkREFUQV9ESVIvaWNvbnMvaGljb2xvciIgJj4vZGV2L251bGwgfHwgdHJ1ZQogIGVsaWYgW1sgLWYgJElDT05fUkVGIF1dOyB0aGVuCiAgICBleHQ9IiR7SUNPTl9SRUYjIyoufSIKICAgIFtbICRleHQgPT0gIiRJQ09OX1JFRiIgXV0gJiYgZXh0PSJwbmciCiAgICBjcCAiJElDT05fUkVGIiAiJElDT05fRElSLyRJQ09OX1ZBTFVFLiRleHQiCiAgICBndGstdXBkYXRlLWljb24tY2FjaGUgIiREQVRBX0RJUi9pY29ucy9oaWNvbG9yIiAmPi9kZXYvbnVsbCB8fCB0cnVlCiAgZWxzZQogICAgSUNPTl9WQUxVRT0iJElDT05fUkVGIiAjIEV4aXN0aW5nIGljb24gbmFtZSBpbiB0aGUgdGhlbWUKICBmaQpmaQoKREVTS1RPUF9GSUxFPSIkREVTS1RPUF9ESVIvJEFQUF9OQU1FLmRlc2t0b3AiCmV4ZWNfbGluZT0iJChkZXNrdG9wX2V4ZWNfYXJnICIkTEFVTkNIRVJfU0NSSVBUIikgJChkZXNrdG9wX2V4ZWNfYXJnICIkQVBQX1VSTCIpIgppZiAoKCAkIyA+IDMgKSk7IHRoZW4KICBmb3IgYXJnIGluICIke0A6NH0iOyBkbyBleGVjX2xpbmUrPSIgJChkZXNrdG9wX2V4ZWNfYXJnICIkYXJnIikiOyBkb25lCmZpCgp7CiAgcHJpbnRmICdbRGVza3RvcCBFbnRyeV1cblZlcnNpb249MS4wXG5OYW1lPSVzXG5Db21tZW50PSVzXG5FeGVjPSVzXG4nIFwKICAgICIkKGRlc2t0b3Bfc3RyaW5nX2VzY2FwZSAiJEFQUF9OQU1FIikiIFwKICAgICIkKGRlc2t0b3Bfc3RyaW5nX2VzY2FwZSAiJEFQUF9OQU1FIikiIFwKICAgICIkKGRlc2t0b3Bfc3RyaW5nX2VzY2FwZSAiJGV4ZWNfbGluZSIpIgogIHByaW50ZiAnVGVybWluYWw9ZmFsc2VcblR5cGU9QXBwbGljYXRpb25cbkljb249JXNcblN0YXJ0dXBOb3RpZnk9dHJ1ZVxuJyBcCiAgICAiJChkZXNrdG9wX3N0cmluZ19lc2NhcGUgIiRJQ09OX1ZBTFVFIikiCn0gPiIkREVTS1RPUF9GSUxFIgoKY2htb2QgK3ggIiRERVNLVE9QX0ZJTEUiCnVwZGF0ZS1kZXNrdG9wLWRhdGFiYXNlICIkREVTS1RPUF9ESVIiICY+L2Rldi9udWxsIHx8IHRydWUKCmVjaG8gLWUgIlxuJEFQUF9OQU1FIGluc3RhbGxlZC4gTGF1bmNoIGl0IGZyb20gdGhlIGxhdW5jaGVyIChTVVBFUiArIFNQQUNFKS4iCg==
EOAINSTALL
}

emit_launch() {
base64 -d <<'EOALAUNCH'
IyEvYmluL2Jhc2gKCiMgTGF1bmNoIGEgVVJMIGFzIGEgYm9yZGVybGVzcyB3ZWItYXBwIHdpbmRvdyBpbiBDaHJvbWl1bSAoLS1hcHA9IGhpZGVzIHRoZQojIHRhYiBzdHJpcCwgdG9vbGJhciwgYW5kIG9tbmlib3gpLiBVc2VkIGFzIHRoZSBFeGVjIHRhcmdldCBvZiB0aGUgZ2VuZXJhdGVkCiMgLmRlc2t0b3AgbGF1bmNoZXJzIGFuZCBieSB0aGUgZm9jdXMtb3ItcmVsYXVuY2ggaGVscGVyLgoKc2V0IC1lCgppZiAoKCAkIyA9PSAwICkpOyB0aGVuCiAgZWNobyAidXNhZ2U6IHFzLXdlYmFwcC1sYXVuY2ggPHVybD4gW2V4dHJhIGNocm9taXVtIGFyZ3MuLi5dIiA+JjIKICBleGl0IDEKZmkKCnVybD0iJDEiCnNoaWZ0CgpleGVjIHNldHNpZCBjaHJvbWl1bSAtLWFwcD0iJHVybCIgIiRAIg==
EOALAUNCH
}

emit_focus() {
base64 -d <<'EOAFOCUS'
IyEvYmluL2Jhc2gKCiMgRm9jdXMgYW4gZXhpc3Rpbmcgd2ViLWFwcCB3aW5kb3cgd2hvc2UgY2xhc3Mgb3IgdGl0bGUgbWF0Y2hlcyA8cGF0dGVybj4sIG9yCiMgcmVsYXVuY2ggaXQgdmlhIHFzLXdlYmFwcC1sYXVuY2ggd2hlbiBub25lIGlzIG9wZW4uIFBhdHRlcm4gaXMgbWF0Y2hlZCBhcyBhCiMgd29yZCBvbiB0aGUgY2xhc3MvdGl0bGUsIGNhc2UtaW5zZW5zaXRpdmVseSwgbGlrZSBvbWFyY2h5J3MgaGVscGVyLgoKc2V0IC1ldW8gcGlwZWZhaWwKCmlmICgoICQjIDwgMiApKTsgdGhlbgogIGVjaG8gInVzYWdlOiBxcy13ZWJhcHAtZm9jdXMgPHdpbmRvdy1wYXR0ZXJuPiA8dXJsPiBbZXh0cmEgY2hyb21pdW0gYXJncy4uLl0iID4mMgogIGV4aXQgMQpmaQoKcGF0dGVybj0iJDEiCnNoaWZ0CnVybD0iJDEiCnNoaWZ0CgphZGRyZXNzPSQoaHlwcmN0bCBjbGllbnRzIC1qIHwganEgLXIgLS1hcmcgcCAiJHBhdHRlcm4iIFwKICAnZmlyc3QoLltdIHwgc2VsZWN0KCguY2xhc3MgfCB0ZXN0KCJcXGIiICsgJHAgKyAiXFxiIjsgImkiKSkgb3IgKC50aXRsZSB8IHRlc3QoIlxcYiIgKyAkcCArICJcXGIiOyAiaSIpKSkgfCAuYWRkcmVzcykgLy8gZW1wdHknKQoKaWYgW1sgLW4gJGFkZHJlc3MgXV07IHRoZW4KICBoeXByY3RsIGRpc3BhdGNoIGZvY3Vzd2luZG93ICJhZGRyZXNzOiRhZGRyZXNzIiA+L2Rldi9udWxsCmVsc2UKICBleGVjICIkKGRpcm5hbWUgIiQocmVhZGxpbmsgLWYgIiQwIikiKS9xcy13ZWJhcHAtbGF1bmNoIiAiJHVybCIgIiRAIgpmaQo=
EOAFOCUS
}

emit_remove() {
base64 -d <<'EOAREMOVE'
IyEvYmluL2Jhc2gKCiMgUmVtb3ZlIGEgd2ViLWFwcCBsYXVuY2hlciBpbnN0YWxsZWQgYnkgcXMtd2ViYXBwLWluc3RhbGwuIEluZGV4ZXMgdGhlCiMgLmRlc2t0b3AgZmlsZXMgdGhhdCBhY3R1YWxseSBwb2ludCBhdCBxcy13ZWJhcHAtbGF1bmNoIChyYXRoZXIgdGhhbgojIHJlY29uc3RydWN0aW5nIGEgcGF0aCBmcm9tIGEgbmFtZSkgYW5kIG9mZmVycyB0aGVtIHRocm91Z2ggZnpmLgoKc2V0IC1lCgpEQVRBX0RJUj0iJHtYREdfREFUQV9IT01FOi0kSE9NRS8ubG9jYWwvc2hhcmV9IgpJQ09OX0RJUj0iJERBVEFfRElSL2ljb25zL2hpY29sb3IvMjU2eDI1Ni9hcHBzIgpERVNLVE9QX0RJUj0iJERBVEFfRElSL2FwcGxpY2F0aW9ucyIKCldFQl9BUFBTPSgpCldFQl9BUFBfUEFUSFM9KCkKd2hpbGUgSUZTPSByZWFkIC1yIC1kICcnIGZpbGU7IGRvCiAgaWYgZ3JlcCAtcSAnXkV4ZWM9Lipxcy13ZWJhcHAtbGF1bmNoLionICIkZmlsZSI7IHRoZW4KICAgIFdFQl9BUFBTKz0oIiQoYmFzZW5hbWUgIiR7ZmlsZSUuZGVza3RvcH0iKSIpCiAgICBXRUJfQVBQX1BBVEhTKz0oIiRmaWxlIikKICBmaQpkb25lIDwgPChmaW5kICIkREVTS1RPUF9ESVIiIC1uYW1lICcqLmRlc2t0b3AnIC1wcmludDAgMj4vZGV2L251bGwpCgppZiAoKCAkeyNXRUJfQVBQU1tAXX0gPT0gMCApKTsgdGhlbgogIGVjaG8gIk5vIHdlYiBhcHBzIGluc3RhbGxlZC4iCiAgZXhpdCAwCmZpCgppZiAoKCAkIyA9PSAwICkpOyB0aGVuCiAgY2hvaWNlPSQocHJpbnRmICclc1xuJyAiJHtXRUJfQVBQU1tAXX0iIHwgc29ydCB8IGZ6ZiAtLWhlaWdodCAxMiAtLXByb21wdD0iU2VsZWN0IHdlYiBhcHAgdG8gcmVtb3ZlPiAiKSB8fCB7CiAgICBzdGF0dXM9JD8KICAgICgoIHN0YXR1cyA9PSAxIHx8IHN0YXR1cyA9PSAxMzAgKSkgJiYgZXhpdCAwCiAgICBleGl0ICIkc3RhdHVzIgogIH0KICBbWyAtbiAkY2hvaWNlIF1dIHx8IGV4aXQgMAogIEFQUF9OQU1FPSIkY2hvaWNlIgplbHNlCiAgQVBQX05BTUU9IiQqIgpmaQoKcGF0aF9mb3Jfd2ViX2FwcCgpIHsKICBsb2NhbCB3YW50ZWQ9IiQxIiBpCiAgZm9yIGkgaW4gIiR7IVdFQl9BUFBTW0BdfSI7IGRvCiAgICBpZiBbWyAke1dFQl9BUFBTWyRpXX0gPT0gIiR3YW50ZWQiIF1dOyB0aGVuCiAgICAgIHByaW50ZiAnJXNcbicgIiR7V0VCX0FQUF9QQVRIU1skaV19IgogICAgICByZXR1cm4gMAogICAgZmkKICBkb25lCiAgcmV0dXJuIDEKfQoKZGVza3RvcF9maWxlPSQocGF0aF9mb3Jfd2ViX2FwcCAiJEFQUF9OQU1FIikgfHwgeyBlY2hvICJObyBtYXRjaGluZyB3ZWIgYXBwOiAkQVBQX05BTUUiID4mMjsgZXhpdCAxOyB9CgpybSAtZiAiJGRlc2t0b3BfZmlsZSIKaWNvbl9uYW1lPSJxcy13ZWJhcHAtJChwcmludGYgJyVzJyAiJEFQUF9OQU1FIiB8IHNoYTI1NnN1bSB8IGN1dCAtZCcgJyAtZjEpIgojIE9ubHkgcmVtb3ZlIHRoaXMgYXBwJ3Mgb3duZWQgaWNvbnMsIGluY2x1ZGluZyBsb2NhbCBTVkcvSlBFRyBmaWxlcy4gTGVnYWN5CiMgdW5wcmVmaXhlZCBpY29ucyBtYXkgYmUgc2hhcmVkIGJ5IG90aGVyIGxhdW5jaGVycywgc28gbGVhdmUgdGhvc2UgaW50YWN0LgpybSAtZiAtLSAiJElDT05fRElSLyRpY29uX25hbWUiLioKdXBkYXRlLWRlc2t0b3AtZGF0YWJhc2UgIiRERVNLVE9QX0RJUiIgJj4vZGV2L251bGwgfHwgdHJ1ZQoKZWNobyAiUmVtb3ZlZCAkQVBQX05BTUUuIgo=
EOAREMOVE
}

emit_open() {
base64 -d <<'EOAOPEN'
IyEvYmluL2Jhc2gKCiMgT3BlbiB0aGUgd2ViLWFwcCBzZXR1cCBUVUkgaW4gYSB0ZXJtaW5hbC4gVXNlZCBhcyB0aGUgRXhlYyB0YXJnZXQgb2YgdGhlCiMgIkluc3RhbGwgV2ViIEFwcCIgbGF1bmNoZXIgZW50cnkgc28gY2hhbmdpbmcgdGVybWluYWxzIG5ldmVyIHRvdWNoZXMgdGhlCiMgLmRlc2t0b3AgZmlsZS4gT3ZlcnJpZGUgdGhlIHRlcm1pbmFsIHdpdGggVEVSTUlOQUw9PGNtZD4uCgpzY3JpcHQ9IiQoZGlybmFtZSAiJChyZWFkbGluayAtZiAiJDAiKSIpL3FzLXdlYmFwcC1pbnN0YWxsIgpwcmludGYgLXYgY21kICIlcTsgZWNobzsgcmVhZCAtciAtcCAnUHJlc3MgRW50ZXIgdG8gY2xvc2UnIiAiJHNjcmlwdCIKCnRlcm1pbmFsPSIke1RFUk1JTkFMOi19IgppZiBbWyAteiAkdGVybWluYWwgXV07IHRoZW4KICBmb3IgdCBpbiBraXR0eSBhbGFjcml0dHkgZm9vdCB4ZmNlNC10ZXJtaW5hbCBrb25zb2xlIGdub21lLXRlcm1pbmFsIHgtdGVybWluYWwtZW11bGF0b3IgeGRnLXRlcm1pbmFsLWV4ZWM7IGRvCiAgICBpZiBjb21tYW5kIC12ICIkdCIgPi9kZXYvbnVsbCAyPiYxOyB0aGVuIHRlcm1pbmFsPSIkdCI7IGJyZWFrOyBmaQogIGRvbmUKZmkKCmlmIFtbIC16ICR0ZXJtaW5hbCBdXTsgdGhlbgogIGVjaG8gIk5vIHRlcm1pbmFsIGZvdW5kLiBJbnN0YWxsIG9uZSBvciBzZXQgVEVSTUlOQUw9L3BhdGgvdG8veW91ci10ZXJtaW5hbC4iID4mMgogIGV4aXQgMQpmaQoKY2FzZSAiJChiYXNlbmFtZSAiJHRlcm1pbmFsIikiIGluCiAga2l0dHkpICAgICAgICAgIGV4ZWMgIiR0ZXJtaW5hbCIgLS10aXRsZSAiQWRkIFdlYiBBcHAiIC1lIGJhc2ggLWMgIiRjbWQiIDs7CiAgYWxhY3JpdHR5KSAgICAgIGV4ZWMgIiR0ZXJtaW5hbCIgLS10aXRsZSAiQWRkIFdlYiBBcHAiIC1lIGJhc2ggLWMgIiRjbWQiIDs7CiAgZm9vdCkgICAgICAgICAgIGV4ZWMgIiR0ZXJtaW5hbCIgLS10aXRsZSAiQWRkIFdlYiBBcHAiIC1lIGJhc2ggLWMgIiRjbWQiIDs7CiAgeGZjZTQtdGVybWluYWwpIGV4ZWMgIiR0ZXJtaW5hbCIgLS10aXRsZSAiQWRkIFdlYiBBcHAiIC0tZXhlY3V0ZSBiYXNoIC1jICIkY21kIiA7OwogIGtvbnNvbGUpICAgICAgICBleGVjICIkdGVybWluYWwiIC0tdGl0bGUgIkFkZCBXZWIgQXBwIiAtZSBiYXNoIC1jICIkY21kIiA7OwogIGdub21lLXRlcm1pbmFsKSBleGVjICIkdGVybWluYWwiIC0tdGl0bGUgIkFkZCBXZWIgQXBwIiAtLSBiYXNoIC1jICIkY21kIiA7OwogIHgtdGVybWluYWwtZW11bGF0b3IpIGV4ZWMgIiR0ZXJtaW5hbCIgLWUgYmFzaCAtYyAiJGNtZCIgOzsKICB4ZGctdGVybWluYWwtZXhlYykgIGV4ZWMgIiR0ZXJtaW5hbCIgYmFzaCAtYyAiJGNtZCIgOzsKICAqKSBleGVjICIkdGVybWluYWwiIC1lIGJhc2ggLWMgIiRjbWQiIDs7CmVzYWMK
EOAOPEN
}

emit_flags() {
base64 -d <<'EOAFLAGS'
LS1vem9uZS1wbGF0Zm9ybT13YXlsYW5kCi0tb3pvbmUtcGxhdGZvcm0taGludD13YXlsYW5kCi0tcGFzc3dvcmQtc3RvcmU9Z25vbWUtbGlic2VjcmV0Ci0tZW5hYmxlLWZlYXR1cmVzPVRvdWNocGFkT3ZlcnNjcm9sbEhpc3RvcnlOYXZpZ2F0aW9u
EOAFLAGS
}

case "${1:-}" in
  --check) check_deps ;;
  --install-deps) install_deps; check_deps ;;
  --link-bin) install; link_bin ;;
  --uninstall) uninstall ;;
  --help|-h) usage ;;
  *) if (( $# == 0 )); then install; else echo "Unknown option: $1" >&2; usage >&2; exit 1; fi ;;
esac