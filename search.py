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
MEM = os.path.expanduser(os.environ.get("MEM_DIR") or CFG.get("MEM_DIR") or "~/notes")
ALIASES = os.path.expanduser(os.environ.get("ALIASES") or CFG.get("ALIASES") or os.path.join(MEM, ".aliases"))

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

    # Alias expansion: a query term in a synonym group also searches the other members,
    # and counts as ONE matched concept if any member hits (bridges the synonym gap).
    # Tokens only (alnum) so aliases can't inject FTS5 MATCH syntax.
    groups = []
    try:
        for line in open(ALIASES, encoding="utf-8", errors="ignore"):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            g = {tok for tok in re.findall(r"[a-z0-9]+", line.lower()) if len(tok) > 1}
            if len(g) > 1:
                groups.append(g)
    except (FileNotFoundError, OSError):
        pass
    def expand(t):
        for g in groups:
            if t in g:
                return g
        return {t}
    concepts, _seen = [], set()
    for t in terms:
        s = expand(t); key = frozenset(s)
        if key in _seen:
            continue
        _seen.add(key); concepts.append((t, s))
    all_terms = sorted({x for _, s in concepts for x in s})
    match = " OR ".join(all_terms)

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
        # Coordination by CONCEPT: a concept counts as matched if ANY alias term hits.
        term_hits = {}
        for t in all_terms:
            try:
                term_hits[t] = {rid for (rid,) in con.execute("SELECT rowid FROM mem WHERE mem MATCH ?", (t,))}
            except sqlite3.OperationalError:
                term_hits[t] = set()
        for rid, path, snip, score in rows:
            nmatched = sum(1 for _, s in concepts if any(rid in term_hits.get(x, ()) for x in s))
            print(f"{score:.2f}\t{nmatched}\t{len(concepts)}\t{path}")
        return 0

    for rid, path, snip, score in rows:
        print(f"{score:7.2f}  {path}")
        print(f"         {' '.join(snip.split())[:150]}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
