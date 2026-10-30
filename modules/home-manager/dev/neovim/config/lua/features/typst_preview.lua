-- ブラウザで開く低遅延プレビュー。tinymist を standalone の preview モードで起動する。
-- 端末内で済ませたいときは tdf (PDF を kitty graphics protocol で描画、hot reload あり) を使う。

-- ssh で入った nvim では、接続元の PC のブラウザでプレビューを開く。接続元は
-- `ssh desktop-preview` でこのポートを転送する (hosts/nixos-spin713/default.nix と番号を揃える)。
-- ブラウザの websocket は表示中のページと同じポートへ接続するので、転送はこの 1 本で足りる。
-- 手元では既定のランダムなポートのままにして、複数のプレビューを同時に開けるようにする。
local remote = vim.env.SSH_CONNECTION ~= nil

return {
  "chomosuke/typst-preview.nvim",
  ft = "typst",
  cmd = { "TypstPreview", "TypstPreviewToggle" },
  opts = {
    -- 既定では :TypstPreviewUpdate が Nix store の外にバイナリを落とすため、
    -- nixpkgs 版を PATH 経由で指す (供給元: dev/neovim/features.nix)。
    dependencies_bin = { tinymist = "tinymist", websocat = "websocat" },
    get_main_file = require("plugins.lang.typst.main_file").resolve,
    port = remote and 23625 or 0,
    -- xdg-open は ssh 先の PC のデスクトップでブラウザを開いてしまう。
    open_cmd = remote and "true %s" or nil,
  },
}
