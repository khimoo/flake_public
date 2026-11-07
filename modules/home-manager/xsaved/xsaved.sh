# ML の依存を取得できないときも sync を動かせるよう、計算するサブコマンドだけに ml を付ける。
# uv run は --exact がなければ既存の ml パッケージを消さないので、venv は共有できる。
case "${1-}" in
  ocr | embed | tag | frames | search | serve) extra=(--extra ml) ;;
  *) extra=() ;;
esac
run=(xsaved-env uv run --project "$XSAVED_PROJECT_DIR" "${extra[@]}" --frozen xsaved "$@")
case "${1-}" in
  # 読むだけのサブコマンドはロックを取らない。serve は何時間も動くので、取るとバックアップが始まらない。
  # frames も何日も動く。データベースに行を足すだけでファイルは書かず、pg_dump はそれだけで一つの時点の
  # 状態を写すので、ロックを取らなくてもバックアップのダンプとファイルは食い違わない。
  status | search | similar | serve | frames) exec "${run[@]}" ;;
  *) exec flock --shared "${XDG_RUNTIME_DIR:?}/xsaved-write.lock" "${run[@]}" ;;
esac
