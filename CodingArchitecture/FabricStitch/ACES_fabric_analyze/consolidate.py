#!/usr/bin/env python3
"""
consolidate.py — Merge per-agent markdown files into one consolidated document.
Called by fabric_analyze.sh for multi-agent consolidated output.

Usage:
  python3 consolidate.py CONS_MD TITLE MAIN_LOG [MD_FILE ...]
"""
import sys, re, pathlib, datetime

def main():
    if len(sys.argv) < 4:
        print("Usage: consolidate.py CONS_MD TITLE MAIN_LOG [MD_FILE ...]")
        sys.exit(1)

    cons_md  = pathlib.Path(sys.argv[1])
    title    = sys.argv[2]
    main_log = pathlib.Path(sys.argv[3])
    md_files = [pathlib.Path(f) for f in sys.argv[4:] if pathlib.Path(f).exists()]
    n        = len(md_files)
    now      = datetime.datetime.now().strftime("%B %d, %Y at %H:%M")

    def strip_frontmatter(text):
        return re.sub(r'^---\n.*?\n---\n', '', text, flags=re.DOTALL)

    parts = [
        "---",
        f'title: "{title}"',
        'subtitle: "Consolidated Multi-Source Analysis"',
        'author: "Peter Heller / Mind Over Metadata LLC"',
        f'date: "{datetime.datetime.now().strftime("%B %d, %Y")}"',
        "---", "",
        "\\newpage", "",
        f"# {title}", "",
        f"*Consolidated from {n} source{'s' if n!=1 else ''} · {now}*", "",
    ]

    for i, mf in enumerate(md_files):
        text = strip_frontmatter(mf.read_text())
        parts += ["---", "", f"# Source {i+1}", "", text.strip(), "", "\\newpage", ""]

    log_text = main_log.read_text() if main_log.exists() else "(no health log)"
    parts += ["---", "", "# Consolidated Health Log", "", "```", log_text, "```", ""]

    cons_md.write_text("\n".join(parts))
    print(f"Consolidated: {cons_md}  ({n} sources)")

if __name__ == "__main__":
    main()
