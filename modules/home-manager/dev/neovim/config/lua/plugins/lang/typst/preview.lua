-- ブラウザで開く低遅延プレビュー。tinymist を standalone の preview モードで起動する。
-- 端末内で済ませたいときは tdf (PDF を kitty graphics protocol で描画、hot reload あり) を使う。
return {
  "chomosuke/typst-preview.nvim",
  ft = "typst",
  cmd = { "TypstPreview", "TypstPreviewToggle" },
  opts = {
    -- 既定では :TypstPreviewUpdate が Nix store の外にバイナリを落とすため、
    -- nixpkgs 版を PATH 経由で指す (供給元: dev/lsp.nix と dev/neovim/default.nix)。
    dependencies_bin = { tinymist = "tinymist", websocat = "websocat" },
    get_main_file = require("plugins.lang.typst.main_file").resolve,
  },
}
