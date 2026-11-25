# Tailscale（LAN 外からのデスクトップ利用）

自宅 LAN の外から tailnet 経由でデスクトップに SSH 接続したり、ビルド処理をデスクトップに委任したりするための設定です。
`tailscaled` は、[tailscale.star](../../config/elements/tailscale.star) をハードウェアプロファイルの `requires` から入れるホストで有効になります。無効にするには、ハードウェアプロファイルの `requires`（desktop と spin713 では、ハードウェアプロファイルが挙げる [personal_pc.star](../../config/elements/personal_pc.star) の `requires`）から `tailscale` を外し、`tailscale` を依存に含む `remote_build` もハードウェアプロファイルの `requires` から外します。

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

## 外出先からデスクトップの画面を使う（Sunshine + Moonlight）

配信先では `serve_remote_desktop`、クライアントでは `use_remote_desktop` をユーザーの利用目的で選びます。接続先は `find_home_server` が解決します。固定 Niri fork のハッシュ確定・ビルドと、配信の実機確認はまだ必要です。[Niri の確認](niri.md) も行ってください。

### 初回の設定とペアリング

1. 配信アカウントで Niri を開始します。デスクトップでログイン済みならそのセッションを使います。誰もそのユーザーで GUI にログインしていなければ、クライアントから `ssh desktop-ts remote-niri start` で headless を起動します。
2. クライアントで `remote-desktop pair` を実行します。これは Sunshine Web UI への SSH トンネルを開くだけで、自動ペアリングは行いません。コマンドを動かしたままブラウザで `https://localhost:47990` を開き、初回の管理アカウントを設定します。
3. Moonlight を起動し、MagicDNS の配信ホスト名（現在は `nixos-desktop`）を手動追加します。Moonlight に表示された PIN を Sunshine Web UI へ入力します。認証情報をリポジトリへ保存しません。
4. `Extend (Virtual Display)` を選び、映像と入力を確認します。終わったらトンネルを `Ctrl+C` で閉じます。

### 日常の開始と終了

ローカルセッションがない状態では、次で headless を起動して Moonlight へ接続します。

```sh
remote-desktop start
```

ローカル Niri が動いているとヘルパーは開始を断ります。そのセッションを使う場合は Moonlight の GUI から直接接続してください。同じユーザーで headless とローカルを同時に起動しません。

配信アプリの準備処理がクライアントの解像度で仮想出力を作り、終了処理が削除します。Moonlight 側で配信アプリを終了してから、headless セッションを止めます。

```sh
remote-desktop stop
```

headless 内のアプリも終了するので、先に作業を保存してください。ローカル Niri が動いている場合、stop も拒否してそのセッションの Sunshine を保護します。単なる切断・異常切断後の出力削除と再接続、ロック中の動作は実機未確認です。

配信ポートは tailnet のインターフェースに限って開けます。Web UI のポートは直接開けず、上の SSH トンネルを使います。Windows VM の FreeRDP/RDP は、この画面配信とは別です。

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
4. 画面配信を使う場合は、外部回線から Moonlight の接続・入力・配信アプリの終了を試す。画面ロック中と、再起動後の SSH による headless 起動も別々に試す。

外出中にデスクトップの NixOS 世代（generation）を切り替えると、ネットワークや sshd、tailscaled を破損する変更が含まれていた場合、帰宅するまで復旧できなくなります。
**外出中はデスクトップ上で `switch` を実行しないでください。**

## ホストを tailnet に参加させる

新しいホストを追加した際や、OS を再インストールした際に実行します。1 ホストにつき最初の 1 回のみ行えばよく、認証状態は `/var/lib/tailscale` に保存されるため再起動後も保持されます。

1. 対象ホストで `switch` を実行する（個人の2台では `machine_*` の依存に `tailscale` が含まれています）
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

### Moonlight に接続できない、または画面が違う

まず `ssh desktop-ts` が通るかを確認します。SSH が通る場合は配信アカウントで次を実行します。

```sh
ssh desktop-ts 'remote-niri status'
ssh desktop-ts 'journalctl --user -b -u sunshine.service -u niri-headless.service -u niri.service --no-pager -n 100'
```

Sunshine のログでキャプチャ方式、選択された出力、エンコーダーのエラーを調べます。`output_name` で指定した仮想出力を実際にキャプチャしているかは、配信開始後のログと画面の両方で確認します。Niri の端末では `niri msg outputs` で出力を確認できます。ペアリングのやり直しには `remote-desktop pair` で Web UI を開いてください。

`remote-niri` がローカルセッションを検出した場合は、ログアウトして headless を使うか、既存の Niri に Moonlight から接続します。別のユーザーに切り替えて回避せず、配信を選んだアカウントで操作してください。

### `ssh desktop-ts` がタイムアウトする

`tailscale status` でデスクトップの状態を確認してください。`offline` になっている場合、デスクトップの電源が切れているか、サスペンド状態になっているか、ネットワークから切断されています。
tailnet 経由でサスペンドから復帰させることはできないため、帰宅するか、自宅にいる人に電源を入れてもらう必要があります。
なお、デスクトップは無操作で自動サスペンドしないよう設定されています（[../architecture/tailscale.md](../architecture/tailscale.md)）。手動でサスペンドした場合や、停電などで終了した場合は自動復帰しません。
