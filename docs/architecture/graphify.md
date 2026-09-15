# Graphify の導入判断

利用: [Graphify による探索](../howtouse/graphify.md)。

安定チャンネルには Graphify が存在しないため、既存 flake.lock の nixpkgs-unstable にある
0.9.53 を利用する。package と Python・tree-sitter grammar の組合せを Nix に任せ、
独自の package 定義や起動時 download は増やさない。パッケージ更新は lock 更新で行う。

上流: [Graphify v0.9.53](https://github.com/Graphify-Labs/graphify/tree/33362d969292b57eda82f3fbd9eb5f3f5bc9bbc2)。
公式 CLI の code-only extract、query、claude-cli backend を利用する。

上流スキルは uv/pip の自動導入と Python interpreter 探索を含むため、そのまま起動すると
Nix の固定版を迂回し得る。共有する薄いスキル本文は外部の agentConfigRoot に置き、
この公開 repo は CLI と既存の配線だけを所有する。private repo の内容や固有パスに依存しない。

Graphify は原典を探すための派生グラフ。設計意図や実行時の順序保証を置き換えない。
文書意味解析の更新と AST 更新は別に扱い、任意の探索にモデル利用を強制しない。
通常起動や activation で生成・更新・認証・hook install を実行しない。

既存の Linux、aarch64 Darwin dev 環境を対象とする。上流 package の対応に含まれない
x86_64 Darwin には package 出力を追加しない。Linux からの Darwin 評価を実機確認と混同しない。

検証は [graphify-smoke](../../tests/default.nix) で実 CLI に Rust fixture を渡し、
原典位置と更新後の削除を確認する。環境全体は [検証ガイド](../howtouse/validation.md) に従う。
