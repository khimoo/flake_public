# papis（文献管理）

papis のライブラリは、vault 内の `~/sagyo/zettelkasten/Assets/references/` に配置する。
文献ごとに `info.yaml`（プレーンテキストのメタデータ）と PDF が同じディレクトリに保存され、このディレクトリ全体を Google Drive と同期する。
`local.profile.features.referenceSync = true` を設定すると、papis 本体、`~/.config/papis/config`、および同期機能が一括でセットアップされる。
同期の設定、認証、トラブルシューティングについては、vault 内の `Assets/attachments/`（添付ファイル）の同期と共通であり、[zettelkasten-attachments-sync.md](./zettelkasten-attachments-sync.md) を参照。

設計: [papis の設計](../architecture/papis-gdrive-sync.md)

## 文献の追加

```sh
papis add --set ref hottbook path/to/paper.pdf    # PDF から追加（DOI 等が含まれていればメタデータを自動取得）
papis add --from doi 10.1000/xyz123               # DOI から追加
```

実行すると `references/<item>/` 内に `info.yaml` と PDF が作成される。

## citekey の設定

引用は citekey で参照するため、各文献の `info.yaml` 内にある `ref:` フィールドに手動で citekey を記述して固定する（`papis edit` を使用してもよい）。自動生成用の `ref-format` は設定していない。

```yaml
ref: hottbook
author: ...
title: ...
```

## 原稿からの引用

`.bib` ファイルをエクスポートし、LaTeX や Markdown から `[@citekey]` や `\cite{citekey}` の形式で参照する。自動エクスポート機能は有効にしていない。

```sh
papis export --all --format bibtex > references.bib
```

## papis 特有の注意事項

- 最初の文献を追加するまで同期機能は動作しない。`Assets/references/` ディレクトリは最初の `papis add` 実行時に作成され、それまでは `ConditionPathIsDirectory` によって同期処理がスキップされる（エラーではなく正常な挙動）。
- 文献ディレクトリ内の変更（`references/<item>/paper.pdf` の差し替えなど）はファイル変更監視イベントで検知されないため、15分ごとの定期実行時に同期される。即座に同期したい場合は `zettelkasten-sync --only papis` を実行する。
- nixos-desktop 環境では `Assets/references/` に SATA ディスクの subvol（サブボリューム）をマウントしている。vault を clone した後にのみマウントされるため、新しい環境では clone 実行後に正しくマウントが始まるか確認すること（[disk-tiering.md](./disk-tiering.md#ディスクレイアウト) 参照）。
