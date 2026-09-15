# Quaderno の取り込み（使い方）

設計判断: [architecture/quaderno.md](../architecture/quaderno.md)

Fujitsu Quaderno A4 Gen2 で手書きした PDF を、同じ LAN にいるときに自動でアーカイブへ
落とす。デバイスから手元への一方向で、手元からデバイスへは何も書かない。

設定ファイル:
- [`modules/home-manager/quaderno.nix`](../../modules/home-manager/quaderno.nix)（`local.quaderno` オプションと `quaderno-pull` コマンド、systemd timer）
- [`modules/home-manager/quaderno_pull.py`](../../modules/home-manager/quaderno_pull.py) / [`quaderno_plan.py`](../../modules/home-manager/quaderno_plan.py)（本体と選別ロジック）
- [`packages/dpt-rp1-py/`](../../packages/dpt-rp1-py/)（デバイス操作 CLI）
- [`profiles/home/pomu-workstation.nix`](../../profiles/home/pomu-workstation.nix)（この環境の設定）

## 初回のペアリング

Quaderno の Wi-Fi を入れる。設定画面に出ている IP を控える。

届いているか確かめる。

```sh
curl -s http://<IP>:8080/register/information
```

`model_name` などが JSON で返れば届いている。

登録する。

```sh
dptrp1 --addr <IP> register
```

`dptrp1` は `local.quaderno.enable` を有効にした home-manager 世代で PATH に入る。
まだ `home-manager switch` していない場合は、代わりに次のコマンドが使える。

```sh
nix run .#dpt-rp1-py -- --addr <IP> register
```

実行すると本体の画面に PIN が出る。それを端末に打つと成功する。

成功すると `~/.config/dpt/deviceid.dat` と `~/.config/dpt/privatekey.dat` ができる。
この 2 つは本体への認証鍵なので、このリポジトリには入れない。以後 `quaderno-pull` は
この 2 つのファイルで認証する。

## 日常の使い方

何もしなくてよい。1 時間ごとにタイマーが探索を試み、Quaderno が起きていれば取り込む。

すぐ取り込みたいときは手で叩く。

```sh
quaderno-pull
```

取り込み先は `/mnt/backup/quaderno`（= `archiveDir`）。SATA 側の `@backup` subvol で、
ディレクトリは `data-disk.nix` が用意する。ここは手動で
Google Drive へ上げる運用にしている（自動同期は作っていない）。デバイス上のパスは
`archiveDir` の下にそのまま再現する。`remoteRoot`（既定 `Document`）配下の文書なら、
`<archiveDir>/Document/...` の 1 段を挟んだ階層になる。

デバイス側で消した文書は手元に残る。手元のアーカイブを整理するのは自分の役目になる。

取り込みの判定は `entry_id` と `file_revision` の対応だけを見る。デバイス側でリネームや
移動をしても、この 2 つは変わらない。そのため新しいファイルとしては落ちてこず、
古い名前・古い場所のまま手元に残り続ける。手元へも同じリネームや移動を反映したい場合は
手作業になる。

## 設定できるオプション

`local.quaderno` 配下（[`modules/home-manager/quaderno.nix`](../../modules/home-manager/quaderno.nix)）。

- `archiveDir`（必須）取り込み先。既定値は無く、環境ごとに `profiles/home/` で指定する。
- `serial`（既定 `null`）接続する機器のシリアル番号。`null` なら mDNS で最初に見つかった
  Digital Paper に接続する。
- `remoteRoot`（既定 `"Document"`）デバイス上の対象フォルダ。この配下だけを取り込む。
- `intervalSeconds`（既定 `3600`）タイマーが取り込みを試す間隔（秒）。
- `discoveryTimeoutSeconds`（既定 `15`）mDNS で機器を探す時間（秒）。この間に見つからな
  ければ何もせず終わる。

## 状態

`~/.local/state/quaderno/state.json` に、どの文書のどの改訂まで取り込んだかを記録している。
取り込み先の外に置いてあるので、Drive へ上げるときに同期の記録が混ざらない。

このファイルを消すと、次回の実行で全件を落とし直す。

## 確認する

```sh
systemctl --user status quaderno-pull
journalctl --user -u quaderno-pull
```

Quaderno がスリープしていると探索が失敗する。これは正常で、終了コード 0 で終わる。
ログに「見つかりません」が並んでいても異常ではない。
