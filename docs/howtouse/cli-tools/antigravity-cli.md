# Antigravity CLI（agy）

Google の Antigravity CLI を `agy` として入れる。
agents-private の gemini-proofread スキルが、Gemini の API で校正できないときと、Gemini 3.8 を指定されたときに使う。
パッケージは [llm-agents.nix](https://github.com/numtide/llm-agents.nix) の `antigravity-cli` を使い、[antigravity_cli.star](../../../config/elements/antigravity_cli.star) が入れる。`claude_code` の `requires` にあり、`needs` で `x86_64_linux` を確かめるので、x86_64 の Linux でないホストで Claude Code を使う利用目的を選ぶと止まる。

## ログイン

引数なしで起動し、ブラウザで Google アカウントにログインする。

```bash
agy
```

ログイン情報は `~/.gemini/antigravity-cli/` に保存される。Nix store や Git には入れない。

## 枠の残量を見る

モデルを呼ばずに、週の枠の残量とリセットの時刻を表示する。

```bash
agy -p /quota
```

## 版を上げる

リポジトリ内で、Claude Code・Codex と共通の input を更新する。

```bash
nix flake update llm-agents
```

[単体 build](../validation.md#対象別の確認手順) と `agy --version` で確認し、[README の適用手順](../../../README.md) に従って rebuild する。上流の定義が自動更新されても、手元の lock を更新して適用するまでは使う版は変わらない。

## 設計

### 使いみち

agents-private の gemini-proofread スキルは、日本語の校正を Gemini の API（無料枠）に送る。
API が失敗したとき（429、5xx、タイムアウトなど）と、人が Gemini 3.8 を指定したときに、`agy -p` で同じ内容を `gemini-3.8-flash` に送る。
Antigravity の枠は API の無料枠とは別で、Google アカウントに紐づく。Google AI の Pro と Ultra 以外は週ごとの枠になる。
2026-09-25 の計測では、約5800字の文書1本の校正で、週の枠の約 2.75% を使った。

### 共通 input で版を固定する

版・URL・ハッシュと NixOS 向けのバイナリ処理は llm-agents.nix に任せる。Nix store に置くことで、版は `flake.lock` に従う。取得元の選択とキャッシュの扱いは [AI エージェントの設計](../../architecture/unstable-packages.md#ai-エージェントは-llm-agentsnix-から取る) を参照。
