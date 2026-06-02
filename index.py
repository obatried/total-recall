#!/usr/bin/env python3
"""total-recall: build a read-only SQLite FTS5 index over a folder of markdown notes.

Your .md files are NEVER modified — the DB is a derived, rebuildable cache. Builds
into a temp DB then atomically renames over the target, so a concurrent search
always sees a complete index.

Config (env var overrides config file overrides default):
  MEM_DIR   directory of .md notes to index   (default: ~/notes)
  DB_PATH   where to write the index           (default: ~/.cache/total-recall/index.db)
Config file: $TOTAL_RECALL_CONFIG or ~/.config/total-recall/config  (KEY=VALUE lines)

Dependencies: Python 3 standard library only (sqlite3 with the FTS5 extension,
which ships in the SQLite bundled with CPython on macOS and most Linux builds).
"""
import sqlite3, os, glob, sys

def load_config():
    cfg = {}
    path = os.environ.get("TOTAL_RECALL_CONFIG", os.path.expanduser("~/.config/total-recall/config"))
    if os.path.exists(path):
        for line in open(path, encoding="utf-8", errors="ignore"):
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            cfg[k.strip()] = v.strip().strip('"').strip("'")
    return cfg

CFG = load_config()
def conf(key, default):
    return os.environ.get(key) or CFG.get(key) or default

MEM = os.path.expanduser(conf("MEM_DIR", "~/notes"))
DB  = os.path.expanduser(conf("DB_PATH", "~/.cache/total-recall/index.db"))

def main():
    if not os.path.isdir(MEM):
        sys.stderr.write(f"total-recall: MEM_DIR does not exist: {MEM}\n")
        return 1
    os.makedirs(os.path.dirname(DB) or ".", exist_ok=True)
    tmp = f"{DB}.tmp.{os.getpid()}"
    if os.path.exists(tmp):
        os.remove(tmp)
    con = sqlite3.connect(tmp)
    try:
        con.execute("CREATE VIRTUAL TABLE mem USING fts5(path, title, body, tokenize='porter unicode61')")
    except sqlite3.OperationalError as e:
        sys.stderr.write(f"total-recall: FTS5 not available in this SQLite build: {e}\n")
        con.close(); os.remove(tmp); return 2
    n = 0
    for f in glob.glob(os.path.join(MEM, "**", "*.md"), recursive=True):
        try:
            body = open(f, encoding="utf-8", errors="ignore").read()
        except Exception:
            continue
        rel = os.path.relpath(f, MEM)
        title = os.path.basename(f)[:-3].replace("_", " ").replace("-", " ")
        con.execute("INSERT INTO mem(path, title, body) VALUES (?,?,?)", (rel, title, body))
        n += 1
    con.commit()
    con.close()
    os.replace(tmp, DB)  # atomic on the same filesystem
    print(f"total-recall: indexed {n} files -> {DB}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
