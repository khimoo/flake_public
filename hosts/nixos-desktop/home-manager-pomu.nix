{ skk-dict, settings, config, pkgs, lib, ... }:

let
  extraGnomeExtensionsList = with pkgs.gnomeExtensions; [
    display-configuration-switcher
  ];

in {
  imports = [ ../../modules/home-manager/minecraft-backup.nix ];

  # リポジトリを NVMe(/) ではなく SATA の @backup subvol に置く。/ は残り 2 割を切っている。
  # ディレクトリの作成と所有者付けは data-disk.nix が行う。
  # /mnt/backup/minecraft 直下には restic 移行前の ZIP が残っているので、repo/ に分ける。
  local.minecraftBackup = {
    enable = true;
    repoDir = "/mnt/backup/minecraft/repo";
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
