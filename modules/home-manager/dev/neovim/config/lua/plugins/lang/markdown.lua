-- Markdown 関連の設定を集約。
-- LSP (marksman) 本体は modules/home-manager/dev/{lsp,neovim/default}.nix の lspServers で導入され、
-- plugins/lsp/init.lua が動的に有効化する (このファイルでは触れない)。
-- 外部ツール依存 (wl-clipboard 等) は modules/home-manager/dev/{lsp,neovim/default}.nix の nvimPluginDeps を参照。

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

return {
  -- バッファ内装飾レンダリング (見出し背景色、テーブル罫線、チェックボックス等)
  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown" },
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "nvim-tree/nvim-web-devicons",
    },
    opts = {},
  },

  -- 箇条書きの自動継続 + Tab/Shift-Tab で outline レベル増減
  {
    "gaoDean/autolist.nvim",
    ft = { "markdown", "text" },
    config = function()
      require("autolist").setup()
      local map = vim.keymap.set
      map("i", "<Tab>",   "<cmd>AutolistTab<cr>",         { desc = "Outline indent" })
      map("i", "<S-Tab>", "<cmd>AutolistShiftTab<cr>",    { desc = "Outline dedent" })
      map("i", "<CR>",    "<CR><cmd>AutolistNewBullet<cr>")
      map("n", "o",       "o<cmd>AutolistNewBullet<cr>")
      map("n", "O",       "O<cmd>AutolistNewBulletBefore<cr>")
    end,
  },

  -- クリップボード画像を貼り付けて assets/ に保存 + リンク挿入
  -- 依存: wl-clipboard (Wayland) / xclip (X11) — dev/neovim/default.nix の nvimPluginDeps で導入
  {
    "HakonHarnes/img-clip.nvim",
    ft = { "markdown" },
    init = function()
      if vim.fn.has("linux") == 1 then
        local has_clipboard_tool = vim.fn.executable("wl-paste") == 1
          or vim.fn.executable("xclip") == 1
        if not has_clipboard_tool then
          vim.notify(
            "img-clip.nvim: wl-clipboard または xclip が必要です " ..
            "(modules/home-manager/dev/{lsp,neovim/default}.nix の nvimPluginDeps を確認)",
            vim.log.levels.WARN
          )
        end
      end
    end,
    opts = {
      default = {
        dir_path = "assets",
        relative_to_current_file = true,
        file_name = "%Y-%m-%d-%H-%M-%S",
      },
    },
    keys = {
      { "<leader>p", "<cmd>PasteImage<cr>", desc = "Paste image from clipboard" },
    },
  },
}
