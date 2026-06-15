-- Markdown 関連の集約モジュール。
-- ・ftplugin (filetype オプション) は require 時に副作用として登録される
-- ・各サブモジュールは lazy.nvim の spec 1 個を返す。同じプラグイン名で複数 spec が
--   あると lazy.nvim が自動で deep-merge するため、treesitter や lspconfig のような
--   「共通プラグインに markdown 固有の設定を追加」する形を取れる
require("plugins.lang.markdown.filetype")

return {
  require("plugins.lang.markdown.render"),
  require("plugins.lang.markdown.autolist"),
  require("plugins.lang.markdown.img-clip"),
  require("plugins.lang.markdown.treesitter"),
}
