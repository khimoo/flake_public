{ ... }:
{
  nixpkgs.config.allowUnfree = true;
  system.stateVersion = "25.11";
  boot.loader.grub.enable = false;
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
}
