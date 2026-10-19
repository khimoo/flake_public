# Zettelkasten の Google Drive 同期（設計方針）

vault の添付ファイル（画像など）や papis ライブラリの実体は Google Drive に配置し、ローカルにも保持して rclone bisync で双方向ミラーリングします。サイズを問わず、これらの添付ファイルや文献の実体ファイルを git で管理することはありません。

具体的な使い方は [../howtouse/zettelkasten-attachments-sync.md](../howtouse/zettelkasten-attachments-sync.md) を参照してください。

## 責務の分離：仕組みは workflow flake、環境固有の配線のみ flake_public

```
khimoo/zettelkasten-workflow (public: ワークフローの仕組み本体を管理)
├─ nix/hm-module.nix    … 公開インターフェースとなる単一の HM モジュール。options { vaultDir, initializeVault,
│                          rcloneRemote, attachments.*, papis.*, obsidian.*, after, wants }
├─ nix/bisync-lib.nix   … bisync のコア処理（preflight、初回ブートストラップ、resync ガード）
├─ nix/sync-script.nix  … 同期対象と同期先を eval 時に埋め込む層 → zettelkasten-sync
├─ nix/sync-job.nix     … 同期ジョブの OS 非依存な定義（systemd / launchd の設定をここから一元生成）
├─ nix/setup.nix        … 宣言的設定でカバーできない処理を行う対話型 CLI → zettelkasten-setup
├─ nix/init-vault.nix / seed-vault.nix … vault と骨格の準備（activation 時に呼び出し）
├─ nix/skeleton-paths.nix … 骨格として配布するファイル/フォルダの allowlist（mirror-vault が利用）
└─ skeleton/            … 配布する骨格データ（分類フォルダ、運用ドキュメント、.obsidian）

flake_public (環境固有の配線のみを注入)
└─ modules/home-manager/zettelkasten.nix … vaultDir / feature toggle / mirrorRepo
```

ノート本文は別の private リポジトリ `khimoo/zettelkasten` で管理しています。仕組み（mechanism）を public リポジトリに切り離したことで、flake_public の eval 時に SSH 鍵を要求されなくなりました。

## 設計判断

### 認証情報はどちらの repo も持たない（各マシンの rclone.conf に委ねる）

以前は rclone.conf を sops で暗号化して workflow リポジトリにコミットし、同期スクリプトの実行ごとにユーザーの SSH 鍵を ssh-to-age で変換して復号していました。この仕組みを廃止し、現在は各マシンで `rclone config` によって生成される `~/.config/rclone/rclone.conf` に管理を委ねています。

その理由は、**第三者が各自の Google Drive で利用できるようにするため**です。暗号化ファイルをリポジトリに含めるアプローチは所有者専用（シングルテナント）になってしまい、リポジトリをフォークした利用者が `.sops.yaml`、暗号文、受信者鍵をすべて差し替える必要がありました。rclone 本来の設定解決に委任すれば、ユーザーが `rclone config` を 1 回実行するだけで自身の Google Drive に接続できます。

副次的な効果として、受信者管理（マシン追加ごとの `sops updatekeys`）や、復号鍵の依存順問題（新規マシンでは SSH 鍵自体が activation による復号を経て初めて配置される）、平文の一時ファイルの取り扱いといった課題が一挙に解消されました。その代償として「初回に `rclone config` を手動実行する」手間が生じますが、そもそも OAuth トークンは宣言的に生成できないため、以前の手法も見かけ上隠蔽していたに過ぎませんでした。

### 同期コマンドを 1 本に集約し、対象は eval 時に確定させる

1 本の `zettelkasten-sync` コマンドで、添付ファイルと papis の両方を同期します（`--only` オプションで片方のみに絞ることも可能です）。同期先は options から eval 時にコードへ直接埋め込まれ、実行時に設定ファイルを読み込む層は設けていません。設定のソースを flake の 1 か所のみに絞り、解決ステップをシンプルにするためです。無効化されている対象のコードは生成されないため、papis を使用しない環境には papis 向けの分岐処理自体が存在しません。

ベースライン（bisync の同期履歴）は、対象ごとにディレクトリを分離しています（`~/.cache/rclone/bisync-zettelkasten` および `bisync-papis`）。同じリモートであっても異なるフォルダを同期するため、履歴情報の混信を防ぎます。

### 初回同期は「安全が自明なら自動実行、判断がつかなければ停止」

bisync では初回実行時のみ `--resync` が必要ですが、これは破壊的な変更を伴う可能性があるため、慎重な判断が求められます。当実装では、判断が必要になるのは**「ローカルとリモートの双方にデータが存在する場合」のみ**と定めています。

- Drive 側が空または未作成：フォルダを作成して自動で resync（データ損失リスクがないため）
- ローカル側が空：Drive からデータを取得（新規マシンのセットアップであり、データ損失リスクがないため）
- 双方にデータが存在する：処理を中断し、明示的に `ZK_FORCE_RESYNC=1` の指定を要求

以前はあらゆるケースで手動の `--resync` を要求していましたが、自動化できる安全なケースまでユーザーに委ねてしまうと、手順書が徒長するばかりで実質的な安全性は向上しません。非対話環境（systemd）でも安全に停止することのみを `bisync-lib` で保証し、ユーザーへの対話的な確認は `zettelkasten-setup` が担当するというように責務を分離しています。

### トリガーには OS 標準のイベント監視と定期実行を併用（常駐 watcher を廃止）

以前は watchexec を常駐させて再帰的なファイル監視を行っていましたが、現在は systemd の path unit（`PathModified`）や launchd の `WatchPaths` を利用して oneshot でスクリプトを呼び出す構成に変更しました。これにより常駐プロセスが不要になり、Linux と macOS の環境差異を `nix/sync-job.nix` の 1 か所に集約できています。

一方で、**path unit はディレクトリの再帰監視に対応していない**という制約があります。そのため、papis の各アイテムフォルダ内部の変更などはイベントだけでは検知できません。これを補うため、フォールバックとして定期同期（デフォルト 15 分間隔）をバックストップとして並行稼働させています。「即応性はあるが取りこぼしがあるイベント監視」と「即応性はないが確実な定期同期」を組み合わせることで、双方の欠点を補完しています。

### 宣言的に設定できない項目は、実行直前にわかりやすく失敗させる

OAuth トークンを宣言的に生成することはできません。このように宣言的に用意できない要素を放置した結果、中途半端な同期がサイレントに実行されるのを防ぐため、同期処理の冒頭で以下の項目を順次チェックし、復旧手順のメッセージを出力して直ちに終了させます。

1. `RCLONE_CONFIG` を明示指定しているにもかかわらず、ファイルが存在しない場合
2. 対象のリモート名が `rclone listremotes` の結果に含まれていない（未定義の）場合
3. `rclone about` が失敗する場合（トークンの期限切れ、権限不足など）

Nix の eval 時点（`assertions`）で検証できるのは `vaultDir` が絶対パスであるかといった静的な設定程度であり、「トークンが有効かどうか」は実際に実行してみなければ判断できません。そのため、こうした検証を実行直前のステップに集約しています。

### 実体ファイルはローカルに保持して Drive へミラー（Drive 単体を正としない）

Obsidian も Neovim（画像のインライン表示）もローカルのファイルパスを直接参照するため、実体ファイルがローカルに存在する構成のほうが動作が軽快で、オフラインでも問題なく利用できます。Drive のみを唯一の実体置き場（rclone mount によるマウント運用）にしてしまうと、アクセス遅延やマウント処理への依存が増大し、ネットワーク切断時に編集作業が停止してしまいます。

### バイナリデータ（blob）は git の追跡から除外（ノートからはファイル名で参照）

添付ファイルや papis のライブラリは vault の `.gitignore` で除外した上で、Google Drive を介して同期します。ノート側からはウィキリンク `![[filename]]` や相対パスによってファイル名を参照するだけなので、git 管理下にバイナリデータが存在しなくてもリンクが途切れることはありません。これにより、画像のバイナリデータで git の履歴が肥大化するのを防いでいます。

### フォルダ名は規約として固定（`attachments/` と `references/`）

vault 内のパスは設定オプションとして公開していません。配布している `.obsidian/app.json` 内の `attachmentFolderPath` と不整合を起こさないようにするためであり、ここを可変にするメリットがないためです。

また、img-clip 側の保存先設定も `~/sagyo/zettelkasten/attachments` にハードコードしてパスを一致させています（`relative_to_current_file = false`。副作用として、zettelkasten 以外の vault で画像を貼り付けた場合もこのフォルダに保存されます）。挿入されるリンクには相対パス形式の Markdown リンクを採用しています。これは、ウィキリンク形式だと image.nvim が treesitter 上で画像ノードとして認識できず、インライン表示が機能しなくなるためです。

## 運用上の特性と既知の制約

- **削除操作は双方向に同期されます**。安全対策として、Google Drive のゴミ箱機能および bisync の `--max-delete`（デフォルト 50%）を設けています。
- **ファイル変更の検知はローカルの操作のみが対象です**。他のマシンで追加されたファイルは、自身の次回同期処理の実行時に pull されます。
- **Google Drive 側のディレクトリは rclone 経由で作成する必要があります**。`drive.file` スコープを使用している場合、Drive の Web UI から手動で作成したディレクトリは rclone から認識できません（初回の同期時に自動で `rclone mkdir` が実行されます）。
- **ローカルでの動作検証には `--override-input` を使用します**。workflow flake の修正内容を flake_public 側でテストする際は、`--override-input zettelkasten path:/path/to/zettelkasten-workflow` を指定して参照先を差し替えてください。

## Originals の同期設計

Originals では `--recover --max-lock 2m` を使用します。プロセスが強制中断された場合などに残るロックは、最終更新から約 2 分で期限切れとなり、以降の通常同期によって直近の正常履歴からのリカバリが試みられます。同期スクリプト側には、ロックの自動削除や自動 resync といった処理は実装していません。履歴の欠損やリカバリの失敗が発生した場合は処理を停止し、手動での調査を行います。詳細は [rclone の復旧仕様](https://rclone.org/bisync/#recover) および [ロック期限の仕様](https://rclone.org/bisync/#max-lock) を参照してください。

基盤には既存と同じ rclone bisync 本体を採用し、Originals 専用の同期ターゲットとベースラインを追加しています。独自の差分マージ処理や管理台帳などは保持しません。通常のファイル競合が発生した場合、Originals のみ `conflict-resolve none` および `conflict-loser num` を適用して両方のバージョンを残すようにし、attachments や papis の既存設定とベースラインはそのまま維持します。画像などのバイナリ内容を自動でマージすることはありません。

削除や上書きによって失われるバージョンは、同期対象外の退避領域へ隔離します。退避先はローカルとリモートの双方に設け、ホスト別かつ実行世代ごとに分離して管理します。削除操作自体は通常通り同期されますが、消去されるバージョンは同期処理によって自動的に退避されます。ただし、これは同一アカウント全体の喪失に備えるようなバックアップではありません。また、初期化時や履歴喪失時にも自動で resync は行わず、手動で差分確認や退避を実施した上で、対象のデータのみを初期化します。

利用環境では、`zettelkastenSync` が有効になっている場合に Originals コマンドを有効化します。2026-10-19 に実際の Google Drive および 2 台の PC 環境下で、追加・競合・退避・復元・重複実行、ならびに強制中断後の復旧検証を実施しました。本番の原本 2 点の SHA-256 ハッシュ照合、両 PC の初期化および通常同期の正常完了を確認できたため、`originals.autoSync = true` を適用しています。既存の添付ファイル・文献向けジョブはそのまま継続して稼働します。なお、オフラインからの復帰検証は「同期前に双方の PC で変更を加える」方式で行っており、実際のネットワーク切断や長期間の停止状態を再現した検証は未実施です。また、2 台の PC はそれぞれ独立した同期履歴を保持しており、ローカルのロック状態をホスト間の排他制御としては扱いません。

競合発生によって元のファイル名が失われた場合は、保持された双方のファイル内容を確認し、参照リンクを手動で修正してください。導入および復旧の手順については [使い方](../howtouse/zettelkasten-attachments-sync.md#originalsの導入と復旧) を、仕様の詳細は [rclone bisync](https://rclone.org/bisync/) を参照してください。
