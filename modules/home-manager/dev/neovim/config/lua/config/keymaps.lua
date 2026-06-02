local map = vim.keymap.set

-- 検索ハイライト解除
map("n", "<Esc><Esc>", ":nohlsearch<CR>", { silent = true })

-- ビジュアルモード: レジスタを汚さない d / p
map("x", "d", '"_d', { noremap = true })
map("x", "p", '"_dP', { noremap = true })

-- 表示行移動
map("n", "k", "gk", { noremap = true })
map("n", "gk", "k", { noremap = true })
map("n", "j", "gj", { noremap = true })
map("n", "gj", "j", { noremap = true })
