# デスクトップ環境（GNOME/GDM）とキーマップ設定
{ specialArgs, ... }: {
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  services.xserver.xkb = {
    layout = specialArgs.settings.keymap;
    variant = "";
  };
}
