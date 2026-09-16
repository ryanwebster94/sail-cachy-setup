# sail-cachy-setup

> A `setup.sh` / `sync.sh` pair that makes two **Noctalia + Hyprland** machines run identically — and keeps them identical as you change things.

The repo mirrors the on-disk configuration it manages. `setup.sh` pushes the repo onto a machine (idempotent, safe to re-run); `sync.sh` pulls a machine's live config back into the repo so your changes travel.

## What it manages

| Repo path | Deploys to | Notes |
|---|---|---|
| `hypr/customconfig/bindings.lua` | `~/.config/hypr/customconfig/bindings.lua` | Whole file. Replaced with a timestamped backup when it differs. |
| `config/chromium-flags.conf` | `~/.config/chromium-flags.conf` | Wayland + keyring flags for borderless web apps. |
| `config/fish.path.line` | appended to `~/.config/fish/config.fish` | Adds `~/.local/bin` to PATH (only if absent). |
| `files/quickshell-picker/` | `~/.config/quickshell/picker/` | Wallpaper / theme-folder carousel picker + scripts. |
| `files/webapps/` | `~/.config/webapps/bin/` | Web app install / launch / focus / remove tooling. |
| *(generated)* | `Install Web App.desktop` | Launcher entry that opens the web-app install TUI. |

Hotkeys (muscle memory, defined in `bindings.lua`):
- `SUPER + CTRL + SPACE` — random wallpaper from current folder
- `SUPER + SHIFT + CTRL + SPACE` — choose folder, then random wallpaper
- `qs-webapp-install` — add a borderless web app (`chromium --app=`)

## Workflow

### Bring the repo to a machine (first time or after a pull)

```sh
git pull && ./setup.sh
```

`setup.sh` never removes anything, only installs. If a file it owns already exists it is overwritten; every overwrite of `bindings.lua` keeps a timestamped `.bak`. `--check` verifies the environment, `--install-deps` installs missing packages, `--uninstall` removes the managed files (bindings stay, restorable from `.bak`).

### Push changes from one machine to the repo

```sh
./sync.sh                 # captures live files + regenerates the single-file installers
git add -A && git commit && git push
```

The `install-src/` templates let `sync.sh` re-embed the live sources into the single-file installers under `dist/` (`qs-picker-install.sh`, `qs-webapp-install.sh`) — the shareable one-script handouts that live in this repo too — and mirrors them into `~/qs-wallpaper-picker` and `~/qs-webapp-creator` if those standalone repos are present.

### Scope and safety

- **Ours vs Noctalia's:** this repo only manages `customconfig/`, the picker, web-app tooling, chromium flags, and one PATH line. Noctalia's own `config/` tree (monitors, environment, core binds) is left machine-local, so a laptop and a gaming rig with different panels/GPUs never get clobbered.
- **Additive only:** installs packages, never purges them; backs up before replacing; your personal folders, games, and apps are untouched.
- **Last-write-wins:** whole files sync cleanly one-at-a-time. The safe rhythm is sync → commit → pull + `setup.sh` on the other machine.

## Automatic sync (`qs-loop`)

`qs-loop` is the one-command version: **`save`** captures this machine, commits, and pushes your changes; **`apply`** pulls and runs setup. **`once`** does both (save then apply) — the default.

```sh
qs-loop once      # my changes out, latest in — one swoop
```

`setup.sh` installs three systemd user units by default (`--no-auto` opts out):
- `qs-loop.timer` — runs `qs-loop once` every 10 minutes (both machines; idle ones no-op).
- `qs-apply.service` — pulls + applies at login.
- `qs-save.service` — runs a final `save` when the session ends (closes the gap between the last timer tick and shutdown).

Safety rails: never force-pushes; offline commits are pushed on the next tick; a same-file conflict aborts cleanly (your commit stays, working tree restored, nothing deleted) and asks you to reconcile manually. Logs live in `~/.local/state/qs-loop/log`; setup output in `~/.local/state/qs-loop/setup.log`.

With automation on, the repo is the source of truth: edit live files with confidence, but make sure `qs-loop save` has run (or run `./sync.sh`) before pulling on a second machine with divergent local edits.

## Layout

```
setup.sh                  # deploy: repo -> machine
sync.sh                   # capture: machine -> repo (+ installer regen)
qs-loop.sh                # one-swoop save/apply sync (installed as `qs-loop`)
systemd/                  # unit templates (timer, login apply, shutdown save)
config/                   # chromium-flags.conf, fish.path.line
hypr/customconfig/        # your bindings.lua (the whole file)
files/quickshell-picker/  # live picker sources
files/webapps/            # live web-app scripts
install-src/              # installer templates for sync.sh regen
dist/                     # regenerated single-file installers (friend handouts)
```

## Requirements

Noctalia + Hyprland (`noctalia` and `hyprctl` on PATH — `setup.sh` refuses to run otherwise). Dependencies: `quickshell libvips imagemagick ffmpegthumbnailer jq file chromium curl fzf`. Install via `./setup.sh --install-deps`.