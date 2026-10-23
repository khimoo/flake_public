# 外観とキー候補の表示

設定: `lua/plugins/lualine.lua`、`lua/plugins/indent.lua`、`lua/plugins/fidget.lua`、`lua/plugins/which-key.lua`

- ステータスライン（lualine）: 現在のモード、ファイル名、エンコーディング、行番号などを表示する。配色は現在のカラースキームに基づいて生成されるため、`:set background=light` などで切り替えるとステータスラインの配色も追従する。
- スコープの可視化（hlchunk）: カーソル位置の関数や if ブロックの範囲をガイド線で囲み、該当範囲の行番号をハイライト表示する。
- LSP の進行状況（fidget）: コード整形やインデックス作成など、LSP サーバーの処理進捗を画面右下に表示する。
- キー候補の表示（which-key）: `<leader>` などのプレフィックスキーを押して待機すると、続けて入力可能なキーの一覧を表示する。キー操作を覚えていない場合でも、プレフィックスキーを押して候補一覧から選んで実行できる（[cheatsheet.md](./cheatsheet.md) を参照）。
