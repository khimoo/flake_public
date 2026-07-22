# Zettelkasten 添付フォルダの Google Drive 同期（設計判断）

Obsidian vault（Zettelkasten）の添付ファイル（画像等）の実体を Google Drive に置き、
ノートからはリンク（ファイル名参照）で辿る運用。実体はローカルにも残し、rclone bisync で
Drive とミラーする。git には blob を載せない。

使い方・鍵運用の手順は [../howtouse/zettelkasten-attachments-sync.md](../howtouse/zettelkasten-attachments-sync.md) を参照。

## 責務分離：仕組みと 同期専用 secret は workflow flake、環境固有の配線は flake_public

同期の**仕組み**・同期専用 secret（rclone.conf の暗号文）・その実行時復号は、すべて
mechanism リポジトリ（public repo `khimoo/zettelkasten-workflow`）の `flake.nix` が所有する。
`flake_public` はそれを `github:`（https 取得）で input に取り込み、vault の clone 位置という
環境固有の配線だけを注入する。ノート本文は別の private repo `khimoo/zettelkasten` にあり、
mechanism を public 分割したことで flake_public の eval に SSH 鍵は要らない。復号鍵（各マシンの
SSH 鍵）は flake の外・環境側に残る。

```
khimoo/zettelkasten-workflow (public。workflow flake = 仕組み + 同期専用 secret + 実行時復号)
├─ nix/bisync-lib.nix … bisync 本体(preflight + resync ガード)。sync-script/papis-sync-script が spec を渡す薄ラッパー
├─ nix/with-rclone-secret.nix … 実行時復号ラッパー(全環境の唯一の入口)。鍵発見 → secrets/rclone.yaml を
│    tmpfs へ復号 → RCLONE_CONFIG を向けて同期本体を実行 → 終了時に平文削除
├─ nix/hm-module.nix  … 統合モジュール services.zettelkasten(+ nix/papis.nix)。watcher 常駐(systemd/launchd)
│    options { zettelkastenRoot, rcloneConfigPath, after, wants, attachments.*, papis.* }
├─ .sops.yaml / secrets/rclone.yaml … 暗号化された rclone.conf(同期専用 secret)と受信者一覧(公開鍵のみ)
└─ packages/apps.<sys>.{zettelkasten-sync,papis-sync} … `nix run` 用スクリプト(HM と同じラップ済み入口)

flake_public (環境固有の配線だけ注入)
└─ modules/home-manager/zettelkasten.nix … vault 本体 import + zettelkastenRoot / attachments.enable / papis.enable
```

- 同期本体（`bisync-lib.nix` / sync-script）は sops を**知らない**（`RCLONE_CONFIG` シームは
  string のまま）。復号は `with-rclone-secret.nix` だけが担い、実行のたびに「鍵発見
  （`SOPS_AGE_KEY(_FILE)` → `~/.ssh/id_ed25519` の ssh-to-age 変換）→ tmpfs へ復号 → 同期 →
  平文削除」を行う。sops-nix（activation 時復号）に依存しないため、NixOS・standalone
  home-manager・素の環境が**全て同じ入口**を通る。添付（`attachments.enable`）と papis
  （`papis.enable`）は独立した sub-toggle で、どちらかが真なら統合モジュールを有効化する。
- `flake_public` の `modules/home-manager/zettelkasten.nix` が唯一の glue。注入するのは vault clone
  位置（`zettelkastenRoot`）と feature toggle だけで、secret の配線は無い。flake は秘密鍵を持たず
  （持つのは暗号文と受信者=公開鍵のみ）、復号鍵は各マシンの SSH 鍵か持ち込みの age 鍵として
  環境側に残る。

### なぜ workflow flake 側に置くのか（`nix run` 単独動作）

**自分自身が** home-manager を使えないマシン（借り物 PC・一時的なマシン）に居るときも、
`nix run github:khimoo/zettelkasten-workflow` で自分の Drive 同期をワンショット実行できるようにするため
（public repo なので取得に SSH 鍵は要らず、復号鍵だけ用意すればよい）。
`hm-module.nix` と `packages/apps` は同じスクリプト（`nix/with-rclone-secret.nix` +
`nix/sync-script.nix`）を**共有**し、復号も同期もロジックを二重に持たない
（HM は watcher で常駐、`nix run` はワンショット、中身は同一）。

この flake は **single-tenant**（zettelkasten と Drive は所有者専用）。第三者が実行時に
自分の Drive を同期する形態は設計対象外で、第三者利用は fork して個人固有部分
（`.sops.yaml`・`secrets/rclone.yaml`・remote 名既定値）を自分用に差し替える想定。

## papis 同期との関係（同じ設計・secret 共有・baseline 隔離）

[papis ライブラリ同期](./papis-gdrive-sync.md)と本質的に同じ構造
（rclone bisync + watchexec + sops）だが、次の点で独立している:

- **secret は共有**。同じ gdrive remote・同じ `rclone_conf` secret を使う。暗号文も
  [実行時復号](./papis-gdrive-sync.md#secret-は-workflow-flake-が所有し同期スクリプト自身が実行時に復号する)も
  workflow flake 側 1 箇所だけで、papis と Zettelkasten の両 sync が同じ入口を通る。
- **baseline は隔離**。rclone bisync のベースラインを papis と混ぜないよう、
  `--workdir` を専用ディレクトリ `~/.cache/rclone/bisync-zettelkasten` に固定する
  （papis は `~/.cache/rclone/bisync-papis`）。同一 remote 名でも別フォルダを同期するので
  `--resync` ガードの baseline も別管理になる。

## 設計判断

### 実体はローカル保持 + Drive ミラー（Drive を唯一の置き場にしない）

添付の実体をローカルにも残し、Drive を**ミラー**にする。理由:

- Obsidian も Neovim（画像インライン表示）もローカルのファイルパスを解決するので、
  実体がローカルにある方が閲覧・貼り付けが速く、オフラインでも動く。
- Drive を唯一の実体置き場（例: rclone mount）にすると、レイテンシとマウント依存が増え、
  ネットワーク断で編集が止まる。bisync ミラーなら片方オフラインでも最終的に整合する。

### blob は git から除外（ノートはファイル名参照で辿る）

添付の実体は git に載せず（vault の `.gitignore` に `/attachments/`）、Drive で同期する。
ノートは wikilink `![[filename]]` か相対リンクでファイル名を参照するだけなので、blob が
git に無くてもリンクは切れない。git 履歴が画像バイトで膨らむのを避ける。

### フォルダ名は `attachments`（Obsidian の attachmentFolderPath と一致）

Obsidian の `attachmentFolderPath = "attachments"`（vault ルート相対）と物理的に一致させる。
これにより「Obsidian で貼り付け」も「Neovim(img-clip)で貼り付け」も**同じ 1 フォルダ**に
着地し、その 1 フォルダを bisync する。img-clip 側は保存先を `~/sagyo/zettelkasten/attachments`
に**ハードコード**して一致させる（`relative_to_current_file = false`。将来 neovim 設定を独立
モジュールへ切り出す際に option 化する TODO 付き。副作用として zettelkasten 以外の Obsidian
vault で貼ってもここに保存される）
（[markdown プラグインのドキュメント](../../modules/home-manager/dev/neovim/config/docs/plugins/markdown.md)参照）。

### リンクは相対 Markdown リンク（Obsidian と image.nvim の両対応）

img-clip が挿入するリンクは `relative_template_path`（既定）で現在ファイルからの相対パスにする。
Obsidian は `useMarkdownLinks=false` でも Markdown リンクを**表示**できるし、Neovim の
image.nvim はインライン表示に相対パスを解決する。wikilink（`![[...]]`）だと image.nvim が
treesitter で画像ノードとして認識できずインライン表示できないため、相対 Markdown リンクを採る。

### 宣言的にできない部分（rclone 認証）は preflight で loud に落とす

Google Drive の OAuth トークンは宣言的に生成できない（対話認証が必要）。この
「宣言的に用意できない要素」を放置してサイレントに半端な同期をしないよう、同期スクリプトの
先頭に**層3 preflight** を置く。順に検知して、復旧手順つきのメッセージで `exit 1` する:

1. （with-rclone-secret）復号鍵が見つからない／復号失敗（受信者未登録）
2. `ZETTELKASTEN_ATTACHMENTS_DIR` 未指定／フォルダ不在
3. `RCLONE_CONFIG` を明示したのにファイル不在
4. remote 名が `rclone listremotes` に無い（未定義）
5. `rclone about` が通らない（token 失効・権限不足）

### 3 層の検知（層1 = eval 時、層3 = 実行時）

- **層1（eval 時 / Nix assertions）**: `hm-module.nix` の `assertions` で
  `attachments.dir != ""` と `attachments.remote` が `remote:folder` 形式かを検査。宣言の抜けを
  rebuild 時点で落とす。
- **層3（実行時 / preflight）**: 上記の rclone 認証まわり。Nix では検知できない
  「実際に token が生きているか」等を実行直前に検査する。

（層2＝activation 時は今回は採らない。認証の有効性は結局 rclone を実行しないと分からず、
層3 に寄せた方が単純なため。）

### `--resync` ガードと watcher の未作成フォルダ耐性（papis と同じ思想）

- 初回 `--resync` は破壊的なので、baseline が既存なら中止する
  （意図的な場合のみ `ZETTELKASTEN_FORCE_RESYNC=1`）。
- watcher は監視対象フォルダが未作成なら正常終了(0)してクラッシュループを避ける
  （添付フォルダは最初の画像貼り付けが作る。モジュールは所有しない）。

## 運用上の性質・既知の制約

- **削除は双方向伝播**。安全網は Drive のゴミ箱と bisync の `--max-delete`（既定 50%）。
- **watcher はローカル変更のみ検知**。他マシンの追加は次回の自分の同期時に pull される。
- **初回 resync は添付が入った状態で**。空ディレクトリでは bisync が baseline を作れない
  （`Empty prior Path1 listing`）。まず Obsidian か img-clip で画像を 1 枚貼ってから resync する。
- **Drive 側フォルダは rclone に作らせる**。scope=`drive.file` では Drive UI で手動作成した
  フォルダが rclone から見えない。初回だけ `rclone mkdir gdrive:zettelkasten-attachments`。
- **flake 評価には workflow flake input が必要**。`flake_public` は
  `github:khimoo/zettelkasten-workflow` を input に持つので、workflow flake
  （`flake.nix` / `nix/`）が push 済みでないと `nix flake lock` が解決できない。
  ローカル検証は `--override-input zettelkasten path:/path/to/zettelkasten-workflow` で回避可能。
- **repo は public**。`github:`（https 取得）で認証なしに取得でき、flake の eval / 取得に
  SSH 鍵は要らない（mechanism を public 分割した狙い。ノート本文は別の private repo
  `khimoo/zettelkasten`）。SSH 鍵を使うのは **runtime の rclone 復号だけ**（各マシンの
  `~/.ssh/id_ed25519` を ssh-to-age 変換）。この ssh-to-age 依存は将来もっと良い形に
  改善したい（→ [復号鍵の設計と将来改善](./papis-gdrive-sync.md#復号鍵は各マシンの-user-ssh-鍵ssh-to-age)）。
