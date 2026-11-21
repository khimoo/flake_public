# ng で Neovim を開く

kitty で対象プロジェクトに移動して `ng .` を実行する。GUI ウィンドウが開くと端末にプロンプトが戻るため、Alt+Tab で kitty に戻って別のコマンドを実行できる。シェルの direnv 環境も引き継ぐ。

## GUI 内でプロジェクトを変える

`<leader>p` で `~/sagyo` 配下の Git リポジトリを選択する。Enter で Neovim の cwd を変更する。direnv の環境は非同期に更新され、完了すると動作中の LSP を再起動する。以降の `<leader>ff` と `<leader>fg` は変更後の cwd を使う。

`.envrc` がないプロジェクトでは、前のプロジェクトの direnv 環境を解除する。未承認の `.envrc` がある場合は、そのディレクトリで `direnv allow` した後、`:cd .` などで cwd を再設定する。

別プロジェクトのバッファは同じ Neovim に残る。異なるプロジェクトの LSP や作業環境を同時に利用する場合は、それぞれのディレクトリから `ng .` を起動する。

## 入力とコピペ

ng では fcitx5 の IME を使い、skkeleton のキーマップは読み込まない。kitty 上の Neovim は従来どおり Ctrl+J で skkeleton を使う。

ng の `y` / `p` は OS クリップボード（Wayland は wl-clipboard、X11 は xclip）につながる。外部から貼り付けるときは Ctrl+Shift+V も使える。
