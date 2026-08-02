-- Mermaid 等の図をバッファ内にインラインプレビューする。
-- 構成: diagram.nvim が mermaid ソースを抽出 → mmdc で PNG 化 →
--       image.nvim が WezTerm の Kitty graphics protocol 経由で表示。
--
-- 依存 (Nix 側で注入済み):
--   - mermaid-cli (mmdc):       modules/home-manager/dev/neovim/default.nix
--   - imagemagick (magick CLI): 同上
--   - magick luarock:           programs.neovim.extraLuaPackages

-- mmdc は 1 図あたり Chromium ヘッドレスを起動する重い処理 (≈3秒, 数百MB)。
-- diagram.nvim は同時実行数を制限せず、キャッシュミスした図の数だけ mmdc を
-- 一斉起動するため、複数図の .md ではメモリが枯渇しシステムがフリーズする
-- (8 図同時起動で Chromium 系 466 プロセス / ピーク RSS 数十 GB を実測)。
-- ここで mermaid renderer.render を上限付きキューでラップし、同時に走る mmdc を
-- MAX_CONCURRENT 個までに絞る。図は順次レンダリングされ、完了ごとに再描画される。
local MAX_CONCURRENT = 2

local function install_mermaid_throttle()
    -- プラグイン内部と同一のテーブルインスタンスを掴むため「スラッシュ記法」で require する。
    -- ドット記法 (require("diagram.renderers.mermaid")) だと package.loaded 上で別キー扱いに
    -- なりモジュールが二重ロードされ、patch した .render がプラグイン側に反映されない。
    local mermaid = require("diagram/renderers/mermaid")
    if mermaid._throttled then
        return
    end
    mermaid._throttled = true

    -- mermaid.lua と同一のキャッシュパス生成を再現する。
    local cache_dir = vim.fn.resolve(vim.fn.stdpath("cache") .. "/diagram-cache/mermaid")
    local orig_render = mermaid.render

    local active = 0
    local queue = {}
    local pending = {} -- path -> true。キュー投入済み or 実行中の図を記録し二重起動を防ぐ。
    local rerender_scheduled = false

    -- レンダリング完了後、キャッシュ済みの図を表示させるためバッファを再描画する。
    -- 完了が連続しても 1 回にまとめるよう debounce する。
    local function schedule_rerender()
        if rerender_scheduled then
            return
        end
        rerender_scheduled = true
        vim.defer_fn(function()
            rerender_scheduled = false
            pcall(function()
                require("diagram").render()
            end)
        end, 50)
    end

    local function poll_job(job_id, on_done)
        local timer = vim.uv.new_timer()
        if not timer then
            on_done()
            return
        end
        timer:start(
            0,
            100,
            vim.schedule_wrap(function()
                if vim.fn.jobwait({ job_id }, 0)[1] ~= -1 then
                    timer:stop()
                    if not timer:is_closing() then
                        timer:close()
                    end
                    on_done()
                end
            end)
        )
    end

    local pump
    pump = function()
        while active < MAX_CONCURRENT and #queue > 0 do
            local item = table.remove(queue, 1)
            if vim.fn.filereadable(item.path) == 1 then
                -- 待機中に別経路で生成済みになった
                pending[item.path] = nil
                schedule_rerender()
            else
                active = active + 1
                local res = orig_render(item.source, item.options)
                if res and res.job_id then
                    poll_job(res.job_id, function()
                        active = active - 1
                        pending[item.path] = nil
                        schedule_rerender()
                        pump()
                    end)
                else
                    -- mmdc 不在等で job が起動しなかった
                    active = active - 1
                    pending[item.path] = nil
                end
            end
        end
    end

    mermaid.render = function(source, options)
        local hash = vim.fn.sha256(mermaid.id .. ":" .. source)
        local path = vim.fn.resolve(cache_dir .. "/" .. hash .. ".png")
        -- キャッシュヒット: オリジナル同様に即座に file_path を返す (job なし)。
        if vim.fn.filereadable(path) == 1 then
            return { file_path = path }
        end
        -- キャッシュミス: job_id を返さずキューに積む。呼び出し側は file が未生成なので
        -- 今回は描画をスキップし、生成完了後の schedule_rerender でキャッシュヒット経由で表示される。
        if not pending[path] then
            pending[path] = true
            table.insert(queue, { source = source, options = options, path = path })
            pump()
        end
        return { file_path = path }
    end
end

return {
    {
        "3rd/image.nvim",
        dependencies = { "nvim-treesitter/nvim-treesitter" },
        -- only_render_image_at_cursor: 同時に転送する画像を 1 枚に絞る。全画像を描画すると
        -- ペイン分割等のリサイズ時に全枚数が一括再送され、WezTerm の GUI スレッドが
        -- CPU 100% + メモリ増加のまま無限ループに入る (wezterm#7400, 未修正)。
        -- mode は既定の "popup" だとフロート窓表示になるため "inline" を明示する。
        -- typst 統合は image.nvim 側で既定有効なので、markdown と同じ設定を明示的に入れる。
        opts = {
            backend = "kitty", -- WezTerm は Kitty graphics protocol 互換
            processor = "magick_cli",
            integrations = {
                markdown = {
                    enabled = true,
                    only_render_image_at_cursor = true,
                    only_render_image_at_cursor_mode = "inline",
                    filetypes = { "markdown", "vimwiki" },
                },
                typst = {
                    enabled = true,
                    only_render_image_at_cursor = true,
                    only_render_image_at_cursor_mode = "inline",
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
                -- 再描画トリガから TextChanged を外す。デフォルトは打鍵ごとに発火し、
                -- キャッシュミスの図の数だけ mmdc (Chromium ヘッドレス, 1図≈3秒) を
                -- 同時実行数の制限なく一斉起動するため、複数図の .md でシステムが
                -- swap スラッシングを起こしフリーズする。手が止まった時 (InsertLeave)、
                -- 保存時 (BufWritePost)、ウィンドウ表示時 (BufWinEnter) のみ再描画する。
                events = {
                    render_buffer = { "InsertLeave", "BufWinEnter", "BufWritePost" },
                },
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
        -- setup 前に mermaid renderer をラップして同時起動数を絞る。
        config = function(_, opts)
            install_mermaid_throttle()
            require("diagram").setup(opts)
        end,
    },
}
