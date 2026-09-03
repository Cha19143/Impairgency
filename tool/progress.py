#!/usr/bin/env python3
"""Regenerate the progress table in docs/TASKS.md.

Counts checkboxes per section so the summary cannot drift from the list.
Run after ticking anything off:

    python3 tool/progress.py
"""
import re
import sys
from pathlib import Path

TASKS = Path(__file__).resolve().parent.parent / "docs" / "TASKS.md"
SKIP = ("Out of scope",)  # declared not-building; not outstanding work


def main() -> int:
    text = TASKS.read_text()
    body = text.split("<!-- PROGRESS -->", 1)[-1]

    rows, totals = [], [0, 0]
    for chunk in re.split(r"^## ", body, flags=re.M)[1:]:
        title = chunk.splitlines()[0].strip()
        if any(title.startswith(s) for s in SKIP):
            continue
        done = len(re.findall(r"^\s*- \[x\]", chunk, re.M))
        started = len(re.findall(r"^\s*- \[~\]", chunk, re.M))
        todo = len(re.findall(r"^\s*- \[ \]", chunk, re.M))
        total = done + started + todo
        if not total:
            continue
        totals[0] += done
        totals[1] += total
        filled = round(done / total * 12)
        bar = "█" * filled + "░" * (12 - filled)
        rows.append(f"| {title} | `{bar}` | {done} / {total} |")

    pct = round(totals[0] / totals[1] * 100) if totals[1] else 0
    table = "\n".join(
        ["| Phase | | Done |", "|---|---|---|", *rows,
         f"| **Overall** | | **{totals[0]} / {totals[1]}  ({pct}%)** |"]
    )

    head, _, tail = text.partition("<!-- PROGRESS -->")
    tail = re.sub(r"\A\n*(\| Phase \|.*?\n)+", "", tail)
    TASKS.write_text(f"{head}<!-- PROGRESS -->\n\n{table}\n{tail}")
    print(f"{totals[0]} / {totals[1]} ({pct}%)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
