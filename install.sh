#!/bin/bash
# total-recall installer.
# Usage: ./install.sh /path/to/your/markdown/notes
#
# - writes config to ~/.config/total-recall/config
# - builds the initial read-only index
# - merges 4 hooks into ~/.claude/settings.json (backed up first, idempotent,
#   validated; never clobbers your existing hooks)
# Re-running is safe: already-installed hooks are skipped.

set -euo pipefail

TR_HOME="$(cd "$(dirname "$0")" && pwd)"
NOTES="${1:-}"
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
CONFIG_DIR="$HOME/.config/total-recall"
CONFIG="$CONFIG_DIR/config"
DB_PATH="$HOME/.cache/total-recall/index.db"

command -v python3 >/dev/null 2>&1 || { echo "total-recall: python3 required"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "total-recall: jq required — the hooks parse Claude Code's JSON with it. Install jq, then re-run."; exit 1; }

if [ -z "$NOTES" ]; then
  echo "Usage: ./install.sh /path/to/your/markdown/notes"
  echo "  (the folder of .md files you want searchable — e.g. your Claude Code memory dir)"
  exit 1
fi
NOTES="$(cd "$NOTES" 2>/dev/null && pwd || true)"
[ -n "$NOTES" ] && [ -d "$NOTES" ] || { echo "total-recall: notes dir not found: ${1}"; exit 1; }

# FTS5 availability check (the one hard requirement beyond stdlib).
python3 - <<'PY' || { echo "total-recall: your Python's sqlite3 lacks FTS5 — see README troubleshooting"; exit 1; }
import sqlite3, sys
c=sqlite3.connect(":memory:")
try: c.execute("CREATE VIRTUAL TABLE t USING fts5(x)")
except Exception: sys.exit(1)
PY

echo "→ writing config: $CONFIG"
mkdir -p "$CONFIG_DIR" "$(dirname "$DB_PATH")"
cat > "$CONFIG" <<EOF
# total-recall config (KEY=VALUE). Env vars override these at runtime.
TR_HOME="$TR_HOME"
MEM_DIR="$NOTES"
DB_PATH="$DB_PATH"

# --- recall tuning (UserPromptSubmit) ---
# RECALL_AVG=-3.0       # path A: fire if score/nmatched <= this (distinctive match)
# RECALL_STRONG=-18     # path B: fire if score <= this ...
# RECALL_RATIO=0.5      #         ... AND nmatched/nterms >= this AND nmatched>=6
# RECALL_CAP=6          # max distinct notes surfaced per session
# --- dedup tuning (PreToolUse Write) ---
# DEDUP_STRONG=-18      # deny new file if best match score <= this ...
# DEDUP_RATIO=0.6       #         ... AND covers >= this fraction of the new file's terms
# --- optional ---
# INDEX_FILE=MEMORY.md  # a note that's always loaded; never recall it / dedup-check against it
EOF

echo "→ building initial index over: $NOTES"
TOTAL_RECALL_CONFIG="$CONFIG" python3 "$TR_HOME/index.py"

echo "→ merging hooks into: $SETTINGS"
TR_HOME="$TR_HOME" SETTINGS="$SETTINGS" python3 - <<'PY'
import json, os, shutil, sys, shlex
tr   = os.environ["TR_HOME"]
path = os.environ["SETTINGS"]
hooks_dir = os.path.join(tr, "hooks")
# shell-quote so a clone path containing spaces still executes correctly as a hook command
REBUILD = shlex.quote(os.path.join(hooks_dir, "total-recall-rebuild.sh"))
RECALL  = shlex.quote(os.path.join(hooks_dir, "total-recall-recall.sh"))
DEDUP   = shlex.quote(os.path.join(hooks_dir, "total-recall-dedup.sh"))

settings = {}
if os.path.exists(path):
    with open(path) as f:
        try: settings = json.load(f)
        except Exception as e:
            print(f"  ! {path} is not valid JSON ({e}); aborting to avoid damage"); sys.exit(1)
    shutil.copy(path, path + ".bak-total-recall")
    print(f"  backed up -> {path}.bak-total-recall")
else:
    os.makedirs(os.path.dirname(path), exist_ok=True)

H = settings.setdefault("hooks", {})
present = json.dumps(settings)

def add(event, group):
    cmd = group["hooks"][0]["command"]
    arr = H.setdefault(event, [])
    if cmd in json.dumps(arr):
        print(f"  = {event}: already wired ({os.path.basename(cmd)})"); return
    arr.append(group); print(f"  + {event}: added {os.path.basename(cmd)}")

add("SessionStart",    {"hooks":[{"type":"command","command":REBUILD,"timeout":10}]})
add("PostToolUse",     {"matcher":"Write|Edit|MultiEdit","hooks":[{"type":"command","command":REBUILD,"timeout":10}]})
add("PreToolUse",      {"matcher":"Write","hooks":[{"type":"command","command":DEDUP,"timeout":5}]})
add("UserPromptSubmit",{"hooks":[{"type":"command","command":RECALL,"timeout":10}]})

tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(settings, f, indent=2)
json.load(open(tmp))  # validate
os.replace(tmp, path)
print("  settings.json updated + validated")
PY

chmod +x "$TR_HOME/hooks/"*.sh "$TR_HOME/index.py" "$TR_HOME/search.py" "$TR_HOME/total-recall" 2>/dev/null || true

echo ""
echo "✓ total-recall installed."
echo "  notes:  $NOTES"
echo "  config: $CONFIG"
echo "  try it: $TR_HOME/total-recall \"some topic in your notes\""
echo ""
echo "  RESTART Claude Code (hooks load at session start) for recall/dedup to go live."
