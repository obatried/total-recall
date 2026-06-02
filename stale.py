#!/usr/bin/env python3
"""total-recall: staleness report. READ-ONLY — never deletes or edits notes.
Flags project/reference notes that are old AND haven't been recalled recently, for human
review. Durable types (user/feedback) never expire. Uses `created:` frontmatter when
present, else the file's mtime. Last-recalled comes from the recall usage log.
Usage: stale.py [age_days=90] [stale_days=60]"""
import os, sys, re, glob, json, datetime

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
MEM = os.path.expanduser(os.environ.get("MEM_DIR") or CFG.get("MEM_DIR") or "~/notes")
USAGE = os.path.expanduser(os.environ.get("USAGE_LOG") or CFG.get("USAGE_LOG")
                           or "~/.cache/total-recall/recall-usage.jsonl")
AGE_DAYS = int(sys.argv[1]) if len(sys.argv) > 1 else 90
STALE_DAYS = int(sys.argv[2]) if len(sys.argv) > 2 else 60
NOW = datetime.datetime.now(datetime.timezone.utc)

def frontmatter(path):
    typ = created = None
    try:
        with open(path, encoding="utf-8", errors="ignore") as f:
            in_fm = False; count = 0
            for line in f:
                s = line.rstrip("\n")
                if s.strip() == "---":
                    count += 1
                    if count == 1: in_fm = True; continue
                    if count == 2: break
                if not in_fm: continue
                m = re.match(r"\s*type:\s*(.+)", s)
                if m: typ = m.group(1).strip().strip('"')
                m = re.match(r"\s*created:\s*(.+)", s)
                if m: created = m.group(1).strip().strip('"')
    except Exception:
        pass
    return typ, created

def parse_date(s):
    if not s: return None
    m = re.match(r"(\d{4})-(\d{2})-(\d{2})", s)
    if m:
        try: return datetime.datetime(int(m[1]), int(m[2]), int(m[3]), tzinfo=datetime.timezone.utc)
        except Exception: return None
    return None

last_recall = {}
try:
    for line in open(USAGE, encoding="utf-8", errors="ignore"):
        try: o = json.loads(line)
        except Exception: continue
        d = parse_date(o.get("ts", "")); p = o.get("note")
        if d and p and (p not in last_recall or d > last_recall[p]):
            last_recall[p] = d
except FileNotFoundError:
    pass

rows = []
for f in glob.glob(os.path.join(MEM, "**", "*.md"), recursive=True):
    rel = os.path.relpath(f, MEM)
    if rel == "MEMORY.md" or rel.startswith("archive/"): continue
    if re.match(r"(topics|projects)/", rel) or rel.endswith("INDEX.md"): continue
    typ, created = frontmatter(f)
    if typ not in ("project", "reference"):   # durable types (user/feedback) don't expire
        continue
    try:
        cd = parse_date(created) or datetime.datetime.fromtimestamp(os.path.getmtime(f), datetime.timezone.utc)
    except OSError:
        continue
    age = (NOW - cd).days
    lr = last_recall.get(rel)
    recall_age = (NOW - lr).days if lr else None
    if age > AGE_DAYS and (recall_age is None or recall_age > STALE_DAYS):
        rows.append((age, rel, typ, "never" if recall_age is None else f"{recall_age}d ago",
                     "created" if created else "mtime"))

rows.sort(reverse=True)
if not rows:
    print(f"No stale project/reference notes (age>{AGE_DAYS}d AND last-recall>{STALE_DAYS}d). Nothing to review.")
    sys.exit(0)
print(f"Stale candidates for REVIEW (not deletion) — {len(rows)} notes, age>{AGE_DAYS}d & last recalled>{STALE_DAYS}d:\n")
print(f"{'age':>5}  {'type':<9} {'last recall':<11}  note")
for age, rel, typ, lr, src in rows:
    print(f"{age:>4}d  {typ:<9} {lr:<11}  {rel}  ({src})")
print("\nReview each: still accurate -> update it. Obsolete -> move to archive/. Never auto-deleted.")
