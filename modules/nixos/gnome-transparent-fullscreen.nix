# 全画面にした半透明のウィンドウ越しに、壁紙や下のウィンドウを見えるようにする。
# 設計判断は docs/architecture/gnome-transparent-fullscreen.md、使い方は docs/howtouse/cli-tools/kitty.md。
{ config, lib, pkgs, ... }:
let
  cfg = config.local.gnome.transparentFullscreen;
in
{
  options.local.gnome.transparentFullscreen.enable = lib.mkEnableOption
    "a patched mutter that keeps the content below a translucent fullscreen window visible";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.desktopManager.gnome.enable;
        message = "local.gnome.transparentFullscreen: GNOME が無効なホストには差し替える mutter がない";
      }
    ];

    # mutter を上書きすると、依存する gnome-shell なども binary cache に無くなり、手元で
    # ビルドすることになる。置換なら新たにビルドするのは mutter だけで済む。
    system.replaceDependencies.replacements = [
      {
        oldDependency = pkgs.mutter;
        newDependency = pkgs.callPackage ../../packages/mutter-transparent-fullscreen { };
      }
    ];
  };
}
