local function is_chromeos()
  local stat = vim.loop.fs_stat("/dev/.cros_milestone")
  return stat and stat.type == "file"
end

-- 基本設定
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"
-- vim.opt.mouse = ""  -- マウス無効化
vim.opt.number = true
vim.opt.relativenumber = true
vim.cmd("filetype plugin on") -- ファイルタイプ検出有効化

-- 表示関連
vim.opt.title = true     -- タイトル表示
vim.opt.showcmd = true   -- コマンド表示
vim.opt.showmatch = true -- 括弧の対応表示
vim.opt.wildmenu = true  -- コマンドライン補完
vim.opt.wildmode = "list:longest"
-- vim.opt.laststatus = 3 -- barを一つにまとめる
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

-- chromeOSではwl-clipboard
if is_chromeos() then
  vim.g.clipboard = {
    name = "wl-clipboard",
    copy = {
      ["+"] = "wl-copy",
      ["*"] = "wl-copy",
    },
    paste = {
      ["+"] = "wl-paste",
      ["*"] = "wl-paste",
    },
    cache_enabled = 1,
  }
  vim.opt.clipboard = "unnamedplus"
end

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

-- fをesc代わりにする
map("i", "<C-f>", "<Esc>", { noremap = true })
map("c", "<C-f>", "<Esc>", { noremap = true })
map("n", "<C-f>", "<Esc>", { noremap = true })


-- 自動コマンド
local autocmd = vim.api.nvim_create_autocmd

-- 保存時末尾空白削除
autocmd("BufWritePre", {
  pattern = "*",
  callback = function()
    vim.cmd([[%s/\s\+$//e]])
  end
})

-- ファイルタイプ固有設定
autocmd("FileType", {
  pattern = "typst",
  callback = function()
    vim.cmd("source ~/.config/nvim/ftplugins/typst.vim")
  end
})

autocmd("FileType", {
  pattern = "markdown",
  callback = function()
    vim.cmd("luafile ~/.config/nvim/ftplugins/markdown.lua")
  end
})

-- Undo設定
if vim.fn.has("persistent_undo") == 1 then
  vim.opt.undodir = vim.fn.expand("~/.vim/undo")
  vim.opt.undofile = true
end

-- その他の設定
vim.opt.nuw = 4     -- 行番号表示幅
vim.wo.wrap = false -- 折り返し無効化

require("config.lazy")

local function trim(s)
  return s:match("^%s*(.-)%s*$")
end

local function GetFcitxStatus()
  local handle = io.popen('fcitx5-remote -n')
  local result = handle:read("*a")
  handle:close()
  return trim(result)
end

local function OnInsertLeave()
  -- Save fcitx status when leaving insert mode
  vim.g.fcitx_status = GetFcitxStatus()
  -- Disable (Japanese) input method
  os.execute('fcitx5-remote -c')
end

local function Enable(status)
  if status ~= 'keyboard-us' then
    os.execute('fcitx5-remote -o')
  end
end

vim.g.fcitx_status = GetFcitxStatus()

-- Autocmd for InsertLeave and InsertEnter
vim.api.nvim_create_autocmd("InsertLeave", {
  callback = OnInsertLeave
})
vim.api.nvim_create_autocmd("InsertEnter", {
  callback = function()
    Enable(vim.g.fcitx_status)
  end
})

vim.api.nvim_create_user_command('Redir', function(ctx)
  -- pcallを使ってエラーハンドリングを行いながらコマンドを実行
  local ok, result = pcall(vim.fn.execute, ctx.args)
  if not ok then
    -- pcallが失敗した場合は、エラーメッセージを結果として扱う
    result = tostring(result)
  end
  -- 結果が文字列でない場合に備えて文字列に変換
  local output = tostring(result)
  -- 新しいバッファを作成
  vim.cmd('new')
  -- 実行結果（改行区切りの文字列）をバッファの行データに設定
  vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(output, '\n', { plain = true }))
  -- バッファを未変更状態に設定（終了時の警告を防ぐ）
  vim.opt_local.modified = false
end, { nargs = '+', complete = 'command' })
