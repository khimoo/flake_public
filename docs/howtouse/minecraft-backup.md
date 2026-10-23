# Minecraft バックアップ

PrismLauncher のインスタンスを終了した際、restic を用いてローカルリポジトリ（`/mnt/backup/minecraft/repo`）へデータを取り込み、さらに Google Drive（`gdrive:minecraft-backups/<ホスト名>`）へ同期します。
Drive 上のリポジトリはマシンごとに隔離されており、各マシンは自身の領域にのみ書き込みを行い、他マシンの領域は読み取り専用として扱います。
設定は [home-manager-pomu.nix](../../hosts/nixos-desktop/home-manager-pomu.nix) の `local.minecraftBackup` で管理しており、現在は nixos-desktop でのみ有効化しています。

設計ドキュメント: [Minecraft バックアップの設計](../architecture/minecraft-backup.md)

## コマンド一覧

- `mc-backup [ID...]`: ローカルリポジトリへデータを取り込み、Drive へ同期する
- `mc-check [ID...]`: 他のマシンに新しい状態が存在しないか確認する
- `mc-restore --from HOST [ID...]`: 他のマシンの状態を自マシンへ取り込む
- `mc-sync`: 古いバックアップ世代を削除し、Drive への転送を再実行する（日次タイマーでも自動実行）

ID の指定を省略すると全インスタンスが対象になります。指定した ID に一致するインスタンスが 1 つも存在しない場合は、非ゼロのステータスコードで終了します。

## 新しいマシンでのセットアップ

PrismLauncher を終了してから、フック処理を設定します。

```sh
mc-setup-hooks --dry-run   # 変更前後の行を表示するだけで変更は行わない
mc-setup-hooks
grep -E 'PreLaunchCommand|PostExitCommand' ~/.local/share/PrismLauncher/prismlauncher.cfg
```

`prismlauncher.cfg` の `[General]` セクションに、起動前処理の `mc-check "$INST_ID"` と終了後処理の `mc-backup "$INST_ID"` が記述されます。
PrismLauncher が起動中だと終了時に設定ファイルが上書きされてしまうため、起動中に実行した場合は何もせずに終了します。
インスタンスごとの個別設定にも同項目の設定欄がありますが、そちらは `Override commands` を有効にしたインスタンスにのみ適用されます。

リポジトリは初回の `mc-backup` 実行時に自動作成されるため、あらかじめ `restic init` を実行しておく必要はありません。

## 通常時の挙動

インスタンスを終了すると `mc-backup` が自動実行されます。ランチャーはバックアップの完了を待機するため、その間インスタンスは実行中表示のまま維持され、ログはインスタンスのコンソールに出力されます。
手動でバックアップを取得する場合は `mc-backup 1.21` や `mc-backup`（全インスタンス対象）を実行します。起動中のインスタンスはセーブデータの書き込み途中である可能性があるためスキップされ、その旨が標準エラー出力に警告されます。

Drive への転送に失敗した場合でも警告を出力して正常終了します。データ自体はローカルリポジトリに保存されているため、次回の `mc-sync` 実行時に再転送されます。
クラッシュや強制終了が発生した場合はフックが実行されないため、そのセッションの変更分は次回正常終了したタイミングで取り込まれます。

## 別のマシンでプレイを継続する場合

マシンを移動する前に、元のマシンでインスタンスを一度正常終了させておきます（終了フックにより Drive へ同期されます）。
移動先のマシンでデータを取り込みます。

```sh
mc-restore --from nixos-desktop 1.21
mc-restore --from nixos-desktop        # 移行元にある全インスタンスを対象とする場合
```

手元のインスタンスデータは上書きされます。手元のデータの方が新しい場合は、両方の更新日時を表示して処理を停止します。強制的に上書きする場合は `--force` フラグを付与してください。
元のマシンに戻ってプレイを再開する際は、逆方向に `mc-restore --from nixos-spin713 1.21` を実行します。

データを取り込み忘れた状態で古い環境のまま起動しようとすると、起動前の `mc-check` が起動を差し止め、実行すべき `mc-restore` コマンドを表示します。なお、オフライン時は照合が行えないためチェックをスキップして起動を許可します。
Drive 上にどのマシンの領域が存在するかは `rclone lsf --dirs-only gdrive:minecraft-backups` で確認できます。

## バックアップ対象ファイル

`instance.cfg`、`mmc-pack.json`、および `minecraft/` ディレクトリ内の `saves`、`mods`、`config`、`options.txt`、`resourcepacks`、`shaderpacks`、`screenshots` のみを対象とします。
`minecraft/backups`（ゲーム内バックアップ機能の出力先）、`logs`、`cache` は除外され、`assets/` や `libraries/` はランチャーによって必要時に再ダウンロードされます。
対象を変更する場合は [minecraft-common.sh](../../modules/home-manager/minecraft-common.sh) 内の `MC_ITEMS` を編集してください。

## ローカルリポジトリから過去の世代へ復元する

```sh
R=(restic --insecure-no-password -r /mnt/backup/minecraft/repo)
"${R[@]}" snapshots --tag 1.21                                  # 対象の世代を選択
"${R[@]}" restore <スナップショット ID> --target /tmp/mc-check  # 別の場所に展開して内容を確認
"${R[@]}" restore <スナップショット ID> --target /              # 記録された絶対パスへ直接書き戻す
```

`--target /` を指定すると、スナップショットに記録された絶対パスへそのまま復元されます。あらかじめ `/tmp` などに展開して内容を確認してから復元を行ってください。

## 状態確認・古い世代の削除

```sh
R=(restic --insecure-no-password -r /mnt/backup/minecraft/repo)
"${R[@]}" snapshots                     # バックアップ世代の一覧を表示
"${R[@]}" stats --mode raw-data         # 重複排除後の実際の使用容量を確認
systemctl --user list-timers mc-sync
journalctl --user -u mc-sync -n 50
rclone about gdrive:                    # Drive の空き容量を確認
```

`mc-sync` は、インスタンスごとに直近 3 世代、日次 14 世代、週次 8 世代、月次 12 世代を残し、それより古い世代を自動削除します。
リポジトリ容量が `warnAtGiB`（規定値: 10 GiB）を超えると警告を出力しますが、容量超過のみを理由として強制削除することはありません。警告が出た場合は `local.minecraftBackup.retention` の保持世代設定を見直してください。

```nix
local.minecraftBackup.retention = [ "--keep-last=3" "--keep-daily=7" "--keep-monthly=6" ];
```

## restic 導入以前の ZIP アーカイブについて

`/mnt/backup/minecraft/*.zip` は restic 導入以前の過去ログであり、restic リポジトリには含まれていません。この期間のデータが必要な場合は手動で `unzip` して解凍してください。
Drive 上にあった同等のアーカイブは Google One 契約終了時に削除されたため、このローカルファイルが当該期間の唯一のバックアップとなります。
