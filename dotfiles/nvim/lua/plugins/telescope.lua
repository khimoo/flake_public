-- skkeletonがinsertenterで読み込まれることを前提に書いてる
return {
    {
        "nvim-telescope/telescope.nvim",
        dependencies = {
            "nvim-lua/plenary.nvim",
            'nvim-telescope/telescope-media-files.nvim',
            "BurntSushi/ripgrep",
            "ahmedkhalf/project.nvim", -- どこにいてもgitのrootにcdしてくれるplugin
        },
        config = function()
            -- Telescopeの基本設定
            require("telescope").setup {
            }

            -- キーマッピングの設定
            local builtin = require("telescope.builtin")
            vim.keymap.set("n", "<leader>ff", builtin.find_files, { desc = "Find files" })
            vim.keymap.set("n", "<leader>fg", builtin.live_grep, { desc = "Live grep" })
            vim.keymap.set("n", "<leader>fb", builtin.buffers, { desc = "Buffers" })
            vim.keymap.set("n", "<leader>fh", builtin.help_tags, { desc = "Help tags" })
            vim.keymap.set("n", "<leader>fd", builtin.diagnostics, { desc = "Diagnostics" })
            vim.keymap.set("n", "<leader>fs", builtin.lsp_document_symbols, { desc = "Document symbols" })
            vim.keymap.set("n", "<leader>fS", builtin.lsp_workspace_symbols, { desc = "Workspace symbols" })
            vim.keymap.set("n", "<leader>fr", builtin.lsp_references, { desc = "LSP references" })
            vim.keymap.set("n", "<leader>fo", builtin.oldfiles, { desc = "Recent files" })
            vim.keymap.set("n", "<leader>ft", ":Telescope<CR>", { desc = "Telescope commands" })
        end
    },
}
