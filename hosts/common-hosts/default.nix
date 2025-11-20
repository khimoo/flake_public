# 共通ホスト設定
# 複数のNixOSホストで共有される設定

{ config, pkgs, specialArgs, ... }: {
  # 自動アップグレード設定
  system.autoUpgrade = {
    enable = true;
    flake = "/etc/nixos#nixos";
    flags = [ "--recreate-lock-file" "nixpkgs" ];
    dates = "Sat *-*-* 04:00:00"; # 毎週土曜4時
  };

  # ブートローダー設定
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.tmp.cleanOnBoot = true;

  # ネットワーク設定
  networking.hostName = specialArgs.settings.hostname;
  networking.networkmanager.enable = true;

  # タイムゾーン設定
  time.timeZone = specialArgs.settings.timezone;

  # 国際化設定
  i18n.defaultLocale = specialArgs.settings.locale;
  i18n.extraLocaleSettings = {
    LC_ADDRESS = specialArgs.settings.locale;
    LC_IDENTIFICATION = specialArgs.settings.locale;
    LC_MEASUREMENT = specialArgs.settings.locale;
    LC_MONETARY = specialArgs.settings.locale;
    LC_NAME = specialArgs.settings.locale;
    LC_NUMERIC = specialArgs.settings.locale;
    LC_PAPER = specialArgs.settings.locale;
    LC_TELEPHONE = specialArgs.settings.locale;
    LC_TIME = specialArgs.settings.locale;
  };

  # X11設定
  services.xserver.enable = true;
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  # キーマップ設定
  services.xserver.xkb = {
    layout = specialArgs.settings.keymap;
    variant = "";
  };

  # 印刷設定
  services.printing.enable = true;

  # 音声設定（PipeWire）
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # ユーザー設定
  users.users.${specialArgs.settings.username} = {
    isNormalUser = true;
    description = specialArgs.settings.username;
    extraGroups = [ "networkmanager" "wheel" ];
    shell = pkgs.nushell;
  };

  # Firefox設定
  programs.firefox.enable = true;

  # 非フリーパッケージの許可
  nixpkgs.config.allowUnfree = true;

  # システムパッケージ
  environment.systemPackages = with pkgs; [
    gparted
    gnomeExtensions.gsconnect
  ];

  # システム状態バージョン
  system.stateVersion = specialArgs.settings.stateVersion;

  # Nix設定
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # KDE Connect用ファイアウォール設定
  networking.firewall.allowedTCPPortRanges = [
    { from = 1714; to = 1764; }
  ];
  networking.firewall.allowedUDPPortRanges = [
    { from = 1714; to = 1764; }
  ];
}
