#!/bin/bash
# total-recall installer — sets up the whole memory system, plug-and-play.
# Usage: ./install.sh /path/to/your/memory
#
# Does, in order:
#   1. creates the memory folder (seeds the starter structure if it's empty)
#   2. writes config to ~/.config/total-recall/config
#   3. builds the read-only search index
#   4. merges 5 hooks into ~/.claude/settings.json (backed up, idempotent, validated)
#   5. appends the memory-writing block to ~/.claude/CLAUDE.md (backed up, idempotent)
# Re-running is safe. Your notes are never modified by the tooling.

set -euo pipefail

TR_HOME="$(cd "$(dirname "$0")" && pwd)"
NOTES="${1:-}"
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
CLAUDEMD="${CLAUDE_MD:-$HOME/.claude/CLAUDE.md}"
CONFIG_DIR="$HOME/.config/total-recall"
CONFIG="$CONFIG_DIR/config"
DB_PATH="$HOME/.cache/total-recall/index.db"

command -v python3 >/dev/null 2>&1 || { echo "total-recall: python3 required"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "total-recall: jq required (hooks parse Claude Code JSON with it). Install jq, then re-run."; exit 1; }

if [ -z "$NOTES" ]; then
  echo "Usage: ./install.sh /path/to/your/memory"
  echo "  The folder for your notes. Created (and seeded with a starter structure) if it doesn't exist."
  echo "  A common choice: ~/.claude/memory"
  exit 1
fi

python3 - <<'PY' || { echo "total-recall: your Python's sqlite3 lacks FTS5 — see README troubleshooting"; exit 1; }
import sqlite3, sys
try: sqlite3.connect(":memory:").execute("CREATE VIRTUAL TABLE t USING fts5(x)")
except Exception: sys.exit(1)
PY

mkdir -p "$NOTES"; NOTES="$(cd "$NOTES" && pwd)"
mkdir -p "$CONFIG_DIR" "$(dirname "$DB_PATH")"

# 1. seed starter structure only if the folder is empty
if [ -z "$(ls -A "$NOTES" 2>/dev/null)" ]; then
  echo "→ seeding starter memory structure into $NOTES"
  cp -R "$TR_HOME/template/." "$NOTES/"
else
  echo "→ $NOTES already has files; using them as-is (not seeding the template)"
fi

# allowed-indexes manifest (valid `home:` targets). Seed from existing indexes if absent.
ALLOWED="$NOTES/.allowed-indexes"
if [ ! -f "$ALLOWED" ]; then
  { echo "MEMORY.md"; ( cd "$NOTES" && for f in topics/*.md projects/*.md; do [ -f "$f" ] && echo "$f"; done ); } > "$ALLOWED"
  echo "→ wrote index manifest: $ALLOWED"
fi

# synonym map (optional, empty by default) for alias-expanded search
ALIASES_FILE="$NOTES/.aliases"
if [ ! -f "$ALIASES_FILE" ]; then
  cat > "$ALIASES_FILE" <<'EOF'
# Synonym groups, one per line (comma-separated). A query term in a group also searches
# the other members, bridging the "different words, same meaning" gap that keyword search
# can't. Edit/extend freely. Examples:
# car, automobile, vehicle
# pay, payment, billing, invoice
EOF
fi

# 2. config
echo "→ writing config: $CONFIG"
cat > "$CONFIG" <<EOF
# total-recall config (KEY=VALUE). Env vars override these at runtime.
TR_HOME="$TR_HOME"
MEM_DIR="$NOTES"
DB_PATH="$DB_PATH"
ALLOWED_INDEXES="$ALLOWED"
ALIASES="$NOTES/.aliases"

# --- write discipline ---
# ENFORCE_HOME=0      # set to 0 to stop requiring a 'home:' field on new notes
# --- recall tuning (UserPromptSubmit) ---
# RECALL_AVG=-3.0
# RECALL_STRONG=-18
# RECALL_RATIO=0.5
# RECALL_CAP=6
# INDEX_FILE=MEMORY.md   # a note that's always loaded; never recall / dedup-check it
# --- dedup tuning (PreToolUse Write) ---
# DEDUP_STRONG=-18
# DEDUP_RATIO=0.6
EOF

# 3. build index
echo "→ building index over: $NOTES"
TOTAL_RECALL_CONFIG="$CONFIG" python3 "$TR_HOME/index.py"

# 4. merge hooks
echo "→ merging hooks into: $SETTINGS"
TR_HOME="$TR_HOME" SETTINGS="$SETTINGS" python3 - <<'PY'
import json, os, shutil, sys, shlex, time
tr   = os.environ["TR_HOME"]; path = os.environ["SETTINGS"]
h = os.path.join(tr, "hooks")
def q(name): return shlex.quote(os.path.join(h, name))
REBUILD, RECALL, DEDUP = q("total-recall-rebuild.sh"), q("total-recall-recall.sh"), q("total-recall-dedup.sh")
HOMEREQ, AUTOIDX = q("memory-home-required.sh"), q("memory-autoindex.sh")

settings = {}
if os.path.exists(path):
    try: settings = json.load(open(path))
    except Exception as e:
        print(f"  ! {path} is not valid JSON ({e}); aborting to avoid damage"); sys.exit(1)
    bak = f"{path}.bak-total-recall-{time.strftime('%Y%m%d-%H%M%S')}"
    shutil.copy(path, bak); print(f"  backed up -> {bak}")
else:
    os.makedirs(os.path.dirname(path), exist_ok=True)

H = settings.setdefault("hooks", {})
def add(event, group):
    cmd = group["hooks"][0]["command"]; arr = H.setdefault(event, [])
    if cmd in json.dumps(arr): print(f"  = {event}: already wired"); return
    arr.append(group); print(f"  + {event}: {os.path.basename(cmd.strip(chr(39)))}")

add("SessionStart",     {"hooks":[{"type":"command","command":REBUILD,"timeout":10}]})
add("PostToolUse",      {"matcher":"Write|Edit|MultiEdit","hooks":[{"type":"command","command":REBUILD,"timeout":10}]})
add("PostToolUse",      {"matcher":"Write|Edit|MultiEdit","hooks":[{"type":"command","command":AUTOIDX,"timeout":10}]})
add("PreToolUse",       {"matcher":"Write","hooks":[{"type":"command","command":DEDUP,"timeout":5}]})
add("PreToolUse",       {"matcher":"Write","hooks":[{"type":"command","command":HOMEREQ,"timeout":5}]})
add("UserPromptSubmit", {"hooks":[{"type":"command","command":RECALL,"timeout":10}]})

tmp = path + ".tmp"; json.dump(settings, open(tmp,"w"), indent=2); json.load(open(tmp)); os.replace(tmp, path)
print("  settings.json updated + validated")
PY

# 5. CLAUDE.md memory block (idempotent, backed up). Done in Python so path-fill is robust
# (handles & | ' in the path), the marker check is exact, and the backup is timestamped.
echo "→ memory-writing block for CLAUDE.md"
SRC="$TR_HOME/claude-memory.md" CLAUDEMD="$CLAUDEMD" NOTES="$NOTES" python3 - <<'PY'
import os, re, time, shutil
src=os.environ["SRC"]; dst=os.environ["CLAUDEMD"]; mem=os.environ["NOTES"]
OPEN="<!-- total-recall:memory-block -->"; CLOSE="<!-- /total-recall:memory-block -->"
raw=open(src).read()
raw=re.sub(r"^<!--.*?-->\s*", "", raw, count=1, flags=re.S)   # strip the leading doc comment
block=raw.replace("<MEM_DIR>", mem).strip("\n")
cur=open(dst).read() if os.path.exists(dst) else ""
if OPEN in cur:
    print(f"  = already present in {dst}")
else:
    os.makedirs(os.path.dirname(dst) or ".", exist_ok=True)
    if os.path.exists(dst):
        bak=f"{dst}.bak-total-recall-{time.strftime('%Y%m%d-%H%M%S')}"
        shutil.copy(dst, bak); note=f" (backup: {bak})"
    else:
        note=""
    sep="" if (not cur or cur.endswith("\n")) else "\n"
    open(dst,"a").write(f"{sep}\n{OPEN}\n{block}\n{CLOSE}\n")
    print(f"  + appended to {dst}{note}")
PY

chmod +x "$TR_HOME/hooks/"*.sh "$TR_HOME/index.py" "$TR_HOME/search.py" "$TR_HOME/total-recall" 2>/dev/null || true

echo ""
echo "✓ total-recall memory system installed."
echo "  memory:  $NOTES"
echo "  config:  $CONFIG"
echo "  try it:  $TR_HOME/total-recall \"something in your notes\""
echo ""
echo "  RESTART Claude Code (hooks + CLAUDE.md load at session start) to go live."
