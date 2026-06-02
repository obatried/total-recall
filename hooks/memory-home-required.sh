#!/bin/bash
# total-recall: write-discipline guard (DISCIPLINE).
# Blocks creating a memory leaf note that lacks a valid `home:` frontmatter field
# (which index it belongs to). This is what keeps a growing collection navigable:
# every fact declares where it's filed. Pairs with memory-autoindex.sh (which then
# auto-files it). PreToolUse on Write. MEMORY.md / index files / archive are exempt.
# Set ENFORCE_HOME=0 in config to turn this off. Fails open.

set -uo pipefail
trap 'exit 0' ERR

command -v jq >/dev/null 2>&1 || exit 0
CONFIG="${TOTAL_RECALL_CONFIG:-$HOME/.config/total-recall/config}"
[ -f "$CONFIG" ] || exit 0
get_conf() { grep -E "^$1=" "$CONFIG" 2>/dev/null | tail -1 | cut -d= -f2- | sed 's/^"//;s/"$//' || true; }
MEM_DIR=$(get_conf MEM_DIR); [ -n "$MEM_DIR" ] || exit 0
[ "$(get_conf ENFORCE_HOME)" = "0" ] && exit 0

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')
[ "$TOOL" = "Write" ] || exit 0
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')
[ -z "$FILE_PATH" ] && exit 0
case "$FILE_PATH" in "$MEM_DIR"/*) ;; *) exit 0 ;; esac
case "$FILE_PATH" in *.md) ;; *) exit 0 ;; esac
[ -f "$FILE_PATH" ] && exit 0   # only guard NEW notes; never block overwriting an existing file
REL="${FILE_PATH#$MEM_DIR/}"
case "$REL" in
  MEMORY.md) exit 0 ;;
  topics/*.md|projects/*.md) exit 0 ;;
  *INDEX.md) exit 0 ;;
  archive/*) exit 0 ;;
esac

CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // ""')
[ -z "$CONTENT" ] && exit 0
ALLOWED_FILE=$(get_conf ALLOWED_INDEXES); [ -z "$ALLOWED_FILE" ] && ALLOWED_FILE="$MEM_DIR/.allowed-indexes"
[ -f "$ALLOWED_FILE" ] || exit 0

HOME_FIELD=$(printf '%s' "$CONTENT" | awk '
  BEGIN{c=0}
  /^---$/{c++; if(c==1){f=1;next} if(c==2)exit}
  f && /^home:/{sub(/^home: */,""); gsub(/"/,""); gsub(/^ */,""); gsub(/ *$/,""); print; exit}')
ALLOWED_LIST=$(tr '\n' ',' < "$ALLOWED_FILE" | sed 's/,$//;s/,/, /g')

emit_deny() { jq -nc --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'; }

if [ -z "$HOME_FIELD" ]; then
  emit_deny "Memory note '$REL' is missing a 'home:' field. Every note declares which index it belongs to so it stays findable. Add to frontmatter:

home: <index-file>

Known indexes: $ALLOWED_LIST
(If this needs a new index/domain, add it to $ALLOWED_FILE first.)"
  exit 0
fi
if ! grep -qFx "$HOME_FIELD" "$ALLOWED_FILE"; then
  emit_deny "Memory note '$REL' has home: '$HOME_FIELD', which isn't a known index.

Known indexes: $ALLOWED_LIST
To add a new one, append it to $ALLOWED_FILE."
  exit 0
fi
exit 0
