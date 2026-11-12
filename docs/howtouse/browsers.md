# ブラウザ（Firefox と Zen）

既定ブラウザとリンクの振り分け: [デフォルトアプリ](../architecture/default-apps.md)
実装: [browser_common.star](../../config/elements/browser_common.star) / [firefox.star](../../config/elements/firefox.star) / [zen_browser.star](../../config/elements/zen_browser.star)

Firefox と Zen は、目的 `web_browsing` を選んだホストに両方入ります。拡張機能の一覧と pref は Nix で宣言し、履歴などの使いながら増えるデータは同期サービスに任せます（分担は「設計」の節）。

## 拡張機能を足す・外す

両方に入れる拡張機能は [browser_common.star](../../config/elements/browser_common.star) の `extensions` に、Firefox だけに入れるものは [firefox.star](../../config/elements/firefox.star) で共通の一覧に足す辞書に、`"拡張機能の ID": "AMO のスラッグ"` の形で書きます。Zen だけに入れる拡張機能を足すときは、[zen_browser.star](../../config/elements/zen_browser.star) でも firefox.star と同じように共通の一覧を写してから足します。スラッグは addons.mozilla.org のページの URL（`/firefox/addon/<スラッグ>/`）の末尾です。ID は、一度手で入れてから `about:support` の「アドオン」の表で確認します。

switch してからブラウザを再起動すると、足した拡張機能が入ります。一覧から外しても、入っている拡張機能は削除されません。各ブラウザのアドオンマネージャー（`about:addons`）で手で削除します。

## pref を変える

両方に適用する pref は `browser_common.star` の `settings` に、片方だけのものは各ブラウザの要素で共通の pref に足す辞書に書きます。宣言した pref はプロファイルの `user.js` に書き出され、ブラウザは起動のたびにその値を読み直します。`about:config` や設定画面で変えても、再起動すると宣言した値に戻ります。試すときは `about:config` で変え、残すと決めたら宣言に移します。

## 新しいマシンやプロファイルで元に戻す

switch したあと、Firefox と Zen のそれぞれで次を行います。

1. 設定の Sync の画面で Mozilla アカウントにログインします。履歴、拡張機能の設定、Zen のワークスペースとピン留めタブが戻り、他の端末で開いているタブを一覧から開けるようになります。
2. Bitwarden の拡張機能にログインします。
3. Bitwarden のセキュアメモに保存した floccus のプロファイルを、ファイルに書き出して floccus の「Import/Export Profiles」からインポートします。同期するブックマークのフォルダを選び直してから同期し、書き出したファイルは削除します。このファイルには Git の認証情報が含まれうるので、repo に置きません。

floccus のプロファイルを保存し直すときは、floccus の「Export profiles」で書き出した中身を、同じセキュアメモに貼り替えます。

OneTab のリストはどこにも同期されません。移すときは OneTab のエクスポートとインポートを使います。

Zen のプロファイルは Home Manager が管理する `~/.config/zen/default` です。

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

ブックマークを Firefox Sync ではなく floccus で同期するのは、Chrome 系のブラウザに移る可能性を残すためです（利用者の選択）。Chrome 系を使わないと決まったら、Firefox Sync に移すと拡張機能が一つ減ります。

各サービスへのログインは宣言できません。Firefox 159 のポリシーにはアカウントへのログインを設定する項目がなく、floccus はポリシーの値（`storage.managed`）を読みません。

### Zen の起動と言語

ポリシー（拡張機能の一覧など）は、Home Manager モジュールが組み立てる Zen のパッケージにだけ入ります。flake の入力のパッケージを直接起動すると、ポリシーのない Zen が立ち上がります。そのため [zen_browser.star](../../config/elements/zen_browser.star) が公開する起動コマンドは、ストアのパスではなく PATH 上の名前です。

Zen は多言語でビルドされているので、画面の言語は `intl.locale.requested` だけで変わります。Firefox は日本語の言語パックを拡張機能として入れます。

### Tree Style Tab を Firefox だけに入れる理由

Zen にはタブの親子関係を作る機能がなく、Zen の左側のバー（タブ一覧、アドレスバー、Essentials）は隠せないので、Tree Style Tab を入れるとタブの一覧が二つ並びます。Zen では、Glance（Alt を押しながらリンクをクリック）、フォルダ、Clear ボタンでタブを整理します。
