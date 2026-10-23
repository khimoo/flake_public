#!/usr/bin/env python3
"""Check local Markdown file links, their heading anchors, and the shared AI instruction entrypoint.

Network links are deliberately outside this check. Ignore fenced/inline code
(including Markdown syntax examples) before collecting links.
"""
import re
import sys
from pathlib import Path
from urllib.parse import unquote


def without_fences(text):
    lines = []
    fence = None
    for line in text.splitlines():
        marker = re.match(r"^\s*(`{3,}|~{3,})", line)
        if marker:
            token = marker.group(1)
            if fence is None:
                fence = token
            elif token[0] == fence[0] and len(token) >= len(fence):
                fence = None
            lines.append("")
        else:
            lines.append(line if fence is None else "")
    return "\n".join(lines)


def prose(text):
    return re.sub(r"(`+).*?\1", "", without_fences(text), flags=re.S)


def heading_anchors(text):
    """Return the anchors GitHub gives the headings of a Markdown document."""
    anchors, seen = set(), {}
    for line in without_fences(text).splitlines():
        match = re.match(r"^#{1,6}\s+(.*?)\s*#*\s*$", line)
        if not match:
            continue
        heading = re.sub(r"\[([^]]*)\]\([^)]*\)", r"\1", match.group(1)).lower()
        slug = re.sub(r"[^\w\- ]", "", heading).replace(" ", "-")
        count = seen.get(slug, 0)
        seen[slug] = count + 1
        anchors.add(slug if count == 0 else f"{slug}-{count}")
    return anchors


def check(root):
    failures = []
    paths = [root / "README.md", root / "AGENTS.md", root / "CLAUDE.md"]
    for folder in ["docs", ".claude/commands", "modules/home-manager/dev/neovim/config/docs"]:
        paths.extend((root / folder).rglob("*.md"))
    for path in paths:
        if not path.is_file():
            failures.append(f"missing document: {path.relative_to(root)}")
            continue
        text = prose(path.read_text())
        targets = re.findall(r"\]\(<?([^\s)>]+)>?(?:\s+\"[^\"]*\")?\)", text)
        targets += re.findall(r"^\s*\[[^]]+\]:\s*<?([^\s>]+)>?", text, re.M)
        for target in targets:
            if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", target):
                continue
            file_part, _, anchor = (unquote(part) for part in target.partition("#"))
            if not file_part:
                dest = path
            elif file_part.startswith("/"):
                dest = root / file_part.lstrip("/")
            else:
                dest = path.parent / file_part
            if not dest.exists():
                failures.append(f"{path.relative_to(root)}: missing link target {file_part}")
            elif anchor and dest.suffix == ".md" and anchor not in heading_anchors(dest.read_text()):
                failures.append(f"{path.relative_to(root)}: missing heading anchor {target}")
    if (root / "CLAUDE.md").is_file() and "@AGENTS.md" not in (root / "CLAUDE.md").read_text():
        failures.append("CLAUDE.md must import @AGENTS.md")
    for failure in failures:
        print(failure, file=sys.stderr)
    return not failures


if __name__ == "__main__":
    sys.exit(0 if check(Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()) else 1)
