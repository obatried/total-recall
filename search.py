#!/usr/bin/env python3
"""total-recall: ranked keyword search over the FTS5 note index (read-only / BM25).

Usage:
  search.py "natural language query" [N]        human output (score + snippet)
  search.py --tsv "query" [N]                    machine output for hooks:
                                                 score<TAB>nmatched<TAB>nterms<TAB>path

Ranking is SQLite FTS5 BM25 (title weighted 5x over body); lower score = better.
"nmatched" = how many DISTINCT query terms actually hit the doc ("coordination").
BM25 ranks by raw strength, which a single rare term can dominate — coordination
lets callers require a real topical match (several terms), not one lucky word.

Config: DB_PATH (env > config file > default ~/.cache/total-recall/index.db).
"""
import sqlite3, os, sys, re

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
DB = os.path.expanduser(os.environ.get("DB_PATH") or CFG.get("DB_PATH") or "~/.cache/total-recall/index.db")

STOP = {"the","a","an","how","do","i","to","is","of","for","and","my","in","on","with",
        "what","can","me","you","it","that","this","be","or","at","from","are","we"}

def main():
    args = sys.argv[1:]
    tsv = "--tsv" in args
    args = [a for a in args if a != "--tsv"]
    limit = 8
    if args and args[-1].isdigit():
        limit = int(args[-1]); args = args[:-1]
    q = " ".join(args)
    terms = [t for t in re.findall(r"[a-z0-9]+", q.lower()) if t not in STOP and len(t) > 1]
    terms = list(dict.fromkeys(terms))  # distinct, order-preserving (nmatched/nterms count distinct terms)
    if not terms:
        if not tsv: print("total-recall: no usable query terms")
        return 1
    match = " OR ".join(terms)

    if not os.path.exists(DB):
        if not tsv: print(f"total-recall: index not found at {DB} — run index.py first")
        return 1
    con = sqlite3.connect(DB)
    try:
        rows = con.execute(
            "SELECT rowid, path, snippet(mem,2,'»','«','…',14), bm25(mem, 1.0, 5.0, 1.0) AS s "
            "FROM mem WHERE mem MATCH ? ORDER BY s LIMIT ?", (match, limit)).fetchall()
    except sqlite3.OperationalError as e:
        if not tsv: print("total-recall: index/query error — rebuild with index.py:", e)
        return 1

    if not rows:
        if not tsv: print(f"(no matches for: {match})")
        return 0

    if tsv:
        # Coordination: distinct query terms hitting each candidate (FTS stems, so
        # this stays consistent with ranking). Output: score nmatched nterms path
        hits = {}
        for t in terms:
            try:
                for (rid,) in con.execute("SELECT rowid FROM mem WHERE mem MATCH ?", (t,)):
                    hits[rid] = hits.get(rid, 0) + 1
            except sqlite3.OperationalError:
                continue
        for rid, path, snip, score in rows:
            print(f"{score:.2f}\t{hits.get(rid,0)}\t{len(terms)}\t{path}")
        return 0

    for rid, path, snip, score in rows:
        print(f"{score:7.2f}  {path}")
        print(f"         {' '.join(snip.split())[:150]}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
