# 自分用サーバの xsaved の Web UI を、ssh のポート転送を通して開く。
# 転送が動いていなければ、手元の XSAVED_LOCAL_PORT からサーバの XSAVED_SERVER_PORT への転送を、背景で始める。
url="http://127.0.0.1:$XSAVED_LOCAL_PORT/"
if ! (exec 3<>"/dev/tcp/127.0.0.1/$XSAVED_LOCAL_PORT") 2>/dev/null; then
  if ! ssh -f -N -o BatchMode=yes -o ExitOnForwardFailure=yes \
    -L "127.0.0.1:$XSAVED_LOCAL_PORT:127.0.0.1:$XSAVED_SERVER_PORT" "$XSAVED_SERVER"; then
    echo "xsaved-web: 自分用サーバ $XSAVED_SERVER に接続できません" >&2
    exit 1
  fi
fi
exec xdg-open "$url"
