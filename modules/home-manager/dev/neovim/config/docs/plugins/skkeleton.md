# 日本語入力 (skkeleton + fcitx5)

SKK 方式の日本語入力と fcitx5 の自動切り替え。

- 設定ファイル: `lua/plugins/skkeleton.lua`, `init.lua` (fcitx5 連携部分)

## プラグイン

### skkeleton

Vim/Neovim 上で動作する SKK 入力メソッド。denops.vim (Deno) に依存。

### skkeleton_indicator.nvim

skkeleton の入力モード (ひらがな/カタカナ/英数) をインジケーター表示。

## キーバインド

| キー | モード | 機能 |
|------|--------|------|
| `<C-j>` | i, c | SKK の ON/OFF トグル |

## SKK の基本操作 (skkeleton が ON の状態)

| 操作 | 機能 |
|------|------|
| 大文字で入力開始 | 漢字変換モードに入る (例: `Kanji`) |
| `<Space>` | 変換候補を表示 |
| `<CR>` | 確定 |
| `q` | カタカナ変換 |
| `l` | 英数モード |

## fcitx5 連携 (init.lua)

Neovim 外の入力メソッド (fcitx5) との自動切り替え:

- **InsertLeave**: fcitx5 の状態を保存し、IME を OFF にする
- **InsertEnter**: 保存した状態を復元する (日本語入力中だったなら ON に戻す)

つまり、ノーマルモードでは常に英数入力になり、インサートモードに戻ると前の IME 状態が復元される。

## 設定のポイント

- `eggLikeNewline = true`: 確定と改行を分離
- `keepMode = true`: モードを維持
- `keepState = true`: 状態を維持
- カスタムかな変換: `z<Space>` → 全角スペース、`,` → `', '`、`.` → `'. '`
