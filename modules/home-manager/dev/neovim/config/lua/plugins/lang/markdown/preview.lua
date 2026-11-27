-- ブラウザの枠なしウィンドウ（--app）で Markdown をライブプレビューする。
-- 固定ポート 8421 の takeover モードで 1 窓を使い回し、画像・Mermaid・数式を表示する。
local preview_browser = require("config.preview_browser")

local PREVIEW_PORT = 8421
local PREVIEW_URL = "http://127.0.0.1:" .. PREVIEW_PORT

return {
  "selimacerbas/mdkite.nvim",
  dependencies = { "selimacerbas/kitehost.nvim" },
  ft = { "markdown" },
  cmd = { "MdKite", "MarkdownPreview" },
  config = function()
    require("mdkite").setup({
      instance_mode = "takeover",
      port = PREVIEW_PORT,
      host = "127.0.0.1",
      -- --app=<URL> で枠なし窓を開くため自動起動は切り、:MarkdownPreview から開く。
      open_browser = false,
    })

    vim.api.nvim_create_user_command("MarkdownPreview", function()
      vim.cmd("MdKite start")
      preview_browser.open(PREVIEW_URL)
    end, { desc = "Start Markdown preview and open app window" })
  end,
}
