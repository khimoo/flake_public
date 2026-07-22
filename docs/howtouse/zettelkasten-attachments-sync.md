# Zettelkasten 添付フォルダの Google Drive 同期（使い方）

Obsidian vault（Zettelkasten）の添付フォルダ（`~/sagyo/zettelkasten/attachments`）を
Google Drive と双方向同期する。実体はローカルにも残し、rclone bisync でミラーする。
git には blob を載せない（vault の `.gitignore` で `/attachments/` を除外）。

同期は rclone bisync、トリガーは watchexec のフォルダ監視。秘密（rclone.conf）は
[papis 同期](./papis-gdrive-sync.md)と**同じ secret を共有**し（sops 暗号化、workflow repo が所有）、
同期コマンドが実行のたびに自動で復号する（復号先の常駐ファイルは無い）。

設計判断・責務分離は [../architecture/zettelkasten-attachments-sync.md](../architecture/zettelkasten-attachments-sync.md) を参照。

## 対応環境

- NixOS ホスト（`nixos-desktop`, `nixos-spin713`）: `features.zettelkastenSync = true` を設定済み
- standalone home-manager（macOS 等）: `mkHome` の `features.zettelkastenSync = true` で有効化
- **home-manager 非対応環境**: `nix run github:khimoo/zettelkasten-workflow` でワンショット同期（下記）

`features.zettelkastenSync` が偽の環境（WSL 等）では一切読み込まれず影響しない。

## 仕組みの所在（workflow flake / flake_public）

- 同期の**仕組み**は mechanism リポジトリ（public repo `khimoo/zettelkasten-workflow`。取得は `github:`）の `flake.nix` が持つ
  （`nix/sync-script.nix` = 同期本体、`nix/with-rclone-secret.nix` = 実行時復号、
  `nix/hm-module.nix` = watcher 常駐）。ノート本文は別の private repo `khimoo/zettelkasten`。
- `flake_public` は input として取り込み、`modules/home-manager/zettelkasten.nix` が
  vault clone 位置（`zettelkastenRoot`。添付フォルダは既定でその下の `attachments/`）を注入する。
  secret の配線は不要（同期コマンド自身が復号するため）。

## secret（rclone.conf）のセットアップ

papis 同期と**まったく同じ** gdrive remote・`rclone_conf` secret を使う。
既に papis 同期をセットアップ済みなら、secret はそのまま流用され追加作業は不要。
未セットアップなら、[papis 同期の使い方](./papis-gdrive-sync.md#このリポジトリを初めて使うマシンのセットアップ)
の「SSH 鍵を age に変換 → `secrets/rclone.yaml` を作成/更新」の手順をそのまま行う。
暗号文・受信者一覧・実行時復号はすべて workflow repo が所有し、`zettelkasten-sync` が
実行のたびに `~/.ssh/id_ed25519`（ssh-to-age 変換）で復号する。rebuild 側の配線は無い。

> **素の `rclone` を手で叩くとき（`$SECRET`）**: 常駐の復号先は無いので一時的に復号する。
> 手順は [papis 同期の使い方](./papis-gdrive-sync.md#このリポジトリを初めて使うマシンのセットアップ)
> 冒頭の注記を参照（使い終わったら消す）。

## 初回セットアップ（rebuild 後）

`~/sagyo/zettelkasten/attachments` に添付が入った状態で、以下の順序を守る:

```sh
# a. Drive 側フォルダを一度だけ作る（無いと resync が directory not found で失敗する）
#    $SECRET は前節の注記どおり一時復号で用意する（この手順にだけ必要）
rclone --config "$SECRET" mkdir gdrive:zettelkasten-attachments

# b. 添付が入った状態で baseline を作る（空ディレクトリで作ると以降の同期を拒否される）
#    ※ Obsidian か Neovim(<leader>p) で画像を1枚貼ってから実行する
zettelkasten-sync --resync

# c. baseline が出来てから watcher を起動する
systemctl --user restart zettelkasten-sync
```

> 順序の理由は papis と同じ（[運用上の制約](../architecture/zettelkasten-attachments-sync.md#運用上の性質既知の制約)）。
> item を入れてから resync、resync してから watcher 起動。

## home-manager 非対応環境（`nix run`）

自分が home-manager の無いマシン（借り物 PC・一時的なマシン）に居て、
常駐なしにワンショットで同期したいとき。復号は自動なので、鍵だけ用意する:

```sh
# 鍵: 受信者登録済みの ~/.ssh/id_ed25519 があれば何もしなくてよい。
# 無いマシンでは、受信者登録済みの age 鍵（Bitwarden 等に保管）を渡す:
#   export SOPS_AGE_KEY='AGE-SECRET-KEY-...'
# ※ mechanism repo は public なので flake の取得に SSH 鍵は不要（github: で https 取得）。
#   鍵が要るのは runtime の rclone 復号だけ（上の SOPS_AGE_KEY / id_ed25519）。
ZETTELKASTEN_ATTACHMENTS_DIR="$HOME/path/to/vault/attachments" \
  nix run github:khimoo/zettelkasten-workflow -- --resync   # 初回のみ --resync、以降は引数なし
```

- sops を使わず手元の rclone.conf で同期する場合は `RCLONE_CONFIG=/path/to/rclone.conf` を
  渡す（復号をスキップする escape hatch）。
- remote 名を変えたいときは `ZETTELKASTEN_REMOTE=myremote:folder` も渡す
  （既定 `gdrive:zettelkasten-attachments`）。

## 日常運用

- 画像を貼る:
  - Obsidian: 通常どおり貼り付け（`attachmentFolderPath=attachments` に保存される）
  - Neovim: Markdown で `<leader>p`（img-clip が vault ルートの `attachments/` に保存）
- ローカルで添付が増減すると watcher が検知し、5 秒デバウンス後に自動 bisync
- 他マシンで追加した添付は、次に自分がローカル変更 / 手動同期した時に pull される
- 手動同期: `zettelkasten-sync`
- ログを見る:
  - Linux: `journalctl --user -u zettelkasten-sync -f`
  - macOS: `~/Library/Logs/zettelkasten-sync.log`

## トラブルシューティング

preflight が復旧手順つきで落ちるので、まずそのメッセージに従う。

| 症状 | 原因 / 対処 |
|------|-------------|
| `復号鍵が見つかりません` | `~/.ssh/id_ed25519` が無い。鍵を置くか、`SOPS_AGE_KEY` で age 鍵を渡すか、`RCLONE_CONFIG` で既存 conf を指す |
| `復号に失敗しました` | この鍵が `.sops.yaml` の受信者に未登録。公開鍵を追加して `sops updatekeys secrets/rclone.yaml` |
| `同期対象ディレクトリが未指定です` | `ZETTELKASTEN_ATTACHMENTS_DIR` 未設定。HM 経由なら `zettelkasten.nix` の `zettelkastenRoot`（→ `attachments.dir`）を確認 |
| `添付フォルダが見つかりません` | まだ画像を貼っていない。Obsidian か `<leader>p` で 1 枚作る |
| `rclone 設定ファイルが存在しません` | 明示した `RCLONE_CONFIG` の指し先誤り |
| `remote '...' が未定義です` | `rclone config` で remote を作るか、既存 rclone.conf を `RCLONE_CONFIG` で指す |
| `認証に失敗しました` | token 失効。`rclone config reconnect gdrive:` で再認証 |
| `--resync が中止される` | baseline が既存（誤上書き防止）。意図的なら `ZETTELKASTEN_FORCE_RESYNC=1` |
| resync が `directory not found` | Drive 側フォルダ未作成。`rclone --config "$SECRET" mkdir gdrive:zettelkasten-attachments` |
| `Empty prior Path1 listing` | 空フォルダで baseline を作った。画像を入れて `ZETTELKASTEN_FORCE_RESYNC=1 zettelkasten-sync --resync` |
