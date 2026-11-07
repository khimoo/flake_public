data="$XSAVED_DATA_DIR"
if [ "$XSAVED_CHECK_MOUNT" = true ]; then
  # 空の世代が日次の世代を押し出すので、マウントされていない保存先は写さない。
  if ! mountpoint -q "$data"; then
    echo "xsaved-backup: $data がマウントされていません" >&2
    exit 1
  fi
fi

# 取得や計算が書き込んでいる途中で写すと、データベースのダンプとファイルが別の時点の状態になる。
# 書き込んでいるサブコマンドが終わるのを待ち、写し終えるまで新しく始めさせない。
exec 9>"${XDG_RUNTIME_DIR:?}/xsaved-write.lock"
flock 9

# OCR と埋め込みの結果も入るので、データベースは丸ごと写す。復元すれば計算し直さずに済む。
# 圧縮しない形式にして、restic が前の日の写しと重なる部分を再利用できるようにする。
mkdir -p "$data/backup"
pg_dump --host=/run/postgresql --dbname="$XSAVED_DATABASE" --no-owner \
  --file="$data/backup/xsaved.sql.tmp"
mv "$data/backup/xsaved.sql.tmp" "$data/backup/xsaved.sql"

# 復元したデータを、どのコードと設定が作ったか分かるようにする。
app="$XSAVED_PROJECT_DIR"
xsaved_rev=$(git -C "$app" rev-parse HEAD 2>/dev/null || echo unknown)
if [ -n "$(git -C "$app" status --porcelain 2>/dev/null)" ]; then xsaved_rev="$xsaved_rev-dirty"; fi
printf 'flake_public %s\nxsaved %s\n' "$FLAKE_REV" "$xsaved_rev" \
  >"$data/backup/revisions"

# 配布元がモデルを消すと同じモデルを取り直せず、保存済みのベクトルと比べる検索ができなくなるので、
# モデルも写す。uv の環境は uv.lock から作り直せるので写さない。
paths=("$data/tweets" "$data/backup/xsaved.sql" "$data/backup/revisions")
if [ -d "$data/huggingface/hub" ]; then paths+=("$data/huggingface/hub"); fi

restic cat config >/dev/null 2>&1 || restic init
restic backup --tag xsaved "${paths[@]}"
flock --unlock 9
restic forget --tag xsaved --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune
