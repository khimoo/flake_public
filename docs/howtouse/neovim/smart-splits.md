# ウィンドウと kitty ペインの操作（smart-splits.nvim）

共通のキーバインドを用いて、Neovim の分割ウィンドウと kitty のペイン間をシームレスに移動・リサイズする。

設定: Neovim 側は `lua/features/smart_splits.lua`、kitty 側は [kitty.conf](../../../modules/home-manager/gui/kitty/kitty.conf)

## キー操作

| キー | 機能 |
|------|------|
| `Ctrl+h` / `Ctrl+j` / `Ctrl+k` / `Ctrl+l` | 左 / 下 / 上 / 右のウィンドウまたはペインへ移動する |
| `Alt+h` / `Alt+j` / `Alt+k` / `Alt+l` | 左 / 下 / 上 / 右方向のサイズを 3 行（列）単位で伸縮する |
| `<leader><leader>h` / `j` / `k` / `l` | 指定した方向のウィンドウとバッファを入れ替える（Neovim 内限定） |

画面の端に到達した場合は、それ以上外側の領域へは移動しない（詳細は [kitty の設計](../../architecture/kitty.md#smart-splits-の-kitty-backend) を参照）。
また、kitty 側でペインを拡大表示（ズーム）している間は、Neovim から kitty のペインへの移動は行われない。

## 正常に動作しないとき

kitty は、現在フォーカスしているペイン内で Neovim が動作しているかどうかを、Neovim 側が設定するユーザー変数 `IS_NVIM` によって判定する。Neovim が動いている場合は `Ctrl+h` などのキーストロークを Neovim 側にそのまま渡し、それ以外の場合は kitty 自身がペインのフォーカスを移動する。Neovim の最端のウィンドウから kitty のペインへ移動する際には、Neovim が `kitty @` コマンドを介してペインを切り替える。

Neovim と kitty ペイン間を移動できない場合は、kitty 側の設定を確認する。smart-splits の kitten は [kitty.nix](../../../modules/home-manager/gui/kitty.nix) によって配置され、`kitty @` が通信に使うソケット設定（`listen_on`）は kitty.conf に記述されている。`listen_on` の設定を変更した場合は、kitty を再起動するまで反映されないため注意すること（[kitty の使い方](../cli-tools/kitty.md)）。
