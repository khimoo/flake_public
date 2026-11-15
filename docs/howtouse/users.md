# ユーザー管理

設計: [ユーザー管理](../architecture/users.md)

## ユーザーの追加

`config/hosts/<ホスト>.toml` の `[[users]]` に追加します。ユーザーごとに `purposes` で利用目的を指定します。ユーザーごとの値は同じ `[[users]]` に書きます。リポジトリの持ち主の値（Git identity、エージェント設定、秘密の配置先）は [owner.toml](../../config/owner.toml) にあり、値を使うコンポーネント（`git_identity`、`agent_config`、`personal_files` など）が有効になったユーザーにだけ反映されます。

```toml
[[users]]
name = "alice"
purposes = ["web_procedures"]
admin = true
```

OS アカウントだけを作る場合は `home_manager = false` にします。

```toml
[[users]]
name = "guest"
purposes = []
home_manager = false
initial_hashed_password = "$6$..."
```

| キー | 既定値 | 用途 |
|---|---|---|
| `name` | 必須 | ユーザー名 |
| `purposes` | 必須 | ユーザーの利用目的の一覧。ハードウェアプロファイルだけを使う場合は `[]` |
| `admin` | `false` | wheel と nixos-rebuild の NOPASSWD |
| `home_manager` | `true` | Home Manager の管理対象にする |
| `description` | ユーザー名 | 表示名 |
| `shell` | `"bash"` | nixpkgs 内のシェルのパッケージ名 |
| `extra_groups` | `[]` | 追加グループ |
| `initial_hashed_password` | 未指定 | 初回ログイン用のハッシュ |
| `hashed_password` | 未指定 | rebuild ごとに設定するハッシュ |

ハッシュは `mkpasswd -m sha-512` で作ります。初回用のパスワードはログイン後に `passwd` で変更できます。

## 個人の値と機能の選択

Git identity と checkout の場所は、そのユーザーの TOML に書きます。別のユーザーのファイルは引き継ぎません。

```toml
git_username = "Alice"
git_email = "alice@example.org"
flake_root = "sagyo/flake_public"
```

パスはホームからの相対パスです。

自宅のホストどうしの ssh に使う共有鍵（`~/.ssh/id_lan`）は、ほかのホストへ ssh で接続するコンポーネント（`use_xsaved`、`remote_build` など）が、`lan_ssh_key` を通してユーザーのホームに置きます。どのコンポーネントが置くかは、`lan_ssh_key` を `confgen explain` に渡したときの `required by` で分かります（[confgen](confgen.md#変更の範囲を見る)）。
共有鍵を持つ人はほかのマシンにもログインできるので、ユーザーに選ばせる利用目的に注意してください。`remote_build` はハードウェアプロファイルから入るので、そのホストの全ユーザーが鍵を受け取ります。

GUI の `gui`、`gnome`、`japanese_input` はハードウェアプロファイルの `requires` で選び、音楽アプリはユーザーの `purposes` に `make_music` を指定します。`gnome` と `japanese_input` は `gui` を自動で含めます。詳細は [confgen](confgen.md) と [GUI アプリ](gui-apps.md) を参照してください。

音楽制作は `make_music` を選んだユーザーに audio グループを付与します。VM のユーザーは、`requires` に `windows_vm` を挙げる利用目的（`write_doc_with_windows`、`work_ss`）を自身の `purposes` で選びます（[Windows VM](windows-vm.md)）。

## 管理者の権限と反映

`admin = true` は wheel グループと、`/run/current-system/sw/bin/nixos-rebuild` だけを対象とした NOPASSWD ルールを設定します。管理者として信頼するユーザーだけに付与してください。

```sh
sudo nixos-rebuild switch --flake .#hostname
```
