# 起動前に、他のマシンがより新しい状態を Drive に置いていないか確かめる。
#
# PrismLauncher の pre-launch フック(Settings -> Custom Commands)から
# `mc-check "$INST_ID"` として呼ぶ運用を想定している。非ゼロで返すと起動が中止される。
#
# ネットに繋がらないときは通す。旅行先で遊べなくなる方が困る。

mc_select "$@"
self="$(mc_host)"

if ! remote_hosts="$(rclone lsf --dirs-only "$MC_REMOTE" 2>/dev/null)"; then
  echo "注意: Drive を確認できませんでした。他のマシンの状態と照合せずに起動します。" >&2
  exit 0
fi

stale=false
for name in "${MC_SELECTED[@]}"; do
  local_t=0
  if [ -f "$MC_REPO/config" ]; then
    local_t="$(mc_latest_time "$MC_REPO" "$name")"
  fi

  while read -r host; do
    host="${host%/}"
    [ -n "$host" ] || continue
    [ "$host" != "$self" ] || continue

    remote_t="$(mc_latest_time "$(mc_remote_repo "$host")" "$name")" || continue
    [ "$remote_t" -gt "$local_t" ] || continue

    echo "中止 ${name}: $host の方が新しい状態を持っています。" >&2
    echo "  手元 $(mc_fmt_time "$local_t") / $host $(mc_fmt_time "$remote_t")" >&2
    echo "  取り込んでから遊ぶ: mc-restore --from $host $name" >&2
    stale=true
  done <<< "$remote_hosts"
done

if [ "$stale" = true ]; then
  exit 1
fi
