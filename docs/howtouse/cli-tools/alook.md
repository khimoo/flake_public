# Alook: ローカル Web UI を使う

`alook-app` は [Nix パッケージ](../../../packages/alook/) で管理し、
[pomu の個人 profile](../../../profiles/home/pomu.nix) から x86_64-linux に導入する。
Node.js はパッケージに含まれ、エージェントは導入済みの Claude Code / Codex を使う。
操作の根拠は [上流の Quick Start（revision 9f236d1）](https://github.com/alookai/alook/blob/9f236d176f1d7981c8a0c0163bbcd4ae938f87ac/src/app/README.md)。

## 初回と日常の起動

[rebuild・世代切替](../../../README.md#セットアップ適用) 後、初回は利用者が次を実行する。

```sh
alook-app onboard
```

案内に従って初期設定を済ませ、ブラウザーで <http://localhost:15210> を開く。
以後は必要なときにサーバーを手動で起動・停止する。

```sh
alook-app start
alook-app stop
```

デーモンの一覧と状態は次で確認する。

```sh
alook-app daemon list
alook-app daemon status
```

DB・秘密情報・ログは `~/.alook/self-hosted/` に保存される。
起動や接続に問題があるときは、状態と `~/.alook/self-hosted/logs/` のログを確認する。
このディレクトリには秘密情報が含まれるため、Git に入れない。

画面が表示されても一部サービスが動かず、サービスのログに `SQLITE_BUSY` がある場合は、
共有 DB の起動時の競合を解消するため `alook-app stop` の後に `alook-app start` で全体を再起動する。

## 更新と復旧

1. `alook-app stop` でサーバーを停止し、`~/.alook/self-hosted/` 全体を安全な場所へバックアップする。
2. `packages/alook/package.json` の `dependencies."@alook/app"` を更新する。
   Nix パッケージの版はこの値から決まる。
   0.1.60 の同梱デーモンで不足する `quickjs-emscripten` は別途固定しているため、
   上流がこの依存を含めた版へ更新するときは補完の要否も確認する。
   同梱ファイルを Nix ストアからコピーしても設定を更新できるよう、
   [パッチ](../../../packages/alook/writable-install.patch) を当てている。
   上流がコピー先の書き込み権限を保証する版になったら、このパッチを外せる。
3. `packages/alook` で `npm install --package-lock-only --ignore-scripts` を実行する。
4. `packages/alook/default.nix` の `npmDepsHash` を一時的に `lib.fakeHash` にし、
   [検証ガイドの単体 build](../validation.md#対象別の確認手順) の `happy` を `alook` に置き換えて実行する。
   表示された正しいハッシュを設定し、同じ単体 build を再実行する。
5. rebuild して新しい Nix 世代へ切り替えた後、`alook-app update` を実行する。
   この操作は導入済みの版から同梱 assets をコピーし、DB migrations を実行する。新しい版の自動取得は行わない。
6. `alook-app start` で起動し、Web UI とデーモンの状態を確認する。

Nix の rollback だけでは DB migration は元に戻らない。
旧版へ戻すときはサーバーを停止し、対応する更新前のバックアップを復元してから、旧 Nix 世代で起動する。
