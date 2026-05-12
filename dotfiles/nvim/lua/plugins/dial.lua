return {
  "monaqa/dial.nvim",
  config = function()
    local map = vim.keymap.set
    local manipulate = require("dial.map").manipulate

    map("n", "<C-a>", function() manipulate("increment", "normal") end, { desc = "Increment" })
    map("n", "<C-x>", function() manipulate("decrement", "normal") end, { desc = "Decrement" })
    map("n", "g<C-a>", function() manipulate("increment", "gnormal") end, { desc = "Increment (sequential)" })
    map("n", "g<C-x>", function() manipulate("decrement", "gnormal") end, { desc = "Decrement (sequential)" })
    map("v", "<C-a>", function() manipulate("increment", "visual") end, { desc = "Increment (visual)" })
    map("v", "<C-x>", function() manipulate("decrement", "visual") end, { desc = "Decrement (visual)" })
    map("v", "g<C-a>", function() manipulate("increment", "gvisual") end, { desc = "Increment (visual sequential)" })
    map("v", "g<C-x>", function() manipulate("decrement", "gvisual") end, { desc = "Decrement (visual sequential)" })

    local augend = require("dial.augend")
    local auconf = require("dial.config")
    local default = auconf.augends:get("default")
    table.insert(default, augend.constant.alias.bool)
    auconf.augends:register_group { default = default }
  end,
}
