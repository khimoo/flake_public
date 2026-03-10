# ネットワーク・ファイアウォール設定
{ specialArgs, ... }: {
  networking.hostName = specialArgs.settings.hostname;
  networking.networkmanager.enable = true;

  # KDE Connect / GSConnect 用ファイアウォール設定
  networking.firewall.allowedTCPPortRanges = [
    { from = 1714; to = 1764; }
  ];
  networking.firewall.allowedUDPPortRanges = [
    { from = 1714; to = 1764; }
  ];
}
