# CLI ツールガイド

ターミナル環境で使う CLI ツールの使いこなしドキュメント。

## ツール一覧

| カテゴリ | ツール | 説明 | ドキュメント |
|----------|--------|------|-------------|
| ファイルマネージャ | yazi | TUI ファイルマネージャ (プラグイン多数) | [yazi.md](./yazi.md) |
| ターミナル | wezterm | GPU 加速ターミナル (Leader キー体系) | [wezterm.md](./wezterm.md) |
| Git UI | lazygit | Git TUI クライアント (delta 連携) | [lazygit.md](./lazygit.md) |
| シェルツール | fzf, eza, zoxide, fd, rg, bat, btm, direnv, jq, xh | モダン CLI ツール群 | [shell-tools.md](./shell-tools.md) |

## シェルエイリアス (core.nix)

日常的に使うコマンドはモダンな代替ツールに置き換え済み。

| 元コマンド | エイリアス | ツール |
|-----------|-----------|--------|
| `ls` | `eza --icons --git` | eza |
| `ll` | `eza -l --icons --git` | eza |
| `la` | `eza -la --icons --git` | eza |
| `cat` | `bat` | bat |
| `grep` | `rg` | ripgrep |
| `top` | `btm` | bottom |
| `cd` | `z` | zoxide |

> `yazi` は `yy` 関数で起動する（終了時にディレクトリを追従する）。直接 `yazi` でも起動できるがディレクトリ追従なし。

---

## ワークフロー

### 1. プロジェクトに入って作業を始める

```bash
z myproject          # zoxide: 過去に訪問した "myproject" に cd
direnv allow         # 初回のみ: devShell を有効化 (.envrc がある場合)
# → 自動で devShell の環境変数・ツールが読み込まれる
yy                   # yazi でファイル構造を確認、Enter で開く
nvim .               # エディタで開く
```

→ [zoxide](./shell-tools.md#zoxide), [direnv](./shell-tools.md#direnv), [yazi](./yazi.md)

### 2. ファイルを探す・内容を検索する

```bash
# ファイル名で探す
fd pattern                    # カレント以下を再帰検索
fd -e rs                      # 拡張子で絞り込み
fd -H pattern                 # 隠しファイルも含める

# ファイル内容を検索する
rg "pattern"                  # カレント以下を grep
rg "pattern" -t rust          # ファイルタイプで絞り込み
rg "pattern" -g "*.toml"      # glob パターンで絞り込み

# インタラクティブに絞り込む
Ctrl+T                        # fzf: ファイルを選んでコマンドラインに挿入
Ctrl+R                        # fzf: コマンド履歴を検索
Alt+C                         # fzf: ディレクトリを選んで cd
```

→ [fd, ripgrep, fzf](./shell-tools.md)

### 3. ファイル内容を確認する

```bash
cat file.rs                   # bat: シンタックスハイライト付きで表示
cat -p file.rs                # bat: ページャー付き (長いファイル)
cat -A file.rs                # bat: 全装飾 (行番号+Git差分マーク)

ll                            # eza: ファイル一覧 (サイズ, 権限, Git状態)
la                            # eza: 隠しファイル含む
eza -l --tree --level=2       # ツリー表示 (2階層まで)
```

→ [bat, eza](./shell-tools.md)

### 4. Git 操作

```bash
lazygit                       # TUI で Git 操作 (ステージ, コミット, push)
git diff                      # delta: side-by-side diff が自動適用
git log                       # delta: commit ログも装飾付き
```

→ [lazygit](./lazygit.md)

### 5. システム監視

```bash
top                           # bottom: プロセス/CPU/メモリ監視
# → btm 内で Tab キーでウィジェット切替, / で検索
```

→ [bottom](./shell-tools.md#bottom)

### 6. HTTP リクエスト (API テスト)

```bash
xh GET https://api.example.com/users     # curl 代替: カラフルな出力
xh POST https://api.example.com/users \
  name=john email=john@example.com        # JSON ボディを簡潔に指定
xh :8080/api/health                       # localhost 省略形
```

→ [xh](./shell-tools.md#xh)

### 7. ノイズ再生 (集中用)

```bash
noise                         # ~/音楽/noise/ をシャッフル再生 (音量50)
noise ~/音楽/rain 30          # ディレクトリと音量を指定
```

> `noise` は bash 関数として定義 (core.nix)。mpv をバックグラウンドで使用。
