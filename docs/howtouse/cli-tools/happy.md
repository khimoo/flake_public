# Happy: スマホから Codex を操作する

Happy 本体・Node.js 24・npm 依存関係は Nix が管理する。
`packages/happy/` のバージョンとロックファイルを使うため、`npm install -g` は不要。
Home Manager の `modules/home-manager/dev/apps.nix` から導入する。

## 試す

このリポジトリで次を実行する。システム設定の適用前でも同じパッケージを試せる。

```bash
nix run .#happy -- auth login
```

スマホに [Happy](https://happy.engineering/) の iOS / Android アプリを入れ、
ターミナルで Mobile を選択して、アプリから QR コードを読み取る。
認証情報と機器情報は `~/.happy/` に保存される。Nix ストアや Git には入れない。

ペアリング後、作業したいプロジェクトで起動する。

```bash
nix run /home/pomu/sagyo/flake_public#happy -- codex
```

Home Manager / NixOS の設定を適用した後は、直接実行できる。

```bash
happy codex
```

Happy 経由で開始したセッションをスマホで開き、追加指示や実行承認を行う。
通常の `codex` で開いている会話が自動的に移行するわけではない。
PC は起動・オンライン状態を保つ。

## 停止

Happy は必要に応じてデーモンを起動する。今回の設定ではログイン時の自動起動は追加しない。

```bash
happy daemon status
happy daemon stop
```

設定の適用前は `happy` を `nix run .#happy --` に置き換える。

## パッケージを更新する

1. `packages/happy/package.json` のバージョンと `dependencies.happy`、
   `default.nix` の `version` と起動チェックを更新する。
2. `packages/happy` で `npm install --package-lock-only --ignore-scripts` を実行する。
3. `npmDepsHash` を一時的に `lib.fakeHash` にして `nix build .#happy` を実行し、
   表示された正しいハッシュを設定する。
4. `nix build .#happy` と `nix run .#happy -- --version` を確認する。

依存パッケージのスクリプトは一括実行せず、Happy の同梱ツール展開だけをビルド時に行う。
Linux の同梱 ELF / ネイティブモジュールは `autoPatchelfHook` で Nix のライブラリに接続する。
同梱 libvips は patchelf 0.15.2 で実行セクションが壊れるため修正対象から外す。
ビルド時にバージョン表示だけでなく、PTY / DB の読み込みと PNG の生成も検証する。
1.2.3 の `--version` がログイン処理まで進む不具合も、表示後に終了するパッチで修正する。
更新時には配布ファイル名とパッチの要否も確認する。
