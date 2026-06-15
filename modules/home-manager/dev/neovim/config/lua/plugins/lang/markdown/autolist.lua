-- 箇条書きの自動継続 + Tab/Shift-Tab で outline レベル増減
return {
  "gaoDean/autolist.nvim",
  ft = { "markdown", "text" },
  config = function()
    require("autolist").setup()
    local map = vim.keymap.set
    map("i", "<Tab>",   "<cmd>AutolistTab<cr>",      { desc = "Outline indent" })
    map("i", "<S-Tab>", "<cmd>AutolistShiftTab<cr>", { desc = "Outline dedent" })
    map("i", "<CR>",    "<CR><cmd>AutolistNewBullet<cr>")
    map("n", "o",       "o<cmd>AutolistNewBullet<cr>")
    map("n", "O",       "O<cmd>AutolistNewBulletBefore<cr>")

    -- skkeleton 有効時は <CR> が skkeleton に横取りされ、上の i-mode マップが効かない。
    -- skk-bridge が skkeleton-handled イベントで改行を検知して AutolistNewBullet を補う。
    require("plugins.lang.markdown.skk-bridge").setup()
  end,
}
