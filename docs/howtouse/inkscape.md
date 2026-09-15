# Inkscape

新規文書の既定の色（ページ `#e8c1a1`、デスク `#30120c`）をリポジトリで管理している。
設計判断は [architecture/inkscape.md](../architecture/inkscape.md) を参照。

## 何が決まるか

`~/.config/inkscape/templates/default.svg` が
[modules/home-manager/gui/inkscape/default.svg](../../modules/home-manager/gui/inkscape/default.svg)
への symlink になる。Inkscape は新規文書をこのテンプレートから作るので、ページ（紙）とデスク
（紙の外側）の色がここで決まる。

- **既存のファイルには効かない。** ページとデスクの色は文書ごとに保存される。既存ファイルの
  色は「ファイル → ドキュメントのプロパティ」で変える
- **書き出しには影響しない。** PNG 書き出しの背景は、ページの色とは別に既定で透明

## 色を変える

どちらの方法でも、リポジトリのファイルが書き換わる。symlink なので switch は要らず、次に
新規文書を開いたときから反映される。

**ファイルを直接編集する。** `default.svg` の `pagecolor` と `inkscape:deskcolor` を書き換える。

**GUI から保存する。**

1. 新規文書を開き、「ファイル → ドキュメントのプロパティ」で色を変える。何も描かない
2. 「ファイル → テンプレートを保存...」で「デフォルトテンプレートとして設定」にチェックを入れて保存する
3. `git diff` を見て、色以外の変更（`inkscape:zoom` やウィンドウ寸法、`inkscape:templateinfo`）を戻してからコミットする

GUI から保存すると、開いている文書の中身と表示状態も一緒に書き込まれる。手順 1 で何も描かず、
手順 3 で差分を確かめるのはそのため。

## 戻す

live symlink なので、home-manager の世代を戻しても中身は戻らない。`git checkout` か
`git revert` で戻す。
