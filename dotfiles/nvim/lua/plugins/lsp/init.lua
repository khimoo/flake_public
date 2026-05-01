return {
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "saghen/blink.cmp",
    },
    config = function()
      require("config.lsp.keymaps").setup()
      require("config.lsp.diagnostics").setup()

      local capabilities = require('blink.cmp').get_lsp_capabilities()

      -- 環境変数からサーバー一覧を取得
      local env = os.getenv("NEOVIM_LSP_SERVERS") or ""
      local servers = {}
      for name in env:gmatch("([^,]+)") do
        table.insert(servers, name)
      end

      -- サーバー固有の設定
      local overrides = {
        tinymist = {
          settings = {
            exportPdf = "onType",
            outputPath = "/tmp/tinymist",
          },
        },
        nil_ls = {
          settings = {
            ['nil'] = { formatting = { command = { "nixfmt" } } },
          },
        },
      }

      for _, name in ipairs(servers) do
        local server_config = { capabilities = capabilities }
        if overrides[name] then
          server_config = vim.tbl_deep_extend("force", server_config, overrides[name])
        end
        vim.lsp.config(name, server_config)
        vim.lsp.enable(name)
      end
    end,
  },
}
