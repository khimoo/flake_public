# ng で Neovim を開く

kitty で対象プロジェクトに移動して `ng .` を実行する。GUI ウィンドウが開くと端末にプロンプトが戻るため、Alt+Tab で kitty に戻って別のコマンドを実行できる。シェルの direnv 環境も引き継ぐ。

## GUI 内でプロジェクトを変える

`<leader>p` で `~/sagyo` 配下の Git リポジトリを選択する。Enter で Neovim の cwd を変更する。direnv の環境は非同期に更新され、完了すると動作中の LSP を再起動する。以降の `<leader>ff` と `<leader>fg` は変更後の cwd を使う。

`.envrc` がないプロジェクトでは、前のプロジェクトの direnv 環境を解除する。未承認の `.envrc` がある場合は、そのディレクトリで `direnv allow` した後、Neovim で `:DirenvReload` を実行する。

別プロジェクトのバッファは同じ Neovim に残る。異なるプロジェクトの LSP や作業環境を同時に利用する場合は、それぞれのディレクトリから `ng .` を起動する。

## 入力とコピペ

ng では fcitx5 の IME（Meltype、[japanese_input.star](../../../config/elements/japanese_input.star)）を使い、skkeleton のキーマップは読み込まない。kitty 上の Neovim は従来どおり Ctrl+J で skkeleton を使う。

Meltype はローマ字を打つだけで英語と日本語を見分け、Mozc と Zenzai でかな漢字に変換する。日本語と英数を手動で切り替えるときは **左 Alt+Space** を押す（[キーボード設定](../keyboard-layers.md)）。左 Alt+バッククォートはウィンドウ選択、右 Alt はアクセント入力に使う。

設定と学習データは `~/.local/share/Meltype` にある。fcitx5 の入力メソッドの一覧（`~/.config/fcitx5/profile`）は [japanese_input.star](../../../config/elements/japanese_input.star) で宣言している。Home Manager が `~/.config/fcitx5` を丸ごと読み取り専用のリンクにするので、`fcitx5-configtool` で変えた設定は保存されない。変えるときは japanese_input.star を直して switch する。

ng の `y` / `p` は OS クリップボード（Wayland は wl-clipboard、X11 は xclip）につながる。外部から貼り付けるときは Ctrl+Shift+V も使える。
