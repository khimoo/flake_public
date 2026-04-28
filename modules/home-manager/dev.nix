{ kiro, settings, config, pkgs, lib, ... }:

let
  lspServers = [
    { pkg = pkgs.pyright; lsp = "pyright"; }
    { pkg = pkgs.lua-language-server; lsp = "lua_ls"; }
    { pkg = pkgs.nil; lsp = "nil_ls"; }
    { pkg = pkgs.tinymist; lsp = "tinymist"; }
  ];

in {
  home.packages = with pkgs; [
    kiro.packages.${pkgs.system}.default
    vscode
    jetbrains.idea
    tree
    antigravity-fhs
    claude-code
  ] ++ map (s: s.pkg) lspServers;

  systemd.user.sessionVariables = {
    NEOVIM_LSP_SERVERS = builtins.concatStringsSep "," (map (s: s.lsp) lspServers);
    CODELLDB_PATH = "${pkgs.vscode-extensions.vadimcn.vscode-lldb}/share/vscode/extensions/vadimcn.vscode-lldb/adapter/codelldb";
  };

  programs.neovim = {
    enable = true;
    vimAlias = true;
    defaultEditor = true;
    withNodeJs = true;
    extraPackages = with pkgs; [
      deno
      ripgrep
      xclip
      nil
      nixfmt-rfc-style
      vscode-extensions.vadimcn.vscode-lldb
    ];
    plugins = with pkgs.vimPlugins; [
      lazy-nvim
    ];
  };

  # mkOutOfStoreSymlinkを使えばrebuild不要で即反映できるが、絶対パスのハードコードが必要になるため使用しない
  xdg.configFile."nvim" = {
    source = ../../dotfiles/nvim;
    recursive = true;
  };
}
