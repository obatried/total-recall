#!/bin/bash
# total-recall uninstaller. Removes the 4 hooks from settings.json (backed up first).
# Leaves your notes untouched (they were never modified). Pass --purge to also remove
# the config + index cache.
set -euo pipefail
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 1; }

if [ -f "$SETTINGS" ]; then
  SETTINGS="$SETTINGS" python3 - <<'PY'
import json, os, shutil
path=os.environ["SETTINGS"]
s=json.load(open(path))
shutil.copy(path, path+".bak-total-recall-uninstall")
removed=0
for event, arr in list(s.get("hooks",{}).items()):
    keep=[]
    for g in arr:
        cmds=json.dumps(g.get("hooks",[]))
        if "total-recall-" in cmds:
            removed+=1
        else:
            keep.append(g)
    s["hooks"][event]=keep
tmp=path+".tmp"
json.dump(s, open(tmp,"w"), indent=2)
json.load(open(tmp))  # validate before replacing
os.replace(tmp, path)
print(f"removed {removed} total-recall hook group(s) from {path}")
print(f"backup: {path}.bak-total-recall-uninstall")
PY
else
  echo "no settings.json at $SETTINGS — nothing to unwire"
fi

if [ "${1:-}" = "--purge" ]; then
  rm -rf "$HOME/.config/total-recall" "$HOME/.cache/total-recall"
  echo "purged config + index cache"
fi
echo "✓ uninstalled (your notes were never touched). Restart Claude Code."
