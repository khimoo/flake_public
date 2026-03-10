# NixOS Configuration Flake
普段使っているNixOSの設定です。neovimやweztermのdotfilesも入ってます。

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

