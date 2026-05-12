-- 表示
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.title = true
vim.opt.showcmd = true
vim.opt.showmatch = true
vim.opt.wildmenu = true
vim.opt.wildmode = "list:longest"
vim.opt.nuw = 4
vim.wo.wrap = false

-- 編集
vim.opt.ignorecase = true
vim.opt.smartindent = true
vim.opt.autoindent = true
vim.opt.expandtab = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.clipboard:append { 'unnamed', 'unnamedplus' }

-- 検索
vim.opt.hlsearch = true

-- ファイル処理
vim.opt.autoread = true
vim.opt.swapfile = false

-- Undo
local undodir = vim.fn.stdpath("state") .. "/undo"
if vim.fn.isdirectory(undodir) == 0 then
    vim.fn.mkdir(undodir, "p")
end
vim.opt.undodir = undodir
vim.opt.undofile = true
