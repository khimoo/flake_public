-- Run from the repository root with the configured Neovim (lazy.nvim required):
-- nvim --headless -n -u NONE -i NONE -l scripts/check-neovim-parser-merge.lua
local root = vim.fn.getcwd() .. "/modules/home-manager/dev/neovim/config"
vim.opt.rtp:prepend(root)

local Plugin = require("lazy.core.plugin")
local base = dofile(root .. "/lua/features/treesitter.lua")[1]
local markdown = dofile(root .. "/lua/plugins/lang/markdown/treesitter.lua")
local required = { "markdown", "markdown_inline", "mermaid", "latex" }

-- Exercise lazy.nvim's real option merge in both orders. Existing language
-- parsers must also survive initialization by the shared spec.
for _, order in ipairs({ { base, markdown }, { markdown, base } }) do
    local previous = { opts = { ensure_installed = { "lua" } } }
    for _, spec in ipairs(order) do
        local current = vim.deepcopy(spec)
        current._ = {}
        setmetatable(current, { __index = previous })
        previous = current
    end
    local opts = Plugin.values(previous, "opts", false)
    for _, lang in ipairs(required) do
        assert(vim.list_contains(opts.ensure_installed, lang), "missing parser: " .. lang)
    end
    assert(vim.list_contains(opts.ensure_installed, "lua"), "existing language parser lost")
end

print("PASS: existing and Markdown parsers survive both spec merge orders")
