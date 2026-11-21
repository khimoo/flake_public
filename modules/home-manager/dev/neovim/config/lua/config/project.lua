-- cwd を変更するときは direnv の環境を更新してから LSP を再起動する。
-- 連続した変更は直列化し、古いディレクトリの結果を適用しない。
local M = {}
local running = false
local pending

local function reload_lsp()
    if vim.fn.exists(":LspRestart") == 2 then
        vim.cmd("LspRestart!")
    end
end

local function refresh()
    if running or not pending then
        return
    end
    local cwd = pending
    running = true
    vim.system({ "direnv", "export", "json" }, { cwd = cwd, text = true }, function(result)
        vim.schedule(function()
            running = false
            if pending ~= cwd then
                refresh()
                return
            end
            if result.code ~= 0 then
                vim.notify("direnv: " .. (result.stderr or "export failed"), vim.log.levels.WARN)
                return
            end

            local output = result.stdout or ""
            if output ~= "" then
                local ok, vars = pcall(vim.json.decode, output)
                if not ok or type(vars) ~= "table" then
                    vim.notify("direnv: invalid export JSON", vim.log.levels.ERROR)
                    return
                end
                for key, value in pairs(vars) do
                    vim.env[key] = value == vim.NIL and nil or value
                end
            end

            pending = nil
            reload_lsp()
        end)
    end)
end

function M.switch(path)
    if not path or vim.fn.isdirectory(path) ~= 1 then
        vim.notify("Project directory does not exist: " .. tostring(path), vim.log.levels.WARN)
        return
    end
    local dir = vim.fs.normalize(path)
    if dir ~= vim.fs.normalize(vim.fn.getcwd()) then
        vim.api.nvim_set_current_dir(dir)
    end
end

function M.setup()
    vim.api.nvim_create_user_command("DirenvReload", function()
        pending = vim.fn.getcwd()
        refresh()
    end, { desc = "Reload project environment with direnv" })
    vim.api.nvim_create_autocmd("DirChanged", {
        callback = function()
            pending = vim.fn.getcwd()
            refresh()
        end,
    })
    -- アプリ一覧からの起動でも初期ディレクトリの .envrc を読む。
    pending = vim.fn.getcwd()
    refresh()
end

return M
