return {
  {
    'mrcjkb/rustaceanvim',
    version = '^5',
    lazy = false,
    dependencies = { "mfussenegger/nvim-dap" },
    init = function()
      local codelldb_path = tostring(os.getenv("CODELLDB_PATH") or "codelldb")
      local liblldb_path = vim.fn.fnamemodify(codelldb_path, ':h:h') .. '/lldb/lib/liblldb.so'

      vim.g.rustaceanvim = {
        dap = {
          adapter = require('rustaceanvim.config').get_codelldb_adapter(codelldb_path, liblldb_path),
        },
      }
    end,
  },
  {
    'cordx56/rustowl',
    version = '*',
    ft = 'rust',
    opts = {
      auto_attach = true,
      auto_enable = false,
      idle_time = 500,
    },
    keys = {
      { '<leader>lo', '<cmd>Rustowl toggle<cr>', desc = 'RustOwl toggle' },
    },
    config = function(_, opts)
      require('rustowl').setup(opts)
      require('plugins.lang.rustowl-hover').setup()
    end,
  },
}
