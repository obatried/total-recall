# How I do memory

This is the method total-recall packages. You can adopt the whole thing with the installer,
or just steal the ideas. It's opinionated on purpose — the opinions are what make it work.

## The core problem

AI assistants are good at *writing things down* and bad at *using what they wrote*. Give one a
place to remember things and it'll happily fill it with hundreds of notes — then never read the
right one at the right moment. The collection grows; the usefulness doesn't. Two failure modes
show up over and over:

1. **It writes a note and never finds it again.** The fact existed, but at the moment it mattered
   nothing surfaced it, so the assistant improvised or repeated a solved mistake.
2. **It writes the same note twice.** No check before creating, so the same playbook gets
   re-derived under a slightly different filename.

Both are *retrieval* failures, not *storage* failures. So the method optimizes for retrieval.

## The four parts

**1. Capture — one fact per file, named for retrieval.**
Every memory is a single fact in its own file. The filename and a one-line `description` are
written in the words you'd *search for later*, not as a vague summary. `feedback_always_humanize_outbound.md`
gets found; `writing_note_3.md` doesn't. Feedback and project notes carry a *why* and a *how to apply*
so the fact is actionable, not just true.

**2. Structure — three tiers, loaded by need.**
You can't load hundreds of facts into context every turn, and you shouldn't try. So:
- `MEMORY.md` is a small always-loaded **index** — one line per note or domain, never content.
- `topics/*.md` and `projects/*.md` are **domain indexes** that load only when a session touches them.
- The **leaf notes** load only when an index points to them.
This is the opposite of dumping everything into one giant instructions file. The index is cheap to
keep in context; the depth is one hop away when you need it.

**3. Discipline — every note declares where it lives.**
A note without a home becomes an orphan nobody can find. So every note must declare a `home:` (which
index it belongs to). A guard blocks notes that don't; another hook auto-files each note into its
index. The collection stays navigable without manual upkeep.

**4. Retrieve — read-only keyword search, surfaced automatically.**
A search index sits over the notes (read-only — it never edits them). On every prompt it surfaces the
relevant note *before* the assistant acts. Before the assistant writes a new note, it searches first
and warns on a near-duplicate. This is the part that closes both failure modes above.

## Why not just use a vector database

Semantic search (embeddings) understands meaning, which keyword search can't. But for a folder of
markdown you maintain by hand, it's usually the wrong trade: it needs a model, it's heavier, and the
tools that bundle it tend to take ownership of your files and rewrite them. Plain keyword search
(BM25, the ranking inside most search engines) is read-only, zero-dependency, transparent, and — if
your filenames and notes use consistent vocabulary, which *this method enforces* — good enough that
the fancier option isn't worth it. Reach for embeddings only after you've measured that keyword
search actually misses. Usually it doesn't.

## The loop

Capture writes good notes → discipline keeps them filed → retrieval surfaces them and blocks
duplicates → which makes the next capture better. The whole thing only works because the pieces
reinforce each other. Adopt one without the others and you get a worse version of each.
