# Manual install

If you'd rather not run `./install.sh`, do these three things by hand.

### 1. Write the config

`~/.config/total-recall/config`:

```
TR_HOME="/absolute/path/to/this/repo"
MEM_DIR="/absolute/path/to/your/markdown/notes"
DB_PATH="/Users/you/.cache/total-recall/index.db"
```

### 2. Build the index

```bash
python3 index.py        # reads the config above; writes the DB; never touches your notes
```

### 3. Add four hooks to `~/.claude/settings.json`

Merge these into the `"hooks"` object (replace `TR_HOME` with the repo's absolute path). Each is a separate group, so they coexist with whatever you already have.

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "TR_HOME/hooks/total-recall-rebuild.sh", "timeout": 10 } ] }
    ],
    "PostToolUse": [
      { "matcher": "Write|Edit|MultiEdit", "hooks": [ { "type": "command", "command": "TR_HOME/hooks/total-recall-rebuild.sh", "timeout": 10 } ] }
    ],
    "PreToolUse": [
      { "matcher": "Write", "hooks": [ { "type": "command", "command": "TR_HOME/hooks/total-recall-dedup.sh", "timeout": 5 } ] }
    ],
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "TR_HOME/hooks/total-recall-recall.sh", "timeout": 10 } ] }
    ]
  }
}
```

Restart Claude Code — hooks load at session start.

### What each hook does

| Hook | Event | Role |
|---|---|---|
| `total-recall-rebuild.sh` | SessionStart + PostToolUse(Write/Edit/MultiEdit in `MEM_DIR`) | keep the index fresh |
| `total-recall-recall.sh` | UserPromptSubmit | inject relevant-note pointers |
| `total-recall-dedup.sh` | PreToolUse(Write) | warn before a duplicate note |
