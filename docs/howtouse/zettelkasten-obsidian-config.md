# Obsidian 設定（`.obsidian`）の配布とミラー（使い方）

Obsidian vault（Zettelkasten）の `.obsidian`（設定 + community plugin 本体）を扱う 2 つの操作:

- **seed**: fresh マシンで vault に `.obsidian` が無いとき、public repo のスナップショットを配る（非破壊）。
- **mirror**: vault の live 設定を変えたあと、たまに手動で config repo（public repo）へ写して commit する。

日常の desktop ↔ spin713 の設定同期は `obsidian-git`（vault の private repo）が担うので、mirror は
その代替ではない。config を大きく変えたときだけ派生スナップショットを追従させる操作。

設計判断・責務分離は [../architecture/zettelkasten-obsidian-config.md](../architecture/zettelkasten-obsidian-config.md) を参照。
添付・papis の Drive 同期は別系統（[zettelkasten-attachments-sync.md](./zettelkasten-attachments-sync.md)）。

## 対応環境

- NixOS ホスト（`nixos-desktop`, `nixos-spin713`）: `features.obsidianSeed = true` を設定済み
- standalone home-manager: `mkHome` の `features.obsidianSeed = true` で有効化
- **home-manager 非対応環境**: `nix run github:khimoo/zettelkasten-workflow#{seed,mirror}-obsidian`（下記）

`features.obsidianSeed` が偽の環境では一切読み込まれず影響しない。

## seed: fresh マシンへ `.obsidian` を配る

- **HM 環境**: rebuild 時に `home.activation.seedObsidian` が走る。`zettelkastenRoot/.obsidian` が
  無いときだけ public snapshot をコピーし、既存の live 設定には触らない（seed-once・非破壊）。
  ノートの private repo を clone したあとに rebuild すれば自動で配られる。
- **非 HM 環境**: `nix run` でワンショット配布（既存があれば skip）:

  ```sh
  nix run github:khimoo/zettelkasten-workflow#seed-obsidian -- /path/to/vault
  ```

## mirror: live 設定を config repo へ反映する（たまに手動）

`obsidian-git` が同期している vault の **tracked な** `.obsidian` を config repo へ写して commit する。
ミラー対象は各自の `.gitignore` が sanitize した集合（`git ls-files .obsidian`）なので、`workspace.json`
や token を持つ `data.json` 等は自動で除外される。

**いつ実行するか**: `.obsidian` の設定を大きく変えて、public のスナップショットを追従させたいとき。

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

push を既定でしないのは、denylist（`.gitignore` で列挙して落とす）方式ゆえ、新規プラグインが tracked な
`data.json` に機密を書くと mirror で公開されうるため。push 前の `git diff` を漏洩ゲートにする
（[設計判断の該当節](../architecture/zettelkasten-obsidian-config.md#sanitize--vault-の-gitignoretracked-集合がミラー対象)）。

**非 HM 環境 / fork**: dest を引数で渡す（owner はハードコードしていない）:

```sh
nix run github:khimoo/zettelkasten-workflow#mirror-obsidian -- /path/to/vault /path/to/config-repo
```

## ミラー先の設定（`obsidianConfigRepo`）

mirror の dest は環境固有の checkout 位置なので、`flake.nix` の各ホストで `settings` に注入する。

| 属性 | 効果 |
|------|------|
| `obsidianConfigRepo = "/abs/path"` | `mirror-obsidian` を PATH に載せ、dest 既定として焼き込む |
| （未指定 = `null`） | `mirror-obsidian` を PATH に載せない（seed は独立して効く） |

`modules/home-manager/zettelkasten.nix` が `services.zettelkasten.obsidian.mirrorRepo` へ橋渡しする。

## fork して使う

この public repo を fork した第三者は、`.obsidian` を自分の config repo で追いたいとき、mirror の dest に
**自分の repo** を渡すだけでよい。sanitize は各自の vault の `.gitignore` が担うので、公開してよい集合も
自分の gitignore で決まる。secret は一切触らない（`.obsidian` は暗号化しない公開設定）ため、同期
（rclone/sops）と違って fork 側で鍵を差し替える必要がない。

## トラブルシューティング

preflight が復旧手順つきで落ちるので、まずそのメッセージに従う。

| 症状 | 原因 / 対処 |
|------|-------------|
| `vault パスが未指定です` | 第1引数か `ZETTELKASTEN_ROOT` で vault を渡す。HM 経由なら `zettelkastenRoot` を確認 |
| `ミラー先 config repo が未指定です` | 第2引数か `OBSIDIAN_CONFIG_REPO` で dest を渡す。HM 経由なら `obsidianConfigRepo` を確認 |
| `.obsidian が vault で git tracked ではありません` | vault 側で `.obsidian` を `git add` していない（誤削除防止で中止する安全策）|
| `vault に .obsidian がありません` | まだ設定が無い。Obsidian か `seed-obsidian` で用意してから実行 |
| `--dry-run` で `(差分なし)` | vault と public が既に一致。mirror 不要 |
