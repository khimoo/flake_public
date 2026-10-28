# CLI ツールガイド

ターミナル環境で活用する各種 CLI ツールの実践ガイドです。

## ツール一覧

| カテゴリ | ツール | 説明 | ドキュメント |
|----------|--------|------|-------------|
| ファイルマネージャ | yazi | TUI ファイルマネージャ | [yazi.md](./yazi.md) |
| ターミナル | kitty | ターミナルエミュレータの操作 | [kitty.md](./kitty.md) |
| Git UI | lazygit | Git 向け TUI クライアント | [lazygit.md](./lazygit.md) |
| AI リモート操作 | Happy | スマートフォンから Codex を遠隔操作 | [happy.md](./happy.md) |
| AI エージェント | Antigravity CLI (agy) | 日本語校正用のフォールバック経路 | [antigravity-cli.md](./antigravity-cli.md) |
| Python | mimikopi-env | 耳コピ用 ML モデルの実行環境 | [mimikopi-env.md](./mimikopi-env.md) |
| シェルツール | fzf, eza, zoxide, fd, rg, bat, btm, direnv, jq, xh | 日常的に使用する各種 CLI ツール | [shell-tools.md](./shell-tools.md) |
| Nix | comma (`,`), nix-locate | 未インストールコマンドの一時実行とパッケージ検索 | [comma.md](./comma.md) |
| PDF ビューア | tdf | ターミナル内での PDF 閲覧 | [shell-tools.md#tdf](./shell-tools.md#tdf) |

## シェルエイリアス (core.nix)

日常的に使う標準コマンドは、モダンな代替ツールに置き換えています。

| 元コマンド | エイリアス | ツール |
|-----------|-----------|--------|
| `ls` | `eza --icons --git` | eza |
| `ll` | `eza -l --icons --git` | eza |
| `la` | `eza -la --icons --git` | eza |
| `cat` | `bat` | bat |
| `grep` | `rg` | ripgrep |
| `top` | `btm` | bottom |
| `cd` | `z` | zoxide |

> `yazi` は `y` 関数経由で起動してください（終了時にカレントディレクトリが追従します）。`yazi` コマンドで直接起動した場合はディレクトリの追従が行われません。

---

## ワークフロー

### 1. プロジェクトへの移動と作業開始

```bash
z myproject          # zoxide: 履歴にある "myproject" へ cd
direnv allow         # 初回のみ: devShell を有効化 (.envrc がある場合)
# → devShell の環境変数やツールが自動ロードされる
y                    # yazi でディレクトリ構造を確認、Enter でファイルを開く
nvim .               # エディタで開く
```

→ [zoxide](./shell-tools.md#zoxide), [direnv](./shell-tools.md#direnv), [yazi](./yazi.md)


### 2. ファイルやコンテンツの検索

```bash
# ファイル名で検索
fd pattern                    # カレントディレクトリ以下を再帰検索
fd -e rs                      # 拡張子で絞り込み
fd -H pattern                 # 隠しファイルも含めて検索

# ファイル内容を検索
rg "pattern"                  # カレントディレクトリ以下を grep 検索
rg "pattern" -t rust          # ファイルタイプで絞り込み
rg "pattern" -g "*.toml"      # glob パターンで絞り込み

# インタラクティブな絞り込み
Ctrl+T                        # fzf: 選択したファイルをコマンドラインに挿入
Ctrl+R                        # fzf: コマンド履歴をインクリメンタル検索
Alt+C                         # fzf: 選択したディレクトリへ cd
```

→ [fd, ripgrep, fzf](./shell-tools.md)

### 3. ファイル内容・一覧の確認

```bash
cat file.rs                   # bat: シンタックスハイライト付きで表示
cat -p file.rs                # bat: ページャー経由で閲覧 (長いファイル向け)
cat -A file.rs                # bat: 行番号や Git 差分マークなどの全装飾付きで表示

ll                            # eza: ファイル一覧 (サイズ・権限・Git 状態を表示)
la                            # eza: 隠しファイルを含めて一覧表示
eza -l --tree --level=2       # ツリー形式で表示 (2階層まで)
```

→ [bat, eza](./shell-tools.md)

### 4. Git 操作

```bash
lazygit                       # TUI 上でステージ・コミット・push などの Git 操作を実行
git diff                      # delta: side-by-side diff を自動適用
git log                       # delta: コミットログを見やすく装飾して表示
```

→ [lazygit](./lazygit.md)

### 5. システム監視

```bash
top                           # bottom: プロセス、CPU、メモリ等のリアルタイム監視
# → btm 内では Tab キーでウィジェット切り替え、/ でプロセス検索
```

→ [bottom](./shell-tools.md#bottom)


### 6. HTTP リクエスト (API テスト)

```bash
xh GET https://api.example.com/users     # curl の代替: カラー出力で見やすく表示
xh POST https://api.example.com/users \
  name=john email=john@example.com        # JSON リクエストボディを簡潔に指定
xh :8080/api/health                       # localhost:8080 の短縮記法
```

→ [xh](./shell-tools.md#xh)


### 7. 環境音・ノイズ再生 (集中用)

```bash
noise                         # ~/音楽/noise/ をシャッフル再生 (デフォルト音量: 50)
noise ~/音楽/rain 30          # ディレクトリと音量を指定して再生
```

> `noise` は bash 関数として定義されています (core.nix)。内部で mpv をバックグラウンド実行します。
