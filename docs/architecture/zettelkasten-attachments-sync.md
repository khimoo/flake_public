# Zettelkasten の Google Drive 同期（設計判断）

vault の添付（画像等）と papis ライブラリの実体を Google Drive に置き、ローカルにも残して
rclone bisync でミラーする。git には blob を載せない。

使い方は [../howtouse/zettelkasten-attachments-sync.md](../howtouse/zettelkasten-attachments-sync.md) を参照。

## 責務分離：仕組みは workflow flake、環境固有の配線だけ flake_public

```
khimoo/zettelkasten-workflow (public。ワークフローの仕組みを所有)
├─ nix/hm-module.nix    … 公開面はこの HM モジュール1つ。options { vaultDir, initializeVault,
│                          rcloneRemote, attachments.*, papis.*, obsidian.*, after, wants }
├─ nix/bisync-lib.nix   … bisync 本体(preflight・初回ブートストラップ・resync ガード)
├─ nix/sync-script.nix  … 何をどこへ同期するかを eval 時に焼き込む層 → zettelkasten-sync
├─ nix/sync-job.nix     … 同期 job の OS 非依存定義(systemd / launchd をここ1か所から導出)
├─ nix/setup.nix        … 宣言で届かない残りを進める対話 CLI → zettelkasten-setup
├─ nix/init-vault.nix / seed-obsidian.nix … vault と .obsidian の用意(activation が呼ぶ)
└─ .obsidian/           … 配布する Obsidian 設定と community plugin 本体

flake_public (環境固有の配線だけ注入)
└─ modules/home-manager/zettelkasten.nix … vaultDir / feature toggle / obsidian.mirrorRepo
```

ノート本文は別の private repo `khimoo/zettelkasten`。mechanism を public 分割したことで
flake_public の eval に SSH 鍵は要らない。

## 設計判断

### 認証情報はどちらの repo も持たない（各マシンの rclone.conf に委ねる）

以前は rclone.conf を sops で暗号化して workflow repo にコミットし、同期スクリプトが実行の
たびに `~/.ssh/id_ed25519` を ssh-to-age 変換して復号していた。これを廃止し、各マシンで
`rclone config` が作る `~/.config/rclone/rclone.conf` に委ねている。

理由は **第三者が自分の Drive で使えること**。暗号文を repo に載せる形は所有者専用
（single-tenant）で、fork した人は `.sops.yaml`・暗号文・受信者を全部差し替える必要があった。
rclone 既定の解決に委ねれば、`rclone config` を 1 回やるだけで誰でも自分の Drive に繋がる。

副次的に、受信者管理（マシン追加のたびの `sops updatekeys`）・復号鍵の順序問題
（fresh マシンでは SSH 鍵自体が activation で復号されて初めて置かれる）・平文の一時ファイルが
まとめて消えた。代償は「rclone config を 1 回手でやる」ことだが、OAuth はもともと宣言的に
生成できないので、隠していただけで無くなってはいなかった。

### 同期コマンドは 1 本、対象は eval 時に焼き込む

`zettelkasten-sync` 1 本が添付と papis の両方を回す（`--only` で片方に絞れる）。同期先は
options から eval 時に焼き込まれ、実行時に設定を読む層は無い。設定の出所を flake ただ 1 つに
保ち、解決順を 1 段にするため。有効でない対象はコードが生成されないので、papis を使わない
環境に papis の分岐は存在しない。

baseline（bisync の記録）は対象ごとに隔離する（`~/.cache/rclone/bisync-zettelkasten` と
`bisync-papis`）。同一 remote でも別フォルダを同期するので、記録を混ぜない。

### 初回同期は「失うものが無いなら自動、曖昧なら止める」

bisync は初回だけ `--resync` が要るが、これは破壊的操作なので誰かが判断しなければならない。
判断が要るのは **両側に中身があるとき** だけ、というのがこの実装の立場:

- Drive 側が空/未作成 … フォルダを作って resync（失うものが無い）
- ローカルが空 … Drive から取り込む（新マシンの合流。失うものが無い）
- 両側に中身がある … 中止して `ZK_FORCE_RESYNC=1` を要求する

以前は全ケースで手動 `--resync` を要求していた。自動化できるケースまで人間に投げると、
手順書が長くなるだけで安全性は上がらない。非対話（systemd）でも安全に止まることだけを
`bisync-lib` が保証し、対話で聞くのは `zettelkasten-setup` の役目、と層を分けている。

### トリガーは OS 純正のイベント + 定期バックストップ（watcher を常駐させない）

以前は watchexec を常駐させて再帰監視していたが、systemd の path unit（`PathModified`）と
launchd の `WatchPaths` で oneshot を起動する形に変えた。常駐プロセスが消え、Linux と macOS の
分岐が `nix/sync-job.nix` 1 か所に閉じる。

代償は **path unit がディレクトリを再帰監視しないこと**。papis の item フォルダ内部の変更は
イベントでは拾えないので、定期実行（既定 15 分）をバックストップとして併走させる。
「イベントは速いが取りこぼす / 定期は遅いが漏れない」を組み合わせて、どちらか一方に
寄せない。

### 宣言的にできない部分は実行前に loud に落とす

OAuth トークンは宣言的に生成できない。この「宣言で用意できない要素」を放置してサイレントに
半端な同期をしないよう、同期の先頭で順に検知し、復旧手順つきのメッセージで落とす:

1. `RCLONE_CONFIG` を明示したのにファイルが無い
2. remote 名が `rclone listremotes` に無い（未定義）
3. `rclone about` が通らない（token 失効・権限不足）

eval 時（Nix の `assertions`）で見られるのは `vaultDir` が絶対パスかどうか程度で、
「token が生きているか」は実行しないと分からない。だから検査を実行直前に寄せている。

### 実体はローカル保持 + Drive ミラー（Drive を唯一の置き場にしない）

Obsidian も Neovim（画像インライン表示）もローカルのファイルパスを解決するので、実体が
ローカルにある方が速く、オフラインでも動く。Drive を唯一の実体置き場（rclone mount）に
すると、レイテンシとマウント依存が増え、ネットワーク断で編集が止まる。

### blob は git から除外（ノートはファイル名参照で辿る）

添付と papis ライブラリは vault の `.gitignore` で除外し、Drive で同期する。ノートは
wikilink `![[filename]]` か相対リンクでファイル名を参照するだけなので、blob が git に
無くてもリンクは切れない。git 履歴が画像バイトで膨らむのを避ける。

### フォルダ名は規約で固定（`attachments/` と `references/`）

vault 内のパスは options にしていない。配布する `.obsidian/app.json` の
`attachmentFolderPath` と食い違わせないため。可変にする利益が無い。

img-clip 側も保存先を `~/sagyo/zettelkasten/attachments` にハードコードして一致させている
（`relative_to_current_file = false`。副作用として zettelkasten 以外の vault で貼っても
ここに保存される）。挿入されるリンクは相対 Markdown リンクにする——wikilink だと image.nvim が
treesitter で画像ノードとして認識できずインライン表示できないため。

## 運用上の性質・既知の制約

- **削除は双方向伝播**。安全網は Drive のゴミ箱と bisync の `--max-delete`（既定 50%）
- **イベント検知はローカル変更のみ**。他マシンの追加は次回の自分の同期時に pull される
- **Drive 側フォルダは rclone に作らせる**。scope=`drive.file` では Drive UI で手動作成した
  フォルダが rclone から見えない（初回同期が自動で `rclone mkdir` する）
- **ローカル検証は `--override-input`**。workflow flake を編集中に flake_public 側を試すときは
  `--override-input zettelkasten path:/path/to/zettelkasten-workflow` で差し替える
