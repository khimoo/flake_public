-- filetype オプション (ftplugin/markdown.lua 相当)
-- ・wrap + linebreak + breakindent: 長い段落の表示折り返し
-- ・spell + spelllang(en,cjk): typo 検出、日本語は誤検知させない
-- ・conceallevel=2: render-markdown.nvim の装飾を効かせる際のフォールバック値
--   (render-markdown 描画中は内部で 3 に上書きされる)
vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function()
    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true
    vim.opt_local.breakindent = true
    vim.opt_local.spell = true
    vim.opt_local.spelllang = { "en", "cjk" }
    vim.opt_local.conceallevel = 2
    vim.opt_local.concealcursor = ""
  end,
})
