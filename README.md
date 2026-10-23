# NixOS Configuration Flake

個人用のNixOS 2台と会社PCのNixOS-WSL、macOS向けHome Manager環境を管理するリポジトリです。

## 構成

| 配置 | 責務 |
|---|---|
| `flake.nix` | ホスト・standalone環境・パッケージ・検証の入口 |
| [hosts/machines.nix](hosts/machines.nix) | マシンの一覧と、NixOS構成・マシン間SSH・リモートビルドへの参加 |
| [lib/configurations.nix](lib/configurations.nix) | `mkSystem` / `mkHome` の組み立て |
| `hosts/` | ハードウェアとホスト固有設定 |
| `profiles/home/` | 個人のGit設定、パス、鍵配布、機能の選択 |
| [modules/home-manager/profile.nix](modules/home-manager/profile.nix) | 型付きの `local.profile` オプション |
| `modules/nixos/`, `modules/home-manager/` | OSとユーザー環境の機能実装 |
| `overlays/`, `packages/` | パッケージ差し替え・独自パッケージ |

[使い方](docs/howtouse/README.md) · [設計判断](docs/architecture/README.md) · [構成の境界](docs/architecture/configuration.md) · [AI作業規約](AGENTS.md)

## 対応範囲

- NixOS: `nixos-desktop`, `nixos-spin713`（x86_64 Linux）。個人プロファイルがGUIとvault同期を選択。音楽制作はホストで選択し、`nixos-desktop` だけで有効。
- NixOS-WSL: `nixos-work-wsl`（x86_64 Linux、会社PC。GUI アプリは WSLg で表示）。`local.restrictedHost` で秘密情報と外部への接続経路を持たせない。[手順](docs/howtouse/wsl.md) · [設計判断](docs/architecture/wsl.md)
- Home Manager: `pomu-macos`（aarch64 Darwin CLI）、`pomu-nixos`（x86_64 Linux GUI・音楽制作）。
- RustOwlの自動導入はx86_64 Linux限定。macOSのGUI・音楽制作・vaultプロファイルは未対応。
- macOS構成の評価と実機での適用は別の確認です。検証範囲は[検証ガイド](docs/howtouse/validation.md)を参照。

## セットアップ・適用

checkoutの既定位置は `<ホーム>/sagyo/flake_public`。別の場所に置く場合は、そのユーザーのhomeモジュールで `local.profile.flakeRoot` を指定します。Neovim・端末設定はこのcheckoutへのlive symlinkなので、適用後もcheckoutを残してください。

初回に個人用の自動cloneを有効にする場合は、[SSH鍵とprivate repo](docs/howtouse/private-repo-clone.md) の前提を満たしてください。鍵配布を選択していないユーザーにはage鍵は不要です。

リポジトリで検証してから、ユーザー自身が適用します:

```sh
bash scripts/check.sh
sudo nixos-rebuild switch --flake .#nixos-desktop
# または standalone Home Manager
home-manager switch --flake .#pomu-macos
```

別ディレクトリからは `--flake /絶対パス/flake_public#<構成名>` を使います。
NixOSで一度 switch を実行すると、`/etc/nixos` が primaryUser のチェックアウト先へのシンボリックリンクに置き換わります。それ以降は、単に `sudo nixos-rebuild switch` を実行するだけで、ホスト名と同じ名前の構成が適用されるようになります（詳細は[仕組み](docs/architecture/configuration.md#etcnixos-のリンク)を参照）。
なお、その際にインストール時の `/etc/nixos` 内のファイルは削除されるため、必要なファイルがある場合はあらかじめリポジトリへ移動しておいてください。

## 新しいホストを追加する

1. `hosts/my-new-host/hardware.nix` に対象機の生成済みハードウェア設定を置く。
2. `hosts/my-new-host/default.nix` を作る:

   ```nix
   { ... }: {
     imports = [ ./hardware.nix ../../modules/nixos/common.nix ];
   }
   ```

3. `hosts/machines.nix` の `machines` に追加する。`nixos` の中身が `mkSystem` の引数になり、`flake.nix` が NixOS 構成を作る:

   ```nix
   my-new-host = {
     system = "x86_64-linux";
     sshUser = "alice"; # マシン間 SSH の接続先にしないなら省く
     nixos = {
       users = [{ username = "alice"; isAdmin = true; }];
       timezone = "Asia/Tokyo";
       stateVersion = "26.05"; # 初回導入時の値を維持する
     };
   };
   ```

Home Managerはユーザーごとに独立した既定値から始まります。GUIや個人設定を追加する場合は `users` の `homeFile` / `homeModules` から指定します。[ユーザー管理](docs/howtouse/users.md)を参照。

同じfactoryの複数ユーザー構成を [tests/default.nix](tests/default.nix) と [ハードウェア代替fixture](examples/new-host.nix) で評価しています。fixtureは実機へ適用する設定ではありません。
