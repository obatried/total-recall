# total-recall

**Proactive keyword search for your Claude Code memory — so the note you already wrote actually shows up when you need it.**

You keep notes in markdown. Claude Code can *write* them well. The problem is **retrieval**: at the moment a relevant runbook or preference matters, nobody goes and reads it — so you re-derive it, or worse, write a second copy. total-recall closes that gap with a **read-only full-text index** over your notes and three small hooks that put the right file in front of you automatically.

It is deliberately boring: **SQLite FTS5 + BM25**, the 30-year-old ranking algorithm behind most search engines, already built into the Python on your machine. No embeddings, no vector DB, no API key, no model download, no daemon. **It never modifies your notes** — the index is a throwaway cache it rebuilds from your files.

---

## What you get

Point it at a folder of `.md` files and you get:

1. **Proactive recall** — on every prompt, it searches your notes and, *only when there's a confident match*, injects 1–2 one-line pointers (`• path — description`) so a relevant note surfaces before you improvise.
2. **Dedup guard** — before you create a *new* note that strongly overlaps an existing one, it stops you with a pointer: "edit X instead." (Warns once, then lets you through if you really meant it.)
3. **Auto-rebuild** — the index refreshes at session start and after any note you write, so search is always current. (~0.2s for hundreds of files.)
4. **A CLI** — `./total-recall "some topic"` for ranked search from your terminal (symlink it onto your `PATH` if you want it everywhere).

All three hooks **fail open** and bias to **precision** — staying silent beats polluting your context. The recall and rebuild hooks never interrupt you; the dedup guard is the only one that ever stops a tool call, and it only *warns once* (denies the first attempt to create a duplicate, then lets a deliberate retry straight through).

## Why keyword search, not "AI memory"?

The popular answer is semantic search (embeddings/vectors). It understands meaning — but it needs a model, it's heavier and slower, and the tools that bundle it tend to take *ownership* of your files (rewriting frontmatter, maintaining a sync layer). For a folder of markdown you already organize by hand, that's the wrong trade.

Keyword/BM25 matches **words** (with stemming, so *firing/fires* and *copy/copies* match). It can't bridge *car ↔ automobile* — but if your filenames and notes use reasonably consistent vocabulary, it's fast, transparent (you can see which terms matched), zero-dependency, and **read-only by construction**. Start here; reach for embeddings only if you measure a real miss.

## Install

Requires Python 3 (with FTS5, which ships in the standard macOS/Linux Python builds) and `jq`.

```bash
git clone https://github.com/obatried/total-recall
cd total-recall
./install.sh /path/to/your/markdown/notes
```

The installer writes a config to `~/.config/total-recall/config`, builds the initial index, and **merges** four hooks into `~/.claude/settings.json` — backed up first, idempotent, and validated, so it never clobbers your existing hooks. **Restart Claude Code** afterward (hooks load at session start).

> Prefer to wire it by hand? The four hook entries are listed in [`docs/manual-install.md`](docs/manual-install.md).

## How it works

`index.py` builds an FTS5 table over your notes (into a temp DB, then an atomic rename, so a search never sees a half-built index). `search.py` runs a BM25 query and — in `--tsv` mode used by the hooks — also reports **coordination**: how many *distinct* query terms actually hit each file.

That coordination number is the trick. BM25 alone will rank a file highly off a single rare word, which is how a rambly prompt latches onto an unrelated note. The hooks require a *real* topical match:

- **Recall fires** when either (A) several query terms hit and the average match is strong (a distinctive match), or (B) the overall score is strong *and* a good fraction of the query's terms are covered.
- **Dedup fires** only when a candidate covers a high **fraction** of the new note's terms (a genuine duplicate ≈ 0.9; a merely-adjacent note ≈ 0.15–0.3).

Noise is bounded three ways: a per-file **once-per-session throttle** (a focused session lexically matches its project's notes every turn — you want that pointer *once*, not every turn), a per-session cap, and max 2 per prompt.

## Configure / tune

Everything lives in `~/.config/total-recall/config` (env vars override at runtime). The defaults suit a corpus of *hundreds* of files; on a tiny corpus the gates rarely fire (by design).

| Key | Default | Meaning |
|---|---|---|
| `MEM_DIR` | — | folder of `.md` notes to index |
| `DB_PATH` | `~/.cache/total-recall/index.db` | where the index cache lives |
| `RECALL_AVG` | `-3.0` | recall path A: fire if score ÷ matched-terms ≤ this |
| `RECALL_STRONG` | `-18` | recall path B: fire if score ≤ this … |
| `RECALL_RATIO` | `0.5` | … and ≥ this fraction of terms covered (with ≥6 matched) |
| `RECALL_CAP` | `6` | max distinct notes surfaced per session |
| `DEDUP_STRONG` | `-18` | deny a new note if best match score ≤ this … |
| `DEDUP_RATIO` | `0.6` | … and it covers ≥ this fraction of the new note's terms |
| `INDEX_FILE` | — | optional: a note that's always loaded; never recall / dedup-check it |

(FTS5 BM25 scores are negative; **more negative = better**.) To tune, run `./total-recall --tsv "a real prompt"` and eyeball the `score / nmatched / nterms` columns against the thresholds above, then nudge. **Tune on your own prompts** — the right cutoffs depend on your corpus.

## Uninstall

```bash
./uninstall.sh           # removes the 4 hooks (settings.json backed up)
./uninstall.sh --purge   # also removes config + index cache
```

Your notes were never touched.

## Troubleshooting

- **"your Python's sqlite3 lacks FTS5"** — rare, but some minimal Python builds omit it. On macOS the system/Homebrew Python and python.org builds include FTS5. Try a different Python 3 (e.g. `brew install python`), or check with: `python3 -c "import sqlite3; sqlite3.connect(':memory:').execute('CREATE VIRTUAL TABLE t USING fts5(x)')"`.
- **"jq required"** — install it (`brew install jq` / `apt install jq`); the hooks parse Claude Code's JSON with it.
- **Recall/dedup never fire** — (1) you must **restart Claude Code** after install; hooks load at session start. (2) On a small corpus (tens of files) the gates rarely fire *by design* — the defaults are tuned for hundreds of notes; lower the thresholds in your config. (3) Confirm the index built: `./total-recall "a word that's in your notes"`.
- **Index seems stale** — rebuild manually with `./total-recall --reindex`. (The auto-rebuild uses `flock` when present and skips it on stock macOS; either way the index is rebuilt safely.)

## Design principles

- **Read-only.** The tool never writes to your notes. The index is a derived cache; delete it anytime.
- **Additive.** It sits next to whatever memory structure you already use; it doesn't impose one.
- **Zero-dependency.** Python standard library + `jq`. Nothing to install, nothing to pay for, nothing running in the background.
- **Transparent.** It's keyword search — you can always see why something matched.
- **Soft.** Hooks fail open and bias to silence. Bad recall is worse than no recall.

## Limitations

- It's lexical, not semantic — consistent vocabulary in your notes matters.
- Thresholds are corpus-dependent; the defaults are a starting point, not gospel.
- Needs SQLite compiled with FTS5 (the norm on macOS/Linux; the installer checks and tells you if yours lacks it).

## License

MIT © 2026 Obafemi Ajayi
