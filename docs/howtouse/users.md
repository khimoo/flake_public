# ユーザー管理

設計方針については [ユーザー管理](../architecture/users.md) を参照してください。

## ユーザーの追加

ユーザーを追加するには、`config/hosts/<ホスト>.toml` の `[[users]]` に設定を記述します。各ユーザーの利用目的は `purposes` で指定します。

リポジトリ所有者の設定（Git identity、エージェント設定、秘密情報の配置先など）は [owner.toml](../../config/owner.toml) で管理されており、対応するコンポーネント（`git_identity`、`agent_config`、`personal_files` など）が有効化されたユーザーにのみ反映されます。

```toml
[[users]]
name = "alice"
purposes = ["web_procedures"]
admin = true
```

OSアカウントのみを作成し、Home Managerの管理対象外とする場合は `home_manager = false` を指定します。

```toml
[[users]]
name = "guest"
purposes = []
home_manager = false
initial_hashed_password = "$6$..."
```

### パラメータ一覧

| キー | 必須/既定値 | 説明 |
|---|---|---|
| `name` | 必須 | ユーザー名 |
| `purposes` | 必須 | 利用目的のリスト。ハードウェアプロファイルのみ使用する場合は `[]` |
| `admin` | `false` | `wheel` グループへの追加および `nixos-rebuild` の NOPASSWD 許可 |
| `home_manager` | `true` | Home Manager の管理対象とするか |
| `description` | ユーザー名 | 表示名 |
| `shell` | `"bash"` | nixpkgs 内のシェルパッケージ名 |
| `extra_groups` | `[]` | 追加するグループのリスト |
| `initial_hashed_password` | 未指定 | 初回ログイン用パスワードハッシュ |
| `hashed_password` | 未指定 | rebuild ごとに強制適用されるパスワードハッシュ |

パスワードハッシュは `mkpasswd -m sha-512` コマンドで生成できます。`initial_hashed_password` を使用した場合、初回ログイン後に `passwd` コマンドで変更可能です。

## 個人の設定と機能の選択

Git identity やチェックアウト先などの個人設定は、ホストの TOML の該当ユーザーの `[[users]]` に記述します（他ユーザーの設定は引き継がれません）。

```toml
git_username = "Alice"
git_email = "alice@example.org"
flake_root = "sagyo/flake_public"
```

※ パスはホームディレクトリからの相対パスで指定します。

### LAN内 SSH共有鍵の配置
宅内ホスト間の SSH 接続に使用する共有鍵（`~/.ssh/id_lan`）は、他ホストへ SSH 接続を行うコンポーネント（`use_xsaved`、`remote_build` など）が有効な場合、`lan_ssh_key` を通じてホームディレクトリに配置されます。どのコンポーネントが鍵を要求しているかは、`confgen explain` で `lan_ssh_key` の `required by` を確認してください（詳細は [confgen](confgen.md#変更の影響範囲を確認する) を参照）。

※ 共有鍵を持つユーザーは他のマシンへもログイン可能になるため、割り当てる `purposes` には注意してください。なお、`remote_build` はハードウェアプロファイル単位で適用されるため、該当ホストの全ユーザーに鍵が配置されます。

### 機能と利用目的（purposes）の指定
- **GUI関連**: `gui`、`gnome`、`japanese_input` はハードウェアプロファイルの `requires` で指定します（`gnome` と `japanese_input` は自動的に `gui` を含みます）。詳細は [confgen](confgen.md) および [GUI アプリ](gui-apps.md) を参照してください。
- **音楽制作**: `purposes` に `make_music` を指定すると、該当ユーザーが `audio` グループに追加されます。
- **Windows VM**: VM を使うユーザーは、`requires` に `windows_vm` を挙げる利用目的（`write_doc_with_windows`、`work_ss`）を自身の `purposes` に指定します（詳細は [Windows VM](windows-vm.md) を参照）。

## 管理者権限（admin）

`admin = true` を設定すると、該当ユーザーに `wheel` グループ権限が付与され、`/run/current-system/sw/bin/nixos-rebuild` の実行時にパスワード入力が不要（NOPASSWD）になります。セキュリティ上の理由から、管理者として信頼できるユーザーにのみ付与してください。

```sh
sudo nixos-rebuild switch --flake .#hostname
```
