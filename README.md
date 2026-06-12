# total-recall

**A complete, plug-and-play memory system for Claude Code — so the notes your AI writes actually get used.**

Point it at a folder, run one command, and your Claude Code gets a real memory: it writes facts down
in a findable way, keeps them organized, surfaces the right one at the right moment, and stops itself
from writing the same note twice. Your notes stay plain markdown you own, it needs nothing but Python
and `jq`, and it sits on top of whatever you already have.

AI assistants are good at *writing things down* and bad at *using what they wrote*. This fixes the
using part. The full philosophy is in [METHOD.md](METHOD.md); the short version is four parts that
reinforce each other:

| Part | What it does | Pieces |
|---|---|---|
| **Capture** | makes the AI write *findable* notes (one fact per file, named for search) | the `CLAUDE.md` memory block |
| **Structure** | a tiered layout so hundreds of notes stay usable | `MEMORY.md` index → topic/project indexes → leaf notes |
| **Discipline** | every note declares where it's filed, and gets filed automatically | `memory-home-required`, `memory-autoindex` hooks |
| **Retrieve** | surfaces the right note on every prompt; blocks duplicates; keeps search fresh | `total-recall-recall`, `-dedup`, `-rebuild` hooks |

The retrieval engine is deliberately boring: **SQLite FTS5 + BM25**, the keyword-search algorithm
behind most search engines, already built into the Python on your machine. No embeddings, no vector
database, no API key, no daemon. **The search index never modifies your notes** — it's a throwaway
cache rebuilt from your files. (The only writes the system makes are one-line entries appended to your
own index files when you add a note.)

## Why keyword search, not "AI memory"?

The popular answer is semantic search (embeddings/vectors). It understands meaning — but it needs a
model, it's heavier, and the tools that bundle it tend to take *ownership* of your files (rewriting
frontmatter, maintaining a sync layer). For a folder of markdown you organize by hand, that's the
wrong trade. Keyword/BM25 matches **words** (with stemming, so *firing/fires* and *copy/copies* match).
It can't bridge *car ↔ automobile* — but if your notes use consistent vocabulary, which this system's
capture rules enforce, it's fast, transparent, zero-dependency, and **read-only by construction**.
Start here; reach for embeddings only if you measure a real miss. (More in [METHOD.md](METHOD.md).)

## Install

Requires Python 3 (with FTS5, standard in macOS/Linux builds) and `jq`.

```bash
git clone https://github.com/obatried/total-recall
cd total-recall
./install.sh ~/.claude/memory      # any folder; created + seeded if empty
```

The installer:
- **seeds a starter memory structure** into your folder (skip if it already has notes),
- writes config to `~/.config/total-recall/config` and builds the search index,
- **merges 5 hooks** into `~/.claude/settings.json` — backed up, idempotent, validated, never clobbering your existing hooks,
- **appends the memory-writing block** to `~/.claude/CLAUDE.md` (backed up, idempotent) so Claude knows how to write notes in this system.

Then **restart Claude Code** (hooks + CLAUDE.md load at session start).

Already have a memory folder? Point the installer at it — it won't overwrite your notes, it just wires
the tooling around them. Want it by hand? See [docs/manual-install.md](docs/manual-install.md).

**Starting a `CLAUDE.md` from scratch?** Crib from [`CLAUDE.example.md`](CLAUDE.example.md) — a short
fill-in-the-blank operating manual (who you are, how you like answers, your always/never rules) that
loads every session so you never re-explain how you work. (This is separate from the memory-*writing*
block the installer appends — that one teaches Claude how to *save* notes.)

## Works well with: recursive-learn

total-recall gives your AI a **memory**. [recursive-learn](https://github.com/obatried/recursive-learn)
gives it a **`/learn` loop** — it audits its own mistakes at the end of a session and writes the lessons
back, so they don't recur. Memory + self-correction is the full "give your AI a memory" setup.

Install both at once with the bundled `meta-install.sh`:

```bash
git clone https://github.com/obatried/total-recall
git clone https://github.com/obatried/recursive-learn   # sibling folder (optional)
cd total-recall
./meta-install.sh ~/.claude/memory
```

`meta-install.sh` runs this installer, then recursive-learn's — cloning recursive-learn to a temp dir
automatically if it isn't sitting next to total-recall.

## Use it

You mostly don't — it runs in the background. Day to day:

- You talk to Claude. When something you've saved is relevant, a one-line pointer to that note is
  surfaced automatically (once per note per session, only on a confident match).
- When Claude goes to save a note, it must declare where it's filed, gets auto-added to that index,
  and gets stopped if it's about to duplicate an existing note.
- Search your own notes from the terminal: `./total-recall "some topic"` (or `--reindex` to rebuild).
- **Synonyms:** add groups to `<MEM_DIR>/.aliases` (e.g. `car, automobile, vehicle`) so a search for one finds notes that use another — the keyword-friendly fix for the one thing keyword search can't do.
- **Staleness review:** `./total-recall --stale` lists `project`/`reference` notes that are old *and* haven't been recalled lately, for you to review (never auto-deleted; durable `user`/`feedback` notes are left alone).

## How retrieval works

`index.py` builds an FTS5 table over your notes (temp DB + atomic rename, so a search never sees a
half-built index). `search.py` runs a BM25 query and, in `--tsv` mode used by the hooks, also reports
**coordination**: how many *distinct* query terms actually hit each note. BM25 alone will rank a note
highly off a single rare word; the hooks require a real topical match (several terms), which is what
keeps recall precise. Noise is bounded by a once-per-note-per-session throttle, a per-session cap, and
max 2 surfaced per prompt. Bad recall is worse than no recall, so every gate biases to silence.

## Configure / tune

Everything lives in `~/.config/total-recall/config` (env vars override at runtime). Defaults suit a
corpus of *hundreds* of notes; on a tiny corpus the gates rarely fire by design.

| Key | Default | Meaning |
|---|---|---|
| `MEM_DIR` | — | your notes folder |
| `DB_PATH` | `~/.cache/total-recall/index.db` | the index cache |
| `ALLOWED_INDEXES` | `<MEM_DIR>/.allowed-indexes` | valid `home:` targets (the discipline guard checks this) |
| `ALIASES` | `<MEM_DIR>/.aliases` | synonym groups so search bridges different-words-same-meaning |
| `ENFORCE_HOME` | on | set `0` to stop requiring a `home:` field on new notes |
| `RECALL_AVG` | `-3.0` | recall path A: fire if score ÷ matched-terms ≤ this |
| `RECALL_STRONG` / `RECALL_RATIO` | `-18` / `0.5` | recall path B: strong score + enough terms covered |
| `RECALL_CAP` | `6` | max distinct notes surfaced per session |
| `DEDUP_STRONG` / `DEDUP_RATIO` | `-18` / `0.6` | a new note is a duplicate if it covers this much of an existing one |
| `INDEX_FILE` | — | a note that's always loaded; never recall / dedup-check it |

(FTS5 BM25 scores are negative; **more negative = better**.) Tune with `./total-recall --tsv "a real prompt"`.

## Troubleshooting

- **"sqlite3 lacks FTS5"** — rare; try another Python 3 (`brew install python`). Check: `python3 -c "import sqlite3; sqlite3.connect(':memory:').execute('CREATE VIRTUAL TABLE t USING fts5(x)')"`.
- **"jq required"** — `brew install jq` / `apt install jq`.
- **Nothing fires / Claude doesn't write notes** — restart Claude Code after install (hooks + CLAUDE.md load at session start). On a small corpus the recall/dedup gates rarely fire by design; lower the thresholds.
- **Index stale** — `./total-recall --reindex`.

## Uninstall

```bash
./uninstall.sh           # removes the hooks + the CLAUDE.md block (both backed up)
./uninstall.sh --purge   # also removes config + index cache
```

Your notes were never touched.

## Design principles

- **Read-only search.** The search engine never writes to your notes; its index is a throwaway cache. The system's only writes are one-line entries appended to your own index files (`MEMORY.md`, topic/project indexes).
- **Additive.** It wires around whatever you already have; it doesn't take over.
- **Zero-dependency.** Python standard library + `jq`. Nothing to install, nothing to pay for, nothing running in the background.
- **Transparent.** Keyword search — you can always see why something matched.
- **Soft.** Hooks fail open and bias to silence. Only two ever block a write — the duplicate guard and the new-note `home:` check — both only on newly created notes, and both give a clear reason.

## Limitations

- Keyword, not semantic — consistent vocabulary in your notes matters (the capture rules push you toward it).
- Thresholds are corpus-dependent; defaults are a starting point.
- Needs SQLite with FTS5 (standard on macOS/Linux; the installer checks).

## License

MIT © 2026 Obafemi Ajayi
