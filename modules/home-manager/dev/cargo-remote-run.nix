# `cargo remote-run`: cargo run と同じ引数でビルドを別のホストに任せ、実行ファイルを手元で動かす。
# 使い方: docs/howtouse/remote-build.md / 設計判断: docs/architecture/remote-build.md
{ config, lib, pkgs, ... }:

let
  cfg = config.local.cargoRemoteRun;
in
{
  options.local.cargoRemoteRun = {
    enable = lib.mkEnableOption "`cargo remote-run` (build on another host, run the binary here)";

    host = lib.mkOption {
      type = lib.types.str;
      example = "desktop-ts";
      description = ''
        ビルドを任せるホストの SSH 接続名。ssh、rsync、nix copy（ssh-ng://）で使う。
        手元の devShell をこのホストへ送るので、接続するユーザーはホストの nix で
        trusted-users に入っている必要がある。
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      (pkgs.writeShellApplication {
        name = "cargo-remote-run";
        # cargo は devShell のものを、nix はシステムのものを使うので入れない。
        runtimeInputs = with pkgs; [ openssh rsync coreutils gnugrep ];
        runtimeEnv.CARGO_REMOTE_RUN_HOST = cfg.host;
        text = builtins.readFile ./cargo-remote-run.sh;
      })
    ];
  };
}
