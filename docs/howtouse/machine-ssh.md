# マシン間 SSH

flake で管理されている NixOS ホスト同士は、`ssh <短縮名>`（`nixos-` を除いたホスト名）で相互に接続できます。
接続先は [ホストの TOML](../../config/hosts/)、LAN の公開鍵は [machine_ssh.star](../../config/elements/machine_ssh.star) で管理します。

設計ドキュメント: [マシン間 SSH の設計](../architecture/machine-ssh.md)

## 接続方法

```sh
ssh desktop     # pomu@nixos-desktop.local
ssh spin713     # pomu@nixos-spin713.local
```

`ssh nixos-desktop.local` のように完全修飾名で接続することも可能です。初回のホスト鍵は自動的に承認されます（accept-new）。
短縮名は mDNS で名前解決されるため、同じ LAN 内でのみ有効です。LAN 外から接続する場合は、`ssh desktop-ts` のように `-ts` を付けて tailnet 経由で接続します（詳細は [tailscale.md](./tailscale.md) を参照）。

認証には `~/.ssh/id_lan` を使用します。この鍵は全マシン共通の 1 本であり、`personal_files` を選んだホストで `lan_ssh = true` に設定されているユーザーに対してのみ、`switch` 実行時に `secrets/secrets.yaml` から生成・配置されます（[private-repo-clone.md](./private-repo-clone.md) を参照）。
個人の2台は、それぞれのホストの TOML で有効化しています。共通鍵を所持するユーザーは接続先の `ssh_user` として認証されるため、鍵を配布するユーザーは明示的に選定してください。
なお、GitHub 用には別の鍵 `~/.ssh/id_github` を使用します。

スタンドアロンの home-manager（macOS）および会社用 PC の nixos-work-wsl（[wsl.md](./wsl.md)）には `id_lan` を配布しません。

## マシンの追加手順

1. 新しいマシンの `~/.config/sops/age/keys.txt` に age 鍵を配置します（既存マシンから SSH 経由で転送するか、Bitwarden から取得）。
2. `config/hosts/<ホスト>.toml` にユーザーと目的を書き、`ssh_user` を指定します。

   ```toml
   ssh_user = "alice"
   # 既存の purposes に machine_ssh を追加します。
   ```

   tailnet の接続名も使う場合は `tailscale` を選びます。LAN 鍵の配布には `personal_files` と `lan_ssh = true` が必要です。[ホスト追加](../../README.md#新しいホストを追加する)と [ユーザー管理](users.md) を参照してください。

新規ユーザーの TOML またはホストの TOML で `lan_ssh = true` に設定されていれば、`switch` 時に `secrets/secrets.yaml` から `id_lan` が復号されて配置され、その時点で既存の全マシンと相互に SSH 接続できるようになります。
既存マシンの `authorized_keys` は変更されないため、既存マシン側で `switch` を実行する必要はありません（既存マシンから `ssh <新しい短縮名>` で接続したい場合のみ `switch` を実行してください）。

## マシンの削除手順

`config/hosts/<ホスト>.toml` を削除します。SSH の接続対象から外すだけであれば `ssh_user` の指定を削除します。
鍵自体は共通鍵であるため、設定項目を削除しても除外したマシンからのログインを遮断することはできません。完全に締め出す場合は LAN 共通鍵を再生成する必要があります。

## LAN 共通鍵の再生成手順

鍵の紛失や漏洩時、あるいは定期的な鍵更新の際も同様の手順で行います。

1. 端末で `ssh-keygen -t ed25519 -C pomu@lan -f ~/.ssh/id_lan.new -N ''` を実行し、新しい鍵対を作成します。
2. `config/elements/machine_ssh.star` 内の `_LAN_PUBLIC_KEY` を `~/.ssh/id_lan.new.pub` の内容に更新します。
3. `secrets/secrets.yaml` の `lan_ssh_key` を新しい秘密鍵で差し替えます（[private-repo-clone.md](./private-repo-clone.md#ssh-鍵を差し替える手順) を参照）。
4. 変更をコミットして push します。
5. 各マシンで `git pull --ff-only` および `sudo nixos-rebuild switch --flake .#<host>` を実行します。既存の `~/.ssh/id_lan` も新しい鍵に更新されます。

※公開鍵と秘密鍵を同時に差し替えるため、`switch` を実行したマシンから順次、古い鍵のままのマシンからのアクセスが拒否されるようになります。
各マシンを手元で直接操作できる環境で作業し、手元操作に残す優先度が高いマシンから順に作業を進めてください。
