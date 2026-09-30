{ config, lib, ... }:

lib.mkIf config.local.profile.features.gui {
  programs.firefox = {
    enable = true;
    # Home Manager 26.05 の既定は XDG の ~/.config/mozilla/firefox だが、移るには各マシンで
    # ~/.mozilla/firefox を手で移す必要がある。設定を宣言的管理に移してから移行するので、それまでは従来の場所に置く。
    configPath = ".mozilla/firefox";
    profiles.default = {
      isDefault = true;
      settings = {
        "browser.shell.checkDefaultBrowser" = false;
        # HTTP/HTTPS は Firefox 自身で処理する。
        # x-scheme-handler/https がディスパッチャを指しているため、
        # この設定がないと Firefox → ディスパッチャ → Firefox の無限ループになる。
        "network.protocol-handler.expose.http" = true;
        "network.protocol-handler.expose.https" = true;
      };
    };
  };

  xdg.mimeApps.defaultApplications = {
    "text/html" = "firefox.desktop";
    "text/xml" = "firefox.desktop";
    "application/xhtml+xml" = "firefox.desktop";
    "x-scheme-handler/about" = "firefox.desktop";
  };
}
