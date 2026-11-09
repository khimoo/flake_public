# Quaderno の取り込みと送信の設計

使い方: [Quaderno の取り込みと送信](../howtouse/quaderno.md)
実装: [quaderno.star](../../config/elements/quaderno.star)、[quaderno_transfer.py](../../modules/home-manager/quaderno_transfer.py)、[quaderno_plan.py](../../modules/home-manager/quaderno_plan.py)、[dpt-rp1-py](../../packages/dpt-rp1-py/)

Fujitsu のクラウド同期は無料枠が 10MB しかなく、使うには有償のプランか、USB で Digital Paper App（Windows と macOS だけ）を使うことになる。
同じ LAN にいるときに取り込めれば、どちらも要らない。
実機での取り込みは動いている（2026-10-23 に、2026-10-19 に更新された `state.json` と 433 MiB のアーカイブを確認）。

## デバイスについて確かめたこと

2026-09-15 に Quaderno A4 Gen2（`model_name` が `FMVDP41`、`sku_code` が `J`）で確かめた。

- 本体は Wi-Fi 上で、HTTPS の REST API を 8443 番、平文の HTTP を 8080 番で出す。`http://<addr>:8080/register/information` は認証なしで `model_name`、`serial_number`、`sku_code`、`device_color` を返す
- ペアリングは [dpt-rp1-py](https://github.com/janten/dpt-rp1-py) の `register` で通り、Digital Paper App は要らない
- 各文書のメタデータの `file_revision`（`ac9116e89ba8.0.845` の形）は、書き込みのたびに変わる。日本語を含むパスもそのまま扱える
- mDNS では `_dp_fujitsu._tcp.local.` として広告され、TXT レコードは空でシリアル番号を含まない。dpt-rp1-py の探索は、各候補の `:8080/register/information` に問い合わせてシリアルを照合する
- 本体がスリープすると Wi-Fi ごと落ち、接続すると `OSError: [Errno 113] No route to host` になる

## dpt-rp1-py は PyPI ではなく master から取る

Gen2 の登録は、PyPI の最新版（0.1.19、2025-10-14）では約半分の確率で失敗する（[issue #134](https://github.com/janten/dpt-rp1-py/issues/134) の `error_code 40301`、[issue #124](https://github.com/janten/dpt-rp1-py/issues/124) の `KeyError: 'a'`）。
本体は Diffie-Hellman の公開値 `yb` を Java の `BigInteger.toByteArray()` で直列化するので、最上位ビットが立つと先頭に `0x00` が付いて 257 バイトになる。dpt-rp1-py はこれを 256 バイトに詰め直して HMAC を計算していたので、本体側の計算と食い違う。
[commit 7a0ef07](https://github.com/janten/dpt-rp1-py/commit/7a0ef077)（2026-07-12）が受け取ったバイト列をそのまま使うよう直したが、この修正を含むリリースは PyPI にまだない。
そこで `packages/dpt-rp1-py/` は rev を固定して GitHub から取る。

## 双方向のマージをしない

dpt-rp1-py の `sync` は双方向のマージで、実行のたびにデバイスの時刻を書き換え、古いほうのファイルを警告なしに上書きする。手元で触った PDF が、デバイス上の注釈入りの版を潰すことがある。
そこで、取り込みと送信を別の場所で行う。取り込みはデバイスの `Document` 以下をアーカイブへ落とすだけで、アーカイブからは送らない。送るのは Send フォルダ（既定は `~/Quaderno/Send`）に置いたファイルだけで、送れたら Send から消す。

アーカイブに置いたものを送る作りにすると、どれが送るべきものかを取り込みの記録（`state.json`）に無いもので決めることになる。記録が消えると、デバイスで消した文書までアーカイブ全体を送り返す。Send フォルダなら、記録が消えても送るものは変わらない。

## 送り先は `Document/Received` にし、同じ名前は英字を付けて分ける

送り先はデバイスに最初からある `Document/Received` で、フォルダを増やさない。
同じ名前の新しい版を何度も送るので、上書きはしない。上書きすると、デバイス上で書き込んだ版が消える。

デバイスは、同じフォルダに同じ名前の文書を作る要求を断る（2026-11-09 に確かめた。`error_code` 40007、`Bad parameter : fileName`）。番号を付け直してはくれない。
そこで送る側で空いている名前を選び、`a (a).pdf`、`a (b).pdf` … と英字を付ける（z の次は aa）。数字にしないのは、デバイスや別の道具が付けた番号と見分けるため。
dpt-rp1-py の `upload` は同じパスの文書を探して中身を差し替えるので使わず、文書を作る要求を直接送る。名前が重なればデバイスが断るので、一覧を取った後に同じ名前ができても上書きしない。

送り先にある名前は、取り込みのために取った文書一覧から知る。そのため送り先は取り込みの対象（`quaderno_remote_root`）の中に限る。

文書を作る要求は HTTP の失敗を例外にしないので、応答を確かめ、送った後にデバイス上のサイズを手元と比べ、一致したときだけ Send から消す。書き込み途中のファイルを送らないよう、更新から 10 秒経っていないファイルは次の回に回す。

## 手元はミラーではなくアーカイブにする

Quaderno は本体の容量が限られるので、読み終えた PDF は本体から消す。手元をミラーにすると、そのとき手元からも消え、取り込む目的がなくなる。
代償として、デバイス上で整理した結果（削除、リネーム、移動）は手元に反映されない。
注釈を足した版は上書きし、世代は残さない。

## 1分ごとに確かめる

Quaderno はスリープすると Wi-Fi ごと消え、起きている短い間しか受け渡しができない。
1時間ごとに試していた 2026-09-15 から 11-09 までは、約1250回のうち接続できたのは22回で、手書きが最長で約8日手元に届かなかった。
そこで 1 分ごとに mDNS で探す。見つからなければ探索の待ち時間（既定 15 秒）で終わる。Quaderno を起こせば、1 分ほどで取り込みと送信が始まる。

## 見つからないことを失敗にしない

定期実行のほとんどは相手が見つからずに終わる。
失敗として扱うと、正常な状態で通知が鳴り続ける。探索の失敗は一行出して 0 で終わり、認証とダウンロードの失敗だけを非 0 にする。

## 機器はシリアルを書かずに mDNS で選ぶ

この環境には機器が 1 台しかないので、既定では mDNS で最初に見つかった Digital Paper に接続し、設定に識別子を持たない。
`quaderno_serial` を書くのは、別の機器へ黙ってつながるのを避けたくなったときでよい。
シリアル番号は同じ LAN から認証なしで読める値なので、公開リポジトリに書いても漏洩には当たらない。書かないのは、書かずに済む値を設定に増やさないため。
認証鍵の `~/.config/dpt/privatekey.dat` はリポジトリに置かない。

## 取り込みの記録はアーカイブの外に置く

`entry_id` から `file_revision` への対応は `$XDG_STATE_HOME/quaderno/state.json` に置く。
アーカイブは手で Google Drive へ上げるので、同期の記録が中身に混ざらないようにする。
各文書は一時ファイルに書いてから rename し、その後で記録を更新する。途中で電源が落ちても書きかけのファイルは残らず、記録されなかった分は次に取り込み直す。

記録はマシンごとに分かれるので、2 台で有効にすると両方が全件を取り込む。取り込みは nixos-desktop の 1 台に限る。

## 取り込み先は SATA の `@backup` にし、vault には置かない

`quaderno_archive` は `/mnt/backup/quaderno` で、ディレクトリは `machine_nixos_desktop` の tmpfiles が作る。`minecraft-backup` と同じく、置き場所と書き込み権限はホストが用意し、モジュールは受け取るだけにする。
PDF は増え続ける一方で読むのは時々なので SATA に置く（最初の 62 件で 428 MiB、[disk-tiering.md](./disk-tiering.md)）。
`~/sagyo/memex`（vault の clone）には置かない。obsidian-git が 2 台で同期しているので、数百 MiB の PDF を持ち込むと同期の対象が膨らむ。

## memex-nix に載せない

workflow 側には vault の資料の Drive 同期があり、取り込み先を vault の下にすれば Drive へ運べる。
しかし既存の同期は `rclone bisync` だけで片方向の `copy` がなく、Drive 側の削除が手元に伝わる。一方向にした判断と合わない。
Drive への同期を自動化するときは、片方向の層を足してから workflow へ移す。
要素はホストの `quaderno_archive` とユーザーのホームを受け取り、`quaderno_archive` に既定値を置かない。失敗の通知は `failure_notify` の公開値を使う。

## まだ分からないこと

- mDNS の広告が、Wi-Fi を入れてから何分後まで続くかは測っていない。Wi-Fi を入れて十数分経っても応答したのは一度の観測で、dpt-rp1-py の README は「数分間だけ有効」と書いている
- dpt-rp1-py は Quaderno Gen2 を公式には対応していない。登録の修正も DPT-RP1 の実機で確かめられたもので、ファームウェアの更新で変わりうる

## 見直す条件

- 登録の修正を含むリリースが PyPI に出たら、rev の固定をやめる
- nixpkgs に dpt-rp1-py が入ったら、`packages/` から消す（2026-09-15 には `python3Packages` になかった）
