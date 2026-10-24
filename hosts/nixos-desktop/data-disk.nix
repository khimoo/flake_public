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
{ config, pkgs, lib, settings, utils, ... }:
let
  hm = config.home-manager.users.${settings.primaryUser};
  # fileSystems の名前を users.users から作ると、NFS の要否の判定を通って fileSystems に戻り、
  # 評価が無限再帰になる。NixOS の既定のホームの場所から作り、一致は assertion で確かめる。
  home = "/home/${settings.primaryUser}";
  vaultRoot = hm.local.profile.memexRoot;
  # btrfs は FS 全体で 1 UUID。各 subvol は subvol= オプションで選ぶので全マウントで共有する。
  device = "/dev/disk/by-uuid/57ba3e14-4099-4708-a643-edfc45d3eb18";

  # SSD 向けに noatime、コールド/メディア層は zstd 圧縮（既圧縮ファイルは btrfs が自動スキップ）。
  dataOpts = [ "noatime" "compress=zstd" ];

  # {subvol, path, opts} のリストから fileSystems を生成し、エントリの手書き重複を避ける。
  mounts = [
    { subvol = "@downloads"; path = "${home}/ダウンロード";  opts = dataOpts; }
    { subvol = "@videos";    path = "${home}/ビデオ";        opts = dataOpts; }
    { subvol = "@music";     path = "${home}/音楽";          opts = dataOpts; }
    { subvol = "@pictures";  path = "${home}/画像";          opts = dataOpts; }
    { subvol = "@documents"; path = "${home}/ドキュメント";  opts = dataOpts; }
    # Steam のライブラリ。ゲームは 1 本で数十 GB になり NVMe の残量を最も削るが、
    # ロードはシーケンシャル読みが中心なので SATA で足りる。
    { subvol = "@games";     path = "${home}/Games";         opts = dataOpts; }
    { subvol = "@backup";    path = config.local.dataDisk.backupDir; opts = dataOpts; }
    # VM は chattr +C で NOCOW 済み（CoW 断片化対策）。NOCOW ファイルには圧縮が効かないので付けない。
    { subvol = "@vm";        path = "/var/lib/libvirt/images";  opts = [ "noatime" ]; }
    # 耳コピの ML モデルの環境とチェックポイント。subvol は手で作るので、作る前に switch や
    # 再起動をしても起動を止めないよう nofail にする。マウントに失敗したときにルートへ書き込ませない
    # 確認は mimikopi-env が受け持つ（docs/architecture/mimikopi-env.md）。
  ] ++ lib.optional hm.local.mimikopi.enable
    { subvol = "@mimikopi"; path = hm.local.mimikopi.dataDir; opts = dataOpts ++ [ "nofail" ]; }
    # X のいいねとブックマークの保存。@mimikopi と同じく手で作る subvol なので nofail にし、マウントの確認は
    # xsaved-env が受け持つ（docs/architecture/xsaved.md）。
    ++ lib.optional hm.local.xsaved.enable
    { subvol = "@xsaved"; path = hm.local.xsaved.dataDir; opts = dataOpts ++ [ "nofail" ]; };
in
{
  options.local.dataDisk.backupDir = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    default = "/mnt/backup";
    description = "Mount point of the @backup subvol. Home Manager settings read it through osConfig to place backups under it.";
  };

  config = {
    assertions = [
      {
        assertion = config.users.users.${settings.primaryUser}.home == home;
        message = "data-disk.nix: ${settings.primaryUser} のホームが ${home} ではないので、データ層のマウント先がホームの外になる";
      }
    ];

    fileSystems = builtins.listToAttrs (map (m: {
      name = m.path;
      value = {
        inherit device;
        fsType = "btrfs";
        options = [ "subvol=${m.subvol}" ] ++ m.opts;
      };
    }) mounts);

    # papis ライブラリは vault(Obsidian)配下の Assets/references/ に置く方針(vault で完結)。マウント先を
    # vault の中にすることで、実体は SATA(コールド/バルク層)のまま、論理的には vault の 1 フォルダに
    # 見える。同期は services.memex.papis が所有する(同じパスを見ている)。
    #
    # ここだけ fileSystems ではなく systemd.mounts なのは、mount 先の親が vault の clone だから。
    # 無条件に mount すると systemd が clone より先に root 所有の中間ディレクトリを作り、
    # clone-repos の git clone が「空でない」「書けない」で失敗する。vault が実在するとき
    # (= .git がある)だけ mount することで、clone → mount の順序を条件で表現する。
    # 初回 clone の後は、下の path unit が .git の出現を見て mount を始める。
    systemd.mounts = [{
      what = device;
      where = "${vaultRoot}/Assets/references";
      type = "btrfs";
      options = lib.concatStringsSep "," ([ "subvol=@papis" ] ++ dataOpts);
      unitConfig.ConditionPathExists = "${vaultRoot}/.git";
      wantedBy = [ "local-fs.target" ];
    }];
    systemd.paths.papis-references = {
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathExists = "${vaultRoot}/.git";
        Unit = "${utils.escapeSystemdPath "${vaultRoot}/Assets/references"}.mount";
      };
    };

    # @backup subvol は root 所有なので、そのままではユーザーのバックアップ処理が書き込めない。
    # 用途ごとのディレクトリを primaryUser 所有で用意する（@backup の直下は root のまま残し、
    # 用途が増えたときに混ざらないようにする）。systemd-tmpfiles は local-fs.target の後に走るので、
    # マウント前の root ファイルシステム側に作られてマウントに隠される事故は起きない。
    systemd.tmpfiles.rules =
      lib.optional hm.local.minecraftBackup.enable
        "d ${dirOf hm.local.minecraftBackup.repoDir} 0755 ${settings.primaryUser} users -"
      ++ lib.optional hm.local.quaderno.enable
        "d ${hm.local.quaderno.archiveDir} 0755 ${settings.primaryUser} users -";

    # btrfs をカーネル/システムで扱えるように（root は ext4 なので既定では無効）+ メンテ用 CLI。
    boot.supportedFilesystems = [ "btrfs" ];
    environment.systemPackages = [ pkgs.btrfs-progs ];
  };
}
