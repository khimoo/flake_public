# Inkscape の既定テンプレート

設定ファイル: [modules/home-manager/gui/inkscape.nix](../../modules/home-manager/gui/inkscape.nix)
使い方: [howtouse/inkscape.md](../howtouse/inkscape.md)

## 何を管理するか

新規文書の既定テンプレート 1 ファイルだけ。ページの白さとデスクの明るさで目が疲れるため、
両方の色を宣言的に固定する。`preferences.xml` は Inkscape が起動中に書き換え続けるので
管理しない。

根拠はいずれも Inkscape 1.4.2 のソース（GitLab タグ `INKSCAPE_1_4_2`）。

- 新規文書は `default.svg` をテンプレートとして探し、ユーザーのディレクトリがシステムの
  言語別テンプレート（`default.ja.svg`）より優先される（`src/io/resource.cpp` の探索順）
- ページの色は `sodipodi:namedview` の `pagecolor`、デスクの色は `inkscape:deskcolor`
  （`src/attributes.cpp`）。デスクの既定は `#d1d1d1`（`src/object/sp-namedview.cpp`）
- ページはテクスチャ画像を持てず、単色か市松模様だけを描く（`src/page-manager.cpp`）
- 書き出しの背景色は既定で透明で、ページの色を参照しない（`src/ui/dialog/export-single.cpp`）

## store へのリンクではなく live symlink にした理由

`xdg.configFile.<name>.text` で store に置くと、GUI の「テンプレートを保存...」→
「デフォルトテンプレートとして設定」が読み取り専用のファイルへの書き込みで失敗する。

Inkscape の SVG 保存は `fopen(filename, "w")` でパスを直接開いて書き込み、一時ファイルから
置き換える処理を持たない（`src/xml/repr-io.cpp`、`src/extension/internal/svg.cpp`）。
`fopen` は symlink を辿るので、`mkOutOfStoreSymlink` でリポジトリを指せば GUI からの保存が
リンクを壊さずにリポジトリ側へ書き込まれる。kitty・wezterm と同じ形にした。

**この書き込み経路は実機では確かめていない。** コードからの判断である。

## 代償

- GUI から保存すると、開いている文書の中身、表示倍率・ウィンドウ寸法
  （`sp_namedview_document_from_window`）、`inkscape:templateinfo` が一緒に書き込まれる。
  コミット前に差分を確かめる運用で吸収する
- live symlink の中身は home-manager の世代のロールバックでは戻らない。Git で戻す

## 見直す条件

- Inkscape の保存処理が一時ファイルからの置き換えに変わった場合、GUI からの保存で
  symlink が通常ファイルに置き換わる。その時点で live symlink にする理由は無くなる
