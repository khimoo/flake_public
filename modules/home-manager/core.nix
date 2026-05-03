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

    lazygit = {
      enable = true;
      settings = {
        # 好みに応じた設定 (デフォルトでも十分使いやすいです)
        gui = {
          showIcons = true; # Nerd Fontのアイコンを表示
          theme = {
            lightTheme = false;
            activeBorderColor = [
              "green"
              "bold"
            ];
            inactiveBorderColor = [ "white" ];
          };
        };

        git = {
          paging = {
            # 先ほど設定した delta を lazygit 内のページャーとしても使う設定
            colorArg = "always";
            pager = "delta --dark --paging=never";
          };
        };
      };
    };

    git = {
      enable = true;
      lfs.enable = true;

      userName = settings.gitUsername;
      userEmail = settings.gitUserEmail;

      extraConfig = {
        init.defaultBranch = "main";
        merge.conflictstyle = "zdiff3";
      };

      delta = {
        enable = true;
        options = {
          features = "side-by-side line-numbers decorations";
          side-by-side = true;
          line-numbers = true;
          navigate = true;
          decorations = {
            commit-decoration-style = "bold yellow box ul";
            file-style = "bold yellow ul";
            file-decoration-style = "none";
          };
        };
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

    yazi = {
      enable = true;
      enableBashIntegration = true;
      settings = {
        manager = {
          show_hidden = true;
          sort_by = "natural";
          sort_dir_first = true;
        };
      };
    };

    bottom = {
      enable = true;
    };
  };

  home.stateVersion = settings.stateVersion;
}
