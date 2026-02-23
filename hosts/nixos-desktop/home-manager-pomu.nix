{ skk-dict, settings, config, pkgs, lib, nix-openclaw, openclawDocumentsPath, ... }:

let
  extraGnomeExtensionsList = with pkgs.gnomeExtensions; [
    display-configuration-switcher
  ];
  # OpenClaw シークレットはリポジトリ外のファイル（OPENCLAW_SECRETS_NIX）からのみ取得
  oc = settings.openclaw or { };
  gatewayToken = oc.gatewayToken or "";
  telegramAllowFrom = oc.telegramAllowFrom or [ ];
  telegramTokenFile = oc.telegramTokenFile or "${config.home.homeDirectory}/.secrets/telegram-bot-token";

in {
  imports = [
    ../../modules/home-manager/core.nix
    ../../modules/home-manager/gui.nix
    ../../modules/home-manager/dev.nix
    ../../modules/home-manager/desktop-entry.nix
    nix-openclaw.homeManagerModules.openclaw
  ];

  programs.openclaw = {
    documents = openclawDocumentsPath;

    config = {
      gateway = {
        mode = "local";
        auth = {
          # OPENCLAW_SECRETS_NIX で指定したファイルの gatewayToken。未設定時は OPENCLAW_GATEWAY_TOKEN 環境変数に依存
          token = gatewayToken;
        };
      };

      channels.telegram = {
        tokenFile = telegramTokenFile;
        # OPENCLAW_SECRETS_NIX で指定したファイルの telegramAllowFrom
        allowFrom = telegramAllowFrom;
        groups."*" = { requireMention = true; };
      };
    };

    instances.default = {
      enable = true;
      plugins = [
        # Example: { source = "github:openclaw/nix-steipete-tools?dir=tools/summarize"; }
      ];
    };
  };

  home.packages = with pkgs; [
    prismlauncher
    wine64
    steam
    blender-hip
    brave
  ] ++ extraGnomeExtensionsList;

  dconf.settings."org/gnome/shell".enabled-extensions =
    lib.mkAfter (map (ext: ext.extensionUuid) extraGnomeExtensionsList);
}
