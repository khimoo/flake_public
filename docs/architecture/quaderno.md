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

## PC との受け渡しは専用のフォルダで行い、同じ名前は英字を付けて分ける

送り先と受け取り元は、同じ専用のフォルダ `Document/PC-Exchange` にする。無ければスクリプトが作る。
デバイスに最初からある `Document/Received` を使わないのは、PC 以外から入った文書も入っていて、受け取りの対象が PC とやりとりする文書に絞れないため。
名前に `Sync` を使わないのは、削除や名前の変更まで反映される同期を連想させるため。機体ごとにフォルダを分けないのは、機体の名前を設定に持ち込まないため。
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

## 受け渡しフォルダは手元のキャッシュに落とす

アーカイブは自分用サーバにあるので、出先のラップトップでは、Quaderno で書き込んだ PDF をすぐに開けない。AI と作業するときは、PDF を送り、書き込み、手元で読むまでを数十秒で回したい。
そこで受け渡しフォルダだけを、自分用サーバを使わずに各機体の手元へ落とす（`quaderno_exchange`）。アーカイブへの取り込みはそのまま残し、長期保存はアーカイブが受け持つ。

置き場所は `~/.cache/quaderno/Received` で、`~/Quaderno/Received` を symlink にする。Quaderno から落とし直せるファイルなので、キャッシュにあたる。
`/run/user/<uid>` は中身がメモリに載り、spin713 では 784 MiB しかないので使わない。`/tmp` は機体によって tmpfs かディスクかが変わり、全利用者で共有される。
7 日間使われなかったファイルは、利用者の tmpfiles の規則で消す。規則は `quaderno_exchange` が持つので、行動をやめれば規則も消える。

どの改訂まで落としたかの記録（`~/.cache/quaderno/received.json`）は、機体ごとに手元に置く。記録が無いと、tmpfiles が消したファイルを次の回に落とし直してしまう。

2026-11-14 に spin713 から Bluetooth の PAN で、8 件 5.9 MiB を落とした。探索と接続を含めて 65 秒かかった。

## 受け取りはコマンドを実行したときだけ行う

受け取りを定期実行に入れると、送ったばかりの PDF が、書き込む前に同じ中身のまま手元へ落ちてくる。送り先と受け取り元が同じフォルダだからである。Bluetooth では転送が遅く、このむだが目立つ。
受け取りを `quaderno-receive` の実行時だけにすれば、受け取るのは書き込んだ後になる。送った改訂を覚えておいて落とし直しを避ける仕組みが要らない。

## 送信は Send を見て 1 分ごとに、取り込みは 1 時間ごとに試す

Quaderno はスリープすると通信できず、起きている短い間しか受け渡しができない。
1時間ごとに試していた 2026-09-15 から 11-09 までは、約1250回のうち接続できたのは22回で、手書きが最長で約8日手元に届かなかった。

送信は、Send に PDF がある間だけ 1 分ごとに試す。Send はスプールで、Quaderno がスリープ中に置いた PDF は、次に見つかった回に送られる。Send が空の間は unit の条件（`ConditionDirectoryNotEmpty`）で実行されないので、探索と Bluetooth の接続を毎分繰り返さない。
取り込みは 1 時間ごとに試す（利用者の決定）。`quaderno-send` と `quaderno-receive` の実行時にも取り込むので、Quaderno を PC と一緒に使う日は、そのときに取り込まれる。定期実行は、コマンドを使わない日のための保険である。
代償として、コマンドを使わずに手書きだけをする日が続くと、取り込みが数日遅れることがある。その間に本体を失うと、取り込んでいない手書きも失う。間隔はホストの `quaderno_archive_interval` で縮められる。

定期実行とコマンドは、同時に Quaderno へ接続しないよう、ロックで排他する。定期実行は、ほかの実行が進行中なら何もせずに終わる。

## LAN に居ないときは Bluetooth の PAN でつなぐ

公共の Wi-Fi では、PC と Quaderno を同じ LAN に置けない。
Quaderno は Bluetooth classic の PAN を提供するので、PC が PAN に接続すれば、Wi-Fi のときと同じ REST API を使える。

2026-11-14 に nixos-spin713 と Quaderno A4 Gen2 で確かめた。

- Quaderno は Bluetooth のサービスとして `NAP` を公開する
- PAN につなぐと、PC は DHCP で `172.25.48.0/24` のアドレスと、`172.25.48.1` を向く default route を受け取る。本体のアドレスは `172.25.48.1` で、dpt-rp1-py の README が書く `172.25.47.1` は応答しない
- PAN の上でも mDNS の広告（`_dp_fujitsu._tcp`）が出るので、探索のコードを変えずに本体が見つかる
- 接続は、Quaderno が起きていれば約 10 秒で成功し、スリープしていれば約 5 秒で失敗する。スリープに入ると、つないでいた PAN も切れる
- systemd のユーザーサービスからも、`networkmanager` グループの利用者は `nmcli connection up` で接続できる

Wi-Fi を先に 5 秒だけ探し、見つからなかったときに PAN をつなぐ。Wi-Fi が先なのは、同じ LAN に居るときに速い Wi-Fi で転送するため（PAN は 5.9 MiB に約 40 秒かかった）。5 秒で切り上げるのは、Bluetooth しか使えない場所で、探索の待ち時間（既定 15 秒）を毎回待たずに済ませるため。
PAN につながらなかったときは、探索の待ち時間の残りで Wi-Fi を探し直す。Wi-Fi の応答が 5 秒より遅い場合に、見つけ損ねないようにする。Wi-Fi 上で見つかるまでの秒数は測っていない。
PAN をつないだ後に探索をやり直すのは、zeroconf が作った時点のネットワークインターフェースしか見ないため。
自分でつないだ PAN は、受け渡しの後に切る。
接続プロファイルは default route を受け取らない設定にする。受け取ると、Wi-Fi が切れたときに PC の全通信が Quaderno へ向く。

Quaderno の BLE は使わない。BLE は譜めくり用のフットペダルをつなぐための機能で、有効にすると PC から Bluetooth で接続できなくなる（本体の設定画面の説明）。
BLE を有効にした Quaderno は、スキャンしても Quaderno と分かるアドバタイズを出していなかったので、起動の合図にも使えない。

接続先は設定に書かず、ペアリング済みの機器から実行時に探す。ホストごとに Bluetooth を使うかを書くと、要素の中で機体を見分けることになる（[構成の境界](./configuration.md#機体による違いを受け持つ場所)）。ペアリングしていない機体では、候補が無いので Wi-Fi だけを使う。
候補は名前で選ぶ。Quaderno の Bluetooth の名前は `FMVDP41_2006338` のように機種名で始まる。`NAP` の有無では選ばない。スマホもテザリングのために `NAP` を公開するので、スマホの回線につながってしまう。
接続先のアドレスが実行時まで決まらないので、接続プロファイルは NixOS で宣言せず、受け渡しのたびに保存せずに作って消す。GNOME がペアリングのときに作るプロファイルは default route を受け取るので使わない。

## 見つからないことを失敗にしない

定期実行のほとんどは相手が見つからずに終わる。
失敗として扱うと、正常な状態で通知が鳴り続ける。探索の失敗は一行出して 0 で終わり、認証とダウンロードの失敗だけを非 0 にする。

## 機器はシリアルを書かずに mDNS で選ぶ

この環境には機器が 1 台しかないので、既定では mDNS で最初に見つかった Digital Paper に接続し、設定に識別子を持たない。
`quaderno_serial` を書くのは、別の機器へ黙ってつながるのを避けたくなったときでよい。
シリアル番号は同じ LAN から認証なしで読める値なので、公開リポジトリに書いても漏洩には当たらない。書かないのは、書かずに済む値を設定に増やさないため。
認証鍵の `~/.config/dpt/privatekey.dat` はリポジトリに置かない。

## 取り込みの記録はアーカイブの外に置く

`entry_id` から `file_revision` への対応は、自分用サーバの利用者の `$XDG_STATE_HOME/quaderno/state.json` に置く。
アーカイブは手で Google Drive へ上げるので、同期の記録が中身に混ざらないようにする。
各文書は一時ファイルに書いてから rename し、その後で記録を更新する。途中で電源が落ちても書きかけのファイルは残らず、記録されなかった分は次に取り込み直す。

## 取り込みは自分用サーバに集める

取り込み先のアーカイブと取り込みの記録は、自分用サーバ（nixos-desktop）の1か所に置く。
Quaderno を見つけた機体（クライアント）は、文書を落として検査し、ssh でサーバの `quaderno-archive store` に渡す（[quaderno_archive.py](../../modules/home-manager/quaderno_archive.py)）。
サーバは記録を `flock` で排他してから、一時ファイルに書いて rename し、記録を更新する。
同じ改訂がすでに記録されていれば書かずに答えるので、desktop と spin713 が同時に Quaderno を見つけても、アーカイブは1つで、同じ改訂を二度取り込まない。
記録が機体ごとに分かれていたときは、2台で有効にすると両方が全件を取り込むので、取り込む機体を1台に限る必要があった。

desktop 自身も、自分に ssh で接続して渡す。desktop でだけアーカイブに直接書く形にすると、要素の中で「自分がサーバなら」と分岐することになる。
サーバへ接続できない（ssh が 255 で終わる）ときは、取り込みを飛ばして 0 で終わる。出先で desktop の電源が切れている間、実行のたびに失敗の通知が鳴らないようにするため。文書は Quaderno に残り、次に接続できたときに取り込む。
サーバのパスやサイズの検査で断られたときは、非 0 で終わる。

## 取り込みと受け渡しを別の要素にする

desktop の電源を切って spin713 だけで出かけたときにも受け渡せるよう、送信と受け取りは自分用サーバを使わずに動かす。取り込み（`use_quaderno_archive`）と受け渡し（`quaderno_exchange`）を別の要素に分け、どちらも行動 `read_materials` の `requires` から入る。`use_quaderno_archive` が `requires` に挙げる `find_home_server` は `needs` に `tailscale` を挙げるので、tailnet に入らない機体で `read_materials` を選ぶと confgen が止まる。
探索、コマンド、systemd の timer は `quaderno` の要素が持ち、二つの要素は `quaderno` へ設定を書き込む。どの実行でも、Quaderno につながったら、取り込みと Send の送信を両方行う。

## 取り込み先は SATA の `@backup` にし、vault には置かない

`quaderno_archive` は `/mnt/backup/quaderno` で、ディレクトリはサーバの `serve_quaderno_archive` の `user_config` が tmpfiles で作る。`minecraft-backup` と同じく、置き場所と書き込み権限はホストが用意し、モジュールは受け取るだけにする。
PDF は増え続ける一方で読むのは時々なので SATA に置く（最初の 62 件で 428 MiB、[disk-tiering.md](./disk-tiering.md)）。
`~/sagyo/memex`（vault の clone）には置かない。obsidian-git が 2 台で同期しているので、数百 MiB の PDF を持ち込むと同期の対象が膨らむ。

## memex-nix に載せない

workflow 側には vault の資料の Drive 同期があり、取り込み先を vault の下にすれば Drive へ運べる。
しかし既存の同期は `rclone bisync` だけで片方向の `copy` がなく、Drive 側の削除が手元に伝わる。一方向にした判断と合わない。
Drive への同期を自動化するときは、片方向の層を足してから workflow へ移す。
`serve_quaderno_archive` はホストの `quaderno_archive` とユーザーのホームを受け取り、`quaderno_archive` に既定値を置かない。失敗の通知は `failure_notify` の公開値を使う。

## まだ分からないこと

- mDNS の広告が、Wi-Fi を入れてから何分後まで続くかは測っていない。Wi-Fi を入れて十数分経っても応答したのは一度の観測で、dpt-rp1-py の README は「数分間だけ有効」と書いている
- PAN の上で PDF を送る速さは測っていない。落とす速さは、上の一度の測定だけ
- PAN をつないだ直後の文書一覧の取得が、一度 `KeyError: 'entry_list'` で失敗した。次の実行は成功し、原因は分かっていない
- PAN をつないでいる間、Quaderno が Wi-Fi にも居続けるかは確かめていない
- dpt-rp1-py は Quaderno Gen2 を公式には対応していない。登録の修正も DPT-RP1 の実機で確かめられたもので、ファームウェアの更新で変わりうる

## 見直す条件

- 登録の修正を含むリリースが PyPI に出たら、rev の固定をやめる
- nixpkgs に dpt-rp1-py が入ったら、`packages/` から消す（2026-09-15 には `python3Packages` になかった）
