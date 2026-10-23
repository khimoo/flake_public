# ファイル間の移動（harpoon2）

作業中に行き来の多いファイルを Harpoon のリストに登録し、ショートカットキーで素早く切り替えます。

設定ファイル: `lua/plugins/harpoon.lua`

| キー | 機能 |
|------|------|
| `<leader>ha` | 現在のファイルをリストに追加 |
| `<leader>hh` | Harpoon のメニューを開く |
| `<leader>h1` 〜 `<leader>h5` | リスト内の 1 〜 5 番目のファイルへ移動 |
| `gt` / `gT` | リスト内の次 / 前のファイルへ移動 |

ファイルの探索・移動は、用途に応じて使い分けます。

- 実装とテスト、型定義と実装のように頻繁に行き来するファイル: Harpoon（`<leader>ha`、`gt` / `gT`）
- ファイル名が分かっている場合や、新しくファイルを開く場合: Telescope（`<leader>ff`）
- ディレクトリ階層を確認しながら探す場合: Oil（`<leader>fe`）
- 定義元や参照先へジャンプする場合: LSP（`gd`、`grr`）

Neovim ウィンドウと Kitty ペイン間のシームレスな移動については、[smart-splits.md](./smart-splits.md) を参照してください。
