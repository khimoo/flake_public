{ inputs, config, pkgs, specialArgs, ... }: {
  imports = [ # Include the results of the hardware scan.
    ./hardware.nix
    ./data-disk.nix
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

  # ラップトップ (nixos-spin713) からリモートビルド用に SSH 接続するための鍵
  # 対応する秘密鍵はラップトップの ~/.ssh/ にある
  users.users.pomu.openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC4IfUPbwqULyrzQFLJHblRRwXaUJcdif2KERKe78HRaTAAYkWxPlPcBOJoTpvd60M1o2hpKABY4JlyPVn5AdCz/cTJ9br/mSqegQ6gOWBa/QwBy696aoT1CLDYnXGEYltP7nRBEIysI1p5BFkadsCVotfFd5BUHgIlV91hAnMrpr+RCf6JW5E+8WkibEwcBgLQ5xL4s5rh4P1orQZ/06sFLkuI7GJxmfeVDmz1ULpFNgVIw5GPx4xuSjjSbPVnF6c5K5GIrF7rG4oR6pQYzBTZC/2DfaM14CkzJRQFDrS4l0cD1pZ9AXqg8HAZjXd3lAsttEE3IS/hNsOs3bFc6irwrr5l5JTsEMUZWwAwKEUvvVJZ4/cd+Y9PoP0JLcEyZFGH/yOrhx1k0gOp3Y+va6isfvIDO0tb3YC4W+tyoufCdA6WFwUDFA8fJGjWQzV9gEU+HMiTQLMiVjRDRpR9HfmUVDbctvNDBO72ARODPfqT7yZCBPXLiYC3+WdTs8jxOoM= pomu@nixos"
  ];

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
