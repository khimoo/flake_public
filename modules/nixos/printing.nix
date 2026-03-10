# 印刷・Avahi設定
{ pkgs, ... }: {
  services.printing = {
    enable = true;
    drivers = [ pkgs.gutenprint ];
  };

  # 自動でネットワークプリント設定
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };
}
