# デスクトップの Windows VM を FreeRDP で使う

使い方: [howtouse/windows-vm.md](../howtouse/windows-vm.md)

実装: [modules/home-manager/windows-vm.nix](../../modules/home-manager/windows-vm.nix)、[modules/home-manager/windows-vm.sh](../../modules/home-manager/windows-vm.sh)、検証: [tests/windows-vm.py](../../tests/windows-vm.py)

nixos-desktop の libvirt VM（`win11`）は、VM の中の MotionPro（Array Networks の SSL VPN クライアント）と mstsc で会社 PC に接続するときと、たまに Windows を使うときに起動する。
画面は SPICE ではなくホストの FreeRDP から RDP で表示し、VM は使うときだけランチャー（`windows-vm`）で起動する。
以下の観察はいずれも 2026-10-14 のもので、FreeRDP 3.31.1（nixpkgs の `freerdp`。`sdl-freerdp` は SDL3 のクライアント）、QEMU のマシン型 `pc-q35-9.2`、Windows 11 Education（ビルド 26200）で確かめた。

## SPICE ではなく RDP で表示する

VM のビデオは QXL で 3D アクセラレーション（`gl`）は無効、表示は SPICE（virt-manager）だった。
この経路では、VM の中のメモ帳でも打鍵が遅れ、会社 PC への RDP ではさらに遅れた。
VM の Windows でリモートデスクトップを有効にし、ホストの `sdl-freerdp` から接続すると、VM の中と会社 PC の両方で操作感がかなり改善した。
比べたのは体感で、遅延の数値は測っていない。

GPU を VM に渡す案（パススルーや Looking Glass）は、ホストの GPU が RX 6600 の一枚だけなので取れない。
SPICE と QXL の設定を調整する案は、変えられる項目が少なく、RDP に切り替えたほどの効果は見込めないので試していない。

USB リダイレクトは SPICE の機能なので、SPICE の画面は残し、USB を渡すときだけ virt-manager で開く。
SPICE と RDP を同時に接続したときの動作（RDP の接続中は SPICE 側がロック画面になり、USB はそのまま渡せる）は、Windows と SPICE の一般的な挙動からの見込みで、まだ確かめていない。

## NLA を切る

VM の Windows には Microsoft Entra ID のアカウントでサインインしている。
NLA を有効にしたままでは、FreeRDP から接続できなかった。

- ユーザー名を `\AzureAD\<UPN>` にすると、FreeRDP は UPN のドメインを Kerberos のレルムとみなして KDC を探し、`Cannot contact any KDC for realm` でタイムアウトした。
- `/auth-pkg-list:!kerberos` を足しても Kerberos を試し、最後は `ERRCONNECT_LOGON_FAILURE` で拒否された。

Microsoft の資料（[Connect to remote Microsoft Entra joined device](https://learn.microsoft.com/en-us/windows/client-management/client-tools/connect-to-remote-aadj-pc)）によると、Entra ID の認証を使わない RDP で Entra ID のアカウントを使うには、接続元と接続先が同じテナントにある必要がある。
ホストの NixOS はテナントに参加していないので、この条件を満たせない。

NLA を切り、`/sec:tls` で接続して Windows のサインイン画面からサインインすると使えた。
代償として、3389 番ポートに届く相手には、認証の前に動く RDP の処理と、サインイン画面でのパスワードの試行がさらされる。
この VM は libvirt の `default` ネットワーク（NAT）の内側にあり、外から VM への新しい接続は libvirt の NAT の規則で通らない。届くのはホスト自身（ホストで動くすべてのプロセス）と、同じ `default` ネットワークにつながるほかの VM だけなので、これを受け入れる。

同じ資料にある Entra ID の認証（mstsc の `enablerdsaadauth`、FreeRDP の `/sec:aad`）は、接続元がテナントに参加していなくても使える。
ただし接続先をホスト名で指定する必要があり、テナントの条件付きアクセスにも左右されるので、試していない。
FreeRDP の `/sec:aad` で接続できると確かめられたら、NLA を戻す。

## 使うときだけ起動する

Windows を使うのは週に数回程度で、VM は動いている間、最大 12 GiB のメモリを使う（ホストは 32 GiB）。
そのため常時起動はしない。
ランチャーは、VM が止まっていれば起動し、`virsh domifaddr --source lease` で引いた IP の 3389 番ポートが応答するまで待ってから接続する。
待つ上限の既定値は 600 秒にする。2026-10-15 に、前回のシャットダウンで予約された Windows Update を適用する起動で、VM の起動から Windows が DHCP でアドレスを求めるまで約 5 分かかり、当初の 180 秒では足りなかった。代償として、RDP が本当に応答しない場合（リモートデスクトップが無効になったなど）は、知らせるまで最大 10 分かかる。
終わるときは Windows のスタートメニューからシャットダウンし、VM ごと止める。

退けた案は次の二つ。

- FreeRDP を閉じたら自動で VM をシャットダウンする: 止め忘れはなくなるが、ウィンドウを閉じただけで保存していない作業ごと Windows が終了し、再接続もできなくなる。
- 閉じたら libvirt の managed save で状態を保存し、次回すぐに再開する: 起動待ちはなくなるが、保存先の `/` は空きが 13 GB（使用率 97%）しかなく、最大 12 GiB のメモリの内容を書き込むと埋まりかねない。再開後は VPN の接続も切れているので、再接続の手間は残る。`/` に余裕ができ、起動待ちが気になるようになったら試す。そのときは、virtiofs の共有があっても保存できるかを先に確かめる。

VM の IP は libvirt の DHCP で割り当てられ、変わりうるので、ランチャーは問い合わせのたびに引き直す。
libvirt の NSS モジュールで VM の名前を引けるようにする案は、一つのスクリプトのためにシステムの名前解決を変えることになるので採らない。

## 止め忘れの通知と二重起動

FreeRDP のウィンドウだけを閉じると VM は動いたまま残るので、ランチャーは通知で知らせ、ボタンから止められるようにする。
スタートメニューからシャットダウンしたときも FreeRDP が先に終わり、VM が止まるのはその数十秒後になる。そのまま状態を調べると止め忘れと区別できないので、ランチャーは FreeRDP が終わってから VM が止まるのを最大 60 秒（2 秒おきに 30 回）待ち、それでも動いているときだけ通知する。
GNOME の通知は一覧に残るので、古い通知のボタンを後から押すと、そのとき使っている別のセッションの Windows まで止めてしまう。
これを防ぐため、ランチャーは起動を待つ間から FreeRDP が終わるまで `$XDG_RUNTIME_DIR/windows-vm.lock` を `flock` で握り、ボタンの処理はロックを握れたときだけ VM を止める。
同じロックで二重起動も止める。同じ VM に二つ目の RDP 接続を張ると、一つ目が切れるからである。

起動を待つ間も毎回 VM の状態を調べ、`running` でなくなったら時間切れを待たずに知らせて終わる。待ち続けるとロックを握ったままになり、もう一度開いても二重起動として断られる（2026-10-15 に、待機中に VM の電源が切れてこの状態になった）。
1 分ほど（30 回の問い合わせ）待っても接続できないときは、更新の適用中かもしれないことと、SPICE で画面を見られることを一度だけ通知する。

アプリ一覧から起動すると端末がなく、エラーの出力が見えない。
想定した失敗（VM の状態、起動待ちの間の停止とタイムアウト、二重起動）は内容を通知し、それ以外の失敗も終了時に通知する。
通知の文言は Gemini で自然な日本語に直したものを使っている。

## キーボードの掴みを右 Alt で切り替える

FreeRDP はフォーカスのある間キーボードを掴むので、Super や Alt+Tab は Windows に渡り、GNOME の操作に使えない。
同じキーを両方に割り当てることはできないので、掴む状態とホストに返す状態を切り替えるキーを決める。VirtualBox のホストキー（既定は右 Ctrl の単独押し）と同じ方式にする。

GNOME には、アプリが奪ったショートカットを取り戻すキー（mutter の `restore-shortcuts`、既定は `Super+Escape`）がある。
ただし取り戻す方向だけで切り替えにはならず、このデスクトップでは dconf で空に上書きされている。PaperWM が `Super+Escape` を `toggle-scratch-window` に使っている。

FreeRDP 3.31.1 の SDL のクライアント（`client/SDL/SDL3/sdl_input.cpp`）では、キーが押されたときに、その時点の修飾キーの状態が `SDL_KeyModMask` を含み、押されたキーが `SDL_Grab` と一致すると、掴みを切り替える。一致したキーは Windows に送らない。
修飾キー自身を `SDL_Grab` に指定してもこの条件は満たせるので、`SDL_KeyModMask` を `KMOD_RALT`、`SDL_Grab` を `SDL_SCANCODE_RALT` にして、右 Alt の単独押しで切り替える。
設定は `~/.config/freerdp/sdl-freerdp.json` から読まれる。FreeRDP はこのファイルに書き込まないので、Home Manager から置く。

右 Ctrl と Fn も候補にしたが、使わない。HHKB には右 Ctrl がない。Fn は、つないでいるキーボード（HHKB-BT Keyboard と SEM USB Keyboard）がどちらもキーボードの中で処理し、OS に送らない（カーネルが示す各デバイスのキーの一覧に `KEY_FN` がない）。
右 Alt を使えるように、keyd の右クリックの連打は、◇ + 右 Alt で入り切りするレイヤー（`toggle(turbo)`）に置く（[keyd-turbo.nix](../../hosts/nixos-desktop/keyd-turbo.nix)）。普段のモードでは右 Alt がそのままアプリに届く。
起動時と keyd の再起動後は普段のモードになる。いまどちらのモードかは画面に出ない。

keyd に右 ◇ の「叩いたら右 Ctrl」（`overload`）を作らせる案は退けた。keyd は叩いた動作を、押す信号と離す信号を間を置かずに続けて送る。FreeRDP は押した信号を処理する時点で修飾キーの状態を読むので、その時点ではもう離されていて、切り替えが発動しないおそれが高い（ソースからの推論で、試してはいない）。

代償は次のとおり。

- 右 Alt が Windows に届かなくなる。左 Alt は使える。
- FreeRDP のほかのホットキーも右 Alt との組み合わせになり（全画面は右 Alt + Enter）、押すと掴みも一緒に切り替わる。
- ターボのモードの間は、右 Alt が連打に使われるので切り替えられない。
- ◇ + 右 Alt は keyd が消費するので、◇ + Alt + キーのショートカットは左 Alt で押す。GNOME（◇ + Alt + S のスクリーンリーダー、◇ + Alt + 8 の拡大鏡など）、PaperWM（◇ + Alt + R、◇ + Alt + 矢印キー）、Windows（◇ + Alt + K のマイクのミュート、Xbox Game Bar の ◇ + Alt + R など）にある。◇ + Alt だけで動くものはない。
- このユーザーが起動するすべての `sdl-freerdp` に適用される。virt-manager など、ほかのツールでは別のキーを使う。

修飾キーの状態は、イベントを処理する時点で `SDL_GetModState()` から読まれる。そのため、ごく短く叩くと、処理の前に離したとみなされて取りこぼす可能性がある。
実機ではまだ確かめていない。取りこぼしが目立つなら、修飾キーと別のキーの組み合わせ（右 Alt + G など）に戻す。

## 会社 PC との接続で分かったこと

VM の中の mstsc は手元の MotionPro（`127.0.0.1`）に接続し、MotionPro がその通信をトンネルで会社へ送る。
YouTube などの通信はこのトンネルを通らないので、家の回線が速くても、トンネルの速さについては何も分からない。

MotionPro のトンネルのプロトコルを TCP から UDP に変えると、mstsc の接続情報が示す帯域は 460 Kbps から 1.14 Mbps に、RTT は 53 ms から 45 ms になった（それぞれ一回ずつの測定）。
mstsc は手元の MotionPro に TCP で接続するので、接続情報のトランスポートは UDP にしても TCP のまま表示される。
UDP でトンネルを張れたことは、MotionPro のプロセスが外向きの UDP ポートを開いていることで確かめた。
Array Networks の SSL VPN が DTLS（UDP）のトンネルを持つことは、[OpenConnect の資料](https://www.infradead.org/openconnect/array.html) にも書かれている。

会社 PC の RemoteFX のパフォーマンスカウンタの RTT は当てにしない。
従来の mstsc では UDP の RTT が常に 0 になり、TCP の RTT も動かなくなるという報告があり（[Microsoft Q&A](https://learn.microsoft.com/en-us/answers/questions/109572/remotefx-rtt-performance-counters)）、今回も 3 回とも同じ値だった。
mstsc の接続バーから開く接続情報のほうを使う。

会社 PC とのクリップボードは連携しない。
会社 PC では `fDisableClip` がポリシーに設定されておらず、`WinStations\RDP-Tcp` の値も `0` で、`rdpclip` も動いていた。
止めているのは MotionPro が mstsc に渡す接続設定かゲートウェイで、会社の管理によるものなので回避しない。
