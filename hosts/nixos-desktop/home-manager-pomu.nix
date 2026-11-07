{ config, pkgs, lib, ... }:

let
  # PyTorch の ROCm wheel に Navi 23 (gfx1032) 向けカーネルがないため、
  # gfx1030 として扱わせる（docs/architecture/mimikopi-env.md）。
  hsaOverrideGfxVersion = "10.3.0";

  extraGnomeExtensionsList = with pkgs.gnomeExtensions; [
    display-configuration-switcher
  ];

in {
  imports = [
    ../../profiles/home/pomu-workstation.nix
  ];

  # X のいいねとブックマークの保存と意味検索。data-disk.nix がこの保存先に @xsaved をマウントし、
  # modules/nixos/xsaved.nix が Postgres のデータベースを用意する。
  local.xsaved = {
    enable = true;
    dataDir = "/home/pomu/.local/share/xsaved";
    projectDir = "/home/pomu/.local/share/xsaved-app";
    inherit hsaOverrideGfxVersion;
    # 保存先の SATA SSD が壊れても残るよう、Google Drive に写す。
    backup = {
      repository = "rclone:gdrive:xsaved-backup";
      passwordFile = "${config.home.homeDirectory}/.config/xsaved/restic-password";
    };
  };
  home.packages = with pkgs; [
    prismlauncher
    wine64
    pkgsRocm.blender
  ] ++ extraGnomeExtensionsList;

  dconf.settings."org/gnome/shell".enabled-extensions =
    lib.mkAfter (map (ext: ext.extensionUuid) extraGnomeExtensionsList);
}
