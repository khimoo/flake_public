# マシン間 SSH

Flake で管理されている NixOS ホスト同士は、`ssh <短縮名>`（`nixos-` を除いたホスト名）で相互に SSH 接続できます。
接続先ホストおよびログインユーザーは、各ホストの `purposes` に基づいて [connect_ssh.star](../../config/elements/connect_ssh.star) が自動的に解決します。また、LAN 内認証用の公開鍵は [owner.toml](../../config/owner.toml) の `lan_public_key` で一元管理されます。

設計ドキュメント: [マシン間 SSH の設計](../architecture/machine-ssh.md)

## 接続方法

```sh
ssh desktop     # pomu@nixos-desktop.local に接続
ssh spin713     # pomu@nixos-spin713.local に接続
```

`ssh nixos-desktop.local` のように完全修飾名（FQDN）での接続も可能です。初回接続時のホスト鍵は自動的に承認されます（`accept-new`）。

- **LAN 内接続**: 短縮名は mDNS で名前解決されるため、同一 LAN 内でのみ有効です。
- **LAN 外接続**: Tailscale 経由で接続します。`ssh desktop-ts` のようにホスト名末尾に `-ts` を付与してください（詳細は [tailscale.md](./tailscale.md) を参照）。

### 認証の仕組み

認証には全マシン共通の秘密鍵 `~/.ssh/id_lan` を使用します。
他ホストへの SSH 接続を伴うコンポーネント（`use_xsaved`、`remote_build` など）が有効なユーザーに対してのみ、`switch` 実行時に `secrets/secrets.yaml` の `lan_ssh_key` が復号され、`~/.ssh/id_lan` として配置されます（詳細は [private-repo-clone.md](./private-repo-clone.md) を参照）。

> [!WARNING]
> 共通鍵を所持するユーザーは、接続先ホスト側でも「ログインを受け付けるユーザー」として認証されます。ユーザーに割り当てる利用目的（`purposes`）の設定には十分注意してください。

※ GitHub 用の認証には、別鍵である `~/.ssh/id_github` が使用されます。
※ スタンドアロンの home-manager（macOS）および会社用 PC である `nixos-work-wsl`（[wsl.md](./wsl.md)）には `id_lan` は配布されません。

## マシンの追加手順

1. **age 鍵の配置**:
   新しいマシンの `~/.config/sops/age/keys.txt` に age 秘密鍵を配置します（既存マシンから SSH 経由で転送するか、Bitwarden から取得）。
2. **ホスト定義の作成**:
   `config/hosts/<ホスト>.toml` を作成し、ユーザーと利用目的（`purposes`）を定義します。
   - ハードウェアプロファイルの `requires` に `ssh_server`（ログイン受付）および `connect_ssh`（他ホストへの接続）を追加します（`personal_pc` を指定した場合は両方が自動で含まれます）。
   - Tailscale 経由の接続名（`-ts`）も利用する場合は、`requires` に `connect_ssh_tailnet` を追加します（`tailscale` も含まれます）。
   - 詳細は [ホスト追加](../../README.md#新しいホストを追加する) および [ユーザー管理](users.md) を参照してください。
3. **ログイン対象ユーザーの設定**:
   SSH ログインを受け付けるのは所有者アカウントです。`purposes` に `personal_files` が設定されているユーザーの `authorized_keys` に LAN 公開鍵が登録され、`ssh <短縮名>` で接続した際のログイン先アカウントになります（ログイン受付は `ssh_server` が有効なホストに限られます）。
4. **設定の適用**:
   新しいマシンで `switch` を実行します。`lan_ssh_key` の配布対象ユーザーであれば `secrets/secrets.yaml` から `~/.ssh/id_lan` が復号・配置され、即座に既存マシンへ SSH 接続できるようになります。

> [!NOTE]
> 既存マシンの `authorized_keys` への変更は発生しないため、既存マシン側で `switch` を再実行しなくても、新マシンから既存マシンへの接続は可能です。ただし、既存マシンから新マシンへ `ssh <新しい短縮名>` で接続したい場合は、既存マシン側でも `switch` を実行して SSH 設定を更新してください。

## マシンの削除手順

`config/hosts/<ホスト>.toml` を削除します。SSH の接続受付のみを停止したい場合は、該当ホストのハードウェアプロファイルの `requires` から `ssh_server` を除外します。

> [!CAUTION]
> LAN 鍵は共通鍵であるため、設定定義からホストを削除しただけでは、除外したマシンからの他マシンへのログイン権限を遮断できません。該当マシンを完全に締め出す必要がある場合は、後述の「LAN 共通鍵の再生成手順」を実施してください。

## LAN 共通鍵の再生成手順

鍵の紛失・漏洩時、または定期的な鍵更新を行う際の手順です。

1. **新しい鍵対の生成**:
   ローカル端末で以下を実行し、新しい鍵対を作成します。
   ```sh
   ssh-keygen -t ed25519 -C pomu@lan -f ~/.ssh/id_lan.new -N ''
   ```
2. **公開鍵の更新**:
   `config/owner.toml` の `lan_public_key` を `~/.ssh/id_lan.new.pub` の内容に更新します。
3. **秘密鍵の更新**:
   `secrets/secrets.yaml` の `lan_ssh_key` を新しい秘密鍵（`~/.ssh/id_lan.new`）で暗号化・差し替えます（手順詳細は [private-repo-clone.md](./private-repo-clone.md#ssh-鍵を差し替える手順) を参照）。
4. **変更の反映**:
   変更内容をコミットし、リモートリポジトリへ push します。
5. **各ホストへの適用**:
   全マシンで以下を実行して最新設定を適用します。既存の `~/.ssh/id_lan` も新しい秘密鍵に更新されます。
   ```sh
   git pull --ff-only
   sudo nixos-rebuild switch --flake .#<host>
   ```

> [!WARNING]
> 公開鍵と秘密鍵を同時に差し替えるため、`switch` を適用したマシンから順次、古い鍵のまま残っている未更新マシンからの SSH 接続が拒否されるようになります。作業は各マシンを直接ローカル操作できる環境で行い、手元での直接操作が必要な優先度の高いマシンから順に適用してください。
