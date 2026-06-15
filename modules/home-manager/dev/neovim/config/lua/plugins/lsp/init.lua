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
    -- opts.servers に各言語モジュール (lang/<x>/) から設定を追加できる。
    -- 同じ "neovim/nvim-lspconfig" spec を別ファイルで宣言して
    -- opts.servers.<name> = {...} を書けば lazy.nvim が deep-merge する。
    opts = {
      servers = {
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
      },
    },
    config = function(_, opts)
      require("config.lsp.keymaps").setup()
      require("config.lsp.diagnostics").setup()

      local capabilities = require('blink.cmp').get_lsp_capabilities()

      -- Nix 生成ファイルから有効化対象のサーバー一覧を取得
      -- (生成元: modules/home-manager/dev/neovim/default.nix, リスト定義: dev/lsp.nix)
      local servers = dofile(vim.fn.stdpath("data") .. "/nix/lsp-servers.lua")
      local overrides = opts.servers or {}

      for _, name in ipairs(servers) do
        local server_config = vim.tbl_deep_extend(
          "force",
          { capabilities = capabilities },
          overrides[name] or {}
        )
        vim.lsp.config(name, server_config)
        vim.lsp.enable(name)
      end
    end,
  },
}
