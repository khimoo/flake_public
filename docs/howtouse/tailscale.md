# Tailscale（LAN 外からのデスクトップ利用）

自宅 LAN の外から tailnet 経由でデスクトップに SSH 接続したり、ビルド処理をデスクトップに委任したりするための設定です。
`tailscaled` は、`common.nix` が [tailscale.nix](../../modules/nixos/tailscale.nix) を読み込むホストで有効になります。

設計ドキュメント: [Tailscale の設計](../architecture/tailscale.md)

## 外出先からデスクトップに接続する

接続用ホスト名の末尾に `-ts` を付けて接続します：

```sh
ssh desktop-ts      # = pomu@nixos-desktop（MagicDNS）
ssh spin713-ts      # デスクトップからラップトップへ接続
```

認証には LAN 内と同様に `~/.ssh/id_lan` を使用します（[machine-ssh.md](./machine-ssh.md) を参照）。
LAN 内であれば `ssh desktop`（mDNS）も使用可能です。tailnet に参加していれば、LAN 内からでも `desktop-ts` で接続できます。

負荷の大きい作業を行う際は、デスクトップに SSH 接続した上で Neovim や cargo などを実行してください。

ラップトップでのビルドは、外出先からでも tailnet 経由で自動的にデスクトップへ分散されます（[remote-build.md](./remote-build.md)）。`--build-host` で個別に指定する場合は、[remote-build.md の「LAN の外からビルドする」](./remote-build.md#lan-の外からビルドする) を参照してください。

## 外出先からデスクトップの画面を使う（RDP）

ゲームの動作確認など、ウィンドウ描画を伴う作業は SSH では表示できません。RDP を使用してデスクトップの画面をそのまま手元に転送します。
描画処理自体はデスクトップの GPU で行われ、手元には映像のみが送信されます。

あらかじめ LAN 内でデスクトップ側の GNOME 設定から有効化しておきます（一度だけ設定すれば完了です）：

1. 「設定」→「システム」→「リモートデスクトップ」を開く
2. 利用する方式を有効にする：
   - デスクトップ共有: ログイン中のセッションをそのまま共有。リモート操作（クリックやキー入力）も行う場合はそちらも有効化する
   - リモートログイン: ログイン画面から新しいセッションを開始。誰もログインしていない場合に使用する
3. RDP 用のユーザー名とパスワードを設定する（Linux のログインパスワードとは別のものを設定。リポジトリには保存しない）

ラップトップ側では「接続」（`gnome-connections`）を開き、接続先に `nixos-desktop` を指定して RDP 接続します。
設定画面で標準と異なるポートが表示されている場合は、`nixos-desktop:3390` のように指定してください。

※ ポートは tailnet 側（`tailscale0`）に対してのみ開放されています。LAN 内から `nixos-desktop.local` 指定で RDP 接続することはできません。

※ 画面ロック時や、再起動後に誰もログインしていない状態での RDP 接続の挙動は未検証です。外出前に、後述の「出かける前の確認事項」の手順 4 でテストしておいてください。

## 出かける前の確認事項

1. デスクトップの電源が入っており、tailnet に参加していることを確認する：
   ```sh
   ssh desktop 'tailscale status'
   ```
   一覧に `nixos-desktop` と `nixos-spin713` が表示されているはずです。
2. デスクトップのキー期限切れ（Key Expiry）が無効化されていることを確認する（Admin Console の Machines ページで確認。手順は次節の 4 を参照）。
3. ラップトップを LAN 以外の回線（スマホのテザリングなど）に接続し、tailnet 経由で接続できるかテストする：
   ```sh
   ssh desktop-ts 'echo ok'
   tailscale ping nixos-desktop
   ```
   `tailscale ping` の応答に `via DERP` と表示される場合は中継サーバー経由です。接続は可能ですが低速になります。
4. RDP を利用する場合は、デスクトップの画面をロックした状態で、外部回線につないだラップトップから「接続」アプリで `nixos-desktop` へ RDP 接続できるか試す。

外出中にデスクトップの NixOS 世代（generation）を切り替えると、ネットワークや sshd、tailscaled を破損する変更が含まれていた場合、帰宅するまで復旧できなくなります。
**外出中はデスクトップ上で `switch` を実行しないでください。**

## ホストを tailnet に参加させる

新しいホストを追加した際や、OS を再インストールした際に実行します。1 ホストにつき最初の 1 回のみ行えばよく、認証状態は `/var/lib/tailscale` に保存されるため再起動後も保持されます。

1. 対象ホストで `switch` を実行する（`tailscale.nix` は `common.nix` 経由で読み込まれるため、ホスト個別の追加設定は不要です）
2. 対象ホスト上で以下を実行する（LAN 内であれば `ssh desktop` 経由でも可）：
   ```sh
   sudo tailscale up
   ```
   表示された URL を任意の端末のブラウザで開き、Tailscale アカウントでログインして認証します。
3. 参加状態を確認する：
   ```sh
   tailscale status                 # 自ホストと接続対象の両方が表示されるか確認
   getent ahostsv4 nixos-desktop    # 相手のホスト名を名前解決。100. で始まる IP アドレスが返れば OK
   ```
   ※自ホストの名前解決を試すとローカル IP アドレスが返ってしまうため、確認には必ず相手のホスト名を使用してください。
4. 常時稼働させるホスト（デスクトップ）は、Admin Console の Machines ページにある各行右端のメニューから「Disable Key Expiry」を選択します。デフォルトの有効期限は 180 日であり、期限が切れると再認証するまで tailnet から除外されます。

外出先からデスクトップへアクセスする経路は tailnet のみとなるため、デスクトップの `tailscale up` は必ず出かける前に LAN 内で済ませておいてください。

## ラップトップで tailnet から一時的に切断する

```sh
sudo tailscale down   # 一時切断
sudo tailscale up     # 再接続（認証済みであればブラウザは開きません）
```

切断中は `-ts` の接続名は使用できません。ただし、LAN 内での `ssh desktop` などには影響しません。

## トラブルシューティング

### `Could not resolve hostname nixos-desktop`

手元のホストが tailnet に参加していないか、MagicDNS の設定が `resolv.conf` に反映されていません。

```sh
tailscale status             # Logged out や Stopped の場合は sudo tailscale up を実行
cat /etc/resolv.conf         # nameserver 100.100.100.100 および search <tailnet名>.ts.net が存在するか確認
```

`tailscale status` が正常なのに `resolv.conf` に反映されていない場合は、`journalctl -u tailscaled` で `dns:` から始まるログを確認してください。
また、Admin Console の DNS ページで MagicDNS が無効になっている場合も短縮ホスト名は解決できません。

### `tailscale status` に `nixos-desktop-1` のような名前で表示される

同じホスト名の古い端末が tailnet 上に残っており、新規端末に連番が付与されています。
Admin Console の Machines ページから古い端末を削除し、新しい端末のホスト名を `nixos-desktop` に修正してください。接続用ホスト名 `desktop-ts` は `nixos-desktop` を名前解決するため、不一致があると接続できません。

### 「設定」→「システム」に「リモートデスクトップ」が表示されない

システム側の `gnome-remote-desktop.service` が `enabled` になっていません。GNOME の設定画面は、同サービスが `enabled` 以外の状態では項目を非表示にします。

```sh
systemctl show gnome-remote-desktop.service -p UnitFileState   # enabled かどうか確認
```

`linked` と表示される場合は、デスクトップが `hosts/nixos-desktop/default.nix` の `wantedBy` を含む世代に `switch` されていません。`switch` を実行してから再度 GNOME 設定を開き直してください（詳細は [../architecture/tailscale.md](../architecture/tailscale.md#gui-の確認は-rdp-でデスクトップの画面ごと使う) を参照）。

### RDP で接続できない

まず `ssh desktop-ts` で SSH 接続が通るか確認してください。通らない場合は後述の項目を確認します。
SSH が通る場合は、デスクトップ側で RDP サーバーが待機しているポートを確認します：

```sh
ssh desktop-ts 'ss -ltn | grep -E ":33(89|9[0-9])"'
```

何も表示されない場合は、GNOME の設定でリモートデスクトップが無効化されています。
3389〜3399 以外のポートで待機している場合は、ファイアウォールの許可範囲外になっています。`gsettings get org.gnome.desktop.remote-desktop.rdp port` で設定値を確認し、許可範囲内に変更するか、`hosts/nixos-desktop/default.nix` で設定範囲を広げてくだい。

### `ssh desktop-ts` がタイムアウトする

`tailscale status` でデスクトップの状態を確認してください。`offline` になっている場合、デスクトップの電源が切れているか、サスペンド状態になっているか、ネットワークから切断されています。
tailnet 経由でサスペンドから復帰させることはできないため、帰宅するか、自宅にいる人に電源を入れてもらう必要があります。
なお、デスクトップは無操作で自動サスペンドしないよう設定されています（[../architecture/tailscale.md](../architecture/tailscale.md)）。手動でサスペンドした場合や、停電などで終了した場合は自動復帰しません。
