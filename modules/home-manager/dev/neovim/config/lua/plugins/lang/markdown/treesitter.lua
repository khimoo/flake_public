-- nvim-treesitter の ensure_installed に markdown 関連パーサを追加する。
-- lazy.nvim の spec マージにより、ベース spec (plugins/treesitter.lua) と本 spec が
-- 同じプラグインを指していると opts が deep-merge される。配列は merge ではなく
-- 上書きされる仕様なので、function 形式で list_extend する必要がある。
--
-- ・markdown / markdown_inline: render-markdown.nvim や marksman 等が要求
-- ・mermaid: diagram.nvim が markdown 内 mermaid ブロックを抽出するため
return {
  "nvim-treesitter/nvim-treesitter",
  opts = function(_, opts)
    opts.ensure_installed = opts.ensure_installed or {}
    vim.list_extend(opts.ensure_installed, { "markdown", "markdown_inline", "mermaid" })
  end,
}
