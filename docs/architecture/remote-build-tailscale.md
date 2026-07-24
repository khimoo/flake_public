# TODO: 外出先から Tailscale 経由で `--build-host` を効かせる

**現状: 未実装（設計メモ）**。実装したらこのファイルを更新し、使い方は
`docs/howtouse/remote-build.md` に追記して二重管理にしない。

## 何を解決するか

現在 `sudo nixos-rebuild switch --flake .#nixos-spin713 --build-host pomu@nixos-desktop.local`
は **自宅 LAN 内でしか通らない**。`nixos-desktop.local` は mDNS 名で、別ネットワーク（大学・
オフィス・カフェ等）にいると `Could not resolve hostname` で SSH 接続に到達しない。

出先ではラップトップ単体で重いビルドを走らせるしかなく、体感的に辛い。既存の
`docs/architecture/remote-build.md` の「ホスト解決」節にも「mDNS が届かない環境では別途
`/etc/hosts` か Tailscale が必要」とトレードオフとして書かれている。ここではその
「Tailscale 化」を具体化する。

## 方針

Tailscale で自宅の nixos-desktop を tailnet に常時 join させ、MagicDNS で `nixos-desktop`
（短縮名）を tailnet 側 IP に解決させる。`--build-host` のホスト名を tailnet 名に置き換える
だけで既存フローがそのまま外出先でも動く。既存の mDNS 経路は自宅 LAN 内で温存する（Tailscale
のルーティングが LAN 内では LAN 側 IP を優先するのが既定挙動）。

## やること

### 1. 両ホストで tailscale を有効化

新規モジュール `modules/nixos/tailscale.nix` を作り、両 host からインポートする（`ssh.nix`
と同じ構成）:

```nix
{ ... }: {
  services.tailscale.enable = true;
  # tailnet からの SSH 経路（build-host は openssh を使うので不要だが、緊急ログイン用に有効化）
  services.tailscale.useRoutingFeatures = "client";
}
```

nixpkgs 側で openssh の firewall は既に開いているので追加設定は不要。tailscale 側 UDP は
モジュールが `networking.firewall.checkReversePath = "loose"` 等を面倒見る。

### 2. tailnet に join

初回だけ手動で:

```sh
sudo tailscale up --ssh
```

ブラウザで Tailscale アカウントに認証。`--ssh` は Tailscale SSH を有効化する（緊急ログイン
用途で便利。`--build-host` の SSH は従来通り openssh 側を使うので鍵設定は既存のまま）。

出先で `tailscale up` するかどうかはラップトップの好みで決める（バッテリー影響あり）。
出張中だけ up して普段は down、という運用も可。

### 3. MagicDNS を確認

Tailscale admin console で MagicDNS が有効になっていることを確認（デフォルト有効）。
tailnet 内で:

```sh
tailscale status
ping nixos-desktop         # 短縮名で引ける
```

### 4. ssh.nix のエイリアスに tailnet ホスト名を追加（任意）

現状の `modules/nixos/ssh.nix` は `<hostname>.local` を `HostName` にしているが、
tailnet を優先したい場合は tailnet 名を書く選択肢もある。両立させるなら
`~/.ssh/config` にユーザ側で別名を張るのが楽:

```
Host nixos-desktop-ts
  HostName nixos-desktop        # MagicDNS 短縮名
  User pomu
```

その上で:

```sh
sudo nixos-rebuild switch --flake .#nixos-spin713 --build-host pomu@nixos-desktop-ts
```

ssh.nix の生成を触ると mDNS 依存を捨てることになるので、まずは併用（既存 `.local` は
そのまま、tailnet 経由は `~/.ssh/config` の別名で切り替え）で運用する。

### 5. デスクトップの常時起動 / WoL

外出中にビルドさせたいときデスクトップが sleep していると意味がない。選択肢:

- **常時起動**（電力コスト増）
- **Wake-on-LAN**: tailnet 内の別ホスト（自宅 LAN の常時起動機、ルータ等）から `wol` で
  起こす。Tailscale 単体では WoL は張れないので、自宅側に踏み台が必要
- **手動**: 出張前に「デスクトップ電源入れっぱなしにしておく」運用

一番現実的なのは 3 番目。実装コスト 0 で「外出前に付けておく」だけ。

## 検討ポイント

- **セキュリティ**: tailnet に足す = tailnet ACL 上の全ノードから SSH 到達可能になる。
  ACL でホスト単位・タグ単位に絞る。個人利用（自分の 2〜3 台のみ）なら緩めでも実害は薄いが、
  仕事用マシンを混ぜるならタグ設計を先にやる
- **既存 LAN 経路との共存**: 自宅 LAN 内では MagicDNS が LAN 側 IP を返すので、tailscale 経由の
  余計なホップは発生しない（Tailscale の direct connection 判定に任せる）。動作は
  `tailscale status` で `direct` になっているか確認
- **eval への影響なし**: `--build-host` は build だけを SSH で投げる。eval は必ずローカル。
  今回の変更で eval 経路は一切変わらない
- **age 鍵・SSH 鍵の設置は不変**: private-repos.nix の clone は home.activation 内で走る
  ので、tailnet の有無と独立

## 参考

- Tailscale on NixOS: https://nixos.wiki/wiki/Tailscale
- 既存の remote-build 設計: [remote-build.md](./remote-build.md)
- machines.nix と ssh.nix の集約設計: [machine-ssh.md](./machine-ssh.md)
