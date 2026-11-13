# ブラウザ（Firefox、Zen、Brave、Chrome）

既定ブラウザとリンクの振り分け: [デフォルトアプリ](../architecture/default-apps.md)
実装: [browser_common.star](../../config/elements/browser_common.star) / [firefox.star](../../config/elements/firefox.star) / [zen_browser.star](../../config/elements/zen_browser.star) / [brave.star](../../config/elements/brave.star) / [google_chrome.star](../../config/elements/google_chrome.star)

`requires` に `web_browsing` を挙げる行動（`programming`、`grow_notes`、`web_procedures`、`write_documents`、`work_ss`、`work_fr`）を選んだ利用者には、`web_browsing` を通じて、Firefox、Zen、Brave、Google Chrome が入ります。Firefox と Zen は拡張機能の一覧と pref を Nix で宣言し、履歴などの使いながら増えるデータは同期サービスに任せます（分担は「設計」の節）。Brave には Bitwarden と floccus だけを宣言で入れ（「Brave」の節）、Chrome はパッケージを入れるだけです（「Google Chrome」の節）。無効にするには、`web_browsing` を `requires` に挙げる行動をすべて、利用者の `purposes` から外します。

## 拡張機能を足す・外す

両方に入れる拡張機能は [browser_common.star](../../config/elements/browser_common.star) の `extensions` に、Firefox だけに入れるものは [firefox.star](../../config/elements/firefox.star) で共通の一覧に足す辞書に、`"拡張機能の ID": "AMO のスラッグ"` の形で書きます。Zen だけに入れる拡張機能を足すときは、[zen_browser.star](../../config/elements/zen_browser.star) でも firefox.star と同じように共通の一覧を写してから足します。スラッグは addons.mozilla.org のページの URL（`/firefox/addon/<スラッグ>/`）の末尾です。ID は、一度手で入れてから `about:support` の「アドオン」の表で確認します。

switch してからブラウザを再起動すると、足した拡張機能が入ります。一覧から外しても、入っている拡張機能は削除されません。各ブラウザのアドオンマネージャー（`about:addons`）で手で削除します。

## pref を変える

両方に適用する pref は `browser_common.star` の `settings` に、片方だけのものは各ブラウザの要素で共通の pref に足す辞書に書きます。宣言した pref はプロファイルの `user.js` に書き出され、ブラウザは起動のたびにその値を読み直します。`about:config` や設定画面で変えても、再起動すると宣言した値に戻ります。試すときは `about:config` で変え、残すと決めたら宣言に移します。

## 新しいマシンやプロファイルで元に戻す

switch したあと、Firefox と Zen のそれぞれで次を行います。

1. 設定の Sync の画面で Mozilla アカウントにログインします。履歴、拡張機能の設定、Zen のワークスペースとピン留めタブが戻り、他の端末で開いているタブを一覧から開けるようになります。
2. Bitwarden の拡張機能にログインします。
3. Bitwarden のセキュアメモに保存した floccus のプロファイルを、ファイルに書き出して floccus の「プロファイルのインポート/エクスポート」からインポートし、書き出したファイルは削除します。このファイルには Git の認証情報が含まれうるので、repo に置きません。同期フォルダ（ルートフォルダー）は記録されたまま見つかるので、選び直しは要りません。
4. floccus の最初の同期は「一度だけプルダウン」で行います。新しいプロファイルに最初からあるブックマーク（ブックマークメニューの「Mozilla Firefox」フォルダなど）が Git に送られて重複するのを防ぎます。

floccus のプロファイルを保存し直すときは、「プロファイルをエクスポート」で書き出した中身を、同じセキュアメモに貼り替えます。floccus の設定を変えたときは、毎回保存し直します。

OneTab のリストはどこにも同期されません。移すときは OneTab のエクスポートとインポートを使います。

Zen のプロファイルは Home Manager が管理する `~/.config/zen/default` です。

## ブックマークを floccus で同期するときの決まり

- floccus の同期フォルダ（ブックマークフォルダー）は、どのブラウザでもルートフォルダー（一番上の名前のないフォルダ）にします。別のフォルダを同期フォルダにしたプロファイルと、同じ Git のリポジトリを共有しません。
- ブックマークは、ブラウザに最初からあるフォルダ（ブックマークツールバー、その他のブックマーク、ブックマークメニュー、モバイルのブックマーク）の中に置きます。Git の `bookmarks.xbel` を手で直すときも、最上位にはこの 4 つに対応するフォルダ以外を足しません。
- Chrome 系のブラウザでも使いたいブックマークは、ツールバーかその他のブックマークに置きます。Chrome にはブックマークメニューがありません。
- 同期フォルダの設定は変えません。変える必要があるときは、すべてのブラウザで floccus の同期を止め、Git の最新のコミットを控えてから変えます。
- Firefox Sync のブックマークの同期はオンにしません（pref で切ってあります）。
- 消えたブックマークは Git の履歴から戻します。Firefox のライブラリの「復元」はブックマーク全体を置き換え、floccus がその差分を Git に同期するので使いません。

## Brave

拡張機能は [brave.star](../../config/elements/brave.star) の `programs.brave.extensions` に、Chrome ウェブストアの拡張機能の ID（ストアのページの URL の末尾）で書きます。Home Manager が ID ごとに `~/.config/BraveSoftware/Brave-Browser/External Extensions/<ID>.json` を置き、Brave が起動時に入れます。Firefox と Zen のポリシーと違って強制ではなく、Brave の拡張機能の画面で削除すると、その拡張機能は起動時に入れ直されなくなります。入れ直すときは、Chrome ウェブストアから手で入れます。

Bitwarden へのログインと floccus のプロファイルのインポートは、Firefox や Zen と同じく手で行い、floccus の決まりにも同じく従います。Brave 自身のブックマーク同期は使いません。

floccus のプロファイルをインポートしたあと、同期フォルダ（ブックマークフォルダー）にルートフォルダーを選び直します。ブックマークの ID の体系が Firefox 系と Chrome 系で違うので、Firefox や Zen で書き出したプロファイルの同期フォルダは Brave では見つかりません。選び直さずに同期すると E038（ローカルのフォルダが見つからない）で止まります。

Brave にブックマークが少ない状態で最初に同期すると、Git から一度に大量のブックマークが追加されることになり、floccus のフェイルセーフ（一度に 20% を超える追加や削除を止める）が E049 で同期を止めます。最初の同期はフェイルセーフを一時的に無効にして「一度だけプルダウン」で行い、終わったら有効に戻します。

## Google Chrome

[google_chrome.star](../../config/elements/google_chrome.star) でパッケージを入れるだけで、拡張機能は宣言しません。Home Manager の Chromium 系のモジュールは、Linux の Google Chrome（プロプライエタリ版）に拡張機能を宣言すると評価を止めます。Chrome で拡張機能を使うときは、Chrome ウェブストアから手で入れます。

## 設計

### データの管理先

| データ | 管理先 |
|---|---|
| 拡張機能の一覧、pref | Nix |
| 履歴、開いているタブ、拡張機能の設定、Zen のワークスペースとピン留めタブ | Firefox Sync |
| ブックマーク | floccus（Git） |
| パスワード、住所、クレジットカード | Bitwarden |

自分で決めて再現したいものを Nix に、使いながらブラウザが書き足すものを同期サービスに置きます。Sync の同期項目の選択はアカウント全体に適用されるので、Firefox と Zen は同じ項目を同期します。

Sync の「アドオン」と「設定」の同期は切っています。Nix で宣言した pref は起動のたびに `user.js` の値に戻るので、Sync で同じ項目を同期すると値が食い違います。拡張機能の設定（拡張機能が `storage.sync` に保存したもの）の同期は、既定では「アドオン」の同期と連動して止まります（Firefox 159 の `extension-storage.sys.mjs`）。`services.sync.engine.extension-storage.force` で、設定の同期だけを続けています。この pref には設定画面がなく、Firefox のソースには、アドオンと拡張機能の設定の同期状態が食い違うと挙動が崩れうるという注記があります。拡張機能の設定の同期が止まったり重複したりしたら、この pref を疑います。

Zen のワークスペースとピン留めタブは、zen-browser-flake の Home Manager モジュール（a7cac935）でも宣言できます。ただしモジュールは switch のときに `zen-sessions.jsonlz4` へ書き込むので、Zen の起動中は書き込みを飛ばし、宣言した項目を UI で変えた分は次の switch で戻します。構成が定まっていない間は Sync（Zen 1.24.1b の Workspaces の同期は、ワークスペース、フォルダ、ピン留めタブ、Essentials を運ぶ）で管理します。構成が固まったら、Sync の Workspaces を切り、今の UUID のまま Nix に移せます。

ブックマークを Firefox Sync ではなく floccus で同期するのは、Chrome 系のブラウザに移る可能性を残すためです（利用者の選択）。Chrome 系を使わないと決まったら、Firefox Sync に移すと拡張機能が一つ減ります。floccus の公式ガイドも、ブラウザ自身のブックマーク同期と併用しないよう求めています。

### floccus をルートで同期する理由

floccus は、ブックマーク全体を同期するときはルートを同期フォルダに選ぶ使い方を案内しており、ブラウザに最初からあるフォルダの名前をそろえて、別の種類のブラウザ間でも対応させます（[Chrome ウェブストアの説明](https://chrome.google.com/webstore/detail/floccus-bookmarks-sync/fnaicdffflnofjppbagibeoednhnbjhg)）。floccus 5.13.0 のコードでは、Firefox のツールバーを「Bookmarks Bar」、その他のブックマークを「Other Bookmarks」、ブックマークメニューを「Bookmarks Menu」、モバイルのブックマークを「Mobile Bookmarks」と読み替えます。ルートの ID はどのプロファイルでも同じなので、インポートしたプロファイルが同期フォルダをそのまま見つけます。自分で作ったフォルダは ID がプロファイルごとに変わるので、作り直しと選び直しが要ります。

ルートの直下には、最初からあるフォルダしか置けません。Firefox 159 のブックマークの処理（`Bookmarks.sys.mjs`）は、テストの自動実行を除いてルートの直下への追加と移動を拒み、floccus の [FAQ](https://floccus.org/faq) も、ルートに項目を作ろうとすると失敗すると説明しています。Git の最上位に、読み替えた名前と一致しないフォルダやブックマークがあると、ルートで同期したブラウザにはそれを置く場所がありません。別のフォルダに同期していたデータをルートでの同期に切り替えたときには、最上位のブックマークと、Chrome が付けた名前の「Mobile bookmarks」（小文字の b）が Firefox と Zen から見えなくなりました。floccus はこれらを削除せずに Git に残しますが、ルートで同期するブラウザでは開けません。決まりの最初の 2 つは、これを防ぐためのものです。

Chrome 系と Firefox をルートで同期したら Firefox 側でフォルダが重複したという報告があります（[floccus #1523](https://github.com/floccusaddon/floccus/discussions/1523)）。Chrome 系でも同期し始めたら、重複が起きないか確かめます。

各サービスへのログインは宣言できません。Firefox 159 のポリシーにはアカウントへのログインを設定する項目がなく、floccus はポリシーの値（`storage.managed`）を読みません。

### Zen の起動と言語

ポリシー（拡張機能の一覧など）は、Home Manager モジュールが組み立てる Zen のパッケージにだけ入ります。flake の入力のパッケージを直接起動すると、ポリシーのない Zen が立ち上がります。そのため [zen_browser.star](../../config/elements/zen_browser.star) が公開する起動コマンドは、ストアのパスではなく PATH 上の名前です。

Zen は多言語でビルドされているので、画面の言語は `intl.locale.requested` だけで変わります。Firefox は日本語の言語パックを拡張機能として入れ、日本語で表示します。

Zen は英語で表示します（利用者の選択）。Zen 1.24.1b の Zen 独自の文言は、日本語版で変数を含まない 423 件のうち 213 件が英語のままで、「Add Route for Domain」を「ルートのドメインを足す」とするような誤訳もあります。英語なら、機能名が公式の文書やネットの情報と一致します。Firefox から来たメニューの日本語訳は Mozilla の公式のもので問題がないので、翻訳が改善されたら日本語に戻す余地があります。

### Tree Style Tab を Firefox だけに入れる理由

Zen にはタブの親子関係を作る機能がなく、Zen の左側のバー（タブ一覧、アドレスバー、Essentials）は隠せないので、Tree Style Tab を入れるとタブの一覧が二つ並びます。Zen では、Glance（Alt を押しながらリンクをクリック）、フォルダ、Clear ボタンでタブを整理します。
