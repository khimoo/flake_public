{ lib, settings, ... }:

lib.mkIf settings.features.gui {
  programs.firefox = {
    enable = true;
    profiles.default = {
      settings = {
        "browser.shell.checkDefaultBrowser" = false;
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
