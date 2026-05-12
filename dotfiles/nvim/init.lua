-- 基本設定
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"
vim.opt.number = true
vim.opt.relativenumber = true
vim.cmd("filetype plugin on") -- ファイルタイプ検出有効化

-- 表示関連
vim.opt.title = true     -- タイトル表示
vim.opt.showcmd = true   -- コマンド表示
vim.opt.showmatch = true -- 括弧の対応表示
vim.opt.wildmenu = true  -- コマンドライン補完
vim.opt.wildmode = "list:longest"
vim.cmd([[
  augroup TransparentBackground
    autocmd!
    autocmd ColorScheme * highlight Normal ctermbg=none guibg=none
    autocmd ColorScheme * highlight NonText ctermbg=none guibg=none
  augroup END
]])

vim.cmd("colorscheme default") -- ここで使用しているカラースキームを指定

-- 編集関連
vim.opt.ignorecase = true -- 大文字小文字を区別しない
vim.opt.smartindent = true
vim.opt.autoindent = true
vim.opt.expandtab = true -- タブをスペースに変換
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.clipboard:append { 'unnamed', 'unnamedplus' }

-- ファイル処理
vim.opt.autoread = true  -- 外部変更を自動検知
vim.opt.swapfile = false -- スワップファイル無効化

-- 検索設定
vim.opt.hlsearch = true -- 検索ハイライト
vim.keymap.set("n", "<Esc><Esc>", ":nohlsearch<CR>", { silent = true })

-- キーマッピング
local map = vim.keymap.set

-- ビジュアルモードのマッピング
map("x", "d", '"_d', { noremap = true })
map("x", "p", '"_dP', { noremap = true })

-- 表示行移動
map("n", "k", "gk", { noremap = true })
map("n", "gk", "k", { noremap = true })
map("n", "j", "gj", { noremap = true })
map("n", "gj", "j", { noremap = true })

-- スクロール加速
map("n", "<C-j>", "5j", { noremap = true })
map("n", "<C-k>", "5k", { noremap = true })
map("x", "<C-j>", "5j", { noremap = true })
map("x", "<C-k>", "5k", { noremap = true })
map("v", "<C-j>", "5j", { noremap = true })
map("v", "<C-k>", "5k", { noremap = true })

-- 自動コマンド
local autocmd = vim.api.nvim_create_autocmd

-- 保存時末尾空白削除
autocmd("BufWritePre", {
  pattern = "*",
  callback = function()
    vim.cmd([[%s/\s\+$//e]])
  end
})

-- Undo設定
local undodir = vim.fn.stdpath("state") .. "/undo"

-- ディレクトリが存在しない場合は作成する
if vim.fn.isdirectory(undodir) == 0 then
    vim.fn.mkdir(undodir, "p")
end

vim.opt.undodir = undodir
vim.opt.undofile = true

-- その他の設定
vim.opt.nuw = 4     -- 行番号表示幅
vim.wo.wrap = false -- 折り返し無効化

require("config.lazy")
