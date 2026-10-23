# 作業ごとのキー操作

よくある作業の流れに沿って、使用するキー操作を順にまとめています。各操作の詳細については、各セクション末尾のリンク先を参照してください。

## コードを読む

```
<leader>ff      ファイル名で検索してエントリポイントを開く
<leader>fs      ファイル内の関数や型の一覧を確認し、構造を把握する
<leader>fS      ワークスペース全体からシンボルを検索する（型名・関数名などで探す）
gd              気になる関数や型の定義へジャンプする
<C-o>           元の場所に戻る（<C-i> で進む）
grr             使われている箇所（参照）の一覧を表示する
K               ホバーで型情報やドキュメントを確認する
<leader>o       aerial でアウトラインを表示する
[s / ]s         シンボル間を移動してコードを流し読みする
]f / [f         次 / 前の関数へ移動する
```

`gd` で定義へジャンプし、`<C-o>` で戻る操作を繰り返しながらコードを読み進めます。`<C-o>` は何回でも履歴を遡ることができます。

→ [lsp.md](./lsp.md)、[telescope.md](./telescope.md)、[treesitter.md](./treesitter.md)

## バグを探して直す

```
<leader>xx      trouble で診断（エラー・警告）一覧を表示する
[d / ]d         エラー箇所を順に移動する
（250ms 静止）   カーソル位置の診断メッセージがフロート表示される
gd              エラーに関連する定義へジャンプする
<leader>fg      エラーメッセージや関連文字列を live_grep で検索する
（修正作業）
gra             code action に修正候補があれば適用する
<leader>lF      コードをフォーマットする
```

→ [lsp.md](./lsp.md)、[trouble.md](./trouble.md)、[telescope.md](./telescope.md)

## リファクタリング

```
gd              変更対象の定義へ移動する
grr             影響範囲（使われている箇所）を確認する
grn             LSP の rename でプロジェクト全体の名前を一括変更する
<C-k>           シグネチャヘルプで引数の型を確認する
gcc             不要なコードを一時的にコメントアウトする
gcc             問題がなければ再度 gcc で戻し、dd で削除する
```

行のコメントアウトは、1 行なら `gcc`、複数行ならビジュアルモードで選択して `gc` を使用します。モーションで範囲を指定する場合は `gcip`（段落単位）や `gc5j`（下へ 5 行）のように入力します。

→ [lsp.md](./lsp.md)、[editing.md](./editing.md)、[completion.md](./completion.md)

## 日常の編集

### ファイルの移動

```
<leader>ff      ファイル名で検索して開く
<leader>fb      開いているバッファ一覧から選択する
<leader>fo      最近開いたファイルの履歴から選択する
gt / gT         harpoon リスト内の次 / 前のファイルへ移動する
<leader>ha      現在のファイルを harpoon リストに追加する
<leader>hh      harpoon のメニューを開く
<leader>fe      Oil でディレクトリを開く（ファイルの作成・名前変更・移動）
```

→ [telescope.md](./telescope.md)、[navigation.md](./navigation.md)

### テキストの編集

```
yiw             単語をヤンク（コピー）する
ciw             単語を書き換える（削除して挿入モードに入る）
ci"             引用符（ダブルクォート）の中身を書き換える
da(             括弧を含めて丸ごと削除する
<C-a> / <C-x>   数値や真偽値（bool）を増減・反転する（dial.nvim）
v → an          外側（親）の構文ノードを選択する（押すたびに選択範囲が拡大）
v → in          内側（子）の構文ノードを選択する（選択範囲を縮小）
v → . / ;       an のエイリアス
v → i;          in のエイリアス
<leader>m       treesj で 1 行と複数行の記述を相互に切り替える
```

→ [editing.md](./editing.md)、[treesitter.md](./treesitter.md)

### 囲み文字の操作（Surround）

```
<leader>sysiw"  word を "word" で囲む
<leader>scs"'   "x" を 'x' に変更する
<leader>sds"    "x" からダブルクォートを削除して x にする
```

→ [editing.md](./editing.md)

### 検索

```
/pattern        パターンを検索する（hlslens によりマッチ件数が表示される）
n / N           次 / 前のマッチ箇所へ移動する
* / #           カーソル下の単語を前方 / 後方検索する
<Esc><Esc>      検索ハイライトを消去する
<leader>fg      プロジェクト全体を全文検索する（Telescope）
```

→ [editing.md](./editing.md)、[telescope.md](./telescope.md)

## Git 操作

```
]c / [c         次 / 前の変更箇所（hunk）へ移動する
<leader>gp      hunk の変更内容をプレビューする
<leader>gs      hunk をステージングする
<leader>gr      hunk をリセットする（変更を取り消す）
<leader>gS      バッファ全体の変更をステージングする
<leader>gb      行ごとの blame（変更履歴）を表示する
<leader>gd      diff を表示する
ih              hunk を選択するテキストオブジェクト（dih, yih など）
```

`]c` で変更箇所（hunk）を順に確認し、`<leader>gp` で内容を確かめた上で、`<leader>gs` でステージしていきます。

→ [git.md](./git.md)

## デバッグ

```
<leader>db      ブレークポイントの設定 / 解除
<leader>dc      デバッグの開始 / 続行
<leader>do      ステップオーバー
<leader>di      ステップイン
<leader>dO      ステップアウト
<leader>dr      REPL を開く
```

→ [dap.md](./dap.md)、[lang-rust.md](./lang-rust.md)

## テストの実行

```
<leader>tt      カーソル位置のテストを実行する
<leader>tf      ファイル内の全テストを実行する
<leader>tl      直前のテストを再実行する
<leader>ts      テスト一覧パネルの表示 / 非表示を切り替える
<leader>to      テストの実行出力を確認する
<leader>td      DAP を使ってテストをデバッグ実行する
```

テストコードを書いて `<leader>tt` で実行し、実装を書いた後はテストが通るまで `<leader>tl` で繰り返し再実行します。

→ [neotest.md](./neotest.md)

## 日本語入力

```
<C-j>           挿入モードおよびコマンドラインモードで SKK の ON/OFF を切り替える
```

→ [skkeleton.md](./skkeleton.md)

## ウィンドウとペインの操作

```
Ctrl+h/j/k/l               ウィンドウおよび kitty ペイン間を移動する
Alt+h/j/k/l                ウィンドウやペインのサイズを変更する
<leader><leader>h/j/k/l    隣接するウィンドウとバッファを入れ替える（Neovim 内限定）
```

→ [smart-splits.md](./smart-splits.md)
