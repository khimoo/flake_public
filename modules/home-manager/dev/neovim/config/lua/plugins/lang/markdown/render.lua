-- バッファ内装飾レンダリング (見出し背景色、テーブル罫線、チェックボックス等)
return {
  "MeanderingProgrammer/render-markdown.nvim",
  ft = { "markdown" },
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "nvim-tree/nvim-web-devicons",
  },
  opts = {},
}
