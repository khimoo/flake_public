# インスタンスを手元の restic リポジトリへ取り込み、Drive の自ホスト領域へ写す。
#
# PrismLauncher の post-exit フック(Settings -> Custom Commands)から
# `mc-backup "$INST_ID"` として呼ぶ運用を想定している。引数なしなら全インスタンス。
#
# 世代の刈り込みはここではやらない。mc-sync のタイマーが受け持つ。

mc_repo_ready
mc_select "$@"
mc_backup_instances "${MC_SELECTED[@]}"

# Drive への転送は失敗しても後始末を止めない。旅行先でネットが無い状況を想定している。
# ローカルのリポジトリには既に入っているので、取り残しは mc-sync が拾う。
if ! mc_push; then
  echo "警告: Drive への同期に失敗しました。ネットに繋がったとき mc-sync が再試行します。" >&2
fi
