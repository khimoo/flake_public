# ユーザー管理

NixOS ホストにおけるユーザーの追加と設定方法について解説します。

設計ドキュメント: [ユーザー管理の設計](../architecture/users.md)

## ユーザーの追加

`hosts/machines.nix` の `machines.<ホスト>.nixos.users` リストに設定を追加します。

### 基本的なユーザー（管理者権限 + Home Manager 管理）

```nix
{
  username = "pomu";
  isAdmin = true;
  homeFile = ./nixos-desktop/home-manager-pomu.nix;
  # 各ユーザーは専用の homeFile を指定してください。pomu 用の設定を共用してはいけません。
}
```

### OS アカウントのみのユーザー（Home Manager 管理なし）

```nix
{
  username = "mase";
  isAdmin = false;
  manageHome = false;
  initialHashedPassword = "$6$...";
}
```

`manageHome = false` を指定すると Home Manager の管理対象外となります。
Nix で環境を管理せず、シェルやホーム環境を手動でカスタマイズしたいユーザー向けの設定です。

## 属性一覧

| 属性名 | 型 | デフォルト値 | 説明 |
|------|-----|-----------|------|
| `username` | string | (必須) | ユーザー名 |
| `isAdmin` | bool | `false` | `true` で sudo 権限を付与 |
| `manageHome` | bool | `true` | `false` で Home Manager による管理をスキップ |
| `homeFile` | path または null | `null` | ユーザー固有の Home Manager モジュールパス |
| `homeModules` | list | `[]` | 該当ユーザーにのみ追加するモジュールのリスト |
| `description` | string | `username` | ユーザーの表示名・説明 |
| `shell` | package | `pkgs.bash` | デフォルトのログインシェル |
| `initialPassword` | string | `null` | 初期パスワード（平文） |
| `initialHashedPassword` | string | `null` | 初期パスワード（ハッシュ済み文字列） |
| `hashedPassword` | string | `null` | 固定パスワード（ハッシュ済み文字列） |
| `extraGroups` | list | `[]` | 所属させる追加グループ |

## ユーザープロファイル

新規追加されたユーザーのホーム環境は最小限の CLI 構成から始まり、既存ユーザーの Git identity、プライベートリポジトリ、SSH 鍵などを自動で引き継ぐことはありません。
個人設定は `homeFile` 内で個別に指定します:

```nix
{ config, ... }: {
  local.profile = {
    gitUsername = "Alice";
    gitUserEmail = "alice@example.org";
    flakeRoot = "${config.home.homeDirectory}/sagyo/flake_public";
    features = { gui = true; gnome = true; ime = true; };
    # 共有 LAN 鍵の配布が必要なユーザーのみ、明示的に true を指定します。
    lanSsh = false;
  };
}
```

全オプションの型定義およびデフォルト値は [profile.nix](../../modules/home-manager/profile.nix) が正本となります。
2 台のマシンで共有される pomu の個人設定は [pomu-workstation.nix](../../profiles/home/pomu-workstation.nix)、スタンドアロン環境用の identity は [pomu.nix](../../profiles/home/pomu.nix) に定義されています。
`mkHome` を利用する場合も、同様に `homeFile` や `modules` を通じて設定します。

### パスワードの設定方針

- `initialPassword` / `initialHashedPassword`: 初回ログイン用の一時パスワードです。ユーザー自身がログイン後に `passwd` コマンドで変更できます。
- `hashedPassword`: rebuild を実行するたびに強制的に上書きされる固定パスワードです。

パスワードハッシュの生成コマンド:

```sh
mkpasswd -m sha-512
```

## 管理者（admin）ユーザーの権限

`isAdmin = true` を設定すると、以下の特権が付与されます:

- `wheel` グループに追加され、`sudo` コマンドが利用可能になる
- `sudo nixos-rebuild` をパスワードなしで実行可能になる（`nix flake update && sudo nixos-rebuild switch --flake .#hostname` などの一連の更新作業をスムーズに行えます）

※ `nixos-rebuild` 以外のコマンドで sudo を実行する際は、通常どおりパスワードが要求されます。

## Home Manager 設定ファイルの配置規則

`homeFile` に指定するファイルには、そのユーザー固有の Home Manager 設定を記述します。
共通モジュール（`modules/home-manager/` 配下）は、全ユーザーへ自動的に読み込まれます。

```
modules/home-manager/   ← 全ユーザー共通（lib/configurations.nix の homeModules が起点）
hosts/<hostname>/home-manager-<username>.nix  ← ユーザー固有設定（homeFile で指定）
```

`dev/`、`gui/`、`audio/` の配下にある子モジュールは、それぞれのディレクトリの `default.nix` 経由で読み込まれます。共通モジュールとして読み込まれていても、GUI などのオプショナル機能はユーザー自身の `local.profile.features` で明示的に有効化しない限り適用されません。詳細は [GUI アプリの管理](gui-apps.md) を参照してください。

## 音楽制作環境・VM を利用するユーザーの設定

ホスト単位の機能有効化は `local.music.enable` および `local.vm.enable` で行います。対象ユーザーはそれぞれ `local.music.users` と `local.vm.users` で指定し、未指定時のデフォルトは primaryUser となります。`audio` や `libvirtd` グループへの所属はこれらの対象ユーザーにのみ限定して付与されます。音楽制作アプリや Windows VM のランチャーは、該当ユーザーのうち Home Manager を利用しているユーザーに対してセットアップされます。VM に関する詳細は [Windows VM](windows-vm.md) を参照してください。

## 反映

```sh
sudo nixos-rebuild switch --flake .#hostname
```
