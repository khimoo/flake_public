-- nvim-treesitter の ensure_installed に typst パーサを追加する。
-- image.nvim の typst integration が typst バッファを開いた際に
-- vim.treesitter.get_parser(buf, "typst") を呼び出すため、パーサ未導入だと
-- エラーになる。
return {
  "nvim-treesitter/nvim-treesitter",
  opts = function(_, opts)
    opts.ensure_installed = opts.ensure_installed or {}
    vim.list_extend(opts.ensure_installed, { "typst" })
  end,
}
