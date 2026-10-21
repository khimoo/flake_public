# Graphify によるコード・文書探索

Graphify は dev 環境の home.packages に入る任意の探索ツール。
通常の環境適用は利用者が行う。導入後は `graphify --version` で版を確認する。

プロジェクト側の対象・除外・更新方針を確認して実行する。

```sh
graphify extract . --code-only --max-workers 1
graphify query "Symbol" --budget 1500
GRAPHIFY_CLAUDE_CLI_MODEL=sonnet graphify extract . --backend claude-cli --max-concurrency 1 --max-workers 1 --api-timeout 90
```

コード解析はローカル AST のみ。文書解析は認証済み Claude CLI を subprocess として使い、
モデル使用枠を消費する。Claude CLI backend の費用表示 $0 は無料の証明ではない。
CLI の終了コードが 0 でも、失敗・省略された文書がないか警告と manifest を確認する。

スキルは agentConfigRoot 側の共有指示で管理する。graphify install や uv/pip による
自動導入を混ぜず、Nix が提供する graphify コマンドを呼ぶ。
API SDK、MCP サーバー、グローバル Git hook は今回追加しない。

## 更新・除去

flake.lock の nixpkgs-unstable 更新時に package version とスキルの呼出しを照合する。
[検証ガイドの単体 build](validation.md#対象別の確認手順) と一括検証に加え、Graphify の smoke check を実行する。

```sh
nix build .#checks.x86_64-linux.graphify-smoke
```

除去するときは [dev apps](../../modules/home-manager/dev/apps.nix) の Graphify と、
[overlay](../../overlays/unstable-packages.nix)、
[smoke check](../../tests/default.nix) の対応を戻し、利用者が通常の環境適用を行う。
個人認証や既存のエージェント設定は削除しない。

## 設計

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
x86_64 Darwin は対象外。Linux からの Darwin 評価を実機確認と混同しない。

検証は [graphify-smoke](../../tests/default.nix) で実 CLI に Rust fixture を渡し、
原典位置と更新後の削除を確認する。環境全体は [検証ガイド](validation.md) に従う。
