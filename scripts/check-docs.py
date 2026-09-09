#!/usr/bin/env python3
"""Check local Markdown file links and the shared AI instruction entrypoint.

Network links and heading anchors are deliberately outside this check. Ignore
fenced/inline code (including Markdown syntax examples) before collecting links.
"""
import re
import sys
from pathlib import Path
from urllib.parse import unquote


def prose(text):
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
    return re.sub(r"(`+).*?\1", "", "\n".join(lines), flags=re.S)


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
            if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", target) or target.startswith("#"):
                continue
            target = unquote(target.split("#", 1)[0])
            dest = root / target.lstrip("/") if target.startswith("/") else path.parent / target
            if not dest.exists():
                failures.append(f"{path.relative_to(root)}: missing link target {target}")
    if (root / "CLAUDE.md").is_file() and "@AGENTS.md" not in (root / "CLAUDE.md").read_text():
        failures.append("CLAUDE.md must import @AGENTS.md")
    for failure in failures:
        print(failure, file=sys.stderr)
    return not failures


if __name__ == "__main__":
    sys.exit(0 if check(Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()) else 1)
