# Telekasten (ノート管理)

Zettelkasten 方式のノート管理。Telescope をバックエンドに使う。

- 設定ファイル: `lua/plugins/telescope.lua` 内
- ノート置き場: `~/sagyo/vaults/`

## 概要

`cmd = {"Telekasten"}` で遅延読み込み。`:Telekasten` コマンドで起動。

## Vault 構成

`~/sagyo/vaults/` 配下のディレクトリを自動検出 + 手動定義の Vault:

- `math_with_typ` — デフォルト Vault。Typst で数学ノート
- `LiteratureNotes` — 文献ノート
- `PermanentNotes` — 恒久ノート
- `StructureNotes` — 構造ノート
- `Templates/` — テンプレート置き場
- `Dailies/` — デイリーノート

## 主なコマンド

`:Telekasten` で以下のサブコマンドを選択:

| コマンド | 機能 |
|----------|------|
| `find_notes` | ノートをファジー検索 |
| `search_notes` | ノートの中身を grep 検索 |
| `new_note` | 新規ノート作成 (テンプレート適用) |
| `follow_link` | カーソル下のリンク先に移動 |
| `insert_link` | リンクを挿入 |
| `switch_vault` | Vault を切り替え |
| `goto_today` | 今日のデイリーノートを開く |

## 設定のポイント

- テンプレート: `template_new_note.typ` (Typst 形式)、`TemplateDailyNote.md`
- メディアプレビュー: telescope-media-files を使用
- `autotheorem.typ` のシンボリックリンクを math_with_typ の全サブディレクトリに自動作成
