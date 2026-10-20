# vault の骨格の配布とミラー（使い方）

Obsidian vault（Zettelkasten）の**骨格**——ノートの分類フォルダ、運用ドキュメント
（`Home.md` / `AGENTS.md` / `CLAUDE.md` / `Templates/` / `System/Bases/`）、
`.obsidian`（設定 + community plugin 本体）、`.agents/skills/` と `.claude/skills` のリンク——を扱う 2 つの操作:

- **seed**: vault に無いものだけ、public repo のスナップショットを配る（非破壊）。
- **mirror**: vault 側で運用を変えたあと、たまに手動で public repo へ写して commit する。

ノート本文は骨格に含まれない。日常の desktop ↔ spin713 の同期は `obsidian-git`（vault の private
repo）が担うので、mirror はその代替ではない。

設計判断・責務分離は [../architecture/zettelkasten-vault-skeleton.md](../architecture/zettelkasten-vault-skeleton.md) を参照。
添付・papis の Drive 同期は別系統（[zettelkasten-attachments-sync.md](./zettelkasten-attachments-sync.md)）。

## clone するマシンでは seed を生成しない

vault は private notes repo の clone で用意する。この repo は
`services.zettelkasten.initializeVault = false` を明示し、修正済み workflow では
`home.activation.seedVault` 自体を生成しない。削除したファイルを「無いから補充する」経路を止める。
利用側のassertionもseed activationの混入を拒否するため、古いinputのままの構成は適用前に止まる。

workflow の checkout を直したり push したりするだけでは更新されない。
`flake.lock` の `zettelkasten` input と、各PCへ適用する世代の更新が必要。

```sh
nix flake update zettelkasten
nix build .#checks.x86_64-linux.vault-seed-isolation --no-link
```

このチェックは desktop と spin713 の両方について、初期化が無効でseed activationが無いことを確かめる。
確認後、利用者が変更を共有し、各PCで通常の switch を行う。AI は switch を実行しない。
既に復活した旧ファイルは、この更新だけでは消えないため、notes repo 側の削除も同期する。

新しいマシンを立てる前に mirror する必要は無い。設定とドキュメントはnotes repoのcloneで届く。

## 対応環境

- NixOS ホスト（`nixos-desktop`, `nixos-spin713`）: `local.profile.features.obsidian = true` を設定済み
- standalone home-manager: 本人のhomeモジュールの `local.profile.features.obsidian = true` と `local.profile.zettelkastenRoot` で有効化

`local.profile.features.obsidian` は Obsidian 本体を導入する。`.obsidian` と分類フォルダ・
運用ドキュメントの自動配置は `initializeVault = true` の環境だけで行う。
同期featureを有効にするだけでは既存vaultへ骨格を補充しない。

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

mirror の dest は環境固有の checkout 位置なので、本人のhomeモジュールで `local.profile.vaultSkeletonRepo` に指定する。

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
| `vault が未 clone です(skip)` | private notes repo をまだ clone していない。初期化環境なら再 switch、既存vaultならnotes repoのclone内容を確認する |
