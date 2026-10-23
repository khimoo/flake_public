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

  # data-disk.nix がこの保存先に @mimikopi をマウントする。
  local.mimikopi = {
    enable = true;
    dataDir = "/home/pomu/.local/share/mimikopi";
    inherit hsaOverrideGfxVersion;
  };

  # X のいいねの保存と意味検索。data-disk.nix がこの保存先に @x-likes をマウントし、
  # modules/nixos/x-likes.nix が Postgres のデータベースを用意する。
  local.xLikes = {
    enable = true;
    dataDir = "/home/pomu/.local/share/x-likes";
    projectDir = "/home/pomu/sagyo/x-likes-archive";
    inherit hsaOverrideGfxVersion;
    # 保存先の SATA SSD が壊れても残るよう、Google Drive に写す。
    backup = {
      repository = "rclone:gdrive:x-likes-backup";
      passwordFile = "${config.home.homeDirectory}/.config/x-likes/restic-password";
    };
  };
  local.profile.secrets = [
    {
      secret = "x_likes_restic_password";
      path = config.local.xLikes.backup.passwordFile;
    }
  ];

  home.packages = with pkgs; [
    prismlauncher
    wine64
    pkgsRocm.blender
  ] ++ extraGnomeExtensionsList;

  dconf.settings."org/gnome/shell".enabled-extensions =
    lib.mkAfter (map (ext: ext.extensionUuid) extraGnomeExtensionsList);
}
