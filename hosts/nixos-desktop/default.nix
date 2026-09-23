{ inputs, config, pkgs, specialArgs, ... }: {
  imports = [ # Include the results of the hardware scan.
    ./hardware.nix
    ./data-disk.nix
    ./keyd-turbo.nix
    ../../modules/nixos/common.nix
  ];
  boot.kernelParams = [ "btusb.enable_autosuspend=n" ];

  # 外出先から tailnet 経由で SSH とリモートビルドに使うので、無操作でサスペンドさせない。
  # サスペンドすると外から起こす手段がない（docs/architecture/tailscale.md）。
  # autoSuspend はログイン画面だけに適用される。再起動後にログイン画面のまま放置されても、これで起きたままになる。
  # ログイン中のセッションは gsettings の既定値で止める。ユーザーが GNOME の設定で変えた値はこれより優先される。
  services.displayManager.gdm.autoSuspend = false;
  services.desktopManager.gnome.extraGSettingsOverrides = ''
    [org.gnome.settings-daemon.plugins.power]
    sleep-inactive-ac-type='nothing'
  '';

  # GNOME のリモートデスクトップ（RDP）を tailnet からだけ受ける。LAN とインターネットには開けない。
  # 有効化とパスワードは GNOME の設定で行い、repo には置かない（docs/howtouse/tailscale.md）。
  # 既定のポートは 3389 で、使用中なら negotiate-port により後続の 10 ポートから空きを探す。
  # Remote Login と Desktop Sharing を両方有効にすると後から起動した側が 3390 以降にずれるので、その範囲まで開ける。
  networking.firewall.interfaces.${config.services.tailscale.interfaceName}.allowedTCPPortRanges = [
    { from = 3389; to = 3399; }
  ];

  virtualisation.spiceUSBRedirection.enable = true;
  virtualisation.libvirtd = {
    enable = true;
    # UEFI対応などのためのQEMU設定
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      swtpm.enable = true;
      vhostUserPackages = [ pkgs.virtiofsd ];
    };
  };
  environment.etc = {
    "ovmf/edk2-x86_64-secure-code.fd" = {
      source = "${pkgs.qemu_kvm}/share/qemu/edk2-x86_64-secure-code.fd";
    };
    "ovmf/edk2-i386-vars.fd" = {
      source = "${pkgs.qemu_kvm}/share/qemu/edk2-i386-vars.fd";
    };
  };

  # virt-manager (GUIでのVM管理用)
  programs.virt-manager.enable = true;

  # steam パッケージ単体でも FHS ラッパなので起動はするが、コントローラ/VR の udev ルール
  # (hardware.steam-hardware) と 32bit ドライバはこのモジュールが設定する。
  # ゲームの置き場は data-disk.nix の @games (~/Games) を Steam 側でライブラリに追加する。
  programs.steam.enable = true;

  # 音声設定（PipeWire）
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };
}
