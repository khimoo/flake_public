-- Telescope のプロジェクト切替と、direnv 完了後の LSP 再起動を結び付ける。
local M = { pending = false }

function M.switch(path)
    if not path or vim.fn.isdirectory(path) == 0 then
        return
    end
    local dir = vim.fs.normalize(path)
    if dir == vim.fs.normalize(vim.fn.getcwd()) then
        return
    end
    M.pending = true
    vim.api.nvim_set_current_dir(dir)
end

function M.on_direnv_finished()
    if not M.pending then
        return
    end
    M.pending = false
    -- 新しい環境変数で既存の LSP を立ち上げ直す。
    if vim.fn.exists(":LspRestart") == 2 then
        vim.cmd("LspRestart!")
    end
end

vim.api.nvim_create_autocmd("User", {
    pattern = "DirenvBlocked",
    callback = function()
        if M.pending then
            M.pending = false
            vim.notify("direnv: このディレクトリで direnv allow が必要です", vim.log.levels.WARN)
        end
    end,
})

return M
