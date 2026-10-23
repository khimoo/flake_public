# 共通 devShell

`~/sagyo` 内のプロジェクトにおいて、`flake.nix` を個別作成せずに `.envrc` の 1 行だけで利用できる開発環境（devShell）です。
定義ファイルは [devShells/default.nix](../../devShells/default.nix) にあります。

- `rust-bevy`: Bevy、wgpu、winit、egui を使用する Rust 環境（Wayland、Vulkan、X11、alsa、udev のライブラリを同梱）
- `rust-min`: GUI ライブラリが不要な Rust 環境（競技プログラミングや、上流リポジトリのコード読みなど）
- `py-sci`: scipy、pandas、scikit-learn、geopandas、GDAL、GEOS、PROJ を使用する Python 環境
- `ts-web`: ブラウザ拡張機能や SPA 開発向けの TypeScript 環境（nodejs_22、pnpm、yarn を含む）

Rust 向けの devShell には `RUST_SRC_PATH` があらかじめ設定されているため、rust-analyzer を使って標準ライブラリ（std）の定義へスムーズにジャンプできます。

設計：[共通 devShell の設計](../architecture/devshells.md)

## 使い方

```sh
cd ~/sagyo/<repo>
echo 'use flake "/home/pomu/sagyo/flake_public#rust-bevy"' > .envrc
direnv allow
```

`cd` で該当ディレクトリに入ると devShell が自動で有効化され、ディレクトリを出ると解除されます。nix-direnv がビルド結果をキャッシュするため、2 回目以降は即座に読み込まれます。

`.envrc` をコミットしたくない上流のリポジトリでは、あらかじめそのリポジトリローカルの設定で除外してください。

```sh
echo '.envrc'   >> .git/info/exclude
echo '.direnv/' >> .git/info/exclude
```

## トラブルシューティング

- `direnv: error use_flake ...` と表示される場合：`direnv allow` の実行を忘れているか、flake_public の評価でエラーが発生しています。`nix flake show /home/pomu/sagyo/flake_public` で状態を確認してください。
- Rust の LSP がプロジェクトの依存関係を認識しない場合：一度 `cargo check` を実行してください。なお、Bevy は初回の `cargo check` に時間がかかります。
- Python の LSP がプロジェクトの依存関係を認識しない場合：`py-sci` には科学技術計算の共通依存ライブラリしか含まれていません。プロジェクト固有の依存関係は `uv venv` および `uv pip install` でセットアップしてください。pyright は `pyrightconfig.json` の `venvPath` と `venv` 設定を参照します。

## devShell を追加する手順

`devShells/default.nix` に attribute を追加し、`nix flake show /home/pomu/sagyo/flake_public` の出力に含まれることを確認した上で、`.envrc` から参照してください。
