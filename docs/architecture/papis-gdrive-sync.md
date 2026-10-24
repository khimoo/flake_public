# papis の設計

使い方: [papis](../howtouse/papis-gdrive-sync.md)
実装: papis、設定、同期は memex-nix の `services.memex` が持ち、このリポジトリは [memex.nix](../../modules/home-manager/memex.nix) で vault の場所と機能の選択を渡すだけ

同期の仕組み（認証、変更の監視、最初の resync）は添付と同じ（[memex-attachments-sync.md](./memex-attachments-sync.md)）。この文書は、papis にした理由と置き方だけを扱う。

## Zotero ではなく papis にする

papis は文献ごとに `info.yaml`（平文のメタデータ）と PDF を同じフォルダに置くので、同期が 1 つで済む。設定は `programs.papis` で `~/.config/papis/config` まで宣言で作れ、citekey もプラグインなしで `info.yaml` の `ref:` に書ける。
Zotero は、生きている SQLite を rclone で安全に同期できず、メタデータは Zotero の同期、PDF は rclone の 2 つに分かれていた。
citekey を作るには Better BibTeX のプラグインが要るが、Zotero がプロファイルの `extensions.json` で管理するので宣言的に入れにくい。BBT 8.0.26 以降は Zotero 7 の対応をやめていて、nixpkgs の zotero と版を合わせる問題もある。これが移った主な理由。

## ライブラリは vault の中の `Assets/references/` に置く

ノートから文献を参照するので、vault だけで持ち運べるようにする。パスは同期の対象と同じ理由で固定し、オプションにしない。
依存の向きは同期からライブラリへの一方向で、`programs.papis` は同期の仕組みを知らない。Google Drive を NAS などに変えても、papis の設定は変わらない。
nixos-desktop では、このパスに SATA の subvol をマウントして、実体を遅い層に置く（[disk-tiering.md](./disk-tiering.md)）。

## papis と同期は 1 つのトグル（`referenceSync`）で入れる

`services.memex.papis.enable` 1 つで、papis、設定、同期をまとめて入れる。papis があって同期がない状態や、その逆には意味がない。
そのため、`gui = true` でも `referenceSync = false` の環境には papis 自体が入らない。

## citekey は自動で作らない

`ref-format` での自動生成は設定しない。citekey は原稿から参照される識別子なので、メタデータの変化（著者名の表記の揺れ、年の訂正）で変わってほしくない。手で決めて `info.yaml` に固定する。

## 認証

トークンは各マシンの `~/.config/rclone/rclone.conf` にだけあり、repo は暗号文も持たない（[memex-attachments-sync.md](./memex-attachments-sync.md#認証情報はどちらの-repo-も持たない各マシンの-rcloneconf-に委ねる)）。
専用の OAuth クライアントに移った後のリモート `gdrive` の scope は `drive`（Drive 全体の読み書きと削除、2026-10-23 に desktop の rclone.conf で確認）で、トークンが漏れたときの被害は rclone が作ったファイルに限られない。
