# memex の Google Drive 同期の設計

使い方: [memex の Google Drive 同期](../howtouse/memex-drive-sync.md)
実装: mechanism は memex-nix（`nix/sync-script.nix`、`nix/setup.nix`、`nix/rclone-lib.nix`、`nix/sync-job.nix`、`nix/hm-module.nix`）、このリポジトリの配線は [memex.star](../../config/elements/memex.star)

vault のノートは Git で、画像や PDF などのバイナリは git-annex で中身を Google Drive に置き、Git には所在だけを入れる。
同期の仕組みは public の memex-nix に置き、このリポジトリは vault の場所と機能の選択だけを渡す。ノートの本文は private の `khimoo/memex` にある。

## 目指す状態

2026-11-06 に次の状態を目指すと決めた。

1. 各ファイルの保存先（Git、Drive、その PC のみ）は1か所の宣言で決まり、両方に入ることもどこにも入らないことも起きない。
2. 置き場所を選ぶときに、同期のことを考えなくてよい。
3. Drive に置くのは宣言で選んだものだけで、宣言で決まらないファイルは黙って同期されない。
4. 宣言を変えても、各 PC は人の操作なしで追いつく（電源が切れていた PC は再接続後に）。
5. 保存先を変えたファイルは、新しい保存先に保存されたのを確かめてから古い側を整理する。退避と Git の履歴は対象外。
6. 日常の作業は、ファイルを置くこととノートを書くことだけ。

Drive の画面でファイル名のまま見られること（スマホで PDF を開く、バックアップを目で確かめる）は、後から足す要件として扱う。

## rclone bisync をやめた理由

以前は vault 全体を rclone bisync で Drive と同期し、対象をフィルタで選んでいた。
bisync は、フィルタを通したファイル一覧を前回と比べて削除を判断する。そのためフィルタを変えると比べられなくなり、各 PC で手で `--resync` するまで止まる（4 に反する）。これは bisync の作りから来ていて、上に手順を足しても残る。
また、Git の除外（`.gitignore`）とフィルタの2か所を手で合わせていた（1 に反する）。

## 保存先は中身で決める

`.gitattributes` の `annex.largefiles=(largerthan=0)and(not((mimeencoding=us-ascii)or(mimeencoding=utf-8)))` で、テキスト（us-ascii、utf-8）と空のファイルは Git、それ以外は git-annex に入る。どのファイルもどちらかに決まるので、宣言で決まらないファイルは出ない（3）。置き場所は関係しない（2）。
`mimeencoding=binary` だけを条件にすると、Typst が出す PDF（libmagic の判定は `unknown-8bit`）が Git に入る。空のファイルは libmagic が `binary` と判定するので、`largerthan=0` で除く（2026-11-06 の移行で見つけた）。
`.obsidian/**` だけは `annex.largefiles=nothing` で Git に入れる。プラグインの wasm などが clone だけで揃わないと、中身が届くまで Obsidian のプラグインが動かない。
その PC だけに置くものは、今までどおり `.gitignore` に書く。`.gitignore` は「管理しない」、`.gitattributes` は「管理するものの行き先」で、役割が重ならない（1）。

普通の `git add` で git-annex に入るよう、作業ツリーには普通のファイルとして置く（`annex.addunlocked`）。Obsidian と obsidian-git は何も変えずに使える。
`annex.thin`（作業ツリーと `.git/annex/objects` を hardlink で共有する設定）は使わない。Drive へ送る前にファイルを上書きすると、古い版の唯一の中身も書き換わり、退避できなくなる。バイナリは各 PC に2部置かれる。

`.gitignore` は追跡中のファイルには効かない（Git の仕様）。追跡中のファイルを「その PC だけ」にするには、`git rm --cached` で追跡から外す。`memex-sync` は、`.gitignore` に当たるのに追跡中のファイルを見つけると失敗にして知らせる（3）。

## 規則と実際の保存先を合わせる

`annex.largefiles` は新しく追加したファイルにだけ効き、`git add --renormalize` でも既存のファイルは移らない（2026-11-06 に確かめた）。
規則を変えた後や、git-annex の無い環境で commit されたファイルは、規則と違う側に残る。
`memex-sync` は前回確かめた commit からの差分と前回保留したファイル（`.gitattributes` が変わったときは全ファイル）を見て、規則と違うファイルを git-annex の公式の変換手順（[largefiles](https://git-annex.branchable.com/tips/largefiles/)）で移し、そのファイルだけを commit する（4、5）。push は利用者に任せる。
利用者が編集中のファイルは移さない。移すと、その編集まで自動の commit に入る。中身がまだ届いていないファイルも、種類を判定できないので保留する。どちらも次の実行で見直す。

## 中身の同期

`git annex sync --only-annex --content` で、git-annex ブランチと中身を origin（GitHub）と Drive の間で同期する。ノートのブランチ（main）の pull と push はしない。
`sync --content` は今のファイルの中身しか扱わないので、続けて `git annex copy --all --to gdrive` で、消したファイルや古い版の中身も Drive に送る。他の PC から古い版を取ったり、手元から消したりはしない。
どの PC がどの中身を持つかは git-annex ブランチに記録されるので、PC ごとの一覧を比べる仕組みがない。オフラインだった PC も次の実行で追いつく（4）。

Drive の保存先は git-annex の `backup` グループで、消したファイルや古い版の中身も保持する。これが退避の役になる。
各 PC は `client` グループで、今のファイルの中身だけを持つ。

Drive へは rclone の `rclone gitannex` を通して置く（git-annex の `type=rclone`）。認証は各マシンの `~/.config/rclone/rclone.conf` にあり、どちらの repo も持たない。
Drive 上のファイルは中身のハッシュ名で保存される。名前を混ぜると、名前を変えるたびに別ファイル扱いになるため。

## 変更の監視

`sync.autoSync` のとき、`.git/logs/HEAD`（commit、pull、checkout のたびに追記される）の変更と 15 分ごとの定期実行で `memex-sync` を起動する。
中身を送れるのは commit 済みのファイルだけで、届いた所在から中身を取れるのは pull の後なので、作業ツリーではなく HEAD の reflog を見る。

## git-annex を PATH に入れる

git-annex で初期化した vault では、Git が add や status のたびに git-annex の filter を呼ぶ。git-annex が PATH に無い環境で Git を操作すると失敗する。
memex-nix は git-annex を home の PATH と、Obsidian の起動環境（obsidian-git が Git を呼ぶ）の両方に入れる。vault を git-annex で初期化するのは、この switch の後にする。
