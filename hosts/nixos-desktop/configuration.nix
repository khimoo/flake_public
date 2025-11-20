{ config, pkgs, specialArgs, ... }: {
  imports = [ # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ../common-hosts/default.nix
  ];
}
