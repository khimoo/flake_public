app="$XSAVED_PROJECT_DIR"
if [ ! -d "$app/.git" ]; then
  echo "xsaved-update: $app がありません。開発用の checkout から git clone で作成してください（docs/howtouse/xsaved.md）" >&2
  exit 1
fi
units=(xsaved-sync.timer xsaved-process.timer xsaved-web.socket)
if [ -n "$RESTIC_REPOSITORY" ]; then units+=(xsaved-backup.timer); fi
# 動画のフレームの計算は、動いていたときだけ、取り込んだコードで続きから起動し直す。止めていたのは、
# GPU を使いたいユーザーが止めたからかもしれない。
frames=$(systemctl --user is-active xsaved-frames.service || true)
systemctl --user stop "${units[@]}" xsaved-web-server.service xsaved-frames.service
trap 'systemctl --user start "${units[@]}"; if [ "$frames" = active ]; then systemctl --user start --no-block xsaved-frames.service; fi' EXIT

# バックアップは書き込みのロックを排他で取るので、動いている取得や計算が終わるのを待ってから写す。
if [ -n "$RESTIC_REPOSITORY" ]; then
  systemctl --user start xsaved-backup.service
else
  flock "${XDG_RUNTIME_DIR:?}/xsaved-write.lock" true
fi
before=$(git -C "$app" rev-parse HEAD)
git -C "$app" pull --ff-only
git -C "$app" log --oneline "$before..HEAD"
xsaved migrate
