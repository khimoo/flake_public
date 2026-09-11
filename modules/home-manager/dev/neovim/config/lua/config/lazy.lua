-- lazy.nvim 本体は nixpkgs (programs.neovim.plugins の lazy-nvim) から入り、
-- Nix のラッパが packpath に載せるので git clone のブートストラップは要らない。
-- プラグイン本体は lazy.nvim が clone し、lazy-lock.json で固定する。
-- 経緯と比較した代替案: docs/architecture/plugin-manager.md
--
-- ~/.config/nvim は mkOutOfStoreSymlink でリポジトリ実体を指す symlink のため、
-- lockfile (lazy-lock.json) はデフォルト位置 (config dir 直下) のまま git で追跡できる。
require("lazy").setup({
  performance = {
    -- Nix のラッパが packpath/rtp に載せた lazy.nvim 本体を見失わないよう、
    -- lazy.nvim 側のリセットを止める。
    reset_packpath = false,
    rtp = {
      reset = false,
    }
  },
  spec = {
    -- import your plugins
    { import = "plugins" },
  },
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
})
