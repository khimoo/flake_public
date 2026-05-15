# NixOS Configuration Flake
普段使っているNixOSの設定です。neovimやweztermのdotfilesも入ってます。

## Features / ワークアラウンド

Nix の純粋性やアプリの制約により、素直に実現できない機能のワークアラウンド一覧。

### Teams マルチアカウント (`gui/teams-dispatcher.nix`)

teams-for-linux はマルチアカウントに対応しておらず、切り替えに毎回ログアウトが必要。
複数インスタンスを `--partition` で起動し、URL ディスパッチャで Teams リンクだけ [Junction](https://apps.gnome.org/Junction/)（アプリ選択ダイアログ）を表示することで、開き先を手動選択できるようにしている。

- Junction 自体に URL フィルタリング機能がないため、シェルスクリプトでラップして Teams URL のみ Junction に振り分け、他は Firefox に直接渡す
- teams-for-linux の公式マルチプロファイル機能 ([#1830](https://github.com/IsmaelMartinez/teams-for-linux/issues/1830)) が完成すれば不要になる

### RustOwl (`dev.nix` の `home.activation.rustowl`)

RustOwl は特定の nightly Rust sysroot を必要とし、nixpkgs でのパッケージングが困難。
GitHub Releases のプリビルドバイナリを Nix store 外（`~/.local/share/rustowl/`）に展開し、NixOS の動的リンカパスに合わせて patchelf で修正している。

- impure な要素であり、`home.activation` で命令的にインストールされる
- 詳細は `CLAUDE.md` の「Nix の純粋性から外れている要素」を参照

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

