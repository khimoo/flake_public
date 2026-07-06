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

## マシンを追加するとき

1. 新マシンで ed25519 鍵を用意（無ければ生成。既存鍵は壊さない）:
   ```sh
   ls ~/.ssh/id_ed25519 || ssh-keygen -t ed25519
   ```
2. 公開鍵を取得:
   ```sh
   cat ~/.ssh/id_ed25519.pub
   ```
3. `hosts/machines.nix` に1行足す:
   ```nix
   nixos-newhost = "ssh-ed25519 AAAA... pomu@nixos-newhost";
   ```
4. rebuild（新マシン＋既存マシン群。既存機は新しい鍵を `authorized_keys` に取り込むため）:
   ```sh
   sudo nixos-rebuild switch --flake .#<host>
   ```

これで新マシンは全既存機と相互に SSH でき、`ssh <短縮名>` エイリアスも全機で使える。

> secret（Zotero 同期など）も使うマシンなら、同じ鍵を age 形式に変換して `.sops.yaml`
> にも登録する。手順は [zotero-gdrive-sync.md](./zotero-gdrive-sync.md) を参照。

## マシンを廃棄するとき

`hosts/machines.nix` からその行を削除して各機を rebuild。以降そのマシンの鍵では
ログインできなくなる。secret を扱っていたら `.sops.yaml` からも受信者を外して
`sops updatekeys`。

## 注意

- 対象は NixOS ホストのみ（`ssh.nix` は NixOS モジュール）。standalone home-manager
  （macOS 等）は現状この生成対象外
- `PasswordAuthentication = false` なので鍵認証必須。新マシンの鍵を `machines.nix` に
  登録して rebuild するまでは、そのマシンへは入れない
- 同一 LAN（mDNS が届く範囲）が前提。VLAN 分離・VPN 越しでは別途 `/etc/hosts` 等が要る
