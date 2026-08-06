{ skk-dict, settings, config, pkgs, lib, ... }:

let
  extraGnomeExtensionsList = with pkgs.gnomeExtensions; [
    display-configuration-switcher
  ];

in {
  imports = [ ../../modules/home-manager/minecraft-backup.nix ];

  # 出力先を NVMe(/) ではなく SATA の @backup subvol にする。/ は残り 2 割を切っており、
  # 1 回で 700M 近く積むため。ディレクトリの作成と所有者付けは data-disk.nix が行う。
  local.minecraftBackup = {
    enable = true;
    outDir = "/mnt/backup/minecraft";
    remote = "gdrive:minecraft-backups";
  };

  home.packages = with pkgs; [
    prismlauncher
    wine64
    steam
    blender-hip
  ] ++ extraGnomeExtensionsList;

  dconf.settings."org/gnome/shell".enabled-extensions =
    lib.mkAfter (map (ext: ext.extensionUuid) extraGnomeExtensionsList);
}
