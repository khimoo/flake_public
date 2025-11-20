{ skk-dict, settings, config, pkgs, lib, ... }:
{
  # Host-specific dconf overrides for nixos-spin713.
  dconf = {
    enable = true;
    settings = {
      "org/gnome/desktop/interface" = {
        # Only this host should have scaled text
        text-scaling-factor = 1.25;
      };
    };
  };
}
