return {
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "saghen/blink.cmp",
      {
        "folke/lazydev.nvim",
        ft = "lua", -- Luaファイルのみで起動
        opts = {
          library = {
            -- Neovimのプラグイン開発や設定に便利な型定義を読み込む
            { path = "${3rd}/luv/library", words = { "vim%.uv" } },
            -- lazy.nvimの型定義も読み込む場合
            { path = "lazy.nvim",          words = { "LazyVim" } },
          },
        },
      },
    },
    config = function()
      require("config.lsp.keymaps").setup()
      require("config.lsp.diagnostics").setup()

      local capabilities = require('blink.cmp').get_lsp_capabilities()

      -- Nix 生成ファイルからサーバー一覧を取得 (生成元: modules/home-manager/dev/neovim/default.nix, リスト定義は dev/lsp.nix)
      local servers = dofile(vim.fn.stdpath("data") .. "/nix/lsp-servers.lua")

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
