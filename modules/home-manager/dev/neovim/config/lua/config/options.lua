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
-- クリップボードはターミナル（kitty）が持つ。OSC 52 で読み書きするので、xclip や wl-clipboard は要らない。
-- 'clipboard' を設定すると Neovim は OSC 52 を自分で選ばないので、明示する。
vim.g.clipboard = "osc52"
vim.opt.clipboard:append { "unnamedplus" }
vim.opt.ignorecase = true
vim.opt.smartindent = true
vim.opt.autoindent = true
vim.opt.expandtab = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4

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
