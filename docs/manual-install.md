# Manual install

If you'd rather not run `./install.sh`, here's everything it does.

### 1. Set up your memory folder

Copy the starter structure (or use your existing notes folder):

```bash
cp -R template/. /path/to/your/memory
```

It contains `MEMORY.md` (the always-loaded index), `topics/` and `projects/` (domain indexes),
one example note per type, and `.allowed-indexes` (the list of valid `home:` targets).

### 2. Write the config

`~/.config/total-recall/config`:

```
TR_HOME="/absolute/path/to/this/repo"
MEM_DIR="/absolute/path/to/your/memory"
DB_PATH="/Users/you/.cache/total-recall/index.db"
ALLOWED_INDEXES="/absolute/path/to/your/memory/.allowed-indexes"
```

### 3. Build the index

```bash
python3 index.py     # reads the config; writes the DB; never touches your notes
```

### 4. Add the memory block to your CLAUDE.md

Copy the contents of `claude-memory.md` (everything from `# Memory` down), replace `<MEM_DIR>` with
your notes path, and paste it into `~/.claude/CLAUDE.md`. This teaches Claude how to write notes in
this system.

### 5. Add the hooks to `~/.claude/settings.json`

Merge these into the `"hooks"` object (replace `TR_HOME` with the repo's absolute path). Each is a
separate group, so they coexist with whatever you already have.

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "TR_HOME/hooks/total-recall-rebuild.sh", "timeout": 10 } ] }
    ],
    "PostToolUse": [
      { "matcher": "Write|Edit|MultiEdit", "hooks": [ { "type": "command", "command": "TR_HOME/hooks/total-recall-rebuild.sh", "timeout": 10 } ] },
      { "matcher": "Write|Edit|MultiEdit", "hooks": [ { "type": "command", "command": "TR_HOME/hooks/memory-autoindex.sh", "timeout": 10 } ] }
    ],
    "PreToolUse": [
      { "matcher": "Write", "hooks": [ { "type": "command", "command": "TR_HOME/hooks/total-recall-dedup.sh", "timeout": 5 } ] },
      { "matcher": "Write", "hooks": [ { "type": "command", "command": "TR_HOME/hooks/memory-home-required.sh", "timeout": 5 } ] }
    ],
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "TR_HOME/hooks/total-recall-recall.sh", "timeout": 10 } ] }
    ]
  }
}
```

Restart Claude Code — hooks and CLAUDE.md load at session start.

### What each hook does

| Hook | Event | Role |
|---|---|---|
| `total-recall-rebuild.sh` | SessionStart + PostToolUse(Write/Edit/MultiEdit in `MEM_DIR`) | keep the index fresh |
| `memory-autoindex.sh` | PostToolUse(Write/Edit/MultiEdit) | auto-file each note into its `home:` index |
| `total-recall-dedup.sh` | PreToolUse(Write) | warn before a duplicate note |
| `memory-home-required.sh` | PreToolUse(Write) | require a valid `home:` on new notes |
| `total-recall-recall.sh` | UserPromptSubmit | surface relevant-note pointers |
