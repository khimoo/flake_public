# ユーザー管理の設計

設定ファイル: `modules/nixos/users.nix`

> 使い方は [docs/howtouse/users.md](../howtouse/users.md) を参照

## 設計方針

### データ駆動のユーザー生成

ユーザー定義は `flake.nix` の `users` リストに集約し、`users.nix` はそのリストから NixOS 設定を導出する。
OSアカウントは属性値から導出し、ユーザー環境は本人の `homeFile` / `homeModules` に分離する。

```
flake.nix (users リスト)  →  users.nix (users.users / sudo を導出)
                           →  lib/configurations.nix 内 (home-manager ユーザーを導出)
```

`users.nix` は `users` リストのみに依存し、ホスト固有の知識を持たない。

### isAdmin による権限の導出

`isAdmin = true` から以下を自動導出する:

- `wheel` グループへの追加（sudo 権限）
- `nixos-rebuild` の NOPASSWD ルール

フラグ一つで関連する権限がすべて揃うようにし、設定漏れを防ぐ。

### nixos-rebuild の NOPASSWD

```nix
security.sudo.extraRules = let
  adminUsers = builtins.filter (user: user.isAdmin or false) users;
in map (user: {
  users = [ user.username ];
  commands = [{
    command = "/run/current-system/sw/bin/nixos-rebuild";
    options = [ "NOPASSWD" ];
  }];
}) adminUsers;
```

**導入の動機**: `nix flake update && sudo nixos-rebuild switch` を一連で実行する際、
`nix flake update` の所要時間が sudo のタイムスタンプキャッシュ（デフォルト15分）を超えると
再度パスワードを求められる問題の解消。

**セキュリティ上の判断**: NOPASSWD の対象を `/run/current-system/sw/bin/nixos-rebuild` に限定。
ユーザーが指定したflakeにはrootで実行されるactivation処理を含められるため、これは実質的にroot権限を委ねる設定。
コマンド名の限定を安全境界とみなさず、既に管理者として信頼するユーザーだけに付与する。

### 共通グループの一括付与

全ユーザーに `networkmanager`, `libvirtd`, `adbusers` を付与している。
これはこの Flake が個人利用を前提としており、全ユーザーが同じ機能を使う想定のため。

### home-manager との境界

ユーザーの OS アカウント管理は `users.nix`、ホーム環境管理は `lib/configurations.nix` の home-manager 設定が担当する。
`manageHome = false` のユーザーは home-manager の対象外となり、`users.nix` による OS アカウントのみ作成される。

この分離により、Nix 管理外のユーザー（自分でホーム環境を設定したい人）にも対応できる。

## 個人設定の分離

Home Manager全員へ共通の個人settingsを渡す方式を廃止した。`local.profile` の既定は個人情報も鍵配布も持たず、pomuのprofileはpomuのhomeFileだけがimportする。
新規ユーザーを追加してもage鍵の設置やpomuのcheckoutへのアクセスは要求されない。制約と検証は[構成の境界](./configuration.md)を参照。
