{ lib, settings, ... }:

lib.mkIf settings.features.gui {
  programs.firefox = {
    enable = true;
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
