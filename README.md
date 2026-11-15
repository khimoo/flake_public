# NixOS Configuration Flake

個人用のNixOS 2台と会社PCのNixOS-WSL、macOS向けHome Manager環境を管理するリポジトリです。

解きたい課題と、それを解く規則 A と規則 B は、[flake_public のあるべき姿](docs/architecture/rules.md) に書いています。

## 構成

| 配置 | 責務 |
|---|---|
| `flake.nix` | 構成・パッケージ・検証の入口 |
| [config/hosts/](config/hosts/) | ホストの一覧、ハードウェアプロファイル、ユーザーごとの利用目的、ホスト固有の値 |
| [config/owner.toml](config/owner.toml) | Git identity、エージェント設定、秘密の配置先など、リポジトリの持ち主の値 |
| [config/elements/](config/elements/) | 選んだハードウェアプロファイルと利用目的から設定を生成する処理 |
| [lib/configurations.nix](lib/configurations.nix) | `mkSystem` / `mkHome` の組み立て |
| `hosts/` | 生成済みハードウェア設定 |
| `modules/` | コンポーネントから参照するスクリプトと設定ファイル |
| `overlays/`, `packages/` | パッケージ差し替え・独自パッケージ |

[使い方](docs/howtouse/README.md) · [設計判断](docs/architecture/README.md) · [構成の境界](docs/architecture/configuration.md) · [AI作業規約](AGENTS.md)

## 対応範囲

- NixOS: `nixos-desktop`, `nixos-spin713`（x86_64 Linux）。GUI はハードウェアプロファイルの `requires`、vault 同期はユーザーの利用目的 `grow_notes` で選択。音楽制作はユーザーの利用目的 `make_music` で選択し、`nixos-desktop` だけで有効。
- NixOS-WSL: `nixos-work-wsl`（x86_64 Linux、会社PC。GUI アプリは WSLg で表示）。秘密情報と自宅への接続経路を持たせない。[手順](docs/howtouse/wsl.md) · [設計判断](docs/architecture/wsl.md)
- Home Manager 単独: `pomu-macos`（aarch64 Darwin CLI）は使い始めるまで `flake.nix` で外している。書き方は「新しいホストを追加する」の例を参照。
- RustOwlの自動導入はx86_64 Linux限定。macOSのGUI・音楽制作・vaultプロファイルは未対応。
- macOS構成の評価と実機での適用は別の確認です。検証範囲は[検証ガイド](docs/howtouse/validation.md)を参照。

## セットアップ・適用

checkoutの既定位置は `<ホーム>/sagyo/flake_public`。別の場所に置く場合は、ホストの TOML のユーザーの `[[users]]` に、`flake_root` をホームからの相対パスで指定します。Neovim・端末設定はこのcheckoutへのlive symlinkなので、適用後もcheckoutを残してください。

初回に個人用の自動cloneを有効にする場合は、[SSH鍵とprivate repo](docs/howtouse/private-repo-clone.md) の前提を満たしてください。鍵配布を選択していないユーザーにはage鍵は不要です。

リポジトリで検証してから、ユーザー自身が適用します:

```sh
bash scripts/check.sh
sudo nixos-rebuild switch --flake .#nixos-desktop
# または Home Manager 単独のホスト（ホストの TOML に kind = "home" を書いたもの）
home-manager switch --flake .#<構成名>
```

別ディレクトリからは `--flake /絶対パス/flake_public#<構成名>` を使います。
NixOSで `etc_nixos_link` を選んだユーザーがいる場合、switch を実行すると、`/etc/nixos` が選んだユーザーのチェックアウト先へのシンボリックリンクに置き換わります。それ以降は、単に `sudo nixos-rebuild switch` を実行するだけで、ホスト名と同じ名前の構成が適用されるようになります（詳細は[仕組み](docs/architecture/configuration.md#etcnixos-のリンク)を参照）。
なお、その際にインストール時の `/etc/nixos` 内のファイルは削除されるため、必要なファイルがある場合はあらかじめリポジトリへ移動しておいてください。

## 新しいホストを追加する

1. `hosts/my-new-host/hardware.nix` に対象機の生成済みハードウェア設定を置く。
2. `config/elements/machine_my_new_host.star` を作り、ハードウェアを import する:

   ```python
   requires = ["machine_base", "systemd_boot", "network_manager"]

   def config():
       return {"nixos_imports": [repoModule("hosts/my-new-host/hardware.nix")]}
   ```

3. `config/hosts/my-new-host.toml` に構成の値、ハードウェアプロファイル、ユーザーごとの利用目的を書く:

   ```toml
   hostname = "my-new-host"
   system = "x86_64-linux"
   kind = "nixos"
   state_version = "26.05"
   timezone = "Asia/Tokyo"
   machine = "machine_my_new_host"

   [[users]]
   name = "alice"
   purposes = ["web_procedures"]
   admin = true
   ```

Home Manager だけで管理するホストは `kind = "home"` にし、NixOS の設定を作らないので、ハードウェアプロファイルの `requires` に `nixos_system` を書きません。`home-manager switch --flake .#<構成名>` で適用します。

`state_version` は初回導入時の値を維持します。マシン間 SSH に参加する場合は、ハードウェアプロファイルの `requires` に `ssh_server` と `connect_ssh` を追加し（`personal_pc` は両方を含みます）、ログインを受け付ける持ち主のアカウントの `purposes` に `personal_files` を入れます。tailnet 越しの接続名（`-ts`）も使うなら、同じ `requires` に `connect_ssh_tailnet` を追加します（`tailscale` も入ります）。

持ち主の値は `config/owner.toml` に、ユーザーごとの値はホストの TOML の `[[users]]` に書きます。[ユーザー管理](docs/howtouse/users.md)と [confgen](docs/howtouse/confgen.md)を参照してください。

複数ユーザー構成は [tests/default.nix](tests/default.nix) と [ハードウェア代替fixture](examples/new-host.nix) で評価しています。fixture は実機へ適用する設定ではありません。

## TODO

- 会社 PC（`nixos-work-wsl`）で、秘密の復号や Git identity を入れる利用目的を選んだとき、設定の生成を止める仕組み。今は止まらない。自宅への接続経路は [isolation.nix](hosts/nixos-work-wsl/isolation.nix) の assertion が評価を止め、x86_64 Linux でしか動かないコンポーネントは `needs` で生成が止まる。
