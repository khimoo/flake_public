# Neovim の機能ごとの依存。各機能は lua/features/<名前>.lua の spec と組になる（default.nix）。
# 外部コマンドや Nix の生成物を使わないプラグインは lua/plugins/ に置き、ここには書かない。
# lua/plugins/ から機能のプラグインへ設定を足す spec は optional = true にし、機能と一緒に外れるようにする。
# neotest と render_markdown、diagram は nvim-treesitter を依存に持つので、treesitter を外しても nvim-treesitter は入る。
{ inputs, config, pkgs, lib, ... }:

let
  inherit (pkgs.stdenv) isLinux;

  # 識別子は lua/features/lsp.lua が vim.lsp.enable に渡す。
  lspServers = [
    { pkg = pkgs.pyright; lsp = "pyright"; }
    { pkg = pkgs.lua-language-server; lsp = "lua_ls"; }
    { pkg = pkgs.nil; lsp = "nil_ls"; }
    { pkg = pkgs.tinymist; lsp = "tinymist"; }
    { pkg = pkgs.marksman; lsp = "marksman"; }
  ];

  # skkeleton の辞書は overlay を通さない nixpkgs で展開する。
  dictionaryPkgs = inputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  skkDictionary = dictionaryPkgs.stdenv.mkDerivation {
    name = "skk-jisyo-dict";
    src = inputs.skk-jisyo;
    nativeBuildInputs = [ dictionaryPkgs.gzip ];
    unpackPhase = "gzip -d < $src > $out";
    dontInstall = true;
  };

  vault = config.local.profile.zettelkastenRoot;
in
{
  local.neovim.features = {
    clipboard.packages = lib.optionals isLinux [
      pkgs.xclip
      pkgs.wl-clipboard
    ];

    telescope.packages = [ pkgs.ripgrep ];

    # main ブランチは全パーサを `tree-sitter build`（0.26.1 以上）で手元でコンパイルする。
    treesitter.packages = [
      pkgs.tree-sitter
      pkgs.stdenv.cc
    ];

    lsp = {
      packages = map (s: s.pkg) lspServers ++ [ pkgs.nixfmt ];
      data.servers = map (s: s.lsp) lspServers;
    };

    # denops が deno で動く。
    skkeleton = {
      packages = [ pkgs.deno ];
      data.dictionary = "${skkDictionary}";
    };

    rust.data.codelldb = "${pkgs.vscode-extensions.vadimcn.vscode-lldb}/share/vscode/extensions/vadimcn.vscode-lldb/adapter/codelldb";

    dap.data.python = "${pkgs.python3.withPackages (ps: [ ps.debugpy ])}/bin/python";

    # mermaid を mmdc で PNG にし、image.nvim が ImageMagick で縮小して表示する。
    diagram = {
      packages = [
        pkgs.mermaid-cli
        pkgs.imagemagick
      ];
      luaPackages = ps: [ ps.magick ];
    };

    # 数式を latex2text で Unicode に近似する。
    render_markdown.packages = [ pkgs.python3Packages.pylatexenc ];

    # 貼り付けた画像は vault の attachments/ に置く。vault のないユーザーでは読み込まない。
    img_clip = {
      enable = vault != null;
      packages = lib.optionals isLinux [ pkgs.wl-clipboard ];
      data.dir = "${toString vault}/attachments";
    };

    typst_preview.packages = [
      pkgs.tinymist
      pkgs.websocat
    ];

    # kitty 側の kitten も同じパッケージから置く（gui/kitty.nix）。
    smart_splits.data.plugin = "${pkgs.vimPlugins.smart-splits-nvim}";
  };
}
