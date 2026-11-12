# ユーザー管理の設計

使い方: [ユーザー管理](../howtouse/users.md)
実装: [machine_base.star](../../config/elements/machine_base.star) / [factory](../../lib/configurations.nix)

## ユーザーと権限の導出

`config/hosts/<ホスト>.toml` の `users` から、`machine_base` が OS アカウントと sudo を、factory が Home Manager の管理対象を作る。同じ人の一覧を手で合わせずに済む。

全ユーザーに networkmanager グループを付与する。`admin = true` は wheel と nixos-rebuild の NOPASSWD を設定する。audio は `music_production` が行動 `make_music` を選んだ利用者に、libvirtd は `windows_vm` が行動 `use_windows` を選んだ利用者に付与する。

## nixos-rebuild の NOPASSWD

更新中に sudo の認証期限が切れても適用を続けられるよう、管理者は `/run/current-system/sw/bin/nixos-rebuild` をパスワードなしで実行できる。

ユーザーが指定する flake には root で動く activation を含められるため、この権限は実質的に root 権限を委ねる。コマンド名の限定を安全境界とみなさず、既に管理者として信頼するユーザーだけに付与する。

## 個人設定の分離

`home_manager = false` のユーザーには OS アカウントだけを作る。Home Manager の利用者には本人の `[[users]]` の `purposes` で選んだ行動を適用し、個人の値は本人の `config/users/<ユーザー>.toml` から読む。Git identity、鍵、mutable checkout を別ユーザーから継承させない。

confgen の NixOS 設定は各ユーザーの評価結果を合わせる。ホーム側も各ユーザーで評価するため、鍵の復号先と checkout は本人のホームから作る。制約と検証は [構成の境界](configuration.md) を参照。
