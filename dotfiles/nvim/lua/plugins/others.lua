return {
  {
    "nvim-lualine/lualine.nvim",
    opts = {
      options = { theme = 'codedark' },
      sections = {
        lualine_c = {
          {
            'filename',
            path = 1, -- 0: 名前のみ, 1: 相対パス, 2: 絶対パス, 3: ホームディレクトリからのパス
          }
        }
      }
    }
  },
  {
    "kevinhwang91/nvim-bqf",
    opts = {},
  },
  {
    "mbbill/undotree",
    config = function()
      vim.api.nvim_set_keymap('n', '<leader>u', ':UndotreeToggle<CR>', { noremap = true, silent = true })
    end
  },
  {
    "kevinhwang91/nvim-hlslens",
    config = function()
      require('hlslens').setup()

      local kopts = { noremap = true, silent = true }

      vim.api.nvim_set_keymap('n', 'n',
        [[<Cmd>execute('normal! ' . v:count1 . 'n')<CR><Cmd>lua require('hlslens').start()<CR>]], kopts)
      vim.api.nvim_set_keymap('n', 'N',
        [[<Cmd>execute('normal! ' . v:count1 . 'N')<CR><Cmd>lua require('hlslens').start()<CR>]], kopts)
      vim.api.nvim_set_keymap('n', '*', [[*<Cmd>lua require('hlslens').start()<CR>]], kopts)
      vim.api.nvim_set_keymap('n', '#', [[#<Cmd>lua require('hlslens').start()<CR>]], kopts)
      vim.api.nvim_set_keymap('n', 'g*', [[g*<Cmd>lua require('hlslens').start()<CR>]], kopts)
      vim.api.nvim_set_keymap('n', 'g#', [[g#<Cmd>lua require('hlslens').start()<CR>]], kopts)

      -- init.luaでesc連打解除を設定してる
      -- vim.api.nvim_set_keymap('n', '<Leader>l', '<Cmd>noh<CR>', kopts)
    end
  },
  {
    'monaqa/dial.nvim',
    config = function()
      vim.keymap.set("n", "<C-a>", function() require("dial.map").manipulate("increment", "normal") end,
        { desc = "increment" })
      vim.keymap.set("n", "<C-x>", function() require("dial.map").manipulate("decrement", "normal") end,
        { desc = "decrement" })
      vim.keymap.set("n", "g<C-a>", function() require("dial.map").manipulate("increment", "gnormal") end,
        { desc = "gincrement" })
      vim.keymap.set("n", "g<C-x>", function() require("dial.map").manipulate("decrement", "gnormal") end,
        { desc = "gdecrement" })
      vim.keymap.set("v", "<C-a>", function() require("dial.map").manipulate("increment", "visual") end,
        { desc = "visual increment" })
      vim.keymap.set("v", "<C-x>", function() require("dial.map").manipulate("decrement", "visual") end,
        { desc = "visual decrement" })
      vim.keymap.set("v", "g<C-a>", function() require("dial.map").manipulate("increment", "gvisual") end,
        { desc = "visual gincrement" })
      vim.keymap.set("v", "g<C-x>", function() require("dial.map").manipulate("decrement", "gvisual") end,
        { desc = "visual gincrement" })

      local augend = require("dial.augend")
      local auconf = require("dial.config")

      local new_default = auconf.augends:get("default")
      table.insert(new_default, augend.constant.alias.bool)
      auconf.augends:register_group {
        default = new_default
      }
      vim.keymap.set("v", "g<C-x>", function() require("dial.map").manipulate("decrement", "gvisual") end)
    end,
  },
  --[[ {
    'akinsho/toggleterm.nvim',
    version = "*",
    opts = {}
  }, ]]
  {
    "kylechui/nvim-surround",
    version = "^3.0.0",
    -- event = "VeryLazy",
    opts = {
      keymaps = {
        insert = "<C-g>s",
        insert_line = "<C-g>S",
        normal = "<leader>sys",
        normal_cur = "<leader>syss",
        normal_line = "<leader>syS",
        normal_cur_line = "<leader>sySS",
        visual = "<leader>sS",
        visual_line = "<leader>sgS",
        delete = "<leader>sds",
        change = "<leader>scs",
        change_line = "<leader>scS",
      },
    }, -- ユーザーがここで keymaps や prefix を上書き可能
    --[[ config = function(_, opts)
      opts = opts or {}

      -- 1) 普通に setup を呼ぶ（失敗しても起動は続ける）
      local ok_setup, _ = pcall(require("nvim-surround").setup, opts)
      if not ok_setup then vim.notify("nvim-surround: setup failed (continuing)", vim.log.levels.WARN) end

      -- プレフィックス（opts.prefix を優先、なければ <leader>s）
      local prefix = opts.prefix
      if prefix == nil then
        prefix = "<leader>s"
      elseif prefix == false then
        -- false を渡すと機能を無効化できる
        return
      end

      local plug_map = {
        insert = "<Plug>(nvim-surround-insert)",
        insert_line = "<Plug>(nvim-surround-insert-line)",
        normal = "<Plug>(nvim-surround-normal)",
        normal_cur = "<Plug>(nvim-surround-normal-cur)",
        normal_line = "<Plug>(nvim-surround-normal-line)",
        normal_cur_line = "<Plug>(nvim-surround-normal-cur-line)",
        visual = "<Plug>(nvim-surround-visual)",
        visual_line = "<Plug>(nvim-surround-visual-line)",
        delete = "<Plug>(nvim-surround-delete)",
        change = "<Plug>(nvim-surround-change)",
        change_line = "<Plug>(nvim-surround-change-line)",
      }

      local mode_map = {
        insert = "i",
        insert_line = "i",
        normal = "n",
        normal_cur = "n",
        normal_line = "n",
        normal_cur_line = "n",
        visual = "x",
        visual_line = "x",
        delete = "n",
        change = "n",
        change_line = "n",
      }

      -- 2) まず opts.keymaps があればそれを使う（ソフト優先）
      local discovered_keymaps = nil
      if type(opts.keymaps) == "table" and next(opts.keymaps) ~= nil then
        discovered_keymaps = opts.keymaps
      else
        -- 3) 次にプラグインのモジュールからデフォルトを取れるか試す（柔軟に複数候補を探す）
        local tries = {
          "nvim-surround.config",
          "nvim-surround",
          "nvim-surround.config.default_opts",
        }
        for _, modname in ipairs(tries) do
          local ok, mod = pcall(require, modname)
          if ok and type(mod) == "table" then
            -- いくつかあり得る場所をチェック
            if type(mod.default_opts) == "table" and type(mod.default_opts.keymaps) == "table" then
              discovered_keymaps = mod.default_opts.keymaps
              break
            end
            if type(mod.opts) == "table" and type(mod.opts.keymaps) == "table" then
              discovered_keymaps = mod.opts.keymaps
              break
            end
            -- もしかすると module 自体が直接 default table を持っている場合
            if type(mod.default) == "table" and type(mod.default.keymaps) == "table" then
              discovered_keymaps = mod.default.keymaps
              break
            end
            -- あるいは module が get_opts を公開している場合（保険）
            if type(mod.get_opts) == "function" then
              local ok2, got = pcall(mod.get_opts)
              if ok2 and type(got) == "table" and type(got.keymaps) == "table" then
                discovered_keymaps = got.keymaps
                break
              end
            end
          end
        end
      end

      -- 4) まだ見つからなければ、現在登録されているキーを走査して <Plug> に繋がる lhs を発見する
      if not discovered_keymaps then
        discovered_keymaps = {}
        -- check modes that matter
        local modes_to_check = { "n", "x", "i" }
        for _, mode in ipairs(modes_to_check) do
          local maps = vim.api.nvim_get_keymap(mode)
          for _, m in ipairs(maps) do
            if type(m.rhs) == "string" then
              for name, plug in pairs(plug_map) do
                if m.rhs:find(plug, 1, true) then
                  -- 既に同じ name を見つけていないなら登録（最初に見つかった lhs を採用）
                  if discovered_keymaps[name] == nil then
                    discovered_keymaps[name] = m.lhs
                  end
                end
              end
            end
          end
        end
      end

      -- 5) discovered_keymaps が空なら何もしない（ハードコーディングしない方針）
      if not discovered_keymaps or next(discovered_keymaps) == nil then
        -- 何も見つからなければ安全に終了（必要ならここでフォールバックを追加可能）
        vim.notify("nvim-surround: no keymaps discovered to create prefixed mappings", vim.log.levels.DEBUG)
        return
      end

      -- 6) 発見した keymaps に対して prefix を付けて <Plug> に remap（衝突は上書きしない）
      for name, lhs in pairs(discovered_keymaps) do
        if type(lhs) == "string" and lhs ~= "" and plug_map[name] then
          local mode = mode_map[name] or "n"
          local new_lhs = tostring(prefix) .. lhs

          -- 衝突回避: 既に new_lhs にマップがあればスキップ
          local exists = false
          local existing = vim.api.nvim_get_keymap(mode)
          for _, m in ipairs(existing) do
            if m.lhs == new_lhs then
              exists = true
              break
            end
          end
          if not exists then
            pcall(vim.keymap.set, mode, new_lhs, plug_map[name], { remap = true, desc = "Surround: " .. name })
          end
        end
      end

      -- which-key があればプレフィックス領域を登録しておく（オプション）
      if pcall(require, "which-key") then
        local wk = require("which-key")
        pcall(wk.register, { [prefix] = { name = "Surround" } })
      end
    end, ]]
  },

  {
    'nmac427/guess-indent.nvim',
    opts = {}
  },
}
