# ユーザー管理ガイド

NixOS ホストにユーザーを追加・設定する方法。

> 設計判断・実装の詳細は [docs/architecture/users.md](../architecture/users.md) を参照

## ユーザーの追加

`flake.nix` の該当ホストの `users` リストにエントリを追加する。

### 基本的なユーザー（admin + home-manager 管理）

```nix
{
  username = "pomu";
  isAdmin = true;
  homeFile = ./hosts/nixos-desktop/home-manager-pomu.nix;
}
```

### OS アカウントのみのユーザー（home-manager なし）

```nix
{
  username = "mase";
  isAdmin = false;
  manageHome = false;
  initialHashedPassword = "$6$...";
}
```

`manageHome = false` を設定すると home-manager の管理対象外になる。
Nix で管理しない（自分でホーム環境を設定する）ユーザー向け。

## 属性一覧

| 属性 | 型 | デフォルト | 説明 |
|------|-----|-----------|------|
| `username` | string | (必須) | ユーザー名 |
| `isAdmin` | bool | `false` | `true` で sudo 権限を付与 |
| `manageHome` | bool | `true` | `false` で home-manager をスキップ |
| `homeFile` | path | `hosts/<hostname>/home.nix` | home-manager 設定ファイル |
| `description` | string | `username` | ユーザーの説明 |
| `shell` | package | `pkgs.bash` | ログインシェル |
| `initialPassword` | string | `null` | 初期パスワード（平文） |
| `initialHashedPassword` | string | `null` | 初期パスワード（ハッシュ済み） |
| `hashedPassword` | string | `null` | 固定パスワード（ハッシュ済み） |
| `extraGroups` | list | `[]` | 追加グループ |

### パスワードの設定方法

- `initialPassword` / `initialHashedPassword` — 初回ログイン用。ユーザーが `passwd` で変更可能
- `hashedPassword` — rebuild のたびに強制リセットされる固定パスワード

ハッシュの生成:

```sh
mkpasswd -m sha-512
```

## admin ユーザーの特権

`isAdmin = true` を設定すると:

- `wheel` グループに追加され、`sudo` が使える
- `sudo nixos-rebuild` がパスワードなしで実行できる

これにより以下のコマンドをパスワード入力なしで一気に実行できる:

```sh
nix flake update && sudo nixos-rebuild switch --flake .#hostname
```

> `nixos-rebuild` 以外の sudo 操作には従来通りパスワードが必要。

## home-manager 設定ファイルの配置

`homeFile` で指定するファイルは、そのユーザー固有の home-manager 設定。
共通モジュール（`modules/home-manager/` 以下）は全ユーザーに自動で適用される。

```
modules/home-manager/   ← 全ユーザー共通（flake.nix の homeModules で定義）
hosts/<hostname>/home-manager-<username>.nix  ← ユーザー固有（homeFile で指定）
```

## 反映

```sh
sudo nixos-rebuild switch --flake .#hostname
```
