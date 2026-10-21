# デスクトップの Windows VM（使い方）

設計判断: [architecture/windows-vm.md](../architecture/windows-vm.md)

実装: [modules/home-manager/windows-vm.nix](../../modules/home-manager/windows-vm.nix)、[modules/home-manager/windows-vm.sh](../../modules/home-manager/windows-vm.sh)

nixos-desktop の libvirt VM は、使うときだけ起動し、画面をホストの FreeRDP で表示します。
VM の名前は、[hosts/nixos-desktop/default.nix](../../hosts/nixos-desktop/default.nix) の `local.vm.windowsDomain` で指定しています。`local.vm.enable` が libvirt・OVMF・virt-manager・default ネットワークの自動起動を有効にし、`local.vm.users`（既定は primaryUser）に `libvirtd` グループを付けます。`windowsDomain` を指定すると、そのうち Home Manager を持つユーザーにランチャーを導入します。null ならランチャーを導入しません。起動を待つ上限は既定の 600 秒です。

## 使う

GNOME のアプリ一覧から「Windows」を開きます。
VM が止まっていれば起動し、RDP が応答するまで待ってから接続します。待っている間は「Windows を起動しています」と通知されます。
1 分ほどたっても接続できないときは、「Windows の起動に時間がかかっています」と一度だけ通知されます。Windows Update を適用する起動は数分かかります。
キーリングにユーザー名とパスワードを置いていれば、自動でサインインします（次の節）。
置いていなければ、Windows のサインイン画面でパスワードを入力してサインインします。ユーザーを選ぶ画面では「他のユーザー」を選び、メールアドレスの形のユーザー名（UPN）を入力します。

ウィンドウの大きさを変えると、Windows の解像度もそれに合わせて変わります。
ホストと Windows のあいだでは、テキストのコピー＆ペーストができます。

端末から `windows-vm connect` を実行しても同じ動作になり（`connect` は省略できます）、こちらでは FreeRDP の出力を確認できます。

## パスワードを打たずにサインインする

RDP のサインインでは PIN を使えません（[設計判断](../architecture/windows-vm.md#パスワードを-gnome-キーリングから渡してサインインする)）。
代わりに、Windows のユーザー名とパスワードを GNOME のキーリングに置くと、ランチャーが FreeRDP に渡して自動でサインインします。
`vm` の値は `local.windowsVm.domain`（このデスクトップでは `win11`）です。

```sh
# ユーザー名。.\AzureAD\ に続けてメールアドレスの形のユーザー名（UPN）を書く
printf '%s' '.\AzureAD\<UPN>' | nix shell nixpkgs#libsecret -c secret-tool store --label='Windows VM のユーザー名' service windows-vm vm win11 field user

# パスワード。入力を求められるので打つ（画面には出ない）
nix shell nixpkgs#libsecret -c secret-tool store --label='Windows VM のパスワード' service windows-vm vm win11 field password
```

Windows のパスワードを変えたら、パスワードのほうをもう一度実行して上書きします。
やめるときは `nix shell nixpkgs#libsecret -c secret-tool clear service windows-vm vm win11` で両方を消します。どちらかが欠けていると、ランチャーは何も渡さず、サインイン画面が出ます。

ユーザー名は先頭の `.\` まで含めて書きます。`AzureAD\<UPN>` や `<UPN>` だけでは、パスワードが正しくても Windows に拒否されます（[設計判断](../architecture/windows-vm.md#パスワードを-gnome-キーリングから渡してサインインする)）。

## Super や Alt+Tab を Windows に渡す

FreeRDP のウィンドウにフォーカスがあれば、文字の入力とマウスは Windows に届きます。
ただし GNOME に割り当てたキー（Super を含むもの、Alt+Tab、Alt+F4、Alt+F2 など）は、普段は GNOME の操作になります。Alt+F4 を押すと、FreeRDP のウィンドウが閉じます。
これらのキーを Windows で使うときは、先に右 Alt を単独で押してから、そのキーを押します。右 Alt のあとに押したキーをすべて離すまでは、キーボードが Windows に渡ります。
Windows の Alt+Tab は、右 Alt を押して離してから、左 Alt を押したまま Tab を押します。Alt を離すまでは、Tab を何回押しても Windows のウィンドウが切り替わります。
右 Alt を押したあと、ほかのキーを押さずにもう一度右 Alt を押すと、取り消せます。

右 Alt そのものは Windows に届きません。Windows で Alt を使うときは左 Alt を使います。Windows では AltGr の文字を打てません。
右 Alt での操作は、ホストのキー配列で右 Alt が AltGr になっていることを前提にしています。既定の配列は English (intl., with AltGr dead keys) です。GNOME の設定で右 Alt が AltGr にならない配列に変えると、右 Alt を押しても何も起きなくなります。
FreeRDP のほかのホットキーも右 Alt との組み合わせになります（全画面は右 Alt + Enter）。押すと、次に押したキーを離すまでキーボードが Windows に渡ります。
ゲーム用のターボ（◇ + 右 Alt で入り切りする、右 Alt での右クリックの連打）を入れている間は、右 Alt が連打に使われるので、キーを Windows に渡せません。◇ + 右 Alt でターボを切ってから使います。
この動作は、ランチャーが起動する FreeRDP にパッチを当てて作っています（[設計判断](../architecture/windows-vm.md#キーボードを掴むのは右-alt-の直後だけにする)）。設定の `~/.config/freerdp/sdl-freerdp.json` はこのユーザーが起動するすべての `sdl-freerdp` に適用されますが、パッチのない `sdl-freerdp` では、右 Alt はキーボードを Windows に渡すか GNOME に残すかの切り替えになります。

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
VM の名前が変わったときは、ホストの `local.vm.windowsDomain` を合わせます。

## うまくいかないとき

「Windows に接続できません」と通知されたら、待つ上限（既定は 600 秒）のうちに RDP が応答しませんでした。
起動が長引いているときは、右クリックの「SPICE で開く」で画面を確かめ、起動し終わってからもう一度開きます。毎回足りないなら `local.windowsVm.bootTimeoutSeconds` を延ばします。
Windows のリモートデスクトップが無効になっている場合も、同じ通知になります。

「Windows は起動待機中または接続中です」と通知されたら、別に開いた「Windows」が起動を待っているか、接続しています。

「Windows が停止しました」と通知されたら、起動を待つ間に VM が止まりました。もう一度「Windows」を開くと起動し直します。

「windows-vm の実行に失敗しました」と通知されたら、端末から `windows-vm connect` を実行して出力を確かめます。

自動サインインで「ユーザー名またはパスワードが正しくありません」と表示されたら、キーリングの項目を確かめます。
ユーザー名が `.\AzureAD\<UPN>` の形になっているかと、パスワードが合っているかを見ます。
次のコマンドでパスワードを打つと、キーリングのものと一致するかどうかだけが表示されます。

```sh
nix shell nixpkgs#libsecret -c bash -c 'read -rsp "Password: " p; echo; [ "$p" = "$(secret-tool lookup service windows-vm vm win11 field password)" ] && echo 一致 || echo 不一致'
```
