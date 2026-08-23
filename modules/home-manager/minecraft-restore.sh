# 別のマシンが Drive に置いた状態を取り込む。旅行への持ち出しと持ち帰りで使う。
#
# リポジトリはホストごとに分かれているので、どのマシンから取るかを --from で指定する。
# 取り込んだ後は手元のリポジトリにも記録する。これが無いと mc-check が
# 「相手の方が新しい」と言い続けて起動を止めてしまう。

usage() {
  cat >&2 <<'EOF'
使い方: mc-restore --from HOST [インスタンス ID...]

  HOST が Drive に置いた最新の状態を、このマシンへ取り込む。
  インスタンス ID を省くと、HOST 側にある全インスタンスが対象になる。

  --force   手元の方が新しいときも上書きする(手元の進行は失われる)

例:
  mc-restore --from nixos-desktop 26.3-snapshot-6
  mc-restore --from nixos-spin713
EOF
}

from=""
force=false
wanted=()

while [ $# -gt 0 ]; do
  case "$1" in
    --from)
      from="${2:-}"
      if [ -z "$from" ]; then
        echo "--from にはホスト名が要ります。" >&2
        exit 1
      fi
      shift 2
      ;;
    --force) force=true; shift ;;
    -h | --help) usage; exit 0 ;;
    -*) echo "解釈できないオプション: $1" >&2; usage; exit 1 ;;
    *) wanted+=("$1"); shift ;;
  esac
done

if [ -z "$from" ]; then
  echo "--from に取り出し元のホストを指定してください。Drive にあるのは:" >&2
  rclone lsf --dirs-only "$MC_REMOTE" >&2 || echo "  (Drive を読めませんでした)" >&2
  exit 1
fi

self="$(mc_host)"
if [ "$from" = "$self" ]; then
  echo "自分自身($self)からは復元できません。手元のリポジトリを直接使ってください:" >&2
  echo "  restic --insecure-no-password -r $MC_REPO restore latest --tag <ID> --target /" >&2
  exit 1
fi

src="$(mc_remote_repo "$from")"

if [ "${#wanted[@]}" -eq 0 ]; then
  mapfile -t wanted < <("${RESTIC[@]}" -r "$src" snapshots --no-lock --json | jq -r '.[].tags[]?' | sort -u)
  if [ "${#wanted[@]}" -eq 0 ]; then
    echo "$from のリポジトリにスナップショットがありません。" >&2
    exit 1
  fi
fi

restored=()
for name in "${wanted[@]}"; do
  if mc_running "$name"; then
    echo "SKIP ${name}: 起動中。終了してから復元すること" >&2
    continue
  fi

  # --target / で絶対パスへ書き戻すので、スナップショットの行き先を必ず確かめる。
  # --delete も付けるため、想定外の場所を指していたら被害が読めない。
  mapfile -t snap_paths < <("${RESTIC[@]}" -r "$src" snapshots --no-lock --tag "$name" --latest 1 --json \
    | jq -r '.[0].paths[]?')
  if [ "${#snap_paths[@]}" -eq 0 ]; then
    echo "SKIP ${name}: $from に該当するスナップショットがありません" >&2
    continue
  fi
  for p in "${snap_paths[@]}"; do
    case "$p" in
      "$MC_INSTANCES"/*) ;;
      *)
        echo "中止 ${name}: スナップショットが $MC_INSTANCES の外を指しています: $p" >&2
        exit 1
        ;;
    esac
  done

  remote_t="$(mc_latest_time "$src" "$name")"
  local_t=0
  if [ -f "$MC_REPO/config" ]; then
    local_t="$(mc_latest_time "$MC_REPO" "$name")"
  fi
  if [ "$local_t" -gt "$remote_t" ] && [ "$force" != true ]; then
    echo "中止 ${name}: 手元の方が新しい状態を持っています。" >&2
    echo "  手元 $(mc_fmt_time "$local_t") / $from $(mc_fmt_time "$remote_t")" >&2
    echo "  取り込むと手元の進行を失います。承知の上なら --force を付けてください。" >&2
    exit 1
  fi

  echo "==> ${name} を $from から取り込みます"
  # --delete: 向こうで消したワールドが手元に残らないようにする。
  # restic はスナップショットに含まれるディレクトリの内側しか消さない。
  "${RESTIC[@]}" -r "$src" restore latest --tag "$name" --target / --delete
  restored+=("$name")
done

if [ "${#restored[@]}" -eq 0 ]; then
  echo "取り込んだものはありません。" >&2
  exit 0
fi

echo "取り込んだ状態を手元のリポジトリにも記録します。"
mc_repo_ready
mc_backup_instances "${restored[@]}"

if ! mc_push; then
  echo "警告: Drive への同期に失敗しました。ネットに繋がったとき mc-sync が再試行します。" >&2
fi
