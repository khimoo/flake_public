-- -- ai.luaのcopilot.luaも必要
-- return {
--     {
--         -- 補完エンジン nvim-cmp の設定
--         "hrsh7th/nvim-cmp",
--         event = "InsertEnter", -- 挿入モードに入ったときにプラグインをロード
--         dependencies = { -- nvim-cmp に必要な依存プラグイン
--              "hrsh7th/cmp-buffer" , -- 現在のバッファの内容を補完候補に含める
--              "saadparwaiz1/cmp_luasnip" , -- LuaSnip と nvim-cmp を統合
--              "L3MON4D3/LuaSnip" , -- スニペットエンジン LuaSnip
--              "rafamadriz/friendly-snippets" , -- 事前定義されたスニペットコレクション
--              "hrsh7th/cmp-nvim-lsp", -- LSP補完
--              --[[ {
--                  "uga-rosa/cmp-skkeleton",
--                  dependencies = { "vim-skk/skkeleton" }
--              } ]]
--             -- {
--             --   "zbirenbaum/copilot-cmp",
--             --   config = function ()
--             --     require("copilot_cmp").setup()
--             --   end
--             -- }
--         },
--         config = function()
--             -- nvim-cmp の設定
--             local cmp = require("cmp") -- nvim-cmp のメインモジュールをロード
--             local luasnip = require("luasnip") -- LuaSnip のモジュールをロード
--             local has_words_before = function()
--               if vim.api.nvim_buf_get_option(0, "buftype") == "prompt" then return false end
--               local line, col = unpack(vim.api.nvim_win_get_cursor(0))
--               return col ~= 0 and vim.api.nvim_buf_get_text(0, line-1, 0, line-1, col, {})[1]:match("^%s*$") == nil
--             end
--
--             require("luasnip/loaders/from_vscode").lazy_load() -- VSCode スタイルのスニペットをロード
--             cmp.setup({
--                 mapping = cmp.mapping.preset.insert({
--                     ["<Tab>"] = vim.schedule_wrap(function(fallback)
--                       if cmp.visible() and has_words_before() then
--                         cmp.select_next_item({ behavior = cmp.SelectBehavior.Select })
--                       else
--                         fallback()
--                       end
--                     end),
--                     ["<C-b>"] = cmp.mapping.scroll_docs(-4), -- 補完候補のドキュメントを上にスクロール
--                     ["<C-f>"] = cmp.mapping.scroll_docs(4), -- 補完候補のドキュメントを下にスクロール
--                     ["<C-e>"] = cmp.mapping.abort(), -- 補完を中断して閉じる
--                 }),
--                 sources = {
--                     { name = "luasnip" },
--                     { name = "nvim_lsp" },
--                     -- { name = "skkeleton" },
--                     { name = "buffer" }, -- バッファの内容を補完候補に含める
--                     -- { name = "copilot" },
--                 },
--             })
--         end,
--     },
-- },
return {
  --[[ {
    'saghen/blink.compat',
    -- use v2.* for blink.cmp v1.*
    version = '2.*',
    -- lazy.nvim will automatically load the plugin when it's required by blink.cmp
    lazy = true,
    -- make sure to set opts so that lazy.nvim calls blink.compat's setup
    opts = {},
  }, ]]
  {
  'saghen/blink.cmp',
  version = '*', -- バイナリをダウンロードする場合
  --[[ dependencies = {
    "uga-rosa/cmp-skkeleton",
  },
  sources = {
    default = { 'lsp', 'path', 'snippets', 'buffer', 'skkeleton' },
    providers = {
      skkeleton = {
        name = 'skkeleton',
        module = 'blink.compat.source',
      }
    }
  }, ]]
  opts = {
    -- 次の項目で紹介
    },
  }
}
