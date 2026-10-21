{ config, pkgs, lib, ... }:

let
  # kitty のフォントを _module.args で渡す。
  terminalFont = {
    package = pkgs.plemoljp-nf;
    name = "PlemolJP Console NF";
  };
in
{
  imports = [
    ./kitty.nix
    ./inkscape.nix
    ./gnome.nix
    ./ime.nix
    ./apps.nix
    ./firefox.nix
    ./teams-dispatcher.nix
  ];

  config = lib.mkMerge [
    # features.gui が false でも kitty.nix は関数の引数として受け取るため、
    # この定義だけは mkIf の外に置く。
    { _module.args.terminalFont = terminalFont; }

    (lib.mkIf config.local.profile.features.gui {
      home.packages = [ terminalFont.package ] ++ (with pkgs; [
        ipafont
        ipaexfont
        noto-fonts
        noto-fonts-cjk-sans
        noto-fonts-color-emoji
      ]);

      fonts.fontconfig = { enable = true; };

      # kitty の背景透過と nvim の背景透過 autocmd を連携させる。
      # 参照元: modules/home-manager/dev/neovim/config/
      home.sessionVariables.TERMINAL_TRANSPARENT = "1";

      programs.obs-studio = {
        enable = true;
        plugins = with pkgs.obs-studio-plugins; [
          input-overlay
        ];
      };

      programs.foliate.enable = true;
      programs.anki = {
        enable = true;
        language = "ja_JP";
      };
    })
  ];
}
