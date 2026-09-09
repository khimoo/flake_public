# Evaluation fixture for the README's mkSystem example.
# On real hardware replace this module with hosts/<hostname>/default.nix
# importing that machine's generated hardware.nix and modules/nixos/common.nix.
{ ... }:
{
  imports = [ ../modules/nixos/users.nix ];
  nixpkgs.config.allowUnfree = true;
  system.stateVersion = "25.11";
  boot.loader.grub.enable = false;
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
}
