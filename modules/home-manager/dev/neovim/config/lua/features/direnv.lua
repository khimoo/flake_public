return {
    {
        "actionshrimp/direnv.nvim",
        main = "direnv-nvim",
        lazy = false,
        opts = {
            type = "dir",
            async = true,
            hook = { msg = nil },
            on_direnv_finished = function()
                require("config.project").on_direnv_finished()
            end,
        },
    },
}
