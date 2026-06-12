#!/usr/bin/env bash
# meta-install.sh — "give your AI a memory" in one command.
# Installs total-recall (the memory) + recursive-learn (the /learn loop) together.
#
# Usage: ./meta-install.sh [/path/to/your/memory]
#   Memory folder defaults to ~/.claude/memory (created + seeded if empty).
#
# recursive-learn is used from a sibling ../recursive-learn if present,
# otherwise cloned to a temp dir for the install.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOTES="${1:-$HOME/.claude/memory}"

echo "==> 1/2  total-recall — the memory (CLAUDE.md + MEMORY.md + search)…"
bash "$HERE/install.sh" "$NOTES"

echo
echo "==> 2/2  recursive-learn — the /learn self-correcting loop…"
RL="$HERE/../recursive-learn"
TMP=""
if [ ! -f "$RL/install.sh" ]; then
  command -v git >/dev/null 2>&1 || {
    echo "  ! git not found, and ../recursive-learn isn't a sibling folder."
    echo "    Clone it next to total-recall, or install it separately:"
    echo "    https://github.com/obatried/recursive-learn"
    exit 1
  }
  TMP="$(mktemp -d)"
  RL="$TMP/recursive-learn"
  git clone --depth 1 https://github.com/obatried/recursive-learn.git "$RL"
fi
bash "$RL/install.sh"
[ -n "$TMP" ] && rm -rf "$TMP" 2>/dev/null || true

echo
echo "✓ Done. Your AI now has a memory AND a /learn loop."
echo "  RESTART Claude Code to load the hooks + CLAUDE.md."
