# 共通ホスト設定
# 複数のNixOSホストで共有される設定

{ config, pkgs, specialArgs, lib, ... }:

let
  users = specialArgs.settings.users or [];
  usersByName = builtins.listToAttrs (map (user: {
    name = user.username;
    value = user;
  }) users);
in {
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
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # キーマップ設定
  services.xserver.xkb = {
    layout = specialArgs.settings.keymap;
    variant = "";
  };

  # 印刷設定
  services.printing = {
    enable = true;
    drivers = [ pkgs.gutenprint ];
  };
  services.avahi = { # 自動でネットワークプリント設定
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  # ユーザー設定
  users.users = lib.genAttrs (builtins.attrNames usersByName) (username:
    let
      user = usersByName.${username};
    in {
      isNormalUser = true;
      description = user.description or username;
      extraGroups = (user.extraGroups or [])
        ++ [ "networkmanager" ]
        ++ lib.optionals (user.isAdmin or false) [ "wheel" ];
      shell = user.shell or pkgs.nushell;
    }
  );

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
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        # オーディオ関連のプロファイルを明示的に有効化
        Enable = "Source,Sink,Media,Socket";
        # 一部のイヤホンで接続を安定させる設定
        ControllerMode = "dual";
        FastConnectable = "true";
        Experimental = "true";
      };
      Policy = { AutoEnable = "true"; };
    };
  };

  # qemu/kvmなどで使う"default"というNICを自動で起動させる
  systemd.services.libvirt-network-autostart = {
    description = "Enable autostart for libvirt default network";
    after = [ "libvirtd.service" ];
    requires = [ "libvirtd.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.libvirt}/bin/virsh net-autostart default";
      RemainAfterExit = "yes";
    };
  };

  # sudo nixos-rebuild switchでsshキーを引き継ぐ
  security.sudo.extraConfig = ''
    Defaults env_keep += "SSH_AUTH_SOCK"
  '';
}
