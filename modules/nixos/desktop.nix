# デスクトップ環境とキーマップ設定
{ specialArgs, pkgs, ... }: {
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # niri（GDM のセッション選択で切り替え可能）
  programs.niri.enable = true;
  # niri 上で XWayland アプリを動かすために必要
  environment.systemPackages = [ pkgs.xwayland-satellite ];

  services.xserver.xkb = {
    layout = specialArgs.settings.keymap;
    variant = "";
  };
}
