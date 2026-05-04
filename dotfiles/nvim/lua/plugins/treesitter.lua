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
