# Quaderno の取り込みの設計

使い方: [Quaderno の取り込み](../howtouse/quaderno.md)
実装: [quaderno.nix](../../modules/home-manager/quaderno.nix)、[quaderno_pull.py](../../modules/home-manager/quaderno_pull.py)、[dpt-rp1-py](../../packages/dpt-rp1-py/)

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

## 取り込み専用にする

デバイスから手元への一方向だけを作り、手元からは書き戻さない。
dpt-rp1-py の `sync` は双方向のマージで、実行のたびにデバイスの時刻を書き換え、古いほうのファイルを警告なしに上書きする。手元で触った PDF が、デバイス上の注釈入りの版を潰すことがある。
一方向なら、デバイス側が壊れることはない。手元から送る必要があれば、`dptrp1 upload` を手で実行する。

## 手元はミラーではなくアーカイブにする

Quaderno は本体の容量が限られるので、読み終えた PDF は本体から消す。手元をミラーにすると、そのとき手元からも消え、取り込む目的がなくなる。
代償として、デバイス上で整理した結果（削除、リネーム、移動）は手元に反映されない。
注釈を足した版は上書きし、世代は残さない。

## 見つからないことを失敗にしない

Quaderno はスリープすると Wi-Fi ごと消えるので、定期実行のほとんどは相手が見つからずに終わる。
失敗として扱うと、正常な状態で通知が鳴り続ける。探索の失敗は一行出して 0 で終わり、認証とダウンロードの失敗だけを非 0 にする。

## 機器はシリアルを書かずに mDNS で選ぶ

この環境には機器が 1 台しかないので、既定では mDNS で最初に見つかった Digital Paper に接続し、設定に識別子を持たない。
`serial` を書くのは、別の機器へ黙ってつながるのを避けたくなったときでよい。
シリアル番号は同じ LAN から認証なしで読める値なので、公開リポジトリに書いても漏洩には当たらない。書かないのは、書かずに済む値を設定に増やさないため。
認証鍵の `~/.config/dpt/privatekey.dat` はリポジトリに置かない。

## 取り込みの記録はアーカイブの外に置く

`entry_id` から `file_revision` への対応は `$XDG_STATE_HOME/quaderno/state.json` に置く。
アーカイブは手で Google Drive へ上げるので、同期の記録が中身に混ざらないようにする。
各文書は一時ファイルに書いてから rename し、その後で記録を更新する。途中で電源が落ちても書きかけのファイルは残らず、記録されなかった分は次に取り込み直す。

記録はマシンごとに分かれるので、2 台で有効にすると両方が全件を取り込む。取り込みは nixos-desktop の 1 台に限る。

## 取り込み先は SATA の `@backup` にし、vault には置かない

`archiveDir` は `/mnt/backup/quaderno` で、ディレクトリは `data-disk.nix` の tmpfiles が作る。`minecraft-backup` と同じく、置き場所と書き込み権限はホストが用意し、モジュールは受け取るだけにする。
PDF は増え続ける一方で読むのは時々なので SATA に置く（最初の 62 件で 428 MiB、[disk-tiering.md](./disk-tiering.md)）。
`~/sagyo/memex`（vault の clone）には置かない。obsidian-git が 2 台で同期しているので、数百 MiB の PDF を持ち込むと同期の対象が膨らむ。

## memex-nix に載せない

workflow 側には添付と papis の Drive 同期があり、取り込み先を vault の下にすれば Drive へ運べる。
しかし既存の同期は `rclone bisync` だけで片方向の `copy` がなく、Drive 側の削除が手元に伝わる。一方向にした判断と合わない。
Drive への同期を自動化するときは、片方向の層を足してから workflow へ移す。
移しやすいよう、モジュールは `local.quaderno` と `config.home.homeDirectory` 以外のこのリポジトリ固有の値を読まず、`archiveDir` に既定値を置かない。

## まだ分からないこと

- mDNS の広告が、Wi-Fi を入れてから何分後まで続くかは測っていない。Wi-Fi を入れて十数分経っても応答したのは一度の観測で、dpt-rp1-py の README は「数分間だけ有効」と書いている
- dpt-rp1-py は Quaderno Gen2 を公式には対応していない。登録の修正も DPT-RP1 の実機で確かめられたもので、ファームウェアの更新で変わりうる

## 見直す条件

- 登録の修正を含むリリースが PyPI に出たら、rev の固定をやめる
- nixpkgs に dpt-rp1-py が入ったら、`packages/` から消す（2026-09-15 には `python3Packages` になかった）
