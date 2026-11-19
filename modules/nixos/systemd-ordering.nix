{ config, pkgs, ... }:
let
  systemd = config.systemd.package;
in
{
  # 起動順序の循環は評価でもビルドでも見つからず、起動のたびに systemd が循環の中のジョブを一つ取り消すだけで
  # 起動が続く（docs/architecture/disk-tiering.md）。toplevel のビルドに含めて、switch と CI のビルドを止める。
  system.checks = [
    # fileSystems のマウントはユニットのディレクトリになく、起動時に fstab から generator が作るので、ここでも作る。
    # SYSTEMD_PROC_CMDLINE を空にして、ビルドするマシンのカーネルのコマンドラインを generator に読ませない。
    # systemd-analyze verify は循環を見つけても 0 で終わるので、出力で判定する。
    # ビルドのサンドボックスには /run がなく、verify は /run/systemd を作れずに止まるので、bwrap で /run を用意する。
    # 入力のユニットはシステム全体のクロージャを参照する。リモートビルダーに送るとそれを丸ごと転送するので、手元でビルドする。
    (pkgs.runCommandLocal "systemd-ordering" { nativeBuildInputs = [ pkgs.bubblewrap ]; } ''
      gen=$PWD/generated
      mkdir -p "$gen"/normal "$gen"/early "$gen"/late
      SYSTEMD_FSTAB=${pkgs.writeText "fstab" config.environment.etc.fstab.text} \
        SYSTEMD_PROC_CMDLINE= SYSTEMD_IN_INITRD=0 \
        ${systemd}/lib/systemd/system-generators/systemd-fstab-generator "$gen"/normal "$gen"/early "$gen"/late
      SYSTEMD_UNIT_PATH="$gen/early:${config.environment.etc."systemd/system".source}:$gen/normal:$gen/late" \
        bwrap --bind /nix /nix --bind "$PWD" "$PWD" --proc /proc --dev /dev --tmpfs /run --tmpfs /tmp \
        ${systemd}/bin/systemd-analyze verify --man=no --generators=no default.target 2>&1 | tee verify.log
      if grep -q 'ordering cycle' verify.log; then
        echo "起動順序が循環している" >&2
        exit 1
      fi
      touch "$out"
    '')
  ];
}
