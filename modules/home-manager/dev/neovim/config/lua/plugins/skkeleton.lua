return {
    { 'delphinus/skkeleton_indicator.nvim', opts = {} }, -- skkeletonのdependenciesに書くと一番最初だけ表示されない(おそらくlazy読み込みが考慮されていない)
    {
        'vim-skk/skkeleton',
        dependencies = {"vim-denops/denops.vim"},
        event = 'InsertEnter',
        config = function()
            local function skkeleton_init()
                vim.fn['skkeleton#config']({
                    -- 生成元: modules/home-manager/core.nix
                    globalDictionaries = {{dofile(vim.fn.stdpath("data") .. "/nix/skk-dict-path.lua"), 'euc-jp'}},
                    eggLikeNewline = true,
                    keepMode = true,
                    keepState = true,
                    setUndoPoint = false,
                    -- showCandidatesCount = 1,
                })
                vim.fn['skkeleton#register_kanatable']('rom', {
                    ["z<Space>"] = { "\\u3000", '' },
                    [","] = { ', ' },
                    ["."] = { '. ' },
                })
            end

            vim.api.nvim_create_augroup('skkeleton_initialize_pre', { clear = true })
            vim.api.nvim_create_autocmd('User', {
                group = 'skkeleton_initialize_pre',
                pattern = 'skkeleton-initialize-pre',
                callback = skkeleton_init,
            })

            vim.api.nvim_create_augroup('skkeleton_enable_pre', { clear = true })
            vim.api.nvim_create_autocmd('User', {
                group = 'skkeleton_enable_pre',
                pattern = 'skkeleton-enable-pre',
                callback = function()
                    require('blink.cmp').hide()
                    vim.b.completion = false
                end
            })

            vim.api.nvim_create_augroup('skkeleton_disable_pre', { clear = true })
            vim.api.nvim_create_autocmd('User', {
                group = 'skkeleton_disable_pre',
                pattern = 'skkeleton-disable-pre',
                callback = function()
                    vim.b.completion = true
                end
            })

            vim.api.nvim_set_keymap('i', '<C-j>', '<Cmd>call skkeleton#handle("enable", {})<CR>', { noremap = true, silent = true })
            vim.api.nvim_set_keymap('c', '<C-j>', '<Cmd>call skkeleton#handle("enable", {})<CR>', { noremap = true, silent = true })
        end,
    },
}
