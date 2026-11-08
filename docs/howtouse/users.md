# ユーザー管理

設計: [ユーザー管理](../architecture/users.md)

## ユーザーの追加

`config/hosts/<ホスト>.toml` の `[[users]]` に追加します。Home Manager を使うユーザーには、そのホストの `purposes` が適用されます。個人の値は `config/users/<ユーザー>.toml` に置きます。

```toml
[[users]]
name = "alice"
admin = true
```

OS アカウントだけを作る場合は `home_manager = false` にします。

```toml
[[users]]
name = "guest"
home_manager = false
initial_hashed_password = "$6$..."
```

| キー | 既定値 | 用途 |
|---|---|---|
| `name` | 必須 | ユーザー名 |
| `admin` | `false` | wheel と nixos-rebuild の NOPASSWD |
| `home_manager` | `true` | Home Manager の管理対象にする |
| `description` | ユーザー名 | 表示名 |
| `shell` | `"bash"` | nixpkgs 内のシェルのパッケージ名 |
| `extra_groups` | `[]` | 追加グループ |
| `initial_hashed_password` | 未指定 | 初回ログイン用のハッシュ |
| `hashed_password` | 未指定 | rebuild ごとに設定するハッシュ |

ハッシュは `mkpasswd -m sha-512` で作ります。初回用のパスワードはログイン後に `passwd` で変更できます。

## 個人の値と機能の選択

Git identity、checkout の場所、LAN 鍵の配布は、そのユーザーの TOML に書きます。別のユーザーのファイルは引き継ぎません。

```toml
git_username = "Alice"
git_email = "alice@example.org"
flake_root = "sagyo/flake_public"
lan_ssh = false
```

パスはホームからの相対パスです。`lan_ssh = true` は、ホストが `personal_files` を選んでいる場合に共有鍵を配布します。共有鍵を持つ人は他のマシンにもログインできるので、配布するユーザーを選んでください。

GUI と音楽アプリはホストの `purposes` に `gui`、`gnome`、`japanese_input`、`music_production` などを指定します。`gnome` と `japanese_input` は `gui` を自動で含めます。詳細は [confgen](confgen.md) と [GUI アプリ](gui-apps.md) を参照してください。

音楽制作は最初のユーザーに audio グループを付与します。VM の利用者は `windows_vm_users` で指定します（[Windows VM](windows-vm.md)）。

## 管理者の権限と反映

`admin = true` は wheel グループと、`/run/current-system/sw/bin/nixos-rebuild` だけを対象とした NOPASSWD ルールを設定します。管理者として信頼するユーザーだけに付与してください。

```sh
sudo nixos-rebuild switch --flake .#hostname
```
