# リモートビルドの設計

ラップトップが `nixos-rebuild` する際に、デスクトップを SSH 経由のビルダーとして使う構成。

設定ファイル:

- `modules/nixos/ssh.nix` — openssh + avahi publish + マシン間 SSH の生成
- `modules/nixos/nix-settings.nix` — `nix.settings.trusted-users`
- `hosts/machines.nix` — ホスト一覧と LAN 共通鍵の公開鍵（`authorizedKeys` と host key 受理設定の元）

> SSH の鍵管理・ホスト鍵受理・`.local` 接続の配線はリモートビルド専用ではなく、
> flake 内マシン間 SSH の共通基盤である [machine-ssh.md](./machine-ssh.md) に集約した。
> このドキュメントはその上に乗る「ビルドのオフロード」固有の判断だけを扱う。
>
> 使い方は [docs/howtouse/remote-build.md](../howtouse/remote-build.md) を参照

## 方式選択：`--build-host` vs `nix.buildMachines`

NixOS でビルドを別ホストにオフロードする方法は大別して 2 つ：

| 方式 | 特徴 | 採用 |
|------|------|------|
| `nixos-rebuild --build-host` | コマンド実行時のみ SSH で接続する ad-hoc 方式 | **採用** |
| `nix.distributedBuilds` + `nix.buildMachines` | nix-daemon が透過的にビルダーへオフロードする常設方式 | 不採用 |

### `--build-host` を選んだ理由

- **root の SSH 鍵管理が不要**：`buildMachines` は nix-daemon（root 権限）が SSH 接続するため、`/root/.ssh/` に鍵を配置し、`known_hosts` も管理する必要がある。`--build-host` の SSH は `nixos-rebuild` を実行したユーザとして接続するので、ユーザの `~/.ssh/id_lan` と `known_hosts` がそのまま使われ、鍵管理がユーザ側で完結する（`sudo` を付けずに実行する前提。後述）。
- **明示性**：オフロードしたいときだけ明示的にフラグを付ける運用なので、デスクトップが落ちているときの挙動がはっきりする（コマンドが失敗するだけ）。`buildMachines` は透過的なフォールバック挙動を理解する必要がある。
- **個人利用の頻度**：ラップトップで rebuild するのは出張中や別室作業時など断続的。常設ビルダーを宣言するメリットが薄い。

将来、ラップトップを日常開発機として使う頻度が上がったら `buildMachines` への移行を検討する余地はある。

## ホスト解決：mDNS（`.local`）

`pomu@nixos-desktop.local` のように `.local` ドメインで接続する。

- **固定 IP に依存しない**：自宅 LAN・宿泊先 LAN・テザリングなどで IP が変わっても、同セグメント内であれば mDNS が解決する
- **DNS サーバ不要**：ルータの DHCP/DNS 設定に手を入れない
- **トレードオフ**：mDNS が届かない環境（VLAN 分離、VPN 越し等）では別途 `/etc/hosts` か Tailscale が必要（Tailscale 化の設計メモ: [remote-build-tailscale.md](./remote-build-tailscale.md)）

実装は `modules/nixos/ssh.nix` の `services.avahi.publish` で：

```nix
services.avahi.publish = {
  enable = true;
  addresses = true;
  domain = true;
  workstation = true;
};
```

`services.avahi.enable` と `nssmdns4 = true`（解決側）は `printing.nix` で先に有効化されており、モジュール合成によって `publish` 設定が後から追加される形になっている。SSH 関連の設定は印刷とは独立した責務なので `ssh.nix` に分けたが、avahi の有効化自体は重複できないため、`publish` だけを書く形にした。

### 既知の落とし穴：libvirt 等の仮想ブリッジ

`libvirt` が `virbr0`（`192.168.122.0/24`）を作っていると、avahi がそのインタフェースでもホスト名を広告し、LAN 外からは到達できない IP を返すことがある。観測した事象としては、デスクトップ自身で `getent hosts nixos-desktop.local` を引くと `192.168.122.1` が返るケースがあった。

対症療法：`services.avahi.denyInterfaces = [ "virbr*" "vnet*" ];` を追加する。現状は LAN 経由の解決では問題が出ていないため未設定だが、再発したら導入する。

## `trusted-users = [ "@wheel" ]`

`modules/nixos/nix-settings.nix`：

```nix
nix.settings.trusted-users = [ "@wheel" ];
```

### 必要性

リモートビルドの受け側は、接続してきたユーザが trusted でないと以下を拒否する：

- 署名なしの派生物の構築
- ストアパスのプッシュ／プル

`--build-host` でビルドする際、ラップトップが生成した derivation をデスクトップに送って構築させるため、デスクトップ側で trusted でないと「`cannot add path '/nix/store/...' because it lacks a signature`」エラーになる。

呼び出し側のラップトップにも同じ設定が要る。`--sudo` で実行すると、デスクトップから戻る成果物を `pomu` のまま手元のストアに取り込むので、ラップトップ側で trusted でなければ同じ署名エラーになる。`nix-settings.nix` は全ホストが読み込むので、両側とも `@wheel` が trusted になる。

### `@wheel` を使う理由

- ホスト固有のユーザ名（`pomu`）をハードコードしたくない
- admin 権限（wheel）と「nix-daemon を信頼できる」のスコープがこの flake では一致している
- 新規 admin ユーザを追加するときに `trusted-users` を別途編集する必要がない

非 admin ユーザにビルダー権限を渡したくなったら明示的に `[ "@wheel" "someuser" ]` のように個別追加する。

### セキュリティ上の判断

`trusted-users` は実質的に root 相当の権限（任意のストアパスを書き込めるため、`/nix/store` 経由でシステムを汚染可能）。`@wheel` は既に sudo 権限を持っており、信頼レベルは等価なので拡大はしていない。

## SSH 鍵管理・ホスト鍵受理は machine-ssh に集約

以前はデスクトップの `authorizedKeys.keys` とラップトップの `programs.ssh.extraConfig`
（`accept-new`）を各 `hosts/<host>/default.nix` に直書きしていたが、マシン間 SSH を
双方向化した際に `hosts/machines.nix` を単一の情報源とする方式へ移した。

- 誰の鍵を受け入れるか（`authorizedKeys`）と、`.local` への `accept-new` 接続設定は、
  `ssh.nix` が `machines.nix` から全ホストぶん生成する
- リモートビルドの SSH が `nixos-desktop.local` の host key を実行ユーザの `known_hosts` に
  accept-new で入れる動作も、この生成される `/etc/ssh/ssh_config` が兼ねる

設計判断（LAN 共通鍵、集約、accept-new の TOFU トレードオフ、CA 不採用など）は
[machine-ssh.md](./machine-ssh.md) を参照。

## `sudo` を付けず `--sudo` で実行する

`nixos-rebuild` 全体を `sudo` で実行せず、一般ユーザのまま `--sudo` を付ける。

```sh
nixos-rebuild switch --flake .#nixos-spin713 --build-host pomu@nixos-desktop.local --sudo
```

nixos-rebuild-ng 25.11 のソース（`nixos_rebuild/process.py` の `run_wrapper` と `nixos_rebuild/nix.py`）を読むと、`--sudo` がローカルで `sudo` を付けるのはアクティベートのコマンド（`nix-env -p <profile> --set` と `switch-to-configuration` の呼び出し）だけである。flake の評価、ビルドホストへの SSH、`nix-copy-closure` による転送は、呼び出したユーザのまま動く。

### 不採用：`sudo` と `SSH_AUTH_SOCK` の引き継ぎ

`sudo nixos-rebuild --build-host ...` では SSH が root として動く。`/etc/ssh/ssh_config` の `IdentityFile ~/.ssh/id_lan` は root の home で解決され、root は `id_lan` を持たない。`users.nix` の `Defaults env_keep += "SSH_AUTH_SOCK"` でユーザの agent を渡しても、agent に `id_lan` が入っていなければ認証できない。`id_lan` は home-manager がファイルとして書き出すだけで、agent には登録しない。この方式を使うには、ログインのたびに `ssh-add ~/.ssh/id_lan` が要る。

観測（2026-09-16、nixos-spin713）：agent には `id_lan` 以外の RSA 鍵が 1 本だけ入っており、`sudo SSH_AUTH_SOCK=$SSH_AUTH_SOCK nixos-rebuild switch --flake .#nixos-spin713 --build-host pomu@nixos-desktop.local` は `pomu@nixos-desktop.local: Permission denied (publickey).` で失敗した。同じ接続を `pomu` から `ssh -v` すると `Server accepts key: /home/pomu/.ssh/id_lan` で認証が通った。

`env_keep` の設定は `nixos-rebuild` を sudo で実行するワークフロー全般のために入れたもので、リモートビルドの前提ではない。

### トレードオフと再検討の条件

`users.nix` で NOPASSWD にしているのは `nixos-rebuild` 本体だけなので、`--sudo` が `sudo` 付きで呼ぶアクティベートのコマンドではパスワードを聞かれる。プロンプトはビルドと転送が終わった後に出る。

このパスワード入力が負担になったら見直す。候補は二つある。一つは `id_lan` を agent に載せて `sudo` と `SSH_AUTH_SOCK` の方式に戻す案で、root から gcr の agent ソケットを使えるかは確認していない。もう一つはアクティベートのコマンドを NOPASSWD にする案で、パスワードなしで root として動かせるコマンドが増える。

## モジュール責務の分離

| モジュール | 責務 |
|-----------|------|
| `modules/nixos/ssh.nix` | openssh の有効化、mDNS publish、`machines.nix` から authorized_keys とクライアント設定を生成 |
| `modules/nixos/nix-settings.nix` | trusted-users（nix-daemon の信頼境界） |
| `modules/nixos/users.nix` | `nixos-rebuild` 本体の NOPASSWD（`--sudo` のアクティベートは対象外） |
| `hosts/machines.nix` | ホスト一覧と LAN 共通鍵の公開鍵（マシン間 SSH の単一の情報源） |

「共通インフラ」と「マシン登録簿」を分離し、新ホストを追加するときに触る場所を
`hosts/machines.nix` の1エントリに局所化している（詳細は [machine-ssh.md](./machine-ssh.md)）。
