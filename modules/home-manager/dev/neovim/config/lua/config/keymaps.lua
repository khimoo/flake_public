local map = vim.keymap.set

-- 検索ハイライト解除
map("n", "<Esc><Esc>", ":nohlsearch<CR>", { silent = true })

-- ビジュアルモード: レジスタを汚さない d / p
map("x", "d", '"_d', { noremap = true })
map("x", "p", '"_dP', { noremap = true })

-- kitty keyboard protocol 対応端末でのみ届く。非対応環境では <C-w> がそのまま残る
map("i", "<C-BS>", "<C-w>")

-- 表示行移動
map("n", "k", "gk", { noremap = true })
map("n", "gk", "k", { noremap = true })
map("n", "j", "gj", { noremap = true })
map("n", "gj", "j", { noremap = true })
