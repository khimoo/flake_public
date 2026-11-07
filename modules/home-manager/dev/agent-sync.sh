dry_run=0
if [ "${1:-}" = "--dry-run" ]; then
  dry_run=1
fi
marker="# agent-sync が生成する。手で編集しない。"
status=0

say() {
  if [ "$dry_run" = 1 ]; then
    echo "agent-sync: (dry-run) $*"
  else
    echo "agent-sync: $*"
  fi
}
warn() {
  echo "agent-sync: $*" >&2
}

if [ ! -d "$root" ]; then
  warn "$root がない。clone-repos で clone すると、次の実行から反映する"
  exit 0
fi

# 書き込みは同じディレクトリの一時ファイルから mv する。途中で止まっても古いか新しいかのどちらかが残る。
replace_file() {
  local dest=$1 mode=$2 tmp
  mkdir -p "$(dirname "$dest")"
  tmp=$(mktemp "$dest.XXXXXX")
  cat > "$tmp"
  chmod "$mode" "$tmp"
  mv -f "$tmp" "$dest"
}

# ---- 起動コマンドと Codex のプロファイルのリンク ----
wanted=" "
write_launcher() {
  local name=$1 body=$2 content
  content=$(printf '#!/bin/sh\n%s\n%s\n' "$marker" "$body")
  wanted="$wanted$name "
  if [ -f "$launcher_dir/$name" ] && [ "$(cat "$launcher_dir/$name")" = "$content" ]; then
    return 0
  fi
  say "$launcher_dir/$name を作る"
  if [ "$dry_run" = 0 ]; then
    printf '%s\n' "$content" | replace_file "$launcher_dir/$name" 755
  fi
}

valid_name() {
  case $1 in
    "" | *[!A-Za-z0-9_-]*) return 1 ;;
  esac
}

for profile in "$root"/claude/profiles/*.json; do
  [ -e "$profile" ] || continue
  name=$(basename "$profile" .json)
  if ! valid_name "$name"; then
    warn "$profile: 名前に使えない文字があるので飛ばす"
    continue
  fi
  write_launcher "claude-$name" "exec $(printf '%q' "$claude_bin") --settings $(printf '%q' "$profile") \"\$@\""
done

linked=" "
for profile in "$root"/codex/*.config.toml; do
  [ -e "$profile" ] || continue
  name=$(basename "$profile" .config.toml)
  if ! valid_name "$name"; then
    warn "$profile: 名前に使えない文字があるので飛ばす"
    continue
  fi
  write_launcher "codex-$name" "exec $(printf '%q' "$python_bin") $(printf '%q' "$root/codex/launch.py") $(printf '%q' "$codex_bin") $(printf '%q' "$name") \"\$@\""
  # Codex はプロファイルを CODEX_HOME 直下のファイルとして探すので、名前ごとに張る。
  link="$codex_dir/$name.config.toml"
  linked="$linked$name.config.toml "
  if [ "$(readlink "$link" 2> /dev/null)" != "$profile" ]; then
    if [ -e "$link" ] && [ ! -L "$link" ]; then
      warn "$link: 通常のファイルがあるので張らない"
    else
      say "$link を $profile へ張る"
      if [ "$dry_run" = 0 ]; then
        mkdir -p "$codex_dir"
        ln -sfn "$profile" "$link"
      fi
    fi
  fi
done

# 設定 repo から消えたプロファイルの後始末。この仕組みが作ったものだけを消す。
for launcher in "$launcher_dir"/*; do
  [ -f "$launcher" ] || continue
  grep -q -x -F -- "$marker" "$launcher" || continue
  case $wanted in
    *" $(basename "$launcher") "*) continue ;;
  esac
  say "$launcher を消す"
  if [ "$dry_run" = 0 ]; then
    rm -f -- "$launcher"
  fi
done
for link in "$codex_dir"/*.config.toml; do
  [ -L "$link" ] || continue
  case $(readlink "$link") in
    "$root"/codex/*) ;;
    *) continue ;;
  esac
  case $linked in
    *" $(basename "$link") "*) continue ;;
  esac
  say "$link を消す"
  if [ "$dry_run" = 0 ]; then
    rm -f -- "$link"
  fi
done

# ---- Claude Code のユーザー設定 ----
source_file="$root/claude/settings.json"
keys_file="$state_dir/claude-managed-paths.json"
applied_file="$state_dir/claude-applied.json"
if [ -f "$source_file" ]; then
  source_json=$(cat "$source_file")
else
  source_json='{}'
fi
current_json='{}'
if [ -f "$settings_file" ]; then
  current_json=$(cat "$settings_file")
fi
previous_keys='[]'
if [ -f "$keys_file" ]; then
  previous_keys=$(cat "$keys_file")
fi
applied_json='{}'
if [ -f "$applied_file" ]; then
  applied_json=$(cat "$applied_file")
fi

if ! jq -e 'type == "object"' > /dev/null 2>&1 <<< "$source_json"; then
  warn "$source_file が JSON のオブジェクトとして読めないので、Claude Code の設定は変えない"
  status=1
elif ! jq -e 'type == "object"' > /dev/null 2>&1 <<< "$current_json"; then
  warn "$settings_file が JSON のオブジェクトとして読めないので変えない"
  status=1
else
  # 管理するパス：値がオブジェクトのキーは [キー, 下のキー]、それ以外は [キー]。
  paths=$(jq -c '[to_entries[] | .key as $k | if (.value | type) == "object" then (.value | keys[] | [$k, .]) else [$k] end]' <<< "$source_json")
  jq -r -n --argjson src "$source_json" --argjson cur "$current_json" --argjson app "$applied_json" --argjson paths "$paths" '
    def value($o; $p): try ($o | getpath($p)) catch null;
    $paths[]
    | select(value($cur; .) != null and value($app; .) != null
             and value($cur; .) != value($app; .) and value($cur; .) != value($src; .))
    | join(".")' | while read -r key; do
    warn "$settings_file の $key は前回の反映の後に変わっていた。設定 repo の値で上書きする"
  done
  new_json=$(jq -n --argjson src "$source_json" --argjson cur "$current_json" --argjson prev "$previous_keys" --argjson paths "$paths" '
    reduce ($prev - $paths)[] as $p ($cur; try delpaths([$p]) catch .)
    | reduce $paths[] as $p (.;
        (if ($p | length) == 2 and ((.[$p[0]] | type) != "object") then .[$p[0]] = {} else . end)
        | setpath($p; $src | getpath($p)))')
  if [ "$(jq -c -S . <<< "$new_json")" != "$(jq -c -S . <<< "$current_json")" ]; then
    say "$settings_file に設定 repo のキーを反映する"
    if [ "$dry_run" = 0 ]; then
      printf '%s\n' "$new_json" | replace_file "$settings_file" 600
    fi
  fi
  if [ "$dry_run" = 0 ]; then
    printf '%s\n' "$paths" | replace_file "$keys_file" 600
    printf '%s\n' "$source_json" | replace_file "$applied_file" 600
  fi
fi

exit "$status"
