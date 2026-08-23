# 世代の刈り込みと、失敗した Drive 転送の取り直しをまとめて行う。
#
# systemd の user timer から毎日呼ばれる (minecraft-backup.nix)。
# mc-backup が Drive への転送に失敗しても、ここが次の機会に拾う。

if [ ! -f "$MC_REPO/config" ]; then
  echo "リポジトリがまだありません: $MC_REPO。何もしません。" >&2
  exit 0
fi

read -ra retention <<< "$MC_RETENTION"

# --group-by host,tags: 保持数はインスタンスごとに数える。よく遊ぶワールドの世代を、
# 放置しているワールドの世代が押し出さないようにするため。
"${RESTIC[@]}" -r "$MC_REPO" forget "${retention[@]}" --group-by host,tags --prune

if ! mc_push; then
  echo "Drive への同期に失敗しました。次回のタイマーで再試行します。" >&2
  exit 1
fi

# 上限で自動削除はしない。保持ポリシーと綱引きになって、どの世代が残るか読めなくなる。
# 超えたら保持ポリシー自体を見直す判断をユーザーがする。
used="$("${RESTIC[@]}" -r "$MC_REPO" stats --mode raw-data --json | jq -r '.total_size')"
limit=$((MC_WARN_GIB * 1024 * 1024 * 1024))
if [ "$used" -gt "$limit" ]; then
  echo "警告: リポジトリが $((used / 1024 / 1024 / 1024)) GiB です (目安 ${MC_WARN_GIB} GiB)。" >&2
  echo "  保持ポリシー(retention)を短くするか、不要なインスタンスのタグを整理してください。" >&2
fi
