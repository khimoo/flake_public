# データ層ディスク（SATA SSD /dev/sda, Samsung 860）の btrfs subvol マウント定義。
#
# 役割分担（速度で 2 層に分ける）:
#   - NVMe (Samsung 980): ホットな領域。/ ・/nix/store ・swap ・開発作業（~/sagyo）・
#     ビルドキャッシュ等、ランダム小 IO とレイテンシが効くものを置く。
#   - SATA (このディスク): コールド/バルク/ネットワーク律速の領域。メディア・papis の
#     Google Drive ミラー・VM イメージ・バックアップ退避先。SATA でも体感差が出ない
#     ワークロードだけを追い出し、NVMe の容量を空ける。
#
# なぜ /nix/store をここに置かないか: store は rebuild/GC で数万個の小ファイルへ
# ランダム IO を叩く、NVMe が最も効くワークロード。SATA へ落とすと rebuild が
# 明確に遅くなるうえ、boot 初期に必要で分離も難しい。据え置きが最適。
#
# 設計判断: docs/architecture/disk-tiering.md
# 使い方:   docs/howtouse/disk-tiering.md
{ pkgs, ... }:
let
  # btrfs は FS 全体で 1 UUID。各 subvol は subvol= オプションで選ぶので全マウントで共有する。
  device = "/dev/disk/by-uuid/57ba3e14-4099-4708-a643-edfc45d3eb18";

  # SSD 向けに noatime、コールド/メディア層は zstd 圧縮（既圧縮ファイルは btrfs が自動スキップ）。
  dataOpts = [ "noatime" "compress=zstd" ];

  # {subvol, path, opts} のリストから fileSystems を生成し、8 エントリの手書き重複を避ける。
  mounts = [
    { subvol = "@papis";     path = "/home/pomu/papis-library"; opts = dataOpts; }
    { subvol = "@downloads"; path = "/home/pomu/ダウンロード";  opts = dataOpts; }
    { subvol = "@videos";    path = "/home/pomu/ビデオ";        opts = dataOpts; }
    { subvol = "@music";     path = "/home/pomu/音楽";          opts = dataOpts; }
    { subvol = "@pictures";  path = "/home/pomu/画像";          opts = dataOpts; }
    { subvol = "@documents"; path = "/home/pomu/ドキュメント";  opts = dataOpts; }
    { subvol = "@backup";    path = "/mnt/backup";              opts = dataOpts; }
    # VM は chattr +C で NOCOW 済み（CoW 断片化対策）。NOCOW ファイルには圧縮が効かないので付けない。
    { subvol = "@vm";        path = "/var/lib/libvirt/images";  opts = [ "noatime" ]; }
  ];
in
{
  fileSystems = builtins.listToAttrs (map (m: {
    name = m.path;
    value = {
      inherit device;
      fsType = "btrfs";
      options = [ "subvol=${m.subvol}" ] ++ m.opts;
    };
  }) mounts);

  # btrfs をカーネル/システムで扱えるように（root は ext4 なので既定では無効）+ メンテ用 CLI。
  boot.supportedFilesystems = [ "btrfs" ];
  environment.systemPackages = [ pkgs.btrfs-progs ];
}
