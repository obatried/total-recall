<!--
  total-recall: paste this block into your ~/.claude/CLAUDE.md (or a project CLAUDE.md).
  It teaches Claude HOW to write memories in this system. The hooks enforce + maintain
  the structure; total-recall retrieves them. Replace <MEM_DIR> with your notes folder
  (the installer does this for you).
-->

# Memory

You have a persistent file-based memory at `<MEM_DIR>`. Write to it directly with the Write tool. Each memory is **one file holding one fact**, with frontmatter:

```markdown
---
name: <short-kebab-case-slug>
description: <one substantive line (~5+ words) — this is what search and recall match against, so phrase it in the words you'd use to look it up later. A vague/empty description is rejected.>
home: <the index file this belongs to, e.g. MEMORY.md or topics/<topic>.md>
created: <YYYY-MM-DD>
metadata:
  type: user | feedback | project | reference
---

<the fact. For feedback/project, follow with **Why:** and **How to apply:** lines.
Link related memories with [[their-name]].>
```

**The four types:**
- `user` — who the user is (role, preferences, durable facts).
- `feedback` — guidance on how you should work (corrections and confirmed approaches); always include the why.
- `project` — ongoing work, goals, or constraints not derivable from the code/repo.
- `reference` — pointers to external resources (URLs, dashboards, tickets, accounts).

**Rules that make memory actually work:**
- **One fact per file.** Don't append unrelated facts to an existing note; make a new one.
- **Name files by what you'd search for**, not by a vague summary. `feedback_always_humanize_outbound.md` beats `feedback_writing_note_3.md`. The filename and `description` are how the fact gets found again.
- **Give every note a substantive `description` and a `created:` date.** The guard rejects a vague/empty description (it's the search surface); `created:` powers the staleness review.
- **Convert relative dates to absolute** ("today" → the actual date) before saving.
- **Link liberally** with `[[name]]` — a link to a note that doesn't exist yet is fine; it marks something worth writing later.
- **Check before creating.** Before writing a new note, see if one already covers it and update that instead. (The dedup guard will stop you on obvious duplicates.)
- **Every note needs a `home:`** — the index it belongs to. The write-discipline hook blocks notes without one. After you write it, it's auto-added to that index.
- **Don't save what the repo already records** (code structure, git history, the contents of CLAUDE.md) or what only matters to the current conversation.

**The structure (three tiers):**
1. `MEMORY.md` — a small index loaded into context every session. One line per memory or domain. Never put memory *content* here.
2. `topics/*.md` and `projects/*.md` — domain indexes, loaded on demand when a session touches that topic/project.
3. The leaf note files at the root — the actual facts, loaded only when their index points you to them.

When a session starts touching a known topic or project, read its index file first before improvising — the relevant facts are one hop away.
