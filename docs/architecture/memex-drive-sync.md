# memex の Google Drive 同期の設計

使い方: [memex の Google Drive 同期](../howtouse/memex-drive-sync.md)
実装: mechanism は memex-nix（`nix/hm-module.nix`、`nix/sync-script.nix`、`nix/validate-sync.py`、`nix/bisync-lib.nix`、`nix/sync-job.nix`、`nix/setup.nix`）、このリポジトリの配線は [memex.nix](../../modules/home-manager/memex.nix)

vault の中で git に載せない資料（貼り付けた画像、読書用の PDF など）は、Google Drive と rclone bisync で同期する。
同期の仕組みは public の memex-nix に置き、このリポジトリは vault の場所と機能の選択だけを渡す。仕組みを public に分けたので、このリポジトリの評価に SSH 鍵が要らない。ノートの本文は private の `khimoo/memex` にある。

## 認証情報はどちらの repo も持たない（各マシンの rclone.conf に委ねる）

Google Drive の認証は、各マシンで `rclone config` が作る `~/.config/rclone/rclone.conf` に任せる。
sops で暗号化した rclone.conf を workflow repo に置く案は退けた。持ち主だけが使える形になり、fork した人は `.sops.yaml`、暗号文、受信者の鍵をすべて差し替えることになる。rclone の設定の探し方に任せれば、誰でも `rclone config` を 1 回実行するだけで自分の Drive につながる。
OAuth のトークンはもともと宣言的に作れないので、`rclone config` を手で実行する手間は避けられない。

## 同期する資料は vault のホワイトリストで選ぶ

以前は `Assets/attachments/`、`Assets/references/`（papis のライブラリ）、`Assets/Originals/` の 3 フォルダを、それぞれ別の Drive フォルダへ同期していた。
この形では「資料をどこに置くか」と「Drive で同期するか」が結び付き、同期したい資料は 3 フォルダのどれかに置くしかなかった。papis をやめた（2026-11-06、手で使っておらず、エージェント向けの登録の手間だけが残っていた）ことで references を置く理由もなくなった。

そこで vault 全体を 1 つの Drive フォルダ（`memex-files`）と bisync し、対象は vault 直下の `.drive-sync-filter`（rclone のフィルタ構文、最後は `- **`）で選ぶ。
フィルタは vault の git に載るので、両 PC で同じ対象を同期する。実行時に読むので、対象を変えても switch は要らない。

フィルタはファイル名ではなくパターンで書く（例: `+ /Knowledge/Reading/**.pdf`）。
rclone bisync はフィルタの内容が変わると通常の同期を止め、`--resync` を要求する。ファイル名で列挙すると、資料を足すたびに両 PC で resync が要る。

## resync は自動で行わない

同期の履歴（baseline）がないとき、`memex-sync` は止まり、手で `--resync` を求める。履歴があるのに `--resync` するときは `MEMEX_FORCE_RESYNC=1` も要る。
resync は両側の和集合を作るので、片方の古い版や消したはずのファイルが戻りうる。どちらが正しいかはプログラムには決められない。

## 消える版と競合した版は退避する

`--conflict-resolve none` と `--conflict-loser num` で、競合したときは両方の版を残す。画像や PDF を自動でマージしない。
消えたり上書きされたりする版は、同期の対象の外の退避先へ移す。手元は `${XDG_DATA_HOME}/memex/files-backups/<host>/<runid>`、Drive は `memex-files-backups/<host>/<runid>`。同じアカウント全体を失うことへの備えではない。

`--resilient --recover --max-lock 2m` で、強制終了などで残ったロックは約 2 分で切れ、次の同期が直前の成功した履歴から復旧を試みる（[recover](https://rclone.org/bisync/#recover)、[max-lock](https://rclone.org/bisync/#max-lock)）。
2 台の PC はそれぞれ別の同期履歴を持ち、手元のロックをホストの間の排他には使わない。

## 変更の監視は貼り付け先だけにし、残りは定期実行で拾う

systemd の path unit（`PathModified`）と launchd の `WatchPaths` は、ディレクトリを再帰的に監視しない。vault 直下を監視しても、`Knowledge/Reading/` の中の変更は拾えない。
すぐに同期したいのは Obsidian に貼り付けた画像だけなので、監視するのは `Assets/attachments/` だけにし、それ以外は 15 分ごとの定期実行で同期する。

## 宣言できないものは、同期の直前に分かりやすく止める

接続の前に、フィルタの欠落、不正な構文、最後の `- **` の欠落を確かめて止める。続けて、`RCLONE_CONFIG` のファイルの有無、リモート名、`rclone about` の成否を確かめ、直し方を出して止める。
評価時の `assertions` で確かめられるのは、`vaultDir` が絶対パスかどうかのような静的な設定だけで、トークンが有効かどうかは実行しないと分からない。

## 実体は手元に置き、Drive へ写す

Obsidian も Neovim（画像のインライン表示）も手元のパスを読むので、実体が手元にあれば軽く、オフラインでも使える。Drive だけに置いて rclone mount で使う形は、遅延とマウントへの依存が増え、ネットワークが切れると編集できない。
同期する資料は vault の `.gitignore` で git から外す。git の履歴が画像や PDF で膨らまない。

## 運用上の性質

- 削除は双方向に伝わる。Google Drive のごみ箱、bisync の `--max-delete`（既定 50%）、上の退避先で守る
- 変更の監視は手元の操作だけを見る。ほかのマシンで足したファイルは次の同期で取り込む
- `drive.file` のスコープでは、Drive の Web UI で手で作ったディレクトリは rclone から見えない
