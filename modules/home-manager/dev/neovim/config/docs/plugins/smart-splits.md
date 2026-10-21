# smart-splits.nvim — ウィンドウ/ペイン統合操作

Neovim のウィンドウ分割と kitty のペインをシームレスに行き来・リサイズできるプラグイン。

- 設定ファイル (nvim): `lua/plugins/smart-splits.lua`
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

## ユースケース

### 1. コードを読みながらターミナルで確認

```
Ctrl+a v          kitty で横ペイン分割（Leader+v）
                   → 右ペインでシェルが開く
(左ペインで nvim、右ペインでシェル)
Ctrl+l            nvim → シェルにフォーカス移動
Ctrl+h            シェル → nvim にフォーカス移動
```

### 2. Neovim 内で複数ファイルを並べて編集

```
:vsplit            Neovim 内で縦分割
Ctrl+l / Ctrl+h   分割間を移動
Alt+h / Alt+l      分割の幅を調整
```

### 3. 複数ペインのレイアウト調整

```
Ctrl+a s          kitty で縦ペイン分割（Leader+s）
Ctrl+a v          kitty で横ペイン分割（Leader+v）
Alt+h/j/k/l       各ペインのサイズを調整
Ctrl+h/j/k/l      ペイン間を自由に移動
```

### 4. ウィンドウの内容を入れ替える

```
:vsplit other.rs   横に別ファイルを開く
<leader><leader>l  左右のバッファを交換（参照と実装の位置を入れ替え等）
```

## kitty 側の設定

[kitty.nix](../../../../../../../modules/home-manager/gui/kitty.nix) が smart-splits 同梱の kitten を配置する。
接続とキー割当ては [kitty の使い方](../../../../../../../docs/howtouse/cli-tools/kitty.md) を参照。

## 注意事項

- ペインがズーム状態のとき、クロスペインナビゲーションは無効（`disable_multiplexer_nav_when_zoomed = true`）
- `Ctrl+h/j/k/l` は kitty 側でも設定されるため、既存キーバインドとの競合に注意
