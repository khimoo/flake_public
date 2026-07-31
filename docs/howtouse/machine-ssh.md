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
2. `hosts/machines.nix` の `hosts` に1行足す:
   ```nix
   hosts = [
     "nixos-desktop"
     "nixos-spin713"
     "nixos-newhost"
   ];
   ```
3. 新マシンで rebuild:
   ```sh
   sudo nixos-rebuild switch --flake .#nixos-newhost
   ```

switch 中に `id_lan` / `id_github` が書き出され、その時点で新マシンは既存全機と
相互に SSH できる。`authorized_keys` は変わらないので**既存機の rebuild は不要**
（`ssh <新短縮名>` エイリアスを既存機でも使いたいときだけ rebuild する）。

## マシンを廃棄するとき

`hosts/machines.nix` の `hosts` からその行を削除する。ただし共通鍵方式なので、
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
5. **各マシンで**古い鍵を退けてから switch する。activation は既存ファイルを上書きしない:
   ```sh
   rm ~/.ssh/id_lan
   sudo nixos-rebuild switch --flake .#<host>
   ```

最後に switch した機が古い鍵のままの機を締め出すので、全機を回りきるまで一部の
組み合わせで SSH が通らない時間がある。手元に残しておく機から順に進める。

## 注意

- 対象は NixOS ホストのみ（`ssh.nix` は NixOS モジュール）。standalone home-manager
  （macOS / WSL）は LAN の一員とみなさず `id_lan` を配らない
- `PasswordAuthentication = false` なので鍵認証必須。age 鍵を置かずに switch すると
  `id_lan` を書き出せないので activation が error で停止する（[private-repo-clone.md](./private-repo-clone.md) 参照）
- 同一 LAN（mDNS が届く範囲）が前提。VLAN 分離・VPN 越しでは別途 `/etc/hosts` 等が要る
