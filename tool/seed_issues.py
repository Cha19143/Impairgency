#!/usr/bin/env python3
"""Turn docs/TASKS.md into GitHub milestones, labels and issues.

Top-level checklist items become issues. Nested items stay as task lists inside
their parent issue, so nothing from TASKS.md is lost but the issue list stays
readable. Run with --dry to see what would be created.
"""
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TASKS = ROOT / "docs" / "TASKS.md"
DRY = "--dry" in sys.argv

SKIP_SECTIONS = ("Out of scope",)

LABELS = {
    "phase-0": ("B60205", "Security and integrity"),
    "phase-1": ("D93F0B", "Location, push, pairing"),
    "phase-2": ("FBCA04", "Location history and aggregations"),
    "phase-3": ("0E8A16", "Web dashboard"),
    "phase-4": ("1D76DB", "Flow, SOS, voice"),
    "phase-5": ("5319E7", "Accessibility, docs, defense"),
    "port": ("C5DEF5", "Carry over from cprwire, do not rewrite"),
    "security": ("B60205", "Blocking; affects who can read user data"),
    "accessibility": ("0052CC", "Requirements section 4"),
}


def sh(args, **kw):
    return subprocess.run(args, check=True, capture_output=True, text=True, **kw)


def parse():
    text = TASKS.read_text().split("<!-- PROGRESS -->", 1)[-1]
    sections = []
    for chunk in re.split(r"^## ", text, flags=re.M)[1:]:
        lines = chunk.splitlines()
        title = lines[0].strip()
        if any(title.startswith(s) for s in SKIP_SECTIONS):
            continue
        gate = ""
        m = re.search(r"^\*\*Gate:\*\*(.+?)(?=\n\n|\n---|\Z)", chunk, re.M | re.S)
        if m:
            gate = " ".join(m.group(1).split())

        items, group = [], ""
        for i, line in enumerate(lines[1:], start=1):
            g = re.match(r"^\*\*(.+?)\*\*(?:\s+—.*)?$", line.strip())
            if g and not line.startswith("**Gate"):
                group = g.group(1)
                continue
            top = re.match(r"^- \[([ x~])\] (.+)$", line)
            if not top:
                continue
            # Indented "- [ ]" lines are sub-tasks. Indented plain text is a
            # continuation of the title, which is what wrapping in the markdown
            # produces - folding it into "extra" truncated six titles mid-clause.
            subs, cont, j = [], [], i + 1
            while j < len(lines) and lines[j].startswith("  ") and lines[j].strip():
                stripped = lines[j].strip()
                (subs if stripped.startswith("- [") else cont).append(stripped)
                j += 1
            item_title = " ".join((top.group(2) + " " + " ".join(cont)).split())
            items.append({
                "done": top.group(1) == "x",
                "title": item_title,
                "extra": subs,
                "group": group,
            })
        sections.append({"title": title, "gate": gate, "items": items})
    return sections


def clean_title(t, limit=110):
    t = re.sub(r"\*\*(.+?)\*\*", r"\1", t)
    t = re.sub(r"`(.+?)`", r"\1", t)
    t = re.sub(r"\*(.+?)\*", r"\1", t)
    t = " ".join(t.split())
    if len(t) <= limit:
        return t
    cut = t[:limit]
    for sep in (" — ", "; ", ", ", " "):
        if sep in cut:
            return cut[: cut.rfind(sep)].rstrip(" ,;—")
    return cut


def main():
    sections = parse()
    plan = []
    for idx, sec in enumerate(sections):
        pm = re.match(r"Phase (\d)", sec["title"])
        label = f"phase-{pm.group(1)}" if pm else "port"
        for it in sec["items"]:
            labels = [label]
            low = it["title"].lower()
            if any(k in low for k in ("rules", "auth guard", "consent", "claim", "deploy")):
                labels.append("security")
            if any(k in low for k in ("contrast", "voiceover", "semantic", "text scale", "screen curtain")):
                labels.append("accessibility")
            plan.append({
                "milestone": sec["title"],
                "gate": sec["gate"],
                "labels": labels,
                **it,
            })

    if DRY:
        by_ms = {}
        for p in plan:
            by_ms.setdefault(p["milestone"], []).append(p)
        for ms, items in by_ms.items():
            print(f"\n## {ms}  ({len(items)} issues)")
            for p in items:
                mark = "x" if p["done"] else " "
                grp = f"[{p['group']}] " if p["group"] else ""
                sub = f"  (+{len(p['extra'])} sub)" if p["extra"] else ""
                print(f"  [{mark}] {grp}{clean_title(p['title'])[:90]}{sub}")
        print(f"\nTOTAL: {len(plan)} issues, {sum(1 for p in plan if p['done'])} to open closed")
        return

    print("creating labels...")
    for name, (colour, desc) in LABELS.items():
        subprocess.run(["gh", "label", "create", name, "--color", colour,
                        "--description", desc, "--force"],
                       capture_output=True, text=True)

    print("creating milestones...")
    ms_numbers = {}
    for sec in sections:
        title = clean_title(sec["title"])
        r = subprocess.run(
            ["gh", "api", "repos/{owner}/{repo}/milestones", "-X", "POST",
             "-f", f"title={title}",
             "-f", f"description={sec['gate'] and 'Gate: ' + sec['gate'] or ''}"],
            capture_output=True, text=True)
        if r.returncode == 0:
            ms_numbers[sec["title"]] = json.loads(r.stdout)["number"]
        else:
            existing = json.loads(sh(["gh", "api",
                                      "repos/{owner}/{repo}/milestones?state=all"]).stdout)
            for m in existing:
                if m["title"] == title:
                    ms_numbers[sec["title"]] = m["number"]

    print(f"creating {len(plan)} issues...")
    for n, p in enumerate(plan, 1):
        body = []
        full = clean_title(p["title"], limit=10_000)
        if full != clean_title(p["title"]):
            body.append(f"{full}\n")
        if p["group"]:
            body.append(f"**{p['group']}**\n")
        if p["extra"]:
            body.extend(p["extra"])
            body.append("")
        if p["gate"]:
            body.append(f"**Phase gate:** {p['gate']}\n")
        body.append("From [`docs/TASKS.md`](../blob/main/docs/TASKS.md). "
                    "See [`docs/BUILD_PLAN.md`](../blob/main/docs/BUILD_PLAN.md) "
                    "for why this is scoped the way it is.")
        args = ["gh", "issue", "create",
                "--title", clean_title(p["title"]),
                "--body", "\n".join(body),
                "--milestone", clean_title(p["milestone"])]
        for lb in p["labels"]:
            args += ["--label", lb]
        r = subprocess.run(args, capture_output=True, text=True)
        if r.returncode != 0:
            print(f"  !! {clean_title(p['title'])[:60]}: {r.stderr.strip()[:120]}")
            continue
        url = r.stdout.strip().splitlines()[-1]
        if p["done"]:
            subprocess.run(["gh", "issue", "close", url, "-r", "completed",
                            "-c", "Done in the initial scaffold."],
                           capture_output=True, text=True)
        print(f"  {n:>3}/{len(plan)} {'closed' if p['done'] else 'open  '} {url}")


if __name__ == "__main__":
    main()
