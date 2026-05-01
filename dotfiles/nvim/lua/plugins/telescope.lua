-- skkeletonがinsertenterで読み込まれることを前提に書いてる
return {
    {
        "nvim-telescope/telescope.nvim",
        dependencies = {
            "nvim-lua/plenary.nvim",
            'nvim-telescope/telescope-media-files.nvim',
            "nvim-telescope/telescope-file-browser.nvim",
            "BurntSushi/ripgrep",
            "ahmedkhalf/project.nvim", -- どこにいてもgitのrootにcdしてくれるplugin
        },
        config = function()
            -- Telescopeの基本設定
            require("telescope").setup {
                extensions = {
                    file_browser = {
                        theme = "dropdown",
                        hijack_netrw = true,
                        mappings = {
                            ["i"] = {
                                ["<C-j>"] = { "<Plug>(skkeleton-enable)", type = "command" },
                                ["<C-f>"] = { "<Esc>", type = "command" },
                            },
                            ["n"] = {},
                        },
                    },
                },
            }

            -- 拡張機能の読み込み
            require("telescope").load_extension "file_browser"

            -- キーマッピングの設定
            vim.keymap.set("n", "<leader>t", ":Telescope<CR>")
            vim.keymap.set("n", "<leader>f", ":Telescope file_browser path=%:p:h select_buffer=true<CR>")
        end
    },

    -- LSP入れてtinymist使わないとtypstのpdf変換できません
    {
        'nvim-telekasten/telekasten.nvim',
        cmd = {"Telekasten"},
        dependencies = { "nvim-telescope/telescope.nvim" },
        config = function()
            -- ディレクトリ探索関数
            local function list_directories(path)
                local directories = {}
                local fs_scandir = vim.loop.fs_scandir(path)
                if not fs_scandir then
                    vim.notify("Failed to scan directory: " .. path, vim.log.levels.ERROR)
                    return directories
                end

                while true do
                    local name, type = vim.loop.fs_scandir_next(fs_scandir)
                    if not name then break end
                    if type == "directory" then
                        table.insert(directories, name)
                    end
                end

                -- 不要なディレクトリをフィルタリング
                return vim.tbl_filter(function(dir)
                    return not (dir:match("^%.") or dir == "Templates" or dir == "Dailies")
                end, directories)
            end

            -- ディレクトリ作成関数
            local function create_directory(path)
                if not vim.loop.fs_stat(path) then
                    local success, err = vim.loop.fs_mkdir(path, 493)
                    if not success then
                        vim.notify("Error creating directory " .. path .. ": " .. tostring(err), vim.log.levels.ERROR)
                    end
                end
            end

            -- シンボリックリンク作成関数
            local function create_symlink(source, target)
                if vim.loop.fs_stat(target) then
                    -- 既存のリンクを削除
                    vim.loop.fs_unlink(target)
                end
                local success, err = vim.loop.fs_symlink(source, target)
                if not success then
                    vim.notify("Error creating symlink " .. target .. ": " .. tostring(err), vim.log.levels.ERROR)
                end
            end

            -- math_with_typ配下のすべてのディレクトリにautotheorem.typをリンク
            local function link_autotheorem_to_all_dirs()
                local math_with_typ_root = vim.fn.expand('~/sagyo/vaults/math_with_typ')
                local autotheorem_source = vim.fn.expand('~/sagyo/vaults/Templates/autotheorem.typ')

                -- ソースファイルの存在確認
                if not vim.loop.fs_stat(autotheorem_source) then
                    vim.notify("Source file not found: " .. autotheorem_source, vim.log.levels.ERROR)
                    return
                end

                -- すべてのサブディレクトリを取得
                local function get_all_subdirs(path)
                    local subdirs = {}
                    local function scan_dir(current_path)
                        local fs_scandir = vim.loop.fs_scandir(current_path)
                        if not fs_scandir then return end

                        while true do
                            local name, type = vim.loop.fs_scandir_next(fs_scandir)
                            if not name then break end

                            if type == "directory" and not name:match("^%.") then
                                local full_path = current_path .. '/' .. name
                                table.insert(subdirs, full_path)
                                scan_dir(full_path) -- 再帰的にサブディレクトリを探索
                            end
                        end
                    end
                    scan_dir(path)
                    return subdirs
                end

                -- 各ディレクトリにリンクを作成
                local subdirs = get_all_subdirs(math_with_typ_root)
                for _, dir in ipairs(subdirs) do
                    local target = dir .. '/autotheorem.typ'
                    create_symlink(autotheorem_source, target)
                end
            end

            -- IndexNote作成関数
            local function create_index_note(vault_path)
                local index_path = vault_path .. '/IndexNote.md'
                if not vim.loop.fs_stat(index_path) then
                    local content = [[
# IndexNote

]]
                    local file = io.open(index_path, "w")
                    if file then
                        file:write(content)
                        file:close()
                    else
                        vim.notify("Error creating IndexNote: " .. index_path, vim.log.levels.ERROR)
                    end
                end
            end

            -- 基本設定
            local vaults_root = vim.fn.expand('~/sagyo/vaults/')
            local some_vaults = list_directories(vaults_root)

            -- IndexNoteを作成する(ないなら)
            create_index_note(vaults_root)

            -- 手動で追加してるvaults
            local my_vaults = {
                math_with_typ = {
                    home = vim.fn.expand('~/sagyo/vaults/math_with_typ'),
                },
                LiteratureNotes = {
                    home = vim.fn.expand('~/sagyo/vaults/LiteratureNotes'),
                },
                PermanentNotes = {
                    home = vim.fn.expand('~/sagyo/vaults/PermanentNotes'),
                },
                StructureNotes = {
                    home = vim.fn.expand('~/sagyo/vaults/StructureNotes'),
                },
            }

            -- 自動検出されたvaultsを追加
            for _, value in ipairs(some_vaults) do
                my_vaults[value] = {
                    home = vaults_root .. value,
                }
            end

            -- ディレクトリ作成(ないなら)
            create_directory(vaults_root .. '/Templates')
            create_directory(vaults_root .. '/Dailies')
            for _, value in pairs(my_vaults) do
                create_directory(value.home)
            end

            -- autotheorem.typのリンクを作成
            link_autotheorem_to_all_dirs()

            -- telekastenの設定
            require('telekasten').setup({
                home = my_vaults.math_with_typ.home,
                vaults = my_vaults,
                dailies = vim.fn.expand('~/sagyo/vaults/Dailies'),
                template_new_note = vim.fn.expand('~/sagyo/vaults/Templates/template_new_note.typ'),
                template_new_daily = vim.fn.expand('~/sagyo/vaults/Templates/TemplateDailyNote.md'),
                media_previewer = "telescope-media-files",
                media_extensions = {
                    ".png", ".jpg", ".bmp", ".gif",
                    ".pdf", ".mp4", ".webm", ".webp",
                },
                image_subdir = "img",
                extension = ".md",
            })
        end
    }
}
