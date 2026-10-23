# エージェント設定 repo（agentConfigRoot）の中身から、ファイルの追加・削除で変わるものを作る。
# 何をどこへ張るかの約束（claude.nix、codex.nix）と違い、プロファイルの名簿や設定の値は
# 設定 repo が正本なので、評価時ではなく実行時に読む（mutable な checkout は評価に入れない）。
#
#   claude/profiles/<名前>.json  → 起動コマンド claude-<名前>（claude --settings で重ねる）
#   codex/<名前>.config.toml     → ~/.codex/<名前>.config.toml へのリンクと起動コマンド codex-<名前>
#                                  （codex/launch.py が系列 <名前> の最新版を選んで codex を起動する）
#   claude/settings.json         → ~/.claude/settings.json の同じ最上位キーへ反映する
#
# ~/.claude/settings.json は Claude Code も書き込む。設定 repo にあるキーは設定 repo の値で
# 上書きし（前回の反映の後に変わっていたら警告する）、設定 repo から消えたキーは消し、
# それ以外のキーは残す。値がオブジェクトのキー（enabledPlugins、env、hooks など）は一段下の
# キーごとに扱うので、/plugin で試しているプラグインのように利用者が足したキーは残る。
#
# switch のたびと、設定 repo の該当ファイルが変わったとき（Linux は systemd の path unit）に走る。
# 設計判断: docs/architecture/agent-config.md
{
  config,
  lib,
  pkgs,
  ...
}:

let
  root = config.local.profile.agentConfigRoot;
  home = config.home.homeDirectory;
  launcherDir = "${config.xdg.dataHome}/agent-launchers/bin";
  stateDir = "${config.xdg.stateHome}/agent-sync";

  syncText = ''
    dry_run=0
    if [ "''${1:-}" = "--dry-run" ]; then
      dry_run=1
    fi
    root=${lib.escapeShellArg root}
    launcher_dir=${lib.escapeShellArg launcherDir}
    state_dir=${lib.escapeShellArg stateDir}
    codex_dir=${lib.escapeShellArg "${home}/.codex"}
    settings_file=${lib.escapeShellArg "${home}/.claude/settings.json"}
    claude_bin=${lib.escapeShellArg "${pkgs.claude-code}/bin/claude"}
    codex_bin=${lib.escapeShellArg "${pkgs.codex}/bin/codex"}
    python_bin=${lib.escapeShellArg "${pkgs.python3}/bin/python3"}
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
  '';

  agentSync = pkgs.writeShellApplication {
    name = "agent-sync";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.jq
    ];
    text = syncText;
    # tests/default.nix が一時ディレクトリの設定 repo に対して本文を実行する。
    passthru.text = syncText;
  };
in
{
  config = lib.mkIf (root != null) (lib.mkMerge [
    {
      home.packages = [ agentSync ];
      home.sessionPath = [ launcherDir ];

      # 設定 repo の JSON が壊れていても switch は止めない（Claude Code の設定を変えずに警告する）。
      home.activation.agentSync = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        if [ -n "''${DRY_RUN_CMD:-}" ]; then
          ${lib.getExe agentSync} --dry-run || true
        else
          ${lib.getExe agentSync} || echo "agent-sync が失敗した。設定 repo の内容を確かめて agent-sync を実行し直す" >&2
        fi
      '';
    }
    (lib.mkIf pkgs.stdenv.isLinux {
      systemd.user.paths.agent-sync = {
        Unit.Description = "エージェント設定 repo のプロファイルと設定の変更を反映する";
        Path = {
          PathChanged = [
            "${root}/claude/profiles"
            "${root}/claude/settings.json"
            "${root}/codex"
          ];
          Unit = "agent-sync.service";
        };
        Install.WantedBy = [ "default.target" ];
      };
      systemd.user.services.agent-sync = {
        Unit.Description = "エージェント設定 repo のプロファイルと設定を反映する";
        Service = {
          Type = "oneshot";
          ExecStart = lib.getExe agentSync;
        };
      };
    })
  ]);
}
