{ skk-dict, settings, config, pkgs, lib, ... }:

{
  nixpkgs.config.allowUnfree = true;

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
  ];

  systemd.user.sessionVariables = {
    EDITOR = "nvim";
    SKK_DICTIONARY_PATH = "${skk-dict}";
  };

  programs = {
    home-manager.enable = true;
    nushell = {
      enable = true;
      shellAliases = {
        ghcs = "gh copilot suggest";
        ghce = "gh copilot explain";
        cursor = "appimage-run ../../.local/bin/cursor.AppImage --enable-features=UseOzonePlatform --ozone-platform=wayland --enable-wayland-ime";
      };
    };
    starship = {
      enable = true;
      settings = {
        add_newline = false;
        command_timeout = 1300;
        scan_timeout = 50;
        format = ''
          $all$nix_shell$nodejs$lua$golang$rust$php$git_branch$git_commit$git_state$git_status
          $username$hostname$directory'';
        character = {
          success_symbol = "[](bold green) ";
          error_symbol = "[✗](bold red) ";
        };
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
