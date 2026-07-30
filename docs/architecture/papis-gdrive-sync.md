# papis（参照文献マネージャ）の設計判断

papis 本体・設定・ライブラリ同期は workflow flake（public repo
`github:khimoo/zettelkasten-workflow`）の `services.zettelkasten` が所有する。flake_public は
`modules/home-manager/zettelkasten.nix` で vault の位置と feature toggle を注入するだけ。

同期の仕組みそのもの（認証・トリガー・初回ブートストラップ）は添付と共通なので
[zettelkasten-attachments-sync.md](./zettelkasten-attachments-sync.md) を参照。本書は
「なぜ papis か」「なぜこの置き方か」だけを扱う。使い方は
[../howtouse/papis-gdrive-sync.md](../howtouse/papis-gdrive-sync.md)。

## 全体構成

```
papis add ──> <vault>/references/<item>/{info.yaml, *.pdf} ──(変更検知/定期)──> zettelkasten-sync --only papis
                                                                                      │
                                                                          rclone bisync
                                                                                      │
                                                                    gdrive:papis-library
```

ライブラリ本体は vault 内 `references/`（Obsidian vault で完結）。nixos-desktop では
このパスに SATA subvol を被せ、実体をコールド層に置く（[disk-tiering.md](./disk-tiering.md)）。

## 設計判断

### 参照文献マネージャは papis（平文）、Zotero 不採用

item ごとに **`info.yaml`（平文メタデータ）と PDF 実体が同じフォルダに同居**する。これにより
同期が 1 系統で済む。設定は `programs.papis`（home-manager）で `~/.config/papis/config` まで
宣言生成でき、Nix で参照文献まわりを閉じられる。citekey はプラグインに依存せず、各
`info.yaml` の `ref:` に平文で pin する。

対して Zotero は citekey 生成に Better BibTeX プラグインが要り、これを宣言的にクリーンに
導入できない（Zotero がプロファイルの `extensions.json` で管理し activation-script と相性が
悪い。BBT 8.0.26+ は Zotero 7 サポートを打ち切っており nixpkgs の zotero とのバージョン固定の
罠もある）。ここが移行の主動機。

### 同期対象は 1 フォルダ（メタデータとバイトを一本化）

`references/` を丸ごと 1 本の rclone bisync で同期すればメタデータも PDF もカバーできる。
Zotero では生きた SQLite を安全に rclone できず、metadata=Zotero 純正同期 + PDF バイト=rclone の
**2 系統**を強いられていた。papis 化でこれが 1 系統に減る。

### ライブラリの位置は vault の中（`references/`）

Obsidian vault で完結させる。ノートから文献を参照する運用なので、ノートと文献が別ツリーに
分かれていると vault 単独で持ち運べない。パスは規約で固定していて option にしていない
（同期対象パスの固定と同じ理由）。

依存の向きは **同期 → ライブラリ** の一方向。同期は「ライブラリが `references/` に存在する」
ことを前提にするが、`programs.papis` は同期 backend を一切知らない。gdrive を NAS 等へ
差し替えても `programs.papis` 設定は不変。

### 本体と同期を 1 トグルでまとめて出す（`referenceSync`）

旧構成は papis 本体を `gui`、同期を `referenceSync` と別 gate にしていたが、
`services.zettelkasten.papis.enable` 1 本で本体・設定・同期をまとめて導入する。参照文献
ワークフローは「本体があるのに同期が無い/その逆」に意味が無く、まとめる方が凝集度が高い。
副作用として、`gui=true` でも `referenceSync=false` の環境では papis 本体も入らない。

### citekey は自動生成しない（`ref:` を手で pin）

`ref-format` による自動生成をあえて設定していない。citekey は原稿から参照される安定した識別子
なので、メタデータの変化（著者名の表記ゆれ・年の訂正）で勝手に変わってほしくない。
`info.yaml` に平文で書いてある以上、手で決めて固定する方が壊れにくい。

## セキュリティモデル

- **OAuth scope は `drive.file`**（フルの `drive` ではない）。万一トークンが漏れても被害範囲を
  「rclone が作成したファイル」に限定する。代償として、Drive UI で手動作成したフォルダは
  rclone から見えない（フォルダは rclone に作らせる）
- **トークンは各マシンの `~/.config/rclone/rclone.conf` にだけ存在する**。repo は暗号文すら
  持たない（[認証情報を repo に持たない判断](./zettelkasten-attachments-sync.md#認証情報はどちらの-repo-も持たない各マシンの-rcloneconf-に委ねる)）
