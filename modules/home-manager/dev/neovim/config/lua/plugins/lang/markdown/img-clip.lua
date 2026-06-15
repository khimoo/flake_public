-- クリップボード画像を貼り付けて assets/ に保存 + リンク挿入
-- 依存: wl-clipboard (Wayland) / xclip (X11) — dev/neovim/default.nix の nvimPluginDeps で導入
return {
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
}
