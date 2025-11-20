return {
    {
        "nvim-treesitter/nvim-treesitter",
        build = ":TSUpdate",
        main = 'nvim-treesitter.configs',
        opts = { highlight = { enable = true } },
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
        'stevearc/aerial.nvim',
        config = function ()
            require("aerial").setup({
              -- optionally use on_attach to set keymaps when aerial has attached to a buffer
              on_attach = function(bufnr)
                -- Jump forwards/backwards with '{' and '}'
                vim.keymap.set("n", "{", "<cmd>AerialPrev<CR>", { buffer = bufnr })
                vim.keymap.set("n", "}", "<cmd>AerialNext<CR>", { buffer = bufnr })
              end,
            })
            -- You probably also want to set a keymap to toggle aerial
            vim.keymap.set("n", "<leader>o", "<cmd>AerialToggle!<CR>")
        end,
        -- Optional dependencies
        dependencies = {
            "nvim-treesitter/nvim-treesitter",
            "nvim-tree/nvim-web-devicons",
        },
    },
}
