# SSH サーバ + mDNS 公開 + マシン間 SSH の配線
# 用途: 他ホストからの SSH ログイン受け入れ、`<hostname>.local` での名前解決、
#       および flake 内の全マシンへ短縮名で SSH できるクライアント設定の生成。
# 例: どのホストからでも `ssh desktop` / `ssh spin713` で接続でき、ラップトップからの
#     `nixos-rebuild --build-host pomu@nixos-desktop.local` の known_hosts 追加も兼ねる。
#     LAN の外からは tailnet 経由の `ssh desktop-ts` を使う（tailscale.nix）。
#     remote-builders.nix の nix-daemon も `desktop-ts` の設定で接続する。
#
# マシンの追加/廃棄は hosts/machines.nix の 1 エントリ増減だけで完結する。
{ config, lib, settings, ... }:
let
  # LAN 共通鍵の公開鍵とホスト一覧（単一の情報源）
  machines = import ../../hosts/machines.nix;
  # `nixos-` プレフィックスを剥がした短縮エイリアス（nixos-desktop → desktop）
  shortName = host: lib.removePrefix "nixos-" host;

  # ConnectTimeout が無いと、応答しないホストへの接続は TCP の既定のタイムアウトまで待つ。
  # nix-daemon は ssh にタイムアウトを渡さないので、落ちたビルダーの待ちはこの値で決まる
  # （docs/architecture/remote-build.md）。
  hostBlock = patterns: hostName: ''
    Host ${patterns}
      HostName ${hostName}
      User ${settings.primaryUser}
      IdentityFile ~/.ssh/id_lan
      StrictHostKeyChecking accept-new
      ConnectTimeout 10
  '';

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
  #
  # ~/.ssh/id_lan は ssh を実行したユーザーの home で解決される。root はこの鍵を持たないので、
  # `sudo nixos-rebuild --build-host` は認証に失敗する。`sudo` を付けずに `--sudo` で実行する
  # （docs/architecture/remote-build.md）。
  #
  # `-ts` の接続名は MagicDNS の短縮名で引く。`.local` の接続名は mDNS だけに依存させ、
  # tailnet に入っていないときも LAN 内で繋がるように残す。
  programs.ssh.extraConfig = lib.concatStrings (map (host:
    hostBlock "${shortName host} ${host} ${host}.local" "${host}.local"
    + lib.optionalString config.services.tailscale.enable
      (hostBlock "${shortName host}-ts" host)
  ) machines.hosts) + ''
    Host github.com
      User git
      IdentityFile ~/.ssh/id_github
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
