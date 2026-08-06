# PrismLauncher のインスタンスから、復元に必要な部分だけを ZIP に固めて遠隔へ送る。
# shebang と set -o は writeShellApplication (minecraft-backup.nix) が付ける。
#
# 含めるもの (allowlist):
#   instance.cfg / mmc-pack.json … インスタンス定義(MC バージョン・ローダー)。復元に必須
#   minecraft/saves               … ワールド本体。代替不能
#   minecraft/mods                … 無いと modded ワールドが開けない
#   minecraft/config              … MOD 設定
#   minecraft/options.txt         … ゲーム内設定・キーバインド
#   minecraft/{resourcepacks,shaderpacks,screenshots}
#
# 含めないもの: minecraft/backups (ゲーム内バックアップ。二重になる)、logs、cache、
#   data、natives、usercache.json、realms_persistence.json、server-resource-packs。
#   assets/ libraries/ はランチャーが再取得するのでインスタンス外ごと対象外。
#
# 引数でインスタンス ID を指定すると、それだけを対象にする(既定は全部)。
# PrismLauncher の post-exit フックからは "$INST_ID" が渡る。

STAMP="$(date +%Y-%m-%d)"

ITEMS=(
  instance.cfg
  mmc-pack.json
  minecraft/saves
  minecraft/mods
  minecraft/config
  minecraft/options.txt
  minecraft/resourcepacks
  minecraft/shaderpacks
  minecraft/screenshots
)

mkdir -p "$MC_BACKUP_OUT"

matched=0
for dir in "$MC_BACKUP_INSTANCES"/*/; do
  name="$(basename "$dir")"
  [ -f "${dir}instance.cfg" ] || continue

  if [ "$#" -gt 0 ] && ! printf '%s\n' "$@" | grep -qxF "$name"; then
    continue
  fi
  matched=1

  # 起動中のインスタンスは書き込み途中の状態が写る。post-exit フック経由なら対象は
  # 既に終了しているので、これは手動実行時の保護として働く。
  if pgrep -af java | grep -qF "instances/${name}/"; then
    echo "SKIP ${name}: 起動中。終了してから取り直すこと" >&2
    continue
  fi

  present=()
  for item in "${ITEMS[@]}"; do
    if [ -e "${dir}${item}" ]; then
      present+=("$item")
    fi
  done
  if [ "${#present[@]}" -eq 0 ]; then
    echo "SKIP ${name}: 保存対象が一つも無い" >&2
    continue
  fi

  # 同名が残っていると zip は追記(古いエントリが残る)になるので、作り直す。
  archive="${MC_BACKUP_OUT}/${name}_${STAMP}.zip"
  rm -f "$archive"
  echo "==> ${name} -> ${archive}"
  ( cd "$dir" && zip -r -q "$archive" "${present[@]}" )
  echo "    size: $(du -h "$archive" | cut -f1)"

  echo "    upload -> ${MC_BACKUP_REMOTE}"
  rclone copy "$archive" "$MC_BACKUP_REMOTE"
done

# 指定した ID が一つも当たらないのは打ち間違いなので、黙って正常終了しない。
if [ "$#" -gt 0 ] && [ "$matched" -eq 0 ]; then
  echo "インスタンスが見つからない: $*" >&2
  exit 1
fi
