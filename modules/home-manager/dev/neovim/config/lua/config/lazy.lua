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
  -- luarocks 統合を無効化。Nix 環境では lazy.nvim 内蔵の hererocks (luarocks 用の
  -- 埋め込み Lua) が組めず、rockspec を持つプラグイン (image.nvim 等) が落ちる。
  -- 必要な luarock は programs.neovim.extraLuaPackages 経由で nixpkgs から注入する。
  rocks = {
      enabled = false,
  },
  -- rockspec の自動読み込みも無効化。rocks.enabled = false だけでは image.nvim 等の
  -- .rockspec を依然パースし、依存 (magick) を「未解決プラグイン」扱いし続けて
  -- "Too many rounds of missing plugins" になる。
  pkg = {
      sources = { "lazy", "packspec" },
  },
  ---@diagnostic disable-next-line: assign-type-mismatch
  dev = {
    -- Nixがインストールしたプラグインの場所を指定
    path = "${pkgs.vimUtils.packDir config.home-manager.users.USERNAME.programs.neovim.finalPackage.passthru.packpathDirs}/pack/myNeovimPackages/start",
  },
})
