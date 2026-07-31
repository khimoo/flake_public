# SSH サーバ + mDNS 公開 + マシン間 SSH の配線
# 用途: 他ホストからの SSH ログイン受け入れ、`<hostname>.local` での名前解決、
#       および flake 内の全マシンへ短縮名で SSH できるクライアント設定の生成。
# 例: どのホストからでも `ssh desktop` / `ssh spin713` で接続でき、ラップトップからの
#     `nixos-rebuild --build-host pomu@nixos-desktop.local` の known_hosts 追加も兼ねる。
#
# マシンの追加/廃棄は hosts/machines.nix の 1 エントリ増減だけで完結する。
{ lib, settings, ... }:
let
  # LAN 共通鍵の公開鍵とホスト一覧（単一の情報源）
  machines = import ../../hosts/machines.nix;
  # `nixos-` プレフィックスを剥がした短縮エイリアス（nixos-desktop → desktop）
  shortName = host: lib.removePrefix "nixos-" host;

  home = "/home/${settings.primaryUser}";
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

  # LAN 共通鍵 1 本で primaryUser のログインを許可する。全マシンが同じ鍵を持つので
  # マシンを増やしても authorized_keys は変わらない。
  users.users.${settings.primaryUser}.openssh.authorizedKeys.keys =
    [ machines.lanPublicKey ];

  # 各マシンへ短縮名で SSH できるクライアント設定を machines.nix から生成する。
  # 初回接続のホスト鍵は accept-new で自動信頼（未登録の新規のみ受理し、変更は拒否）。
  # /etc/ssh/ssh_config は root にも効くため、リモートビルドの known_hosts 追加も担う。
  #
  # IdentitiesOnly は付けない。root には ~/.ssh/id_lan が無く、
  # `sudo nixos-rebuild --build-host` は env_keep した SSH_AUTH_SOCK 越しの agent で認証する。
  # IdentitiesOnly yes を付けると agent の鍵が無視されリモートビルドが壊れる
  # （存在しない IdentityFile は単に読み飛ばされるので、指定するだけなら無害）。
  programs.ssh.extraConfig = lib.concatStrings (map (host: ''
    Host ${shortName host} ${host} ${host}.local
      HostName ${host}.local
      User ${settings.primaryUser}
      IdentityFile ${home}/.ssh/id_lan
      StrictHostKeyChecking accept-new
  '') machines.hosts) + ''
    Host github.com
      User git
      IdentityFile ${home}/.ssh/id_github
  '';

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
