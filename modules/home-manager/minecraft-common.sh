# mc-* 各コマンドの先頭に連結される共通部分。単体では実行されない。
# shebang と set -o は writeShellApplication (minecraft-backup.nix) が付ける。
#
# minecraft-backup.nix の runtimeEnv が次を与える:
#   MC_INSTANCES  PrismLauncher のインスタンス置き場
#   MC_REPO       ローカルの restic リポジトリ。ここが正本
#   MC_REMOTE     Drive 側の親ディレクトリ。この下にホスト名でリポジトリを分ける
#   MC_RETENTION  restic forget に渡す保持ポリシー(空白区切り)
#   MC_WARN_GIB   リポジトリがこの大きさを超えたら警告する

# リポジトリはパスワードを持たない。判断の理由は docs/architecture/minecraft-backup.md を参照。
RESTIC=(restic --insecure-no-password)

# 復元に必要なものだけを挙げた allowlist。除外リストにすると、新しく増えたゴミが黙って入る。
MC_ITEMS=(
  instance.cfg
  mmc-pack.json
  minecraft/saves
  minecraft/mods
  minecraft/config
  minecraft/options.txt
  minecraft/resourcepacks
  minecraft/shaderpacks
  minecraft/screenshots
)

# Drive 上の置き場所をホストごとに分けるための識別子。
# 2 台が同じリポジトリへ書くと、後から走った側の rclone sync が相手の世代を消す。
mc_host() {
  local h
  h="$(cat /etc/hostname 2>/dev/null || true)"
  if [ -z "$h" ]; then
    echo "/etc/hostname が読めません。Drive 上の置き場所を決められないので中止します。" >&2
    return 1
  fi
  printf '%s\n' "$h"
}

mc_remote_path() { printf '%s/%s\n' "$MC_REMOTE" "$1"; }
mc_remote_repo() { printf 'rclone:%s\n' "$(mc_remote_path "$1")"; }

# 対象インスタンスの ID を 1 行ずつ出す。引数があればその ID に絞る。
mc_instances() {
  local dir name
  for dir in "$MC_INSTANCES"/*/; do
    name="$(basename "$dir")"
    [ -f "${dir}instance.cfg" ] || continue
    if [ "$#" -gt 0 ] && ! printf '%s\n' "$@" | grep -qxF "$name"; then
      continue
    fi
    printf '%s\n' "$name"
  done
}

# mc_instances の結果を MC_SELECTED に入れる。一つも当たらないのは打ち間違いなので非ゼロで返す。
mc_select() {
  mapfile -t MC_SELECTED < <(mc_instances "$@")
  if [ "${#MC_SELECTED[@]}" -eq 0 ]; then
    if [ "$#" -gt 0 ]; then
      echo "インスタンスが見つかりません: $*" >&2
    else
      echo "インスタンスが一つもありません: $MC_INSTANCES" >&2
    fi
    return 1
  fi
}

# 起動中のインスタンスは書き込み途中の状態が写る。フック経由なら対象は既に終了しているので、
# これは手動実行時の保護として働く。
mc_running() {
  pgrep -af java | grep -qF "instances/${1}/"
}

# インスタンス配下で実在する対象だけを絶対パスで並べる。
mc_present_paths() {
  local dir="$1" item
  for item in "${MC_ITEMS[@]}"; do
    if [ -e "${dir}/${item}" ]; then
      printf '%s\n' "${dir}/${item}"
    fi
  done
}

# リポジトリが無ければ作る。あるときは何もしない。
mc_repo_ready() {
  if [ -f "$MC_REPO/config" ]; then
    return 0
  fi
  echo "restic リポジトリを作成します: $MC_REPO" >&2
  "${RESTIC[@]}" -r "$MC_REPO" init
}

# 指定タグの最新スナップショットの時刻を Unix 時間で返す。無ければ 0。読めなければ非ゼロ。
mc_latest_time() {
  local repo="$1" tag="$2" iso
  iso="$("${RESTIC[@]}" -r "$repo" snapshots --no-lock --tag "$tag" --latest 1 --json \
    | jq -r '.[0].time // empty')" || return 1
  if [ -z "$iso" ]; then
    printf '0\n'
    return 0
  fi
  date -d "$iso" +%s
}

mc_fmt_time() {
  if [ "$1" -eq 0 ]; then
    printf '記録なし\n'
  else
    date -d "@$1" '+%F %T'
  fi
}

# 対象インスタンスを手元のリポジトリへ取り込む。mc-backup と mc-restore の両方が使う。
mc_backup_instances() {
  local name dir paths
  for name in "$@"; do
    dir="$MC_INSTANCES/$name"

    if mc_running "$name"; then
      echo "SKIP ${name}: 起動中。終了してから取り直すこと" >&2
      continue
    fi

    mapfile -t paths < <(mc_present_paths "$dir")
    if [ "${#paths[@]}" -eq 0 ]; then
      echo "SKIP ${name}: 保存対象が一つも無い" >&2
      continue
    fi

    echo "==> ${name}"
    # --group-by host,tags: 対象の増減で paths が変わっても前回分を親として選べる。
    "${RESTIC[@]}" -r "$MC_REPO" backup --tag "$name" --group-by host,tags "${paths[@]}"
  done
}

# ローカルのリポジトリを Drive の自ホスト領域へ写す。sync なので削除も伝播する。
# 空や壊れたリポジトリで呼ぶと Drive 側を消してしまうので、config の存在を先に確かめる。
mc_push() {
  if [ ! -f "$MC_REPO/config" ]; then
    echo "リポジトリが見当たりません: $MC_REPO/config。Drive を消さないよう同期を中止します。" >&2
    return 1
  fi
  rclone sync "$MC_REPO" "$(mc_remote_path "$(mc_host)")"
}
