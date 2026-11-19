# 自分用サーバの aiboard を、引数をそのまま渡して ssh 越しに実行する。
# 引数は printf %q でエスケープしてから、サーバのログインシェル（bash）に渡す。
# shellcheck disable=SC2029
exec ssh -o BatchMode=yes "$AIBOARD_SERVER" "$(printf '%q ' aiboard "$@")"
