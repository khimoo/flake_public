return {
    "stevearc/oil.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
        require("oil").setup {
            default_file_explorer = true,
            view_options = {
                show_hidden = true,
            },
            keymaps = {
                -- <C-h> / <C-l> は smart-splits のペイン移動に譲る
                ["<C-h>"] = false,
                ["<C-l>"] = false,
                ["<C-x>"] = { "actions.select", opts = { horizontal = true } },
                ["gr"] = "actions.refresh",
            },
        }
        vim.keymap.set("n", "<leader>fe", "<CMD>Oil<CR>", { desc = "File explorer (Oil)" })
    end,
}
