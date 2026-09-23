# Tailscale（LAN の外からデスクトップを使う）

自宅 LAN の外から、tailnet 経由でデスクトップに SSH したり、ビルドをデスクトップに任せたりする。
設計判断は [../architecture/tailscale.md](../architecture/tailscale.md) を参照。

## 出先からデスクトップに入る

接続名の末尾に `-ts` を付ける:

```sh
ssh desktop-ts      # = pomu@nixos-desktop（MagicDNS）
ssh spin713-ts      # デスクトップからラップトップへ
```

認証は LAN 内と同じ `~/.ssh/id_lan` を使う（[machine-ssh.md](./machine-ssh.md)）。
LAN 内では従来どおり `ssh desktop`（mDNS）を使える。tailnet に入っていれば LAN 内でも `desktop-ts` で繋がる。

重い作業は、デスクトップに入ってからそこで Neovim や cargo を動かす。

出先からのリモートビルドは [remote-build.md の「LAN の外からビルドする」](./remote-build.md#lan-の外からビルドする) を参照。

## 出先からデスクトップの画面を使う（RDP）

ゲームの試遊のようにウィンドウを開く確認は、SSH では表示されない。RDP でデスクトップの画面ごと手元に出す。
描画はデスクトップの GPU で行われ、手元には映像だけが届く。

デスクトップ側で、GNOME の設定から一度だけ有効にしておく（LAN 内で行う）:

1. 設定 → システム → リモートデスクトップを開く
2. 使う方式を有効にする
   - デスクトップ共有: ログイン中のセッションをそのまま共有する。クリックやキー入力もするなら、リモート操作も有効にする
   - リモートログイン: ログイン画面から新しいセッションを始める。誰もログインしていないときに使う
3. RDP 用のユーザー名とパスワードを決める。これは Linux のログインパスワードとは別物で、repo には書かない

ラップトップ側では「接続」（`gnome-connections`）を開き、接続先に `nixos-desktop` を入れて RDP で繋ぐ。
設定画面に別のポートが表示されている場合は `nixos-desktop:3390` のように付ける。

ポートは tailnet 側（`tailscale0`）だけに開けてある。LAN 内から `nixos-desktop.local` で RDP しても繋がらない。

画面をロックした状態と、再起動して誰もログインしていない状態で繋がるかは、まだ確かめていない。出かける前に、次の「出かける前に確かめる」の 4 で試しておく。

## 出かける前に確かめる

1. デスクトップの電源が入っていて、tailnet に参加している:
   ```sh
   ssh desktop 'tailscale status'
   ```
   一覧に `nixos-desktop` と `nixos-spin713` が出る。
2. デスクトップの鍵の期限が無効になっている（admin console の Machines ページで確かめる。手順は次節の 4）
3. ラップトップを LAN 以外の回線（スマホのテザリングなど）につなぎ、tailnet 経由で入れる:
   ```sh
   ssh desktop-ts 'echo ok'
   tailscale ping nixos-desktop
   ```
   `tailscale ping` の応答に `via DERP` と出るなら中継を経由している。繋がるが遅い。
4. RDP を使うなら、デスクトップの画面をロックしてから、同じ回線のラップトップで「接続」から `nixos-desktop` に RDP で入れる

外出中にデスクトップの世代を切り替えると、ネットワークや sshd、tailscaled を壊す変更だった場合に、帰宅するまで直せない。
外出中はデスクトップで `switch` しない。

## ホストを tailnet に参加させる

新しいホストを足したときや、OS を入れ直したときに行う。1 ホストにつき一度でよく、認証の状態は `/var/lib/tailscale` に残るので再起動しても続く。

1. そのホストを switch する（`tailscale.nix` は `common.nix` が読むので、ホスト側の設定は要らない）
2. そのホストで実行する（LAN 内なら `ssh desktop` 越しでもよい）:
   ```sh
   sudo tailscale up
   ```
   表示された URL を、どの端末のブラウザでもよいので開き、Tailscale アカウントでログインする。
3. 参加を確かめる:
   ```sh
   tailscale status
   getent hosts nixos-desktop    # 100. で始まるアドレスが返る
   ```
4. 常時稼働させるホスト（デスクトップ）は、admin console の Machines ページで行末のメニューから Disable Key Expiry を選ぶ。期限は既定で 180 日で、切れると再認証するまで tailnet から外れる

外出先からデスクトップに入る経路は tailnet しかないので、デスクトップの `tailscale up` は出かける前に LAN 内で済ませる。

## ラップトップで tailnet から一時的に抜ける

```sh
sudo tailscale down   # 抜ける
sudo tailscale up     # 戻る。認証済みならブラウザは開かない
```

抜けている間は `-ts` の接続名が使えない。LAN 内の `ssh desktop` は影響を受けない。

## トラブルシューティング

### `Could not resolve hostname nixos-desktop`

手元のホストが tailnet に入っていないか、MagicDNS の設定が resolv.conf に入っていない。

```sh
tailscale status             # Logged out / Stopped なら sudo tailscale up
cat /etc/resolv.conf         # nameserver 100.100.100.100 と search <tailnet 名>.ts.net があるか
```

`tailscale status` が正常なのに resolv.conf に入っていないなら、`journalctl -u tailscaled` で `dns:` から始まる行を見る。
admin console の DNS ページで MagicDNS が無効になっている場合も、短縮名は引けない。

### `tailscale status` に `nixos-desktop-1` のような名前で出る

同じ名前の古い端末が tailnet に残っていて、新しい端末に連番が付いた。
admin console の Machines ページで古い端末を削除し、新しい端末の名前を `nixos-desktop` に直す。接続名 `desktop-ts` はホスト名 `nixos-desktop` を引くので、名前がずれると繋がらない。

### RDP で繋がらない

先に `ssh desktop-ts` が通るか確かめる。通らないなら次項を見る。
SSH が通るなら、デスクトップで RDP のサーバがどのポートで待ち受けているかを見る:

```sh
ssh desktop-ts 'ss -ltn | grep -E ":33(89|9[0-9])"'
```

何も出なければ、GNOME の設定でリモートデスクトップが無効になっている。
3389〜3399 の外で待ち受けているなら、ファイアウォールで開けた範囲に入っていない。`gsettings get org.gnome.desktop.remote-desktop.rdp port` で設定値を確かめ、範囲内に戻すか、`hosts/nixos-desktop/default.nix` の範囲を広げる。

### `ssh desktop-ts` がタイムアウトする

`tailscale status` でデスクトップの行を見る。`offline` なら、デスクトップが止まっているか、サスペンドしているか、ネットワークから外れている。
tailnet からは起こせないので、帰宅するか自宅の人に電源を入れてもらうしかない。
デスクトップは無操作でサスペンドしない設定にしてある（[../architecture/tailscale.md](../architecture/tailscale.md)）。手動でサスペンドした場合と、停電で落ちた場合は戻らない。

## 関連ファイル

- [modules/nixos/tailscale.nix](../../modules/nixos/tailscale.nix) — tailscaled の有効化
- [modules/nixos/ssh.nix](../../modules/nixos/ssh.nix) — `-ts` の接続名の生成
- [hosts/nixos-desktop/default.nix](../../hosts/nixos-desktop/default.nix) — デスクトップの自動サスペンドの無効化と、tailnet 側だけの RDP のポート
- マシン間 SSH: [machine-ssh.md](./machine-ssh.md)
- リモートビルド: [remote-build.md](./remote-build.md)
