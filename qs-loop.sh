#!/bin/bash
# qs-loop -- one swoop, both directions. Save your machine's state into the
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

# Background jobs must fail promptly instead of opening an authentication UI.
export GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never
online() { timeout 6 git -C "$REPO_DIR" ls-remote --exit-code "$REMOTE" "$MERGE_REF" >/dev/null 2>&1; }

LOCK_FD=
acquire() {
    exec {LOCK_FD}>"$LOCK" || exit 1
    flock -n "$LOCK_FD" || { log "skip: another qs-loop is running"; exit 0; }
}

require_clean() {
    local state
    state="$(git -C "$REPO_DIR" status --porcelain)" || die "cannot read repository status"
    [[ -z $state ]] || die "repository has uncommitted changes; commit or stash them before qs-loop (nothing captured or deployed)"
    local operation
    for operation in rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD; do
        [[ ! -e $(git -C "$REPO_DIR" rev-parse --path-format=absolute --git-path "$operation") ]] \
            || die "finish the current Git operation before qs-loop"
    done
}

pull_changes() {
    if ! git -C "$REPO_DIR" pull --rebase -q "$REMOTE" "$MERGE_REF"; then
        log "pull failed; preserving local commits and aborting this rebase"
        git -C "$REPO_DIR" rebase --abort 2>/dev/null || true
        die "pull failed or conflicted; not deploying. Reconcile manually."
    fi
}

save() {
    log "save: begin"
    ( cd "$REPO_DIR" && ./sync.sh ) >/dev/null 2>&1 || { log "save: sync.sh failed"; say "capture step failed"; exit 1; }
    local state
    state="$(git -C "$REPO_DIR" status --porcelain)" || die "cannot read captured changes"
    if [[ -n $state ]]; then
        git -C "$REPO_DIR" add -u || die "cannot stage captured changes"
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
    pull_changes
    if ! git -C "$REPO_DIR" push -q "$REMOTE" "HEAD:$MERGE_REF"; then
        log "save: push failed (network?), retrying next interval"
        say "push failed; retrying on the next interval"
        return 1
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
    pull_changes
    local revision applied=""
    revision="$(git -C "$REPO_DIR" rev-parse HEAD)" || die "cannot read revision"
    [[ ! -f "$STATE_DIR/applied-revision" ]] || applied="$(<"$STATE_DIR/applied-revision")"
    if [[ $MODE == once && $applied == "$REPO_DIR:$revision" ]]; then
        log "apply: revision already deployed"
        return 0
    fi
    if ! "$REPO_DIR/setup.sh" > "$STATE_DIR/setup.log" 2>&1; then
        log "apply: setup.sh failed (see $STATE_DIR/setup.log)"
        say "apply failed; see $STATE_DIR/setup.log"
        exit 1
    fi
    printf '%s:%s\n' "$REPO_DIR" "$revision" > "$STATE_DIR/applied-revision"
    log "apply: done"
}

usage() { die "usage: qs-loop [save|apply|once]"; }

git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not a git repo: $REPO_DIR"

MODE="${1:-once}"
case "$MODE" in
    save|apply|once) ;;
    *) usage ;;
esac

acquire
require_clean
BRANCH="$(git -C "$REPO_DIR" symbolic-ref --quiet --short HEAD)" || die "detached HEAD: select a tracking branch first"
REMOTE="$(git -C "$REPO_DIR" config --get "branch.$BRANCH.remote")" || die "branch has no upstream remote"
MERGE_REF="$(git -C "$REPO_DIR" config --get "branch.$BRANCH.merge")" || die "branch has no upstream branch"
[[ $REMOTE != . && $MERGE_REF == refs/heads/* ]] || die "qs-loop requires a remote tracking branch"

# Rotate while holding the lock; two instances must not race on the same log.
if [[ -f "$LOG" ]] && (( $(wc -c < "$LOG") > 524288 )); then
    tail -n 200 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi

if [[ "$MODE" = save ]]; then
    save
elif [[ "$MODE" = apply ]]; then
    apply
else
    save || exit $?
    apply
fi
