-- Mermaid 等の図をバッファ内にインラインプレビューする。
-- 構成: diagram.nvim が mermaid ソースを抽出 → mmdc で PNG 化 →
--       image.nvim が WezTerm の Kitty graphics protocol 経由で表示。
--
-- 依存 (Nix 側で注入済み):
--   - mermaid-cli (mmdc):       modules/home-manager/dev/neovim/default.nix
--   - imagemagick (magick CLI): 同上
--   - magick luarock:           programs.neovim.extraLuaPackages
return {
    {
        "3rd/image.nvim",
        dependencies = { "nvim-treesitter/nvim-treesitter" },
        opts = {
            backend = "kitty", -- WezTerm は Kitty graphics protocol 互換
            processor = "magick_cli",
            integrations = {
                markdown = {
                    enabled = true,
                    only_render_image_at_cursor = false,
                    filetypes = { "markdown", "vimwiki" },
                },
            },
            max_width = 100,
            max_height = 30,
            max_width_window_percentage = nil,
            max_height_window_percentage = 50,
            window_overlap_clear_enabled = true,
        },
    },
    {
        "3rd/diagram.nvim",
        dependencies = { "3rd/image.nvim" },
        ft = { "markdown" },
        -- opts を関数にして遅延評価。直接テーブルに書くと lazy.nvim が spec を読む時点で
        -- diagram.* が rtp 未配置のため require できず落ちる。
        opts = function()
            return {
                integrations = {
                    require("diagram.integrations.markdown"),
                },
                renderer_options = {
                    mermaid = {
                        theme = "dark",
                        background = "transparent",
                        scale = 2,
                    },
                },
            }
        end,
    },
}
