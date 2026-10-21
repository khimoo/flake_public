{
  inputs,
  lib,
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
    poppler-utils
    mpv
    fd
    ripgrep
    jq
    xh
    nodejs_22
  ]
  # buildFHSEnv は Linux でしか作れない（docs/architecture/uv-mode.md）。
  ++ lib.optionals pkgs.stdenv.isLinux [
    inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.uv-mode
  ];

  home.sessionVariables = {
    EDITOR = "nvim";
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
        # yazi は enableBashIntegration により y 関数が定義済み
        # yazi=y のエイリアスは y 内部の yazi 呼び出しと無限再帰するため使わない
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
        # packages/uv-mode が設定する目印。モードの外では uv が取得した Python を起動できないので、
        # 中にいるかをプロンプトで見分けられるようにする。
        env_var.IN_UV_MODE = {
          format = "[uv-mode]($style) ";
          style = "bold yellow";
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

    bottom = {
      enable = true;
    };
  };

}
