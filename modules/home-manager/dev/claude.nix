# Claude Code のユーザー設定 (~/.claude/) のうち git 管理するものを、エージェント設定 repo の
# clone (agentConfigRoot) へ out-of-store symlink で配線する。Codex 側は codex.nix。
#
# flake_public は公開リポジトリなので、private な設定 repo の固有名や中身には依存しない。
# agentConfigRoot が null (既定) なら何もしないため、この flake だけを使う人には影響しない。
# 期待するレイアウト:
#   <root>/claude/CLAUDE.md, settings.json, hooks/, output-styles/, agents/, commands/   Claude Code だけが読む
#   <root>/claude/profiles/<name>.json                                                  モデル別プロファイル (agentProfiles.claude)
#   <root>/shared/skills/                                                              Codex と共有
#
# ~/.claude 自体は Claude Code が settings.json や履歴等を書き込む live なディレクトリ
# なので丸ごとは symlink せず、git 管理したいエントリだけを個別に symlink する。
# out-of-store symlink のため、repo 側の編集は rebuild なしで即反映される。
#
# claudeDirs は Claude Code がユーザー設定を読む既知カテゴリのうち Claude 固有のもの。
# 各ディレクトリを丸ごと symlink するので、配下の agent/command 追加・編集は rebuild なしで
# 即反映される。repo にまだ存在しないカテゴリは dangling symlink になるが、Claude Code からは
# 「設定なし」に見えるだけで壊れない。repo 側でそのディレクトリを作った時点で live に
# なるため、Claude Code が全く新しいカテゴリを導入した時以外は switch が要らない。
#
# skills は Codex と同じ SKILL.md 形式。~/.claude/skills は shared/skills を指し、
# Codex は codex/skills の個別リンクから <root>/shared/skills の共有スキルを参照する。
#
# モデル別プロファイルは `claude --settings <file>` でユーザー設定の上に重ねる。alias ではなく
# PATH 上の実行ファイル (claude-<name>) にするのは、対話シェルの外 (IDE や他ツール) からの
# 起動でも同じ経路を使えるようにするため。素の claude はそのまま残る。プロファイルの中身は
# 起動時に読まれるので編集に switch は要らず、名前の追加・削除だけが switch を要する。
# `--resume` は transcript のモデルを優先するため、再開時にモデルを変えるなら `--model` を足す。
{
  config,
  lib,
  pkgs,
  ...
}:

let
  root = config.local.profile.agentConfigRoot;
  profiles = config.local.profile.agentProfiles.claude;
  claudeDirs = [ "agents" "commands" "output-styles" "hooks" ];
  mkLink = path: config.lib.file.mkOutOfStoreSymlink "${root}/${path}";
  mkLauncher =
    name:
    pkgs.writeShellScriptBin "claude-${name}" ''
      exec ${pkgs.claude-code}/bin/claude --settings ${lib.escapeShellArg "${root}/claude/profiles/${name}.json"} "$@"
    '';
in
{
  config = lib.mkIf (root != null) {
    home.file = {
      ".claude/CLAUDE.md".source = mkLink "claude/CLAUDE.md";
      ".claude/skills".source = mkLink "shared/skills";
    } // builtins.listToAttrs (map (d: {
      name = ".claude/${d}";
      value.source = mkLink "claude/${d}";
    }) claudeDirs);
    # Claude's atomic settings writer follows one symlink before creating its
    # temporary file. A home.file link lands in the read-only generation store.
    # Linux/Darwin: link directly to the mutable checkout after HM's link cleanup.
    # Dry runs do not write; rerunning repairs an interrupted/missing link.
    home.activation.claudeSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      settings_source=${lib.escapeShellArg "${root}/claude/settings.json"}
      settings_link=${lib.escapeShellArg "${config.home.homeDirectory}/.claude/settings.json"}
      if [ -n "''${DRY_RUN_CMD:-}" ]; then
        echo "Would link $settings_link directly to $settings_source"
      else
        if [ -e "$settings_link" ] && [ ! -L "$settings_link" ]; then
          echo "Refusing to replace unmanaged Claude settings: $settings_link" >&2
          exit 1
        fi
        mkdir -p "$(dirname "$settings_link")"
        ln -sfn "$settings_source" "$settings_link"
      fi
    '';
    home.packages = map mkLauncher profiles;
  };
}
