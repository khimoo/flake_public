# ng で Neovim を開く

kitty で対象プロジェクトに移動して `ng .` を実行する。GUI ウィンドウが開くと端末にプロンプトが戻るため、Alt+Tab で kitty に戻って別のコマンドを実行できる。シェルの direnv 環境も引き継ぐ。

## GUI 内でプロジェクトを変える

`<leader>p` で `~/sagyo` 配下の Git リポジトリを選択する。Enter で Neovim の cwd を変更し、direnv の非同期更新完了後に LSP を再起動する。以降の `<leader>ff` と `<leader>fg` は変更後の cwd を使う。

読み込む `.envrc` が未承認なら、そのプロジェクトのディレクトリで `direnv allow` を実行する。既に開いている別プロジェクトのバッファも同じ Neovim プロセスに残るため、独立した環境が必要な場合は kitty から `ng .` を新たに起動する。

## 入力とコピペ

ng では fcitx5 の IME を使い、skkeleton のキーマップは読み込まない。kitty 上の Neovim は従来どおり Ctrl+J で skkeleton を使う。

ng の `y` / `p` は OS クリップボード（Wayland は wl-clipboard、X11 は xclip）につながる。外部から貼り付けるときは Ctrl+Shift+V も使える。
