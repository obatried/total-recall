#!/bin/bash
# total-recall: dedup write-guard (PreToolUse Write, SOFT).
# Before creating a NEW note that strongly overlaps an existing one, DENY once with
# a pointer ("edit X instead") — the fix for "wrote it once, then wrote it again."
# Deny-ONCE-then-allow: the first attempt to create a given new file is denied; if
# you decide it's genuinely distinct and re-issue the same Write, it passes. So this
# warns, it never hard-locks. Fails open. Only fires on Write to a NEW .md in MEM_DIR.

set -uo pipefail
trap 'exit 0' ERR

command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

CONFIG="${TOTAL_RECALL_CONFIG:-$HOME/.config/total-recall/config}"
[ -f "$CONFIG" ] || exit 0
get_conf() { grep -E "^$1=" "$CONFIG" 2>/dev/null | tail -1 | cut -d= -f2- | sed 's/^"//;s/"$//' || true; }
TR_HOME=$(get_conf TR_HOME); MEM_DIR=$(get_conf MEM_DIR)
[ -n "$TR_HOME" ] && [ -n "$MEM_DIR" ] || exit 0
SEARCH="$TR_HOME/search.py"
[ -f "$SEARCH" ] || exit 0

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')
[ "$TOOL" = "Write" ] || exit 0
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')
[ -z "$FILE_PATH" ] && exit 0
case "$FILE_PATH" in "$MEM_DIR"/*) ;; *) exit 0 ;; esac
case "$FILE_PATH" in *.md) ;; *) exit 0 ;; esac
[ -f "$FILE_PATH" ] && exit 0   # overwrite of an existing file is not a duplicate
REL="${FILE_PATH#$MEM_DIR/}"
INDEX_FILE=$(get_conf INDEX_FILE)
[ -n "$INDEX_FILE" ] && [ "$REL" = "$INDEX_FILE" ] && exit 0

CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // ""')
[ -z "$CONTENT" ] && exit 0
# Query = the new note's most topical terms: name/description frontmatter, else the
# first heading + filename.
QUERY=$(printf '%s' "$CONTENT" | awk '
  BEGIN{c=0}
  /^---$/{c++; if(c==2)exit; next}
  c==1 && /^name:/{v=$0; sub(/^name: */,"",v); gsub(/"/,"",v); printf "%s ", v}
  c==1 && /^description:/{v=$0; sub(/^description: */,"",v); gsub(/"/,"",v); printf "%s ", v}
')
if [ -z "${QUERY// /}" ]; then
  HEAD=$(printf '%s' "$CONTENT" | grep -m1 '^#\{1,6\} ' | sed 's/^#\{1,6\} *//' || true)
  QUERY="$(basename "$REL" .md | tr '_-' '  ') $HEAD"
fi
[ -z "${QUERY// /}" ] && exit 0

# Real dup signal is COORDINATION RATIO: a genuine dup covers most of the new note's
# terms (~0.9); a novel note shares only incidental words (~0.15-0.3).
STRONG=$(get_conf DEDUP_STRONG); STRONG="${STRONG:--18}"
RATIO=$(get_conf DEDUP_RATIO);   RATIO="${RATIO:-0.6}"
HIT=$(TOTAL_RECALL_CONFIG="$CONFIG" python3 "$SEARCH" --tsv "$QUERY" 5 2>/dev/null | awk -F'\t' \
  -v strong="$STRONG" -v ratio="$RATIO" -v idx="$INDEX_FILE" '
  NF>=4 {
    s=$1+0; m=$2+0; tot=$3+0; p=$4;
    if (idx != "" && p == idx) next;
    r=(tot>0)? m/tot : 0;
    if (m>=4 && s<=strong && r>=ratio) { print p; exit }
  }')
[ -z "$HIT" ] && exit 0

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"')
SAFE_SID=$(printf '%s' "$SESSION_ID" | tr -cs 'A-Za-z0-9._-' '_'); [ -z "$SAFE_SID" ] && SAFE_SID="unknown"
SAFE_REL=$(printf '%s' "$REL" | tr -cs 'A-Za-z0-9._-' '_')   # full rel path, not just basename
STATE_DIR="$HOME/.cache/total-recall"; mkdir -p "$STATE_DIR" 2>/dev/null || true
THROTTLE="$STATE_DIR/dedup-${SAFE_SID}-${SAFE_REL}"
[ -f "$THROTTLE" ] && exit 0   # already warned once this session — let the deliberate retry through
date -u +%Y-%m-%dT%H:%M:%SZ > "$THROTTLE" 2>/dev/null || true

HIT_DESC=$(awk 'BEGIN{c=0} /^---$/{c++; if(c==2)exit; next} c==1 && /^description:/{sub(/^description: */,""); gsub(/"/,""); print; exit}' "$MEM_DIR/$HIT" 2>/dev/null)
REASON="DEDUP CHECK — a note on this topic may already exist:

  → $HIT
    $HIT_DESC

You're about to create a NEW file '$REL'. Prefer EDITING the existing note above. If '$REL' is genuinely distinct, re-issue the same Write and it will go through — this check fires once per file per session."
jq -nc --arg r "$REASON" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
