# Graphify によるコード・文書探索

設計: [採用理由と管理境界](../architecture/graphify.md)。
Graphify は dev 環境の home.packages に入る任意の探索ツール。
通常の環境適用は利用者が行う。適用前は次の経路で同じ固定版を試せる。

```sh
nix build .#graphify --out-link /tmp/graphify-result
/tmp/graphify-result/bin/graphify --version
```

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
[検証ガイド](validation.md)の一括検証に加え、Graphify の smoke check を実行する。

```sh
nix build .#graphify .#checks.x86_64-linux.graphify-smoke
```

除去するときは [dev apps](../../modules/home-manager/dev/apps.nix) の Graphify と、
[overlay](../../overlays/unstable-packages.nix)、[flake 出力](../../flake.nix)、
[smoke check](../../tests/default.nix) の対応を戻し、利用者が通常の環境適用を行う。
個人認証や既存のエージェント設定は削除しない。
