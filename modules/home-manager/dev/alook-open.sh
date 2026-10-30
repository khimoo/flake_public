# 指定した PC の Alook の Web UI をブラウザで開く。別の PC なら ssh でポートを転送してから開く。
# 使い方は docs/howtouse/cli-tools/alook.md。

# Alook のログインは Origin が http://localhost:15210 のときだけ通る。別の PC の Alook も
# 手元の同じアドレスへ転送するので、手元の Alook と別の PC への転送は同時に使えない。
port=15210
url=http://localhost:$port
state_dir=${XDG_RUNTIME_DIR:-/tmp}/alook-open
pid_file=$state_dir/forward.pid
target_file=$state_dir/forward.target
log_file=$state_dir/forward.log

usage() {
  echo "使い方: alook-open <接続先>"
  echo "接続先:"
  echo "  local  このPCの Alook"
  for entry in $ALOOK_OPEN_REMOTES; do
    echo "  ${entry%%=*}  ssh ${entry#*=} で転送した Alook"
  done
}

remote_host() {
  for entry in $ALOOK_OPEN_REMOTES; do
    if [ "${entry%%=*}" = "$1" ]; then
      echo "${entry#*=}"
      return 0
    fi
  done
  return 1
}

# このコマンドが作った転送が動いていれば、その接続先の名前を出力する。
active_forward() {
  [ -f "$pid_file" ] || return 1
  if ! kill -0 "$(cat "$pid_file")" 2>/dev/null; then
    rm -f "$pid_file" "$target_file"
    return 1
  fi
  cat "$target_file"
}

close_forward() {
  echo "alook-open: $1 への転送を閉じる"
  kill "$(cat "$pid_file")"
  rm -f "$pid_file" "$target_file"
  for _ in $(seq 50); do
    port_in_use || return 0
    sleep 0.1
  done
}

port_in_use() {
  [ -n "$(ss -Hltn "sport = :$port")" ]
}

open_url() {
  echo "alook-open: $1 の Alook を開く ($url)"
  xdg-open "$url" >/dev/null 2>&1 &
}

target=${1-}
if [ -z "$target" ]; then
  usage
  exit 0
fi

current=$(active_forward || true)

if [ "$target" = local ]; then
  if [ -n "$current" ]; then close_forward "$current"; fi
  if ! port_in_use; then
    echo "alook-open: このPCの Alook が起動していない。alook-app start で起動する" >&2
    exit 1
  fi
  open_url "このPC"
  exit 0
fi

if ! host=$(remote_host "$target"); then
  echo "alook-open: 接続先 $target は無い" >&2
  usage >&2
  exit 1
fi

if [ "$current" = "$target" ]; then
  open_url "$target"
  exit 0
fi
if [ -n "$current" ]; then close_forward "$current"; fi
if port_in_use; then
  echo "alook-open: このPCの $port 番ポートを別のプロセスが使っている。このPCの Alook なら alook-app stop で止める" >&2
  exit 1
fi

mkdir -p "$state_dir"
# ServerAlive を付けないと、相手の PC が止まっても転送が残り、開いた画面が応答しない。
setsid ssh -N \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=15 -o ServerAliveCountMax=2 \
  -L "$port:localhost:$port" "$host" \
  </dev/null >"$log_file" 2>&1 &
pid=$!
for _ in $(seq 150); do
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "alook-open: ssh $host で転送を作れなかった" >&2
    cat "$log_file" >&2
    exit 1
  fi
  if port_in_use; then
    echo "$pid" >"$pid_file"
    echo "$target" >"$target_file"
    open_url "$target"
    exit 0
  fi
  sleep 0.1
done
kill "$pid"
echo "alook-open: ssh $host の転送が 15 秒以内に始まらなかった" >&2
exit 1
