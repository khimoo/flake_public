# Zettelkasten の Google Drive 同期の設計

使い方: [Zettelkasten の Google Drive 同期](../howtouse/zettelkasten-attachments-sync.md)
実装: mechanism は zettelkasten-workflow（`nix/hm-module.nix`、`nix/bisync-lib.nix`、`nix/sync-job.nix`、`nix/setup.nix`）、このリポジトリの配線は [zettelkasten.nix](../../modules/home-manager/zettelkasten.nix)

vault の添付と papis のライブラリは、git ではなく Google Drive と rclone bisync で同期する。
同期の仕組みは public の zettelkasten-workflow に置き、このリポジトリは vault の場所、機能の選択、写し先だけを渡す。仕組みを public に分けたので、このリポジトリの評価に SSH 鍵が要らない。ノートの本文は private の `khimoo/zettelkasten` にある。

## 認証情報はどちらの repo も持たない（各マシンの rclone.conf に委ねる）

Google Drive の認証は、各マシンで `rclone config` が作る `~/.config/rclone/rclone.conf` に任せる。
sops で暗号化した rclone.conf を workflow repo に置く案は退けた。持ち主だけが使える形になり、fork した人は `.sops.yaml`、暗号文、受信者の鍵をすべて差し替えることになる。rclone の設定の探し方に任せれば、誰でも `rclone config` を 1 回実行するだけで自分の Drive につながる。
受信者の管理、復号の鍵の順序（新しいマシンでは SSH 鍵自体が activation で復号されて初めて置かれる）、平文の一時ファイルの扱いもなくなる。
OAuth のトークンはもともと宣言的に作れないので、`rclone config` を手で実行する手間は以前も実質的にはあった。

## 同期コマンドは 1 本にし、対象は評価時に決める

`zettelkasten-sync` 1 本で全部の対象を同期し、`--only` で絞る。同期先は評価時にコードへ埋め込み、実行時に設定ファイルを読まない。設定の正本を flake の一か所にするため。無効な対象のコードは生成しない。
同期の履歴（baseline）は対象ごとにディレクトリを分ける（`~/.cache/rclone/bisync-zettelkasten`、`bisync-papis`）。同じリモートの違うフォルダを同期するので、履歴が混ざらないようにする。

## 最初の resync は、安全なら自動、判断が要るなら止める

bisync の最初の `--resync` は壊す可能性があるが、判断が要るのは手元と Drive の両方にデータがあるときだけと定めた。
Drive が空か手元が空なら失うものがないので自動で進め、両方にあるときだけ止めて `ZK_FORCE_RESYNC=1` を求める。
自動にできる場面まで利用者に任せると、手順書が長くなるだけで安全にはならない。systemd のような対話のない環境で安全に止まることは `bisync-lib` が保証し、対話での確認は `zettelkasten-setup` が受け持つ。

## 変更の監視は path unit と定期実行を併用する

systemd の path unit（`PathModified`）と launchd の `WatchPaths` で、変更があったら oneshot で同期する。常駐の監視プロセス（watchexec）は要らず、Linux と macOS の違いは `nix/sync-job.nix` に閉じる。
path unit はディレクトリを再帰的に監視しないので、papis のアイテムのフォルダの中の変更などは拾えない。そのため 15 分ごとの定期実行も併用する。

## 宣言できないものは、同期の直前に分かりやすく止める

OAuth のトークンは宣言で用意できない。中途半端な同期が黙って走らないよう、同期の最初に次を確かめ、直し方を出して止める。

1. `RCLONE_CONFIG` を指定しているのに、そのファイルがない
2. リモート名が `rclone listremotes` にない
3. `rclone about` が失敗する（トークンの期限切れ、権限の不足など）

評価時の `assertions` で確かめられるのは、`vaultDir` が絶対パスかどうかのような静的な設定だけで、トークンが有効かどうかは実行しないと分からない。

## 実体は手元に置き、Drive へ写す

Obsidian も Neovim（画像のインライン表示）も手元のパスを読むので、実体が手元にあれば軽く、オフラインでも使える。Drive だけに置いて rclone mount で使う形は、遅延とマウントへの依存が増え、ネットワークが切れると編集できない。
バイナリは git から外し、ノートはファイル名（`![[filename]]` や相対パス）で参照する。git の履歴が画像で膨らまない。

## フォルダ名は `Assets/attachments/` と `Assets/references/` に固定する

配る `.obsidian/app.json` の `attachmentFolderPath` と食い違わないよう、vault の中のパスはオプションにしない。

## Originals は退避を足し、自動で resync しない

Originals も同じ rclone bisync を使い、専用の同期先と baseline を足す。独自のマージや台帳は持たない。
競合したときは、Originals だけ `conflict-resolve none` と `conflict-loser num` で両方の版を残す。attachments と papis の設定と baseline はそのまま。画像のようなバイナリを自動でマージしない。

消えたり上書きされたりする版は、同期の対象の外の退避先へ移す。退避先は手元と Drive の両方に、ホストと実行ごとに分けて置く。同じアカウント全体を失うことへの備えではない。
初期化のときも履歴を失ったときも自動では resync せず、手で差分を確かめて退避してから、対象だけを初期化する。

`--recover --max-lock 2m` で、強制終了などで残ったロックは約 2 分で切れ、次の同期が直前の成功した履歴から復旧を試みる（[recover](https://rclone.org/bisync/#recover)、[max-lock](https://rclone.org/bisync/#max-lock)）。ロックを消したり自動で resync したりする処理は書かない。
2 台の PC はそれぞれ別の同期履歴を持ち、手元のロックをホストの間の排他には使わない。

2026-10-19 に、実際の Google Drive と 2 台の PC で、追加、競合、退避、復元、多重の実行、強制終了の後の復旧を確かめ、本番の原本 2 点の SHA-256 を照合して、両方の PC の初期化と通常の同期が通ったので `originals.autoSync = true` にした。
オフラインからの復帰は、同期の前に両方の PC で変更する形で確かめただけで、実際にネットワークを切ったり長く止めたりした状態は確かめていない。

## 運用上の性質

- 削除は双方向に伝わる。Google Drive のごみ箱と bisync の `--max-delete`（既定 50%）で守る
- 変更の監視は手元の操作だけを見る。ほかのマシンで足したファイルは次の同期で取り込む
- `drive.file` のスコープでは、Drive の Web UI で手で作ったディレクトリは rclone から見えない。最初の同期で `rclone mkdir` する
