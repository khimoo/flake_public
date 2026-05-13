# シェルツール クイックリファレンス

日常的に使うモダン CLI ツール群のリファレンス。エイリアスで元コマンドを置き換えているため、意識せず使えるものが多いが、オプションを知ると活用の幅が広がる。

> 設定: `modules/home-manager/core.nix`

---

## fzf — ファジーファインダー

あらゆる一覧をインタラクティブに絞り込む。Bash integration により以下のショートカットが使える。

### シェルショートカット

| キー | 操作 |
|------|------|
| `Ctrl+R` | コマンド履歴を検索 |
| `Ctrl+T` | ファイルを検索してコマンドラインに挿入 |
| `Alt+C` | ディレクトリを検索して cd |

### fzf 内の操作

| キー | 操作 |
|------|------|
| 入力 | ファジー検索 (部分一致、順不同) |
| `Ctrl+J` / `Ctrl+K` | 候補を上下に移動 |
| `Enter` | 選択確定 |
| `Tab` | 複数選択 (対応コマンドの場合) |
| `Ctrl+C` / `Escape` | キャンセル |

### 検索構文

| パターン | 意味 |
|---------|------|
| `foo` | "foo" を含む (ファジー) |
| `'foo` | "foo" を完全一致で含む |
| `^foo` | "foo" で始まる |
| `foo$` | "foo" で終わる |
| `!foo` | "foo" を含まない |
| `foo bar` | "foo" AND "bar" (スペース区切り) |
| `foo \| bar` | "foo" OR "bar" |

### パイプとの組み合わせ

```bash
# git ブランチを選んで checkout
git branch | fzf | xargs git checkout

# プロセスを選んで kill
ps aux | fzf | awk '{print $2}' | xargs kill

# fd の結果を fzf で絞り込んで nvim で開く
fd -e py | fzf | xargs nvim
```

---

## eza — ls 代替 {#eza}

ファイル一覧にアイコン、Git 状態、色分けを追加する `ls` の代替。

### エイリアス (設定済み)

| コマンド | 展開 |
|---------|------|
| `ls` | `eza --icons --git` |
| `ll` | `eza -l --icons --git` |
| `la` | `eza -la --icons --git` |

### よく使うオプション

```bash
eza -l --tree --level=2          # ツリー表示 (2階層)
eza -l --sort=modified           # 更新日時順
eza -l --sort=size               # サイズ順
eza -l --group-directories-first # ディレクトリを先に表示 (デフォルト有効ではない)
eza -l --no-git                  # Git 状態を非表示 (大規模リポジトリで高速化)
eza -l --header                  # カラムヘッダーを表示
eza --only-dirs                  # ディレクトリのみ表示
```

### Git 状態の読み方 (--git)

`ll` の出力で各ファイルの右側に表示される:

| マーク | 意味 |
|--------|------|
| `N` | New (untracked) |
| `M` | Modified |
| `-` | 変更なし |

---

## zoxide — スマート cd {#zoxide}

訪問頻度と最終アクセス日時に基づく賢い `cd`。

### エイリアス (設定済み)

`cd` → `z` (zoxide)

### 使い方

```bash
z myproject         # 過去に訪問した "myproject" を含むパスに cd
z my pro            # 複数キーワードで絞り込み (AND)
z ~/exact/path      # 通常の cd としても動作
zi                  # インタラクティブモード (fzf で選択)
```

### 仕組み

- `cd` するたびに訪問履歴が記録される
- `z <keyword>` でスコアが最も高いパスに移動
- 同スコアなら最近訪問したパスが優先
- 完全パスを指定した場合は通常の `cd` と同じ動作

---

## fd — ファイル検索 {#fd}

`find` の代替。デフォルトで `.gitignore` を尊重し、隠しファイルを除外する。

```bash
fd pattern                # ファイル名にパターンを含むものを検索
fd -e rs                  # 拡張子で絞り込み
fd -e rs -e toml          # 複数の拡張子
fd -H pattern             # 隠しファイルも含める
fd -I pattern             # .gitignore を無視
fd -t d                   # ディレクトリのみ
fd -t f                   # ファイルのみ
fd -t l                   # シンボリックリンクのみ
fd pattern /path/to/dir   # 検索ディレクトリを指定
fd -x command {}          # 結果に対してコマンド実行 (find -exec 相当)
fd -X command             # 全結果をまとめてコマンドに渡す (xargs 相当)
```

### 実用例

```bash
fd -e rs -x wc -l         # 全 .rs ファイルの行数
fd -e log -X rm            # 全 .log ファイルを削除
fd -t d node_modules       # node_modules ディレクトリを探す
```

---

## ripgrep (rg) — ファイル内容検索 {#ripgrep}

`grep` の代替。デフォルトで再帰検索、`.gitignore` 尊重、シンタックスハイライト。

### エイリアス (設定済み)

`grep` → `rg`

```bash
rg "pattern"                # カレント以下を再帰 grep
rg "pattern" -t rust        # ファイルタイプ指定
rg "pattern" -g "*.toml"    # glob で絞り込み
rg "pattern" -i             # 大文字小文字を無視
rg "pattern" -w             # 単語単位でマッチ
rg "pattern" -l             # マッチしたファイル名のみ表示
rg "pattern" -c             # ファイルごとのマッチ数
rg "pattern" -C 3           # 前後 3 行のコンテキスト付き
rg "pattern" --replace "new" # マッチ箇所を置換して表示 (ファイルは変更しない)
rg "pattern" -F             # 正規表現を無効にしてリテラル検索
```

### 正規表現の例

```bash
rg "fn\s+\w+\("             # Rust の関数定義を検索
rg "TODO|FIXME|HACK"        # TODO コメントを一括検索
rg "use\s+\w+::\w+"         # Rust の use 文を検索
```

---

## bat — cat 代替 {#bat}

シンタックスハイライト + 行番号付きでファイルを表示する `cat` の代替。

### エイリアス (設定済み)

`cat` → `bat`

```bash
cat file.rs               # ハイライト付き表示
cat -n file.rs             # 行番号表示 (デフォルトで表示される場合もある)
cat -p file.rs             # ページャー付き (長いファイル向け)
cat -l json < data         # stdin の言語を指定してハイライト
cat --diff                 # Git diff のあった行を強調表示
cat -r 10:20 file.rs       # 10~20 行目だけ表示
```

### パイプでの利用

```bash
rg "pattern" -C 3 | bat -l rs     # rg の結果をハイライト表示
curl -s https://example.com/api | bat -l json  # API レスポンスを整形
```

---

## bottom (btm) — システムモニター {#bottom}

`top`/`htop` の代替。CPU、メモリ、ネットワーク、ディスク、プロセスを一画面で監視。

### エイリアス (設定済み)

`top` → `btm`

### 操作

| キー | 操作 |
|------|------|
| `Tab` / `Shift+Tab` | ウィジェット間を移動 |
| `e` | プロセスツリー表示の切替 |
| `/` | プロセスをフィルタ |
| `dd` | 選択プロセスを kill |
| `s` | プロセスのソート方法を変更 |
| `I` | ソート順の反転 |
| `h` / `l` | 時間範囲の縮小/拡大 (グラフ表示) |
| `q` | 終了 |

---

## direnv — ディレクトリ別の環境変数管理 {#direnv}

ディレクトリに `.envrc` を置くと、そのディレクトリに入ったとき自動で環境変数が設定される。Nix devShell との組み合わせが主な用途。

### 基本操作

```bash
direnv allow          # .envrc の変更を許可 (初回 or 変更後に必要)
direnv deny           # .envrc を無効化
direnv reload         # 手動で再読み込み
```

### Nix devShell との連携

プロジェクトルートに `.envrc` を作成:

```bash
# .envrc
use flake
```

これにより `cd` でプロジェクトに入るだけで `flake.nix` の `devShell` が自動ロードされる。`nix develop` を手動で実行する必要がなくなる。

### nix-direnv

`nix-direnv` が有効なため、devShell のビルド結果がキャッシュされる。`cd` のたびに再ビルドが走ることはない (flake.lock が変わらない限り)。

---

## jq — JSON プロセッサ {#jq}

JSON データをフィルタ・変換・整形するコマンドラインツール。

```bash
cat data.json | jq '.'                     # 整形表示
cat data.json | jq '.name'                 # フィールドを取得
cat data.json | jq '.users[0]'             # 配列の要素
cat data.json | jq '.users[] | .name'      # 配列の各要素からフィールド抽出
cat data.json | jq '.users | length'       # 配列の長さ
cat data.json | jq 'select(.age > 20)'     # 条件フィルタ
cat data.json | jq '{name, email}'         # 必要なフィールドだけ抽出
cat data.json | jq -r '.url'              # raw 出力 (引用符なし)
```

### 実用例

```bash
# GitHub API のレスポンスから名前一覧
gh api /repos/:owner/:repo/pulls | jq '.[].title'

# JSON Lines を処理
cat logs.jsonl | jq -c 'select(.level == "error")'
```

---

## xh — HTTP クライアント {#xh}

`curl` の代替。リクエスト/レスポンスを色分けして見やすく表示する。

```bash
xh GET https://api.example.com/users           # GET リクエスト
xh https://api.example.com/users               # GET は省略可

xh POST https://api.example.com/users \
  name=john email=john@example.com              # JSON ボディ (自動)

xh PUT https://api.example.com/users/1 \
  name=jane                                     # PUT リクエスト

xh :8080/api/health                             # localhost 省略形
xh -v POST :3000/api/login user=admin pass=123  # リクエストも表示 (-v)
xh -d https://example.com/file.tar.gz           # ダウンロード
xh -h GET https://example.com                   # ヘッダーのみ表示

# ヘッダー指定
xh GET https://api.example.com/users \
  Authorization:"Bearer token123"
```

---

## gh — GitHub CLI {#gh}

```bash
gh pr create                   # PR 作成
gh pr list                     # PR 一覧
gh pr checkout 123             # PR #123 をチェックアウト
gh pr view --web               # ブラウザで PR を開く
gh issue list                  # Issue 一覧
gh repo clone owner/repo       # リポジトリをクローン
gh api /repos/:owner/:repo     # GitHub API を直接叩く
```

---

## starship — プロンプト

自動で検出・表示される情報:

- Git ブランチ名、変更状態
- 現在のディレクトリに応じた言語バージョン (Rust, Python, Node.js 等)
- 直前のコマンドの成功/失敗 (成功: `❯` / 失敗: `✗`)
- direnv によるシェル環境の検出

設定不要で機能する。表示がうるさい場合は `core.nix` で `disabled` フラグを追加できる。
