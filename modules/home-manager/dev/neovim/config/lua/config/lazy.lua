-- lazy.nvim 本体は nixpkgs (programs.neovim.plugins の lazy-nvim) から入り、
-- Nix のラッパが packpath に載せるので git clone のブートストラップは要らない。
-- プラグイン本体は lazy.nvim が clone し、lazy-lock.json で固定する。
-- 経緯と比較した代替案: docs/architecture/neovim/plugin-manager.md
--
-- ~/.config/nvim は dotfiles-mode 経由の symlink。既定は Nix store（読み取り専用）、
-- Dev モード ON 時だけ checkout（書き込み可能）を指す（docs/howtouse/dotfiles-mode.md）。
-- store モード中は lazy-lock.json へ書き込めないため、lockfile を stdpath("state") へ逃がす。
-- Dev モード ON にすれば checkout 側の lazy-lock.json へそのまま書き戻せる。
local config_dir = vim.fn.stdpath("config")
local lockfile = config_dir .. "/lazy-lock.json"
if not vim.uv.fs_access(config_dir, "W") then
  local state_dir = vim.fn.stdpath("state")
  local state_lockfile = state_dir .. "/lazy-lock.json"
  if not vim.uv.fs_stat(state_lockfile) and vim.uv.fs_stat(lockfile) then
    vim.fn.mkdir(state_dir, "p")
    local src = io.open(lockfile, "rb")
    if src then
      local data = src:read("*a")
      src:close()
      local dst = io.open(state_lockfile, "wb")
      if dst then
        dst:write(data)
        dst:close()
      end
    end
  end
  lockfile = state_lockfile
end

-- 外部コマンドや Nix の生成物を使うプラグインは lua/features/ に置き、Home Manager が
-- 有効にした機能だけを読み込む。lua/plugins/ の一括 import はそれらを拾わない。
local spec = { { import = "plugins" } }
for _, name in ipairs(require("config.nix").features) do
  spec[#spec + 1] = { import = "features." .. name }
end

require("lazy").setup({
  lockfile = lockfile,
  performance = {
    -- Nix のラッパが packpath/rtp に載せた lazy.nvim 本体を見失わないよう、
    -- lazy.nvim 側のリセットを止める。
    reset_packpath = false,
    rtp = {
      reset = false,
    }
  },
  spec = spec,
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
