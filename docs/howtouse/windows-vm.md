# デスクトップの Windows VM

nixos-desktop 上の libvirt VM は、必要なときだけ起動し、画面はホスト側の FreeRDP で表示します。
VM 名は [hosts/nixos-desktop/default.nix](../../hosts/nixos-desktop/default.nix) の `local.vm.windowsDomain` で指定されており、`local.vm.users`（デフォルトは primaryUser）のうち Home Manager を利用しているユーザーにランチャーが追加されます。

設計: [デスクトップの Windows VM の設計](../architecture/windows-vm.md)

## 使い方

GNOME のアプリケーション一覧から「Windows」を起動します。
VM が停止している場合は自動で起動し、RDP の応答を待ってから接続します。待機中は「Windows を起動しています」と通知が表示されます。
1 分ほど経過しても接続できない場合は、「Windows の起動に時間がかかっています」と一度だけ通知されます。なお、Windows Update を適用する起動には数分かかることがあります。
キーリングにユーザー名とパスワードを登録していれば、自動でサインインします（詳細は次の節を参照）。
未登録の場合は、Windows のサインイン画面でパスワードを入力してください。アカウント選択画面では「他のユーザー」を選び、メールアドレス形式のユーザー名（UPN）を入力します。

ウィンドウサイズを変更すると、Windows 側の解像度もそれに合わせて自動的に調整されます。
ホストと Windows の間では、テキストのコピー＆ペーストが共有されます。

端末から `windows-vm connect`（`connect` は省略可）を実行しても同様に動作し、こちらでは FreeRDP のログ出力を確認できます。

## パスワードを入力せずにサインインする

RDP サインインでは PIN を利用できません（[設計判断](../architecture/windows-vm.md#パスワードを-gnome-キーリングから渡してサインインする)）。
代わりに、Windows のユーザー名とパスワードを GNOME キーリングに保存しておくことで、ランチャー経由で FreeRDP に渡され自動サインインが可能になります。
`vm` の値には `local.windowsVm.domain`（このデスクトップ環境では `win11`）を指定します。

```sh
# ユーザー名。.\AzureAD\ に続けてメールアドレス形式のユーザー名（UPN）を入力
printf '%s' '.\AzureAD\<UPN>' | nix shell nixpkgs#libsecret -c secret-tool store --label='Windows VM のユーザー名' service windows-vm vm win11 field user

# パスワード。入力を促されるので入力（画面には表示されません）
nix shell nixpkgs#libsecret -c secret-tool store --label='Windows VM のパスワード' service windows-vm vm win11 field password
```

Windows のパスワードを変更した場合は、パスワード保存コマンドを再実行して上書きしてください。
自動サインインを解除したい場合は、`nix shell nixpkgs#libsecret -c secret-tool clear service windows-vm vm win11` を実行して両方を削除します。どちらか一方でも未登録の場合、ランチャーは資格情報を渡さず、通常のサインイン画面が表示されます。

ユーザー名は先頭の `.\` まで含めて登録する必要があります。`AzureAD\<UPN>` や `<UPN>` 単体では、パスワードが合っていても Windows 側に拒否されます（[設計判断](../architecture/windows-vm.md#パスワードを-gnome-キーリングから渡してサインインする)）。

## Super キーや Alt+Tab を Windows に送る

FreeRDP のウィンドウにフォーカスがある間は、文字入力やマウス操作は Windows 側に送信されます。
ただし、GNOME に割り当てられているキー操作（Super キーを含むショートカット、Alt+Tab、Alt+F4、Alt+F2 など）は、通常は GNOME 側で処理されます（例えば Alt+F4 を押すと FreeRDP 自体が終了します）。
これらのキーを Windows 側へ送りたい場合は、あらかじめ「右 Alt」を単独で押してから、目的のキーを押します。右 Alt を押した後に押したキーをすべて離すまでの間、キーボード入力が Windows 側へ渡されます。
Windows の Alt+Tab を実行したい場合は、右 Alt を押して離したあと、左 Alt を押したまま Tab を押してください。左 Alt を離すまでは、Tab を複数回押しても Windows 内でウィンドウが切り替わります。
右 Alt を押したあと、他のキーを押さずにもう一度右 Alt を押せば、キー入力の転送状態を取り消せます。

なお、右 Alt 自体は Windows 側に送信されません。Windows 内で Alt を使いたい場合は左 Alt を使用してください。また、Windows 内では AltGr による文字入力は行えません。
右 Alt によるこの操作は、ホスト側のキー配列で右 Alt が AltGr として機能していることを前提としています（既定の配列は「English (intl., with AltGr dead keys)」）。GNOME の設定で右 Alt が AltGr にならない配列に変更すると、右 Alt を押しても何も機能しなくなります。
FreeRDP のその他のホットキーも右 Alt との組み合わせになります（例: 全画面表示は 右 Alt + Enter）。これを押すと、次に押したキーを離すまでキーボード入力が Windows 側へ渡されます。
ゲーム用の連打機能（◇ + 右 Alt でオン/オフを切り替える、右 Alt による右クリック連打）を有効にしている間は、右 Alt が連打処理に使われるため、キーを Windows に渡すことができません。◇ + 右 Alt で連打機能をオフにしてから操作してください。
この動作は、ランチャーが起動する FreeRDP にパッチを適用して実装しています（[設計判断](../architecture/windows-vm.md#キーボードを掴むのは右-alt-の直後だけにする)）。設定ファイル `~/.config/freerdp/sdl-freerdp.json` はそのユーザーが実行するすべての `sdl-freerdp` に適用されますが、パッチが適用されていない通常の `sdl-freerdp` では、右 Alt はキーボード入力を Windows と GNOME のどちらで捕捉するかの切り替えスイッチとして機能します。

## 終了する

Windows のスタートメニューからシャットダウンを行います。
Windows がシャットダウンされると VM も自動で停止し、FreeRDP のウィンドウも閉じます。

FreeRDP のウィンドウだけを閉じた場合、Windows のセッションは切断された状態で稼働し続けます。ウィンドウを閉じてから 1 分ほど経っても Windows が動作している場合は、「Windows はまだ起動しています」という通知が表示されます（スタートメニューからシャットダウンした場合でも完全に停止するまで数十秒かかるため、その間は通知を待ちます）。
通知内の「シャットダウン」をクリックすると VM を停止できます。何もしなければ VM は稼働したままとなるため、再度「Windows」を起動すれば元のセッションに復帰できます。
後から停止させたい場合は、アプリケーション一覧の「Windows」を右クリックして「シャットダウン」を選択してください。

通知内のボタンは、クリックした時点で別の接続が開かれている場合には VM を停止せず、「Windows を停止しませんでした」と通知します。これは、過去の通知ボタンを誤ってクリックしたことで使用中の Windows を停止させてしまうのを防ぐためです。

なお、このシャットダウン処理は内部的に `virsh shutdown` を実行しており、VM の電源ボタンを押した際と同じ ACPI 信号を Windows に送信しているだけです。そのため、未保存の作業などがあると Windows が終了しない場合があります。
正常に停止しない場合は、右クリックメニューの「SPICE で開く」から Windows の画面状態を確認してください。

Windows を動かしたままホストをシャットダウンまたは再起動すると、ホストが Windows に同じ ACPI 信号を送り、Windows が終了するのを最大 300 秒待ちます。Windows の状態は保存されないため、未保存の作業はホストを止める前に保存してください。
ホストの起動後に Windows は自動では起動しないので、使うときに「Windows」を開きます。

## USB 機器を Windows に接続する

USB リダイレクトは SPICE の機能を利用します。
アプリケーション一覧の「Windows」を右クリックして「SPICE で開く」を選択し、virt-manager の画面から対象の USB 機器を接続してください。
RDP 接続中に virt-manager 経由で USB を渡せるかどうかは未検証ですが、virt-manager 側はロック画面になり、USB 自体は正常に渡せると見込んでいます。

## 会社 PC とのクリップボード共有について

VM 内の MotionPro から会社の PC へ RDP 接続している場合、クリップボードの共有は機能しません。
会社 PC 側ではクリップボードを受け付ける設定になっていますが、MotionPro が mstsc に渡す接続設定またはゲートウェイ側で制限されています。
会社の管理ポリシーによる設定であるため、手元での回避対応は行いません。

## VM を再作成した場合の設定

Windows 側で以下の 2 点を設定します。

1. 「設定」→「システム」→「リモート デスクトップ」を有効にする。
2. 同画面の有効化スイッチ横を展開し、「ネットワーク レベル認証（NLA）」を必須とするチェックを外す。

NLA を無効化する理由については、[設計判断](../architecture/windows-vm.md#nla-を切る) を参照してください。
libvirt 上の VM 名（`virsh list` で表示される名前）が変更された場合は、ホスト側の `local.vm.windowsDomain` の設定も合わせて修正してください。

## トラブルシューティング

「Windows に接続できません」と通知された場合、タイムアウト時間（既定は 600 秒）内に RDP の応答がありませんでした。
起動に時間がかかっている場合は、右クリックメニューの「SPICE で開く」で画面の進捗を確認し、起動が完了してから再度接続してください。毎回タイムアウトする場合は、`local.windowsVm.bootTimeoutSeconds` の値を延ばします。
Windows 側のリモートデスクトップ機能が無効になっている場合も、同様の通知が表示されます。

「Windows は起動待機中または接続中です」と通知された場合は、別で開いた「Windows」がすでに起動待機中か接続中であることを示しています。

「Windows が停止しました」と通知された場合は、接続待機中に VM が停止してしまったことを示します。再度「Windows」を開くと再起動します。

「windows-vm の実行に失敗しました」と通知された場合は、端末から `windows-vm connect` を実行してエラー出力を確認してください。

自動サインイン時に「ユーザー名またはパスワードが正しくありません」と表示された場合は、キーリングの登録内容を確認してください。
ユーザー名が `.\AzureAD\<UPN>` の形式になっているか、パスワードに誤りがないかを確認します。
以下のコマンドを実行してパスワードを入力すると、キーリングの内容と一致しているかどうかを確認できます。

```sh
nix shell nixpkgs#libsecret -c bash -c 'read -rsp "Password: " p; echo; [ "$p" = "$(secret-tool lookup service windows-vm vm win11 field password)" ] && echo 一致 || echo 不一致'
```
