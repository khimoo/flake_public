return {
  {
    "j-hui/fidget.nvim",
    opts = {},
  },
  "mfussenegger/nvim-dap",
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "saghen/blink.cmp",
    },
    config = function()
      -- blink.cmp の capabilities を取得
      local blink_capabilities = require('blink.cmp').get_lsp_capabilities()

      -- LSP キーマップ用プレフィックス（<leader>l に統一）
      local prefix = "<leader>l"

      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(ev)
          local bufnr = ev.buf
          local set = vim.keymap.set

          -- bufローカルマップ作成用ヘルパー
          local function nmap(suffix, func, desc)
            local lhs = prefix .. suffix
            local opts = { buffer = bufnr }
            if desc then opts.desc = "LSP: " .. desc end
            set("n", lhs, func, opts)
          end

          local function vmap(suffix, func, desc)
            local lhs = prefix .. suffix
            local opts = { buffer = bufnr }
            if desc then opts.desc = "LSP: " .. desc end
            set("v", lhs, func, opts)
          end

          -- ▼ LSP 関連キーマップ定義
          nmap("gD", vim.lsp.buf.declaration, "Go to declaration")
          nmap("gd", vim.lsp.buf.definition, "Go to definition")
          nmap("gi", vim.lsp.buf.implementation, "Go to implementation")
          nmap("gr", vim.lsp.buf.references, "List references")
          nmap("K", vim.lsp.buf.hover, "Hover documentation")
          nmap("<C-f>", vim.lsp.buf.signature_help, "Signature help")

          nmap("wa", vim.lsp.buf.add_workspace_folder, "Add workspace folder")
          nmap("wr", vim.lsp.buf.remove_workspace_folder, "Remove workspace folder")
          nmap("wl", function() print(vim.inspect(vim.lsp.buf.list_workspace_folders())) end, "List workspace folders")

          nmap("D", vim.lsp.buf.type_definition, "Go to type definition")
          nmap("rn", vim.lsp.buf.rename, "Rename symbol")
          nmap("ca", vim.lsp.buf.code_action, "Code action")
          nmap("F", function() vim.lsp.buf.format({ bufnr = bufnr, async = true }) end, "Format buffer")

          vmap("ca", vim.lsp.buf.range_code_action or vim.lsp.buf.code_action, "Range code action")

          nmap("[d", vim.diagnostic.goto_prev, "Previous diagnostic")
          nmap("]d", vim.diagnostic.goto_next, "Next diagnostic")
          nmap("dl", vim.diagnostic.open_float, "Open diagnostic float")
          nmap("q", vim.diagnostic.setloclist, "Diagnostics to loclist")

          -- which-key 登録
          if pcall(require, "which-key") then
            local wk = require("which-key")
            pcall(wk.register, {
              [prefix] = {
                name = "LSP",
                g = { name = "Goto" },
                w = { name = "Workspace" },
                d = { "Diagnostics" },
                r = { name = "Rename/References" },
                c = { name = "Code Action" },
                F = { "Format buffer" },
              },
            }, { buffer = bufnr })
          end
        end,
      })

      -- Diagnostics 設定
      vim.lsp.handlers["textDocument/publishDiagnostics"] = vim.lsp.with(
        vim.lsp.diagnostic.on_publish_diagnostics,
        {
          underline = true,
          virtual_text = false,
          signs = true,
          severity_sort = true,
          update_in_insert = true,
        }
      )
      vim.o.updatetime = 250
      vim.cmd [[autocmd CursorHold * lua vim.diagnostic.open_float(nil, {focus=false})]]

      -- ここからlsp設定
      -- util: list files under a directory (non-recursive). If you want recursive, see note below.
      local function list_rs_files(dir)
        local uv = vim.loop
        local rs = {}

        if not dir or dir == "" then return rs end

        local stat = uv.fs_stat(dir)
        if not stat or stat.type ~= "directory" then return rs end

        local p = uv.fs_scandir(dir)
        if not p then return rs end

        while true do
          local name, t = uv.fs_scandir_next(p)
          if not name then break end
          if t == "file" or t == "link" then
            if name:match("%.rs$") then
              table.insert(rs, dir .. "/" .. name)
            end
          elseif t == "directory" then
            -- If you want recursive discovery, you can either call list_rs_files(dir .. "/" .. name)
            -- and merge results, or implement a queue for BFS. For now we do non-recursive.
          end
        end

        return rs
      end

      -- read env and split by comma for NEOVIM_LSP_SERVERS (existing code)
      local lsp_servers_env = tostring(os.getenv("NEOVIM_LSP_SERVERS") or "")
      local servers = {}
      if lsp_servers_env ~= "" then
        for server in string.gmatch(lsp_servers_env, "([^,]+)") do
          table.insert(servers, server)
        end
      end

      -- Build linkedProjects for rust_analyzer from SCRIPTS_RS (colon-separated)
      local function split_str(s, sep)
        local res = {}
        if s == nil or s == "" then return res end
        sep = sep or "%s"
        for part in string.gmatch(s, "([^" .. sep .. "]+)") do
          table.insert(res, part)
        end
        return res
      end

      -- set up servers from NEOVIM_LSP_SERVERS
      for _, server in ipairs(servers) do
        vim.lsp.config(server, {
          capabilities = blink_capabilities,
        })
      end

      -- explicit configs
      vim.lsp.config("tinymist", {
        capabilities = blink_capabilities,
        settings = {
          exportPdf = "onType",
          outputPath = "/tmp/tinymist",
        },
      })

      vim.lsp.config("nil_ls", {
        capabilities = blink_capabilities,
        settings = {
          ['nil'] = { formatting = { command = { "nixfmt" } } }
        },
      })

      -- rust_analyzer: use linkedProjects from environment
      -- Build linkedProjects by listing .rs files under SCRIPTS_RS directory
      local scripts_dir = tostring(os.getenv("SCRIPTS_RS") or "")
      local linked_projects = list_rs_files(scripts_dir)

      vim.lsp.config("rust_analyzer", {
        capabilities = blink_capabilities,
        settings = { ['rust-analyzer'] = {
          linkedProjects = linked_projects,
        } },
      })

      for _, server in ipairs(servers) do
        vim.lsp.enable(server)
      end
    end,
  }
}
