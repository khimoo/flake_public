{
  skk-dict,
  settings,
  config,
  pkgs,
  lib,
  ...
}:

{

  home.packages = with pkgs; [
    curl
    tig
    gcc
    neofetch
    python3
    gh
    uv
    direnv
    ghostscript
    mpv
  ];

  home.sessionVariables = {
    EDITOR = "nvim";
    SKK_DICTIONARY_PATH = "${skk-dict}";
  };

  programs = {
    home-manager.enable = true;
    bash = {
      enable = true;
      shellAliases = {
        ghcs = "gh copilot suggest";
        ghce = "gh copilot explain";
        cursor = "appimage-run ../../.local/bin/cursor.AppImage --enable-features=UseOzonePlatform --ozone-platform=wayland --enable-wayland-ime";
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
      };
    };
    git = {
      lfs.enable = true;
      enable = true;
      settings = {
        user.name = settings.gitUsername;
        user.email = settings.gitUserEmail;
        init.defaultBranch = "main";
      };
    };
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
  };

  home.stateVersion = settings.stateVersion;
}
