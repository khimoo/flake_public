return {
    --[[ {
        "lukas-reineke/indent-blankline.nvim",
        config = function()
            vim.cmd('syntax enable')
            vim.cmd('colorscheme desert')
            -- https://qiita.com/s4kr4/items/b2c1b692ec430fe24f15
            vim.cmd('highlight Normal ctermbg=NONE guibg=NONE')
            vim.cmd('highlight NonText ctermbg=NONE guibg=NONE')
            vim.cmd('highlight SpecialKey ctermbg=NONE guibg=NONE')
            vim.cmd('highlight EndOfBuffer ctermbg=NONE guibg=NONE')

            -- termguicolorsがonになっていることに注意
            vim.cmd('highlight IblIndent ctermfg=230 guifg=#877b7a gui=bold')
            vim.cmd('highlight IblIndent1 ctermfg=230 guifg=#877b7a gui=bold')
            vim.cmd('highlight IblScope ctermfg=230 guifg=#98c0c3')

            vim.o.list = true
            vim.o.listchars = "lead:."

            local indent = {
              "IblIndent",
              "IblIndent1",
            }

            local whitespace = {
              "IblIndent",
              "IblIndent1",
            }

            local scope = {
              "Whitespace",
              "IblIndent",
            }

            require("ibl").setup {
              indent = { highlight = indent, char = "|" },
              whitespace = {
                highlight = whitespace,
                remove_blankline_trail = false,
              },
              scope = {
                char = "║",
              },
            }
        end
    }, ]]
    {
        "shellRaining/hlchunk.nvim",
        event = { "BufReadPre", "BufNewFile" },
        config = function()
            require("hlchunk").setup({
                chunk = {
                    enable = true
                },
                line_num = {
                    enable = true
                },
            })
        end
    },
}
