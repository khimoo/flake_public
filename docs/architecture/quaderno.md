# Quaderno の取り込み

使い方: [howtouse/quaderno.md](../howtouse/quaderno.md)

実装: [modules/home-manager/quaderno.nix](../../modules/home-manager/quaderno.nix)、
[packages/dpt-rp1-py/](../../packages/dpt-rp1-py/)

**実機での取り込みはまだ確認していない。** 2026-09-15 時点で、評価・契約テスト・
選別ロジックの単体テストは通っているが、Quaderno を起こして実際に文書を落とすところまでは
確かめていない。「確認した事実」の節は設計時に実機で検証した記録で、そこに書かれた範囲
（ペアリング、一覧の取得、1 件のダウンロード）は動作を確認済み。

## 解決する問題

Quaderno A4 Gen2 で手書きした PDF を、この環境へ自動で取り込みたい。

Fujitsu が提供するクラウド同期は無料枠が 10MB しかなく、数 MiB の PDF が数十件ある
用途では使えない。有償プランを契約するか、USB ケーブルを挿して Digital Paper App
（Windows と macOS のみ）を使うかの二択になっている。

同じ LAN にいるときに取り込めれば、どちらも要らなくなる。

## 確認した事実

2026-09-15 に Quaderno A4 Gen2（`model_name` が `FMVDP41`、`sku_code` が `J`）で確認した。

本体は Wi-Fi 上に HTTPS の REST API を 8443 番で出し、平文の HTTP を 8080 番で出す。
`http://<addr>:8080/register/information` は認証なしで `model_name`、`serial_number`、
`sku_code`、`device_color` を返す。8443 番は認証前だと
`{"error_code":"40100","message":"Authentication is required."}` を返す。

ペアリングは [`dpt-rp1-py`](https://github.com/janten/dpt-rp1-py) の `register` で通り、
Digital Paper App は要らない。成功すると `~/.config/dpt/deviceid.dat` と
`~/.config/dpt/privatekey.dat` が作られる。以後はこの 2 つで認証する。

認証後、72 エントリ（うち文書 62 件）の一覧を取得し、1 件をダウンロードして
`%PDF-1.5` で始まる 3262 バイトのファイルを得た。日本語を含むパスもそのまま扱える。

各文書のメタデータには `entry_id`、`file_revision`、`modified_date`、`file_size`、
`mime_type`、`total_page`、`current_page` が含まれる。`file_revision` は
`ac9116e89ba8.0.845` の形で、書き込みのたびに変わる。

mDNS では `_dp_fujitsu._tcp.local.` として `Digital Paper FMVDP41 (2)` の名前で
広告され、ポートは 8080 を示す。TXT レコードは空で、シリアル番号は含まれない。
`dpt-rp1-py` の探索は、各候補の `:8080/register/information` に問い合わせて
シリアルを照合する実装になっている。

本体がスリープすると Wi-Fi ごと落ちる。この状態で接続すると
`OSError: [Errno 113] No route to host` になる。

## dpt-rp1-py を PyPI からではなく master から取る理由

Gen2 の登録は PyPI の最新版（0.1.19、2025-10-14）では確率的に失敗する。

[issue #134](https://github.com/janten/dpt-rp1-py/issues/134) が
`error_code 40301 "Bad parameters for registration process."` を、
[issue #124](https://github.com/janten/dpt-rp1-py/issues/124) が
`KeyError: 'a'` を報告している。後者はエラー応答を正常応答として読もうとした結果なので、
原因は同じとみられる。

原因は Diffie-Hellman の公開値 `yb` の符号バイトにある。本体側は Java の
`BigInteger.toByteArray()` で `yb` を直列化するため、最上位ビットが立つと先頭に `0x00` が
付いて 257 バイトになる。`dpt-rp1-py` はこれを 256 バイトに詰め直してから HMAC を
計算していたので、約半分の確率で本体側の計算と食い違い、HTTP 403 で弾かれていた。

[commit 7a0ef07](https://github.com/janten/dpt-rp1-py/commit/7a0ef077)（2026-07-12）が、
受信したバイト列をそのまま HMAC に使うよう直している。この修正を含むリリースはまだ
PyPI に出ていない。

したがって `packages/dpt-rp1-py/` は rev を固定して GitHub から取る。

**再検討の条件:** この修正を含むリリースが PyPI に出たら rev 固定をやめる。
nixpkgs に `dpt-rp1-py` が入ったら `packages/` から削除する（2026-09-15 時点では
`python3Packages` に該当する属性は無い）。

## 設計

### 取り込み専用にする

デバイスから手元への一方向だけを実装する。手元からデバイスへは書き戻さない。

`dpt-rp1-py` には `sync` コマンドがあるが、中身は双方向の三方向マージで、checkpoint を
`.sync` という pickle ファイルに持つ。加えて実行のたびに `set_datetime()` で
デバイス側の時刻を書き換え、古いほうのファイルを警告なく上書きする。手元で触った
PDF がデバイス上の注釈入りを潰す経路が存在することになる。

一方向にすれば、デバイス側が壊れる経路が存在しない。取り込みの判定も「まだ持って
いないもの」と「`file_revision` が記録と違うもの」だけで閉じる。

手元からデバイスへ送る必要が生じたときは `dptrp1 upload` を手で叩く。

### 手元はアーカイブとして扱う

デバイス上で削除された文書を、手元からは消さない。取り込みの判定は `entry_id` と
`file_revision` の対応だけを見るため、リネームや移動をしても `entry_id` は変わらず、
新しいファイルとしては落ちてこない。手元には古い名前・古い場所のファイルが残るだけになる。

Quaderno は本体容量が限られるため、読み終えた PDF は本体から消すことになる。
このとき手元のコピーまで消えると、取り込む目的が失われる。手元をミラーにすると
デバイス側の誤操作がそのまま手元の削除になり、一方向にした意味が薄れる。

代償として、デバイス上で整理した結果は手元に反映されない。消したはずの文書が残り、
フォルダを移動しても手元は古い場所のまま溜まる。

`file_revision` が変わった文書は上書きする。注釈を書き足した版で置き換わり、前の版は
残らない。世代を残す仕組みは作らない。必要になったときに足す。

### 機器の選び方

`local.quaderno.serial` は省略できる option にする。既定では mDNS で最初に見つかった
Digital Paper に接続する。この環境には該当する機器が一台しかないので、設定に識別子を
持たずに済む。

シリアルを指定した場合は、mDNS で見つけた候補のうちシリアルが一致する一台だけに
接続する。LAN に別の Digital Paper 系の機器が現れて、黙って別の機器へ繋がる状態を
避けたくなったときに書き足す。

その値を公開リポジトリに置くこと自体は秘密の漏洩にあたらない。同じ LAN にいれば
`:8080/register/information` から認証なしで読める値であり、それ単体では何もできない。
ディスクの UUID を `hosts/*/hardware.nix` に平文で置いているのと同じ扱いになる。
書かない理由は秘匿ではなく、書かずに済むものを設定に増やさないことにある。

これに対し `~/.config/dpt/privatekey.dat` は本体への認証鍵であり、リポジトリには置かない。
ペアリングは利用者が一度だけ手で実行し、生成物はそのまま home に残す。

### 到達しないことを異常として扱わない

Quaderno はスリープすると Wi-Fi ごと消える。定期実行のほとんどは相手が見つからずに
終わる。

探索が失敗したときは一行出力して終了コード 0 で抜ける。失敗として扱うと、正常な
状態で通知が鳴り続けることになる。認証の失敗とダウンロードの失敗は非 0 で落とす。

### 状態はアーカイブの外に持つ

`entry_id` から `file_revision` への対応を `$XDG_STATE_HOME/quaderno/state.json` に持つ。

アーカイブのディレクトリに置かない理由は、そこが手動で Google Drive へ上げる対象に
なるため。同期の記録が中身に紛れない。

各文書は一時ファイルへ書いてから rename し、その後で状態を更新する。途中で電源が
落ちても、書きかけのファイルが完成品として残ることはない。状態に記録されなかった
分は次回もう一度落ちてくる。

### 置き場所と移設できる状態の維持

`modules/home-manager/quaderno.nix` に置き、`lib/configurations.nix` の imports に加えて
`local.quaderno.enable` で切る。Wi-Fi 越しなので、どのホストからでも有効にできる。

ただしこの環境では nixos-desktop だけで有効にする（[`hosts/nixos-desktop/home-manager-pomu.nix`](../../hosts/nixos-desktop/home-manager-pomu.nix)）。
`profiles/home/pomu-workstation.nix` に置くと nixos-spin713 にも入るが、取り込み先は
vault の中にあり、vault は obsidian-git が 2 台の間で同期している。状態ファイルは
`$XDG_STATE_HOME` にあってマシンごとに分かれるので、2 台で有効にすると両方が全件を
落とし、同じ PDF が両側から vault に入る。取り込みは 1 台に限る。

このモジュールは `local.quaderno` と `config.home.homeDirectory` 以外の、この
リポジトリに固有の値を読まない。`archiveDir` に既定値を置かず、
`profiles/home/` から注入する。

将来 [zettelkasten-workflow](https://github.com/khimoo/zettelkasten-workflow) へ
移すときは、このファイルを `nix/` へ動かし、名前空間を `services.zettelkasten.quaderno`
へ変え、`packages/dpt-rp1-py/` を持っていけば済む。

### 取り込み先が vault の Git 作業ツリー内にあること

この環境では `archiveDir`（[`hosts/nixos-desktop/home-manager-pomu.nix`](../../hosts/nixos-desktop/home-manager-pomu.nix)）を
`~/sagyo/zettelkasten/Resources/quaderno` に置いている。ここは `khimoo/zettelkasten` を
clone した Git の作業ツリーの中である。

そのため最初の取り込みで、数十 MiB になりうる PDF が未追跡ファイルとしてこの
作業ツリーに現れる。これを vault の `.gitignore` に足して追跡から外すか、そのまま
commit して vault の履歴に含めるかは利用者が決める必要があり、**この判断はまだ済んで
いない。**

`archiveDir` に既定値を置かないのは置き場所を利用者が決める設計であるためで、この
場所自体は変えない。

## 退けた案

### zettelkasten-workflow に最初から載せる

workflow 側はすでに添付と papis ライブラリの Google Drive 同期を持ち、`sync-job.nix` が
「監視ディレクトリと対象名だけが違う汎用ジョブ」として書かれている。取り込み先を
vault 配下にすれば、既存の同期がそのままアーカイブを Drive へ運ぶ構成になる。

これを採らなかったのは、Drive への同期をいま自動化しないと決めたため。
既存の同期は `rclone bisync` 専用で片方向の `copy` を持たないので、アーカイブを
そのまま載せると Drive 側の削除が手元に伝播する。一方向にした判断と噛み合わない。

Drive へは当面、手動で上げる。自動化が必要になった時点で、片方向の層を足したうえで
workflow へ移す。上の「移設できる状態の維持」はそのための準備である。

なお `flake.nix` はすでに `zettelkasten` を input として取り込んでいるので、移設の際に
配線を新しく作る必要はない。

### 固定 IP を振る

当初は DHCP の予約で IP を固定する前提で考えていたが、mDNS で見つかるので要らない。

`dpt-rp1-py` の README は「自動探索は Wi-Fi をオンにしてから数分間だけ有効」と
書いているが、Wi-Fi を入れて十数分が経った状態でも応答した。

## 残る不確実性

- mDNS の広告が何分後まで生きているかを測っていない。上記は一度の観測にすぎない。
  定期実行が十分な頻度で相手を捕まえられるかは、運用してから判断する。
- アーカイブの総量を測れていない。測ろうとした時点で本体がスリープしていた。
  Google Drive の枠に対してどれだけ増えるかは、取り込みが動いてから確認する。
- upstream は Quaderno Gen2 を公式にサポートしていない。`README` は Fujitsu Quaderno に
  言及するが世代を区別しておらず、登録の修正も DPT-RP1 実機で検証されたものである。
  Gen2 で登録が通ることはこの環境で確認したが、ファームウェアの更新で変わりうる。
