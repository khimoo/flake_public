# smart-splits.nvim — ウィンドウ/ペイン統合操作

Neovim のウィンドウ分割と wezterm のペインをシームレスに行き来・リサイズできるプラグイン。

- 設定ファイル (nvim): `lua/plugins/smart-splits.lua`
- 設定ファイル (wezterm): `dotfiles/wezterm/wezterm.lua`

## 仕組み

wezterm 側に smart-splits のプラグインを読み込み、`apply_to_config` でキーバインドを登録する。
キーが押されると wezterm はフォーカス中のペインが Neovim かどうかを判定し:

- **Neovim の場合**: キーを Neovim に転送 → smart-splits.nvim がウィンドウ間を移動/リサイズ
- **Neovim 以外の場合**: wezterm がペイン間を移動/リサイズ

この仕組みにより、同じキーバインドで Neovim のウィンドウも wezterm のペインも区別なく操作できる。

## キーバインド

### ペイン/ウィンドウ間の移動

| キー | 機能 |
|------|------|
| `Ctrl+h` | 左のウィンドウ/ペインに移動 |
| `Ctrl+j` | 下のウィンドウ/ペインに移動 |
| `Ctrl+k` | 上のウィンドウ/ペインに移動 |
| `Ctrl+l` | 右のウィンドウ/ペインに移動 |

端に到達すると反対側にラップする（`at_edge = "wrap"`）。

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

バッファスワップは Neovim のウィンドウ間でのみ動作する（wezterm ペインとは交換しない）。

## ユースケース

### 1. コードを読みながらターミナルで確認

```
Ctrl+s v          wezterm で横ペイン分割（Leader+v）
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
Ctrl+s s          wezterm で縦ペイン分割（Leader+s）
Ctrl+s v          wezterm で横ペイン分割（Leader+v）
Alt+h/j/k/l       各ペインのサイズを調整
Ctrl+h/j/k/l      ペイン間を自由に移動
```

### 4. ウィンドウの内容を入れ替える

```
:vsplit other.rs   横に別ファイルを開く
<leader><leader>l  左右のバッファを交換（参照と実装の位置を入れ替え等）
```

## wezterm 側の設定

`wezterm.lua` の末尾で以下を記述：

```lua
local smart_splits = wezterm.plugin.require('https://github.com/mrjones2014/smart-splits.nvim')
smart_splits.apply_to_config(config, {
  direction_keys = { 'h', 'j', 'k', 'l' },
  modifiers = {
    move = 'CTRL',
    resize = 'META',
  },
})
```

`apply_to_config` は `config.keys` にキーバインドを追加するため、`config.keys` の定義より後に呼ぶこと。

## 注意事項

- wezterm の `wezterm.plugin.require()` が必要（比較的新しい機能）
- ペインがズーム状態のとき、クロスペインナビゲーションは無効（`disable_multiplexer_nav_when_zoomed = true`）
- `Ctrl+h/j/k/l` は wezterm 側でも設定されるため、wezterm の既存キーバインドと競合しないか注意
