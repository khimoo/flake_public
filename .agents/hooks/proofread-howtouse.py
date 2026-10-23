#!/usr/bin/env python3
"""PreToolUse(Bash): git commit の前に、ステージした docs/howtouse/ の文書を Gemini で校正する。

Claude Code（.claude/settings.json）と Codex（.codex/hooks.json）の両方から呼ぶ。
校正の結果を作業ツリーに書き戻したらコミットを止め、確認の手順を stderr に出して exit 2 する。
エージェントは gemini-proofread スキルの手順で差分を確かめ、`git add` してから、
コマンドの先頭に GEMINI_PROOFREAD=0 を付けて実行し直す。

文書を書くたびではなくコミットのときだけ校正する。Gemini の無料枠はモデルごとに 1 日 20 リクエストで、
書きかけの文書を何度も送ると枠を使い切り、校正のたびに表現が行き来するため。
gemini-proofread のスキルが見つからない環境では何もしない。
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
TARGET_DIR = "docs/howtouse/"
SKIP_MARK = "GEMINI_PROOFREAD=0"
GIT_COMMIT = re.compile(r"(?:^|[\s;&|(])git(?:\s+-[cC]\s+\S+|\s+--\S+)*\s+commit(?=\s|$)(?P<args>[^\n;&|]*)")
ALL_FLAG = re.compile(r"(?:^|\s)(?:--all|-[A-Za-z]*a[A-Za-z]*)(?=\s|$)")
LEAD = (
    f"ステージした {TARGET_DIR} の文書に gemini-proofread をかけ、校正の結果を作業ツリーに書き戻した。"
    "コミットはまだ実行していない。\n"
    "gemini-proofread スキルの「受け取る」に従って差分を確かめ、壊れた箇所を直す。\n"
    "意味がずれた箇所があれば、originals にある原文を書き直して対象のファイルに上書きし、"
    f"`git add` してから `{SKIP_MARK}` を付けずに実行し直す。hook がもう一度校正する（送り直しは 2 回まで）。\n"
    f"確かめ終えたら `git add` し、コマンドの先頭に `{SKIP_MARK}` を付けて実行し直す。"
)
FAILED = (
    f"ステージした {TARGET_DIR} の文書を gemini-proofread で校正できなかった。何も書き戻していない。\n"
    f"校正せずにコミットするなら、コマンドの先頭に `{SKIP_MARK}` を付けて実行し直し、未校正だと報告する。"
)


def skill_scripts():
    candidates = [os.environ.get("GEMINI_PROOFREAD_SKILL_DIR")]
    candidates += [Path.home() / ".claude/skills/gemini-proofread", Path.home() / ".agents/skills/gemini-proofread"]
    for candidate in filter(None, candidates):
        rewrite = Path(candidate) / "scripts/rewrite.py"
        if rewrite.is_file():
            return rewrite
    return None


def git(cwd, *args):
    return subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True)


def commit_args(command):
    """コマンドの中の git commit の引数を返す。git commit がなければ None。"""
    match = GIT_COMMIT.search(command)
    return match.group("args") if match else None


def target_files(args):
    names = git(REPO, "diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z").stdout.split("\0")
    # git commit -a は、ステージしていない変更もコミットに含める。
    if ALL_FLAG.search(args):
        names += git(REPO, "diff", "--name-only", "--diff-filter=M", "-z").stdout.split("\0")
    return sorted({name for name in names if name.startswith(TARGET_DIR) and name.endswith(".md")})


def main():
    if os.environ.get("GEMINI_PROOFREAD") == "0":
        return 0
    payload = json.load(sys.stdin)
    command = (payload.get("tool_input") or {}).get("command") or ""
    args = commit_args(command)
    if args is None or SKIP_MARK in command:
        return 0
    toplevel = git(payload.get("cwd") or os.getcwd(), "rev-parse", "--show-toplevel").stdout.strip()
    if not toplevel or Path(toplevel).resolve() != REPO:
        return 0
    rewrite = skill_scripts()
    names = target_files(args)
    if rewrite is None or not names:
        return 0

    result = subprocess.run(
        [sys.executable, str(rewrite), "file", *names], cwd=REPO, capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"{FAILED}\n\n{result.stderr.strip()}", file=sys.stderr)
        return 2
    output = json.loads(result.stdout)
    if not output["diff"] and not output["skipped"]:
        return 0
    report = {key: output[key] for key in ("skipped", "originals")}
    print(f"{LEAD}\n\n{json.dumps(report, ensure_ascii=False, indent=2)}\n\n{output['diff']}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
