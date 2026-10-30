# `alook-open`: 手元または別の PC の Alook の Web UI をブラウザで開く。
# 使い方: docs/howtouse/cli-tools/alook.md
{ config, lib, pkgs, ... }:

let
  cfg = config.local.alookOpen;
in
{
  options.local.alookOpen = {
    enable = lib.mkEnableOption "`alook-open` (open the Alook web UI of this or another machine)";

    remotes = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = { desktop-ts = "desktop-ts"; };
      description = ''
        `alook-open <名前>` で開ける別の PC。値はその PC の SSH 接続名で、
        ユーザー名や鍵は SSH 設定から決まる。名前 `local` は手元の PC に使うので指定できない。
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = !(cfg.remotes ? local);
      message = "local.alookOpen.remotes: 名前 local は手元の PC に使う";
    }];

    home.packages = [
      (pkgs.writeShellApplication {
        name = "alook-open";
        runtimeInputs = with pkgs; [ openssh iproute2 coreutils util-linux xdg-utils ];
        runtimeEnv.ALOOK_OPEN_REMOTES =
          lib.concatStringsSep " " (lib.mapAttrsToList (name: host: "${name}=${host}") cfg.remotes);
        text = builtins.readFile ./alook-open.sh;
      })
    ];
  };
}
