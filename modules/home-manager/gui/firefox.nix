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
        # false にすると、expose.* で true にしたスキーム以外（blob: のダウンロードなど）も
        # すべて外部プログラムへ回され、どのサイトでもダウンロードできなくなる。
        "network.protocol-handler.expose-all" = true;
      };
    };
    # 拡張機能の導入だけを宣言する。拡張機能の中の設定は各マシンの Firefox が持つ。
    policies.ExtensionSettings =
      let
        amo = slug: {
          installation_mode = "normal_installed";
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/${slug}/latest.xpi";
        };
      in
      {
        "{77fcd6fa-22a1-498c-88a5-cee7bf16b989}" = amo "manaba-plus";
        "jid1-YcMV6ngYmQRA2w@jetpack" = amo "pinterest";
        "@firefoxinvertcolors" = amo "invert-colors";
        "side-view@mozilla.org" = amo "side-view";
        "{d7742d87-e61d-4b78-b8a1-b469842139fa}" = amo "vimium-ff";
        "clipper@obsidian.md" = amo "web-clipper-obsidian";
        "enhancerforyoutube@maximerf.addons.mozilla.org" = amo "enhancer-for-youtube";
        "{7058a75b-0f6c-4f10-a54d-bf427dc62b63}" = amo "notebooklmwebimporter";
        "newtaboverride@agenedia.com" = amo "new-tab-override";
        "{54e2eb33-18eb-46ad-a4e4-1329c29f6e17}" = amo "block-website";
        "uBlock0@raymondhill.net" = amo "ublock-origin";
        "treestyletab@piro.sakura.ne.jp" = amo "tree-style-tab";
        "soundlift@yourdomain.com" = amo "soundlift-volume-booster";
        "extension@one-tab.com" = amo "onetab";
        "floccus@handmadeideas.org" = amo "floccus";
        "{da1a7868-5062-4eb9-a787-6d9210703929}" = amo "plamo-translate";
        "langpack-ja@firefox.mozilla.org" = amo "japanese-language-pack-1";
        "{446900e4-71c2-419f-a6a7-df9c091e268b}" = amo "bitwarden-password-manager";
      };
  };

  xdg.mimeApps.defaultApplications = {
    "text/html" = "firefox.desktop";
    "text/xml" = "firefox.desktop";
    "application/xhtml+xml" = "firefox.desktop";
    "x-scheme-handler/about" = "firefox.desktop";
  };
}
