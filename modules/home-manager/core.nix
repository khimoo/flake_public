{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:

let
  # osConfig は NixOS か nix-darwin のモジュールとして使うときだけある。nix-darwin には nix-ld がない。
  nixLd = config.submoduleSupport.enable && (osConfig.programs.nix-ld.enable or false);
in
{
  home.packages = with pkgs; [
    curl
    fastfetch
    python3 # agents-private のスキルと scripts/check.sh が直接呼ぶ。
    gh
    ghostscript
    poppler-utils
    mpv
    fd
    ripgrep
    jq
    xh
  ];

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

    uv = {
      enable = true;
      # 既定の managed では、取得済みの Python がないと uv は PATH 上の Nix の python3 で venv を作り、
      # その venv では wheel が libstdc++ を見つけられない。uv が取得した Python は nix-ld がないと
      # 起動しないので、nix-ld のあるホストでだけ設定する（docs/architecture/wsl.md）。
      settings = lib.mkIf nixLd { python-preference = "only-managed"; };
    };
  };

}
