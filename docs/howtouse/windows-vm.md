# デスクトップの Windows VM（使い方）

設計判断: [architecture/windows-vm.md](../architecture/windows-vm.md)

実装: [modules/home-manager/windows-vm.nix](../../modules/home-manager/windows-vm.nix)、[modules/home-manager/windows-vm.sh](../../modules/home-manager/windows-vm.sh)

nixos-desktop の libvirt VM は、使うときだけ起動し、画面をホストの FreeRDP で表示します。
VM の名前は、[hosts/nixos-desktop/home-manager-pomu.nix](../../hosts/nixos-desktop/home-manager-pomu.nix) の `local.windowsVm` で指定しています。起動を待つ上限は既定の 600 秒です。

## 使う

GNOME のアプリ一覧から「Windows」を開きます。
VM が止まっていれば起動し、RDP が応答するまで待ってから接続します。待っている間は「Windows を起動しています」と通知されます。
1 分ほどたっても接続できないときは、「Windows の起動に時間がかかっています」と一度だけ通知されます。Windows Update を適用する起動は数分かかります。
Windows のサインイン画面が出たら、パスワードでサインインします。ユーザーを選ぶ画面では「他のユーザー」を選び、メールアドレスの形のユーザー名（UPN）を入力します。

ウィンドウの大きさを変えると、Windows の解像度もそれに合わせて変わります。
ホストと Windows のあいだでは、テキストのコピー＆ペーストができます。

端末から `windows-vm connect` を実行しても同じ動作になり（`connect` は省略できます）、こちらでは FreeRDP の出力を確認できます。

## Super や Alt+Tab を Windows に渡すか切り替える

FreeRDP のウィンドウにフォーカスがある間、FreeRDP はキーボードを掴み、Super や Alt+Tab も Windows に渡します。
右 Alt を単独で押すたびに、キーボードを Windows に渡す状態と、ホスト（GNOME）に残す状態が切り替わります。ホストに残している間は、Super や Alt+Tab が GNOME の操作になります。
右 Alt そのものは Windows に届きません。Windows で Alt を使うとき（Alt+Tab など）は左 Alt を使います。Windows では AltGr の文字を打てません。
切り替えは、ホストのキー配列で右 Alt が AltGr になっていることを前提にしています。既定の配列は English (intl., with AltGr dead keys) です。GNOME の設定で右 Alt が AltGr にならない配列に変えると、切り替わらなくなります。
FreeRDP のほかのホットキーも右 Alt との組み合わせになります（全画面は右 Alt + Enter）。右 Alt を押した時点で切り替えも起きるので、もう一度右 Alt を押して戻します。
ゲーム用のターボ（◇ + 右 Alt で入り切りする、右 Alt での右クリックの連打）を入れている間は、右 Alt が連打に使われるので切り替えられません。◇ + 右 Alt でターボを切ってから使います。
設定は `~/.config/freerdp/sdl-freerdp.json` にあり、このユーザーが起動するすべての `sdl-freerdp` に適用されます。
右 Alt での切り替えは、まだ実機で確かめていません。

## 終わる

Windows のスタートメニューからシャットダウンします。
Windows が止まると VM も止まり、FreeRDP のウィンドウも閉じます。

FreeRDP のウィンドウだけを閉じると、Windows のセッションは切断された状態で残ります。ウィンドウが閉じてから 1 分ほどたっても Windows が動いていると、「Windows はまだ起動しています」と通知されます（スタートメニューからのシャットダウンでも Windows が止まるまで数十秒かかるので、その間は待ちます）。
通知の「シャットダウン」を押すと VM を止めます。何もしなければ VM は動いたままで、もう一度「Windows」を開けば同じセッションに戻れます。
あとで止めるときは、アプリ一覧の「Windows」を右クリックして「シャットダウン」を選びます。

通知のボタンは、押した時点で別の接続が開いていれば、VM を止めずに「Windows を停止しませんでした」と通知します。古い通知のボタンで、使っている最中の Windows を止めないためです。

シャットダウンは ACPI の電源ボタンを押したのと同じ操作（`virsh shutdown`）なので、保存していない作業が残っていると Windows が止まらないことがあります。
止まらないときは、右クリックの「SPICE で開く」で Windows の画面を確かめます。

## USB を Windows に渡す

USB リダイレクトは SPICE の機能です。
アプリ一覧の「Windows」を右クリックして「SPICE で開く」を選び、virt-manager の画面から USB 機器を渡します。
RDP で接続したままでも渡せるはずです。ただし、Windows は画面を一つのセッションにしか表示しないので、RDP で接続している間は virt-manager 側がロック画面になると見込んでいます（どちらもまだ確かめていません）。

## 会社 PC とのクリップボード

VM の中の MotionPro から会社 PC に RDP で接続したときは、クリップボードが連携しません。
会社 PC 側はクリップボードを受け付けているので、止めているのは MotionPro が mstsc に渡す接続設定かゲートウェイです。
会社の管理による設定なので、手元で回避しません。

## VM を作り直したとき

Windows で次の二つを設定します。

1. 「設定」→「システム」→「リモート デスクトップ」をオンにする。
2. 同じ画面でオンのスイッチの横を展開し、「ネットワーク レベル認証」を必須にするチェックを外す。

NLA を切る理由は [設計判断](../architecture/windows-vm.md#nla-を切る) にあります。
VM の名前が変わったときは、`local.windowsVm.domain` を合わせます。

## うまくいかないとき

「Windows に接続できません」と通知されたら、待つ上限（既定は 600 秒）のうちに RDP が応答しませんでした。
起動が長引いているときは、右クリックの「SPICE で開く」で画面を確かめ、起動し終わってからもう一度開きます。毎回足りないなら `local.windowsVm.bootTimeoutSeconds` を延ばします。
Windows のリモートデスクトップが無効になっている場合も、同じ通知になります。

「Windows は起動待機中または接続中です」と通知されたら、別に開いた「Windows」が起動を待っているか、接続しています。

「Windows が停止しました」と通知されたら、起動を待つ間に VM が止まりました。もう一度「Windows」を開くと起動し直します。

「windows-vm の実行に失敗しました」と通知されたら、端末から `windows-vm connect` を実行して出力を確かめます。
