# SSH サーバ + mDNS 公開
# 用途: 他ホストからの SSH ログイン受け入れ、および `<hostname>.local` での名前解決
# 例: ラップトップから `nixos-rebuild --build-host pomu@nixos-desktop.local` で
#     デスクトップのリソースを使ってビルドする
{ ... }: {
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

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
