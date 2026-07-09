-- クリップボード画像を貼り付けて Obsidian vault ルートの attachments/ に保存 + リンク挿入
-- 依存: wl-clipboard (Wayland) / xclip (X11) — dev/neovim/default.nix の nvimPluginDeps で導入
--
-- 保存先は zettelkasten vault の attachments/ に固定(ハードコード)。
-- これは Obsidian の attachmentFolderPath="attachments" と物理的に一致し、rclone bisync で
-- Google Drive に同期される単一フォルダ(~/sagyo/zettelkasten/attachments)へ集約する。
--
-- TODO: 将来 neovim 設定を独立モジュールとして切り出す際、この保存先を option 化して
--       外(flake)から注入できるようにする。それまでは暫定でハードコードする。
--       (副作用: zettelkasten 以外の Obsidian vault で貼っても保存先はここに固定される。
--        以前の .obsidian 上方向探索は「開いている vault の attachments」に振り分けていた)
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
          "(modules/home-manager/dev/{lsp,neovim/default}.nix の nvimPluginDeps を確認)",
          vim.log.levels.WARN
        )
      end
    end
  end,
  opts = {
    default = {
      dir_path = vim.fn.expand("~/sagyo/zettelkasten/attachments"),
      relative_to_current_file = false,
      file_name = "%Y-%m-%d-%H-%M-%S",
    },
  },
  keys = {
    { "<leader>p", "<cmd>PasteImage<cr>", desc = "Paste image from clipboard" },
  },
}
