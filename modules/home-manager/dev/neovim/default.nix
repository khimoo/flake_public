{ settings, lspServers, config, pkgs, lib, ... }:

let
  # Neovim プラグインが必要とする外部ツール (Neovim 実行時の PATH のみに注入)
  # for: 依存元プラグイン/機能を明記。プラグイン削除時はここも消すこと。
  nvimPluginDeps = [
    { pkg = pkgs.deno;             for = "denols / 各種 deno ベースのプラグイン"; }
    { pkg = pkgs.ripgrep;          for = "telescope (live_grep)"; }
    { pkg = pkgs.nil;              for = "nil_ls (LSP 本体)"; }
    { pkg = pkgs.nixfmt-rfc-style; for = "nil_ls の formatter"; }
    { pkg = pkgs.vscode-extensions.vadimcn.vscode-lldb;
                                   for = "rustaceanvim DAP (codelldb)"; }
    { pkg = pkgs.mermaid-cli;      for = "diagram.nvim (mermaid → PNG レンダリング, mmdc)"; }
    { pkg = pkgs.imagemagick;      for = "image.nvim (画像リサイズ/変換, magick CLI backend)"; }
  ] ++ lib.optionals pkgs.stdenv.isLinux [
    { pkg = pkgs.xclip;        for = "system clipboard 連携 (X11)"; }
    { pkg = pkgs.wl-clipboard; for = "img-clip.nvim (Wayland 画像貼付)"; }
  ];

  # nvim 実行ファイルのフルパス。home.shellAliases から参照することで
  # 「programs.neovim が有効でないと eval エラー」という形で依存を強制する。
  nvimExe = lib.getExe config.programs.neovim.finalPackage;
in
{
  programs.neovim = {
    enable = true;
    vimAlias = true;
    defaultEditor = true;
    withNodeJs = true;
    extraPackages = map (d: d.pkg) nvimPluginDeps;
    # image.nvim が必要とする ImageMagick の Lua バインディング (magick luarock)。
    # nixpkgs 経由で注入することで luarocks をユーザ環境に出さずに済む。
    extraLuaPackages = ps: [ ps.magick ];
    plugins = with pkgs.vimPlugins; [
      lazy-nvim
    ];
  };

  # Neovim の設定ディレクトリを out-of-store symlink で配置する。
  # ~/.config/nvim → ${flakeRoot}/modules/home-manager/dev/neovim/config への symlink。
  # これにより lua の編集が rebuild なしで反映され、lazy-lock.json もリポジトリ内に
  # 書き戻されるため git で追跡できる。
  xdg.configFile."nvim".source =
    config.lib.file.mkOutOfStoreSymlink
      "${settings.flakeRoot}/modules/home-manager/dev/neovim/config";

  # Neovim が dofile で読む Nix 生成ファイル (環境変数と違い rebuild 即反映)。
  # ~/.config/nvim 全体が mkOutOfStoreSymlink でリポジトリへの symlink になっているため、
  # 配下に追加ファイルを置けない。代わりに ~/.local/share/nvim/nix/ (stdpath("data")) に配置する。
  # 参照元: modules/home-manager/dev/neovim/config/lua/plugins/lsp/init.lua
  xdg.dataFile."nvim/nix/lsp-servers.lua".text =
    "return {${builtins.concatStringsSep ", " (map (s: ''"${s.lsp}"'') lspServers)}}";
  # 参照元: modules/home-manager/dev/neovim/config/lua/plugins/lang/rust.lua
  xdg.dataFile."nvim/nix/codelldb-path.lua".text =
    ''return "${pkgs.vscode-extensions.vadimcn.vscode-lldb}/share/vscode/extensions/vadimcn.vscode-lldb/adapter/codelldb"'';

  # 一時 markdown draft を nvim で開く。Claude への返信下書きなどに使う。
  # /tmp は systemd-tmpfiles が 10 日経過で自動削除するためメンテ不要。
  # nvim 本体への依存は let の nvimExe で構造的に表現済み。
  home.shellAliases.draft = ''${nvimExe} "$(mktemp --suffix=.md)"'';
}
