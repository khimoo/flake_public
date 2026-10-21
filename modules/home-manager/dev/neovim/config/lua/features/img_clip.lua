-- クリップボード画像を貼り付けて Obsidian vault ルートの attachments/ に保存 + リンク挿入
-- 依存: wl-clipboard (Wayland) / xclip (X11) — dev/neovim/features.nix で導入
--
-- 保存先は vault の attachments/（features.nix が vault の位置から渡す）。Obsidian の
-- attachmentFolderPath と同じフォルダで、rclone bisync が Google Drive に同期する。
--
-- 挿入されるリンクは relative_template_path(既定 true)で現在ファイルからの相対パスになるため、
-- Obsidian でも Neovim(image.nvim のインライン表示)でも同一に解決される。
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
          "(modules/home-manager/dev/neovim/features.nix を確認)",
          vim.log.levels.WARN
        )
      end
    end
  end,
  opts = {
    default = {
      dir_path = require("config.nix").data.img_clip.dir,
      relative_to_current_file = false,
      file_name = "%Y-%m-%d-%H-%M-%S",
    },
  },
  keys = {
    { "<leader>p", "<cmd>PasteImage<cr>", desc = "Paste image from clipboard" },
  },
}
