{ inputs, config, pkgs, specialArgs, ... }: {
  imports = [ # Include the results of the hardware scan.
    ./hardware.nix
    ../../modules/nixos/common.nix
  ];
  boot.kernelParams = [ "btusb.enable_autosuspend=n" ];

  virtualisation.libvirtd = {
    enable = true;
    # UEFI対応などのためのQEMU設定
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      swtpm.enable = true;
    };
  };

  # virt-manager (GUIでのVM管理用)
  programs.virt-manager.enable = true;

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

  # Home Manager管理下の全ユーザーでUnfree(非自由)パッケージを許可
  home-manager.sharedModules = [
    { nixpkgs.config.allowUnfree = true; }
  ];
}
