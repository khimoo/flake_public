# Claude Code の managed settings を、ユーザーの設定 repo にあるファイルへのリンクにする。
# managed settings はマシンの全ユーザーに掛かり、ユーザー設定より優先される。
# 文字列のパスで受けるのは、Nix store に写さず checkout を直接指すため。repo を直せば
# switch せずに次のセッションから効く（docs/architecture/agent-config.md）。
{ config, lib, ... }:
let
  path = config.local.claudeManagedSettings;
in
{
  options.local.claudeManagedSettings = lib.mkOption {
    type = lib.types.nullOr (lib.types.strMatching "/.+");
    default = null;
    description = "Absolute path of a managed-settings.json that /etc/claude-code/managed-settings.json links to. Applies to every user on the host.";
  };

  config = lib.mkIf (path != null) {
    environment.etc."claude-code/managed-settings.json".source = path;
  };
}
