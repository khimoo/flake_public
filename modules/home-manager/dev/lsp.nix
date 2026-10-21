{ pkgs, ... }:

let
  # LSP サーバーの一覧。
  # lsp フィールドは neovim/config 側で「有効化する LSP の識別子」として使われる。
  # 導入パッケージと Neovim が読む識別子を、同じ一覧からここで生成する。
  lspServers = [
    { pkg = pkgs.pyright; lsp = "pyright"; }
    { pkg = pkgs.lua-language-server; lsp = "lua_ls"; }
    { pkg = pkgs.nil; lsp = "nil_ls"; }
    { pkg = pkgs.tinymist; lsp = "tinymist"; }
    { pkg = pkgs.marksman; lsp = "marksman"; }
  ];
in
{
  home.packages = map (s: s.pkg) lspServers;

  # ~/.config/nvim は live checkout へのリンクなので、生成ファイルは stdpath("data") に置く。
  # 参照元: neovim/config/lua/plugins/lsp/init.lua
  xdg.dataFile."nvim/nix/lsp-servers.lua".text =
    "return {${builtins.concatStringsSep ", " (map (s: ''"${s.lsp}"'') lspServers)}}";
}
