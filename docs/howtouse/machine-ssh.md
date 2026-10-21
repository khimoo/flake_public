# マシン間 SSH（使い方）

flake 内の NixOS ホスト同士が `ssh <短縮名>` で相互に接続できる。
設計判断は [../architecture/machine-ssh.md](../architecture/machine-ssh.md) を参照。

## 接続

どのホストからでも短縮名（`nixos-` を除いた名前）で繋がる:

```sh
ssh desktop     # = pomu@nixos-desktop.local
ssh spin713     # = pomu@nixos-spin713.local
```

フルネーム（`ssh nixos-desktop.local`）でも可。初回のホスト鍵は自動受理される（accept-new）。

LAN の外からは、末尾に `-ts` を付けた接続名（`ssh desktop-ts`）で tailnet 経由で繋ぐ（[tailscale.md](./tailscale.md)）。

## 鍵の構成

用途ごとにファイルを分けてある。どちらも `secrets/secrets.yaml` から
switch のたびに書き出される（[private-repo-clone.md](./private-repo-clone.md) 参照）。

| ファイル | 用途 | 対になる公開鍵 |
|---|---|---|
| `~/.ssh/id_lan` | LAN 内 machine-to-machine | `hosts/machines.nix` の `lanPublicKey` |
| `~/.ssh/id_github` | GitHub 認証（clone / push） | GitHub アカウントの SSH keys |

`id_lan` は**全マシン共通の 1 本**。マシンごとに別の鍵は作らない。

## マシンを追加するとき

1. 新マシンの `~/.config/sops/age/keys.txt` に age 鍵を置く
   （既存マシンから SSH 送信、または Bitwarden から取得）
2. `hosts/machines.nix` の `machines` に一項目を足す（NixOS 構成も同じ項目に定義する）:
   ```nix
   machines.nixos-newhost = {
     system = "x86_64-linux";
     sshUser = "pomu";
     nixos = {
       users = [{ username = "pomu"; isAdmin = true; }];
       timezone = "Asia/Tokyo";
       stateVersion = "26.05";
     };
   };
   ```
3. 新マシンで rebuild:
   ```sh
   sudo nixos-rebuild switch --flake .#nixos-newhost
   ```

新ユーザーの home で `local.profile.lanSsh = true` を選択すると、switch 中に `id_lan` / `id_github` が書き出され、その時点で新マシンは既存全機と
相互に SSH できる。`authorized_keys` は変わらないので**既存機の rebuild は不要**
（`ssh <新短縮名>` エイリアスを既存機でも使いたいときだけ rebuild する）。

## マシンを廃棄するとき

`hosts/machines.nix` の `machines` からその項目を削除する。SSH 接続先だけから外すなら `sshUser` を外す。ただし共通鍵方式なので、
**行を消しても廃棄機からのログインは止まらない**。締め出したいなら LAN 鍵ごと作り直す（次節）。

## LAN 共通鍵を作り直すとき

紛失・侵害・単なる rotate のいずれでも手順は同じ。

1. 新しい鍵ペアを作る:
   ```sh
   ssh-keygen -t ed25519 -C pomu@lan -f ~/.ssh/id_lan.new -N ''
   ```
2. `hosts/machines.nix` の `lanPublicKey` を `~/.ssh/id_lan.new.pub` の内容に差し替える
3. `secrets/secrets.yaml` の `lan_ssh_key` を新しい秘密鍵で作り直す
   （[private-repo-clone.md の「SSH 鍵を差し替えたとき」](./private-repo-clone.md#ssh-鍵を差し替えたとき)）
4. commit / push
5. **各マシンで** switch してから `update-secrets` を実行する。switch は既存の `~/.ssh/id_lan` を
   上書きしないが、`update-secrets` はこの flake が置いたまま変更されていない鍵を新しい鍵に置き換える:
   ```sh
   sudo nixos-rebuild switch --flake .#<host>
   update-secrets --dry-run   # 置き換える予定のファイルを確かめる
   update-secrets
   ```

`lanPublicKey`（各機の `authorized_keys`）と秘密鍵を同時に変えるので、switch した機から順に、
古い鍵のままの機からの接続が通らなくなる。全機を回りきるまで一部の組み合わせで SSH が通らない。
各マシンを手元で操作できるときに、手元に残しておく機から順に進める。

## 注意

- 対象は `ssh.nix` を読む NixOS ホストのみ。standalone home-manager（macOS）と、
  会社PCの nixos-work-wsl（[wsl.md](./wsl.md)）は LAN の一員とみなさず `id_lan` を配らない
- `PasswordAuthentication = false` なので鍵認証必須。age 鍵を置かずに switch すると
  `id_lan` を書き出せないので activation が error で停止する（[private-repo-clone.md](./private-repo-clone.md) 参照）
- 短縮名（`ssh desktop`）は同一 LAN（mDNS が届く範囲）が前提。LAN の外では `-ts` の接続名を使う（[tailscale.md](./tailscale.md)）

## ユーザープロファイル

既存2台のpomuは `profiles/home/pomu-workstation.nix` で `local.profile.lanSsh = true` を選択しています。新規ユーザーには既定でLAN秘密鍵は配布しません。共有鍵を持つユーザーは接続先の `sshUser` として認証できるため、共有対象を明示的に選んでください。
IdentityFileはログインユーザー自身の `~/.ssh/id_lan`（GitHubは `~/.ssh/id_github`）を参照します。rootは `id_lan` を持たないので、`--build-host` のremote buildは `sudo` を付けずに `--sudo` で実行します。常設のリモートビルド（`local.remoteBuilders`）だけは、nix-daemonがprimaryUserの `id_lan` を絶対パスで読みます（[remote-build.md](./remote-build.md)）。
