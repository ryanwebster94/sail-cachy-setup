#!/bin/bash
# qs-loop -- one swoop, both directions. savey our machine's state into the
# repo, then apply the repo's state to this machine. Safe to run on an empty
# stomach: no-op when there's nothing to do, never force-pushes, never deletes
# your work on a conflict.
#
#   qs-loop save    capture -> commit -> push (deferred when offline)
#   qs-loop apply   pull -> setup.sh (deploy)
#   qs-loop once    save, then apply        [default]

set -uo pipefail

REPO_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/qs-loop"
LOG="$STATE_DIR/log"
LOCK="$STATE_DIR/lock"
mkdir -p "$STATE_DIR" || exit 1

log()  { printf '%(%F %T)T %s\n' -1 "$*" >> "$LOG"; }
say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mERR\033[0m %s\n' "$*" >&2; exit 1; }

# keep the log from growing forever
if [[ -f "$LOG" ]] && (( $(wc -c < "$LOG") > 524288 )); then
    tail -n 200 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi

online() { timeout 6 git -C "$REPO_DIR" ls-remote --exit-code origin HEAD >/dev/null 2>&1; }

LOCK_FD=
acquire() {
    exec {LOCK_FD}>"$LOCK" || exit 1
    flock -n "$LOCK_FD" || { log "skip: another qs-loop is running"; exit 0; }
}

save() {
    log "save: begin"
    ( cd "$REPO_DIR" && ./sync.sh ) >/dev/null 2>&1 || { log "save: sync.sh failed"; say "capture step failed"; exit 1; }
    if git -C "$REPO_DIR" status --porcelain | grep -q .; then
        git -C "$REPO_DIR" add -A
        git -C "$REPO_DIR" commit -q -m "sync: $(hostname) $(date '+%F %T')" \
            || { log "save: commit failed"; say "commit failed"; exit 1; }
        log "save: committed"
        say "committed local changes"
    else
        log "save: nothing to sync"
        say "nothing to sync"
    fi
    if ! online; then
        log "save: offline, push deferred"
        say "offline: last local commit will be pushed on the next interval"
        return 0
    fi
    if ! git -C "$REPO_DIR" pull --rebase --autostash -q; then
        log "save: conflict during pull, aborting (no destructive action)"
        git -C "$REPO_DIR" rebase --abort 2>/dev/null
        say "conflict while syncing: your changes are safe but unmerged. Reconcile manually."
        exit 2
    fi
    if ! git -C "$REPO_DIR" push -q origin HEAD:main; then
        log "save: push failed (network?), retrying next interval"
        say "push failed; retrying on the next interval"
        return 0
    fi
    log "save: pushed"
}

apply() {
    log "apply: begin"
    if ! online; then
        log "apply: offline, skipping"
        say "offline: skipping apply"
        return 0
    fi
    if ! git -C "$REPO_DIR" pull --rebase --autostash -q; then
        log "apply: conflict during pull, aborting (no destructive action)"
        git -C "$REPO_DIR" rebase --abort 2>/dev/null
        say "conflict while pulling: not applying. Reconcile manually."
        exit 2
    fi
    if ! "$REPO_DIR/setup.sh" >> "$STATE_DIR/setup.log" 2>&1; then
        log "apply: setup.sh failed (see $STATE_DIR/setup.log)"
        say "apply failed; see $STATE_DIR/setup.log"
        exit 1
    fi
    log "apply: done"
}

usage() { die "usage: qs-loop [save|apply|once]"; }

[[ -d "$REPO_DIR/.git" ]] || die "not a git repo: $REPO_DIR"

MODE="${1:-once}"
case "$MODE" in
    save|apply|once) ;;
    *) usage ;;
esac

acquire

if [[ "$MODE" = save ]]; then
    save
elif [[ "$MODE" = apply ]]; then
    apply
else
    save; s=$?
    (( s == 2 )) && exit 2
    apply
fi