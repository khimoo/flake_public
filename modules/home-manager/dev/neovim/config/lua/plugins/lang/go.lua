return {
  {
    "mfussenegger/nvim-dap",
    -- dap 機能を外すと、nvim-dap と一緒に nvim-dap-go も外れる。
    optional = true,
    dependencies = {
      { "leoluz/nvim-dap-go", opts = {} },
    },
  },
}
