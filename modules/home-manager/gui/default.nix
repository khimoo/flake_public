{ settings, pkgs, lib, ... }:

let
  # wezterm と kitty で同じフォントを使う。両モジュールへは _module.args で渡す。
  terminalFont = {
    package = pkgs.plemoljp-nf;
    name = "PlemolJP Console NF";
  };
in
{
  imports = [
    ./wezterm.nix
    ./kitty.nix
  ];

  config = lib.mkMerge [
    # features.gui が false でも wezterm.nix / kitty.nix は関数の引数として受け取るため、
    # この定義だけは mkIf の外に置く。
    { _module.args.terminalFont = terminalFont; }

    (lib.mkIf settings.features.gui {
      home.packages = [ terminalFont.package ] ++ (with pkgs; [
        ipafont
        ipaexfont
        noto-fonts
        noto-fonts-cjk-sans
        noto-fonts-color-emoji
      ]);

      fonts.fontconfig = { enable = true; };

      # 端末の背景透過と nvim の背景透過 autocmd を連携させる。wezterm も kitty も透過する
      # ので、個々の端末モジュールではなくここに置く。
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
