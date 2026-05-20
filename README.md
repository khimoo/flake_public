# NixOS Configuration Flake
普段使っているNixOSの設定です。neovimやweztermのdotfilesも入ってます。

## Features / ワークアラウンド

Nix の純粋性やアプリの制約により、素直に実現できない機能のワークアラウンド一覧。
詳細は [docs/architecture/](./docs/architecture/) を参照。

- **Teams マルチアカウント** — URL ディスパッチャで Teams リンクだけ Junction に振り分け ([詳細](./docs/architecture/teams-dispatcher.md))
- **RustOwl** — impure なプリビルドバイナリを patchelf で NixOS 対応 ([詳細](./docs/architecture/rustowl.md))
- **XDG スキームハンドラ** — NixOS が自動登録しないため手動設定 ([詳細](./docs/architecture/xdg-scheme-workaround.md))

## セットアップ
### 設定の適用
1. flake.nixにあるhost名と環境のホスト名を一致させる。
1. `flake.nix` を `/etc/nixos/flake.nix` にシンボリックリンク
    1. $sudo ln -s $(pwd)/flake.nix /etc/nixos/flake.nix

こうすると、/etc/nixos/flake.nixのホスト名が環境のホスト名と一致する上、/etc/nixos/flake.nixからはこのリポジトリの各ファイルが見えるようになるので、カレントディレクトリを問わずsudo nixos-rebuild switchが実行できるようになります。

### 新しいホストの追加方法
1.  `hosts/` ディレクトリ配下に新しいホスト名のディレクトリを作成します（例: `hosts/my-new-host/`）。
2.  作成したディレクトリに以下のファイルを作成します。
    *   `default.nix`: NixOS システム全体の設定
    *   `home.nix`: Home Manager のユーザー設定
    *   `hardware.nix`: `nixos-generate-config` で生成されたハードウェア設定など
3.  `flake.nix` の `nixosConfigurations` セクションに新しいホストの設定を追加します。`mkSystem` ヘルパー関数を使用して以下みたいな感じにしてください。
```nix
nixosConfigurations = {
  # ...
  my-new-host = mkSystem {
    hostname = "my-new-host";
    system = "x86_64-linux";
    username = "username";
    timezone = "Asia/Tokyo";
    keymap = "us";
    stateVersion = "25.11";
  };
};
```

