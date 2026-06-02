-- -- Bootstrap lazy.nvim
-- local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
-- if not (vim.uv or vim.loop).fs_stat(lazypath) then
--   local lazyrepo = "https://github.com/folke/lazy.nvim.git"
--   local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
--   if vim.v.shell_error ~= 0 then
--     vim.api.nvim_echo({
--       { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
--       { out, "WarningMsg" },
--       { "\nPress any key to exit..." }, }, true, {})
--     vim.fn.getchar()
--     os.exit(1)
--   end
-- end
-- vim.opt.rtp:prepend(lazypath)

-- Setup lazy.nvim
-- ~/.config/nvim は mkOutOfStoreSymlink でリポジトリ実体を指す symlink のため、
-- lockfile (lazy-lock.json) はデフォルト位置 (config dir 直下) のまま git で追跡できる。
require("lazy").setup({
  performance = {
    reset_packpath = false, -- packpathのリセットを無効化
    rtp = {
      reset = false, -- rtpのリセットを無効化
    }
  },
  spec = {
    -- import your plugins
    { import = "plugins" },
  },
  -- Configure any other settings here. See the documentation for more details.
  -- colorscheme that will be used when installing plugins.
  install = {
      missing = true,
  },
  ---@diagnostic disable-next-line: assign-type-mismatch
  dev = {
    -- Nixがインストールしたプラグインの場所を指定
    path = "${pkgs.vimUtils.packDir config.home-manager.users.USERNAME.programs.neovim.finalPackage.passthru.packpathDirs}/pack/myNeovimPackages/start",
  },
})
