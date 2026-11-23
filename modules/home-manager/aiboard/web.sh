remote=${AIBOARD_SSH_HOST:-$AIBOARD_DEFAULT_SSH_HOST}
port=25280
# Use a stable socket for this SSH peer; checking it avoids starting duplicate tunnels.
key=$(printf '%s' "$remote" | sha256sum)
key=${key%% *}
run_dir=${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}
control=$run_dir/aiboard-${key:0:16}.sock
if ! ssh -S "$control" -O check -- "$remote" >/dev/null 2>&1; then
    ssh -fNT -M -S "$control" -o ExitOnForwardFailure=yes \
        -L "127.0.0.1:$port:127.0.0.1:15280" -- "$remote"
fi
exec xdg-open "http://127.0.0.1:$port/"
