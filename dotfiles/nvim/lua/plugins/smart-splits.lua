return {
  "mrjones2014/smart-splits.nvim",
  lazy = false,
  opts = {
    at_edge = "wrap",
    default_amount = 3,
    disable_multiplexer_nav_when_zoomed = true,
  },
  keys = {
    { "<C-h>", function() require("smart-splits").move_cursor_left() end, desc = "Move to left split" },
    { "<C-j>", function() require("smart-splits").move_cursor_down() end, desc = "Move to below split" },
    { "<C-k>", function() require("smart-splits").move_cursor_up() end, desc = "Move to above split" },
    { "<C-l>", function() require("smart-splits").move_cursor_right() end, desc = "Move to right split" },

    { "<A-h>", function() require("smart-splits").resize_left() end, desc = "Resize split left" },
    { "<A-j>", function() require("smart-splits").resize_down() end, desc = "Resize split down" },
    { "<A-k>", function() require("smart-splits").resize_up() end, desc = "Resize split up" },
    { "<A-l>", function() require("smart-splits").resize_right() end, desc = "Resize split right" },

    { "<leader><leader>h", function() require("smart-splits").swap_buf_left() end, desc = "Swap buffer left" },
    { "<leader><leader>j", function() require("smart-splits").swap_buf_down() end, desc = "Swap buffer down" },
    { "<leader><leader>k", function() require("smart-splits").swap_buf_up() end, desc = "Swap buffer up" },
    { "<leader><leader>l", function() require("smart-splits").swap_buf_right() end, desc = "Swap buffer right" },
  },
}
