return {
    {
        "nvim-treesitter/nvim-treesitter",
        branch = "main",
        -- main ブランチは lazy-load を公式に非対応と明記している
        lazy = false,
        build = ":TSUpdate",
        -- ensure_installed は各言語モジュール (lang/<x>/treesitter.lua) から
        -- spec マージで追加される。main ブランチに同名のオプションは無いので、
        -- 本リポジトリ内の受け渡し用の名前として残し config で install() に渡す。
        opts = { ensure_installed = {} },
        config = function(_, opts)
            require("nvim-treesitter").install(opts.ensure_installed)

            -- master の highlight = { enable = true } 相当。
            -- main はハイライトを有効化せず、Neovim 側の vim.treesitter.start を
            -- 呼ぶのは利用者の責務になった。パーサ未導入の filetype では
            -- start がエラーを投げるので pcall で握る。
            vim.api.nvim_create_autocmd("FileType", {
                group = vim.api.nvim_create_augroup("user_treesitter_start", { clear = true }),
                callback = function(ev)
                    pcall(vim.treesitter.start, ev.buf)
                end,
            })
        end,
    },
    {
        'Wansmer/treesj',
        keys = { '<leader>m' },
        dependencies = { 'nvim-treesitter/nvim-treesitter' },
        config = function () vim.keymap.set("n", "<leader>m", require('treesj').toggle) end
    },
    {
        "nvim-treesitter/nvim-treesitter-textobjects",
        branch = "main",
        dependencies = { "nvim-treesitter/nvim-treesitter" },
        config = function()
            require("nvim-treesitter-textobjects").setup({
                select = { lookahead = true },
                move = { set_jumps = true },
            })

            local select = require("nvim-treesitter-textobjects.select")
            local move = require("nvim-treesitter-textobjects.move")
            local swap = require("nvim-treesitter-textobjects.swap")
            local map = vim.keymap.set

            for key, query in pairs({
                ["af"] = "@function.outer",
                ["if"] = "@function.inner",
                ["ac"] = "@class.outer",
                ["ic"] = "@class.inner",
                ["aa"] = "@parameter.outer",
                ["ia"] = "@parameter.inner",
            }) do
                map({ "x", "o" }, key, function()
                    select.select_textobject(query, "textobjects")
                end, { desc = "Select " .. query })
            end

            for key, spec in pairs({
                ["]f"] = { move.goto_next_start, "@function.outer" },
                ["]F"] = { move.goto_next_end, "@function.outer" },
                ["[f"] = { move.goto_previous_start, "@function.outer" },
                ["[F"] = { move.goto_previous_end, "@function.outer" },
                ["]a"] = { move.goto_next_start, "@parameter.outer" },
                ["[a"] = { move.goto_previous_start, "@parameter.outer" },
            }) do
                map({ "n", "x", "o" }, key, function()
                    spec[1](spec[2], "textobjects")
                end, { desc = "Move to " .. spec[2] })
            end

            map("n", "<leader>a", function() swap.swap_next("@parameter.inner") end,
                { desc = "Swap with next argument" })
            map("n", "<leader>A", function() swap.swap_previous("@parameter.inner") end,
                { desc = "Swap with prev argument" })
        end,
    },
    {
        'stevearc/aerial.nvim',
        config = function ()
            require("aerial").setup({
              on_attach = function(bufnr)
                vim.keymap.set("n", "[s", "<cmd>AerialPrev<CR>", { buffer = bufnr, desc = "Aerial: prev symbol" })
                vim.keymap.set("n", "]s", "<cmd>AerialNext<CR>", { buffer = bufnr, desc = "Aerial: next symbol" })
              end,
            })
            vim.keymap.set("n", "<leader>o", "<cmd>AerialToggle!<CR>", { desc = "Aerial: toggle outline" })
        end,
        -- Optional dependencies
        dependencies = {
            "nvim-treesitter/nvim-treesitter",
            "nvim-tree/nvim-web-devicons",
        },
    },
}
