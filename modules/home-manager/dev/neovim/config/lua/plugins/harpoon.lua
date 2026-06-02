-- NOTE: harpoon2 が main ブランチに統合されたら branch = "harpoon2" を削除すること
return {
    "ThePrimeagen/harpoon",
    branch = "harpoon2",
    dependencies = {
        "nvim-lua/plenary.nvim",
        { "kiennt63/harpoon-files.nvim", opts = {} },
    },
    config = function()
        local harpoon = require("harpoon")
        harpoon:setup({
            settings = {
                save_on_toggle = true,
            },
        })

        vim.keymap.set("n", "<leader>ha", function() harpoon:list():add() end, { desc = "Harpoon: add file" })
        vim.keymap.set("n", "<leader>hh", function() harpoon.ui:toggle_quick_menu(harpoon:list()) end,
            { desc = "Harpoon: menu" })
        vim.keymap.set("n", "<leader>h1", function() harpoon:list():select(1) end, { desc = "Harpoon: file 1" })
        vim.keymap.set("n", "<leader>h2", function() harpoon:list():select(2) end, { desc = "Harpoon: file 2" })
        vim.keymap.set("n", "<leader>h3", function() harpoon:list():select(3) end, { desc = "Harpoon: file 3" })
        vim.keymap.set("n", "<leader>h4", function() harpoon:list():select(4) end, { desc = "Harpoon: file 4" })
        vim.keymap.set("n", "<leader>h5", function() harpoon:list():select(5) end, { desc = "Harpoon: file 5" })
        vim.keymap.set("n", "gT", function() harpoon:list():prev({ ui_nav_wrap = true }) end, { desc = "Harpoon: prev" })
        vim.keymap.set("n", "gt", function() harpoon:list():next({ ui_nav_wrap = true }) end, { desc = "Harpoon: next" })
    end,
}
