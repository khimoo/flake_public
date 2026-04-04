{ inputs, config, pkgs, specialArgs, ... }: {
  imports = [ # Include the results of the hardware scan.
    ./hardware.nix
    ../../modules/nixos/common.nix
  ];
  boot.kernelParams = [ "btusb.enable_autosuspend=n" ];

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
