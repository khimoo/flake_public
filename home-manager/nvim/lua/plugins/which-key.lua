return {
    {
        "folke/which-key.nvim",
        event = "VeryLazy",
        opts = {
            preset = "modern",
            triggers = {
                { "<auto>", mode = "nixsotc" },
                -- { "y",      mode = { "n", "v", "i", "x", "s", "o" } },
                -- { "d",      mode = { "n", "v", "i", "x", "s", "o" } },
            }
        },
        --[[ config = function()
            function CheckMissingDesc()
                local modes = { "n", "v", "i", "x", "s", "o" }
                for _, mode in ipairs(modes) do
                    local keymaps = vim.api.nvim_get_keymap(mode)
                    print("=== Mode: " .. mode .. " ===")
                    for _, keymap in ipairs(keymaps) do
                        if not keymap.desc then
                            -- rhs または callback を取得
                            local rhs = keymap.rhs
                            local cb = keymap.callback if rhs then
                                print("No desc: " .. keymap.lhs .. " -> " .. rhs)
                            elseif cb then
                                print("No desc: " .. keymap.lhs .. " -> [function] " .. tostring(cb))
                            else
                                print("No desc: " .. keymap.lhs .. " -> <unknown>")
                            end
                        end
                    end
                end
            end
        end, ]]
    }
}
