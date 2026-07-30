# papis（参照文献マネージャ）の使い方

papis のライブラリは vault 内の `~/sagyo/zettelkasten/references/` に置く。item ごとに
`info.yaml`（平文メタデータ）と PDF 実体が同じフォルダに同居するので、このフォルダを丸ごと
1 本の rclone bisync で同期すればメタデータも PDF も同時に揃う。

**同期のセットアップ・認証・トラブルシューティングは添付と共通**なので
[zettelkasten-attachments-sync.md](./zettelkasten-attachments-sync.md) を参照。本書は papis
固有の話だけを扱う。設計判断は [../architecture/papis-gdrive-sync.md](../architecture/papis-gdrive-sync.md)。

有効化は `features.referenceSync = true`。これ 1 本で papis 本体・`~/.config/papis/config`・
同期がまとめて入る。

## 文献を追加する

```sh
# PDF から（DOI などが埋まっていれば自動でメタデータ取得）
papis add --set ref hottbook path/to/paper.pdf

# DOI 指定で追加
papis add --from doi 10.1000/xyz123
```

`references/<item>/{info.yaml, *.pdf}` が作られる。

## citekey を pin する（`ref:`）

引用はファイルパスでなく citekey で参照するので、各 item の `info.yaml` の `ref:` に安定した
citekey を手で pin する運用にしている（自動 `ref-format` はあえて設定していない。理由は
[設計ドキュメント](../architecture/papis-gdrive-sync.md)）。

```yaml
# references/<item>/info.yaml
ref: hottbook
author: ...
title: ...
```

`papis edit` でエディタを開いて設定してもよい。

## 原稿から引用する

`.bib` を書き出して LaTeX/Markdown から `[@citekey]` や `\cite{citekey}` で参照する:

```sh
papis export --all --format bibtex > references.bib
```

自動書き出しはしていない（手動運用）。

## papis 固有の注意

- **最初の item を入れるまで同期 unit は動かない。** `references/` は `papis add` が初めて
  作るので、それまで `ConditionPathIsDirectory` で skip される（失敗ではない）。
- **item フォルダの中の変更は、イベントでは検知されない。** 変更検知は `references/` 直下
  しか見ないので、`references/<item>/paper.pdf` の書き換えは定期実行（既定 15 分）が拾う。
  すぐ反映したいときは `zettelkasten-sync --only papis` を手で打つ。
- **nixos-desktop では `references/` に SATA subvol を被せている**（実体をコールド層に置く）。
  vault が clone 済みのときだけマウントする条件付き unit なので、新マシンでは初回 clone の
  あとに一度マウントを起こす必要がある
  （[disk-tiering.md](./disk-tiering.md#レイアウト)）。
