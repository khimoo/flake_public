local autocmd = vim.api.nvim_create_autocmd

-- 透過背景（TERMINAL_TRANSPARENT が設定されている場合のみ有効）
-- 環境変数は gui/default.nix で設定される
if vim.env.TERMINAL_TRANSPARENT then
    autocmd("ColorScheme", {
        pattern = "*",
        callback = function()
            vim.api.nvim_set_hl(0, "Normal", { bg = "none", ctermbg = "none" })
            vim.api.nvim_set_hl(0, "NonText", { bg = "none", ctermbg = "none" })
        end,
    })
end
vim.cmd("colorscheme default")

-- 保存時末尾空白削除
autocmd("BufWritePre", {
    pattern = "*",
    callback = function()
        local pos = vim.api.nvim_win_get_cursor(0)
        vim.cmd([[%s/\s\+$//e]])
        vim.api.nvim_win_set_cursor(0, pos)
    end,
})
