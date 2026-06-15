return {
    {
        "nvim-treesitter/nvim-treesitter",
        build = ":TSUpdate",
        main = 'nvim-treesitter.configs',
        opts = {
            highlight = { enable = true },
            -- ensure_installed は各言語モジュール (lang/<x>/treesitter.lua) から
            -- spec マージで追加される
            ensure_installed = {},
        },
    },
    {
        'Wansmer/treesj',
        keys = { '<leader>m' },
        dependencies = { 'nvim-treesitter/nvim-treesitter' },
        config = function () vim.keymap.set("n", "<leader>m", require('treesj').toggle) end
    },
    {
        "RRethy/nvim-treesitter-textsubjects",
        dependencies = { "nvim-treesitter/nvim-treesitter" },
        config = function ()
            require('nvim-treesitter-textsubjects').configure({
                prev_selection = ',',
                keymaps = {
                    ['.'] = 'textsubjects-smart',
                    [';'] = 'textsubjects-container-outer',
                    ['i;'] = 'textsubjects-container-inner',
                },
            })
        end
    },
    {
        "nvim-treesitter/nvim-treesitter-textobjects",
        dependencies = { "nvim-treesitter/nvim-treesitter" },
        config = function()
            require('nvim-treesitter.configs').setup({
                textobjects = {
                    select = {
                        enable = true,
                        lookahead = true,
                        keymaps = {
                            ["af"] = { query = "@function.outer", desc = "Select outer function" },
                            ["if"] = { query = "@function.inner", desc = "Select inner function" },
                            ["ac"] = { query = "@class.outer", desc = "Select outer class" },
                            ["ic"] = { query = "@class.inner", desc = "Select inner class" },
                            ["aa"] = { query = "@parameter.outer", desc = "Select outer argument" },
                            ["ia"] = { query = "@parameter.inner", desc = "Select inner argument" },
                        },
                    },
                    move = {
                        enable = true,
                        set_jumps = true,
                        goto_next_start = {
                            ["]f"] = { query = "@function.outer", desc = "Next function start" },
                            ["]a"] = { query = "@parameter.outer", desc = "Next argument start" },
                        },
                        goto_next_end = {
                            ["]F"] = { query = "@function.outer", desc = "Next function end" },
                        },
                        goto_previous_start = {
                            ["[f"] = { query = "@function.outer", desc = "Prev function start" },
                            ["[a"] = { query = "@parameter.outer", desc = "Prev argument start" },
                        },
                        goto_previous_end = {
                            ["[F"] = { query = "@function.outer", desc = "Prev function end" },
                        },
                    },
                    swap = {
                        enable = true,
                        swap_next = {
                            ["<leader>a"] = { query = "@parameter.inner", desc = "Swap with next argument" },
                        },
                        swap_previous = {
                            ["<leader>A"] = { query = "@parameter.inner", desc = "Swap with prev argument" },
                        },
                    },
                },
            })
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
