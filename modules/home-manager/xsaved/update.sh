app="$XSAVED_PROJECT_DIR"
if [ ! -d "$app/.git" ]; then
  echo "xsaved-update: $app がありません。開発用の checkout から git clone で作成してください（docs/howtouse/xsaved.md）" >&2
  exit 1
fi
units=(xsaved-sync.timer xsaved-process.timer "${XSAVED_WEB_UNIT:-xsaved-web.socket}")
has_backup=false
if systemctl --user cat xsaved-backup.service >/dev/null 2>&1; then
  has_backup=true
  units+=(xsaved-backup.timer)
fi
# 動画のフレームの計算は、動いていたときだけ、取り込んだコードで続きから起動し直す。止めていたのは、
# GPU を使いたいユーザーが止めたからかもしれない。
frames=$(systemctl --user is-active xsaved-frames.service || true)
systemctl --user stop "${units[@]}" xsaved-web-server.service xsaved-frames.service
trap 'systemctl --user start "${units[@]}"; if [ "$frames" = active ]; then systemctl --user start --no-block xsaved-frames.service; fi' EXIT

# バックアップがある構成では、書き込みのロックを排他で取って、動いている取得や計算が終わるのを待ってから写す。
if [ "$has_backup" = true ]; then
  systemctl --user start xsaved-backup.service
fi
before=$(git -C "$app" rev-parse HEAD)
git -C "$app" pull --ff-only
git -C "$app" log --oneline "$before..HEAD"
xsaved migrate
