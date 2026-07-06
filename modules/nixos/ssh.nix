# SSH サーバ + mDNS 公開 + マシン間 SSH の配線
# 用途: 他ホストからの SSH ログイン受け入れ、`<hostname>.local` での名前解決、
#       および flake 内の全マシンへ短縮名で SSH できるクライアント設定の生成。
# 例: どのホストからでも `ssh desktop` / `ssh spin713` で接続でき、ラップトップからの
#     `nixos-rebuild --build-host pomu@nixos-desktop.local` の known_hosts 追加も兼ねる。
#
# マシンの追加/廃棄は hosts/machines.nix の 1 エントリ増減だけで完結する。
{ lib, settings, ... }:
let
  # flake 内の全マシンの user 公開鍵（単一の情報源）
  machines = import ../../hosts/machines.nix;
  # `nixos-` プレフィックスを剥がした短縮エイリアス（nixos-desktop → desktop）
  shortName = host: lib.removePrefix "nixos-" host;
in {
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # 登録済み全マシンの公開鍵で primaryUser のログインを許可する。
  # 自分自身の鍵を含めても無害。マシン追加は machines.nix に 1 行足すだけで全ホストに反映。
  users.users.${settings.primaryUser}.openssh.authorizedKeys.keys =
    lib.attrValues machines;

  # 各マシンへ短縮名で SSH できるクライアント設定を machines.nix から生成する。
  # 初回接続のホスト鍵は accept-new で自動信頼（未登録の新規のみ受理し、変更は拒否）。
  # /etc/ssh/ssh_config は root にも効くため、リモートビルドの known_hosts 追加も担う。
  programs.ssh.extraConfig = lib.concatStrings (lib.mapAttrsToList (host: _: ''
    Host ${shortName host} ${host} ${host}.local
      HostName ${host}.local
      User ${settings.primaryUser}
      StrictHostKeyChecking accept-new
  '') machines);

  # mDNS で自ホスト名を LAN に広告する
  # （printing.nix で services.avahi.enable / nssmdns4 は既に有効化済み。
  #   ここでは publish 設定のみを追加し、モジュール合成でマージされる）
  services.avahi.publish = {
    enable = true;
    addresses = true;
    domain = true;
    workstation = true;
  };
}
