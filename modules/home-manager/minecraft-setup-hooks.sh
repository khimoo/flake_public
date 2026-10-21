# PrismLauncher のグローバルな Custom Commands に、mc-check（起動前）と mc-backup（終了後）を書く。
# 新しいマシンで一度だけ実行する。インスタンス単位の欄は Override commands を有効にした
# インスタンスにしか効かないので、全インスタンスに効くグローバル側（prismlauncher.cfg）に書く。
cfg=$MC_PRISM_CFG
dry_run=0
if [ "${1:-}" = "--dry-run" ]; then
  dry_run=1
fi

# 起動中の PrismLauncher は終了時に設定を書き戻し、ここでの変更を消す。
if pgrep -x prismlauncher > /dev/null; then
  echo "mc-setup-hooks: PrismLauncher が起動中。終了してから実行する" >&2
  exit 1
fi

# \" は Qt の INI のエスケープ。GUI で設定したときと同じ文字列になる。
# $INST_ID は Prism が展開する変数なので、ここでは展開しない。
# shellcheck disable=SC2016
export MC_PRE='PreLaunchCommand=mc-check \"$INST_ID\"'
# shellcheck disable=SC2016
export MC_POST='PostExitCommand=mc-backup \"$INST_ID\"'

for line in "$MC_PRE" "$MC_POST"; do
  key=${line%%=*}
  current=""
  if [ -f "$cfg" ]; then
    current=$(grep -m1 "^$key=" "$cfg" || true)
  fi
  printf '%s -> %s\n' "${current:-$key (未設定)}" "$line"
done

if [ "$dry_run" = 1 ]; then
  exit 0
fi

mkdir -p "$(dirname "$cfg")"
if [ ! -f "$cfg" ]; then
  printf '[General]\n' > "$cfg"
fi
tmp=$(mktemp "$cfg.XXXXXX")
# awk の -v は \" を解釈してしまうので、値は環境変数から読む。
awk '
  function flush() {
    if (!donePre) print ENVIRON["MC_PRE"]
    if (!donePost) print ENVIRON["MC_POST"]
    donePre = donePost = 1
  }
  /^\[/ {
    if (inGeneral) flush()
    inGeneral = ($0 == "[General]")
    if (inGeneral) seen = 1
    print
    next
  }
  inGeneral && /^PreLaunchCommand=/ { print ENVIRON["MC_PRE"]; donePre = 1; next }
  inGeneral && /^PostExitCommand=/ { print ENVIRON["MC_POST"]; donePost = 1; next }
  { print }
  END {
    if (inGeneral) flush()
    else if (!seen) { print "[General]"; flush() }
  }
' "$cfg" > "$tmp"
mv "$tmp" "$cfg"
