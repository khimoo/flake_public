data="$XSAVED_DATA_DIR"
snapshot=(latest --tag xsaved)

# ルートは空きが少なく、ダンプを読み込んだデータベースは数 GB になるので、保存先と同じディスクで試す。
work=$(mktemp -d "$data/restore-check.XXXXXX")
cleanup() {
  pg_ctl -D "$work/pg" -m fast stop >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

restic snapshots --tag xsaved --latest 1
restic restore "${snapshot[@]}" --target "$work/files" --include "$data/backup" >/dev/null
cat "$work/files$data/backup/revisions" 2>/dev/null || echo "このスナップショットにはコミットの記録がない"

# 本番のデータベースに触れないよう、一時的な Postgres にダンプを読み込む。
initdb -D "$work/pg" -U postgres --auth=trust -E UTF8 --locale=C.UTF-8 >/dev/null
pg_ctl -D "$work/pg" -l "$work/pg.log" -w -o "-c listen_addresses='' -c unix_socket_directories=$work" start >/dev/null
psql=(psql -h "$work" -U postgres -X -q -v ON_ERROR_STOP=1)
"${psql[@]}" -d postgres -c 'CREATE DATABASE restored'
"${psql[@]}" -d restored -f "$work/files$data/backup/xsaved.sql" >/dev/null
q() { "${psql[@]}" -d restored -At -c "$1"; }

echo "いいね $(q 'SELECT count(*) FROM tweets WHERE liked')、ブックマーク $(q 'SELECT count(*) FROM tweets WHERE bookmarked')、ツイート全体 $(q 'SELECT count(*) FROM tweets')"
echo "引用 $(q 'SELECT count(*) FROM quotes')、返信 $(q 'SELECT count(*) FROM replies')、メディア $(q 'SELECT count(*) FROM media')"
echo "ベクトル: ruri $(q 'SELECT count(*) FROM tweet_ruri')、Qwen の本文 $(q 'SELECT count(*) FROM tweet_qwen')、Qwen の画像 $(q 'SELECT count(*) FROM image_qwen')"
# データだけ復元できても索引が壊れていれば検索できないので、索引を使わせて確かめる。
echo "全文検索で「の」を含むツイート $(q "SET enable_seqscan = off; SELECT count(*) FROM tweets WHERE search_text &@~ 'の'") 件"
echo "ベクトル検索の結果 $(q 'SELECT count(*) FROM (SELECT tweet_id FROM tweet_ruri ORDER BY embedding <=> (SELECT embedding FROM tweet_ruri LIMIT 1) LIMIT 10) s') 件"

# メディアを全部戻す空きはないので、全ファイルがスナップショットにあることを一覧で確かめ、
# 一部だけ戻して中身をデータベースのハッシュと照合する。
restic ls "${snapshot[@]}" "$data/tweets/media" | sed -n "s|^$data/tweets/media/||p" | sort >"$work/listed"
q 'SELECT path FROM media' | sort >"$work/expected"
missing=$(comm -13 "$work/listed" "$work/expected" | wc -l)
echo "データベースにあってスナップショットにないメディア $missing 件"
q 'SELECT path, sha256 FROM media ORDER BY random() LIMIT 20' | tr '|' ' ' >"$work/sample"
includes=()
while read -r path _; do includes+=(--include "$data/tweets/media/$path"); done <"$work/sample"
restic restore "${snapshot[@]}" --target "$work/files" "${includes[@]}" >/dev/null
mismatched=0
while read -r path sha; do
  if [ "$(sha256sum "$work/files$data/tweets/media/$path" | cut -d' ' -f1)" != "$sha" ]; then
    echo "中身が一致しない: $path"
    mismatched=$((mismatched + 1))
  fi
done <"$work/sample"
echo "戻して照合したメディア $(wc -l <"$work/sample") 件、一致しないもの $mismatched 件"
echo "モデル: $(restic ls "${snapshot[@]}" "$data/huggingface/hub" | sed -n "s|^$data/huggingface/hub/\(models--[^/]*\)$|\1|p" | tr '\n' ' ')"

[ "$missing" -eq 0 ] && [ "$mismatched" -eq 0 ]
