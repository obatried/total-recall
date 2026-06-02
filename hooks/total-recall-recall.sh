#!/bin/bash
# total-recall: proactive recall (UserPromptSubmit, SOFT).
# Searches your notes for the prompt and injects up to 2 one-line pointers when
# there's a confident match — so a relevant note surfaces at point-of-need instead
# of being forgotten. PRECISION first (context pollution is as bad as silence), via:
#   1. a two-path score gate (tuned defaults below)
#   2. once-per-file-per-session throttle (a focused session lexically matches its
#      project's notes every turn — surface each note ONCE, never repeat)
#   3. per-session cap + max 2 per prompt
# Informational only — never blocks. Fails open.
#
# Gate (fire if EITHER), over "score<TAB>nmatched<TAB>nterms<TAB>path":
#   A: nmatched>=3 AND score/nmatched <= RECALL_AVG       (distinctive rare-term match)
#   B: score<=RECALL_STRONG AND nmatched>=6 AND nmatched/nterms>=RECALL_RATIO
# All thresholds are config/env tunable (see README).

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
SEARCH="$TR_HOME/search.py"
[ -f "$SEARCH" ] || exit 0

AVG=$(get_conf RECALL_AVG);     AVG="${AVG:--3.0}"
STRONG=$(get_conf RECALL_STRONG); STRONG="${STRONG:--18}"
RATIO=$(get_conf RECALL_RATIO);   RATIO="${RATIO:-0.5}"
CAP=$(get_conf RECALL_CAP);       CAP="${CAP:-6}"
INDEX_FILE=$(get_conf INDEX_FILE)  # optional: a note that's always loaded, never worth recalling

INPUT=$(cat)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // ""')
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"')
[ -z "$PROMPT" ] && exit 0
case "$PROMPT" in '/'*|'<'*|'#'*) exit 0 ;; esac
[ "${#PROMPT}" -lt 12 ] && exit 0

TSV=$(TOTAL_RECALL_CONFIG="$CONFIG" python3 "$SEARCH" --tsv "$PROMPT" 5 2>/dev/null)
CANDS=$(printf '%s\n' "$TSV" | awk -F'\t' \
  -v avg="$AVG" -v strong="$STRONG" -v ratio="$RATIO" -v idx="$INDEX_FILE" '
  NF>=4 {
    s=$1+0; m=$2+0; tot=$3+0; p=$4;
    if (idx != "" && p == idx) next;
    a=(m>0)? s/m : 0; r=(tot>0)? m/tot : 0;
    if ((m>=3 && a<=avg) || (s<=strong && m>=6 && r>=ratio)) print p;
  }')
if [ -z "$CANDS" ]; then
  # Near-miss logging: the gate surfaced nothing, but a plausibly-relevant candidate
  # existed (loose raw-score floor) — the cases aliases/embeddings might fix. Logged to a
  # separate file for review, never injected into context. Skip true no-matches.
  TOP=$(printf '%s\n' "$TSV" | awk -F'\t' 'NR==1{print; exit}')
  if [ -n "$TOP" ]; then
    TS=$(printf '%s' "$TOP" | cut -f1); TM=$(printf '%s' "$TOP" | cut -f2)
    TT=$(printf '%s' "$TOP" | cut -f3); TP=$(printf '%s' "$TOP" | cut -f4)
    if [ -n "$TP" ] && awk -v s="$TS" 'BEGIN{exit !((s+0)<=-8)}'; then
      MISS="$HOME/.cache/total-recall/recall-misses.jsonl"; mkdir -p "$(dirname "$MISS")" 2>/dev/null || true
      jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg pr "${PROMPT:0:160}" --arg p "$TP" \
         --argjson s "${TS:-0}" --argjson m "${TM:-0}" --argjson tot "${TT:-0}" \
         '{ts:$ts,prompt:$pr,top_candidate:$p,score:$s,nmatched:$m,nterms:$tot}' >> "$MISS" 2>/dev/null || true
    fi
  fi
  exit 0
fi

SAFE_SID=$(printf '%s' "$SESSION_ID" | tr -cs 'A-Za-z0-9._-' '_'); [ -z "$SAFE_SID" ] && SAFE_SID="unknown"
STATE_DIR="$HOME/.cache/total-recall"; mkdir -p "$STATE_DIR" 2>/dev/null || true
SEEN_FILE="$STATE_DIR/recall-$SAFE_SID.seen"; touch "$SEEN_FILE" 2>/dev/null || true
SEEN_COUNT=$(grep -c . "$SEEN_FILE" 2>/dev/null || true); SEEN_COUNT=${SEEN_COUNT:-0}

label_of() {  # $1 = abs path -> description / first heading / humanized filename
  local d
  d=$(awk 'BEGIN{c=0} /^---$/{c++; if(c==2)exit; next} c==1 && /^description:/{sub(/^description: */,""); gsub(/"/,""); print; exit}' "$1" 2>/dev/null)
  [ -z "$d" ] && d=$(grep -m1 '^#\{1,6\} ' "$1" 2>/dev/null | sed 's/^#\{1,6\} *//' || true)
  [ -z "$d" ] && d=$(basename "$1" .md | tr '_-' '  ')
  printf '%.140s' "$d"
}

LINES=""; EMITTED=0
while IFS= read -r rel; do
  [ -z "$rel" ] && continue
  [ "$EMITTED" -ge 2 ] && break
  [ "$SEEN_COUNT" -ge "$CAP" ] && break
  grep -qxF "$rel" "$SEEN_FILE" 2>/dev/null && continue
  abs="$MEM_DIR/$rel"; [ -f "$abs" ] || continue
  LINES="${LINES}• ${rel} — $(label_of "$abs")"$'\n'
  printf '%s\n' "$rel" >> "$SEEN_FILE"
  # usage log (for the staleness report): which note got surfaced, when. Read-only re: notes.
  jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg p "$rel" '{ts:$ts,note:$p}' \
     >> "$STATE_DIR/recall-usage.jsonl" 2>/dev/null || true
  EMITTED=$((EMITTED+1)); SEEN_COUNT=$((SEEN_COUNT+1))
done <<< "$CANDS"
[ "$EMITTED" -eq 0 ] && exit 0

MSG="[MEMORY RECALL — soft] Possibly-relevant existing notes for this prompt (read before improvising or creating a new one):
${LINES}Keyword-search pointers, not certainties — skip any that don't fit. Shown once per file per session."
jq -nc --arg m "$MSG" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$m}}'
exit 0
