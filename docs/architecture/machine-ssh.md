# マシン間 SSH（設計判断）

flake 内の全 NixOS ホストが相互に SSH でき、`ssh <短縮名>`（例 `ssh desktop`）で
接続できるようにする配線。リモートビルド（[remote-build.md](./remote-build.md)）は
この上に乗る一利用例。

設定ファイル:
- `hosts/machines.nix` — 各マシンの user 公開鍵レジストリ（単一の情報源）
- `modules/nixos/ssh.nix` — レジストリから authorized_keys とクライアント設定を生成
- `.sops.yaml` — 同じ鍵ペアの age 版（sops 受信者）。別管理の理由は下記

使い方は [../howtouse/machine-ssh.md](../howtouse/machine-ssh.md) を参照。

## 全体構成

`machines.nix`（hostname → ssh 公開鍵）を単一の情報源とし、共通モジュール `ssh.nix`
が2方向に展開する:

- **サーバ側**: 全マシンの公開鍵を primaryUser の `authorized_keys` に登録 → 相互ログイン可
- **クライアント側**: 各マシンぶんの `Host` ブロック（短縮エイリアス＋`accept-new`）を生成
  → `ssh desktop` 等で接続可

マシンの追加/廃棄は `machines.nix` の1行増減だけで、全ホストの `authorized_keys` と
エイリアスに反映される。

## 設計判断

### 鍵は各マシンで別（per-machine）。1本を使い回さない

各マシンが自分の ed25519 鍵ペアを持ち、公開鍵だけを `machines.nix` に登録する。
秘密鍵は生成マシンから出ない。

- **個別失効**: 1台を廃棄/紛失したら `machines.nix` からその行を消して rebuild するだけで、
  その台だけ締め出せる。他機の鍵は無傷
- **被害の局所化**: この flake は公開リポジトリで、同じ鍵が `ssh-to-age` 変換で sops
  secret の復号も兼ねる。鍵を共有するとコピーが増え、1本漏れると全機の SSH＋全 secret が
  一度に危険になる。per-machine なら被害をその台に閉じ込められる

共有鍵は増設が最も楽（新機に鍵を置くだけ）だが、上記の失効性・被害局所化を失うため不採用。
SSH 証明書（CA）方式は「既存機を触らず増設」を実現できるが、CA 鍵という新たな最重要秘密と
署名運用が増え、3台規模では過剰。台数が増えたら CA 移行を検討する余地はある。

### 鍵管理は per-host 直書きでなく machines.nix に集約

以前は各 `hosts/<host>/default.nix` に `authorizedKeys` を直書きしていたが、双方向化すると
N×N の直書きになり重複する。単一の情報源に集約し、`ssh.nix` が全ホストぶんを生成する。
増設時に触る場所が `machines.nix` の1箇所になる。

> デスクトップの `hosts/nixos-desktop/default.nix` には旧リモートビルド用の RSA 鍵が
> 1つ残っている。ラップトップが ed25519 でリモートビルドできることを確認したら削除して
> よい暫定物（`machines.nix` の ed25519 で置き換わる）。

### クライアント設定も同じ情報源から生成

`ssh <短縮名>` で繋がるには ①認証 ②名前解決 ③ホスト鍵受理 が要る。②は avahi の mDNS
（[remote-build.md](./remote-build.md) 参照）、①③と短縮エイリアスを `machines.nix` から
生成する。`nixos-` プレフィックスを剥がして `desktop` / `spin713` を短縮名にする。

### ホスト鍵は accept-new（TOFU）

生成する各 `Host` ブロックに `StrictHostKeyChecking accept-new` を付ける。初回接続の鍵は
自動受理、以降は変更を拒否（MITM 検出）。家庭 LAN の脅威モデルでは十分。厳密にやるなら
`programs.ssh.knownHosts` に host key を直書きする手もあるが、再インストールのたびに
更新が要るため不採用。

`/etc/ssh/ssh_config`（`programs.ssh.extraConfig`）は root にも効くため、
`sudo nixos-rebuild --build-host` の root known_hosts 追加もこの生成設定が兼ねる。

### age 鍵（sops）は別ファイルで対に管理

同じ ed25519 鍵ペアが SSH 認証と（`ssh-to-age` 変換で）sops 復号を兼ねるが、sops は
age 形式・専用フォーマットの `.sops.yaml` を要求するため `machines.nix` に統合できない。
secret が要るマシンは `machines.nix`（SSH 形式）と `.sops.yaml`（age 形式）の両方に登録する。

## セキュリティモデル

- 秘密鍵は各マシンから出ない。`machines.nix` / `.sops.yaml` に載るのは公開鍵のみ
  （公開リポジトリにコミット可）
- `PasswordAuthentication = false`（`ssh.nix` 共通）。鍵認証のみ
- 自分自身の公開鍵も `authorized_keys` に含むが、自機への self-login が増えるだけで無害
- 対象は NixOS ホストのみ（`ssh.nix` は NixOS モジュール）。standalone home-manager
  （macOS 等）は現状この生成対象外
