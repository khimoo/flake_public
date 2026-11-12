{
  lib,
  pkgs,
  system,
  helpers,
  ...
}:
let
  inherit (helpers) purposeHome allAssertions;
  browsing = purposeHome system "test-web-browsing";
  dispatcher = purposeHome system "test-web-dispatcher";
  defaults = browsing.config.xdg.mimeApps.defaultApplications;
  dispatchedDefaults = dispatcher.config.xdg.mimeApps.defaultApplications;
in
{
  web-browsing-contracts =
    (lib.lazyDerivation {
      derivation = (
        assert allAssertions browsing;
        assert allAssertions dispatcher;
        assert browsing.config.programs.firefox.enable;
        assert browsing.config.programs.zen-browser.enable;
        assert browsing.config.programs.firefox.policies.ExtensionSettings ? "uBlock0@raymondhill.net";
        assert browsing.config.programs.zen-browser.policies.ExtensionSettings ? "uBlock0@raymondhill.net";
        assert browsing.config.programs.firefox.policies.ExtensionSettings ? "treestyletab@piro.sakura.ne.jp";
        assert !(browsing.config.programs.zen-browser.policies.ExtensionSettings ? "treestyletab@piro.sakura.ne.jp");
        assert browsing.config.programs.firefox.profiles.default.settings."services.sync.engine.extension-storage.force";
        assert browsing.config.programs.zen-browser.profiles.default.settings."services.sync.engine.extension-storage.force";
        assert browsing.config.programs.zen-browser.profiles.default.settings."services.sync.engine.spaces";
        assert !browsing.config.programs.anki.enable;
        assert !builtins.any (p: (p.pname or "") == "inkscape") browsing.config.home.packages;
        assert builtins.all (mime: defaults.${mime} == [ "zen-beta.desktop" ]) [
          "text/html"
          "text/xml"
          "application/xhtml+xml"
          "x-scheme-handler/about"
          "x-scheme-handler/http"
          "x-scheme-handler/https"
        ];
        assert dispatchedDefaults."text/html" == [ "zen-beta.desktop" ];
        assert builtins.all
          (scheme: dispatchedDefaults.${"x-scheme-handler/" + scheme} == [ "teams-url-dispatcher.desktop" ])
          [
            "http"
            "https"
          ];
        assert dispatcher.config.home.file ? ".local/share/applications/teams-url-dispatcher.desktop";
        pkgs.runCommand "web-browsing-contracts" { } ''touch "$out"''
      );
    })
    // {
      elements = [
        "browser_common"
        "web_browsing"
        "zen_browser"
        "firefox"
        "teams_dispatcher"
        "gui"
        "kitty"
      ];
    };
}
