# リモートビルドガイド

ラップトップ（`nixos-spin713`）で `nixos-rebuild` を実行する際に、ビルドだけをデスクトップ（`nixos-desktop`）にオフロードする運用方法。成果物のみがラップトップに転送され、アクティベートは手元で行われる。

> 設計判断・実装の詳細は [docs/architecture/remote-build.md](../architecture/remote-build.md) を参照

## 前提条件

| 項目 | 要件 |
|------|------|
| ネットワーク | ラップトップとデスクトップが同一 LAN（mDNS が届く範囲）※出先で使えるようにする計画: [remote-build-tailscale.md](../architecture/remote-build-tailscale.md) |
| アーキテクチャ | 両ホストとも `x86_64-linux`（クロスビルドはしない） |
| SSH 鍵 | ラップトップの `pomu` に `~/.ssh/id_lan` がある（`local.profile.lanSsh = true` で switch すると書き出される） |

設定ファイル側は既に構成済み：

- 鍵登録と `.local` への `accept-new` 接続は `hosts/machines.nix` を元に `ssh.nix` が
  全ホストぶん生成する（マシン間 SSH の共通基盤。[machine-ssh.md](./machine-ssh.md) を参照）
- 両ホスト：`nix.settings.trusted-users = [ "@wheel" ]`（デスクトップはビルドの受け入れ、ラップトップは成果物の取り込みに使う）
- 両ホスト：`services.avahi.publish` で `<hostname>.local` を LAN に広告

## 基本コマンド

ラップトップ側で、`sudo` を付けずに実行する：

```sh
nixos-rebuild switch \
  --flake .#nixos-spin713 \
  --build-host pomu@nixos-desktop.local \
  --sudo
```

- `--build-host` 指定先（デスクトップ）でビルドが実行される
- 完了後、結果のストアパスがラップトップに転送される
- アクティベート（switch）はラップトップ上で行われる。`sudo` で動くのはこの処理だけ

評価、ビルド、転送は `pomu` として動くので、SSH は `pomu` の `~/.ssh/id_lan` で認証する。
コマンド全体を `sudo nixos-rebuild ...` で実行すると SSH が root として動き、`/root/.ssh/id_lan` を探して `Permission denied (publickey)` で失敗する。

アクティベートの直前に `sudo` のパスワードを聞かれる（同じ端末で直前に `sudo` を通していれば省略される）。
`users.nix` で NOPASSWD にしているのは `nixos-rebuild` 本体だけで、`--sudo` が `sudo` 付きで呼ぶ `nix-env` と `switch-to-configuration` は対象外だから。

## 動作確認

セットアップ直後に確認すべき項目：

```sh
# 1. mDNS 名前解決
ping -c 1 nixos-desktop.local

# 2. SSH 疎通（sudo を付けない）
ssh pomu@nixos-desktop.local 'echo ok'

# 3. デスクトップの Nix が pomu を trusted として扱うか（Trusted: 1）
ssh pomu@nixos-desktop.local 'nix store info --store daemon'

# 4. ラップトップの Nix が pomu を trusted として扱うか（Trusted: 1）
nix store info --store daemon
```

4 まで通れば `--build-host` も通る。

## トラブルシューティング

### `ping: nixos-desktop.local: System error`（初回のみ）

avahi のキャッシュが温まっていないだけ。数秒待ってから再実行すると応答する。常時再発する場合は次項を疑う。

### 名前解決が変なアドレス（`192.168.122.*`）に向く

デスクトップで `libvirt` の `virbr0` を経由した IP が mDNS で広告されると、LAN 外からは到達できない。デスクトップ上で `getent hosts nixos-desktop.local` を実行して `192.168.11.*`（LAN 側）以外が返るなら、`services.avahi.denyInterfaces = [ "virbr0" "vnet*" ];` を `modules/nixos/ssh.nix` に追加して LAN 以外の IF を除外する。

### `error: cannot add path '/nix/store/...' because it lacks a signature`

デスクトップかラップトップの `nix.settings.trusted-users` に `pomu` が入っていない。デスクトップはビルドを受け入れるとき、ラップトップは成果物を取り込むときに署名を要求する。動作確認の 3 と 4 で `Trusted: 1` になるか確認する（`@wheel` グループに `pomu` が入っていれば通る）。

### `Host key verification failed`

`~/.ssh/known_hosts` に `nixos-desktop.local` のエントリが無く、かつ `accept-new` が適用されていない。`ssh.nix` が `machines.nix` から生成する `/etc/ssh/ssh_config` に `Host ... nixos-desktop.local` の `StrictHostKeyChecking accept-new` が含まれるはず。デスクトップが `machines.nix` に登録済みか確認。手動回避は `ssh-keyscan -H nixos-desktop.local >> ~/.ssh/known_hosts`。

### `Permission denied (publickey)`

コマンド全体を `sudo` で実行すると、SSH が root として動いて `id_lan` を読めない。`sudo` を外し、基本コマンドのとおり `--sudo` を付けて実行する。

`sudo` を付けていないのに失敗するなら、ラップトップに `~/.ssh/id_lan` があるか確認する。無ければ `local.profile.lanSsh = true` で switch する（[machine-ssh.md](./machine-ssh.md) を参照）。

## 新しいビルダー／クライアントを追加するとき

### クライアントを増やす（新しいホストからデスクトップでビルド）

LAN 認証は全マシン共通の鍵 1 本なので、鍵の生成も登録も要らない
（[machine-ssh.md](./machine-ssh.md) の「マシンを追加するとき」を参照）。

1. 新規ホストの `~/.config/sops/age/keys.txt` に age 鍵を置く
2. `hosts/machines.nix` の `hosts` に1行足す
3. 新規ホストを rebuild（switch 中に `~/.ssh/id_lan` が書き出される）

### ビルダーを増やす（別のホストもビルドサーバ化）

新しいビルダーホストの `default.nix` に：

```nix
services.openssh.enable = true;   # ssh.nix で共通設定済みだが念のため
users.users.<user>.openssh.authorizedKeys.keys = [ "ssh-... ..." ];
```

`nix.settings.trusted-users = [ "@wheel" ]` は `nix-settings.nix` で全ホスト共通設定済みなので追加不要。

クライアント側から：

```sh
nixos-rebuild switch --flake .#<client-host> --build-host <user>@<new-builder>.local --sudo
```

## 関連ファイル

- [modules/nixos/ssh.nix](../../modules/nixos/ssh.nix) — openssh + avahi publish + マシン間 SSH 生成
- [hosts/machines.nix](../../hosts/machines.nix) — ホスト一覧と LAN 共通鍵の公開鍵（authorized_keys / accept-new の元）
- [modules/nixos/nix-settings.nix](../../modules/nixos/nix-settings.nix) — trusted-users
- [modules/nixos/users.nix](../../modules/nixos/users.nix) — `nixos-rebuild` 本体だけを NOPASSWD にする sudo 規則
- マシン間 SSH の使い方・設計: [machine-ssh.md](./machine-ssh.md) / [../architecture/machine-ssh.md](../architecture/machine-ssh.md)
