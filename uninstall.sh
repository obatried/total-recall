#!/bin/bash
# total-recall uninstaller. Removes the hooks from settings.json and the memory block
# from CLAUDE.md (both backed up first). Leaves your notes untouched. Pass --purge to
# also remove the config + index cache.
set -euo pipefail
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
CLAUDEMD="${CLAUDE_MD:-$HOME/.claude/CLAUDE.md}"
CONFIG="${TOTAL_RECALL_CONFIG:-$HOME/.config/total-recall/config}"
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 1; }

TR_HOME=""
[ -f "$CONFIG" ] && TR_HOME=$(grep -E '^TR_HOME=' "$CONFIG" 2>/dev/null | tail -1 | cut -d= -f2- | sed 's/^"//;s/"$//' || true)

# remove hooks
if [ -f "$SETTINGS" ]; then
  SETTINGS="$SETTINGS" TR_HOME="$TR_HOME" python3 - <<'PY'
import json, os, shutil
path=os.environ["SETTINGS"]; tr=os.environ.get("TR_HOME","")
s=json.load(open(path)); shutil.copy(path, path+".bak-total-recall-uninstall")
ours=["total-recall-rebuild.sh","total-recall-recall.sh","total-recall-dedup.sh",
      "memory-home-required.sh","memory-autoindex.sh"]
def is_ours(group):
    c=json.dumps(group.get("hooks",[]))
    if tr and (tr+"/hooks") in c: return True
    return any(name in c for name in ours)
removed=0
for event, arr in list(s.get("hooks",{}).items()):
    keep=[g for g in arr if not is_ours(g)]
    removed += len(arr)-len(keep); s["hooks"][event]=keep
tmp=path+".tmp"; json.dump(s, open(tmp,"w"), indent=2); json.load(open(tmp)); os.replace(tmp,path)
print(f"removed {removed} hook group(s) from {path} (backup: {path}.bak-total-recall-uninstall)")
PY
else
  echo "no settings.json at $SETTINGS"
fi

# remove CLAUDE.md block
if [ -f "$CLAUDEMD" ] && grep -qF "total-recall:memory-block" "$CLAUDEMD"; then
  cp "$CLAUDEMD" "$CLAUDEMD.bak-total-recall-uninstall"
  python3 - "$CLAUDEMD" <<'PY'
import sys, re
p=sys.argv[1]; t=open(p).read()
t=re.sub(r"\n?<!-- total-recall:memory-block -->.*?<!-- /total-recall:memory-block -->\n?", "\n", t, flags=re.S)
open(p,"w").write(t)
print(f"removed memory block from {p} (backup: {p}.bak-total-recall-uninstall)")
PY
fi

if [ "${1:-}" = "--purge" ]; then
  rm -rf "$HOME/.config/total-recall" "$HOME/.cache/total-recall"
  echo "purged config + index cache"
fi
echo "✓ uninstalled (your notes were never touched). Restart Claude Code."
