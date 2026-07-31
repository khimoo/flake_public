# Obsidian 設定（`.obsidian`）の配布とミラー（使い方）

Obsidian vault（Zettelkasten）の `.obsidian`（設定 + community plugin 本体）を扱う 2 つの操作:

- **seed**: vault に `.obsidian` が無いとき、public repo のスナップショットを配る（非破壊）。
- **mirror**: vault の live 設定を変えたあと、たまに手動で public repo へ写して commit する。

日常の desktop ↔ spin713 の設定同期は `obsidian-git`（vault の private repo）が担うので、mirror は
その代替ではない。

設計判断・責務分離は [../architecture/zettelkasten-obsidian-config.md](../architecture/zettelkasten-obsidian-config.md) を参照。
添付・papis の Drive 同期は別系統（[zettelkasten-attachments-sync.md](./zettelkasten-attachments-sync.md)）。

## 自分のマシンでは seed は動かない（動かなくてよい）

vault は private notes repo の clone で用意しており、その clone が `.obsidian` を連れてくる。
`seed-obsidian` は `.obsidian` が既にあれば何もしないので、**この repo のホストでは必ず skip する**。
設定が新マシンに届く経路は clone であって、public repo ではない。

したがって:

- **新しいマシンを立てる前に mirror や push をする必要は無い。**
- seed が実際に配るのは、`initializeVault = true` で vault をゼロから作る環境（＝ノートの repo を
  持たない人）だけ。

## 対応環境

- NixOS ホスト（`nixos-desktop`, `nixos-spin713`）: `features.obsidianSeed = true` を設定済み
- standalone home-manager: `mkHome` の `features.obsidianSeed = true` で有効化

`features.obsidianSeed` が偽の環境では一切読み込まれず影響しない。この feature は seed だけでなく
Obsidian 本体の導入と `mirror-obsidian` の PATH 登録も兼ねる。

ノートの repo を持たない環境へ配るときは、`initializeVault = true` にしたうえで switch する
（zettelkasten-workflow の README にセットアップ手順がある）。

## mirror: live 設定を public repo へ反映する（たまに手動）

**いつ実行するか**: `.obsidian` の設定を変えて、配る版にも反映したくなったとき。マシンを追加した
ときではない。

HM 環境では `mirror-obsidian` が PATH に載る（`obsidianConfigRepo` を設定したホストのみ）。vault と
dest は env 既定として焼き込み済みなので**引数なしで実行できる**:

```sh
mirror-obsidian --dry-run   # commit せず差分だけ表示（何が公開されるか確認）
mirror-obsidian             # rsync + commit まで。push はしない（人間ゲート）
# 確認してから push する:
git -C ~/sagyo/zettelkasten-workflow diff HEAD~1   # 漏洩ゲート（機密が混ざっていないか）
git -C ~/sagyo/zettelkasten-workflow push
# ↑ をまとめてやるなら:
mirror-obsidian --push      # commit 後に push まで
```

push を既定でしないのは、sanitize が denylist 方式ゆえ、新規プラグインが tracked な `data.json` に
機密を書くと mirror で公開されうるため。push 前の `git diff` を漏洩ゲートにする
（[設計判断の該当節](../architecture/zettelkasten-obsidian-config.md#sanitize-は-2-段)）。

push しただけでは消費側には届かない。反映するには消費側で input を更新する:

```sh
nix flake update zettelkasten
```

## 何が公開され、何が落ちるか

公開されるのは vault で **git-tracked な `.obsidian`** から、配布境界で以下を除いたもの:

| 落とすもの | 理由 |
|---|---|
| `.obsidian/workspace.json` / `workspace-mobile.json` | vault の `.gitignore` が除外（per-machine のレイアウト） |
| `.obsidian/plugins/realclaudian/data.json` | 同上（トークンを持ちうる） |
| `bookmarks.json` / `workspaces.json` | 自分のノートへの参照と名前付きレイアウト。vault では同期したいので untrack せず、配布境界で削除する |
| typst plugin | WSL の Obsidian を落とす。`community-plugins.json` の id も同時に除く |
| `obsidian-git` の `autoPullOnBoot` | remote を持たない配布先で起動ごとにエラー通知が出るため `false` に倒す |

`--dry-run` の出力にこれらが削除として現れていれば正常。

## ミラー先の設定（`obsidianConfigRepo`）

mirror の dest は環境固有の checkout 位置なので、`flake.nix` の各ホストで `settings` に注入する。

| 属性 | 効果 |
|------|------|
| `obsidianConfigRepo = "/abs/path"` | `mirror-obsidian` を PATH に載せ、dest 既定として焼き込む |
| （未指定 = `null`） | `mirror-obsidian` を PATH に載せない（seed は独立して効く） |

`modules/home-manager/zettelkasten.nix` が `services.zettelkasten.obsidian.mirrorRepo` へ橋渡しする。

自分の `.obsidian` を別の config repo として配りたい場合は、dest を引数で渡せばよい（owner は
ハードコードしていない）:

```sh
nix run github:khimoo/zettelkasten-workflow#mirror-obsidian -- /path/to/vault /path/to/config-repo
```

## トラブルシューティング

preflight が復旧手順つきで落ちるので、まずそのメッセージに従う。

| 症状 | 原因 / 対処 |
|------|-------------|
| `vault パスが未指定です` | 第1引数か `ZETTELKASTEN_ROOT` で vault を渡す。HM 経由なら `zettelkastenRoot` を確認 |
| `ミラー先 config repo が未指定です` | 第2引数か `OBSIDIAN_CONFIG_REPO` で dest を渡す。HM 経由なら `obsidianConfigRepo` を確認 |
| `.obsidian が vault で git tracked ではありません` | vault 側で `.obsidian` を `git add` していない（誤削除防止で中止する安全策）|
| `vault に .obsidian がありません` | まだ設定が無い。Obsidian か `seed-obsidian` で用意してから実行 |
| `--dry-run` で `(差分なし)` | vault と public が既に一致。mirror 不要 |
| seed したのに `.obsidian` が配られない | vault に既に `.obsidian` がある（clone 由来）。仕様どおりの skip |
