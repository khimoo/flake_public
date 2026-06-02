{ pkgs, ... }:

let
  # LSP サーバーの一覧。
  # lsp フィールドは neovim/config 側で「有効化する LSP の識別子」として使われる。
  # _module.args 経由で neovim.nix がこの値を読み、bridge file (nvim/nix/lsp-servers.lua) に書き出す。
  lspServers = [
    { pkg = pkgs.pyright; lsp = "pyright"; }
    { pkg = pkgs.lua-language-server; lsp = "lua_ls"; }
    { pkg = pkgs.nil; lsp = "nil_ls"; }
    { pkg = pkgs.tinymist; lsp = "tinymist"; }
    { pkg = pkgs.marksman; lsp = "marksman"; }
  ];
in
{
  _module.args.lspServers = lspServers;

  home.packages = map (s: s.pkg) lspServers;
}
