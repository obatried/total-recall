#!/bin/bash
# total-recall: auto-filing (DISCIPLINE).
# After a memory note is written, append a one-line entry to the index named in its
# `home:` field, if not already there — so indexes stay in sync without manual upkeep.
# PostToolUse on Write/Edit/MultiEdit. Idempotent. MEMORY.md / index files / archive
# are skipped. Fails open.

set -uo pipefail
trap 'exit 0' ERR

command -v jq >/dev/null 2>&1 || exit 0
CONFIG="${TOTAL_RECALL_CONFIG:-$HOME/.config/total-recall/config}"
[ -f "$CONFIG" ] || exit 0
get_conf() { grep -E "^$1=" "$CONFIG" 2>/dev/null | tail -1 | cut -d= -f2- | sed 's/^"//;s/"$//' || true; }
MEM_DIR=$(get_conf MEM_DIR); [ -n "$MEM_DIR" ] || exit 0

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')
case "$TOOL" in Write|Edit|MultiEdit) ;; *) exit 0 ;; esac
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')
[ -z "$FILE_PATH" ] && exit 0
[ -f "$FILE_PATH" ] || exit 0
case "$FILE_PATH" in "$MEM_DIR"/*) ;; *) exit 0 ;; esac
REL="${FILE_PATH#$MEM_DIR/}"
case "$REL" in
  MEMORY.md) exit 0 ;;
  topics/*.md|projects/*.md) exit 0 ;;
  *INDEX.md) exit 0 ;;
  archive/*) exit 0 ;;
esac

HOME_FIELD=$(awk '
  BEGIN{c=0}
  /^---$/{c++; if(c==1){f=1;next} if(c==2)exit}
  f && /^home:/{sub(/^home: */,""); gsub(/"/,""); gsub(/^ */,""); gsub(/ *$/,""); print; exit}' "$FILE_PATH")
[ -z "$HOME_FIELD" ] && exit 0
# SECURITY: never append outside MEM_DIR. Reject traversal / absolute homes, require the
# home to be a declared index (Edit/MultiEdit bypass the home-required guard, so a note with
# home: ../CLAUDE.md must not be able to make us write into the user's config).
case "$HOME_FIELD" in /*|*..*) exit 0 ;; esac
ALLOWED_FILE=$(get_conf ALLOWED_INDEXES); [ -z "$ALLOWED_FILE" ] && ALLOWED_FILE="$MEM_DIR/.allowed-indexes"
[ -f "$ALLOWED_FILE" ] && { grep -qFx "$HOME_FIELD" "$ALLOWED_FILE" || exit 0; }
INDEX_FILE="$MEM_DIR/$HOME_FIELD"
case "$INDEX_FILE" in "$MEM_DIR"/*) ;; *) exit 0 ;; esac
[ -f "$INDEX_FILE" ] || exit 0

FILENAME=$(basename "$FILE_PATH")
grep -qF "$FILENAME" "$INDEX_FILE" && exit 0

DESC=$(awk 'BEGIN{c=0} /^---$/{c++; if(c==1){f=1;next} if(c==2)exit} f && /^description:/{sub(/^description: */,""); gsub(/"/,""); print; exit}' "$FILE_PATH")
NAME=$(awk 'BEGIN{c=0} /^---$/{c++; if(c==1){f=1;next} if(c==2)exit} f && /^name:/{sub(/^name: */,""); gsub(/"/,""); print; exit}' "$FILE_PATH")
[ -z "$NAME" ] && NAME="${FILENAME%.md}"
INDEX_DIR=$(dirname "$INDEX_FILE")
REL_LINK=$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1],sys.argv[2]))' "$FILE_PATH" "$INDEX_DIR" 2>/dev/null || echo "$FILENAME")

append() { grep -qF "$FILENAME" "$INDEX_FILE" || printf '\n- [%s](%s) — %s\n' "$NAME" "$REL_LINK" "$DESC" >> "$INDEX_FILE"; }
if command -v flock >/dev/null 2>&1; then
  ( flock -x 9; append ) 9>"$INDEX_FILE.lock"
else
  append   # stock macOS has no flock; single-writer append is fine
fi
exit 0
