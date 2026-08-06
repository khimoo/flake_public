# Minecraft バックアップ（使い方・セットアップ）

PrismLauncher のインスタンスを ZIP に固めて Google Drive へ送る。インスタンスを終了すると
自動で走る。なぜこの構成かは [../architecture/minecraft-backup.md](../architecture/minecraft-backup.md) を参照。

設定ファイル:
- `modules/home-manager/minecraft-backup.nix` / `minecraft-backup.sh`（`mc-backup` コマンド）
- `hosts/nixos-desktop/home-manager-pomu.nix`（出力先と送り先の指定）
- `hosts/nixos-desktop/data-disk.nix`（`/mnt/backup/minecraft` の作成）

| | |
|---|---|
| 出力先 | `/mnt/backup/minecraft/<インスタンス ID>_<YYYY-MM-DD>.zip` |
| 送り先 | `gdrive:minecraft-backups` |
| 発火 | PrismLauncher の post-exit フック |

同じ日に取り直すと同名で上書きされる。日をまたぐと別ファイルとして増える。

## セットアップ（新しいマシンで一度だけ）

`prismlauncher.cfg` は Nix 管理下に無いので、GUI で設定する。

1. PrismLauncher → Settings → Custom Commands
2. Post-exit command に次を入れる:
   ```
   mc-backup "$INST_ID"
   ```

インスタンス単位の Settings にも同じ欄があるが、そちらは `Override commands` を有効にした
インスタンスだけに効く。全インスタンスに効かせたいのでグローバル側に入れる。

設定できたか確認する:

```sh
grep PostExitCommand ~/.local/share/PrismLauncher/prismlauncher.cfg
```

## 動かす

インスタンスを終了すると走る。ランチャーはコマンドの完了を待つので、その間インスタンスは
実行中の表示のまま残る（`1.21` で 1〜2 分）。ログはインスタンスのコンソールに出る。

手動で取ることもできる:

```sh
mc-backup 1.21          # インスタンス ID を指定
mc-backup               # 全インスタンス
```

起動中のインスタンスは書き込み途中の状態が写るのでスキップされ、その旨が stderr に出る。

## 中身

| 含める | 理由 |
|--------|------|
| `instance.cfg` / `mmc-pack.json` | インスタンス定義（MC バージョン・ローダー）。復元に必須 |
| `minecraft/saves` | ワールド本体。代替不能 |
| `minecraft/mods` | 無いと modded ワールドが開けない |
| `minecraft/config` | MOD 設定 |
| `minecraft/options.txt` | ゲーム内設定・キーバインド |
| `minecraft/resourcepacks` `shaderpacks` `screenshots` | |

含めないもの: `minecraft/backups`（ゲーム内バックアップ。二重になる）、`logs`、`cache`、
`data`、`natives`、`usercache.json`、`realms_persistence.json`、`server-resource-packs`。
`assets/` と `libraries/` はランチャーが再取得するのでインスタンス外ごと対象外。

対象を変えるときは `minecraft-backup.sh` の `ITEMS` を編集する。

## 復元

```sh
# Drive から取る場合（ローカルに残っていれば不要）
rclone copy gdrive:minecraft-backups/1.21_2026-08-05.zip /tmp/

# インスタンスとして展開する
mkdir -p ~/.local/share/PrismLauncher/instances/1.21
unzip -d ~/.local/share/PrismLauncher/instances/1.21 /tmp/1.21_2026-08-05.zip
```

PrismLauncher を再起動すると一覧に出る。ローダー・ライブラリ・アセットは `mmc-pack.json` を
見てランチャーが取り直す。ワールドだけ戻したい場合は `minecraft/saves/<ワールド名>` だけを
既存インスタンスへ展開すればよい。

この手順は実際に復元して確かめたわけではないので、初めて使うときは既存インスタンスを
上書きしない名前で展開して確認するのが安全。

## 状態を見る

```sh
ls -lh /mnt/backup/minecraft            # ローカル
rclone ls gdrive:minecraft-backups      # Drive
rclone about gdrive:                    # Drive の空き

# ローカルと Drive が一致しているか（チェックサム比較）
rclone check /mnt/backup/minecraft gdrive:minecraft-backups
```

## 古い世代を消す

世代の刈り込みは自動化していない。日付付きファイル名なので、遊んだ日の数だけ両側に増える。
`1.21` は 1 回あたり 450M 前後なので、放置すると Drive を圧迫する。

```sh
rm /mnt/backup/minecraft/1.21_2026-07-*.zip
rclone delete gdrive:minecraft-backups --include '1.21_2026-07-*.zip'
```

消す前に `rclone ls` で残す世代を確認する。
