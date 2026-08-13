{ inputs, config, pkgs, specialArgs, ... }: {
  imports = [ # Include the results of the hardware scan.
    ./hardware.nix
    ./data-disk.nix
    ./keyd-turbo.nix
    ../../modules/nixos/common.nix
  ];
  boot.kernelParams = [ "btusb.enable_autosuspend=n" ];

  # 起動時の OS 選択画面（実体は systemd-boot の世代メニュー。Windows エントリは無い）を
  # 出さず既定世代を即起動する。共有 boot.nix に置くと laptop(spin713) のメニューも
  # 消えてしまうため、desktop 限定でここに置く。メニューはキー長押しで復帰可能。
  boot.loader.timeout = 0;

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
