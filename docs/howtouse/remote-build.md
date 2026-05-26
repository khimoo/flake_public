# リモートビルドガイド

ラップトップ（`nixos-spin713`）で `nixos-rebuild` を実行する際に、ビルドだけをデスクトップ（`nixos-desktop`）にオフロードする運用方法。成果物のみがラップトップに転送され、アクティベートは手元で行われる。

> 設計判断・実装の詳細は [docs/architecture/remote-build.md](../architecture/remote-build.md) を参照

## 前提条件

| 項目 | 要件 |
|------|------|
| ネットワーク | ラップトップとデスクトップが同一 LAN（mDNS が届く範囲） |
| アーキテクチャ | 両ホストとも `x86_64-linux`（クロスビルドはしない） |
| SSH 鍵 | ラップトップ `pomu` の公開鍵がデスクトップに登録済み |
| SSH エージェント | ラップトップ側で `ssh-add` 済み（鍵にパスフレーズがある場合） |

設定ファイル側は既に構成済み：

- デスクトップ：`services.openssh.enable`、`nix.settings.trusted-users = [ "@wheel" ]`、`users.users.pomu.openssh.authorizedKeys.keys`
- ラップトップ：`programs.ssh.extraConfig` に `StrictHostKeyChecking accept-new`（初回接続時に host key を自動受け入れ）
- 両ホスト：`services.avahi.publish` で `<hostname>.local` を LAN に広告

## 基本コマンド

ラップトップ側で：

```sh
sudo nixos-rebuild switch \
  --flake .#nixos-spin713 \
  --build-host pomu@nixos-desktop.local
```

- `--build-host` 指定先（デスクトップ）でビルドが実行される
- 完了後、結果のストアパスがラップトップに転送される
- アクティベート（switch）はラップトップ上で行われる

`sudo` を付けた場合でも、SSH 接続には `SSH_AUTH_SOCK` が引き継がれるため、ラップトップユーザのエージェントに登録された鍵で `pomu@nixos-desktop.local` に認証する（`modules/nixos/users.nix` 参照）。

## 動作確認

セットアップ直後に確認すべき項目：

```sh
# 1. mDNS 名前解決
ping -c 1 nixos-desktop.local

# 2. SSH 疎通
ssh pomu@nixos-desktop.local 'echo ok'

# 3. リモート Nix が trusted-users として動くか
ssh pomu@nixos-desktop.local 'nix store ping --store daemon'
```

3 が通れば `--build-host` も通る。

## トラブルシューティング

### `ping: nixos-desktop.local: System error`（初回のみ）

avahi のキャッシュが温まっていないだけ。数秒待ってから再実行すると応答する。常時再発する場合は次項を疑う。

### 名前解決が変なアドレス（`192.168.122.*`）に向く

デスクトップで `libvirt` の `virbr0` を経由した IP が mDNS で広告されると、LAN 外からは到達できない。デスクトップ上で `getent hosts nixos-desktop.local` を実行して `192.168.11.*`（LAN 側）以外が返るなら、`services.avahi.denyInterfaces = [ "virbr0" "vnet*" ];` を `modules/nixos/ssh.nix` に追加して LAN 以外の IF を除外する。

### `error: cannot add path '/nix/store/...' because it lacks a signature`

接続元ユーザがリモートの `nix.settings.trusted-users` に入っていない。デスクトップ側の `nix.settings.trusted-users` を確認する（`@wheel` グループに `pomu` が入っていれば通る）。

### `Host key verification failed`

`/root/.ssh/known_hosts` に `nixos-desktop.local` のエントリが無く、かつ `accept-new` が効いていない。`programs.ssh.extraConfig`（ラップトップの `hosts/nixos-spin713/default.nix`）に `StrictHostKeyChecking accept-new` が含まれているか確認。手動回避は `sudo ssh-keyscan -H nixos-desktop.local >> /root/.ssh/known_hosts`。

### SSH 認証で鍵が使われずパスワードを聞かれる

`sudo` 経由の SSH で `SSH_AUTH_SOCK` が引き継がれていない可能性。ラップトップで `sudo env | grep SSH_AUTH_SOCK` を確認。`users.nix` の `Defaults env_keep += "SSH_AUTH_SOCK"` が効いていれば値が表示される。

## 新しいビルダー／クライアントを追加するとき

### クライアントを増やす（新しいホストからデスクトップでビルド）

1. 新規ホストで SSH 鍵を生成：`ssh-keygen -t ed25519`
2. 公開鍵を `hosts/nixos-desktop/default.nix` の `users.users.pomu.openssh.authorizedKeys.keys` に追加
3. デスクトップを rebuild：`sudo nixos-rebuild switch --flake .#nixos-desktop`
4. 新規ホスト側に `programs.ssh.extraConfig` で `StrictHostKeyChecking accept-new`（または declarative に host key を `programs.ssh.knownHosts` で登録）

### ビルダーを増やす（別のホストもビルドサーバ化）

新しいビルダーホストの `default.nix` に：

```nix
services.openssh.enable = true;   # ssh.nix で共通設定済みだが念のため
users.users.<user>.openssh.authorizedKeys.keys = [ "ssh-... ..." ];
```

`nix.settings.trusted-users = [ "@wheel" ]` は `nix-settings.nix` で全ホスト共通設定済みなので追加不要。

クライアント側から：

```sh
sudo nixos-rebuild switch --flake .#<client-host> --build-host <user>@<new-builder>.local
```

## 関連ファイル

- [modules/nixos/ssh.nix](../../modules/nixos/ssh.nix) — openssh + avahi publish
- [modules/nixos/nix-settings.nix](../../modules/nixos/nix-settings.nix) — trusted-users
- [hosts/nixos-desktop/default.nix](../../hosts/nixos-desktop/default.nix) — authorized_keys
- [hosts/nixos-spin713/default.nix](../../hosts/nixos-spin713/default.nix) — accept-new 設定
- [modules/nixos/users.nix](../../modules/nixos/users.nix) — sudo の `SSH_AUTH_SOCK` 引き継ぎ
