# Minecraft バックアップ（使い方・セットアップ）

PrismLauncher のインスタンスを restic で世代管理し、Google Drive へ写す。インスタンスを
終了すると自動で走る。なぜこの構成かは
[../architecture/minecraft-backup.md](../architecture/minecraft-backup.md) を参照。

設定ファイル:
- `modules/home-manager/minecraft-backup.nix`（コマンドの定義とオプション）
- `modules/home-manager/minecraft-common.sh` / `minecraft-{backup,check,restore,sync}.sh`（本体）
- `hosts/nixos-desktop/home-manager-pomu.nix`（リポジトリ位置と送り先の指定）
- `hosts/nixos-desktop/data-disk.nix`（`/mnt/backup/minecraft` の作成）

| | |
|---|---|
| リポジトリ（正本） | `/mnt/backup/minecraft/repo` |
| 送り先（写し） | `gdrive:minecraft-backups/<ホスト名>` |
| 発火 | PrismLauncher の post-exit フック + 毎日の `mc-sync` タイマー |
| 保持 | 直近 3 / 日次 14 / 週次 8 / 月次 12（インスタンスごと） |

Drive 上のリポジトリはマシンごとに分かれている。デスクトップは
`gdrive:minecraft-backups/nixos-desktop` にしか書かず、他のマシンの領域は読むだけ。

## コマンド

| | |
|---|---|
| `mc-backup [ID...]` | 手元のリポジトリへ取り込み、Drive へ写す |
| `mc-check [ID...]` | 他のマシンがより新しい状態を持っていないか確かめる |
| `mc-restore --from HOST [ID...]` | 別のマシンの状態をこのマシンへ取り込む |
| `mc-sync` | 古い世代を刈り、Drive への転送を取り直す |

ID を省くと全インスタンスが対象。

## セットアップ（新しいマシンで一度だけ）

`prismlauncher.cfg` は Nix 管理下に無いので、GUI で設定する。

1. PrismLauncher → Settings → Custom Commands
2. Pre-launch command:
   ```
   mc-check "$INST_ID"
   ```
3. Post-exit command:
   ```
   mc-backup "$INST_ID"
   ```

インスタンス単位の Settings にも同じ欄があるが、そちらは `Override commands` を有効にした
インスタンスだけに効く。全インスタンスに効かせたいのでグローバル側に入れる。

設定できたか確認する:

```sh
grep -E 'PreLaunchCommand|PostExitCommand' ~/.local/share/PrismLauncher/prismlauncher.cfg
```

リポジトリは最初の `mc-backup` が自分で作る。事前の `restic init` は要らない。

## 動かす

インスタンスを終了すると `mc-backup` が走る。ランチャーはコマンドの完了を待つので、その間
インスタンスは実行中の表示のまま残る。ログはインスタンスのコンソールに出る。

手動で取ることもできる:

```sh
mc-backup 1.21          # インスタンス ID を指定
mc-backup               # 全インスタンス
```

起動中のインスタンスは書き込み途中の状態が写るのでスキップされ、その旨が stderr に出る。

Drive への転送に失敗しても警告だけ出して正常終了する。手元のリポジトリには既に入っている
ので、次の `mc-sync` が取り直す。旅行先などネットが無い場所を想定している。

## 別のマシンで続きを遊ぶ

デスクトップで遊んだ続きをラップトップで遊ぶ、という往復を想定した手順。**移動前に
デスクトップ側でインスタンスを一度終了しておく**（post-exit フックが Drive へ写す）。

持ち出す側で取り込む:

```sh
mc-restore --from nixos-desktop 1.21
mc-restore --from nixos-desktop        # 相手にある全インスタンス
```

取り込むと手元のインスタンスが上書きされる。手元の方が新しい場合は中止し、両方の日時を
表示する。それでも上書きするなら `--force`。

帰宅後は逆向きに:

```sh
mc-restore --from nixos-spin713 1.21
```

取り込み忘れて古い方で遊ぼうとすると、pre-launch の `mc-check` が起動を止めて、実行すべき
`mc-restore` の行を出す。ただしネットに繋がらないときは照合できないので通す。

Drive にどのマシンの領域があるか:

```sh
rclone lsf --dirs-only gdrive:minecraft-backups
```

## 中身

| 含める | 理由 |
|--------|------|
| `instance.cfg` / `mmc-pack.json` | インスタンス定義（MC バージョン・ローダー）。復元に必須 |
| `minecraft/saves` | ワールド本体。代替不能 |
| `minecraft/mods` | 無いと modded ワールドが開けない |
| `minecraft/config` | MOD 設定 |
| `minecraft/options.txt` | ゲーム内設定・キーバインド |
| `minecraft/resourcepacks` `shaderpacks` `screenshots` | |

これは allowlist なので、ここに無いものは入らない。`minecraft/backups`（ゲーム内バックアップ）、
`logs`、`cache` などは対象外。`assets/` と `libraries/` はランチャーが再取得する。

対象を変えるときは `minecraft-common.sh` の `MC_ITEMS` を編集する。

## 手元のリポジトリから戻す

同じマシンで過去の世代に戻す場合は restic を直接使う。

```sh
R=(restic --insecure-no-password -r /mnt/backup/minecraft/repo)

# 世代を選ぶ
"${R[@]}" snapshots --tag 1.21

# ワールドだけを別の場所へ出して中身を確かめる
"${R[@]}" restore <スナップショット ID> --target /tmp/mc-check

# インスタンスへ書き戻す（元の絶対パスに戻るので --target /）
"${R[@]}" restore <スナップショット ID> --target /
```

`--target /` はスナップショットに記録された絶対パスへ書き戻す。先に `/tmp` へ出して中身を
確かめてから本番へ戻すのが安全。

## 状態を見る

```sh
R=(restic --insecure-no-password -r /mnt/backup/minecraft/repo)

"${R[@]}" snapshots                     # 世代一覧
"${R[@]}" stats --mode raw-data         # 実際に使っている容量（重複排除後）
"${R[@]}" stats --mode restore-size     # 復元したときの合計サイズ

systemctl --user list-timers mc-sync    # 次回の刈り込み
journalctl --user -u mc-sync -n 50      # 直近のログ

rclone about gdrive:                    # Drive の空き
```

## 古い世代を消す

毎日 `mc-sync` が保持ポリシーに従って刈る。手で走らせることもできる:

```sh
mc-sync
```

リポジトリが `warnAtGiB`（既定 10 GiB）を超えると `mc-sync` が警告するが、容量を理由に
自動削除はしない。超えたら保持ポリシーを見直す。ポリシーは
`hosts/nixos-desktop/home-manager-pomu.nix` の `local.minecraftBackup.retention` で変える。

```nix
local.minecraftBackup.retention = [ "--keep-last=3" "--keep-daily=7" "--keep-monthly=6" ];
```

## restic 移行前の ZIP

`/mnt/backup/minecraft/*.zip` は restic 導入前の履歴で、restic には入っていない。当時の
状態が要るときはここから `unzip` する。Drive 側の同名アーカイブは Google One 失効時に
消えているので、これがその期間の唯一の写し。
