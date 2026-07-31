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

- **root の SSH 鍵管理が不要**：`buildMachines` は nix-daemon（root 権限）が SSH 接続するため、`/root/.ssh/` に鍵を配置し、`known_hosts` も管理する必要がある。`--build-host` は呼び出し時の `SSH_AUTH_SOCK` 経由でユーザの鍵を使えるため、鍵管理がユーザ側で完結する。
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
- リモートビルドが必要とする「root の `known_hosts` に `nixos-desktop.local` を
  accept-new で入れる」動作も、この生成される `/etc/ssh/ssh_config`（root にも効く）が兼ねる

設計判断（LAN 共通鍵、集約、accept-new の TOFU トレードオフ、CA 不採用など）は
[machine-ssh.md](./machine-ssh.md) を参照。

> デスクトップ `hosts/nixos-desktop/default.nix` に残る RSA 鍵は、ed25519 集約前からの
> ラップトップ用リモートビルド鍵。ed25519 でのリモートビルドを確認後に削除してよい暫定物。

## `sudo` 経由でも SSH 鍵が使われる仕組み

`modules/nixos/users.nix`：

```nix
security.sudo.extraConfig = ''
  Defaults env_keep += "SSH_AUTH_SOCK"
'';
```

`sudo nixos-rebuild ...` で root として実行されるが、ssh が `SSH_AUTH_SOCK` を経由してユーザの SSH エージェントを参照するため、ユーザの秘密鍵（パスフレーズ入力済み）でリモートに認証できる。これが無いと root のホームに別途鍵を置く必要があり、`--build-host` の利点が失われる。

この設定は元々 `nixos-rebuild` を sudo で実行するワークフロー全般のために入れたものだが、リモートビルドにも必須の前提条件になっている。

## モジュール責務の分離

| モジュール | 責務 |
|-----------|------|
| `modules/nixos/ssh.nix` | openssh の有効化、mDNS publish、`machines.nix` から authorized_keys とクライアント設定を生成 |
| `modules/nixos/nix-settings.nix` | trusted-users（nix-daemon の信頼境界） |
| `modules/nixos/users.nix` | sudo の `SSH_AUTH_SOCK` 引き継ぎ |
| `hosts/machines.nix` | ホスト一覧と LAN 共通鍵の公開鍵（マシン間 SSH の単一の情報源） |

「共通インフラ」と「マシン登録簿」を分離し、新ホストを追加するときに触る場所を
`hosts/machines.nix` の1エントリに局所化している（詳細は [machine-ssh.md](./machine-ssh.md)）。
