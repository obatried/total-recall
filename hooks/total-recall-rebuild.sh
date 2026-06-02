#!/bin/bash
# total-recall: keep the read-only FTS5 index fresh.
# Wired to SessionStart (rebuild once) and PostToolUse Write/Edit/MultiEdit
# (rebuild when a write touched MEM_DIR). The rebuild NEVER edits your .md files;
# it builds a temp DB + atomic rename, so concurrent searches stay safe. Runs in
# the background under flock so it never blocks. Fails open.

set -uo pipefail
exec 2>/dev/null
trap 'exit 0' ERR

[ -n "${HOME:-}" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

CONFIG="${TOTAL_RECALL_CONFIG:-$HOME/.config/total-recall/config}"
[ -f "$CONFIG" ] || exit 0
get_conf() { grep -E "^$1=" "$CONFIG" 2>/dev/null | tail -1 | cut -d= -f2- | sed 's/^"//;s/"$//' || true; }
TR_HOME=$(get_conf TR_HOME); MEM_DIR=$(get_conf MEM_DIR)
[ -n "$TR_HOME" ] && [ -n "$MEM_DIR" ] || exit 0
INDEXER="$TR_HOME/index.py"
[ -f "$INDEXER" ] || exit 0
LOCK="${TMPDIR:-/tmp}/total-recall-rebuild.lock"

INPUT=$(cat)
EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // ""')
case "$EVENT" in
  SessionStart) : ;;
  PostToolUse)
    TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')
    case "$TOOL" in Write|Edit|MultiEdit) ;; *) exit 0 ;; esac
    FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')
    case "$FILE_PATH" in "$MEM_DIR"/*) ;; *) exit 0 ;; esac
    ;;
  *) exit 0 ;;
esac

# Background rebuild. flock serializes concurrent rebuilds when available (Linux);
# stock macOS has no flock, so we skip the lock there — index.py builds to a temp
# file + atomic rename, so concurrent rebuilds are safe regardless.
if command -v flock >/dev/null 2>&1; then
  ( flock 9; TOTAL_RECALL_CONFIG="$CONFIG" python3 "$INDEXER" >/dev/null 2>&1 ) 9>"$LOCK" &
else
  ( TOTAL_RECALL_CONFIG="$CONFIG" python3 "$INDEXER" >/dev/null 2>&1 ) &
fi
disown 2>/dev/null || true
exit 0
