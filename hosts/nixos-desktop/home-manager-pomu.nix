{ config, pkgs, lib, ... }:

let
  extraGnomeExtensionsList = with pkgs.gnomeExtensions; [
    display-configuration-switcher
  ];

in {
  imports = [
    ../../profiles/home/pomu-workstation.nix
  ];

  # リポジトリを NVMe(/) ではなく SATA の @backup subvol に置く。/ は残り 2 割を切っている。
  # ディレクトリの作成と所有者付けは data-disk.nix が行う。
  # /mnt/backup/minecraft 直下には restic 移行前の ZIP が残っているので、repo/ に分ける。
  local.minecraftBackup = {
    enable = true;
    repoDir = "/mnt/backup/minecraft/repo";
    remote = "gdrive:minecraft-backups";
  };

  # 手書き PDF の取り込み。デバイスが見つからない間は何もせず終わる。
  # minecraft と同じく NVMe(/) ではなく SATA の @backup subvol に置く。取り込んだ PDF は
  # 増え続けるが、読むのは時々なので SATA で足りる。ディレクトリの作成と所有者付けは
  # data-disk.nix が行う。
  # このホストだけで有効にする。取り込みを 2 台で走らせると、状態ファイルがマシンごとに
  # 分かれているせいで両方が全件を落とす。
  local.quaderno = {
    enable = true;
    archiveDir = "/mnt/backup/quaderno";
  };

  # PyTorch の ROCm wheel に Navi 23 (gfx1032) 向けカーネルがないため、
  # gfx1030 として扱わせる（docs/architecture/mimikopi-env.md）。
  # data-disk.nix がこの保存先に @mimikopi をマウントする。
  local.mimikopi = {
    enable = true;
    dataDir = "/home/pomu/.local/share/mimikopi";
    hsaOverrideGfxVersion = "10.3.0";
  };

  home.packages = with pkgs; [
    prismlauncher
    wine64
    pkgsRocm.blender
  ] ++ extraGnomeExtensionsList;

  dconf.settings."org/gnome/shell".enabled-extensions =
    lib.mkAfter (map (ext: ext.extensionUuid) extraGnomeExtensionsList);
}
