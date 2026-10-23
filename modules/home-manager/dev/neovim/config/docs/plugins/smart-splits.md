# smart-splits.nvim — ウィンドウ/ペイン統合操作

Neovim のウィンドウ分割と kitty のペインをシームレスに行き来・リサイズできるプラグイン。

- 設定ファイル (nvim): `lua/features/smart_splits.lua`
- 設定ファイル (kitty): `modules/home-manager/gui/kitty/kitty.conf`

## 仕組み

kitty 側でペイン移動とリサイズのキーを登録する。
Neovim が設定する `IS_NVIM` user var でフォーカス中のペインを判定し:

- **Neovim の場合**: キーを Neovim に転送 → smart-splits.nvim がウィンドウ間を移動/リサイズ
- **Neovim 以外の場合**: kitty がペイン間を移動/リサイズ

この仕組みにより、同じキーバインドで Neovim のウィンドウも kitty のペインも区別なく操作できる。

## キーバインド

### ペイン/ウィンドウ間の移動

| キー | 機能 |
|------|------|
| `Ctrl+h` | 左のウィンドウ/ペインに移動 |
| `Ctrl+j` | 下のウィンドウ/ペインに移動 |
| `Ctrl+k` | 上のウィンドウ/ペインに移動 |
| `Ctrl+l` | 右のウィンドウ/ペインに移動 |

端に到達したらそこで止まる（`at_edge = "stop"`）。理由は
[kitty.md](../../../../../../../docs/architecture/kitty.md#smart-splits-の-kitty-backend) を参照。

### リサイズ

| キー | 機能 |
|------|------|
| `Alt+h` | 左方向にリサイズ |
| `Alt+j` | 下方向にリサイズ |
| `Alt+k` | 上方向にリサイズ |
| `Alt+l` | 右方向にリサイズ |

リサイズ量は `default_amount = 3`（行/列）。

### バッファスワップ (Neovim 内のみ)

| キー | 機能 |
|------|------|
| `<leader><leader>h` | 左のウィンドウとバッファを交換 |
| `<leader><leader>j` | 下のウィンドウとバッファを交換 |
| `<leader><leader>k` | 上のウィンドウとバッファを交換 |
| `<leader><leader>l` | 右のウィンドウとバッファを交換 |

バッファスワップは Neovim のウィンドウ間でのみ動作する（kitty ペインとは交換しない）。

## kitty 側の設定

[kitty.nix](../../../../../../../modules/home-manager/gui/kitty.nix) が smart-splits 同梱の kitten を配置する。
接続とキー割当ては [kitty の使い方](../../../../../../../docs/howtouse/cli-tools/kitty.md) を参照。

## 注意事項

- ペインがズーム状態のとき、クロスペインナビゲーションは無効（`disable_multiplexer_nav_when_zoomed = true`）
- `Ctrl+h/j/k/l` は kitty 側でも設定されるため、既存キーバインドとの競合に注意
