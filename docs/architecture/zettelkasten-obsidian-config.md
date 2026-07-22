# Obsidian 設定（`.obsidian`）の配布と将来の source-of-truth 分離（設計判断）

Obsidian vault（Zettelkasten）の `.obsidian`（設定 + community plugin 本体）を、fresh マシンでも
「clone してそのまま動く」状態にするための配布方式と、その source-of-truth を将来どこに置くかの構想。

添付・papis の Drive 同期は [zettelkasten-attachments-sync.md](./zettelkasten-attachments-sync.md) を参照
（`.obsidian` 設定はそれとは別系統で、Drive ではなく git に載る）。

## 現状: public repo から seed-once コピー（非破壊）

`.obsidian` の sanitize 済みスナップショットを public repo `khimoo/zettelkasten-workflow` が
`packages.obsidian-config` として持ち、`seed-obsidian`（`nix run` app と HM activation が共有する
1 本のスクリプト）が vault へ**非破壊コピー**する。vault に `.obsidian` が既にあれば何もしない。

- **copy であって symlink ではない**。Obsidian は起動中 `.obsidian`（`workspace.json` 等）へ常時
  書き込むが、nix store は read-only なので symlink できない。ゆえに書き込める copy を置く。
- **seed-once**。既存の live 設定を上書きしないため、初回の1回だけ baseline を配る。以降の変更は
  各マシン local に残り、baseline の更新は手動。
- flake_public 側は `services.zettelkasten.obsidian.enable`（feature `obsidianSeed`）で有効化し、
  vault 位置（`zettelkastenRoot`）だけを注入する薄い glue。

## 現状の live 設定同期は private notes repo が兼ねている

`.obsidian`（`workspace.json` 等の可変ファイルを除く）は private notes repo `khimoo/zettelkasten` に
tracked で、`obsidian-git` の vault 同期に相乗りしている。これが実質 desktop ↔ spin713 の**設定同期**を
担う。public repo の seed は seed-once・非同期なので、この同期は肩代わりしない。両マシンとも Obsidian を
常用するため、この同期は実運用で効いている。

## 将来構想: config を public repo に寄せ、config=public / notes=private で分離

やりたいのは、**設定の変更は public repo（zettelkasten-workflow）で、ノート（zettel）の変更は
private repo（zettelkasten）で**追尾する分離。public repo を「seed-once の静的スナップショット」から
「config の生きた source-of-truth」へ格上げする。

機構は copy でなく **symlink**。vault の `.obsidian`（または個別ファイル）を zettelkasten-workflow の
**ローカル checkout（working tree。nix store ではない）** に張る。nvim/wezterm や Claude 設定を
`mkOutOfStoreSymlink` でリポジトリ実体へ直リンクしているのと同じ発想
（[claude-config.md](./claude-config.md) が out-of-store symlink + パス注入の先例）。Obsidian の書き込みが
public repo の working tree に落ち、そこから config を commit できる。

未確定のまま残す論点:

- `.obsidian` を丸ごと張るか個別ファイルか。`workspace.json` など**可変・per-machine な state を
  public repo に載せない**除外設計（public repo 側 `.gitignore`）が要る。
- private repo が tracked している現状の `.obsidian` からの**移行手順**。単純に untrack すると、pull した
  他マシンで tracked config が working tree から消え、seed は「`.obsidian` あり」で skip して再配置しない
  ため設定が欠ける。desktop ↔ spin713 の同期を切らさない段取りが要る。
- リンク先 checkout の位置は環境固有なので、直書きせず settings 経由で注入する
  （claude-config.md と同じパス注入方針）。

2026-07-22 時点では未実装（「今はここまでやらなくていい」判断）。当面は現状の seed-once + private repo
同期で運用し、上記の分離は将来の課題として残す。
