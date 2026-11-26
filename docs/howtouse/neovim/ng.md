# ng で Neovim を開く

kitty で対象プロジェクトに移動して `ng .` を実行する。GUI ウィンドウが開くと端末にプロンプトが戻るため、Alt+Tab で kitty に戻って別のコマンドを実行できる。シェルの direnv 環境も引き継ぐ。

## GUI 内でプロジェクトを変える

`<leader>p` で `~/sagyo` 配下の Git リポジトリを選択する。Enter で Neovim の cwd を変更する。direnv の環境は非同期に更新され、完了すると動作中の LSP を再起動する。以降の `<leader>ff` と `<leader>fg` は変更後の cwd を使う。

`.envrc` がないプロジェクトでは、前のプロジェクトの direnv 環境を解除する。未承認の `.envrc` がある場合は、そのディレクトリで `direnv allow` した後、Neovim で `:DirenvReload` を実行する。

別プロジェクトのバッファは同じ Neovim に残る。異なるプロジェクトの LSP や作業環境を同時に利用する場合は、それぞれのディレクトリから `ng .` を起動する。

## 入力とコピペ

ng では fcitx5 の IME（Meltype、[japanese_input.star](../../../config/elements/japanese_input.star)）を使い、skkeleton のキーマップは読み込まない。kitty 上の Neovim は従来どおり Ctrl+J で skkeleton を使う。

Meltype はローマ字を打つだけで英語と日本語を見分け、Mozc と Zenzai でかな漢字に変換する。既定の切り替えキーは 半角/全角 と Alt+` だが、US 配列には 半角/全角 が無く、Alt+` はウィンドウの選択に使われている。右 Alt は altgr-intl 配列の AltGr なので、設定「左 Alt で英数 / 右 Alt で日本語」も右側が効かない。設定と学習データは `~/.local/share/Meltype` にある。fcitx5 の入力メソッドの一覧（`~/.config/fcitx5/profile`）は Nix で管理していないので、初めて使うときは `fcitx5-configtool` で Meltype を追加する。

ng の `y` / `p` は OS クリップボード（Wayland は wl-clipboard、X11 は xclip）につながる。外部から貼り付けるときは Ctrl+Shift+V も使える。
