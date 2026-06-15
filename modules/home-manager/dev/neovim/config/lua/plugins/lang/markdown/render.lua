-- バッファ内装飾レンダリング (見出し背景色、テーブル罫線、チェックボックス等)
return {
  "MeanderingProgrammer/render-markdown.nvim",
  ft = { "markdown" },
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "nvim-tree/nvim-web-devicons",
  },
  opts = {
    -- 数式 ($...$, $$...$$) を Unicode 近似で表示する。
    -- 実装: 外部 CLI (latex2text) に LaTeX を渡し、返ってきた Unicode 文字列を
    -- extmark で描画する。画像ではなく Unicode 近似なので、行列など複雑な式は
    -- 粗くなるが、依存が軽くターミナル要件もない。
    -- 依存: pylatexenc (latex2text を提供) — nvim/default.nix の nvimPluginDeps で注入
    latex = {
      enabled = true,
      converter = "latex2text",
    },
  },
}
