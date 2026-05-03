{
  skk-dict,
  settings,
  pkgs,
  ...
}:

{
  home.packages = with pkgs; [
    curl
    gcc
    fastfetch
    python3
    gh
    uv
    ghostscript
    mpv
    fd
    ripgrep
    jq
    xh
  ];

  home.sessionVariables = {
    EDITOR = "nvim";
    SKK_DICTIONARY_PATH = "${skk-dict}";
  };

  programs = {
    home-manager.enable = true;

    bash = {
      enable = true;

      enableCompletion = true;
      historyControl = [
        "ignoredups"
        "ignorespace"
      ];

      shellAliases = {
        ls = "eza --icons --git";
        ll = "eza -l --icons --git";
        la = "eza -la --icons --git";
        cat = "bat";
        grep = "rg";
        top = "btm";
        cd = "z";
        # yazi は enableBashIntegration により yy 関数が定義済み
        # yazi=yy のエイリアスは yy 内部の yazi 呼び出しと無限再帰するため使わない
      };

      initExtra = ''
        noise() {
          local dir="''${1:-$HOME/音楽/noise}"
          local volume="''${2:-50}"
          mpv --shuffle --loop-playlist --no-video --really-quiet "--volume=$volume" "$dir"
        }
      '';
    };

    starship = {
      enable = true;
      settings = {
        add_newline = true;
        character = {
          success_symbol = "[❯](bold green)";
          error_symbol = "[✗](bold red)";
        };
        package.disabled = true;
        aws.disabled = true;
        gcloud.disabled = true;
      };
    };

    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    fzf = {
      enable = true;
      enableBashIntegration = true;
    };

    zoxide = {
      enable = true;
      enableBashIntegration = true;
    };

    eza = {
      enable = true;
    };

    bat = {
      enable = true;
    };

    bottom = {
      enable = true;
    };
  };

  home.stateVersion = settings.stateVersion;
}
