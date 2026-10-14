# デスクトップの Windows VM を FreeRDP で使う

状態: 設計（未実装）。

## 目的

nixos-desktop の libvirt VM `win11` の画面を、SPICE ではなくホストの FreeRDP で表示し、GNOME のアプリ一覧から起動できるようにする。
VM の中では MotionPro（Array Networks の SSL VPN クライアント）と mstsc を使って会社 PC に RDP で接続しており、SPICE で表示すると VM の中でも会社 PC でも打鍵が遅れていた。

Windows を使うのは週 2 回のアルバイトのときと、それ以外のときにたまにだけなので、VM は常時起動しない。
使うときにランチャーから起動し、終わったら Windows ごと止める。
USB リダイレクトが必要なときだけ、これまでどおり virt-manager の SPICE の画面を使う。

## 確認済みの前提

いずれも 2026-10-14 に確かめた。

- `win11` のビデオは QXL で、`<gl enable='no'/>`、表示は SPICE（virt-manager）。vCPU 16 個はホストの CPU 8〜15 と 24〜31 に固定され、Hyper-V の拡張は一通り有効。NIC は e1000e で libvirt の `default` ネットワーク（NAT）につながる。`/home/pomu/sagyo` を virtiofs で共有している。
- ホストの GPU は RX 6600 の一枚だけで、GPU パススルーは使えない。
- VM の Windows は Windows 11 Education（ビルド 26200）で、Microsoft Entra ID のアカウントでサインインしている。
- SPICE で表示しているときは、VM の中のメモ帳でも打鍵が遅れ、会社 PC への RDP ではさらに遅れていた。VM の Windows でリモートデスクトップを有効にし、ホストから `sdl-freerdp` で接続すると、VM の中と会社 PC の両方で操作感がかなり改善した（ご本人の体感）。
- NLA を有効にしたままでは、FreeRDP（3.31.1）から接続できなかった。ユーザー名を `\AzureAD\<UPN>` にすると、FreeRDP は UPN のドメインを Kerberos のレルムとみなして KDC を探し、`Cannot contact any KDC for realm '<UPN のドメイン>'` でタイムアウトした。`/auth-pkg-list:!kerberos` を足しても Kerberos を試し、最後は `ERRCONNECT_LOGON_FAILURE` になった。
- NLA を切り、`/sec:tls` で接続して Windows のサインイン画面からサインインすると使えた。
- `+clipboard` で、ホストと VM のあいだのクリップボードは連携する。
- 会社 PC とのクリップボードは連携しない。会社 PC 側では `fDisableClip` が設定されておらず（ポリシーのキーに値がなく、`WinStations\RDP-Tcp` は `0`）、`rdpclip` も動いていたので、止めているのは MotionPro が mstsc に渡す接続設定かゲートウェイ。会社の管理によるものなので、手元で回避しない。
- nixpkgs の `freerdp` 3.31.1 には `sdl-freerdp`（SDL3、Wayland に直接つながる）、`xfreerdp`、`wlfreerdp` が入っている。
- ホストの `/` は空きが 13 GB（使用率 97%）。
- 使っている Home Manager の `xdg.desktopEntries` は `actions` を持つ。

## 決めたこと

### `local.windowsVm` モジュールを置き、デスクトップだけで有効にする

`modules/home-manager/windows-vm.nix` に `local.windowsVm` を定義し、`hosts/nixos-desktop/home-manager-pomu.nix` で import して有効にする。`minecraft-backup.nix` と同じ形にする。

オプションは三つにする。

- `enable`: `mkEnableOption`。
- `domain`: libvirt のドメイン名。既定値は置かず、デスクトップで `"win11"` を指定する。
- `bootTimeoutSeconds`: VM を起動してから RDP が応答するまで待つ上限。既定は 180 秒。Windows Update の適用で起動が長引くときは呼び出し側で延ばす。

接続先は `qemu:///system` に固定する。VM はそこにしかなく、オプションにする理由がない。

`local.profile.features.gui` が無効の場合と Linux 以外の場合は、assertion で評価を止める。

### コマンド `windows-vm` を三つのサブコマンドで作る

`writeShellApplication` で作り、`runtimeInputs` に `libvirt`、`freerdp`、`libnotify`、`virt-manager`、`util-linux`（`flock`）を入れる。

`windows-vm connect` は次の順に動く。

1. `virsh domstate` で状態を調べる。`shut off` なら `virsh start` で起動し、「Windows を起動しています」と通知する。`running` ならそのまま進む。それ以外の状態（`paused` など）は、状態を書いたエラーを通知して終わる。
2. `bootTimeoutSeconds` を期限に、`virsh domifaddr --source lease` で最初の IPv4 アドレスを引き、そのアドレスの 3389 番ポートに TCP で接続できるまで数秒おきに試す。期限を過ぎたら、待った秒数を書いたエラーを通知して終わる。
3. `$XDG_RUNTIME_DIR/windows-vm.lock` を `flock -n` で握ったまま、`sdl-freerdp /v:<IP> /sec:tls /dynamic-resolution /network:lan +clipboard /cert:tofu` を実行する。ロックを握れなければ、すでに接続していると通知して終わる。同じ VM に二つ目の RDP 接続を張ると一つ目が切れるので、二重に起動させない。
4. FreeRDP が終わったあとも VM が `running` なら、「シャットダウン」のボタン付きで「Windows はまだ起動しています」と通知する（`notify-send --action --wait`）。ボタンが押されたら、ロックを `flock -n` で握れた場合に限り `virsh shutdown` する。

`windows-vm shutdown` は、VM が `running` なら `virsh shutdown` を実行し、要求したことを通知する。
アプリ一覧の右クリックから明示的に選ぶ操作なので、接続中でも止める。

`windows-vm console` は `virt-manager --connect qemu:///system --show-domain-console <domain>` を実行する。
VM の電源の操作は virt-manager に任せる。

### 通知のボタンはロックで守る

GNOME の通知はメッセージ一覧に残るので、古い通知のボタンをあとで押すと、そのとき使っている別のセッションの Windows まで止めてしまう。
`connect` が FreeRDP の実行中にロックを握り、ボタンの処理はロックを握れたときだけ VM を止める。

### アプリ一覧に「Windows」を置く

`xdg.desktopEntries.windows-vm` で、名前を「Windows」、`Exec` を `windows-vm connect` にする。
`actions` に「シャットダウン」（`windows-vm shutdown`）と「SPICE で開く」（`windows-vm console`）を置く。

### VM の Windows 側の設定は手順として文書にする

リモートデスクトップの有効化と NLA の無効化は VM の中の設定で、repo からは管理できない。
`docs/howtouse/windows-vm.md` に手順として書く。

NLA を切ると、3389 番ポートに届く相手は誰でもサインイン画面まで進める。
この VM は libvirt の NAT の内側にあり、届くのはホストと同じネットワークの VM だけなので、これを受け入れる。

### クリップボードの範囲

ホストと VM のあいだだけを対象にする。
会社 PC とのクリップボードは、会社の管理で止められているので扱わない。

## 退けた案

- FreeRDP を閉じたら自動で VM をシャットダウンする: 止め忘れはなくなるが、ウィンドウを閉じただけで保存していない作業ごと Windows が終了し、再接続もできなくなる。
- 閉じたら libvirt の managed save で状態を保存し、次回すぐに再開する: 起動待ちはなくなるが、保存先の `/` は空きが 13 GB しかなく、最大 12 GiB のメモリの内容を書き込むと埋まりかねない。再開後は VPN の接続も切れているので、再接続の手間は残る。
- VM の名前の解決に libvirt の NSS モジュールを使う: 一つのスクリプトのためにシステムの名前解決を変えることになる。`virsh domifaddr` で足りる。
- NLA を有効にしたまま接続する: FreeRDP からは Entra ID のアカウントで NLA を通せなかった（「確認済みの前提」）。FreeRDP の `/sec:aad`（Entra ID の認証）は、テナントの条件付きアクセスに左右されるので試していない。
- SPICE と QXL の設定を調整する: 変えられる項目が少なく、RDP に切り替えたほどの効果は見込めない。

## 未確認

- 保存していない作業があるときに、`virsh shutdown`（ACPI の電源ボタン）で Windows が止まるか。止まらなかったら「SPICE で開く」で状態を確かめる、と文書に書く。
- `sdl-freerdp` のウィンドウが GNOME で「Windows」のアイコンにまとまるか。まとまらなければ `/wm-class` と `StartupWMClass` を合わせる。
- VM の証明書が変わったとき、アプリ一覧から起動した `sdl-freerdp` が確認の画面を出すか。
- アプリ一覧から起動したときの `windows-vm` と FreeRDP の出力がどこに残るか（journal に出るなら、文書に調べ方を書く）。

## 変更するファイル

- `modules/home-manager/windows-vm.nix`（新規）
- `hosts/nixos-desktop/home-manager-pomu.nix`: import と `local.windowsVm` の設定
- `docs/howtouse/windows-vm.md`（新規）と `docs/howtouse/README.md` の目次
- `docs/architecture/windows-vm.md`（新規）と `docs/architecture/README.md` の目次

## 確かめ方

- `nix eval` で nixos-desktop の Home Manager の構成を評価し、`windows-vm` をビルドする（`writeShellApplication` が shellcheck を通す）。
- `local.profile.features.gui` を無効にした構成で assertion が評価を止めることを、`extendModules` で確かめる。
- ドキュメントは `python3 scripts/check-docs.py .` と `git diff --check` で確かめる。
- switch したあとにご本人に確かめてもらう: VM が止まっている状態からの `connect`、すでに動いている状態からの `connect`、FreeRDP を閉じたあとの通知とボタン、二重起動の拒否、右クリックの「シャットダウン」と「SPICE で開く」。
