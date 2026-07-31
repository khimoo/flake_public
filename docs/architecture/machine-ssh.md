# マシン間 SSH（設計判断）

flake 内の全 NixOS ホストが相互に SSH でき、`ssh <短縮名>`（例 `ssh desktop`）で
接続できるようにする配線。リモートビルド（[remote-build.md](./remote-build.md)）は
この上に乗る一利用例。

設定ファイル:
- `hosts/machines.nix` — ホスト名一覧と LAN 共通鍵の公開鍵（単一の情報源）
- `modules/nixos/ssh.nix` — そこから authorized_keys とクライアント設定を生成
- `modules/home-manager/ssh-keys.nix` — 秘密鍵側を `secrets/secrets.yaml` から書き出す
  （[private-repo-clone.md](./private-repo-clone.md) 参照）

使い方は [../howtouse/machine-ssh.md](../howtouse/machine-ssh.md) を参照。

## 全体構成

`machines.nix` を単一の情報源とし、共通モジュール `ssh.nix` が2方向に展開する:

- **サーバ側**: `lanPublicKey` を primaryUser の `authorized_keys` に登録 → 相互ログイン可
- **クライアント側**: `hosts` の各要素ぶんの `Host` ブロック（短縮エイリアス＋`IdentityFile`
  ＋`accept-new`）を生成 → `ssh desktop` 等で接続可

秘密鍵の実体はここには無い。`ssh-keys.nix` が switch のたびに `secrets/secrets.yaml`
から `~/.ssh/id_lan` を書き出す。つまり**新マシンで手作業が要るのは age 鍵 1 本の設置だけ**で、
SSH 鍵の生成も登録も無い。

## 設計判断

### 鍵は用途で名付ける（id_lan / id_github）

`id_ed25519` のようなアルゴリズム名だと、1 ファイルに複数の役割が同居しても気づけない。
実際この repo では長らく `~/.ssh/id_ed25519` が「LAN の身元」と「GitHub 認証鍵」を兼ねており、
GitHub 側の鍵を rotate したときに LAN 接続を巻き込んで壊した。役割ごとにファイルを分ければ、
片方の失効がもう片方に波及しない。

- `~/.ssh/id_lan` — LAN 内 machine-to-machine。`machines.nix` の `lanPublicKey` と対
- `~/.ssh/id_github` — GitHub 認証（clone/push）。`private-repos.nix` の clone が使う

### LAN 認証は全マシン共通の鍵 1 本

以前は per-machine 鍵（各マシンが自分の鍵ペアを持ち、公開鍵を `machines.nix` に登録）を
採っていた。共通鍵に反転した。

理由は per-machine を選んだ根拠が消滅したこと。当時は同じ SSH 鍵が `ssh-to-age` 変換で
sops secret の復号も兼ねており、1本漏れれば全 secret が一度に危険だった。この変換は廃止され、
復号の種は独立した age 鍵（`~/.config/sops/age/keys.txt`）に移った。今の `id_lan` は
LAN ログイン以外に何も開けない。

得られるもの: 新マシンの立ち上げが age 鍵の設置だけで完結する。マシン追加時に
既存全機を rebuild して回る必要がなくなった（`authorized_keys` が変わらないため）。

失うもの: **個別失効ができない**。1台紛失したら `lan_ssh_key` を作り直して
`secrets.yaml` を再暗号化し、全機を switch する必要がある。3台規模ではこの手間より
「増設のたびに全機 rebuild」を消すほうが効く。台数や共有者が増えるなら per-machine か
SSH 証明書（CA）方式へ戻す。

### 鍵管理は per-host 直書きでなく machines.nix に集約

以前は各 `hosts/<host>/default.nix` に `authorizedKeys` を直書きしていたが、双方向化すると
N×N の直書きになり重複する。単一の情報源に集約し、`ssh.nix` が全ホストぶんを生成する。

### クライアント設定も同じ情報源から生成

`ssh <短縮名>` で繋がるには ①認証 ②名前解決 ③ホスト鍵受理 が要る。②は avahi の mDNS
（[remote-build.md](./remote-build.md) 参照）、①③と短縮エイリアスを `machines.nix` から
生成する。`nixos-` プレフィックスを剥がして `desktop` / `spin713` を短縮名にする。

### IdentitiesOnly は付けない

生成する `Host` ブロックは `IdentityFile` を指定するが `IdentitiesOnly yes` は付けない。
`/etc/ssh/ssh_config` は root にも効き、root の `~/.ssh/id_lan` は存在しない。
`sudo nixos-rebuild --build-host` は `env_keep` した `SSH_AUTH_SOCK` 越しに
ユーザーの agent で認証しており、`IdentitiesOnly yes` を付けると agent の鍵が無視されて
リモートビルドが壊れる。存在しない `IdentityFile` は単に読み飛ばされるので、
指定するだけなら root に無害。

### ホスト鍵は accept-new（TOFU）

生成する各 `Host` ブロックに `StrictHostKeyChecking accept-new` を付ける。初回接続の鍵は
自動受理、以降は変更を拒否（MITM 検出）。家庭 LAN の脅威モデルでは十分。厳密にやるなら
`programs.ssh.knownHosts` に host key を直書きする手もあるが、再インストールのたびに
更新が要るため不採用。

`/etc/ssh/ssh_config`（`programs.ssh.extraConfig`）は root にも効くため、
`sudo nixos-rebuild --build-host` の root known_hosts 追加もこの生成設定が兼ねる。

## セキュリティモデル

- repo にコミットされるのは `machines.nix` の公開鍵と、age で暗号化された
  `secrets/secrets.yaml` のみ。平文の秘密鍵は入らない
- 秘密鍵は各マシンに存在するが、**同一の鍵**である。1台が侵害されたら全機の LAN 認証を
  作り直す（上記トレードオフ）
- `PasswordAuthentication = false`（`ssh.nix` 共通）。鍵認証のみ
- 自分自身の公開鍵も `authorized_keys` に含むが、自機への self-login が増えるだけで無害
- 対象は NixOS ホストのみ（`ssh.nix` は NixOS モジュール）。standalone home-manager
  （macOS 等）は LAN の一員とみなさず `id_lan` を配らない
