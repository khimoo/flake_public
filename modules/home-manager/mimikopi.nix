# 耳コピの ML モデルを動かす環境。保存先と GPU の互換設定はユーザーが選ぶ。
{ config, lib, pkgs, ... }:
let
  cfg = config.local.mimikopi;
in
{
  options.local.mimikopi = {
    enable = lib.mkEnableOption "mimikopi ML environment";
    dataDir = lib.mkOption {
      type = lib.types.strMatching "/.*";
      description = "Absolute path to the mounted model environments and checkpoints.";
    };
    hsaOverrideGfxVersion = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional ROCm GPU compatibility version.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      (pkgs.callPackage ../../packages/mimikopi-env {
        inherit (cfg) dataDir hsaOverrideGfxVersion;
      })
    ];
  };
}
