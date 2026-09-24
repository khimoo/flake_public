# nix-daemon のビルドを hosts/machines.nix の builders に常設で回す（nix.buildMachines）。
# nixos-rebuild だけでなく nix build / nix develop / direnv のビルドも回る。
# 設計判断は docs/architecture/remote-build.md、使い方は docs/howtouse/remote-build.md。
{ config, lib, settings, ... }:
let
  machines = import ../../hosts/machines.nix;
  cfg = config.local.remoteBuilders;
  builders = lib.filterAttrs (host: _: host != settings.hostname) machines.builders;
in
{
  options.local.remoteBuilders = {
    enable = lib.mkEnableOption "remote builds on the other hosts listed in hosts/machines.nix builders";
    localBuilds = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether this host also runs builds itself. When false, a build that no builder
        can take fails instead of running locally; pass `--max-jobs N` to allow it once.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = builders != { };
        message = "local.remoteBuilders: hosts/machines.nix の builders に ${settings.hostname} 以外のホストがない";
      }
      {
        assertion = config.services.tailscale.enable;
        message = "local.remoteBuilders: ビルダーへの接続名 `<短縮名>-ts` は、ssh.nix が tailscale を有効にしたホストでだけ生成する";
      }
    ];

    nix.distributedBuilds = true;
    nix.buildMachines = lib.mapAttrsToList (host: builder: {
      # ssh.nix が生成する tailnet 側の接続名。自宅 LAN の内外で同じ経路を使う。
      # `.local` の接続名にすると LAN の外で名前が引けず、ビルドが毎回手元に戻る。
      hostName = "${lib.removePrefix "nixos-" host}-ts";
      protocol = "ssh-ng";
      inherit (builder) system maxJobs supportedFeatures;
      # SSH を張るのは nix-daemon（root）で、root の ~/.ssh に id_lan はない。
      sshKey = "${config.users.users.${settings.primaryUser}.home}/.ssh/id_lan";
    }) builders;

    # ビルドの入力をビルダーが binary cache から直接取る。無効だと、手元のストアから
    # tailnet 越しに送る。
    nix.settings.builders-use-substitutes = true;

    # 0 にすると、Nix はビルダーに繋がらないときも手元でビルドせずに失敗する。
    # binary cache からの取得は止まらない。
    nix.settings.max-jobs = lib.mkIf (!cfg.localBuilds) 0;
  };
}
