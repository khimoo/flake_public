# vault の骨格の配布とミラー（使い方）

Obsidian vault（Zettelkasten）の**骨格**——ノートの分類フォルダ、運用ドキュメント
（`README.md` / `CLAUDE.md` / `IndexNote.md` / `Templates/` / 各フォルダの運用ルール）、
`.obsidian`（設定 + community plugin 本体）、`.claude/skills/`——を扱う 2 つの操作:

- **seed**: vault に無いものだけ、public repo のスナップショットを配る（非破壊）。
- **mirror**: vault 側で運用を変えたあと、たまに手動で public repo へ写して commit する。

ノート本文は骨格に含まれない。日常の desktop ↔ spin713 の同期は `obsidian-git`（vault の private
repo）が担うので、mirror はその代替ではない。

設計判断・責務分離は [../architecture/zettelkasten-vault-skeleton.md](../architecture/zettelkasten-vault-skeleton.md) を参照。
添付・papis の Drive 同期は別系統（[zettelkasten-attachments-sync.md](./zettelkasten-attachments-sync.md)）。

## 自分のマシンでは seed はほぼ動かない

vault は private notes repo の clone で用意しており、その clone が骨格を連れてくる。`seed-vault` は
既にあるものを上書きしないので、**この repo のホストでは実質 skip する**。設定やドキュメントが
新マシンに届く経路は clone であって、public repo ではない。

したがって:

- **新しいマシンを立てる前に mirror や push をする必要は無い。**
- seed が実際に配るのは、`initializeVault = true` で vault をゼロから作る環境（＝ノートの repo を
  持たない人）だけ。

「ほぼ」なのは、`.obsidian` 以外がファイル単位の seed だから。public 側の骨格に新しく足した
ファイルが vault に無ければ、それだけが次の switch で降ってくる。

## 対応環境

- NixOS ホスト（`nixos-desktop`, `nixos-spin713`）: `features.obsidian = true` を設定済み
- standalone home-manager: `mkHome` の `features.obsidian = true` で有効化

`features.obsidian` が gate するのは **Obsidian 本体の導入と `.obsidian` の seed** だけ。骨格
（分類フォルダ・運用ドキュメント）の seed は同期 feature 側にも載っているので、
`zettelkastenSync` か `referenceSync` だけ有効なホストでも骨格は配置される。

ノートの repo を持たない環境へ配るときは、`initializeVault = true` にしたうえで switch する
（zettelkasten-workflow の README にセットアップ手順がある）。

## mirror: vault の骨格を public repo へ反映する（たまに手動）

**いつ実行するか**: vault 側で運用を変えて（プラグイン設定・運用ルール・テンプレート・分類フォルダ）
配る版にも反映したくなったとき。マシンを追加したときではない。

HM 環境では `mirror-vault` が PATH に載る（`vaultSkeletonRepo` を設定したホストのみ）。vault と
dest は env 既定として焼き込み済みなので**引数なしで実行できる**:

```sh
mirror-vault --dry-run   # commit せず差分だけ表示（何が公開されるか確認）
mirror-vault             # rsync + commit まで。push はしない（人間ゲート）
# 確認してから push する:
git -C ~/sagyo/zettelkasten-workflow diff HEAD~1   # 漏洩ゲート（機密が混ざっていないか）
git -C ~/sagyo/zettelkasten-workflow push
# ↑ をまとめてやるなら:
mirror-vault --push      # commit 後に push まで
```

反映先は workflow repo の `skeleton/` 配下。push を既定でしないのは、`.obsidian` の sanitize が
denylist 方式ゆえ、新規プラグインが tracked な `data.json` に機密を書くと mirror で公開されうるため。
push 前の `git diff` を漏洩ゲートにする
（[設計判断の該当節](../architecture/zettelkasten-vault-skeleton.md#配るものの選び方は-2-通り)）。

push しただけでは消費側には届かない。反映するには消費側で input を更新する:

```sh
nix flake update zettelkasten
```

## 何が公開され、何が落ちるか

運ぶ物によって選び方が逆になる。

**`.obsidian` は denylist**。vault で git-tracked な `.obsidian` から、配布境界で以下を除いたもの:

| 落とすもの | 理由 |
|---|---|
| `.obsidian/workspace.json` / `workspace-mobile.json` | vault の `.gitignore` が除外（per-machine のレイアウト） |
| `.obsidian/plugins/realclaudian/data.json` | 同上（トークンを持ちうる） |
| `bookmarks.json` / `workspaces.json` | 自分のノートへの参照と名前付きレイアウト。vault では同期したいので untrack せず、配布境界で削除する |
| typst plugin | WSL の Obsidian を落とす。`community-plugins.json` の id も同時に除く |
| `obsidian-git` の `autoPullOnBoot` | remote を持たない配布先で起動ごとにエラー通知が出るため `false` に倒す |

**骨格は allowlist**。workflow repo の `nix/skeleton-paths.nix` に列挙したファイル（運用ドキュメント・
テンプレート・各フォルダの運用ルール・`lint-zettel` skill）と、空で配るフォルダだけが公開される。
`Zettel/` や `Dailies/` の中身は tracked でも運ばれない。

骨格に何かを足すときは、vault に置いたうえで `nix/skeleton-paths.nix` に列挙する。列挙したのに
vault に無いと mirror は中止する（黙って落とすと、直後の `rsync --delete` が repo 側からも消すため）。

`--dry-run` の出力にこれらが削除として現れていれば正常。

## ミラー先の設定（`vaultSkeletonRepo`）

mirror の dest は環境固有の checkout 位置なので、`flake.nix` の各ホストで `settings` に注入する。

| 属性 | 効果 |
|------|------|
| `vaultSkeletonRepo = "/abs/path"` | `mirror-vault` を PATH に載せ、dest 既定として焼き込む |
| （未指定 = `null`） | `mirror-vault` を PATH に載せない（seed は独立して効く） |

`modules/home-manager/zettelkasten.nix` が `services.zettelkasten.mirrorRepo` へ橋渡しする。

自分の vault を骨格として別の repo へ配りたい場合は、dest を引数で渡せばよい（owner は
ハードコードしていない）:

```sh
nix run github:khimoo/zettelkasten-workflow#mirror-vault -- /path/to/vault /path/to/config-repo
```

## トラブルシューティング

preflight が復旧手順つきで落ちるので、まずそのメッセージに従う。

| 症状 | 原因 / 対処 |
|------|-------------|
| `vault パスが未指定です` | 第1引数か `ZETTELKASTEN_ROOT` で vault を渡す。HM 経由なら `zettelkastenRoot` を確認 |
| `ミラー先 config repo が未指定です` | 第2引数か `ZETTELKASTEN_CONFIG_REPO` で dest を渡す。HM 経由なら `vaultSkeletonRepo` を確認 |
| `.obsidian が vault で git tracked ではありません` | vault 側で `.obsidian` を `git add` していない（誤削除防止で中止する安全策）|
| `vault に .obsidian がありません` | まだ設定が無い。Obsidian か `seed-vault` で用意してから実行 |
| `配布対象が vault にありません` | `nix/skeleton-paths.nix` の列挙と vault が食い違っている。vault 側で用意するか列挙から外す |
| `--dry-run` で `(差分なし)` | vault と public が既に一致。mirror 不要 |
| seed したのに何も配られない | vault に既にある（clone 由来）。仕様どおりの skip |
| `vault が未 clone です(skip)` | private notes repo をまだ clone していない。clone 後に再 switch すれば骨格が配置される |
